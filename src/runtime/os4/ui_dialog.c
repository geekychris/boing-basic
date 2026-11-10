/* The CommonDialog (docs/ui.md section 3): asl file (open/save, multi-select, patterns), font
 * and screen mode requesters, a colour requester (a small form of its own) and a message
 * requester with the program's own buttons. A `commondialog` in the .afg is a bb_ctl of its
 * form; CreateObject("Boing.CommonDialog") makes one without a form (bb_dialog_new). */
#include "forms_int.h"
#include <proto/asl.h>
#include <libraries/asl.h>
#include <workbench/startup.h>
#include <graphics/text.h>
#include "../canvas.h"

static struct Library *AslLib;
static struct AslIFace *IAs;

typedef struct dlg {
    char *title, *filename, *filetitle, *initdir, *filter;
    int32 flags;
    int cancelerror, cancelled;
    char **files;
    int nfiles;
    char *fontname;
    int32 fontsize, bold, italic, underline;
    int32 color;
    uint32 modeid;
    int32 sw, sh, sd;
    int32 colors[256];
    int32 ncolors;
    int32 colorindex;      /* ShowPalette: the colour picked (and the one it starts on) */
} dlg;

enum {
    cdlOFNOverwritePrompt = 0x2, cdlOFNAllowMultiselect = 0x200, cdlOFNPathMustExist = 0x800,
    cdlOFNFileMustExist = 0x1000, cdlCancel = 32755
};

static dlg *D(bb_ctl *c)
{
    if (!c->ext) {
        dlg *d = calloc(1, sizeof *d);
        d->fontsize = 13;
        d->fontname = xstrdup("DejaVu Sans");
        d->ncolors = 16;
        for (int i = 0; i < 16; i++) d->colors[i] = (i & 1 ? 0xAA : 0) | (i & 2 ? 0xAA00 : 0) | (i & 4 ? 0xAA0000 : 0) | (i & 8 ? 0x555555 : 0);
        if (c->node) {
            if (afg_has(c->node, "title")) d->title = xstrdup(afg_get(c->node, "title"));
            if (afg_has(c->node, "filter")) d->filter = xstrdup(afg_get(c->node, "filter"));
            if (afg_has(c->node, "initdir")) d->initdir = xstrdup(afg_get(c->node, "initdir"));
            d->flags = afg_get_int(c->node, "flags");
        }
        c->ext = d;
    }
    return c->ext;
}

static void set_str(char **p, const char *s)
{
    free(*p);
    *p = s ? xstrdup(s) : NULL;
}

static void clear_files(dlg *d)
{
    for (int i = 0; i < d->nfiles; i++) free(d->files[i]);
    free(d->files);
    d->files = NULL;
    d->nfiles = 0;
}

void bbf_dialog_free(bb_ctl *c)
{
    dlg *d = c->ext;
    if (!d) return;
    clear_files(d);
    free(d->title);
    free(d->filename);
    free(d->filetitle);
    free(d->initdir);
    free(d->filter);
    free(d->fontname);
    free(d);
    c->ext = NULL;
}

void bbf_dialog_cleanup(void)
{
    if (IAs) IExec->DropInterface((struct Interface *)IAs);
    if (AslLib) IExec->CloseLibrary(AslLib);
    IAs = NULL;
    AslLib = NULL;
}

static struct AslIFace *asl(void)
{
    if (!IAs) {
        AslLib = IExec->OpenLibrary("asl.library", 50);
        if (AslLib) IAs = (void *)IExec->GetInterface(AslLib, "main", 1, NULL);
    }
    return IAs;
}

/* every open form gets a busy pointer and no input while a requester is open */
static void sleep_all(int on)
{
    for (bb_form *f = forms; f; f = f->next)
        if (f->win) IIntuition->SetAttrs(f->winobj, WA_BusyPointer, on ? TRUE : !f->enabled, TAG_DONE);
}

static struct Window *parent_win(bb_ctl *c)
{
    if (c->form && c->form->win) return c->form->win;
    return bbf_front_window();
}

/* "Pictures|#?.png" (VB style, the description is ignored) or "#?.png" -> the AmigaDOS pattern;
   VB's "*.txt;*.bas" become "#?.(txt|bas)" */
