/* App, Clipboard and Printer as late-bound objects (docs/ui.md sections 6 to 8), and VB's
 * GetSetting / SaveSetting / DeleteSetting. `App.ToolType("X")` compiles to a late-bound call on
 * bb_app_object() when App.ToolType isn't one of the compiler's built-ins (App.Path, App.Title
 * ...), see sema_expr.c. Portable members are here; the rest go to the platform (bb_app.h). */
#include "boing.h"
#include "bb_app.h"
#include "bb_sys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

void bb_fv_from_value(const bb_value *v, bb_fval *fv, bb_str **hold);   /* forms_rt.c */
bb_value bb_value_from_fv(const bb_fval *fv);

enum { O_APP, O_CLIP, O_PRN };

typedef struct appobj {
    bb_obj hdr;
    int which;
} appobj;

static char **anames;
static int32_t nanames, capanames;

static int32_t ainter(const char *s)
{
    int32_t i;
    for (i = 0; i < nanames; i++) if (strcasecmp(anames[i], s) == 0) return i;
    if (nanames == capanames) {
        capanames = capanames ? capanames * 2 : 32;
        anames = (char **)bb_realloc(anames, sizeof(char *) * (size_t)capanames);
    }
    anames[nanames] = strdup(s);
    return nanames++;
}

static int32_t app_find(const bb_class *cls, const char *name)
{
    (void)cls;
    return ainter(name ? name : "");
}

static char *ret_hold;     /* strings the portable members return */

static int ret_s(bb_fval *out, char *owned)
{
    free(ret_hold);
    ret_hold = owned ? owned : strdup("");
    out->type = BB_FV_STR;
    out->s = ret_hold;
    return 0;
}

static int ret_i(bb_fval *out, int32_t v)
{
    out->type = BB_FV_INT;
    out->i = v;
    return 0;
}

static const char *fs(const bb_fval *v, char *buf)
{
    if (v->type == BB_FV_STR) return v->s ? v->s : "";
    if (v->type == BB_FV_INT) { sprintf(buf, "%ld", (long)v->i); return buf; }
    return "";
}

static int fi(const bb_fval *v) { return v->type == BB_FV_INT ? v->i : v->type == BB_FV_STR && v->s ? atoi(v->s) : 0; }

static char *cat3(const char *a, const char *b, const char *c)
{
    size_t n = strlen(a) + strlen(b) + strlen(c) + 1;
    char *o = (char *)malloc(n);
    snprintf(o, n, "%s%s%s", a, b, c);
    return o;
}

/* --- members ------------------------------------------------------------------------------ */

#define IS(a) (!strcasecmp(name, a))

static int app_get(const char *name, int index, bb_fval *out)
{
    if (IS("Path")) return ret_s(out, strdup(bb_sys_app_path()));
    if (IS("EXEName")) return ret_s(out, strdup(bb_sys_app_exename()));
    if (IS("Title")) {
        bb_str *t = bb_app_title();
        char *c = strdup(bb_str_ptr(t));
        bb_str_release(t);
        return ret_s(out, c);
    }
    if (IS("EnvPath")) {
        bb_str *t = bb_app_title();
        char *c = cat3(bb_app_settings_dir(1), bb_str_ptr(t), "");
        bb_str_release(t);
        return ret_s(out, c);
    }
    return bb_app_plat_get(name, index, out);
}

static int app_call(const char *name, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b0[16], b1[16], b2[16];
    if (IS("Request")) {        /* App.Request(prompt, "_A|_B|_C" [, title [, icon]]) */
        if (argc < 2) return 450;
        return ret_i(ret, bb_ui_request(fs(&argv[0], b0), fs(&argv[1], b1),
                                        argc > 2 && argv[2].type != BB_FV_NONE ? fs(&argv[2], b2) : NULL,
                                        argc > 3 ? fi(&argv[3]) : 0));
    }
    return bb_app_plat_call(name, argc, argv, ret);
}

