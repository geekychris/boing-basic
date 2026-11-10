/* bbre.c - the regular expression engine (bbre.h). Pattern -> syntax tree -> a program for a
 * backtracking VM:
 *
 *   CHAR c / ANY / CLASS k     match one byte          SPLIT x, y   try x, on failure y
 *   JMP x                      SAVE n  capture slot n   BOL EOL WORDB NWORDB   assertions
 *   BACKREF n                  LOOK neg, len  a sub-program of len instructions (ends in MATCH)
 *   MARK k / PROGRESS k        a loop whose body can match "" must move on (else it would spin)
 *   MATCH
 *
 * The VM keeps its backtrack stack on the heap: BRANCH entries (pc, position) and RESTORE
 * entries (a register's old value, undone when backtracking past it). */
#include "bbre.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { I_CHAR, I_ANY, I_CLASS, I_SPLIT, I_JMP, I_SAVE, I_BOL, I_EOL, I_WORDB, I_NWORDB, I_BACKREF, I_LOOK,
       I_MARK, I_PROGRESS, I_MATCH };

typedef struct { unsigned char op; int x, y; } inst;
typedef struct { unsigned char bits[32]; } cset;

struct bb_re {
    inst *code;
    int ncode;
    cset *sets;
    int nsets;
    int ngroups, nmarks, flags;
    int first;                  /* a byte every match starts with (-1: unknown) */
};

/* ---- Latin-1 case folding ---- */

static unsigned char fold_tab[256];
static int fold_ready;

static void fold_init(void)
{
    int c;
    if (fold_ready) return;
    for (c = 0; c < 256; c++) fold_tab[c] = (unsigned char)c;
    for (c = 'A'; c <= 'Z'; c++) fold_tab[c] = (unsigned char)(c + 32);
    for (c = 0xC0; c <= 0xDE; c++) if (c != 0xD7) fold_tab[c] = (unsigned char)(c + 32);
    fold_ready = 1;
}

static int other_case(int c)
{
    if (c >= 'a' && c <= 'z') return c - 32;
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c >= 0xE0 && c <= 0xFE && c != 0xF7) return c - 32;
    if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
    return c;
}

static int is_word(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; }

/* ---- syntax tree ---- */

enum { N_EMPTY, N_CHAR, N_ANY, N_CLASS, N_BOL, N_EOL, N_WORDB, N_NWORDB, N_GROUP, N_LOOK, N_CAT, N_ALT,
       N_REP, N_BACKREF };

typedef struct node {
    int kind;
    int c;                      /* CHAR byte, CLASS set index, GROUP number (-1 non-capturing), BACKREF n, LOOK negative */
    int min, max, lazy;         /* REP (max -1: no limit) */
    struct node *a, *b;         /* child (GROUP/LOOK/REP), CAT/ALT left and right */
} node;

typedef struct {
    const unsigned char *p, *end;
    int flags;
    char *err;
    int errlen;
    int failed;
    int ngroups;
    cset *sets;
    int nsets, capsets;
    node **pool;                /* every node, freed together */
    int npool, cappool;
} parser;

static void fail(parser *ps, const char *msg)
{
    if (!ps->failed) snprintf(ps->err, (size_t)ps->errlen, "%s", msg);
    ps->failed = 1;
}

static node *mk(parser *ps, int kind)
{
    node *n;
    if (ps->npool == ps->cappool) {
        ps->cappool = ps->cappool ? ps->cappool * 2 : 64;
        ps->pool = (node **)realloc(ps->pool, sizeof(node *) * (size_t)ps->cappool);
    }
    n = (node *)calloc(1, sizeof *n);
    if (!n) {
        fail(ps, "out of memory");
        return NULL;
    }
    n->kind = kind;
    ps->pool[ps->npool++] = n;
    return n;
}

static int new_set(parser *ps)
{
    if (ps->nsets == ps->capsets) {
        ps->capsets = ps->capsets ? ps->capsets * 2 : 8;
        ps->sets = (cset *)realloc(ps->sets, sizeof(cset) * (size_t)ps->capsets);
    }
    memset(&ps->sets[ps->nsets], 0, sizeof(cset));
    return ps->nsets++;
}

