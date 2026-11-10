/* ui_desktop_test - docs/ui.md "Screens and fonts" and "Keyboard": `_` shortcuts on buttons,
 * check boxes and labelled fields, default=1 (Return) and cancel=1 (Esc) buttons, a window font
 * (font= fontsize=, Me.FontName/FontSize), a form on the program's own full-screen screen
 * (screen=own fullscreen=1) closed again at the end. TAP lines and PASS/FAIL. */
#define MAIN_TITLE "Boing desktop test - running"
#include "test_inject.h"
#include "bb_forms.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing desktop test\" width=320 height=150 font=\"DejaVu Sans\" fontsize=18\n"
    "vlayout id=root\n"
    "  button id=go text=\"_Go\"\n"
    "  checkbox id=fast text=\"_Fast\"\n"
    "  string id=name label=\"_Name\"\n"
    "  hlayout\n"
    "    button id=ok text=\"OK\" default=1\n"
    "    button id=cancel text=\"Cancel\" cancel=1\n"
    "  timer id=tick interval=400\n"
    "  timer id=guard interval=120000\n";

static const char *afg_screen =
    "window name=full title=\"Boing full screen\" screen=own screenwidth=640 screenheight=480 screendepth=16 fullscreen=1\n"
    "vlayout id=root\n"
    "  label text=\"On the program's own screen\"\n";

static bb_form *form;
static int step, c_go, c_fast, c_ok, c_cancel;

static bb_ctl *C(const char *n) { return strcasecmp(n, "Form") ? bb_form_ctl(form, n) : bb_form_self(form); }
static int geti(bb_ctl *c, const char *p) { bb_fval v; return bb_ctl_get(c, p, -1, &v) ? -9999 : v.i; }
static const char *gets_(bb_ctl *c, const char *p)
{
    static char b[128];
    bb_fval v;
    if (bb_ctl_get(c, p, -1, &v)) return "<error>";
    snprintf(b, sizeof b, "%s", v.s ? v.s : "");
    return b;
}

static void script(void);
static int ev(void *ud, bb_form *f, const char *ctl, const char *e, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)argc; (void)args;
    if (!strcasecmp(ctl, "guard") && !strcasecmp(e, "Timer")) {
        printf("not ok - the test took more than 2 minutes (guard timer)\n");
        fails++;
        bb_forms_end();
        return 0;
    }
    if (!strcasecmp(e, "Click")) {
        if (!strcasecmp(ctl, "go")) c_go++;
        if (!strcasecmp(ctl, "fast")) c_fast++;
        if (!strcasecmp(ctl, "ok")) c_ok++;
        if (!strcasecmp(ctl, "cancel")) c_cancel++;
    }
    if (!strcasecmp(ctl, "tick") && !strcasecmp(e, "Timer")) script();
    return 0;
}

static void script(void)
{
    switch (step++) {
    case 0: key(0x24); break;                         /* g */
    case 1:
        check(c_go == 1, "the _G shortcut clicks the Go button");
        key(0x23);                                    /* f */
        break;
    case 2:
        check(c_fast == 1 && geti(C("fast"), "Value") == 1, "the _F shortcut toggles the check box");
        key(0x44);                                    /* Return */
        break;
    case 3:
        check(c_ok == 1, "Return clicks the default=1 button");
        key(0x45);                                    /* Esc */
        break;
    case 4:
        check(c_cancel == 1, "Esc clicks the cancel=1 button");
        break;
    case 5: {
        char err[200];
        bb_form *full = bb_form_load(afg_screen, "full.afg", NULL, NULL, NULL, err, sizeof err);
        check(full != NULL, "a form with screen=own fullscreen=1 loads");
        if (!full) { printf("# %s\n", err); break; }
        check(bb_form_show(full) == 0, "it opens on its own screen");
        bb_ctl *s = bb_form_self(full);
        printf("# screen %dx%d, window %d wide\n", geti(s, "ScreenWidth"), geti(s, "ScreenHeight"), geti(s, "Width"));
        check(geti(s, "ScreenWidth") == 640 && geti(s, "ScreenHeight") == 480, "the screen has the asked size (640 x 480)");
        check(geti(s, "Width") == 640, "the full-screen window covers the screen");
        IDOS->Delay(25);
        bb_form_unload(full);
        break;
    }
    case 6: {
        bb_fval v = { BB_FV_INT, 0, NULL, NULL };
        bb_ctl_set(C("tick"), "Enabled", -1, &v);
        bb_form_unload(form);
        break;
    }
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "desktop.afg", ev, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    printf("# FontName \"%s\" FontSize %d\n", gets_(C("Form"), "FontName"), geti(C("Form"), "FontSize"));
    check(!strcmp(gets_(C("Form"), "FontName"), "DejaVu Sans") && geti(C("Form"), "FontSize") == 18, "the window font from font= fontsize=");
    check(bb_form_show(form) == 0, "Show");
    printf("# button height %d\n", geti(C("go"), "Height"));
    check(geti(C("go"), "Height") >= 20, "the controls use the 18-pixel font (button height >= 20)");
    bb_fval cap = { BB_FV_STR, 0, MAIN_TITLE, NULL };
    bb_ctl_set(C("Form"), "Caption", -1, &cap);
    bb_forms_run();
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