static char *amiga_pattern(const char *f)
{
    if (!f || !*f) return NULL;
    const char *bar = strrchr(f, '|');
    if (bar) f = bar + 1;
    if (!strchr(f, '*')) return xstrdup(f);
    char *o = malloc(strlen(f) * 3 + 8), *d = o;
    int alts = strchr(f, ';') != NULL;
    if (alts) *d++ = '(';
    for (const char *p = f; *p; p++) {
        if (*p == '*') { *d++ = '#'; *d++ = '?'; }
        else if (*p == ';') *d++ = '|';
        else *d++ = *p;
    }
    if (alts) *d++ = ')';
    *d = 0;
    return o;
}

static char *join_path(const char *dir, const char *file)
{
    size_t n = strlen(dir) + strlen(file) + 4;
    char *o = malloc(n);
    strcpy(o, dir);
    IDOS->AddPart(o, file, n);
    return o;
}

static int file_exists(const char *path)
{
    BPTR l = IDOS->Lock(path, SHARED_LOCK);
    if (l) IDOS->UnLock(l);
    return l != 0;
}

static int show_file(bb_ctl *c, int save)
{
    dlg *d = D(c);
    if (!asl()) return 7;
    char *pat = amiga_pattern(d->filter);
    /* InitialDrawer/File from FileName when it has a directory */
    char *idir = d->initdir ? xstrdup(d->initdir) : NULL, *ifile = NULL;
    if (d->filename && *d->filename) {
        const char *fp = (const char *)IDOS->FilePart(d->filename);
        ifile = xstrdup(fp);
        if (!idir && fp != d->filename) {
            idir = xstrdup(d->filename);
            *(char *)IDOS->PathPart(idir) = 0;
        }
    }
    struct FileRequester *fr = IAs->AllocAslRequestTags(ASL_FileRequest, TAG_DONE);
    if (!fr) {
        free(pat); free(idir); free(ifile);
        return 7;
    }
    struct Window *w = parent_win(c);
    int multi = !save && (d->flags & cdlOFNAllowMultiselect);
    int ok;
    sleep_all(1);
    for (;;) {
        ok = IAs->AslRequestTags(fr, ASLFR_TitleText, (uint32)(d->title ? d->title : save ? "Save" : "Open"),
                                 w ? ASLFR_Window : TAG_IGNORE, (uint32)w,
                                 ASLFR_SleepWindow, w != NULL,
                                 ASLFR_DoSaveMode, save,
                                 ASLFR_DoMultiSelect, multi,
                                 ASLFR_RejectIcons, TRUE,
                                 pat ? ASLFR_InitialPattern : TAG_IGNORE, (uint32)pat,
                                 ASLFR_DoPatterns, pat != NULL,
                                 idir ? ASLFR_InitialDrawer : TAG_IGNORE, (uint32)idir,
                                 ifile ? ASLFR_InitialFile : TAG_IGNORE, (uint32)ifile,
                                 TAG_DONE);
        if (!ok || !save || !(d->flags & cdlOFNOverwritePrompt)) break;
        char *full = join_path(fr->fr_Drawer ? (char *)fr->fr_Drawer : "", fr->fr_File ? (char *)fr->fr_File : "");
        int exists = fr->fr_File && *fr->fr_File && file_exists(full);
        free(full);
        if (!exists) break;
        char msg[300];
        snprintf(msg, sizeof msg, "%s already exists.\nDo you want to replace it?", (char *)fr->fr_File);
        if (bb_ui_msgbox(msg, 4 + 48, d->title) == 6) break;      /* vbYes */
        free(ifile);
        ifile = xstrdup((char *)fr->fr_File);
        free(idir);
        idir = xstrdup(fr->fr_Drawer ? (char *)fr->fr_Drawer : "");
    }
    sleep_all(0);
    d->cancelled = !ok;
    if (ok) {
        clear_files(d);
        const char *dir = fr->fr_Drawer ? (const char *)fr->fr_Drawer : "";
        if (multi && fr->fr_NumArgs > 0) {
            d->files = calloc(fr->fr_NumArgs, sizeof *d->files);
            for (int i = 0; i < fr->fr_NumArgs; i++) d->files[d->nfiles++] = join_path(dir, (const char *)fr->fr_ArgList[i].wa_Name);
        } else if (fr->fr_File && *fr->fr_File) {
            d->files = calloc(1, sizeof *d->files);
            d->files[d->nfiles++] = join_path(dir, (const char *)fr->fr_File);
        }
        set_str(&d->filename, d->nfiles ? d->files[0] : dir);
        set_str(&d->filetitle, d->nfiles ? (const char *)IDOS->FilePart(d->files[0]) : "");
        if (!(d->flags & 0x8)) set_str(&d->initdir, dir);         /* cdlOFNNoChangeDir */
        if (!save && (d->flags & cdlOFNFileMustExist))
            for (int i = 0; i < d->nfiles; i++)
                if (!file_exists(d->files[i])) {
                    d->cancelled = 1;
                    ok = 0;
                }
    }
    IAs->FreeAslRequest(fr);
    free(pat);
    free(idir);
    free(ifile);
    if (!ok && d->cancelerror) return cdlCancel;
    return 0;
}

