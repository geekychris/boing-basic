/* form_show FILE.afg [SECONDS] - open a form from an .afg file (no code-behind) for SECONDS
 * (default 10), for screenshots. Prints the window's box: "box x y w h". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <proto/exec.h>
#include <proto/dos.h>

#include "bb_forms.h"

/* run from a background CLI (run >NIL:) the default stack is only a few KB */
static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static bb_form *form;
static int secs = 10, ticks;

static int on_event(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    (void)ud; (void)argc; (void)args;
    if (!strcmp(ctl, "_shot") && !strcmp(ev, "Timer") && ++ticks >= secs) bb_form_unload(f);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: form_show FILE.afg [SECONDS]\n");
        return 5;
    }
    if (argc > 2) secs = atoi(argv[2]);
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        printf("can't open %s\n", argv[1]);
        return 10;
    }
    static char text[65536];
    size_t n = fread(text, 1, sizeof text - 200, fp);
    fclose(fp);
    text[n] = 0;
    /* a 1 s timer to close it: the root layout's first child (menus may follow the layout, so
       not at the end) */
    {
        char *root = strstr(text, "\nvlayout");
        if (!root) root = strstr(text, "\nhlayout");
        char *eol = root ? strchr(root + 1, '\n') : NULL;
        static const char t[] = "\n  timer id=_shot interval=1000";
        if (eol) {
            memmove(eol + sizeof t - 1, eol, strlen(eol) + 1);
            memcpy(eol, t, sizeof t - 1);
        } else
            strcat(text, t);
    }
    char err[200];
    form = bb_form_load(text, argv[1], on_event, NULL, NULL, err, sizeof err);
    if (!form) {
        printf("%s\n", err);
        return 10;
    }
    bb_form_show(form);
    int x, y, w, h;
    if (bb_ctl_screen_box(bb_form_self(form), &x, &y, &w, &h)) {
        printf("box %d %d %d %d\n", x, y, w, h);
        FILE *b = fopen("RAM:bbtest/box", "w");
        if (b) {
            fprintf(b, "box %d %d %d %d\n", x, y, w, h);
            fclose(b);
        }
    }
    fflush(stdout);
    bb_forms_run();
    bb_forms_cleanup();
    return 0;
}