static void obj_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    appobj *o = (appobj *)self;
    const char *name = anames[id];
    bb_fval args[8], out;
    bb_str *holds[8];
    int i, err = 438;
    if (argc > 8) bb_raise(450, NULL);
    for (i = 0; i < argc; i++) {
        holds[i] = NULL;
        if (argv[i].type == BB_ERROR && (argv[i].flags & BB_VF_MISSING)) {
            memset(&args[i], 0, sizeof args[i]);
            args[i].type = BB_FV_NONE;
        } else
            bb_fv_from_value(&argv[i], &args[i], &holds[i]);
    }
    memset(&out, 0, sizeof out);
    if (kind & (BB_INV_LET | BB_INV_SET)) {
        int idx = argc == 2 ? fi(&args[0]) : -1;
        if (argc < 1 || argc > 2) err = 450;
        else if (o->which == O_APP) err = bb_app_plat_set(name, idx, &args[argc - 1]);
        else if (o->which == O_PRN) err = bb_prn_plat_set(name, idx, &args[argc - 1]);
    } else {
        if ((kind & BB_INV_GET) && argc <= 1) {
            int idx = argc == 1 ? fi(&args[0]) : -1;
            if (o->which == O_APP) err = app_get(name, idx, &out);
            else if (o->which == O_PRN) err = bb_prn_plat_get(name, idx, &out);
        }
        if (err == 438 && (kind & BB_INV_METHOD)) {
            memset(&out, 0, sizeof out);
            if (o->which == O_APP) err = app_call(name, argc, args, &out);
            else if (o->which == O_CLIP) err = bb_clip_plat_call(name, argc, args, &out);
            else err = bb_prn_plat_call(name, argc, args, &out);
        }
    }
    for (i = 0; i < argc; i++) bb_str_release(holds[i]);
    if (err) bb_raise(err, NULL);
    if (!(kind & (BB_INV_LET | BB_INV_SET))) *ret = bb_value_from_fv(&out);
}

static const bb_class app_class = {"App", sizeof(appobj), app_find, obj_invoke, NULL, NULL, NULL, 0, NULL, 0, NULL, NULL};
static const bb_class clip_class = {"Clipboard", sizeof(appobj), app_find, obj_invoke, NULL, NULL, NULL, 0, NULL, 0, NULL, NULL};
static const bb_class prn_class = {"Printer", sizeof(appobj), app_find, obj_invoke, NULL, NULL, NULL, 0, NULL, 0, NULL, NULL};

static bb_obj *singletons[3];

static bb_value single(int which)
{
    static const bb_class *const k[3] = { &app_class, &clip_class, &prn_class };
    if (!singletons[which]) {
        appobj *o = (appobj *)bb_obj_new(k[which]);
        o->which = which;
        o->hdr.ref = -1000000;      /* never freed: retain/release keep it negative */
        singletons[which] = &o->hdr;
    }
    return bb_v_obj(singletons[which]);
}

bb_value bb_app_object(void) { return single(O_APP); }
bb_value bb_clipboard_object(void) { return single(O_CLIP); }
bb_value bb_printer_object(void) { return single(O_PRN); }

/* --- events for BASIC from the platform ---------------------------------------------------- */

int bb_app_event(const char *name, int argc, bb_value *argv)
{
    void *p = bb_find_proc(NULL, name);
    int32_t err;
    if (!p) return 0;
    err = bb_call_proc(p, argc, argv, NULL);
    if (err) {
        bb_fatal_error();
        bb_forms_end();
    }
    return 1;
}

/* --- GetSetting / SaveSetting / DeleteSetting ----------------------------------------------- */

