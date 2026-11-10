/* Screens and fonts for forms (docs/ui.md, "Screens and fonts"): windows on a named public screen
 * or the program's own screen (App.OpenScreen, often with a ShowScreenMode result, or screen=own
 * in the .afg), full-screen / borderless / backdrop windows, the screen title while a window is
 * active, and fonts for windows and controls (font= fontsize=, Me.FontName/FontSize, so a
 * ShowFont result can be applied). */
#include "forms_int.h"
#include "../boing.h"
#include <proto/diskfont.h>
#include <proto/graphics.h>
#include <graphics/text.h>
#include <diskfont/diskfont.h>
#include <graphics/modeid.h>

static struct Screen *own_screen;      /* App.OpenScreen / screen=own */
static char own_name[64];
static struct Library *DiskfontLib;
static struct DiskfontIFace *IDF;

/* --- fonts ----------------------------------------------------------------------------- */

typedef struct ofont {
    struct ofont *next;
    struct TextAttr ta;
    struct TextFont *tf;
    int refs;
} ofont;
static ofont *fonts;
static const char *screen_font(bb_form *f, char *buf, size_t n);

/* a font in memory (diskfont), shared by every control and window that asks for it */
struct TextAttr *bbf_font(const char *name, int size)
{
    char full[128];
    if (!name || !*name || size <= 0) return NULL;
    snprintf(full, sizeof full, "%s%s", name, strstr(name, ".font") ? "" : ".font");
    for (ofont *o = fonts; o; o = o->next)
        if (!strcasecmp(o->ta.ta_Name, full) && o->ta.ta_YSize == size) {
            o->refs++;
            return &o->ta;
        }
    if (!IDF) {
        DiskfontLib = IExec->OpenLibrary("diskfont.library", 50);
        if (DiskfontLib) IDF = (void *)IExec->GetInterface(DiskfontLib, "main", 1, NULL);
    }
    ofont *o = calloc(1, sizeof *o);
    o->ta.ta_Name = (STRPTR)xstrdup(full);
    o->ta.ta_YSize = size;
    o->tf = IDF ? IDF->OpenDiskFont(&o->ta) : IGraphics->OpenFont(&o->ta);
    if (!o->tf) {
        free((void *)o->ta.ta_Name);
        free(o);
        return NULL;       /* no such font: the control keeps the default */
    }
    o->refs = 1;
    o->next = fonts;
    fonts = o;
    return &o->ta;
}

void bbf_fonts_cleanup(void)
{
    while (fonts) {
        ofont *o = fonts;
        fonts = o->next;
        if (o->tf) IGraphics->CloseFont(o->tf);
        free((void *)o->ta.ta_Name);
        free(o);
    }
    if (IDF) IExec->DropInterface((struct Interface *)IDF);
    if (DiskfontLib) IExec->CloseLibrary(DiskfontLib);
    IDF = NULL;
    DiskfontLib = NULL;
}

/* a control's font= / fontsize= (fontsize alone: the window's font at that size) */
void bbf_control_font(bb_ctl *c, tags *t)
{
    afg_node *n = c->node;
    if (!n || (!afg_has(n, "font") && !afg_has(n, "fontsize"))) return;
    const char *name = afg_has(n, "font") ? afg_get(n, "font") : afg_get(c->form->afg, "font");
    int size = afg_has(n, "fontsize") ? afg_get_int(n, "fontsize") : afg_get_int(c->form->afg, "fontsize");
    char sf[128];
    if (!*name) name = c->form->tattr ? (const char *)c->form->tattr->ta_Name : screen_font(c->form, sf, sizeof sf);
    if (size <= 0) size = c->form->tattr ? c->form->tattr->ta_YSize : 13;
    struct TextAttr *ta = bbf_font(name, size);
    if (ta) tg(t, GA_TextAttr, (uint32)ta);
}

/* --- screens --------------------------------------------------------------------------- */

struct Screen *bbf_own_screen(void) { return own_screen; }

/* App.OpenScreen modeid [, width, height, depth [, title [, showTitle]]]: the program's own public
   screen; forms loaded afterwards open on it. 0 or a VB error (5: one is already open). */