static void set_add(cset *s, int c) { s->bits[c >> 3] |= (unsigned char)(1 << (c & 7)); }
static int set_has(const cset *s, int c) { return (s->bits[c >> 3] >> (c & 7)) & 1; }

static void set_class(cset *s, int k)       /* d w s, D W S */
{
    int c;
    for (c = 0; c < 256; c++) {
        int in = k == 'd' || k == 'D' ? (c >= '0' && c <= '9')
               : k == 'w' || k == 'W' ? is_word(c)
               : (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v');
        if (k == 'D' || k == 'W' || k == 'S') in = !in;
        if (in) set_add(s, c);
    }
}

static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* an escape after '\' that stands for one byte; -1 if it isn't one */
static int escape_byte(parser *ps)
{
    int c = *ps->p++, v, i, n;
    switch (c) {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case 'f': return '\f';
    case 'v': return '\v';
    case '0': return 0;
    case 'x':
    case 'u':
        n = c == 'x' ? 2 : 4;
        for (v = 0, i = 0; i < n; i++) {
            int h = ps->p < ps->end ? hexval(*ps->p) : -1;
            if (h < 0) {
                fail(ps, c == 'x' ? "\\x needs two hex digits" : "\\u needs four hex digits");
                return 0;
            }
            v = v * 16 + h;
            ps->p++;
        }
        if (v > 255) {
            fail(ps, "\\u character beyond 255 (strings are bytes)");
            return 0;
        }
        return v;
    case 'c':
        if (ps->p < ps->end && ((*ps->p >= 'A' && *ps->p <= 'Z') || (*ps->p >= 'a' && *ps->p <= 'z')))
            return *ps->p++ & 31;
        return 'c';
    }
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '1' && c <= '9')) {
        ps->p--;
        return -1;
    }
    return c;                   /* \. \* \\ \/ ... */
}

static node *parse_alt(parser *ps);

static node *parse_class(parser *ps)
{
    int k = new_set(ps), neg = 0, first = 1, prev = -1, i;
    cset s;
    memset(&s, 0, sizeof s);
    if (ps->p < ps->end && *ps->p == '^') {
        neg = 1;
        ps->p++;
    }
    for (;;) {
        int c, lo;
        if (ps->p >= ps->end) {
            fail(ps, "missing ] in a character class");
            return NULL;
        }
        c = *ps->p++;
        if (c == ']' && !first) break;
        first = 0;
        if (c == '\\') {
            if (ps->p >= ps->end) {
                fail(ps, "\\ at the end of the pattern");
                return NULL;
            }
            if (strchr("dwsDWS", *ps->p)) {
                set_class(&s, *ps->p++);
                prev = -1;
                continue;
            }
            if (*ps->p == 'b') {
                ps->p++;
                c = '\b';
            } else {
                c = escape_byte(ps);
                if (c < 0) c = *ps->p++;     /* an unknown letter escape: the letter */
            }
        }
        if (c == '-' && prev >= 0 && ps->p < ps->end && *ps->p != ']') {
            int hi = *ps->p++;
            if (hi == '\\') {
                if (ps->p >= ps->end) {
                    fail(ps, "\\ at the end of the pattern");
                    return NULL;
                }
                hi = escape_byte(ps);
                if (hi < 0) {
                    fail(ps, "a class like \\d can't end a range");
                    return NULL;
                }
            }
            if (hi < prev) {
                fail(ps, "a range out of order in a character class");
                return NULL;
            }
            for (lo = prev; lo <= hi; lo++) set_add(&s, lo);
            prev = -1;
            continue;
        }
        set_add(&s, c);
        prev = c;
    }
    if (ps->flags & BB_RE_ICASE)
        for (i = 0; i < 256; i++) if (set_has(&s, i)) set_add(&s, other_case(i));
    if (neg) for (i = 0; i < 32; i++) s.bits[i] = (unsigned char)~s.bits[i];
    ps->sets[k] = s;
    {
        node *n = mk(ps, N_CLASS);
        if (n) n->c = k;
        return n;
    }
}

