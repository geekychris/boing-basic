/* ini.c - Boing.IniFile, INI / preferences files (docs/ini.md):
 *
 *     Dim prefs As IniFile
 *     Set prefs = CreateObject("IniFile")
 *     prefs.Load "PROGDIR:game.ini"            ' a missing file is an empty one
 *     w = CLng(prefs.Value("Video", "Width", "640"))
 *     prefs.Value("Video", "Width") = 800
 *     prefs.Save
 *
 * The file is kept as its lines, so Save writes back comments, blank lines and the order of
 * everything the program didn't change. Section and key names are not case-sensitive. Keys
 * before the first [section] are in the section "". */
#include "boing.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum { L_OTHER, L_SECTION, L_KEY };

typedef struct {
    int kind;
    char *text;                 /* the line as in the file (L_OTHER), or NULL */
    char *name;                 /* section name (L_SECTION) / key (L_KEY) */
    char *value;                /* L_KEY */
    int section;                /* L_KEY: index of its section line, -1 for the "" section */
} iline;

enum {
    M_LOAD = 1, M_LOADTEXT, M_SAVE, M_VALUE, M_SECTIONS, M_KEYS, M_HASSECTION, M_HASKEY, M_DELETEKEY,
    M_DELETESECTION, M_CLEAR, P_PATH, P_TEXT, P_CHANGED,
};
static const struct { const char *name; int id; } members[] = {
    {"Load", M_LOAD}, {"LoadText", M_LOADTEXT}, {"Save", M_SAVE}, {"Value", M_VALUE}, {"Sections", M_SECTIONS},
    {"Keys", M_KEYS}, {"HasSection", M_HASSECTION}, {"HasKey", M_HASKEY}, {"DeleteKey", M_DELETEKEY},
    {"DeleteSection", M_DELETESECTION}, {"Clear", M_CLEAR}, {"Path", P_PATH}, {"Text", P_TEXT},
    {"Changed", P_CHANGED},
};

typedef struct {
    bb_obj hdr;
    iline *lines;
    int n, cap;
    char *path;
    int changed;
    int crlf;                   /* the file used CR LF: keep it */
} ini_obj;

static const bb_class ini_class;

static char *dupn(const char *p, size_t n)
{
    char *o = malloc(n + 1);
    memcpy(o, p, n);
    o[n] = 0;
    return o;
}

static char *trimdup(const char *p, size_t n)
{
    while (n && (*p == ' ' || *p == '\t')) p++, n--;
    while (n && (p[n - 1] == ' ' || p[n - 1] == '\t' || p[n - 1] == '\r')) n--;
    return dupn(p, n);
}

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static char *arg_c(int argc, bb_value *argv, int i)
{
    bb_str *s = arg_str(argc, argv, i);
    char *c = dupn(bb_str_ptr(s), (size_t)bb_str_len(s));
    bb_str_release(s);
    return c;
}

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static void free_line(iline *l)
{
    free(l->text);
    free(l->name);
    free(l->value);
}

static void clear(ini_obj *o)
{
    int i;
    for (i = 0; i < o->n; i++) free_line(&o->lines[i]);
    o->n = 0;
}

static iline *insert(ini_obj *o, int at)
{
    int i;
    if (o->n == o->cap) {
        o->cap = o->cap ? o->cap * 2 : 32;
        o->lines = realloc(o->lines, sizeof(iline) * (size_t)o->cap);
    }
    memmove(&o->lines[at + 1], &o->lines[at], sizeof(iline) * (size_t)(o->n - at));
    o->n++;
    memset(&o->lines[at], 0, sizeof(iline));
    /* section indices after the insertion point move by one */
    for (i = 0; i < o->n; i++)
        if (i != at && o->lines[i].kind == L_KEY && o->lines[i].section >= at) o->lines[i].section++;
    return &o->lines[at];
}

static void remove_line(ini_obj *o, int at)
{
    int i;
    free_line(&o->lines[at]);
    memmove(&o->lines[at], &o->lines[at + 1], sizeof(iline) * (size_t)(o->n - at - 1));
    o->n--;
    for (i = 0; i < o->n; i++)
        if (o->lines[i].kind == L_KEY && o->lines[i].section > at) o->lines[i].section--;
}

