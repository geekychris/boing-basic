/* regexp.c - Boing.RegExp, regular expressions (docs/regexp.md), on the engine in bbre.c:
 *
 *     Dim re As RegExp
 *     Set re = CreateObject("RegExp")
 *     re.Pattern = "(\w+)@(\w+)\.com"
 *     re.Global = True
 *     For Each m In re.Execute(text)
 *         Print m.Value; " at "; m.FirstIndex; " user "; m.SubMatches(0)
 *     Next
 *     Print re.Replace(text, "$2: $1")
 *
 * Execute returns a Matches collection of Match objects; a Match's SubMatches is a collection
 * of the groups' texts. Positions (FirstIndex) count from 0. The compiled pattern is cached in
 * the object until Pattern / IgnoreCase / MultiLine change. */
#include "boing.h"
#include "bbre.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define E_RE_SYNTAX 5017        /* bad pattern */
#define E_RE_TOOLONG 5019       /* the step limit */

enum { M_TEST = 1, M_EXECUTE, M_REPLACE, M_SPLIT, M_MATCH1, M_ESCAPE,
       P_PATTERN, P_GLOBAL, P_IGNORECASE, P_MULTILINE };
static const struct { const char *name; int id; } members[] = {
    {"Test", M_TEST}, {"Execute", M_EXECUTE}, {"Replace", M_REPLACE}, {"Split", M_SPLIT},
    {"FirstMatch", M_MATCH1}, {"Escape", M_ESCAPE},
    {"Pattern", P_PATTERN}, {"Global", P_GLOBAL}, {"IgnoreCase", P_IGNORECASE}, {"MultiLine", P_MULTILINE},
};

enum { MC_COUNT = 1, MC_ITEM };
static const struct { const char *name; int id; } mc_tab[] = { {"Count", MC_COUNT}, {"Item", MC_ITEM} };

enum { MM_VALUE = 1, MM_FIRSTINDEX, MM_LENGTH, MM_SUBMATCHES, MM_GROUPINDEX };
static const struct { const char *name; int id; } mm_tab[] = {
    {"Value", MM_VALUE}, {"FirstIndex", MM_FIRSTINDEX}, {"Length", MM_LENGTH}, {"SubMatches", MM_SUBMATCHES},
    {"SubMatchIndex", MM_GROUPINDEX},
};

typedef struct {
    bb_obj hdr;
    bb_str *pattern;
    int global, icase, multiline;
    bb_re *re;                  /* compiled, or NULL */
} regexp_obj;

typedef struct {                /* Matches */
    bb_obj hdr;
    int n;
    bb_obj **items;             /* Match objects */
} mcoll_obj;

typedef struct {                /* Match */
    bb_obj hdr;
    bb_str *value;
    int first, length;
    int ngroups;
    bb_value *groups;           /* String, or Empty for a group that didn't take part */
    int *gstart;                /* each group's position (-1) */
} match_obj;

typedef struct {                /* SubMatches */
    bb_obj hdr;
    match_obj *m;               /* retained */
} subm_obj;

static const bb_class regexp_class, mcoll_class, match_class, subm_class;

/* ---- helpers ---- */

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static int arg_bool(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_bool(bb_v_deref(&argv[i], &t)) != 0;
}

static int find_in(const void *tab, size_t n, size_t stride, const char *name)
{
    size_t i;
    for (i = 0; i < n; i++) {
        const struct { const char *name; int id; } *e = (const void *)((const char *)tab + i * stride);
        if (!strcasecmp(e->name, name)) return e->id;
    }
    return BB_NOMEMBER;
}

static const bb_re *compiled(regexp_obj *r)
{
    char err[200];
    int flags;
    if (r->re) return r->re;
    flags = (r->icase ? BB_RE_ICASE : 0) | (r->multiline ? BB_RE_MULTILINE : 0);
    r->re = bb_re_compile(bb_str_ptr(r->pattern), (int)bb_str_len(r->pattern), flags, err, sizeof err);
    if (!r->re) {
        char msg[300];
        snprintf(msg, sizeof msg, "bad regular expression: %s", err);
        bb_raise(E_RE_SYNTAX, msg);
    }
    return r->re;
}