static int parse_int(parser *ps, int *out)
{
    int v = 0, any = 0;
    while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9') {
        v = v * 10 + (*ps->p++ - '0');
        if (v > 100000) v = 100000;
        any = 1;
    }
    *out = v;
    return any;
}

static node *parse_atom(parser *ps)
{
    int c;
    node *n;
    if (ps->p >= ps->end) return mk(ps, N_EMPTY);
    c = *ps->p++;
    switch (c) {
    case '.':
        return mk(ps, N_ANY);
    case '^':
        return mk(ps, N_BOL);
    case '$':
        return mk(ps, N_EOL);
    case '[':
        return parse_class(ps);
    case '(': {
        int kind = N_GROUP, grp = -1, neg = 0;
        if (ps->p + 1 < ps->end && ps->p[0] == '?') {
            if (ps->p[1] == ':') kind = N_GROUP;
            else if (ps->p[1] == '=' || ps->p[1] == '!') {
                kind = N_LOOK;
                neg = ps->p[1] == '!';
            } else {
                fail(ps, "unknown group type (?...");
                return NULL;
            }
            ps->p += 2;
        } else {
            if (ps->ngroups >= 99) {
                fail(ps, "more than 99 groups");
                return NULL;
            }
            grp = ++ps->ngroups;
        }
        n = mk(ps, kind);
        if (!n) return NULL;
        n->c = kind == N_LOOK ? neg : grp;
        n->a = parse_alt(ps);
        if (ps->failed) return NULL;
        if (ps->p >= ps->end || *ps->p != ')') {
            fail(ps, "missing )");
            return NULL;
        }
        ps->p++;
        return n;
    }
    case ')':
        fail(ps, "unmatched )");
        return NULL;
    case '*':
    case '+':
    case '?':
        fail(ps, "nothing to repeat before *, + or ?");
        return NULL;
    case '\\':
        if (ps->p >= ps->end) {
            fail(ps, "\\ at the end of the pattern");
            return NULL;
        }
        c = *ps->p;
        if (strchr("dwsDWS", c)) {
            int k = new_set(ps);
            ps->p++;
            set_class(&ps->sets[k], c);
            n = mk(ps, N_CLASS);
            if (n) n->c = k;
            return n;
        }
        if (c == 'b' || c == 'B') {
            ps->p++;
            return mk(ps, c == 'b' ? N_WORDB : N_NWORDB);
        }
        if (c >= '1' && c <= '9') {
            ps->p++;
            n = mk(ps, N_BACKREF);
            if (n) n->c = c - '0';
            return n;
        }
        c = escape_byte(ps);
        if (c < 0) {
            c = *ps->p++;       /* \q and friends: the letter itself */
        }
        break;
    case '{': {
        /* a { that doesn't start a valid {n,m} is a literal */
        break;
    }
    }
    n = mk(ps, N_CHAR);
    if (n) n->c = c;
    return n;
}

/* {n}, {n,}, {n,m} at p? Then consume it. */
static int parse_braces(parser *ps, int *min, int *max)
{
    const unsigned char *save = ps->p;
    int a, b;
    if (ps->p >= ps->end || *ps->p != '{') return 0;
    ps->p++;
    if (!parse_int(ps, &a)) goto no;
    b = a;
    if (ps->p < ps->end && *ps->p == ',') {
        ps->p++;
        if (!parse_int(ps, &b)) b = -1;
    }
    if (ps->p >= ps->end || *ps->p != '}') goto no;
    ps->p++;
    if (b >= 0 && b < a) {
        fail(ps, "{n,m} with m < n");
        return 0;
    }
    *min = a;
    *max = b;
    return 1;
no:
    ps->p = save;
    return 0;
}