static int show_font(bb_ctl *c)
{
    dlg *d = D(c);
    if (!asl()) return 7;
    char init[128];
    snprintf(init, sizeof init, "%s.font", d->fontname ? d->fontname : "DejaVu Sans");
    struct FontRequester *fo = IAs->AllocAslRequestTags(ASL_FontRequest, TAG_DONE);
    if (!fo) return 7;
    struct Window *w = parent_win(c);
    uint32 style = (d->bold ? FSF_BOLD : 0) | (d->italic ? FSF_ITALIC : 0) | (d->underline ? FSF_UNDERLINED : 0);
    sleep_all(1);
    int ok = IAs->AslRequestTags(fo, ASLFO_TitleText, (uint32)(d->title ? d->title : "Font"),
                                 w ? ASLFO_Window : TAG_IGNORE, (uint32)w, ASLFO_SleepWindow, w != NULL,
                                 ASLFO_InitialName, (uint32)init, ASLFO_InitialSize, d->fontsize,
                                 ASLFO_InitialStyle, style, ASLFO_DoStyle, TRUE, TAG_DONE);
    sleep_all(0);
    d->cancelled = !ok;
    if (ok) {
        char name[128];
        snprintf(name, sizeof name, "%s", (char *)fo->fo_Attr.ta_Name);
        char *dot = strrchr(name, '.');
        if (dot && !strcasecmp(dot, ".font")) *dot = 0;
        set_str(&d->fontname, name);
        d->fontsize = fo->fo_Attr.ta_YSize;
        d->bold = (fo->fo_Attr.ta_Style & FSF_BOLD) != 0;
        d->italic = (fo->fo_Attr.ta_Style & FSF_ITALIC) != 0;
        d->underline = (fo->fo_Attr.ta_Style & FSF_UNDERLINED) != 0;
    }
    IAs->FreeAslRequest(fo);
    return !ok && d->cancelerror ? cdlCancel : 0;
}

static int show_screenmode(bb_ctl *c)
{
    dlg *d = D(c);
    if (!asl()) return 7;
    struct ScreenModeRequester *sm = IAs->AllocAslRequestTags(ASL_ScreenModeRequest, TAG_DONE);
    if (!sm) return 7;
    struct Window *w = parent_win(c);
    sleep_all(1);
    int ok = IAs->AslRequestTags(sm, ASLSM_TitleText, (uint32)(d->title ? d->title : "Screen mode"),
                                 w ? ASLSM_Window : TAG_IGNORE, (uint32)w, ASLSM_SleepWindow, w != NULL,
                                 d->modeid ? ASLSM_InitialDisplayID : TAG_IGNORE, d->modeid,
                                 ASLSM_DoWidth, TRUE, ASLSM_DoHeight, TRUE, ASLSM_DoDepth, TRUE, TAG_DONE);
    sleep_all(0);
    d->cancelled = !ok;
    if (ok) {
        d->modeid = sm->sm_DisplayID;
        d->sw = sm->sm_DisplayWidth;
        d->sh = sm->sm_DisplayHeight;
        d->sd = sm->sm_DisplayDepth;
    }
    IAs->FreeAslRequest(sm);
    return !ok && d->cancelerror ? cdlCancel : 0;
}

/* a picture in one of the requesters' canvas controls, kept in a Canvas object so the forms
   layer shows it again whenever the layout repaints the control's box */
static void dlg_picture(bb_obj **cv, bb_ctl *ctl, const uint32_t *px, int32 w, int32 h)
{
    if (!ctl) return;
    if (!*cv) *cv = bb_canvas_new(w, h, ctl);
    bb_canvas_put_picture(*cv, px, w, h);
    bb_canvas_ctl_refresh(ctl);
}

/* --- the colour requester: a form of its own, modal like InputBox -------------------------- */

