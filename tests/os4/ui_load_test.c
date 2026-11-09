/* ui_load_test - robustness and the late additions of docs/ui.md: every menu, tool, status bar,
 * grid, tree and list property set in Form_Load (before the window exists: separators and titles
 * included) is kept and nothing crashes; qualifier keys as KeyDown/KeyUp (vbKeyLShift 160,
 * vbKeyRMenu 165); a canvas with fill=1 follows the window size (<id>_Resize); rmb=1 gives the
 * right button to the canvas. TAP lines and PASS/FAIL. */
#define MAIN_TITLE "Boing load test - running"
#include "test_inject.h"
#include "bb_forms.h"
#include "canvas.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing load test\" width=360 height=260\n"
    "vlayout id=root\n"
    "  toolbar id=tb weight=0\n"
    "    tool id=t1 text=\"New\" image=\"TBImages:new\" menu=mNew\n"
    "    tool id=t2 text=\"Grid\" toggle=1\n"
    "    tool id=t3 text=\"Gone\" image=\"TBImages:no_such_image_here\"\n"
    "  canvas id=view width=100 height=50 fill=1 rmb=1 contextmenu=ctx\n"
    "  hlayout weight=0\n"
    "    grid id=g rows=5 cols=3 minheight=60\n"
    "    treeview id=tv\n"
    "    listbrowser id=lb columns=\"A|B\" items=\"x\t1|y\t2\"\n"
    "  statusbar id=sb panels=\"a|b\"\n"
    "  timer id=tick interval=400\n"
    "  timer id=guard interval=120000\n"
    "menu id=mFile text=\"File\"\n"
    "  menu id=mNew text=\"New\" key=N\n"
    "  menu id=mSep text=-\n"
    "  menu id=mR1 text=\"One\" radio=1 checked=1\n"
    "  menu id=mR2 text=\"Two\" radio=1\n"
    "  menu id=mQuit text=\"Quit\"\n"
    "menu id=ctx text=\"Ctx\" hidden=1\n"
    "  menu id=c1 text=\"Clear\"\n";

static bb_form *form;
static bb_obj *cv;
static int step, resizes, kd = -1, ku = -1, cdown = -1;

static bb_ctl *C(const char *n) { return strcasecmp(n, "Form") ? bb_form_ctl(form, n) : bb_form_self(form); }
static int geti(const char *c, const char *p, int i) { bb_fval v; return bb_ctl_get(C(c), p, i, &v) ? -9999 : v.i; }
static const char *gets_(const char *c, const char *p, int i)
{
    static char b[256];
    bb_fval v;
    if (bb_ctl_get(C(c), p, i, &v)) return "<error>";
    snprintf(b, sizeof b, "%s", v.s ? v.s : "");
    return b;
}
static int seti(bb_form *f, const char *c, const char *p, int i, int x)
{
    bb_fval v = { BB_FV_INT, x, NULL, NULL };
    return bb_ctl_set(strcasecmp(c, "Form") ? bb_form_ctl(f, c) : bb_form_self(f), p, i, &v);
}
static int sets(bb_form *f, const char *c, const char *p, int i, const char *x)
{
    bb_fval v = { BB_FV_STR, 0, x, NULL };
    return bb_ctl_set(strcasecmp(c, "Form") ? bb_form_ctl(f, c) : bb_form_self(f), p, i, &v);
}

static void on_load(bb_form *f)
{
    /* everything, before the window exists */
    static const char *const menus[] = { "mFile", "mNew", "mSep", "mR1", "mR2", "mQuit", "ctx", "c1" };
    for (unsigned i = 0; i < 8; i++) {
        seti(f, menus[i], "Checked", -1, -1);
        seti(f, menus[i], "Enabled", -1, 0);
        seti(f, menus[i], "Enabled", -1, -1);
        sets(f, menus[i], "Shortcut", -1, "K");
        seti(f, menus[i], "Visible", -1, 0);
        seti(f, menus[i], "Visible", -1, -1);
        seti(f, menus[i], "Checkable", -1, -1);
    }
    sets(f, "mSep", "Caption", -1, "ignored");
    sets(f, "mQuit", "Caption", -1, "Quit now");
    seti(f, "mR1", "Checked", -1, 0);
    seti(f, "t1", "Enabled", -1, 0);
    seti(f, "t2", "Value", -1, 0);
    sets(f, "t1", "Caption", -1, "Neu");
    sets(f, "t1", "ToolTipText", -1, "tip");
    sets(f, "sb", "Panel", 1, "b2");
    sets(f, "sb", "Text", -1, "a2");
    sets(f, "view", "ContextMenu", -1, "ctx");
    bb_fval v = { BB_FV_STR, 0, "cell", NULL };
    bb_ctl_set2(bb_form_ctl(f, "g"), "TextMatrix", 1, 1, &v);
    bb_fval a[3] = { { BB_FV_STR, 0, "k", NULL }, { BB_FV_STR, 0, "", NULL }, { BB_FV_STR, 0, "Node", NULL } }, r;
    bb_ctl_call(bb_form_ctl(f, "tv"), "AddNode", 3, a, &r);
    seti(f, "lb", "ItemData", 1, 7);
    bb_fval am[3] = { { BB_FV_STR, 0, "mAdded", NULL }, { BB_FV_STR, 0, "Added", NULL }, { BB_FV_STR, 0, "mFile", NULL } };
    bb_ctl_call(bb_form_self(f), "AddMenu", 3, am, &r);
    seti(f, "mAdded", "Checked", -1, -1);
}

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
    (void)ud; (void)argc;
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "Load")) on_load(f);
    if (!strcasecmp(ctl, "view") && !strcasecmp(ev, "Resize")) resizes++;
    if (!strcasecmp(ctl, "view") && !strcasecmp(ev, "MouseDown")) cdown = args[0];
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "KeyDown")) kd = args[0];
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "KeyUp")) ku = args[0];
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) script();
    return 0;
}