static void drop_compiled(regexp_obj *r)
{
    bb_re_free(r->re);
    r->re = NULL;
}

/* search; raises on the step limit. caps sized 2*(ngroups+1). */
static int search(const bb_re *re, const bb_str *s, int start, int *caps)
{
    int rc = bb_re_search(re, bb_str_ptr(s), (int)bb_str_len(s), start, caps);
    if (rc == BB_RE_TOOLONG) bb_raise(E_RE_TOOLONG, "the regular expression takes too long on this text (too much backtracking)");
    if (rc == BB_RE_NOMEM) bb_raise(7, NULL);
    return rc == BB_RE_MATCH;
}

static bb_obj *new_match(const bb_str *s, const int *caps, int ngroups)
{
    match_obj *m = (match_obj *)bb_obj_new(&match_class);
    int i;
    m->value = bb_str_new(bb_str_ptr(s) + caps[0], caps[1] - caps[0]);
    m->first = caps[0];
    m->length = caps[1] - caps[0];
    m->ngroups = ngroups;
    m->groups = (bb_value *)calloc((size_t)ngroups + 1, sizeof(bb_value));
    m->gstart = (int *)calloc((size_t)ngroups + 1, sizeof(int));
    for (i = 0; i < ngroups; i++) {
        int a = caps[2 * (i + 1)], b = caps[2 * (i + 1) + 1];
        m->gstart[i] = a;
        m->groups[i] = a >= 0 ? bb_v_str(bb_str_new(bb_str_ptr(s) + a, b - a)) : bb_v_empty();
    }
    return &m->hdr;
}

/* the next match position after a match [a,b): b, or b+1 after an empty match */
static int next_start(int a, int b) { return b > a ? b : b + 1; }

/* ---- RegExp ---- */

typedef struct { char *p; long n, cap; } sbuf;

static void sb_add(sbuf *b, const char *p, long n)
{
    if (n <= 0) return;
    if (b->n + n > b->cap) {
        b->cap = (b->n + n) * 2 + 64;
        b->p = (char *)realloc(b->p, (size_t)b->cap);
    }
    memcpy(b->p + b->n, p, (size_t)n);
    b->n += n;
}

static void sb_free(void *ctx) { free(((sbuf *)ctx)->p); }

/* the replacement for one match: $1..$99, $& whole match, $` before, $' after, $$ */
static void expand(sbuf *out, const bb_str *rep, const bb_str *s, const int *caps, int ngroups)
{
    const char *r = bb_str_ptr(rep), *src = bb_str_ptr(s);
    long n = bb_str_len(rep), i;
    for (i = 0; i < n; i++) {
        char c = r[i];
        if (c != '$' || i + 1 >= n) {
            sb_add(out, &c, 1);
            continue;
        }
        c = r[i + 1];
        if (c == '$') {
            sb_add(out, "$", 1);
            i++;
        } else if (c == '&') {
            sb_add(out, src + caps[0], caps[1] - caps[0]);
            i++;
        } else if (c == '`') {
            sb_add(out, src, caps[0]);
            i++;
        } else if (c == '\'') {
            sb_add(out, src + caps[1], bb_str_len(s) - caps[1]);
            i++;
        } else if (c >= '0' && c <= '9') {
            int g = c - '0', used = 1;
            /* two digits when that group exists ($10), else one */
            if (i + 2 < n && r[i + 2] >= '0' && r[i + 2] <= '9' && g * 10 + (r[i + 2] - '0') <= ngroups) {
                g = g * 10 + (r[i + 2] - '0');
                used = 2;
            }
            if (g >= 1 && g <= ngroups) {
                if (caps[2 * g] >= 0) sb_add(out, src + caps[2 * g], caps[2 * g + 1] - caps[2 * g]);
                i += used;
            } else
                sb_add(out, "$", 1);   /* $0, $7 with 3 groups: literal */
        } else
            sb_add(out, "$", 1);
    }
}