static void parse(ini_obj *o, const char *text, long len)
{
    long i = 0;
    int section = -1;
    clear(o);
    o->crlf = 0;
    if (len >= 3 && (unsigned char)text[0] == 0xEF && (unsigned char)text[1] == 0xBB && (unsigned char)text[2] == 0xBF) i = 3;
    while (i < len) {
        const char *s = text + i, *nl = memchr(s, '\n', (size_t)(len - i));
        long n = nl ? nl - s : len - i;
        const char *p = s, *e = s + n;
        iline *l = insert(o, o->n);
        if (n && s[n - 1] == '\r') o->crlf = 1;
        while (p < e && (*p == ' ' || *p == '\t')) p++;
        if (p < e && *p == '[') {
            const char *close = memchr(p, ']', (size_t)(e - p));
            if (close) {
                l->kind = L_SECTION;
                l->name = trimdup(p + 1, (size_t)(close - p - 1));
                l->text = trimdup(s, (size_t)n);
                section = o->n - 1;
                i += n + 1;
                continue;
            }
        }
        if (p < e && *p != ';' && *p != '#') {
            const char *eq = memchr(p, '=', (size_t)(e - p));
            if (eq) {
                char *v;
                size_t vl;
                l->kind = L_KEY;
                l->name = trimdup(p, (size_t)(eq - p));
                v = trimdup(eq + 1, (size_t)(e - eq - 1));
                vl = strlen(v);
                /* "quoted values" keep their spaces */
                if (vl >= 2 && v[0] == '"' && v[vl - 1] == '"') {
                    memmove(v, v + 1, vl - 2);
                    v[vl - 2] = 0;
                }
                l->value = v;
                l->section = section;
                l->text = dupn(s, (size_t)(n && s[n - 1] == '\r' ? n - 1 : n));   /* written back while unchanged */
                i += n + 1;
                continue;
            }
        }
        l->kind = L_OTHER;
        l->text = dupn(s, (size_t)(n && s[n - 1] == '\r' ? n - 1 : n));
        i += n + 1;
    }
    o->changed = 0;
}

/* the section line's index; -1 for "" (the top); -2 if there is no such section */
static int find_section(ini_obj *o, const char *sec)
{
    int i;
    if (!*sec) return -1;
    for (i = 0; i < o->n; i++)
        if (o->lines[i].kind == L_SECTION && !strcasecmp(o->lines[i].name, sec)) return i;
    return -2;
}

static int find_key(ini_obj *o, int sec, const char *key)
{
    int i;
    for (i = 0; i < o->n; i++)
        if (o->lines[i].kind == L_KEY && o->lines[i].section == sec && !strcasecmp(o->lines[i].name, key)) return i;
    return -1;
}

/* where a new key of section sec goes: after its last key, else right after its header; keys
   of the "" section go before the first section (before the blank lines in front of it) */
static int insert_point(ini_obj *o, int sec)
{
    int i, at = -1;
    for (i = 0; i < o->n; i++)
        if (o->lines[i].kind == L_KEY && o->lines[i].section == sec) at = i + 1;
    if (at >= 0) return at;
    if (sec >= 0) return sec + 1;
    for (at = 0; at < o->n && o->lines[at].kind != L_SECTION; at++) ;
    if (at < o->n)
        while (at > 0 && o->lines[at - 1].kind == L_OTHER && !o->lines[at - 1].text[0]) at--;
    return at;
}

static void set_value(ini_obj *o, const char *sec, const char *key, const char *value)
{
    int s = find_section(o, sec), k;
    if (!*key || strchr(key, '=') || strchr(key, '\n') || key[0] == '[' || key[0] == ';' || key[0] == '#')
        bb_raise(5, "bad key name");
    if (strchr(sec, ']') || strchr(sec, '\n')) bb_raise(5, "bad section name");
    if (strchr(value, '\n')) bb_raise(5, "a value can't contain a line break");
    if (s == -2) {
        /* a new section at the end, after a blank line */
        iline *l;
        if (o->n && !(o->lines[o->n - 1].kind == L_OTHER && !o->lines[o->n - 1].text[0])) {
            l = insert(o, o->n);
            l->kind = L_OTHER;
            l->text = dupn("", 0);
        }
        l = insert(o, o->n);
        l->kind = L_SECTION;
        l->name = dupn(sec, strlen(sec));
        l->text = malloc(strlen(sec) + 3);
        sprintf(l->text, "[%s]", sec);
        s = o->n - 1;
    }
    k = find_key(o, s, key);
    if (k >= 0) {
        if (!strcmp(o->lines[k].value, value)) return;
        free(o->lines[k].value);
        o->lines[k].value = dupn(value, strlen(value));
        free(o->lines[k].text);
        o->lines[k].text = NULL;
    } else {
        int at = insert_point(o, s);
        iline *l = insert(o, at);
        if (s >= at) s++;           /* (insert moved it) */
        l->kind = L_KEY;
        l->name = dupn(key, strlen(key));
        l->value = dupn(value, strlen(value));
        l->section = s;
    }
    o->changed = 1;
}