static node *parse_repeat(parser *ps)
{
    node *a = parse_atom(ps);
    for (;;) {
        int min, max;
        node *r;
        if (ps->failed || !a) return NULL;
        if (ps->p >= ps->end) return a;
        if (*ps->p == '*') { min = 0; max = -1; ps->p++; }
        else if (*ps->p == '+') { min = 1; max = -1; ps->p++; }
        else if (*ps->p == '?') { min = 0; max = 1; ps->p++; }
        else if (!parse_braces(ps, &min, &max)) return ps->failed ? NULL : a;
        if (a->kind == N_REP) {
            fail(ps, "a repetition can't be repeated directly (put it in a group)");
            return NULL;
        }
        if (a->kind == N_BOL || a->kind == N_EOL || a->kind == N_WORDB || a->kind == N_NWORDB || a->kind == N_LOOK) {
            fail(ps, "an assertion can't be repeated");
            return NULL;
        }
        r = mk(ps, N_REP);
        if (!r) return NULL;
        r->a = a;
        r->min = min;
        r->max = max;
        if (ps->p < ps->end && *ps->p == '?') {
            r->lazy = 1;
            ps->p++;
        }
        a = r;
    }
}

static node *parse_cat(parser *ps)
{
    node *left = NULL;
    while (ps->p < ps->end && *ps->p != '|' && *ps->p != ')') {
        node *r = parse_repeat(ps), *c;
        if (ps->failed) return NULL;
        if (!left) {
            left = r;
            continue;
        }
        c = mk(ps, N_CAT);
        if (!c) return NULL;
        c->a = left;
        c->b = r;
        left = c;
    }
    return left ? left : mk(ps, N_EMPTY);
}

static node *parse_alt(parser *ps)
{
    node *left = parse_cat(ps);
    while (!ps->failed && ps->p < ps->end && *ps->p == '|') {
        node *n;
        ps->p++;
        n = mk(ps, N_ALT);
        if (!n) return NULL;
        n->a = left;
        n->b = parse_cat(ps);
        left = n;
    }
    return ps->failed ? NULL : left;
}

/* ---- code generation ---- */

typedef struct {
    inst *code;
    int n, cap;
    int nmarks;
    int flags;
    int toobig;
} gen;

#define MAXCODE 200000

static int emit(gen *g, int op, int x, int y)
{
    if (g->n >= MAXCODE) {
        g->toobig = 1;
        return g->n;
    }
    if (g->n == g->cap) {
        g->cap = g->cap ? g->cap * 2 : 64;
        g->code = (inst *)realloc(g->code, sizeof(inst) * (size_t)g->cap);
    }
    g->code[g->n].op = (unsigned char)op;
    g->code[g->n].x = x;
    g->code[g->n].y = y;
    return g->n++;
}

static int nullable(const node *n)
{
    switch (n->kind) {
    case N_CHAR: case N_ANY: case N_CLASS: return 0;
    case N_GROUP: return nullable(n->a);
    case N_CAT: return nullable(n->a) && nullable(n->b);
    case N_ALT: return nullable(n->a) || nullable(n->b);
    case N_REP: return n->min == 0 || nullable(n->a);
    case N_BACKREF: return 1;
    default: return 1;          /* empty, assertions */
    }
}

static void gen_node(gen *g, const node *n);

/* one optional or repeated copy of the body: SPLIT body, out */
static void gen_star(gen *g, const node *body, int lazy)
{
    int l1 = emit(g, I_SPLIT, 0, 0), l2, mark = -1;
    l2 = g->n;
    if (nullable(body)) {
        mark = g->nmarks++;
        emit(g, I_MARK, mark, 0);
    }
    gen_node(g, body);
    if (mark >= 0) emit(g, I_PROGRESS, mark, 0);
    emit(g, I_JMP, l1, 0);
    if (g->toobig) return;
    g->code[l1].x = lazy ? g->n : l2;
    g->code[l1].y = lazy ? l2 : g->n;
}