static bb_str *do_replace(regexp_obj *r, const bb_str *s, const bb_str *rep)
{
    const bb_re *re = compiled(r);
    int ng = bb_re_ngroups(re), fixed[64], *caps = 2 * (ng + 1) <= 64 ? fixed : (int *)malloc(sizeof(int) * 2 * (size_t)(ng + 1));
    int pos = 0, last = 0, len = (int)bb_str_len(s);
    sbuf out = {NULL, 0, 0};
    bb_cleanup cl;
    bb_str *res;
    cl.prev = bb_cleanups;
    cl.fn = sb_free;
    cl.ctx = &out;
    bb_cleanups = &cl;
    while (pos <= len && search(re, s, pos, caps)) {
        sb_add(&out, bb_str_ptr(s) + last, caps[0] - last);
        expand(&out, rep, s, caps, ng);
        last = caps[1];
        pos = next_start(caps[0], caps[1]);
        if (caps[1] == caps[0] && caps[0] < len) {
            /* an empty match: copy the byte we step over */
            sb_add(&out, bb_str_ptr(s) + caps[0], 1);
            last = caps[0] + 1;
        }
        if (!r->global) break;
    }
    if (last < len) sb_add(&out, bb_str_ptr(s) + last, len - last);
    bb_cleanups = cl.prev;
    res = bb_str_new(out.p ? out.p : "", (int32_t)out.n);
    free(out.p);
    if (caps != fixed) free(caps);
    return res;
}

static bb_obj *do_execute(regexp_obj *r, const bb_str *s)
{
    const bb_re *re = compiled(r);
    int ng = bb_re_ngroups(re), fixed[64], *caps = 2 * (ng + 1) <= 64 ? fixed : (int *)malloc(sizeof(int) * 2 * (size_t)(ng + 1));
    int pos = 0, len = (int)bb_str_len(s), cap = 0;
    mcoll_obj *mc = (mcoll_obj *)bb_obj_new(&mcoll_class);
    bb_cleanup cl;
    cl.prev = bb_cleanups;
    cl.fn = (void (*)(void *))bb_obj_release;
    cl.ctx = mc;
    bb_cleanups = &cl;
    while (pos <= len && search(re, s, pos, caps)) {
        if (mc->n == cap) {
            cap = cap ? cap * 2 : 8;
            mc->items = (bb_obj **)realloc(mc->items, sizeof(bb_obj *) * (size_t)cap);
        }
        mc->items[mc->n++] = new_match(s, caps, ng);
        pos = next_start(caps[0], caps[1]);
        if (!r->global) break;
    }
    bb_cleanups = cl.prev;
    if (caps != fixed) free(caps);
    return &mc->hdr;
}

/* Split: the pieces between matches (groups' texts are included, as with most Split functions) */
static bb_array *do_split(regexp_obj *r, const bb_str *s)
{
    const bb_re *re = compiled(r);
    int ng = bb_re_ngroups(re), fixed[64], *caps = 2 * (ng + 1) <= 64 ? fixed : (int *)malloc(sizeof(int) * 2 * (size_t)(ng + 1));
    int pos = 0, last = 0, len = (int)bb_str_len(s), n = 0, capn = 16, i;
    bb_str **parts = (bb_str **)malloc(sizeof(bb_str *) * (size_t)capn);
    bb_array *a;
    while (pos <= len && search(re, s, pos, caps)) {
        if (caps[1] == caps[0] && (caps[0] == 0 || caps[0] == len || caps[0] == last)) {
            pos = caps[0] + 1;          /* no empty pieces from empty matches at the ends */
            if (caps[0] == len) break;
            continue;
        }
        if (n + ng + 2 > capn) {
            capn = (n + ng + 2) * 2;
            parts = (bb_str **)realloc(parts, sizeof(bb_str *) * (size_t)capn);
        }
        parts[n++] = bb_str_new(bb_str_ptr(s) + last, caps[0] - last);
        for (i = 1; i <= ng; i++)
            parts[n++] = caps[2 * i] >= 0 ? bb_str_new(bb_str_ptr(s) + caps[2 * i], caps[2 * i + 1] - caps[2 * i])
                                          : bb_str_from_c("");
        last = caps[1];
        pos = next_start(caps[0], caps[1]);
    }
    if (n + 1 > capn) parts = (bb_str **)realloc(parts, sizeof(bb_str *) * (size_t)(n + 1));
    parts[n++] = bb_str_new(bb_str_ptr(s) + last, len - last);
    a = bb_arr_new1(BB_STRING, 0, n - 1);
    for (i = 0; i < n; i++) *(bb_str **)bb_arr_elem1(a, i) = parts[i];
    free(parts);
    if (caps != fixed) free(caps);
    return a;
}

