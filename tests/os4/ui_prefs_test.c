/* ui_prefs_test - docs/ui.md group 7: CommonDialog.ShowPalette (Return keeps the colours, a click
 * on a swatch picks it (ColorIndex) and a click on the Red slider changes that colour only, Esc
 * cancels), hints in a statusbar hints=1 (the hint of the control under the pointer, the
 * program's text back afterwards) and the HelpNode property. TAP lines and PASS/FAIL. */
#define MAIN_TITLE "Boing prefs test - running"
#include "test_inject.h"
#include "bb_forms.h"
#include <proto/graphics.h>

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing prefs test\" width=360 height=160 helpnode=mainnode\n"
    "vlayout id=root\n"
    "  button id=save text=\"Save\" hint=\"Saves the file\" helpnode=saving\n"
    "  space\n"
    "  label id=plain text=\"no hint here\"\n"
    "  statusbar id=sb hints=1 panels=\"Ready|x\" widths=\"0|40\"\n"
    "  commondialog id=dlg title=\"Palette test\"\n"
    "  timer id=tick interval=500\n"
    "  timer id=guard interval=150000\n";

static bb_form *form;
static int step;

static bb_ctl *C(const char *n) { return strcasecmp(n, "Form") ? bb_form_ctl(form, n) : bb_form_self(form); }
static int geti(bb_ctl *c, const char *p, int idx) { bb_fval v; return bb_ctl_get(c, p, idx, &v) ? -9999 : v.i; }
static const char *gets_(bb_ctl *c, const char *p, int idx)
{
    static char b[128];
    bb_fval v;
    if (bb_ctl_get(c, p, idx, &v)) return "<error>";
    snprintf(b, sizeof b, "%s", v.s ? v.s : "");
    return b;
}
static void seti(bb_ctl *c, const char *p, int idx, int32_t i) { bb_fval v = { BB_FV_INT, i, NULL, NULL }; bb_ctl_set(c, p, idx, &v); }
static void sets(bb_ctl *c, const char *p, const char *s) { bb_fval v = { BB_FV_STR, 0, s, NULL }; bb_ctl_set(c, p, -1, &v); }
static int call0(bb_ctl *c, const char *m) { bb_fval r; memset(&r, 0, sizeof r); return bb_ctl_call(c, m, 0, NULL, &r); }

/* a process that clicks in the palette requester while the test sits in ShowPalette: swatch 5,
   then the right end of the Red slider, then Return */
static volatile int clicker_done, clicker_ok;
static volatile uint32 swatch1 = 0xDEAD;
static void clicker_entry(void)
{
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq),
                                                   ASOIOR_ReplyPort, p, TAG_DONE);
    if (r && !IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) {
        struct IOStdReq *saved = ireq;
        ireq = r;              /* inject() through this process's own request */
        IDOS->Delay(60);
        int active = 0, front = 0;
        for (int t = 0; t < 30 && !active; t++) {
            active = make_active("Palette test");
            if (!active) IDOS->Delay(10);
        }
        find_window_ex("Palette test", &front);
        bb_form *pf = bb_form_find("_palette");
        struct Window *w = find_window("Palette test");
        if (!active || !front || !pf || !w) printf("# clicker: active %d front %d form %p\n", active, front, (void *)pf);
        else {
            bb_ctl *pal = bb_form_ctl(pf, "pal"), *red = bb_form_ctl(pf, "r");
            int px = w->LeftEdge + geti(pal, "Left", -1), py = w->TopEdge + geti(pal, "Top", -1);
            printf("# palette canvas at %d,%d (%dx%d)\n", px, py, geti(pal, "Width", -1), geti(pal, "Height", -1));
            IDOS->Delay(15);
            /* swatch 1 (white) as drawn in the window: the picture must survive the layout's repaint */
            swatch1 = IGraphics->ReadPixelColor(w->RPort, geti(pal, "Left", -1) + 1 * 20 + 10, geti(pal, "Top", -1) + 10) & 0xFFFFFF;
            click_at(px + 5 * 20 + 10, py + 10);
            IDOS->Delay(25);
            int rx = w->LeftEdge + geti(red, "Left", -1) + geti(red, "Width", -1) - 4;
            int ry = w->TopEdge + geti(red, "Top", -1) + geti(red, "Height", -1) / 2;
            click_at(rx, ry);
            IDOS->Delay(25);
            if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow == find_window("Palette test")) {
                struct InputEvent ie;
                memset(&ie, 0, sizeof ie);
                ie.ie_Class = IECLASS_RAWKEY;
                ie.ie_Code = 0x44;                     /* Return */
                inject(&ie);
                ie.ie_Code |= IECODE_UP_PREFIX;
                inject(&ie);
                clicker_ok = 1;
            }
        }
        ireq = saved;
        IExec->CloseDevice((struct IORequest *)r);
    }
    if (r) IExec->FreeSysObject(ASOT_IOREQUEST, r);
    if (p) IExec->FreeSysObject(ASOT_PORT, p);
    clicker_done = 1;
}

static void script(void);
static int ev(void *ud, bb_form *f, const char *ctl, const char *e, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)argc; (void)args;
    if (!strcasecmp(ctl, "guard") && !strcasecmp(e, "Timer")) {
        printf("not ok - the test took more than 2.5 minutes (guard timer)\n");
        fails++;
        bb_forms_end();
        return 0;
    }
    if (!strcasecmp(ctl, "tick") && !strcasecmp(e, "Timer")) script();
    return 0;
}