static void gen_node(gen *g, const node *n)
{
    int i, l, j;
    if (g->toobig) return;
    switch (n->kind) {
    case N_EMPTY:
        break;
    case N_CHAR:
        if ((g->flags & BB_RE_ICASE) && other_case(n->c) != n->c) emit(g, I_CHAR, fold_tab[n->c], 1);
        else emit(g, I_CHAR, n->c, 0);
        break;
    case N_ANY:
        emit(g, I_ANY, 0, 0);
        break;
    case N_CLASS:
        emit(g, I_CLASS, n->c, 0);
        break;
    case N_BOL: emit(g, I_BOL, 0, 0); break;
    case N_EOL: emit(g, I_EOL, 0, 0); break;
    case N_WORDB: emit(g, I_WORDB, 0, 0); break;
    case N_NWORDB: emit(g, I_NWORDB, 0, 0); break;
    case N_BACKREF: emit(g, I_BACKREF, n->c, 0); break;
    case N_GROUP:
        if (n->c > 0) emit(g, I_SAVE, 2 * n->c, 0);
        gen_node(g, n->a);
        if (n->c > 0) emit(g, I_SAVE, 2 * n->c + 1, 0);
        break;
    case N_LOOK:
        l = emit(g, I_LOOK, n->c, 0);
        gen_node(g, n->a);
        emit(g, I_MATCH, 0, 0);
        if (!g->toobig) g->code[l].y = g->n - l - 1;
        break;
    case N_CAT:
        gen_node(g, n->a);
        gen_node(g, n->b);
        break;
    case N_ALT:
        l = emit(g, I_SPLIT, 0, 0);
        if (!g->toobig) g->code[l].x = g->n;
        gen_node(g, n->a);
        j = emit(g, I_JMP, 0, 0);
        if (!g->toobig) g->code[l].y = g->n;
        gen_node(g, n->b);
        if (!g->toobig) g->code[j].x = g->n;
        break;
    case N_REP: {
        int fixups[64], nf = 0, *fx = fixups, capf = 64;
        for (i = 0; i < n->min && !g->toobig; i++) gen_node(g, n->a);
        if (n->max < 0) {
            gen_star(g, n->a, n->lazy);
            break;
        }
        /* max - min optional copies; any of them may end the repetition */
        for (i = n->min; i < n->max && !g->toobig; i++) {
            l = emit(g, I_SPLIT, 0, 0);
            if (nf == capf) {
                int *nfx = (int *)malloc(sizeof(int) * (size_t)capf * 2);
                memcpy(nfx, fx, sizeof(int) * (size_t)nf);
                if (fx != fixups) free(fx);
                fx = nfx;
                capf *= 2;
            }
            fx[nf++] = l;
            if (!g->toobig) {
                if (n->lazy) g->code[l].y = g->n;
                else g->code[l].x = g->n;
            }
            gen_node(g, n->a);
        }
        for (i = 0; i < nf && !g->toobig; i++) {
            if (n->lazy) g->code[fx[i]].x = g->n;
            else g->code[fx[i]].y = g->n;
        }
        if (fx != fixups) free(fx);
        break;
    }
    }
}

static void free_nodes(parser *ps)
{
    int i;
    for (i = 0; i < ps->npool; i++) free(ps->pool[i]);
    free(ps->pool);
    ps->pool = NULL;
    ps->npool = 0;
}

/* the byte every match must start with, if the pattern starts with a plain byte */
static int first_byte(const node *n)
{
    while (n) {
        if (n->kind == N_CHAR) return n->c;
        if (n->kind == N_CAT) n = n->a;
        else if (n->kind == N_GROUP) n = n->a;
        else if (n->kind == N_REP && n->min > 0) n = n->a;
        else return -1;
    }
    return -1;
}