struct cbox {
    int done, ok;
    int32 rgb;           /* VB colour 0x00BBGGRR */
    bb_form *f;
    bb_obj *canvas;
};

static void cbox_show(struct cbox *b)
{
    bb_fval v;
    int r = 0, g = 0, bl = 0;
    if (!bb_ctl_get(bb_form_ctl(b->f, "r"), "Value", -1, &v)) r = v.i;
    if (!bb_ctl_get(bb_form_ctl(b->f, "g"), "Value", -1, &v)) g = v.i;
    if (!bb_ctl_get(bb_form_ctl(b->f, "b"), "Value", -1, &v)) bl = v.i;
    b->rgb = r | g << 8 | bl << 16;
    static uint32_t px[64 * 24];
    for (int i = 0; i < 64 * 24; i++) px[i] = 0xFF000000u | (uint32_t)r << 16 | (uint32_t)g << 8 | (uint32_t)bl;
    dlg_picture(&b->canvas, bb_form_ctl(b->f, "swatch"), px, 64, 24);
    char hex[16];
    snprintf(hex, sizeof hex, "#%02X%02X%02X", r, g, bl);
    bb_fval s = { BB_FV_STR, 0, hex };
    bb_ctl_set(bb_form_ctl(b->f, "hex"), "Caption", -1, &s);
}

static int cbox_event(void *ud, bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
{
    struct cbox *b = ud;
    (void)argc;
    b->f = f;
    if (!strcmp(event, "Click") && !strcmp(ctl, "ok")) b->done = b->ok = 1;
    else if (!strcmp(event, "Click") && !strcmp(ctl, "cancel")) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "Unload")) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "KeyDown") && args[0] == 27) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "KeyDown") && args[0] == 13) b->done = b->ok = 1;
    else if (!strcmp(event, "Scroll") || !strcmp(event, "Change") || (!strcmp(ctl, "Form") && !strcmp(event, "Resize")))
        cbox_show(b);
    return 0;
}

static int show_color(bb_ctl *c)
{
    dlg *d = D(c);
    char afg[1200];
    int32 col = d->color;
    snprintf(afg, sizeof afg,
             "window name=_color title=\"%s\" width=300 resizable=0\n"
             "vlayout id=root\n"
             "  hlayout\n"
             "    vlayout\n"
             "      slider id=r label=\"_Red\" min=0 max=255 level=%ld\n"
             "      slider id=g label=\"_Green\" min=0 max=255 level=%ld\n"
             "      slider id=b label=\"_Blue\" min=0 max=255 level=%ld\n"
             "    vlayout weight=0\n"
             "      canvas id=swatch width=64 height=24\n"
             "      label id=hex text=\"#000000\"\n"
             "  hlayout weight=0 even=1\n    button id=ok text=_OK default=1\n    space\n    button id=cancel text=_Cancel cancel=1\n",
             d->title ? d->title : "Colour", (long)(col & 255), (long)((col >> 8) & 255), (long)((col >> 16) & 255));
    struct cbox box = { 0 };
    char err[200];
    bb_form *f = bb_form_load(afg, "ColorDialog", cbox_event, NULL, &box, err, sizeof err);
    if (!f) return 7;
    box.f = f;
    sleep_all(1);
    if (bb_form_show(f) == 0) {
        cbox_show(&box);
        uint32 sig = 0;
        IIntuition->GetAttr(WINDOW_SigMask, f->winobj, &sig);
        int was_ending = ending;
        while (!box.done && f->loaded && f->win && !ending) {
            uint32 got = IExec->Wait(sig | SIGBREAKF_CTRL_C);
            if (got & SIGBREAKF_CTRL_C) {
                /* the requester goes; the break stays set for the program's own loop (it ends) */
                IExec->SetSignal(SIGBREAKF_CTRL_C, SIGBREAKF_CTRL_C);
                break;
            }
            bbf_handle_form(f);
        }
        ending = was_ending;
    }
    bbf_form_discard(f);
    bb_obj_release(box.canvas);
    sleep_all(0);
    d->cancelled = !box.ok;
    if (box.ok) d->color = box.rgb;
    return !box.ok && d->cancelerror ? cdlCancel : 0;
}

/* --- ShowPalette: Colors(0 .. ColorCount-1) as swatches (16 a row); a click or the "Colour"
   slider picks one, the RGB sliders change it ------------------------------------------- */

#define PCELL 20

