/* ui_mouse_test - mouse events of a canvas (docs/ui.md section 4): MouseDown / MouseMove /
 * MouseUp with canvas coordinates (a scale=2 canvas, centred in a bigger box), DblClick, and
 * Form_MouseDown outside the canvas. Input injected only while the window is active and in
 * front. Prints TAP-like lines and PASS/FAIL. */
#define MAIN_TITLE "Boing mouse test - running"
#include "test_inject.h"
#include "bb_forms.h"
#include "canvas.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing mouse test\" width=360 height=200\n"
    "vlayout id=root\n"
    "  canvas id=view width=100 height=60 scale=2\n"
    "  space id=gap minheight=30\n"
    "  timer id=tick interval=400\n"
    "  timer id=guard interval=120000\n";

static bb_form *form;
static int step;
static int downs, ups, moves, dbl, fdowns;
static int32_t last[4], lastmove[4], lastup[4];

static bb_ctl *C(const char *name) { return strcasecmp(name, "Form") ? bb_form_ctl(form, name) : bb_form_self(form); }

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
    (void)ud; (void)f;
    if (!strcasecmp(ctl, "view")) {
        if (!strcasecmp(ev, "MouseDown")) { downs++; memcpy(last, args, sizeof last); }
        if (!strcasecmp(ev, "MouseMove")) { moves++; memcpy(lastmove, args, sizeof lastmove); }
        if (!strcasecmp(ev, "MouseUp")) { ups++; memcpy(lastup, args, sizeof lastup); }
        if (!strcasecmp(ev, "DblClick")) dbl++;
    }
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "MouseDown")) fdowns++;
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) script();
    (void)argc;
    return 0;
}

static int bx, by, bw, bh;
/* screen position of canvas pixel (x, y): the 200x120 picture is centred in the box */
static int sx(int x) { return bx + (bw - 200) / 2 + x * 2 + 1; }
static int sy(int y) { return by + (bh - 120) / 2 + y * 2 + 1; }

static void script(void)
{
    switch (step++) {
    case 0:
        if (!ready_mouse() || !bb_ctl_screen_box(C("view"), &bx, &by, &bw, &bh)) { step = 4; break; }
        printf("# canvas box %d,%d %dx%d\n", bx, by, bw, bh);
        pointer(sx(10), sy(10));
        IDOS->Delay(2);
        mbutton(IECODE_LBUTTON, 0);
        for (int i = 1; i <= 5; i++) { pointer(sx(10 + 2 * i), sy(10 + i)); IDOS->Delay(1); }
        mbutton(IECODE_LBUTTON, 1);
        break;
    case 1:
        printf("# down %ld,%ld,%ld,%ld move %ld,%ld,%ld,%ld up %ld,%ld,%ld,%ld moves %d\n", (long)last[0], (long)last[1],
               (long)last[2], (long)last[3], (long)lastmove[0], (long)lastmove[1], (long)lastmove[2], (long)lastmove[3],
               (long)lastup[0], (long)lastup[1], (long)lastup[2], (long)lastup[3], moves);
        check(downs == 1 && last[0] == 1 && last[2] == 10 && last[3] == 10, "view_MouseDown(vbLeftButton, 0, 10, 10)");
        check(moves >= 1 && lastmove[0] == 1 && lastmove[2] == 20 && lastmove[3] == 15, "view_MouseMove while dragging, last at 20, 15");
        check(ups == 1 && lastup[2] == 20 && lastup[3] == 15, "view_MouseUp at 20, 15");
        if (ready_mouse()) {
            pointer(sx(50), sy(30));
            mbutton(IECODE_LBUTTON, 0);
            mbutton(IECODE_LBUTTON, 1);
            mbutton(IECODE_LBUTTON, 0);
            mbutton(IECODE_LBUTTON, 1);
        }
        break;
    case 2:
        check(dbl == 1, "two quick clicks fire view_DblClick");
        {
            int lx, ly, lw, lh;
            if (ready_mouse() && bb_ctl_screen_box(C("gap"), &lx, &ly, &lw, &lh)) click_at(lx + lw / 2, ly + lh / 2);
        }
        break;
    case 3:
        check(fdowns >= 1, "a click outside the canvas fires Form_MouseDown");
        break;
    case 4:
        bb_ctl_set(C("tick"), "Enabled", -1, &(bb_fval){ BB_FV_INT, 0, NULL });
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "mouse.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    bb_obj *cv = bb_canvas_new(100, 60, C("view"));
    bb_canvas_set_scale(cv, 2);
    check(bb_form_show(form) == 0, "Show");
    bb_ctl_set(C("Form"), "Caption", -1, &(bb_fval){ BB_FV_STR, 0, MAIN_TITLE });
    bb_forms_run();
    bb_obj_release(cv);
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
