/* ui_menu_test - menus of a form (docs/ui.md section 1), from C: the strip from the .afg,
 * Amiga-key shortcuts (injected) fire <menu>_Click, checkable and radio items, Enabled,
 * Caption, menus added and removed at run time, a context menu opened with the right mouse
 * button over a control. Prints TAP-like lines and PASS/FAIL. */
#define MAIN_TITLE "Boing menu test - running"
#include "test_inject.h"
#include "bb_forms.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "# AmiForge GUI\n"
    "window name=main title=\"Boing menu test\" width=320 height=120\n"
    "vlayout id=root\n"
    "  label id=status text=\"Ready\"\n"
    "  button id=ok text=\"_OK\" contextmenu=mnuCtx minheight=40\n"
    "  timer id=tick interval=400\n"
    "menu id=mnuFile text=\"Project\"\n"
    "  menu id=mnuNew text=\"_New\" key=N\n"
    "  menu text=-\n"
    "  menu id=mnuQuit text=\"Quit\" key=Q\n"
    "menu id=mnuView text=\"View\"\n"
    "  menu id=mnuGrid text=\"Grid\" checkable=1 checked=1 key=G\n"
    "  menu id=mnuZ1 text=\"Zoom 1\" radio=1 checked=1 key=1\n"
    "  menu id=mnuZ2 text=\"Zoom 2\" radio=1 key=2\n"
    "  menu id=mnuSub text=\"More\"\n"
    "    menu id=mnuDeep text=\"Deep\" key=E\n"
    "menu id=mnuCtx text=\"Context\" hidden=1\n"
    "  menu id=mnuCtxA text=\"Context A\"\n"
    "  menu id=mnuCtxB text=\"Context B\"\n";

static bb_form *form;
static int step, timers;
static int c_new, c_quit, c_grid, c_z2, c_deep, c_dyn, c_ctxa, c_ctxb;
static char log_[2048];

static bb_ctl *C(const char *name) { return strcasecmp(name, "Form") ? bb_form_ctl(form, name) : bb_form_self(form); }

static int geti(const char *ctl, const char *prop)
{
    bb_fval v;
    bb_ctl *c = C(ctl);
    if (!c) return -9999;
    int e = bb_ctl_get(c, prop, -1, &v);
    return e ? -9999 : v.i;
}

static const char *gets_(const char *ctl, const char *prop)
{
    static char buf[256];
    bb_fval v;
    bb_ctl *c = C(ctl);
    if (!c || bb_ctl_get(c, prop, -1, &v)) return "<error>";
    snprintf(buf, sizeof buf, "%s", v.s);
    return buf;
}

static int seti(const char *ctl, const char *prop, int i)
{
    bb_fval v = { BB_FV_INT, i, NULL };
    return bb_ctl_set(C(ctl), prop, -1, &v);
}

static int sets(const char *ctl, const char *prop, const char *s)
{
    bb_fval v = { BB_FV_STR, 0, s };
    return bb_ctl_set(C(ctl), prop, -1, &v);
}

static int call(const char *ctl, const char *m, int argc, const char *a0, const char *a1, const char *a2, const char *a3)
{
    bb_fval a[4] = { { BB_FV_STR, 0, a0 }, { BB_FV_STR, 0, a1 }, { BB_FV_STR, 0, a2 }, { BB_FV_STR, 0, a3 } };
    bb_fval r;
    return bb_ctl_call(C(ctl), m, argc, a, &r);
}

#define RAMIGA IEQUALIFIER_RCOMMAND
enum { K_N = 0x36, K_G = 0x24, K_2 = 0x02, K_E = 0x12, K_D = 0x22 };

static void script(void);

static int on_event(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)argc; (void)args;
    char line[80];
    snprintf(line, sizeof line, "%s_%s ", ctl, ev);
    if (strlen(log_) + strlen(line) < sizeof log_ - 1 && strcmp(ctl, "tick")) strcat(log_, line);
    if (strcasecmp(ev, "Click") == 0) {
        if (!strcasecmp(ctl, "mnuNew")) c_new++;
        if (!strcasecmp(ctl, "mnuQuit")) c_quit++;
        if (!strcasecmp(ctl, "mnuGrid")) c_grid++;
        if (!strcasecmp(ctl, "mnuZ2")) c_z2++;
        if (!strcasecmp(ctl, "mnuDeep")) c_deep++;
        if (!strcasecmp(ctl, "mnuDyn")) c_dyn++;
        if (!strcasecmp(ctl, "mnuCtxA")) c_ctxa++;
        if (!strcasecmp(ctl, "mnuCtxB")) c_ctxb++;
    }
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) {
        timers++;
        script();
    }
    return 0;
}