struct pbox {
    int done, ok, sel, n, loading;
    int32 cols[256];
    bb_form *f;
    bb_obj *canvas;
};

static void pbox_draw(struct pbox *b)
{
    int rows = (b->n + 15) / 16, w = 16 * PCELL, h = rows * PCELL;
    static uint32_t px[16 * PCELL * 16 * PCELL];
    for (int i = 0; i < w * h; i++) px[i] = 0xFF888888u;
    for (int i = 0; i < b->n; i++) {
        int x0 = (i % 16) * PCELL, y0 = (i / 16) * PCELL;
        int32 c = b->cols[i];
        uint32_t argb = 0xFF000000u | (uint32_t)(c & 255) << 16 | (uint32_t)(c & 0xFF00) | (uint32_t)((c >> 16) & 255);
        for (int y = 0; y < PCELL; y++)
            for (int x = 0; x < PCELL; x++) {
                int edge = x == 0 || y == 0 || x == PCELL - 1 || y == PCELL - 1;
                int ring = x < 3 || y < 3 || x >= PCELL - 3 || y >= PCELL - 3;
                uint32_t v = argb;
                if (i == b->sel && ring) v = edge || x == 2 || y == 2 || x == PCELL - 3 || y == PCELL - 3 ? 0xFF000000u : 0xFFFFFFFFu;
                else if (edge) v = 0xFF333333u;
                px[(y0 + y) * w + x0 + x] = v;
            }
    }
    dlg_picture(&b->canvas, bb_form_ctl(b->f, "pal"), px, w, h);
    char hex[24];
    int32 c = b->cols[b->sel];
    snprintf(hex, sizeof hex, "%ld: #%02lX%02lX%02lX", (long)b->sel, (long)(c & 255), (long)((c >> 8) & 255), (long)((c >> 16) & 255));
    bb_fval s = { BB_FV_STR, 0, hex };
    bb_ctl_set(bb_form_ctl(b->f, "hex"), "Caption", -1, &s);
}

/* the sliders show colour sel */
static void pbox_select(struct pbox *b, int sel)
{
    if (sel < 0 || sel >= b->n) return;
    b->sel = sel;
    b->loading = 1;
    int32 c = b->cols[sel];
    bb_fval v = { BB_FV_INT, 0, NULL };
    v.i = sel;
    bb_ctl_set(bb_form_ctl(b->f, "idx"), "Value", -1, &v);
    v.i = c & 255;
    bb_ctl_set(bb_form_ctl(b->f, "r"), "Value", -1, &v);
    v.i = (c >> 8) & 255;
    bb_ctl_set(bb_form_ctl(b->f, "g"), "Value", -1, &v);
    v.i = (c >> 16) & 255;
    bb_ctl_set(bb_form_ctl(b->f, "b"), "Value", -1, &v);
    b->loading = 0;
    pbox_draw(b);
}

static int pbox_event(void *ud, bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
{
    struct pbox *b = ud;
    b->f = f;
    if (!strcmp(event, "Click") && !strcmp(ctl, "ok")) b->done = b->ok = 1;
    else if (!strcmp(event, "Click") && !strcmp(ctl, "cancel")) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "Unload")) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "KeyDown") && argc > 0 && args[0] == 27) b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "KeyDown") && argc > 0 && args[0] == 13) b->done = b->ok = 1;
    else if (!strcmp(ctl, "pal") && !strcmp(event, "MouseDown") && argc >= 4 && args[2] >= 0 && args[3] >= 0) {
        int i = (args[3] / PCELL) * 16 + args[2] / PCELL;
        if (args[2] < 16 * PCELL && i < b->n) pbox_select(b, i);
    } else if (!strcmp(ctl, "idx") && (!strcmp(event, "Scroll") || !strcmp(event, "Change"))) {
        bb_fval v;
        if (!b->loading && !bb_ctl_get(bb_form_ctl(f, "idx"), "Value", -1, &v) && v.i != b->sel) pbox_select(b, v.i);
    } else if (!strcmp(event, "Scroll") || !strcmp(event, "Change")) {
        if (b->loading) return 0;
        bb_fval v;
        int r = 0, g = 0, bl = 0;
        if (!bb_ctl_get(bb_form_ctl(f, "r"), "Value", -1, &v)) r = v.i;
        if (!bb_ctl_get(bb_form_ctl(f, "g"), "Value", -1, &v)) g = v.i;
        if (!bb_ctl_get(bb_form_ctl(f, "b"), "Value", -1, &v)) bl = v.i;
        b->cols[b->sel] = r | g << 8 | bl << 16;
        pbox_draw(b);
    } else if (!strcmp(ctl, "Form") && !strcmp(event, "Resize"))
        pbox_draw(b);
    return 0;
}

