/* Forms on hosts without a GUI implementation: a program that loads a form fails with a
 * clear message; MsgBox and InputBox use the console, so console programs and the test
 * suite run everywhere. */
#include "../bb_forms.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bb_form *bb_form_load(const char *afg_text, const char *file, bb_form_event_fn fn, bb_form_has_event_fn has,
                      void *ud, char *err, int errlen)
{
    (void)afg_text; (void)fn; (void)has; (void)ud;
    snprintf(err, errlen, "%s:1: forms need AmigaOS 4 (no GUI on this platform)", file ? file : "form");
    return NULL;
}

const char *bb_form_name(bb_form *f) { (void)f; return ""; }
int bb_form_show(bb_form *f) { (void)f; return 364; }
int bb_form_hide(bb_form *f) { (void)f; return 364; }
int bb_form_unload(bb_form *f) { (void)f; return 0; }
bb_form *bb_form_find(const char *name) { (void)name; return NULL; }
bb_ctl *bb_form_self(bb_form *f) { (void)f; return NULL; }
bb_ctl *bb_form_ctl(bb_form *f, const char *name) { (void)f; (void)name; return NULL; }
const char *bb_ctl_kind(bb_ctl *c) { (void)c; return ""; }
int bb_ctl_get(bb_ctl *c, const char *p, int i, bb_fval *o) { (void)c; (void)p; (void)i; o->type = BB_FV_NONE; return 364; }
int bb_ctl_set(bb_ctl *c, const char *p, int i, const bb_fval *v) { (void)c; (void)p; (void)i; (void)v; return 364; }
int bb_ctl_call(bb_ctl *c, const char *m, int n, const bb_fval *a, bb_fval *r) { (void)c; (void)m; (void)n; (void)a; (void)r; return 364; }
int bb_forms_run(void) { return 0; }
void bb_forms_end(void) {}
void bb_forms_cleanup(void) {}
void bb_forms_doevents(void) {}
int bb_ctl_screen_box(bb_ctl *c, int *x, int *y, int *w, int *h) { (void)c; (void)x; (void)y; (void)w; (void)h; return 0; }

/* MsgBox on the console: prints the prompt, returns the first button's value (vbOK, vbAbort,
 * vbYes, vbRetry), so programs run unattended in tests. */
int bb_ui_msgbox(const char *prompt, int buttons, const char *title)
{
    static const int first[6] = { 1, 1, 3, 6, 6, 4 };
    (void)title;
    printf("%s\n", prompt);
    fflush(stdout);
    int t = buttons & 7;
    return first[t > 5 ? 0 : t];
}

/* InputBox on the console: the prompt, then a line from stdin (NULL at end of input). */
char *bb_ui_inputbox(const char *prompt, const char *title, const char *def)
{
    (void)title;
    printf("%s", prompt);
    fflush(stdout);
    char buf[1024];
    if (!fgets(buf, sizeof buf, stdin)) return def ? strdup(def) : NULL;
    buf[strcspn(buf, "\r\n")] = 0;
    return strdup(buf);
}