/* RegExp.Escape(text): text with every special character escaped, for a literal pattern */
static bb_str *do_escape(const bb_str *s)
{
    const char *p = bb_str_ptr(s);
    long n = bb_str_len(s), i;
    sbuf out = {NULL, 0, 0};
    bb_str *r;
    for (i = 0; i < n; i++) {
        if (strchr("\\^$.|?*+()[]{}-", p[i]) && p[i]) sb_add(&out, "\\", 1);
        sb_add(&out, p + i, 1);
    }
    r = bb_str_new(out.p ? out.p : "", (int32_t)out.n);
    free(out.p);
    return r;
}

static void re_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    regexp_obj *r = (regexp_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    bb_str *s, *rep;
    switch (id) {
    case M_TEST: {
        int caps[200], ok, *cp;
        const bb_re *re;
        s = arg_str(argc, argv, 0);
        re = compiled(r);
        cp = 2 * (bb_re_ngroups(re) + 1) <= 200 ? caps : (int *)malloc(sizeof(int) * 2 * (size_t)(bb_re_ngroups(re) + 1));
        ok = search(re, s, 0, cp);
        if (cp != caps) free(cp);
        bb_str_release(s);
        *ret = bb_v_bool(ok);
        return;
    }
    case M_EXECUTE:
        s = arg_str(argc, argv, 0);
        *ret = bb_v_obj(do_execute(r, s));
        bb_str_release(s);
        return;
    case M_MATCH1: {             /* FirstMatch(text): the first match's text, "" if none */
        int g = r->global;
        bb_obj *mc;
        s = arg_str(argc, argv, 0);
        r->global = 0;
        mc = do_execute(r, s);
        r->global = g;
        bb_str_release(s);
        *ret = bb_v_str(((mcoll_obj *)mc)->n ? bb_str_retain(((match_obj *)((mcoll_obj *)mc)->items[0])->value)
                                             : bb_str_from_c(""));
        bb_obj_release(mc);
        return;
    }
    case M_REPLACE:
        s = arg_str(argc, argv, 0);
        rep = arg_str(argc, argv, 1);
        *ret = bb_v_str(do_replace(r, s, rep));
        bb_str_release(s);
        bb_str_release(rep);
        return;
    case M_SPLIT:
        s = arg_str(argc, argv, 0);
        *ret = bb_v_arr(do_split(r, s));
        bb_str_release(s);
        return;
    case M_ESCAPE:
        s = arg_str(argc, argv, 0);
        *ret = bb_v_str(do_escape(s));
        bb_str_release(s);
        return;
    case P_PATTERN:
        if (set) {
            bb_str_set(&r->pattern, arg_str(argc, argv, argc - 1));
            drop_compiled(r);
        } else
            *ret = bb_v_str(bb_str_retain(r->pattern));
        return;
    case P_GLOBAL:
    case P_IGNORECASE:
    case P_MULTILINE: {
        int *f = id == P_GLOBAL ? &r->global : id == P_IGNORECASE ? &r->icase : &r->multiline;
        if (set) {
            int v = arg_bool(argc, argv, argc - 1);
            if (v != *f && id != P_GLOBAL) drop_compiled(r);
            *f = v;
        } else
            *ret = bb_v_bool(*f);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t re_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return P_PATTERN;
    return find_in(members, sizeof members / sizeof members[0], sizeof members[0], name);
}

static void re_terminate(bb_obj *self)
{
    regexp_obj *r = (regexp_obj *)self;
    bb_str_release(r->pattern);
    bb_re_free(r->re);
}

static const bb_class regexp_class = {
    "RegExp", sizeof(regexp_obj), re_find, re_invoke, re_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_regexp_class(void) { return &regexp_class; }
bb_obj *bb_regexp_new(void) { return bb_obj_new(&regexp_class); }

/* ---- Matches ---- */

static int32_t index_arg(int argc, bb_value *argv, int n)
{
    int32_t i = arg_long(argc, argv, 0);
    if (i < 0 || i >= n) bb_raise(9, NULL);
    return i;
}

static void mc_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    mcoll_obj *mc = (mcoll_obj *)self;
    if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);     /* read-only */
    if (id == MC_COUNT) {
        *ret = bb_v_long(mc->n);
        return;
    }
    if (id == MC_ITEM) {
        *ret = bb_v_obj(bb_obj_retain(mc->items[index_arg(argc, argv, mc->n)]));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t mc_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return MC_ITEM;
    return find_in(mc_tab, 2, sizeof mc_tab[0], name);
}

static void mc_terminate(bb_obj *self)
{
    mcoll_obj *mc = (mcoll_obj *)self;
    int i;
    for (i = 0; i < mc->n; i++) bb_obj_release(mc->items[i]);
    free(mc->items);
}

static int mc_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    mcoll_obj *mc = (mcoll_obj *)self;
    int32_t i = state->type == BB_LONG ? state->u.l : 0;
    if (i >= mc->n) return 0;
    *out = bb_v_obj(bb_obj_retain(mc->items[i]));
    *state = bb_v_long(i + 1);
    return 1;
}

static const bb_class mcoll_class = {
    "Matches", sizeof(mcoll_obj), mc_find, mc_invoke, mc_terminate, mc_iterate, NULL, 0, NULL, 0, NULL, NULL
};

/* ---- Match ---- */

static void mm_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    match_obj *m = (match_obj *)self;
    if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);
    switch (id) {
    case MM_VALUE:
        *ret = bb_v_str(bb_str_retain(m->value));
        return;
    case MM_FIRSTINDEX:
        *ret = bb_v_long(m->first);
        return;
    case MM_LENGTH:
        *ret = bb_v_long(m->length);
        return;
    case MM_SUBMATCHES:
        if (argc > 0) {             /* m.SubMatches(i) */
            bb_v_copy(ret, &m->groups[index_arg(argc, argv, m->ngroups)]);
        } else {
            subm_obj *sm = (subm_obj *)bb_obj_new(&subm_class);
            sm->m = (match_obj *)bb_obj_retain(&m->hdr);
            *ret = bb_v_obj(&sm->hdr);
        }
        return;
    case MM_GROUPINDEX:             /* SubMatchIndex(i): where group i matched, -1 if it didn't */
        *ret = bb_v_long(m->gstart[index_arg(argc, argv, m->ngroups)]);
        return;
    }
    bb_raise(438, NULL);
}