/* "<dir><app>/<section>/<key>"; app and section must not be empty (VB error 5) */
static char *setting_path(const char *dir, bb_str *app, bb_str *section, bb_str *key)
{
    const char *a = bb_str_ptr(app), *s = bb_str_ptr(section), *k = key ? bb_str_ptr(key) : "";
    size_t n = strlen(dir) + strlen(a) + strlen(s) + strlen(k) + 4;
    char *o = (char *)malloc(n);
    if (!*a) bb_raise(5, NULL);
    if (*s && *k) snprintf(o, n, "%s%s/%s/%s", dir, a, s, k);
    else if (*s) snprintf(o, n, "%s%s/%s", dir, a, s);
    else snprintf(o, n, "%s%s", dir, a);
    return o;
}

static char *read_all(const char *path)
{
    FILE *f = fopen(path, "rb");
    char *buf;
    long n;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) n = 0;
    buf = (char *)malloc((size_t)n + 1);
    n = (long)fread(buf, 1, (size_t)n, f);
    buf[n] = 0;
    fclose(f);
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = 0;
    return buf;
}

bb_str *bb_getsetting(bb_str *app, bb_str *section, bb_str *key, bb_str *def)
{
    int arch;
    for (arch = 0; arch < 2; arch++) {
        char *p = setting_path(bb_app_settings_dir(arch), app, section, key);
        char *v = read_all(p);
        free(p);
        if (v) {
            bb_str *r = bb_str_from_c(v);
            free(v);
            return r;
        }
    }
    return bb_str_retain(def);
}

static void mkdirs(char *path)
{
    /* every directory of path but the last part */
    char *p;
    for (p = path; *p; p++) {
        if (*p == '/' && p > path && p[-1] != ':') {
            *p = 0;
            bb_sys_mkdir(path);
            *p = '/';
        }
    }
}

void bb_savesetting(bb_str *app, bb_str *section, bb_str *key, bb_str *value)
{
    int arch, ok = 0;
    if (!bb_str_ptr(section)[0] || !bb_str_ptr(key)[0]) bb_raise(5, NULL);
    for (arch = 0; arch < 2; arch++) {
        const char *dir = bb_app_settings_dir(arch);
        char *p = setting_path(dir, app, section, key);
        FILE *f;
        mkdirs(p);
        f = fopen(p, "wb");
        if (f) {
            fputs(bb_str_ptr(value), f);
            fclose(f);
            ok = 1;
        }
        free(p);
        if (!strcmp(dir, bb_app_settings_dir(!arch))) break;    /* hosts: one directory */
    }
    if (!ok) bb_raise(75, NULL);
}

/* delete a directory's files and (one level of) sub-directories, then the directory */
static void remove_tree(const char *dir, int depth)
{
    char *pat = cat3(dir, "/", "*"), *f;
    char **names = NULL;
    int n = 0, i;
    /* collect first: Dir's scan is global */
    for (f = bb_sys_dir_first(pat, 16); f; f = bb_sys_dir_next()) {
        if (!strcmp(f, ".") || !strcmp(f, "..")) {    /* hosts list these with vbDirectory */
            free(f);
            continue;
        }
        names = (char **)bb_realloc(names, sizeof(char *) * (size_t)(n + 1));
        names[n++] = f;
    }
    for (i = 0; i < n; i++) {
        char *full = cat3(dir, "/", names[i]);
        if (bb_sys_getattr(full) >= 0 && (bb_sys_getattr(full) & 16)) {
            if (depth < 2) remove_tree(full, depth + 1);
        } else
            remove(full);
        free(full);
        free(names[i]);
    }
    free(names);
    free(pat);
    bb_sys_rmdir(dir);
}

void bb_deletesetting(bb_str *app, bb_str *section, bb_str *key)
{
    int arch;
    for (arch = 0; arch < 2; arch++) {
        const char *dir = bb_app_settings_dir(arch);
        char *p = setting_path(dir, app, section, bb_str_ptr(key)[0] ? key : NULL);
        if (bb_str_ptr(key)[0]) remove(p);
        else remove_tree(p, 0);       /* a whole section, or the whole application */
        free(p);
        if (!strcmp(dir, bb_app_settings_dir(!arch))) break;
    }
}
