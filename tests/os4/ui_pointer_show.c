/* ui_pointer_show [SECONDS] - a window with a crosshair canvas (mousepointer=2) and a plain
 * area; the pointer is moved over the canvas (only while this window is active in front) and the
 * window stays open SECONDS (default 8) for a screenshot of the pointer. */
#define MAIN_TITLE "Boing pointer show"
#include "test_inject.h"
#include "bb_forms.h"
#include "canvas.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";
static bb_form *form;
static int ticks, secs = 8;   /* a guard: the timer quits after secs */

static int ev(void *ud, bb_form *f, const char *ctl, const char *e, int argc, int32_t *args)
{
    (void)ud; (void)argc; (void)args;
    if (strcasecmp(ctl, "tick") || strcasecmp(e, "Timer")) return 0;
    if (++ticks == 2) {
        int x, y, w, h;
        if (ready_mouse() && bb_ctl_screen_box(bb_form_ctl(f, "view"), &x, &y, &w, &h)) {
            pointer(x + w / 2 - 3, y + h / 2 - 3);
            IDOS->Delay(5);
            pointer(x + w / 2, y + h / 2);
            printf("pointer over the canvas at %d,%d\n", x + w / 2, y + h / 2);
        }
    }
    if (ticks == 4) {
        bb_fval v;
        bb_ctl_get(bb_form_self(f), "PointerType", -1, &v);
        printf("PointerType %ld\n", (long)v.i);
    }
    /* run-time MousePointer changes (pen, rubber, select, cross) before quitting: bb-app-paint's
       crash at exit */
    if (ticks == secs * 2 - 4 || ticks == secs * 2 - 3 || ticks == secs * 2 - 2) {
        static const int p[3] = { 135, 137, 138 };
        bb_fval v = { BB_FV_INT, p[ticks - (secs * 2 - 4)], NULL, NULL };
        bb_ctl_set(bb_form_ctl(f, "view"), "MousePointer", -1, &v);
        printf("MousePointer = %ld\n", (long)v.i);
        int x, y, w, h;       /* a move over the canvas, so the new pointer is set on the window */
        if (ready_mouse() && bb_ctl_screen_box(bb_form_ctl(f, "view"), &x, &y, &w, &h)) pointer(x + w / 2 + (ticks & 1), y + h / 2);
    }
    if (ticks >= secs * 2) bb_form_unload(f);
    return 0;
}

int main(int argc, char **argv)
{
    char err[200];
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc > 1) secs = atoi(argv[1]);
    if (!inject_open()) return 20;
    form = bb_form_load("window name=main title=\"Boing pointer show\" width=320 height=200\n"
                        "vlayout id=root\n"
                        "  canvas id=view width=200 height=120 mousepointer=2\n"
                        "  label text=\"The pointer is a crosshair over the canvas\"\n"
                        "  timer id=tick interval=500\n", "ptr.afg", ev, NULL, NULL, err, sizeof err);
    if (!form) { printf("%s\n", err); return 20; }
    bb_obj *cv = bb_canvas_new(200, 120, bb_form_ctl(form, "view"));
    bb_form_show(form);
    bb_forms_run();
    bb_obj_release(cv);
    bb_forms_cleanup();
    inject_close();
    printf("ok 1 - closed after run-time MousePointer changes\nPASS (1/1)\n");
    return 0;
}