static int32_t mm_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return MM_VALUE;
    return find_in(mm_tab, sizeof mm_tab / sizeof mm_tab[0], sizeof mm_tab[0], name);
}

static void mm_terminate(bb_obj *self)
{
    match_obj *m = (match_obj *)self;
    int i;
    bb_str_release(m->value);
    for (i = 0; i < m->ngroups; i++) bb_v_release(&m->groups[i]);
    free(m->groups);
    free(m->gstart);
}

static const bb_class match_class = {
    "Match", sizeof(match_obj), mm_find, mm_invoke, mm_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

/* ---- SubMatches ---- */

static void sm_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    subm_obj *sm = (subm_obj *)self;
    if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);
    if (id == MC_COUNT) {
        *ret = bb_v_long(sm->m->ngroups);
        return;
    }
    if (id == MC_ITEM) {
        bb_v_copy(ret, &sm->m->groups[index_arg(argc, argv, sm->m->ngroups)]);
        return;
    }
    bb_raise(438, NULL);
}

static void sm_terminate(bb_obj *self) { bb_obj_release(&((subm_obj *)self)->m->hdr); }

static int sm_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    subm_obj *sm = (subm_obj *)self;
    int32_t i = state->type == BB_LONG ? state->u.l : 0;
    if (i >= sm->m->ngroups) return 0;
    bb_v_copy(out, &sm->m->groups[i]);
    *state = bb_v_long(i + 1);
    return 1;
}

static const bb_class subm_class = {
    "SubMatches", sizeof(subm_obj), mc_find, sm_invoke, sm_terminate, sm_iterate, NULL, 0, NULL, 0, NULL, NULL
};