static int show_palette(bb_ctl *c)
{
    dlg *d = D(c);
    char afg[1600];
    int n = d->ncolors < 1 ? 1 : d->ncolors > 256 ? 256 : d->ncolors;
    snprintf(afg, sizeof afg,
             "window name=_palette title=\"%s\" resizable=0 mouse=1\n"
             "vlayout id=root\n"
             "  canvas id=pal width=%d height=%d\n"
             "  hlayout weight=0\n"
             "    slider id=idx label=\"C_olour\" min=0 max=%d level=0\n"
             "    label id=hex text=\"0: #000000\" weight=0 minwidth=110\n"
             "  slider id=r label=\"_Red\" min=0 max=255 level=0\n"
             "  slider id=g label=\"_Green\" min=0 max=255 level=0\n"
             "  slider id=b label=\"_Blue\" min=0 max=255 level=0\n"
             "  hlayout weight=0 even=1\n    button id=ok text=_OK default=1\n    space\n    button id=cancel text=_Cancel cancel=1\n",
             d->title ? d->title : "Palette", 16 * PCELL, ((n + 15) / 16) * PCELL, n - 1 > 0 ? n - 1 : 1);
    struct pbox *box = calloc(1, sizeof *box);
    if (!box) return 7;
    box->n = n;
    memcpy(box->cols, d->colors, sizeof box->cols);
    char err[200];
    bb_form *f = bb_form_load(afg, "PaletteDialog", pbox_event, NULL, box, err, sizeof err);
    if (!f) {
        free(box);
        return 7;
    }
    box->f = f;
    sleep_all(1);
    if (bb_form_show(f) == 0) {
        pbox_select(box, d->colorindex >= 0 && d->colorindex < n ? d->colorindex : 0);
        uint32 sig = 0;
        IIntuition->GetAttr(WINDOW_SigMask, f->winobj, &sig);
        int was_ending = ending;
        while (!box->done && f->loaded && f->win && !ending) {
            uint32 got = IExec->Wait(sig | SIGBREAKF_CTRL_C);
            if (got & SIGBREAKF_CTRL_C) {
                /* the requester goes; the break stays set for the program's own loop (it ends) */
                IExec->SetSignal(SIGBREAKF_CTRL_C, SIGBREAKF_CTRL_C);
                break;
            }
            bbf_handle_form(f);
        }
        ending = was_ending;
    }
    bbf_form_discard(f);
    bb_obj_release(box->canvas);
    sleep_all(0);
    int ok = box->ok;
    d->cancelled = !ok;
    if (ok) {
        memcpy(d->colors, box->cols, sizeof d->colors);
        d->colorindex = box->sel;
    }
    free(box);
    return !ok && d->cancelerror ? cdlCancel : 0;
}

/* ShowMessage(prompt, "_Save|_Discard|_Cancel" [, title [, icon]]): 1-based button number */
static int show_message(bb_ctl *c, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b0[16], b1[16], b2[16];
    if (argc < 2) return 450;
    const char *prompt = vstr(&argv[0], b0), *buttons = vstr(&argv[1], b1);
    const char *title = argc > 2 && argv[2].type != BB_FV_NONE ? vstr(&argv[2], b2) : (D(c)->title ? D(c)->title : NULL);
    int icon = argc > 3 && argv[3].type != BB_FV_NONE ? vint(&argv[3]) : 0;
    int n = bb_ui_request(prompt, buttons, title, icon);
    return ret_int(ret, n);
}