bb_re *bb_re_compile(const char *pat, int patlen, int flags, char *err, int errlen)
{
    parser ps;
    gen g;
    node *root;
    bb_re *re;
    fold_init();
    memset(&ps, 0, sizeof ps);
    memset(&g, 0, sizeof g);
    ps.p = (const unsigned char *)pat;
    ps.end = ps.p + patlen;
    ps.flags = flags;
    ps.err = err;
    ps.errlen = errlen;
    root = parse_alt(&ps);
    if (!ps.failed && ps.p < ps.end) fail(&ps, "unmatched )");
    if (!ps.failed) {
        /* backreferences must name an existing group */
        int i;
        for (i = 0; i < ps.npool; i++) {
            node *n = ps.pool[i];
            if (n->kind == N_BACKREF && n->c > ps.ngroups) {
                fail(&ps, "a backreference to a group that doesn't exist");
                break;
            }
        }
    }
    if (ps.failed || !root) {
        if (!ps.failed) snprintf(err, (size_t)errlen, "out of memory");
        free_nodes(&ps);
        free(ps.sets);
        return NULL;
    }
    g.flags = flags;
    emit(&g, I_SAVE, 0, 0);
    gen_node(&g, root);
    emit(&g, I_SAVE, 1, 0);
    emit(&g, I_MATCH, 0, 0);
    re = (bb_re *)calloc(1, sizeof *re);
    re->first = (flags & BB_RE_ICASE) ? -1 : first_byte(root);
    free_nodes(&ps);
    if (g.toobig) {
        snprintf(err, (size_t)errlen, "the pattern is too big (repetition counts too high)");
        free(g.code);
        free(ps.sets);
        free(re);
        return NULL;
    }
    re->code = g.code;
    re->ncode = g.n;
    re->sets = ps.sets;
    re->nsets = ps.nsets;
    re->ngroups = ps.ngroups;
    re->nmarks = g.nmarks;
    re->flags = flags;
    return re;
}

void bb_re_free(bb_re *re)
{
    if (!re) return;
    free(re->code);
    free(re->sets);
    free(re);
}

int bb_re_ngroups(const bb_re *re) { return re->ngroups; }

/* ---- matching ---- */

enum { BT_BRANCH, BT_RESTORE };
typedef struct { int kind, a, b; } bt;

typedef struct {
    const bb_re *re;
    const unsigned char *s;
    int len;
    int *regs;                  /* captures, then loop marks */
    bt *st;
    int sp, cap;
    long steps;
    int toolong, nomem;
} vm;

#define MAXSTEPS 50000000L

static int push(vm *m, int kind, int a, int b)
{
    if (m->sp == m->cap) {
        int nc = m->cap ? m->cap * 2 : 256;
        bt *n = (bt *)realloc(m->st, sizeof(bt) * (size_t)nc);
        if (!n) {
            m->nomem = 1;
            return 0;
        }
        m->st = n;
        m->cap = nc;
    }
    m->st[m->sp].kind = kind;
    m->st[m->sp].a = a;
    m->st[m->sp].b = b;
    m->sp++;
    return 1;
}

static void setreg(vm *m, int r, int v)
{
    push(m, BT_RESTORE, r, m->regs[r]);
    m->regs[r] = v;
}

/* run from pc at position pos; 1 matched (*endpos), 0 failed. Backtrack entries above base
   belong to this run; on failure they are all gone (registers restored). */