int bbf_open_screen(uint32 modeid, int w, int h, int depth, const char *title, int showtitle)
{
    if (own_screen) return 5;
    bb_str *t = bb_app_title();
    snprintf(own_name, sizeof own_name, "%.40s.%lu", bb_str_ptr(t)[0] ? bb_str_ptr(t) : "Boing", (unsigned long)(uint32)IExec->FindTask(NULL) & 0xFFFF);
    for (char *p = own_name; *p; p++)
        if (*p == ' ' || *p == ':' || *p == '/') *p = '_';
    if (!title || !*title) title = bb_str_ptr(t);
    own_screen = IIntuition->OpenScreenTags(NULL,
        modeid && modeid != INVALID_ID ? SA_DisplayID : TAG_IGNORE, modeid,
        w > 0 ? SA_Width : TAG_IGNORE, w, h > 0 ? SA_Height : TAG_IGNORE, h,
        depth > 0 ? SA_Depth : TAG_IGNORE, depth,
        SA_LikeWorkbench, TRUE, SA_Title, (uint32)xstrdup(title), SA_ShowTitle, showtitle,
        SA_PubName, (uint32)own_name, SA_Type, PUBLICSCREEN, SA_SharePens, TRUE, TAG_DONE);
    bb_str_release(t);
    if (!own_screen) return 5;
    IIntuition->PubScreenStatus(own_screen, 0);
    return 0;
}

/* closes the program's screen when no window is open on it; 1 if it was closed */
int bbf_close_screen(void)
{
    if (!own_screen) return 1;
    for (bb_form *f = forms; f; f = f->next)
        if (f->win && f->win->WScreen == own_screen) return 0;
    if (!IIntuition->CloseScreen(own_screen)) return 0;       /* a visitor window is still open */
    own_screen = NULL;
    return 1;
}

/* the window tags of a form: its screen, full-screen / borderless / backdrop, screen title, font.
   *placed = 1 when the position and size are set here (the caller then leaves them alone). */
void bbf_screen_tags(bb_form *f, tags *t, int *placed)
{
    afg_node *a = f->afg;
    *placed = 0;
    if (!strcasecmp(afg_get(a, "screen"), "own") && !own_screen) {
        uint32 id = afg_has(a, "screenmode") ? (uint32)strtoul(afg_get(a, "screenmode"), NULL, 0) : INVALID_ID;
        bbf_open_screen(id, afg_get_int(a, "screenwidth"), afg_get_int(a, "screenheight"), afg_get_int(a, "screendepth"),
                        afg_get(a, "screentitle"), !afg_get_bool(a, "fullscreen"));
    }
    struct Screen *scr = NULL;
    int unlock = 0;
    if (own_screen && strcasecmp(afg_get(a, "screen"), "workbench")) {
        scr = own_screen;
        tg(t, WA_CustomScreen, (uint32)own_screen);
    } else if (afg_has(a, "pubscreen")) {
        scr = IIntuition->LockPubScreen(afg_get(a, "pubscreen"));
        if (scr) {
            unlock = 1;
            tg(t, WA_PubScreen, (uint32)scr);    /* locked until the window is open (bbf_screen_unlock) */
            f->pubscr = scr;
            unlock = 0;
        }
    }
    if (afg_has(a, "screentitle")) tg(t, WA_ScreenTitle, (uint32)afg_get(a, "screentitle"));
    if (afg_get_bool(a, "fullscreen")) {
        struct Screen *s = scr ? scr : IIntuition->LockPubScreen(NULL);
        /* the whole screen; on the program's own screen its title bar is hidden (games) */
        if (s && s == own_screen) IIntuition->ShowTitle(own_screen, FALSE);
        tg(t, WA_Left, 0);
        tg(t, WA_Top, 0);
        tg(t, WA_Width, s ? s->Width : 640);
        tg(t, WA_Height, s ? s->Height : 480);
        tg(t, WA_Borderless, TRUE);
        tg(t, WA_Backdrop, TRUE);
        if (!scr && s) IIntuition->UnlockPubScreen(NULL, s);
        *placed = 1;
    } else {
        if (afg_get_bool(a, "borderless")) tg(t, WA_Borderless, TRUE);
        if (afg_get_bool(a, "backdrop")) tg(t, WA_Backdrop, TRUE);
    }
    if (afg_has(a, "font") || afg_has(a, "fontsize")) {
        char sf[128];
        struct TextAttr *ta = bbf_font(afg_has(a, "font") ? afg_get(a, "font") : screen_font(f, sf, sizeof sf),
                                       afg_has(a, "fontsize") ? afg_get_int(a, "fontsize") : 13);
        if (ta) tg(t, WINDOW_TextAttr, (uint32)ta);
        f->tattr = ta;
    }
    (void)unlock;
}

