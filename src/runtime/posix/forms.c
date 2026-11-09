/* Forms on hosts without a GUI implementation: a program that loads a form fails with a
 * clear message; MsgBox and InputBox use the console, so console programs and the test
 * suite run everywhere. */
#define _POSIX_C_SOURCE 200809L   /* clock_gettime, nanosleep, strdup (headless forms) */
#include "../bb_forms.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------------------------------------------------------- headless forms
 *
 * With BOING_HEADLESS=1 forms run without a display: the .afg is parsed, every control keeps
 * its properties (Text, Caption, Value, ListIndex, List(), Enabled, Visible, Tag ...), events
 * fire as on AmigaOS (Form_Load during the load, Activate and Resize on Show, Click/Change when
 * code sets ListIndex/Value/Text, the QueryUnload/Unload pair), timers fire in real time, and
 * the event loop ends when the last form is unloaded or after BOING_HEADLESS_SECS seconds
 * (default 10). Canvases draw into their pictures as always (they just aren't shown). So a form
 * program's own test modes (--smoke ...) run on the host, under sanitizers too. Without the
 * variable a program that loads a form fails with the message below, as before. */
#include "../afg.h"
#include <strings.h>
#include <time.h>

struct bb_ctl {
    bb_form *form;
    char *name;
    afg_kind kind;
    int enabled, visible;
    int32_t value, min, max, interval, left, top, width, height;
    char *text, *tag;
    char **items;
    int nitems, listindex, timer_on;
    double next_fire;
};

struct bb_form {
    char *name;
    bb_ctl self;
    bb_ctl **ctls;
    int nctls, loaded, unloading;
    bb_form_event_fn fn;
    bb_form_has_event_fn has;
    void *ud;
    char *ret;                      /* the last string handed out */
    bb_form *next;
};

static bb_form *hl_forms;
static int hl_ending;

static int headless(void)
{
    const char *e = getenv("BOING_HEADLESS");
    return e && *e && strcmp(e, "0") != 0;
}

static double now_s(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + t.tv_nsec / 1e9;
}

static char *xdup(const char *s) { char *d = strdup(s ? s : ""); if (!d) abort(); return d; }

static int hl_fire(bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    if (!f->fn || hl_ending) return 0;
    if (f->fn(f->ud, f, ctl, ev, argc, args)) { hl_ending = 1; return 1; }
    return 0;
}

static void set_items(bb_ctl *c, const char *list)
{
    const char *p = list;
    while (p && *p) {
        const char *q = strchr(p, '|');
        size_t n = q ? (size_t)(q - p) : strlen(p);
        char *it = (char *)malloc(n + 1);
        memcpy(it, p, n);
        it[n] = 0;
        c->items = (char **)realloc(c->items, sizeof(char *) * (size_t)(c->nitems + 1));
        c->items[c->nitems++] = it;
        p = q ? q + 1 : NULL;
    }
}

static void add_ctl(afg_node *n, void *ud)
{
    bb_form *f = (bb_form *)ud;
    const char *id = afg_get(n, "id");
    bb_ctl *c;
    if (n->kind == AFG_WINDOW || !id || !*id) return;
    c = (bb_ctl *)calloc(1, sizeof *c);
    c->form = f;
    c->name = xdup(id);
    c->kind = n->kind;
    c->enabled = !afg_get_bool(n, "disabled");
    c->visible = !afg_get_bool(n, "hidden");
    c->text = xdup(afg_get(n, "text"));
    c->tag = xdup("");
    c->min = afg_get_int(n, "min");
    c->max = afg_get_int(n, "max");
    c->width = afg_get_int(n, "width");
    c->height = afg_get_int(n, "height");
    c->listindex = -1;
    switch (n->kind) {
    case AFG_CHECKBOX: c->value = afg_get_int(n, "checked"); break;
    case AFG_SLIDER: case AFG_FUELGAUGE: c->value = afg_get_int(n, "level"); break;
    case AFG_INTEGER: c->value = afg_get_int(n, "value"); break;
    case AFG_SCROLLER: c->value = afg_get_int(n, "top"); c->max = afg_get_int(n, "total"); break;
    case AFG_CHOOSER: case AFG_RADIO: case AFG_LISTBROWSER:
        set_items(c, afg_get(n, "items"));
        if (n->kind != AFG_LISTBROWSER) c->listindex = afg_get_int(n, "selected");
        break;
    case AFG_TIMER:
        c->interval = afg_get_int(n, "interval");
        c->timer_on = afg_get_bool(n, "enabled");
        c->next_fire = now_s() + c->interval / 1000.0;
        break;
    case AFG_MENU: c->value = afg_get_int(n, "checked"); break;
    default: break;
    }
    f->ctls = (bb_ctl **)realloc(f->ctls, sizeof(bb_ctl *) * (size_t)(f->nctls + 1));
    f->ctls[f->nctls++] = c;
}

bb_form *bb_form_load(const char *afg_text, const char *file, bb_form_event_fn fn, bb_form_has_event_fn has,
                      void *ud, char *err, int errlen)
{
    afg_node *root;
    bb_form *f;
    if (!headless()) {
        (void)afg_text; (void)fn; (void)has; (void)ud;
        snprintf(err, errlen, "%s:1: forms need AmigaOS 4 (no GUI on this platform; BOING_HEADLESS=1 runs them without one)",
                 file ? file : "form");
        return NULL;
    }
    root = afg_parse(afg_text, err, errlen);
    if (!root) return NULL;
    f = (bb_form *)calloc(1, sizeof *f);
    f->name = xdup(afg_get(root, "name"));
    f->self.form = f;
    f->self.name = xdup("Form");
    f->self.kind = AFG_WINDOW;
    f->self.enabled = 1;
    f->self.text = xdup(afg_get(root, "title"));
    f->self.tag = xdup("");
    f->self.width = afg_get_int(root, "width");
    f->self.height = afg_get_int(root, "height");
    f->fn = fn;
    f->has = has;
    f->ud = ud;
    f->loaded = 1;
    afg_walk(root, add_ctl, f);
    afg_free(root);
    f->next = hl_forms;
    hl_forms = f;
    hl_fire(f, "Form", "Load", 0, NULL);
    return f;
}

const char *bb_form_name(bb_form *f) { return f ? f->name : ""; }

int bb_form_show(bb_form *f)
{
    if (!f || !f->loaded) return 364;
    if (f->self.visible) return 0;
    f->self.visible = 1;
    hl_fire(f, "Form", "Activate", 0, NULL);
    hl_fire(f, "Form", "Resize", 0, NULL);
    return 0;
}

int bb_form_hide(bb_form *f)
{
    if (!f || !f->loaded) return 364;
    f->self.visible = 0;
    return 0;
}

int bb_form_unload(bb_form *f)
{
    int32_t a[2] = { 0, 1 };
    if (!f || !f->loaded || f->unloading) return 0;
    f->unloading = 1;
    hl_fire(f, "Form", "QueryUnload", 2, a);
    if (!a[0]) hl_fire(f, "Form", "Unload", 1, a);
    f->unloading = 0;
    if (a[0] && !hl_ending) return 1;
    f->self.visible = 0;
    f->loaded = 0;
    return 0;
}

bb_form *bb_form_find(const char *name)
{
    bb_form *f;
    for (f = hl_forms; f; f = f->next)
        if (f->loaded && name && !strcasecmp(f->name, name)) return f;
    return NULL;
}

bb_ctl *bb_form_self(bb_form *f) { return f ? &f->self : NULL; }

bb_ctl *bb_form_ctl(bb_form *f, const char *name)
{
    int i;
    if (!f || !name || !*name) return NULL;
    for (i = 0; i < f->nctls; i++)
        if (!strcasecmp(f->ctls[i]->name, name)) return f->ctls[i];
    return NULL;
}

const char *bb_ctl_kind(bb_ctl *c) { return c ? afg_kind_name(c->kind) : ""; }

#define IS(x) (!strcasecmp(prop, x))

static int ret_int(bb_fval *o, int32_t v) { o->type = BB_FV_INT; o->i = v; return 0; }
static int ret_str(bb_ctl *c, bb_fval *o, const char *s)
{
    free(c->form->ret);
    c->form->ret = xdup(s);
    o->type = BB_FV_STR;
    o->s = c->form->ret;
    return 0;
}
static int is_list(bb_ctl *c) { return c->kind == AFG_CHOOSER || c->kind == AFG_RADIO || c->kind == AFG_LISTBROWSER; }

int bb_ctl_get(bb_ctl *c, const char *prop, int i, bb_fval *o)
{
    o->type = BB_FV_NONE;
    if (!headless() || !c) return 364;
    if (!c->form->loaded && c->kind != AFG_WINDOW) return 364;
    if (IS("Name")) return ret_str(c, o, c->kind == AFG_WINDOW ? c->form->name : c->name);
    if (IS("Tag")) return ret_str(c, o, c->tag);
    if (IS("Enabled")) return ret_int(o, c->enabled ? -1 : 0);
    if (IS("Visible")) return ret_int(o, c->visible ? -1 : 0);
    if (IS("Left")) return ret_int(o, c->left);
    if (IS("Top")) return ret_int(o, c->top);
    if (IS("Width")) return ret_int(o, c->width);
    if (IS("Height")) return ret_int(o, c->height);
    if (IS("Caption") || IS("Text") || IS("FileName")) {
        if (is_list(c) && IS("Text")) return ret_str(c, o, c->listindex >= 0 && c->listindex < c->nitems ? c->items[c->listindex] : "");
        if (c->kind == AFG_INTEGER && IS("Text")) { char b[16]; snprintf(b, sizeof b, "%d", (int)c->value); return ret_str(c, o, b); }
        return ret_str(c, o, c->text);
    }
    if (IS("Value") || IS("Checked")) {
        if (c->kind == AFG_RADIO) return ret_int(o, c->listindex);
        if (c->kind == AFG_MENU) return ret_int(o, c->value ? -1 : 0);
        return ret_int(o, c->value);
    }
    if (IS("Min")) return ret_int(o, c->min);
    if (IS("Max")) return ret_int(o, c->max);
    if (IS("Interval")) return ret_int(o, c->interval);
    if (IS("WindowState")) return ret_int(o, 0);
    if (is_list(c)) {
        if (IS("ListIndex")) return ret_int(o, c->listindex);
        if (IS("ListCount")) return ret_int(o, c->nitems);
        if (IS("List")) return (i >= 0 && i < c->nitems) ? ret_str(c, o, c->items[i]) : 381;
        if (IS("TopIndex")) return ret_int(o, 0);
    }
    return 438;
}

static int fv_int(const bb_fval *v) { return v->type == BB_FV_STR ? atoi(v->s ? v->s : "0") : v->i; }

int bb_ctl_set(bb_ctl *c, const char *prop, int i, const bb_fval *v)
{
    if (!headless() || !c) return 364;
    if (!c->form->loaded && c->kind != AFG_WINDOW) return 364;
    if (IS("Tag")) { free(c->tag); c->tag = xdup(v->type == BB_FV_STR ? v->s : ""); return 0; }
    if (IS("Enabled")) { c->enabled = fv_int(v) != 0; if (c->kind == AFG_TIMER) c->timer_on = c->enabled, c->next_fire = now_s() + c->interval / 1000.0; return 0; }
    if (IS("Visible")) { c->visible = fv_int(v) != 0; if (c->kind == AFG_WINDOW) return c->visible ? bb_form_show(c->form) : bb_form_hide(c->form); return 0; }
    if (IS("Width") || IS("Height") || IS("Left") || IS("Top")) {
        if (c->kind != AFG_WINDOW) return 383;
        if (IS("Width")) c->width = fv_int(v); else if (IS("Height")) c->height = fv_int(v);
        else if (IS("Left")) c->left = fv_int(v); else c->top = fv_int(v);
        return 0;
    }
    if (IS("Caption") || IS("Text") || IS("FileName")) {
        char buf[16];
        const char *s = v->type == BB_FV_STR ? v->s : (snprintf(buf, sizeof buf, "%d", (int)v->i), buf);
        if (c->kind == AFG_INTEGER) { c->value = atoi(s); return 0; }
        free(c->text);
        c->text = xdup(s);
        if (c->kind == AFG_STRING && IS("Text")) hl_fire(c->form, c->name, "Change", 0, NULL);
        return 0;
    }
    if (IS("Value") || IS("Checked")) {
        int32_t n = fv_int(v);
        if (c->kind == AFG_RADIO) { c->listindex = n; hl_fire(c->form, c->name, "Click", 0, NULL); return 0; }
        if (c->kind == AFG_MENU) { c->value = n != 0; return 0; }
        c->value = n;
        /* as on AmigaOS: code setting Value fires the event even when it doesn't change */
        if (c->kind == AFG_CHECKBOX) hl_fire(c->form, c->name, "Click", 0, NULL);
        else if (c->kind == AFG_SLIDER || c->kind == AFG_SCROLLER) hl_fire(c->form, c->name, "Change", 0, NULL);
        return 0;
    }
    if (IS("Min")) { c->min = fv_int(v); return 0; }
    if (IS("Max")) { c->max = fv_int(v); return 0; }
    if (IS("Interval")) { c->interval = fv_int(v); c->next_fire = now_s() + c->interval / 1000.0; return 0; }
    if (IS("ToolTipText") || IS("MousePointer") || IS("WindowState") || IS("OLEDropMode") || IS("ContextMenu")) return 0;
    if (is_list(c)) {
        if (IS("ListIndex")) {
            int32_t n = fv_int(v);
            if (n < -1 || n >= c->nitems || (n == -1 && c->kind != AFG_LISTBROWSER)) return 380;
            c->listindex = n;
            hl_fire(c->form, c->name, "Click", 0, NULL);
            return 0;
        }
        if (IS("List")) {
            if (i < 0 || i >= c->nitems) return 381;
            free(c->items[i]);
            c->items[i] = xdup(v->type == BB_FV_STR ? v->s : "");
            return 0;
        }
        if (IS("TopIndex")) return 0;
    }
    return 438;
}

int bb_ctl_call(bb_ctl *c, const char *prop, int n, const bb_fval *a, bb_fval *r)
{
    if (!headless() || !c) return 364;
    r->type = BB_FV_NONE;
    if (IS("Show")) return bb_form_show(c->form);
    if (IS("Hide")) return bb_form_hide(c->form);
    if (IS("SetFocus") || IS("Refresh") || IS("Move") || IS("PopupMenu") || IS("ShowOpen")) return 0;
    if (is_list(c)) {
        if (IS("AddItem")) {
            int at = (n > 1 && a[1].type != BB_FV_NONE) ? fv_int(&a[1]) : c->nitems, k;
            if (at < 0 || at > c->nitems) return 5;
            c->items = (char **)realloc(c->items, sizeof(char *) * (size_t)(c->nitems + 1));
            for (k = c->nitems; k > at; k--) c->items[k] = c->items[k - 1];
            c->items[at] = xdup(n > 0 && a[0].type == BB_FV_STR ? a[0].s : "");
            c->nitems++;
            return 0;
        }
        if (IS("RemoveItem")) {
            int at = n > 0 ? fv_int(&a[0]) : -1, k;
            if (at < 0 || at >= c->nitems) return 5;
            free(c->items[at]);
            for (k = at; k < c->nitems - 1; k++) c->items[k] = c->items[k + 1];
            c->nitems--;
            if (c->listindex >= c->nitems) c->listindex = c->nitems - 1;
            return 0;
        }
        if (IS("Clear")) {
            int k;
            for (k = 0; k < c->nitems; k++) free(c->items[k]);
            c->nitems = 0;
            c->listindex = -1;
            return 0;
        }
    }
    return 438;
}

#undef IS

/* run the timers until the last form is unloaded, End, or the time limit */
int bb_forms_run(void)
{
    const char *lim = getenv("BOING_HEADLESS_SECS");
    double end = now_s() + (lim && *lim ? atof(lim) : 10.0);
    if (!headless()) return 0;
    while (!hl_ending) {
        bb_form *f;
        int any = 0;
        double t = now_s();
        if (t >= end) break;
        for (f = hl_forms; f && !hl_ending; f = f->next) {
            int i;
            if (!f->loaded) continue;
            any = 1;
            for (i = 0; i < f->nctls && f->loaded && !hl_ending; i++) {
                bb_ctl *c = f->ctls[i];
                if (c->kind == AFG_TIMER && c->timer_on && c->enabled && c->interval > 0 && t >= c->next_fire) {
                    c->next_fire = t + c->interval / 1000.0;
                    hl_fire(f, c->name, "Timer", 0, NULL);
                }
            }
        }
        if (!any) break;
        {
            struct timespec ts = { 0, 5000000 };
            nanosleep(&ts, NULL);
        }
    }
    return 0;
}

int bb_ctl_os_window(bb_ctl *c, void **window, int *x, int *y, int *w, int *h)    /* canvas */
{
    (void)c; (void)window; (void)x; (void)y; (void)w; (void)h;
    return 0;
}
void bb_forms_end(void) { hl_ending = 1; }
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

/* docs/ui.md on hosts without a GUI: the first button, no CommonDialog object */
int bb_ui_request(const char *prompt, const char *buttons, const char *title, int icon)
{
    (void)buttons; (void)title; (void)icon;
    printf("%s\n", prompt ? prompt : "");
    fflush(stdout);
    return 1;
}

bb_ctl *bb_dialog_new(void) { return NULL; }
void bb_dialog_free(bb_ctl *c) { (void)c; }
int bb_ctl_get2(bb_ctl *c, const char *p, int i, int j, bb_fval *o) { (void)c; (void)p; (void)i; (void)j; o->type = BB_FV_NONE; return 364; }
int bb_ctl_set2(bb_ctl *c, const char *p, int i, int j, const bb_fval *v) { (void)c; (void)p; (void)i; (void)j; (void)v; return 364; }
int bb_form_show_modal(bb_form *f) { (void)f; return 364; }