/* --- properties ----------------------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

int bbf_dialog_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    dlg *d = D(c);
    if (IS("DialogTitle")) return ret_str(c, out, d->title);
    if (IS("FileName")) return ret_str(c, out, d->filename);
    if (IS("FileTitle")) return ret_str(c, out, d->filetitle);
    if (IS("InitDir")) return ret_str(c, out, d->initdir);
    if (IS("Filter")) return ret_str(c, out, d->filter);
    if (IS("Flags")) return ret_int(out, d->flags);
    if (IS("CancelError")) return ret_int(out, vb_bool(d->cancelerror));
    if (IS("Cancelled")) return ret_int(out, vb_bool(d->cancelled));
    if (IS("FileCount")) return ret_int(out, d->nfiles);
    if (IS("Files")) {
        if (index < 0 || index >= d->nfiles) return 381;
        return ret_str(c, out, d->files[index]);
    }
    if (IS("FontName")) return ret_str(c, out, d->fontname);
    if (IS("FontSize")) return ret_int(out, d->fontsize);
    if (IS("FontBold")) return ret_int(out, vb_bool(d->bold));
    if (IS("FontItalic")) return ret_int(out, vb_bool(d->italic));
    if (IS("FontUnderline")) return ret_int(out, vb_bool(d->underline));
    if (IS("Color")) return ret_int(out, d->color);
    if (IS("ScreenModeID")) return ret_int(out, (int32)d->modeid);
    if (IS("ScreenWidth")) return ret_int(out, d->sw);
    if (IS("ScreenHeight")) return ret_int(out, d->sh);
    if (IS("ScreenDepth")) return ret_int(out, d->sd);
    if (IS("ColorCount")) return ret_int(out, d->ncolors);
    if (IS("ColorIndex")) return ret_int(out, d->colorindex);
    if (IS("Colors")) {
        if (index < 0 || index >= d->ncolors) return 381;
        return ret_int(out, d->colors[index]);
    }
    return 438;
}

int bbf_dialog_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    dlg *d = D(c);
    char buf[16];
    if (IS("DialogTitle")) { set_str(&d->title, vstr(v, buf)); return 0; }
    if (IS("FileName")) { set_str(&d->filename, vstr(v, buf)); return 0; }
    if (IS("InitDir")) { set_str(&d->initdir, vstr(v, buf)); return 0; }
    if (IS("Filter")) { set_str(&d->filter, vstr(v, buf)); return 0; }
    if (IS("Flags")) { d->flags = vint(v); return 0; }
    if (IS("CancelError")) { d->cancelerror = vint(v) != 0; return 0; }
    if (IS("FontName")) { set_str(&d->fontname, vstr(v, buf)); return 0; }
    if (IS("FontSize")) { d->fontsize = vint(v); return 0; }
    if (IS("FontBold")) { d->bold = vint(v) != 0; return 0; }
    if (IS("FontItalic")) { d->italic = vint(v) != 0; return 0; }
    if (IS("FontUnderline")) { d->underline = vint(v) != 0; return 0; }
    if (IS("Color")) { d->color = vint(v) & 0xFFFFFF; return 0; }
    if (IS("ScreenModeID")) { d->modeid = (uint32)vint(v); return 0; }
    if (IS("ColorIndex")) {
        if (vint(v) < 0 || vint(v) > 255) return 380;
        d->colorindex = vint(v);
        return 0;
    }
    if (IS("ColorCount")) {
        int n = vint(v);
        if (n < 1 || n > 256) return 380;
        d->ncolors = n;
        return 0;
    }
    if (IS("Colors")) {
        if (index < 0 || index >= 256) return 381;
        d->colors[index] = vint(v) & 0xFFFFFF;
        if (index >= d->ncolors) d->ncolors = index + 1;
        return 0;
    }
    if (IS("FileTitle") || IS("FileCount") || IS("Files") || IS("Cancelled") || IS("ScreenWidth") || IS("ScreenHeight") ||
        IS("ScreenDepth"))
        return 383;
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

int bbf_dialog_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    if (IS("ShowOpen")) return show_file(c, 0);
    if (IS("ShowSave")) return show_file(c, 1);
    if (IS("ShowFont")) return show_font(c);
    if (IS("ShowScreenMode")) return show_screenmode(c);
    if (IS("ShowColor")) return show_color(c);
    if (IS("ShowPalette")) return show_palette(c);
    if (IS("ShowMessage")) return show_message(c, argc, argv, ret);
    return 438;
}

/* CreateObject("Boing.CommonDialog"): a control without a form */
bb_ctl *bb_dialog_new(void)
{
    bb_ctl *c = calloc(1, sizeof *c);
    c->kind = AFG_COMMONDIALOG;
    c->name = "CommonDialog";
    c->visible = 1;
    IExec->NewList(&c->labels);
    return c;
}

void bb_dialog_free(bb_ctl *c)
{
    if (!c) return;
    bbf_dialog_free(c);
    free(c->ret_buf);
    free(c);
}