static char *to_text(ini_obj *o, long *len)
{
    size_t cap = 256, n = 0;
    char *b = malloc(cap);
    const char *eol = o->crlf ? "\r\n" : "\n";
    int i;
    for (i = 0; i < o->n; i++) {
        iline *l = &o->lines[i];
        const char *v = l->value ? l->value : "";
        size_t need = (l->text ? strlen(l->text) : 0) + (l->name ? strlen(l->name) : 0) + strlen(v) + 8;
        int q;
        if (n + need + 1 > cap) {
            cap = (n + need + 1) * 2;
            b = realloc(b, cap);
        }
        if (l->kind == L_KEY && !l->text) {
            size_t vl = strlen(v);
            q = vl && (v[0] == ' ' || v[vl - 1] == ' ' || v[0] == '\t' || v[vl - 1] == '\t' ||
                       (v[0] == '"' && v[vl - 1] == '"'));
            n += (size_t)sprintf(b + n, q ? "%s=\"%s\"" : "%s=%s", l->name, v);
        } else
            n += (size_t)sprintf(b + n, "%s", l->text);
        n += (size_t)sprintf(b + n, "%s", eol);
    }
    b[n] = 0;
    *len = (long)n;
    return b;
}

static bb_array *str_array(char **items, int n)
{
    bb_array *a = bb_arr_new1(BB_STRING, 0, n - 1);
    int i;
    for (i = 0; i < n; i++) *(bb_str **)bb_arr_elem1(a, i) = bb_str_from_c(items[i]);
    return a;
}

