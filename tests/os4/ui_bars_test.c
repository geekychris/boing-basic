/* ui_bars_test - toolbar, status bar, image, CommonDialog (docs/ui.md sections 2 to 4): a click
 * on a tool fires <tool>_Click and its menu's Click, tool properties, status bar panels, the
 * custom-button requester, asl requesters answered by injected keys (cancel, CancelError,
 * Return on a preset file), the colour requester, CreateObject's dialog without a form.
 * Prints TAP-like lines and PASS/FAIL. */
#define MAIN_TITLE "Boing bars test - running"
#include "test_inject.h"
#include "bb_forms.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing bars test\" width=360 height=160\n"
    "vlayout id=root\n"
    "  toolbar id=tb weight=0\n"
    "    tool id=tbNew text=\"New\" image=\"TBImages:new\" hint=\"New document\" menu=mnuNew\n"
    "    tool id=tbOpen text=\"Open\" image=\"TBImages:open\"\n"
    "    tool separator=1\n"
    "    tool id=tbGrid text=\"Grid\" toggle=1 checked=1\n"
    "  image id=logo file=\"TBImages:save\"\n"
    "  label id=status text=\"Ready\"\n"
    "  commondialog id=dlg title=\"Bars test dialog\"\n"
    "  statusbar id=sb panels=\"Ready|Ln 1|100%\" widths=\"0|60|50\"\n"
    "  timer id=tick interval=400\n"
    "  timer id=guard interval=120000\n"
    "menu id=mnuFile text=\"Project\"\n"
    "  menu id=mnuNew text=\"New\" key=N\n";

static bb_form *form;
static int step, c_tbnew, c_mnunew, c_tbopen;

static bb_ctl *C(const char *name) { return strcasecmp(name, "Form") ? bb_form_ctl(form, name) : bb_form_self(form); }

static int geti_c(bb_ctl *c, const char *prop, int idx)
{
    bb_fval v;
    if (!c) return -9999;
    return bb_ctl_get(c, prop, idx, &v) ? -9999 : v.i;
}
static int geti(const char *ctl, const char *prop) { return geti_c(C(ctl), prop, -1); }

static const char *gets_c(bb_ctl *c, const char *prop, int idx)
{
    static char buf[256];
    bb_fval v;
    if (!c || bb_ctl_get(c, prop, idx, &v)) return "<error>";
    snprintf(buf, sizeof buf, "%s", v.s);
    return buf;
}
static const char *gets_(const char *ctl, const char *prop) { return gets_c(C(ctl), prop, -1); }

static int seti_c(bb_ctl *c, const char *prop, int idx, int i)
{
    bb_fval v = { BB_FV_INT, i, NULL };
    return bb_ctl_set(c, prop, idx, &v);
}
static int sets_c(bb_ctl *c, const char *prop, int idx, const char *s)
{
    bb_fval v = { BB_FV_STR, 0, s };
    return bb_ctl_set(c, prop, idx, &v);
}
static int call0(bb_ctl *c, const char *m) { bb_fval r; return bb_ctl_call(c, m, 0, NULL, &r); }

static void script(void);

static int on_event(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    if (!strcasecmp(ctl, "guard") && !strcasecmp(ev, "Timer")) {
        /* a step got stuck: fail and close everything rather than leave a window behind */
        printf("not ok - the test took more than 2 minutes (guard timer)\n");
        fails++;
        bb_forms_end();
        return 0;
    }
    (void)ud; (void)f; (void)argc; (void)args;
    if (!strcasecmp(ev, "Click")) {
        if (!strcasecmp(ctl, "tbNew")) c_tbnew++;
        if (!strcasecmp(ctl, "mnuNew")) c_mnunew++;
        if (!strcasecmp(ctl, "tbOpen")) c_tbopen++;
    }
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) script();
    return 0;
}

enum { K_RETURN = 0x44, K_ESC = 0x45, K_D = 0x22, K_S = 0x21, K_C = 0x33 };