static int ox, oy, ow, oh;

static void script(void)
{
    switch (step++) {
    case 0:
        key_q(K_N, RAMIGA);
        break;
    case 1:
        check(c_new == 1, "Amiga-N fires mnuNew_Click");
        key_q(K_G, RAMIGA);
        break;
    case 2:
        check(c_grid == 1, "Amiga-G fires mnuGrid_Click");
        check(geti("mnuGrid", "Checked") == 0, "the checkable item is now unchecked (Checked = False)");
        key_q(K_2, RAMIGA);
        break;
    case 3:
        check(c_z2 == 1, "Amiga-2 fires mnuZ2_Click");
        check(geti("mnuZ2", "Checked") == -1 && geti("mnuZ1", "Checked") == 0, "radio items: Zoom 2 on, Zoom 1 off");
        key_q(K_E, RAMIGA);
        break;
    case 4:
        check(c_deep == 1, "a sub-item's shortcut fires mnuDeep_Click");
        seti("mnuNew", "Enabled", 0);
        check(geti("mnuNew", "Enabled") == 0, "mnuNew.Enabled = False");
        key_q(K_N, RAMIGA);
        break;
    case 5:
        check(c_new == 1, "a disabled item's shortcut does nothing");
        seti("mnuNew", "Enabled", 1);
        check(call("Form", "AddMenu", 4, "mnuDyn", "Dynamic", "mnuFile", "D") == 0, "Me.AddMenu \"mnuDyn\", ..., \"mnuFile\", \"D\"");
        check(C("mnuDyn") != NULL, "the new menu is a control");
        key_q(K_D, RAMIGA);
        break;
    case 6:
        check(c_dyn == 1, "Amiga-D fires mnuDyn_Click (added at run time)");
        check(call("Form", "RemoveMenu", 1, "mnuDyn", 0, 0, 0) == 0, "Me.RemoveMenu \"mnuDyn\"");
        check(C("mnuDyn") == NULL, "the removed menu is gone");
        key_q(K_D, RAMIGA);
        break;
    case 7:
        check(c_dyn == 1, "its shortcut does nothing any more");
        /* a context menu: RMB down over the OK button, move onto the first item, release */
        if (ready_mouse() && bb_ctl_screen_box(C("ok"), &ox, &oy, &ow, &oh)) {
            pointer(ox + ow / 2, oy + oh / 2);
            IDOS->Delay(2);
            mbutton(IECODE_RBUTTON, 0);
        } else
            step = 10;
        break;
    case 8:
        /* the context menu opens with its first item under the pointer, or just below it */
        for (int i = 1; i <= 6; i++) {
            pointer(ox + ow / 2 + 2 * i, oy + oh / 2 + 2 * i);
            IDOS->Delay(1);
        }
        break;
    case 9:
        mbutton(IECODE_RBUTTON, 1);
        break;
    case 10:
        printf("# context menu: A %d, B %d, ContextControl \"%s\"\n", c_ctxa, c_ctxb, gets_("Form", "ContextControl"));
        check(c_ctxa + c_ctxb == 1, "the right mouse button over ok opened mnuCtx and picked an item");
        check(!strcmp(gets_("Form", "ContextControl"), "ok"), "Me.ContextControl = \"ok\"");
        seti("tick", "Enabled", 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) {
        printf("can't open input.device\nFAIL\n");
        return 20;
    }
    form = bb_form_load(afg, "menu.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form with menus loads");
    if (!form) {
        printf("# %s\nFAIL\n", err);
        return 20;
    }
    check(!strcmp(gets_("mnuNew", "Caption"), "New"), "mnuNew.Caption = \"New\" (underscore stripped)");
    check(!strcmp(gets_("mnuNew", "Shortcut"), "N"), "mnuNew.Shortcut = \"N\"");
    check(geti("mnuGrid", "Checked") == -1, "mnuGrid.Checked from checked=1");
    check(geti("mnuZ1", "Checked") == -1 && geti("mnuZ2", "Checked") == 0, "radio items from the .afg");
    check(!strcmp(gets_("ok", "ContextMenu"), "mnuCtx"), "ok.ContextMenu = \"mnuCtx\"");
    check(sets("mnuQuit", "Caption", "Quit program") == 0 && !strcmp(gets_("mnuQuit", "Caption"), "Quit program"),
          "mnuQuit.Caption round trip");
    check(bb_form_show(form) == 0, "Show opens the window with the menu strip");
    sets("Form", "Caption", MAIN_TITLE);
    int r = bb_forms_run();
    check(r == 0, "the event loop ended");
    bb_forms_cleanup();
    printf("# events: %s\n", log_);
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