static void i_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    ini_obj *o = (ini_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char *a = NULL, *b = NULL, *c = NULL;
    switch (id) {
    case M_LOAD: {
        FILE *f;
        long n = 0;
        char *buf;
        a = arg_c(argc, argv, 0);
        free(o->path);
        o->path = a;
        f = fopen(a, "rb");
        if (!f) {
            /* a missing file is an empty one (unless MustExist) */
            if (present(argc, argv, 1)) {
                bb_value t;
                if (bb_v_to_bool(bb_v_deref(&argv[1], &t))) bb_raise(53, NULL);
            }
            clear(o);
            o->changed = 0;
            *ret = bb_v_bool(0);
            return;
        }
        fseek(f, 0, SEEK_END);
        n = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)n + 1);
        if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) n = 0;
        fclose(f);
        parse(o, buf, n);
        free(buf);
        *ret = bb_v_bool(1);
        return;
    }
    case M_LOADTEXT: {
        bb_str *s = arg_str(argc, argv, 0);
        parse(o, bb_str_ptr(s), bb_str_len(s));
        bb_str_release(s);
        return;
    }
    case M_SAVE: {
        FILE *f;
        long n;
        char *t;
        if (present(argc, argv, 0)) {
            free(o->path);
            o->path = arg_c(argc, argv, 0);
        }
        if (!o->path || !*o->path) bb_raise(5, "Save needs a file name (none was loaded)");
        t = to_text(o, &n);
        f = fopen(o->path, "wb");
        if (!f) {
            free(t);
            bb_raise(75, NULL);
        }
        if (fwrite(t, 1, (size_t)n, f) != (size_t)n) {
            fclose(f);
            free(t);
            bb_raise(61, NULL);
        }
        free(t);
        if (fclose(f)) bb_raise(61, NULL);
        o->changed = 0;
        return;
    }
    case M_VALUE: {
        int s, k;
        if (set) {
            /* Value(section, key) = v */
            if (argc != 3) bb_raise(450, NULL);
            a = arg_c(argc, argv, 0);
            b = arg_c(argc, argv, 1);
            c = arg_c(argc, argv, 2);
            set_value(o, a, b, c);
            free(a); free(b); free(c);
            return;
        }
        a = arg_c(argc, argv, 0);
        b = arg_c(argc, argv, 1);
        s = find_section(o, a);
        k = s == -2 ? -1 : find_key(o, s, b);
        free(a);
        free(b);
        if (k >= 0) *ret = bb_v_str(bb_str_from_c(o->lines[k].value));
        else if (present(argc, argv, 2)) *ret = bb_v_str(arg_str(argc, argv, 2));
        else *ret = bb_v_str(bb_str_from_c(""));
        return;
    }
    case M_SECTIONS: {
        char **items = malloc(sizeof(char *) * (size_t)(o->n + 1));
        int n = 0, i, top = 0;
        for (i = 0; i < o->n; i++) if (o->lines[i].kind == L_KEY && o->lines[i].section == -1) top = 1;
        if (top) items[n++] = "";
        for (i = 0; i < o->n; i++) if (o->lines[i].kind == L_SECTION) items[n++] = o->lines[i].name;
        *ret = bb_v_arr(str_array(items, n));
        free(items);
        return;
    }
    case M_KEYS: {
        char **items = malloc(sizeof(char *) * (size_t)(o->n + 1));
        int n = 0, i, s;
        a = arg_c(argc, argv, 0);
        s = find_section(o, a);
        free(a);
        for (i = 0; s != -2 && i < o->n; i++)
            if (o->lines[i].kind == L_KEY && o->lines[i].section == s) items[n++] = o->lines[i].name;
        *ret = bb_v_arr(str_array(items, n));
        free(items);
        return;
    }
    case M_HASSECTION: {
        int s, i, any = 0;
        a = arg_c(argc, argv, 0);
        s = find_section(o, a);
        free(a);
        if (s == -1) for (i = 0; i < o->n; i++) if (o->lines[i].kind == L_KEY && o->lines[i].section == -1) any = 1;
        *ret = bb_v_bool(s >= 0 || any);
        return;
    }
    case M_HASKEY: {
        int s;
        a = arg_c(argc, argv, 0);
        b = arg_c(argc, argv, 1);
        s = find_section(o, a);
        *ret = bb_v_bool(s != -2 && find_key(o, s, b) >= 0);
        free(a);
        free(b);
        return;
    }
    case M_DELETEKEY: {
        int s, k;
        a = arg_c(argc, argv, 0);
        b = arg_c(argc, argv, 1);
        s = find_section(o, a);
        k = s == -2 ? -1 : find_key(o, s, b);
        free(a);
        free(b);
        if (k >= 0) {
            remove_line(o, k);
            o->changed = 1;
        }
        *ret = bb_v_bool(k >= 0);
        return;
    }
    case M_DELETESECTION: {
        int s, i;
        a = arg_c(argc, argv, 0);
        s = find_section(o, a);
        free(a);
        if (s == -2) {
            *ret = bb_v_bool(0);
            return;
        }
        if (s >= 0) {
            /* the header and every line up to the next section (its blank lines too: the blank
               lines in front of the header then separate what was before from the next section) */
            int end = s + 1;
            while (end < o->n && o->lines[end].kind != L_SECTION) end++;
            for (i = end - 1; i >= s; i--) remove_line(o, i);
            if (s >= o->n)                  /* it was the last one: no blank lines left at the end */
                while (o->n && o->lines[o->n - 1].kind == L_OTHER && !o->lines[o->n - 1].text[0]) remove_line(o, o->n - 1);
        } else
            for (i = o->n - 1; i >= 0; i--) if (o->lines[i].kind == L_KEY && o->lines[i].section == -1) remove_line(o, i);
        o->changed = 1;
        *ret = bb_v_bool(1);
        return;
    }
    case M_CLEAR:
        clear(o);
        o->changed = 1;
        return;
    case P_PATH:
        if (set) {
            free(o->path);
            o->path = arg_c(argc, argv, argc - 1);
        } else
            *ret = bb_v_str(bb_str_from_c(o->path ? o->path : ""));
        return;
    case P_TEXT:
        if (set) {
            bb_str *s = arg_str(argc, argv, argc - 1);
            parse(o, bb_str_ptr(s), bb_str_len(s));
            bb_str_release(s);
        } else {
            long n;
            char *t = to_text(o, &n);
            *ret = bb_v_str(bb_str_new(t, (int32_t)n));
            free(t);
        }
        return;
    case P_CHANGED:
        *ret = bb_v_bool(o->changed);
        return;
    }
    bb_raise(438, NULL);
}

static int32_t i_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return M_VALUE;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void i_terminate(bb_obj *self)
{
    ini_obj *o = (ini_obj *)self;
    clear(o);
    free(o->lines);
    free(o->path);
}

static const bb_class ini_class = {
    "IniFile", sizeof(ini_obj), i_find, i_invoke, i_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_ini_class(void) { return &ini_class; }
bb_obj *bb_ini_new(void) { return bb_obj_new(&ini_class); }