/* the name of a screen's font ("DejaVu Sans.font"), for a fontsize= without font= */
static const char *screen_font(bb_form *f, char *buf, size_t n)
{
    struct Screen *s = bbf_lock_form_screen(f);
    snprintf(buf, n, "%s", s && s->Font && s->Font->ta_Name ? (const char *)s->Font->ta_Name : "DejaVu Sans.font");
    bbf_unlock_form_screen(f, s);
    return buf;
}

/* the screen a form's window opens (or will open) on, locked: for pictures and font sizes made
   before the window exists. bbf_unlock_form_screen gives it back. */
struct Screen *bbf_lock_form_screen(bb_form *f)
{
    if (f && f->win) return f->win->WScreen;
    if (f && own_screen && strcasecmp(afg_get(f->afg, "screen"), "workbench")) return own_screen;
    struct Screen *s = f && afg_has(f->afg, "pubscreen") ? IIntuition->LockPubScreen(afg_get(f->afg, "pubscreen")) : NULL;
    return s ? s : IIntuition->LockPubScreen(NULL);
}

void bbf_unlock_form_screen(bb_form *f, struct Screen *s)
{
    if (!s || (f && f->win && s == f->win->WScreen) || s == own_screen) return;
    IIntuition->UnlockPubScreen(NULL, s);
}

/* after WM_OPEN: the public screen's lock isn't needed any more (the window holds it) */
void bbf_screen_unlock(bb_form *f)
{
    if (f->pubscr) IIntuition->UnlockPubScreen(NULL, f->pubscr);
    f->pubscr = NULL;
}

/* --- properties -------------------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

int bbf_screen_get(bb_form *f, const char *prop, bb_fval *out)
{
    if (IS("ScreenTitle")) return ret_str(&f->self, out, f->scrtitle ? f->scrtitle : afg_get(f->afg, "screentitle"));
    if (IS("FontName")) {
        if (!f->tattr) return ret_str(&f->self, out, "");
        char b[128];
        snprintf(b, sizeof b, "%s", f->tattr->ta_Name);
        char *dot = strstr(b, ".font");
        if (dot) *dot = 0;
        return ret_str(&f->self, out, b);
    }
    if (IS("FontSize")) return ret_int(out, f->tattr ? f->tattr->ta_YSize : 0);
    if (IS("ScreenWidth") || IS("ScreenHeight")) {
        struct Screen *s = f->win ? f->win->WScreen : own_screen;
        int lock = !s;
        if (!s) s = IIntuition->LockPubScreen(NULL);
        int v = s ? (IS("ScreenWidth") ? s->Width : s->Height) : 0;
        if (lock && s) IIntuition->UnlockPubScreen(NULL, s);
        return ret_int(out, v);
    }
    return 438;
}

/* the new font on every gadget of the form, then a new layout */
static void apply_font(bb_form *f)
{
    if (!f->tattr) return;
    IIntuition->SetAttrs(f->winobj, WINDOW_TextAttr, (uint32)f->tattr, TAG_DONE);
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (!c->obj || !afg_takes_space(c->kind) || c->kind == AFG_TOOL || afg_has(c->node, "font")) continue;
        set_attr(c, GA_TextAttr, (uint32)f->tattr);
    }
    if (f->root && f->win) IIntuition->SetGadgetAttrs((struct Gadget *)f->root, f->win, NULL, GA_TextAttr, (uint32)f->tattr, TAG_DONE);
    relayout(f);
}

int bbf_screen_set(bb_form *f, const char *prop, const bb_fval *v)
{
    char buf[16];
    if (IS("ScreenTitle")) {
        free(f->scrtitle);
        f->scrtitle = xstrdup(vstr(v, buf));
        if (f->win) IIntuition->SetWindowTitles(f->win, (STRPTR)~0, f->scrtitle);
        return 0;
    }
    if (IS("FontName") || IS("FontSize")) {
        char name[128];
        int size = f->tattr ? f->tattr->ta_YSize : 13;
        if (f->tattr) snprintf(name, sizeof name, "%s", (char *)f->tattr->ta_Name);
        else {
            screen_font(f, name, sizeof name);       /* no font= yet: the screen's font */
            struct Screen *s = bbf_lock_form_screen(f);
            if (s && s->Font) size = s->Font->ta_YSize;
            bbf_unlock_form_screen(f, s);
        }
        if (IS("FontName")) snprintf(name, sizeof name, "%s", vstr(v, buf));
        else size = vint(v);
        struct TextAttr *ta = bbf_font(name, size);
        if (!ta) return 380;
        f->tattr = ta;
        apply_font(f);
        return 0;
    }
    if (IS("ScreenWidth") || IS("ScreenHeight")) return 383;
    return 438;
}