static int w0, h0, cx, cy, cw, ch;
static void script(void)
{
    switch (step++) {
    case 0: {
        int s;
        bb_canvas_ctl_geometry(C("view"), &w0, &h0, &s);
        bb_ctl_screen_box(C("view"), &cx, &cy, &cw, &ch);
        printf("# canvas %dx%d in a %dx%d box, %d Resize events\n", w0, h0, cw, ch, resizes);
        check(w0 == cw && h0 == ch && resizes >= 1, "fill=1: the canvas picture has the control's size (view_Resize)");
        check(w0 > 100, "it grew beyond its .afg width");
        {
            int sx, sy, sw, sh, tx, ty, tw, th;
            bb_ctl_screen_box(C("sb"), &sx, &sy, &sw, &sh);
            bb_ctl_screen_box(C("tb"), &tx, &ty, &tw, &th);
            printf("# status bar height %d, toolbar height %d, canvas height %d\n", sh, th, ch);
            check(sh > 0 && sh < 40 && th > 0 && th < 60, "the status bar and the toolbar keep their own height");
            check(ch > sh * 2, "the canvas gets the rest of the window");
        }
        seti(form, "Form", "Width", -1, geti("Form", "Width", -1) + 60);
        break;
    }
    case 1: {
        int w, h, s;
        bb_canvas_ctl_geometry(C("view"), &w, &h, &s);
        printf("# after a wider window: %dx%d\n", w, h);
        check(w >= w0 + 40, "a wider window makes the canvas wider");
        key_q(0x60, IEQUALIFIER_LSHIFT);           /* left Shift */
        break;
    }
    case 2:
        printf("# KeyDown %d KeyUp %d\n", kd, ku);
        check(kd == 160 && ku == 160, "left Shift: Form_KeyDown/KeyUp(vbKeyLShift = 160)");
        key_q(0x65, IEQUALIFIER_RALT);            /* right Alt */
        break;
    case 3:
        check(kd == 165, "right Alt: Form_KeyDown(vbKeyRMenu = 165)");
        if (ready_mouse() && bb_ctl_screen_box(C("view"), &cx, &cy, &cw, &ch)) {
            pointer(cx + cw / 2, cy + ch / 2);
            IDOS->Delay(5);
            pointer(cx + cw / 2 + 2, cy + ch / 2 + 1);   /* a move: the trap goes on */
            IDOS->Delay(5);
        } else step = 6;
        break;
    case 4:
        mbutton(IECODE_RBUTTON, 0);
        IDOS->Delay(3);
        mbutton(IECODE_RBUTTON, 1);
        break;
    case 5:
        check(cdown == 2, "rmb=1: the right button over the canvas is view_MouseDown(2), no menu");
        break;
    case 6:
        seti(form, "tick", "Enabled", -1, 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "load.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads with every property set in Form_Load");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    cv = bb_canvas_new(100, 50, C("view"));
    check(geti("mNew", "Checked", -1) == -1 && geti("mSep", "Checked", -1) == -1, "menu Checked kept (item and separator)");
    check(!strcmp(gets_("mSep", "Caption", -1), "-") && !strcmp(gets_("mQuit", "Caption", -1), "Quit now"), "separator Caption stays \"-\", items take theirs");
    check(geti("mR1", "Checked", -1) == 0 && geti("mAdded", "Checked", -1) == -1, "radio and run-time menu Checked");
    check(geti("t1", "Enabled", -1) == 0 && !strcmp(gets_("t1", "Caption", -1), "Neu"), "tool properties kept");
    check(!strcmp(gets_("t3", "Caption", -1), "Gone"), "a tool whose picture file is missing is a text tool");
    check(!strcmp(gets_("sb", "Panel", 1), "b2") && !strcmp(gets_("sb", "Text", -1), "a2"), "status bar panels kept");
    check(geti("lb", "ItemData", 1) == 7 && geti("tv", "NodeCount", -1) == 1, "list and tree contents kept");
    check(bb_form_show(form) == 0, "the window opens");
    check(geti("mNew", "Checked", -1) == -1 && !strcmp(gets_("t1", "Caption", -1), "Neu"), "and the states are still there");
    bb_fval cap = { BB_FV_STR, 0, MAIN_TITLE, NULL };
    bb_ctl_set(C("Form"), "Caption", -1, &cap);
    bb_forms_run();
    bb_obj_release(cv);
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
