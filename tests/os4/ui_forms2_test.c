/* ui_forms2_test - docs/ui.md section 5: Show vbModal (the other form gets no input, timers keep
 * running, Show returns when the dialog is hidden), WindowState iconify/uniconify (iconify=1),
 * remembered window boxes (remember=1 in ENV:), a tool window. TAP lines, PASS/FAIL. */
#define MAIN_TITLE "Boing forms2 main - running"
#include "test_inject.h"
#include "bb_forms.h"
#include "bb_sys.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg_main =
    "window name=main title=\"Boing forms2 main\" width=300 height=100\n"
    "vlayout id=root\n"
    "  button id=ok text=\"_OK\" minheight=40\n"
    "  timer id=tick interval=400\n"
    "  timer id=tick2 interval=300\n";
static const char *afg_dlg =
    "window name=dlg title=\"Boing forms2 dialog\" width=220 height=80 remember=1 iconify=1 toolwindow=1\n"
    "vlayout id=root\n"
    "  label text=\"A modal dialog\"\n"
    "  timer id=dtick interval=400\n";

static bb_form *fmain, *fdlg;
static int mstep, dstep, mainclicks, inmodal, returned, mainticks_in_modal;
static int ox, oy, ow, oh;

static bb_ctl *CM(const char *n) { return strcasecmp(n, "Form") ? bb_form_ctl(fmain, n) : bb_form_self(fmain); }
static bb_ctl *CD(const char *n) { return strcasecmp(n, "Form") ? bb_form_ctl(fdlg, n) : bb_form_self(fdlg); }
static int geti(bb_ctl *c, const char *p) { bb_fval v; return bb_ctl_get(c, p, -1, &v) ? -9999 : v.i; }
static void seti(bb_ctl *c, const char *p, int i) { bb_fval v = { BB_FV_INT, i, NULL, NULL }; bb_ctl_set(c, p, -1, &v); }

static int ev_main(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args);
static int ev_dlg(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)argc; (void)args;
    if (strcasecmp(ctl, "dtick") || strcasecmp(ev, "Timer")) return 0;
    switch (dstep++) {
    case 0:
        check(inmodal, "the dialog runs inside Show vbModal");
        /* a click on the main window's button must do nothing now */
        if (bb_ctl_screen_box(CM("ok"), &ox, &oy, &ow, &oh) && make_active("Boing forms2 main - running")) click_at(ox + ow / 2, oy + oh / 2);
        break;
    case 1:
        check(mainclicks == 0, "the main form gets no input while the dialog is modal");
        check(mainticks_in_modal > 0, "the main form's timer keeps running");
        seti(CD("Form"), "WindowState", 1);
        break;
    case 2:
        check(geti(CD("Form"), "WindowState") == 1 && geti(CD("Form"), "Visible") == 0, "WindowState = 1 iconifies (no window)");
        seti(CD("Form"), "WindowState", 0);
        break;
    case 3:
        check(geti(CD("Form"), "WindowState") == 0 && geti(CD("Form"), "Visible") == -1, "WindowState = 0 opens it again");
        seti(CD("dtick"), "Enabled", 0);
        bb_form_hide(fdlg);              /* ends the modal Show */
        break;
    }
    return 0;
}

static int ev_main(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)argc; (void)args;
    if (!strcasecmp(ctl, "ok") && !strcasecmp(ev, "Click")) mainclicks++;
    /* another timer of the main form (tick's own event is still running: it started the modal) */
    if (!strcasecmp(ctl, "tick2") && !strcasecmp(ev, "Timer") && inmodal) mainticks_in_modal++;
    if (strcasecmp(ctl, "tick") || strcasecmp(ev, "Timer")) return 0;
    switch (mstep++) {
    case 0: {
        char err[200];
        fdlg = bb_form_load(afg_dlg, "dlg.afg", ev_dlg, NULL, NULL, err, sizeof err);
        check(fdlg != NULL, "the dialog form loads");
        if (!fdlg) { bb_form_unload(fmain); break; }
        inmodal = 1;
        int e = bb_form_show_modal(fdlg);
        inmodal = 0;
        returned = 1;
        check(e == 0 && dstep == 4, "Show vbModal returned after the dialog was hidden");
        FILE *fp = fopen("ENV:ui_forms2_test/windows/dlg", "r");
        int b[4] = { 0 };
        int nn = fp ? fscanf(fp, "%d %d %d %d", &b[0], &b[1], &b[2], &b[3]) : 0;
        if (fp) fclose(fp);
        printf("# remembered box %d %d %d %d\n", b[0], b[1], b[2], b[3]);
        check(nn == 4 && b[2] > 0, "remember=1 saved the window box in ENV:<App.Title>/windows/dlg");
        break;
    }
    case 1:
        bb_form_unload(fdlg);
        seti(CM("tick"), "Enabled", 0);
        seti(CM("tick2"), "Enabled", 0);
        bb_form_unload(fmain);
        break;
    }
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    bb_sys_init(argc, argv, NULL);      /* App.Title = the program name */
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    fmain = bb_form_load(afg_main, "main.afg", ev_main, NULL, NULL, err, sizeof err);
    check(fmain != NULL, "the main form loads");
    if (!fmain) { printf("# %s\nFAIL\n", err); return 20; }
    bb_form_show(fmain);
    bb_fval cap = { BB_FV_STR, 0, MAIN_TITLE, NULL };
    bb_ctl_set(CM("Form"), "Caption", -1, &cap);
    bb_forms_run();
    bb_forms_cleanup();
    inject_close();
    IDOS->Delete("ENV:ui_forms2_test/windows/dlg");
    IDOS->Delete("ENVARC:ui_forms2_test/windows/dlg");
    IDOS->Delete("ENV:ui_forms2_test/windows");
    IDOS->Delete("ENVARC:ui_forms2_test/windows");
    IDOS->Delete("ENV:ui_forms2_test");
    IDOS->Delete("ENVARC:ui_forms2_test");
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