static int32_t pal0[8] = { 0x000000, 0xFFFFFF, 0x0000FF, 0x00FF00, 0xFF0000, 0x404010, 0x808080, 0x00FFFF };

static int colours_are(int skip)
{
    for (int i = 0; i < 8; i++)
        if (i != skip && geti(C("dlg"), "Colors", i) != pal0[i]) return 0;
    return 1;
}

static void script(void)
{
    struct Window *w = find_window(MAIN_TITLE);
    switch (step++) {
    case 0:
        check(!strcmp(gets_(C("save"), "HelpNode", -1), "saving"), "HelpNode from helpnode=");
        sets(C("save"), "HelpNode", "saving2");
        check(!strcmp(gets_(C("save"), "HelpNode", -1), "saving2"), "HelpNode can be set");
        check(!strcmp(gets_(C("Form"), "HelpNode", -1), "mainnode"), "the form's HelpNode from the window's helpnode=");
        sets(C("Form"), "HelpNode", "other");
        check(!strcmp(gets_(C("Form"), "HelpNode", -1), "other"), "the form's HelpNode can be set");
        if (ready_mouse() && w) pointer(w->LeftEdge + geti(C("save"), "Left", -1) + 10, w->TopEdge + geti(C("save"), "Top", -1) + 5);
        break;
    case 1:
        if (strcmp(gets_(C("sb"), "Hint", -1), "Saves the file") && w)      /* the first move can come before the window is ready */
            pointer(w->LeftEdge + geti(C("save"), "Left", -1) + 12, w->TopEdge + geti(C("save"), "Top", -1) + 6);
        break;
    case 2:
        {
            printf("# hint shown: \"%s\"\n", gets_(C("sb"), "Hint", -1));
            check(!strcmp(gets_(C("sb"), "Hint", -1), "Saves the file"), "the button's hint in the status bar while the pointer is over it");
            check(!strcmp(gets_(C("sb"), "Panel", 0), "Ready"), "Panel(0) is still the program's text while a hint shows");
            bb_fval v = { BB_FV_STR, 0, "Saved 3 files", NULL };
            bb_ctl_set(C("sb"), "Panel", 0, &v);          /* the program writes while the hint shows */
            check(!strcmp(gets_(C("sb"), "Panel", 0), "Saved 3 files"), "a text written while a hint shows is what Panel(0) gives");
        }
        if (w) pointer(w->LeftEdge + geti(C("plain"), "Left", -1) + 5, w->TopEdge + geti(C("plain"), "Top", -1) + 3);
        break;
    case 3:
        printf("# panel elsewhere: \"%s\"\n", gets_(C("sb"), "Panel", 0));
        check(!strcmp(gets_(C("sb"), "Panel", 0), "Saved 3 files") && !*gets_(C("sb"), "Hint", -1), "the program's latest text when the pointer leaves");
        break;
    case 4: {
        seti(C("dlg"), "ColorCount", -1, 8);
        for (int i = 0; i < 8; i++) seti(C("dlg"), "Colors", i, pal0[i]);
        int k[1] = { 0x44 };
        keys_later(60, "Palette test", k, 1);
        int e = call0(C("dlg"), "ShowPalette");
        keys_later_wait();
        check(e == 0 && geti(C("dlg"), "Cancelled", -1) == 0 && colours_are(-1), "ShowPalette + Return keeps the colours");
        check(geti(C("dlg"), "ColorIndex", -1) == 0, "ColorIndex 0 (the first colour) when nothing was picked");
        break;
    }
    case 5: {
        int k[1] = { 0x45 };
        keys_later(60, "Palette test", k, 1);
        int e = call0(C("dlg"), "ShowPalette");
        keys_later_wait();
        printf("# Esc: e %d Cancelled %d\n", e, geti(C("dlg"), "Cancelled", -1));
        check(e == 0 && geti(C("dlg"), "Cancelled", -1) != 0 && colours_are(-1), "ShowPalette + Esc: Cancelled, colours kept");
        break;
    }
    case 6: {
        clicker_done = clicker_ok = 0;
        IDOS->CreateNewProcTags(NP_Entry, clicker_entry, NP_Name, "bb ui test clicker", NP_Child, TRUE, TAG_DONE);
        int e = call0(C("dlg"), "ShowPalette");
        for (int i = 0; i < 100 && !clicker_done; i++) IDOS->Delay(5);
        int32_t c5 = geti(C("dlg"), "Colors", 5);
        printf("# clicker %d, ColorIndex %d, Colors(5) %06lX\n", clicker_ok, geti(C("dlg"), "ColorIndex", -1), (long)c5);
        check(e == 0 && clicker_ok && geti(C("dlg"), "Cancelled", -1) == 0, "ShowPalette closed with Return after the clicks");
        check(geti(C("dlg"), "ColorIndex", -1) == 5, "a click on swatch 5 picks it (ColorIndex 5)");
        check((c5 & 0xFF) > (pal0[5] & 0xFF) && (c5 & 0xFFFF00) == (pal0[5] & 0xFFFF00), "the Red slider raised colour 5's red only");
        check(colours_are(5), "the other colours are unchanged");
        printf("# swatch 1 on screen: %06lX\n", (long)swatch1);
        check(swatch1 == 0xFFFFFF, "the swatches are drawn in the window (swatch 1 white)");
        break;
    }
    case 7:
        seti(C("tick"), "Enabled", -1, 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "prefs.afg", ev, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    check(bb_form_show(form) == 0, "Show");
    bb_fval cap = { BB_FV_STR, 0, MAIN_TITLE, NULL };
    bb_ctl_set(C("Form"), "Caption", -1, &cap);
    bb_forms_run();
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