static int run(vm *m, int pc, int pos, int base, int *endpos)
{
    const inst *code = m->re->code;
    const unsigned char *s = m->s;
    int len = m->len, ml = m->re->flags & BB_RE_MULTILINE;
    for (;;) {
        const inst *in = &code[pc];
        int ok = 1;
        if (++m->steps > MAXSTEPS) {
            m->toolong = 1;
            return 0;
        }
        switch (in->op) {
        case I_CHAR:
            if (pos < len && (in->y ? fold_tab[s[pos]] : s[pos]) == in->x) {
                pos++;
                pc++;
            } else
                ok = 0;
            break;
        case I_ANY:
            if (pos < len && s[pos] != '\n') {
                pos++;
                pc++;
            } else
                ok = 0;
            break;
        case I_CLASS:
            if (pos < len && set_has(&m->re->sets[in->x], s[pos])) {
                pos++;
                pc++;
            } else
                ok = 0;
            break;
        case I_SPLIT:
            if (!push(m, BT_BRANCH, in->y, pos)) return 0;
            pc = in->x;
            break;
        case I_JMP:
            pc = in->x;
            break;
        case I_SAVE:
            setreg(m, in->x, pos);
            pc++;
            break;
        case I_BOL:
            ok = pos == 0 || (ml && s[pos - 1] == '\n');
            pc++;
            break;
        case I_EOL:
            ok = pos == len || (ml && s[pos] == '\n');
            pc++;
            break;
        case I_WORDB:
        case I_NWORDB: {
            int a = pos > 0 && is_word(s[pos - 1]), b = pos < len && is_word(s[pos]);
            ok = (a != b) == (in->op == I_WORDB);
            pc++;
            break;
        }
        case I_BACKREF: {
            int st = m->regs[2 * in->x], en = m->regs[2 * in->x + 1], n, i;
            if (st < 0 || en < 0) {     /* a group that didn't take part matches "" */
                pc++;
                break;
            }
            n = en - st;
            if (pos + n > len) ok = 0;
            else if (m->re->flags & BB_RE_ICASE) {
                for (i = 0; i < n; i++) if (fold_tab[s[st + i]] != fold_tab[s[pos + i]]) break;
                ok = i == n;
            } else
                ok = memcmp(s + st, s + pos, (size_t)n) == 0;
            if (ok) pos += n;
            pc++;
            break;
        }
        case I_LOOK: {
            int b0 = m->sp, e, got = run(m, pc + 1, pos, b0, &e);
            if (m->toolong || m->nomem) return 0;
            if (got) {
                if (in->x) {
                    /* negative: undo what the look did, then fail */
                    while (m->sp > b0) {
                        bt *t = &m->st[--m->sp];
                        if (t->kind == BT_RESTORE) m->regs[t->a] = t->b;
                    }
                    ok = 0;
                } else {
                    /* positive: keep its captures (and their undo entries), drop its branches */
                    int i, k = b0;
                    for (i = b0; i < m->sp; i++) if (m->st[i].kind == BT_RESTORE) m->st[k++] = m->st[i];
                    m->sp = k;
                }
            } else
                ok = !!in->x;
            pc += in->y + 1;
            break;
        }
        case I_MARK:
            setreg(m, 2 * (m->re->ngroups + 1) + in->x, pos);
            pc++;
            break;
        case I_PROGRESS:
            ok = m->regs[2 * (m->re->ngroups + 1) + in->x] != pos;
            pc++;
            break;
        case I_MATCH:
            *endpos = pos;
            return 1;
        }
        if (m->nomem) return 0;
        if (!ok) {
            /* backtrack */
            for (;;) {
                bt *t;
                if (m->sp <= base) return 0;
                t = &m->st[--m->sp];
                if (t->kind == BT_RESTORE) m->regs[t->a] = t->b;
                else {
                    pc = t->a;
                    pos = t->b;
                    break;
                }
            }
        }
    }
}

int bb_re_search(const bb_re *re, const char *s, int len, int start, int *caps)
{
    vm m;
    int nregs = 2 * (re->ngroups + 1) + re->nmarks, i, at, endp, rc = BB_RE_NOMATCH;
    int fixed[64];
    memset(&m, 0, sizeof m);
    m.re = re;
    m.s = (const unsigned char *)s;
    m.len = len;
    m.regs = nregs <= 64 ? fixed : (int *)malloc(sizeof(int) * (size_t)nregs);
    if (!m.regs) return BB_RE_NOMEM;
    for (at = start; at <= len; at++) {
        if (re->first >= 0) {
            const char *p = at < len ? memchr(s + at, re->first, (size_t)(len - at)) : NULL;
            if (!p) break;
            at = (int)(p - s);
        }
        for (i = 0; i < nregs; i++) m.regs[i] = -1;
        m.sp = 0;
        if (run(&m, 0, at, 0, &endp)) {
            for (i = 0; i < 2 * (re->ngroups + 1); i++) caps[i] = m.regs[i];
            caps[0] = at;
            caps[1] = endp;
            /* a group whose end wasn't recorded didn't complete */
            for (i = 1; i <= re->ngroups; i++) if (caps[2 * i] < 0 || caps[2 * i + 1] < 0) caps[2 * i] = caps[2 * i + 1] = -1;
            rc = BB_RE_MATCH;
            break;
        }
        if (m.toolong) {
            rc = BB_RE_TOOLONG;
            break;
        }
        if (m.nomem) {
            rc = BB_RE_NOMEM;
            break;
        }
    }
    free(m.st);
    if (m.regs != fixed) free(m.regs);
    return rc;
}