static void script(void)
{
    int x, y, w, h;
    switch (step++) {
    case 0:
        if (ready_mouse() && bb_ctl_screen_box(C("tb"), &x, &y, &w, &h)) {
            printf("# toolbar box %d,%d %dx%d\n", x, y, w, h);
            click_at(x + 12, y + h / 2);          /* the first tool */
        }
        break;
    case 1:
        check(c_tbnew == 1, "a click on the first tool fires tbNew_Click");
        check(c_mnunew == 1, "and its menu= item's mnuNew_Click");
        seti_c(C("mnuNew"), "Enabled", -1, 0);
        check(geti("tbNew", "Enabled") == 0, "disabling mnuNew disables tbNew (menu=)");
        seti_c(C("mnuNew"), "Enabled", -1, -1);
        check(geti("tbNew", "Enabled") == -1, "and enabling it enables the tool");
        break;
    case 2: {
        /* the custom-button requester: D picks "_Discard" (button 2 of 3) */
        if (ready()) {
            int k[1] = { K_D };
            keys_later(40, "Bars test", k, 1);
            bb_fval a[3] = { { BB_FV_STR, 0, "Save the changes?" }, { BB_FV_STR, 0, "_Save|_Discard|_Cancel" },
                             { BB_FV_STR, 0, "Bars test" } };
            bb_fval r = { 0 };
            int e = bb_ctl_call(C("dlg"), "ShowMessage", 3, a, &r);
            keys_later_wait();
            check(e == 0 && r.type == BB_FV_INT && r.i == 2, "dlg.ShowMessage(..., \"_Save|_Discard|_Cancel\") = 2 for D");
            printf("# ShowMessage returned %ld\n", (long)r.i);
            int k2[1] = { K_ESC };
            keys_later(40, "Bars test", k2, 1);
            r.i = 0;
            bb_ctl_call(C("dlg"), "ShowMessage", 3, a, &r);
            keys_later_wait();
            check(r.i == 3, "Esc gives the last button (3)");
        }
        break;
    }
    case 3:
        if (ready()) {
            /* the asl requester: Esc cancels */
            int k[1] = { K_ESC };
            keys_later(60, "Bars test dialog", k, 1);
            int e = call0(C("dlg"), "ShowOpen");
            keys_later_wait();
            check(e == 0 && geti("dlg", "Cancelled") == -1, "ShowOpen + Esc: Cancelled = True");
            seti_c(C("dlg"), "CancelError", -1, -1);
            keys_later(60, "Bars test dialog", k, 1);
            e = call0(C("dlg"), "ShowOpen");
            keys_later_wait();
            check(e == 32755, "with CancelError = True, cancelling is error 32755 (cdlCancel)");
            seti_c(C("dlg"), "CancelError", -1, 0);
            /* Return accepts the preset file */
            sets_c(C("dlg"), "FileName", -1, "RAM:bbtest/ui_bars_test");
            int k2[1] = { K_RETURN };
            keys_later(60, "Bars test dialog", k2, 1);
            e = call0(C("dlg"), "ShowOpen");
            keys_later_wait();
            printf("# ShowOpen: FileName \"%s\" FileCount %d\n", gets_("dlg", "FileName"), geti("dlg", "FileCount"));
            check(e == 0 && geti("dlg", "Cancelled") == 0 && !strcasecmp(gets_("dlg", "FileName"), "RAM:bbtest/ui_bars_test"),
                  "ShowOpen + Return: FileName = the preset file");
            check(!strcmp(gets_("dlg", "FileTitle"), "ui_bars_test"), "FileTitle = the file part");
            check(geti("dlg", "FileCount") == 1 && !strcasecmp(gets_c(C("dlg"), "Files", 0), "RAM:bbtest/ui_bars_test"),
                  "FileCount = 1, Files(0)");
        }
        break;
    case 4:
        if (ready()) {
            /* the colour requester: Return = OK with the colour given */
            seti_c(C("dlg"), "Color", -1, 0x336699);
            int k[1] = { K_RETURN };
            keys_later(60, "Bars test dialog", k, 1);
            int e = call0(C("dlg"), "ShowColor");
            keys_later_wait();
            printf("# ShowColor: Color %06lX Cancelled %d\n", (long)geti("dlg", "Color"), geti("dlg", "Cancelled"));
            check(e == 0 && geti("dlg", "Cancelled") == 0 && geti("dlg", "Color") == 0x336699, "ShowColor + Return keeps the colour");
        }
        break;
    case 5:
        seti_c(C("tick"), "Enabled", -1, 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "bars.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form with a toolbar, a status bar and a commondialog loads");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    check(!strcmp(gets_("tbNew", "Caption"), "New") && !strcmp(gets_("tbNew", "ToolTipText"), "New document"), "tool Caption, ToolTipText");
    check(geti("tbGrid", "Value") == 1, "toggle tool Value = 1 from checked=1");
    seti_c(C("tbGrid"), "Value", -1, 0);
    check(geti("tbGrid", "Value") == 0, "tbGrid.Value = 0");
    check(geti("tb", "ButtonCount") == 4, "tb.ButtonCount = 4 (the separator counts)");
    check(geti("sb", "PanelCount") == 3 && !strcmp(gets_c(C("sb"), "Panel", 1), "Ln 1"), "statusbar PanelCount, Panel(1)");
    check(sets_c(C("sb"), "Panel", 1, "Ln 42") == 0 && !strcmp(gets_c(C("sb"), "Panel", 1), "Ln 42"), "sb.Panel(1) = \"Ln 42\"");
    check(!strcmp(gets_("logo", "Picture"), "TBImages:save"), "image.Picture");
    check(!strcmp(gets_("dlg", "DialogTitle"), "Bars test dialog"), "dlg.DialogTitle from the .afg");
    check(bb_form_show(form) == 0, "Show");
    check(sets_c(C("sb"), "Text", -1, "Working") == 0 && !strcmp(gets_("sb", "Text"), "Working"), "sb.Text on the open window");
    check(geti("tbNew", "Value") == 0 && seti_c(C("tbOpen"), "Enabled", -1, 0) == 0 && geti("tbOpen", "Enabled") == 0,
          "tbOpen.Enabled = False on the open window");
    seti_c(C("tbOpen"), "Enabled", -1, -1);
    sets_c(C("Form"), "Caption", -1, MAIN_TITLE);

    /* a dialog object without a form */
    bb_ctl *d = bb_dialog_new();
    check(d != NULL && sets_c(d, "Filter", -1, "Text files|*.txt;*.doc") == 0 && !strcmp(gets_c(d, "Filter", -1), "Text files|*.txt;*.doc"),
          "bb_dialog_new: a CommonDialog without a form");
    bb_dialog_free(d);

    bb_forms_run();
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
