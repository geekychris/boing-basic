/* sema_expr.c - expression checking: names, calls, members, operators, conversions */
#include "sema.h"
#include "../runtime/boing.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <setjmp.h>
#include <ctype.h>

Node *mk_var(Node *at, Sym *s)
{
    Node *n = node_new(E_VAR, at->file, at->line, at->col);
    n->sym = s;
    n->ty = s->ty;
    s->used = 1;
    return n;
}

Type *cval_type(CVal *v)
{
    if (v->is_nothing) return &ty_object;
    return type_prim(v->type);
}

Node *mk_const_node(Node *at, CVal *v)
{
    Node *n = node_new(E_CONST, at->file, at->line, at->col);
    n->cv = *v;
    n->ty = cval_type(v);
    return n;
}

void cval_from_node(Node *e, CVal *v)
{
    memset(v, 0, sizeof *v);
    v->type = T_VOID;
    if (e && e->kind == E_CONST) *v = e->cv;
}

int is_lvalue(Node *e)
{
    switch (e->kind) {
    case E_VAR: case E_INDEX: case E_FIELD: case E_MFIELD: return 1;
    default: return 0;
    }
}

Sym *new_temp(Ctx *c, Type *t, Node *at)
{
    Sym *s = (Sym *)xcalloc(1, sizeof(Sym));
    s->kind = SK_VAR;
    s->name = xsprintf("$t%d", c->ntemps++);
    s->ty = t;
    s->storage = ST_LOCAL;
    s->mod = c->mod;
    s->proc = c->proc;
    s->line = at->line;
    s->file = at->file;
    proc_local_add(c->proc, s);
    return s;
}

Type *suffix_type(char s)
{
    switch (s) {
    case '%': return &ty_integer;
    case '&': return &ty_long;
    case '!': return &ty_single;
    case '#': return &ty_double;
    case '@': return &ty_currency;
    case '$': return &ty_string;
    default: return NULL;
    }
}

/* the type of a declaration without As or suffix: DefInt etc. by first letter, else Variant */
Type *default_type(Ctx *c, const char *name)
{
    int k;
    if (!name || !c->mod || !isalpha((unsigned char)name[0])) return &ty_variant;
    k = c->mod->deftype[toupper((unsigned char)name[0]) - 'A'];
    switch (k) {
    case T_INTEGER: return &ty_integer;
    case T_LONG: return &ty_long;
    case T_SINGLE: return &ty_single;
    case T_DOUBLE: return &ty_double;
    case T_CURRENCY: return &ty_currency;
    case T_STRING: return &ty_string;
    case T_BOOLEAN: return &ty_boolean;
    case T_BYTE: return &ty_byte;
    case T_DATE: return &ty_date;
    case T_OBJECT: return &ty_object;
    default: return &ty_variant;
    }
}

Sym *declare_implicit(Ctx *c, Node *e)
{
    Sym *s = (Sym *)xcalloc(1, sizeof(Sym));
    Type *t = suffix_type(e->suffix);
    s->kind = SK_VAR;
    s->name = e->name;
    s->ty = t ? t : default_type(c, e->name);
    s->implicit = 1;
    s->mod = c->mod;
    s->line = e->line;
    s->col = e->col;
    s->file = e->file;
    s->proc = c->proc;
    s->storage = ST_LOCAL;
    proc_local_add(c->proc, s);
    scope_add(c->proc->scope, s);
    return s;
}

ClassInfo *find_class(Ctx *c, const char *name)
{
    Sym *s = scope_find(c->scope, name);
    if (s && s->kind == SK_CLASS) return s->cls;
    return NULL;
}

/* ---------- constants ---------- */

static int cv_is_num(CVal *v)
{
    return v->type == T_INTEGER || v->type == T_LONG || v->type == T_BYTE || v->type == T_BOOLEAN ||
           v->type == T_SINGLE || v->type == T_DOUBLE || v->type == T_CURRENCY || v->type == T_DATE;
}
static int cv_is_int(CVal *v) { return v->type == T_INTEGER || v->type == T_LONG || v->type == T_BYTE || v->type == T_BOOLEAN; }
static double cv_num(CVal *v) { return cv_is_int(v) ? (double)v->i : v->d; }

static int fits(int t, int64_t x)
{
    switch (t) {
    case T_BYTE: return x >= 0 && x <= 255;
    case T_INTEGER: case T_BOOLEAN: return x >= -32768 && x <= 32767;
    case T_LONG: return x >= INT32_MIN && x <= INT32_MAX;
    default: return 1;
    }
}

static int int_result_type(CVal *a, CVal *b)
{
    int ta = a->type == T_BOOLEAN ? T_INTEGER : a->type, tb = b ? (b->type == T_BOOLEAN ? T_INTEGER : b->type) : ta;
    if (ta == T_BYTE && tb == T_BYTE) return T_BYTE;
    if (ta == T_LONG || tb == T_LONG) return T_LONG;
    return T_INTEGER;
}

static double round_even(double d)
{
    double f = floor(d), r = d - f;
    if (r > 0.5) return f + 1;
    if (r < 0.5) return f;
    return fmod(f, 2.0) == 0 ? f : f + 1;
}

/* convert a constant to type t at compile time; 0 if not possible */
static int cv_convert(CVal *v, int t, CVal *out)
{
    CVal r;
    memset(&r, 0, sizeof r);
    r.type = t;
    if (v->is_null || v->is_empty || v->is_nothing) return 0;
    if (t == v->type) { *out = *v; return 1; }
    if (cv_is_num(v)) {
        double d = cv_num(v);
        switch (t) {
        case T_BYTE: case T_INTEGER: case T_LONG: {
            double x = cv_is_int(v) ? d : round_even(d);
            if (x != x || !fits(t, (int64_t)x) || x > 9e18 || x < -9e18) return 0;
            r.i = (int64_t)x;
            break;
        }
        case T_BOOLEAN: r.i = d != 0 ? -1 : 0; break;
        case T_SINGLE: r.d = (float)d; break;
        case T_DOUBLE: case T_DATE: r.d = d; break;
        case T_CURRENCY: r.d = round_even(d * 10000.0) / 10000.0; break;
        case T_STRING:
            if (v->type == T_BOOLEAN) { r.s = xstrdup(v->i ? "True" : "False"); r.slen = (int)strlen(r.s); break; }
            if (cv_is_int(v)) { r.s = xsprintf("%lld", (long long)v->i); r.slen = (int)strlen(r.s); break; }
            return 0;
        default: return 0;
        }
        *out = r;
        return 1;
    }
    return 0;
}

int fold_const(Ctx *c, Node *e, CVal *out)
{
    (void)c;
    if (e->kind == E_CONST) { *out = e->cv; return 1; }
    return 0;
}

static Node *fold_binop(Ctx *c, Node *e)
{
    CVal *a = &e->a->cv, *b = &e->b->cv, r;
    int op = e->op;
    memset(&r, 0, sizeof r);
    if (e->a->kind != E_CONST || e->b->kind != E_CONST) return e;
    if (a->is_null || b->is_null || a->is_empty || b->is_empty || a->is_nothing || b->is_nothing) return e;
    if (a->type == T_STRING && b->type == T_STRING) {
        int cmp;
        if (op == OP_CAT || op == OP_ADD) {
            r.type = T_STRING;
            r.slen = a->slen + b->slen;
            r.s = (char *)xmalloc((size_t)r.slen + 1);
            memcpy(r.s, a->s, (size_t)a->slen);
            memcpy(r.s + a->slen, b->s, (size_t)b->slen);
            r.s[r.slen] = 0;
            return mk_const_node(e, &r);
        }
        if (e->text) return e;
        {
            int n = a->slen < b->slen ? a->slen : b->slen;
            cmp = memcmp(a->s, b->s, (size_t)n);
            if (cmp == 0) cmp = a->slen < b->slen ? -1 : a->slen > b->slen;
        }
        r.type = T_BOOLEAN;
        switch (op) {
        case OP_EQ: r.i = cmp == 0; break;
        case OP_NE: r.i = cmp != 0; break;
        case OP_LT: r.i = cmp < 0; break;
        case OP_GT: r.i = cmp > 0; break;
        case OP_LE: r.i = cmp <= 0; break;
        case OP_GE: r.i = cmp >= 0; break;
        default: return e;
        }
        r.i = r.i ? -1 : 0;
        return mk_const_node(e, &r);
    }
    if (op == OP_CAT) {
        CVal sa, sb;
        Node tmp;
        if (!cv_convert(a, T_STRING, &sa) || !cv_convert(b, T_STRING, &sb)) return e;
        memset(&tmp, 0, sizeof tmp);
        r.type = T_STRING;
        r.slen = sa.slen + sb.slen;
        r.s = (char *)xmalloc((size_t)r.slen + 1);
        memcpy(r.s, sa.s, (size_t)sa.slen);
        memcpy(r.s + sa.slen, sb.s, (size_t)sb.slen);
        r.s[r.slen] = 0;
        return mk_const_node(e, &r);
    }
    if (!cv_is_num(a) || !cv_is_num(b)) return e;
    switch (op) {
    case OP_ADD: case OP_SUB: case OP_MUL:
        if (cv_is_int(a) && cv_is_int(b)) {
            int64_t x = op == OP_ADD ? a->i + b->i : op == OP_SUB ? a->i - b->i : a->i * b->i;
            r.type = int_result_type(a, b);
            if (!fits(r.type, x)) return e;
            r.i = x;
            return mk_const_node(e, &r);
        }
        if (e->ty->kind == T_DOUBLE || e->ty->kind == T_SINGLE) {
            double x = cv_num(a), y = cv_num(b);
            r.type = e->ty->kind;
            r.d = op == OP_ADD ? x + y : op == OP_SUB ? x - y : x * y;
            if (r.type == T_SINGLE) r.d = (float)r.d;
            return mk_const_node(e, &r);
        }
        return e;
    case OP_DIV: {
        double x = cv_num(a), y = cv_num(b);
        if (y == 0) return e;
        r.type = e->ty->kind == T_SINGLE ? T_SINGLE : T_DOUBLE;
        r.d = x / y;
        if (r.type == T_SINGLE) r.d = (float)r.d;
        return mk_const_node(e, &r);
    }
    case OP_POW:
        r.type = T_DOUBLE;
        if (cv_num(a) < 0 && cv_num(b) != floor(cv_num(b))) return e;
        r.d = pow(cv_num(a), cv_num(b));
        return mk_const_node(e, &r);
    case OP_IDIV: case OP_MOD: {
        CVal x, y;
        int t = int_result_type(cv_is_int(a) ? a : &(CVal){T_LONG, 0, 0, 0, 0, 0, 0, 0},
                                cv_is_int(b) ? b : &(CVal){T_LONG, 0, 0, 0, 0, 0, 0, 0});
        if (!cv_convert(a, T_LONG, &x) || !cv_convert(b, T_LONG, &y) || y.i == 0) return e;
        r.type = e->ty->kind == T_BYTE ? T_BYTE : t;
        r.i = op == OP_IDIV ? x.i / y.i : x.i % y.i;
        if (!fits(r.type, r.i)) return e;
        return mk_const_node(e, &r);
    }
    case OP_AND: case OP_OR: case OP_XOR: case OP_EQV: case OP_IMP: {
        CVal x, y;
        int64_t v;
        if (!cv_convert(a, T_LONG, &x) || !cv_convert(b, T_LONG, &y)) return e;
        switch (op) {
        case OP_AND: v = x.i & y.i; break;
        case OP_OR: v = x.i | y.i; break;
        case OP_XOR: v = x.i ^ y.i; break;
        case OP_EQV: v = ~(x.i ^ y.i); break;
        default: v = (~x.i) | y.i; break;
        }
        r.type = e->ty->kind;
        if (r.type == T_BYTE) v &= 255;
        else if (r.type == T_INTEGER || r.type == T_BOOLEAN) v = (int16_t)v;
        else v = (int32_t)v;
        r.i = v;
        return mk_const_node(e, &r);
    }
    case OP_EQ: case OP_NE: case OP_LT: case OP_GT: case OP_LE: case OP_GE: {
        double x = cv_num(a), y = cv_num(b);
        int res;
        switch (op) {
        case OP_EQ: res = x == y; break;
        case OP_NE: res = x != y; break;
        case OP_LT: res = x < y; break;
        case OP_GT: res = x > y; break;
        case OP_LE: res = x <= y; break;
        default: res = x >= y; break;
        }
        r.type = T_BOOLEAN;
        r.i = res ? -1 : 0;
        return mk_const_node(e, &r);
    }
    default: return e;
    }
}

/* ---------- conversions ---------- */

static Node *mk_conv(Node *e, Type *to)
{
    Node *n = node_new(E_CONV, e->file, e->line, e->col);
    n->a = e;
    n->ty = to;
    return n;
}

static int class_compatible(ClassInfo *from, ClassInfo *to)
{
    int i;
    if (!to || !from) return 1;     /* Object: checked at run time */
    if (from == to) return 1;
    for (i = 0; i < from->nimpls; i++) if (from->impls[i] == to) return 1;
    if (to->builtin || from->builtin) return 0;
    return 0;
}

static Node *coerce_k(Ctx *c, Node *e, Type *to, int explicit_)
{
    Type *from = e->ty;
    if (!from || !to || to->kind == T_ANY) return e;
    if (from->kind == T_VOID) {
        ERR(c, e, "expression does not produce a value");
        e->ty = &ty_variant;
        return e;
    }
    if (to->kind == T_STRING && to->fixlen) {
        Node *n;
        if (from->kind != T_STRING) e = coerce_k(c, e, &ty_string, explicit_);
        n = mk_conv(e, to);
        return n;
    }
    if (type_eq(from, to)) return e;
    if (to->kind == T_UDT || from->kind == T_UDT) {
        if (to->kind == T_VARIANT || from->kind == T_VARIANT)
            ERR(c, e, "user-defined types cannot be stored in a Variant");
        else
            ERR(c, e, "type mismatch: cannot convert %s to %s", type_name(from), type_name(to));
        return e;
    }
    if (to->kind == T_ARRAY) {
        if (from->kind == T_ARRAY) {
            if (!type_eq(from->elem, to->elem))
                ERR(c, e, "type mismatch: cannot assign %s to %s", type_name(from), type_name(to));
            return e;
        }
        if (from->kind == T_VARIANT) return mk_conv(e, to);
        ERR(c, e, "type mismatch: %s is not an array", type_name(from));
        return e;
    }
    if (from->kind == T_ARRAY) {
        if (to->kind == T_VARIANT) return mk_conv(e, to);
        ERR(c, e, "type mismatch: cannot convert %s to %s", type_name(from), type_name(to));
        return e;
    }
    if (to->kind == T_OBJECT) {
        if (from->kind == T_OBJECT) {
            if (!class_compatible(from->cls, to->cls) && !(e->kind == E_CONST && e->cv.is_nothing))
                ERR(c, e, "type mismatch: cannot assign %s to %s", type_name(from), type_name(to));
            if (e->kind == E_CONST) { e->ty = to; return e; }
            if (from->cls == to->cls || !to->cls) { if (!to->cls) return e; }
            return mk_conv(e, to);
        }
        if (from->kind == T_VARIANT) return mk_conv(e, to);
        ERR(c, e, "type mismatch: object required (found %s)", type_name(from));
        return e;
    }
    if (from->kind == T_OBJECT) {
        /* default member */
        Node *v = mk_conv(e, &ty_variant);
        if (to->kind == T_VARIANT) return v;
        return mk_conv(v, to);
    }
    /* constants */
    if (e->kind == E_CONST && to->kind != T_VARIANT) {
        CVal r;
        if (cv_convert(&e->cv, to->kind, &r)) return mk_const_node(e, &r);
    }
    (void)explicit_;
    return mk_conv(e, to);
}

Node *coerce(Ctx *c, Node *e, Type *to) { return coerce_k(c, e, to, 0); }
Node *coerce_explicit(Ctx *c, Node *e, Type *to)
{
    Node *n = coerce_k(c, e, to, 1);
    if (n->kind == E_CONV) n->flags |= NF_ISDEFAULT;  /* explicit CXxx */
    return n;
}

Node *conv_to_bool_cond(Ctx *c, Node *e)
{
    e = check_value(c, e);
    if (e->ty->kind == T_BOOLEAN) return e;
    if (e->ty->kind == T_VARIANT) return e;     /* emitters use bb_v_truth */
    return coerce(c, e, &ty_boolean);
}

/* ---------- operators ---------- */

static Type *arith_type(Type *a, Type *b)
{
    int ka = a->kind, kb = b->kind;
    if (ka == T_BOOLEAN) ka = T_INTEGER;
    if (kb == T_BOOLEAN) kb = T_INTEGER;
    if (ka == T_STRING) ka = T_DOUBLE;
    if (kb == T_STRING) kb = T_DOUBLE;
    if (ka == T_DATE || kb == T_DATE) return &ty_date;
    if (ka == T_CURRENCY || kb == T_CURRENCY) {
        int o = ka == T_CURRENCY ? kb : ka;
        return (o == T_SINGLE || o == T_DOUBLE) ? &ty_double : &ty_currency;
    }
    if ((ka == T_SINGLE && kb == T_LONG) || (kb == T_SINGLE && ka == T_LONG)) return &ty_double;
    {
        static const int order[] = {T_BYTE, T_INTEGER, T_LONG, T_SINGLE, T_DOUBLE};
        int ra = 0, rb = 0, i;
        for (i = 0; i < 5; i++) { if (order[i] == ka) ra = i; if (order[i] == kb) rb = i; }
        return type_prim(order[ra > rb ? ra : rb]);
    }
}

static Type *int_op_type(Type *a, Type *b)
{
    int ka = a->kind, kb = b ? b->kind : ka;
    if (ka == T_BYTE && kb == T_BYTE) return &ty_byte;
    if ((ka == T_BYTE || ka == T_INTEGER || ka == T_BOOLEAN) && (kb == T_BYTE || kb == T_INTEGER || kb == T_BOOLEAN))
        return &ty_integer;
    return &ty_long;
}

static int is_varlike(Type *t) { return t->kind == T_VARIANT || t->kind == T_OBJECT; }

/* Mid$(s, i, 1) or Left$(s, 1): *ps = s, *pi = i (a Long); 0 if x is something else */
static int one_char_of(Node *x, Node **ps, Node **pi)
{
    const char *nm;
    while (x->kind == E_CONV && x->ty->kind == T_STRING && x->a->ty->kind != T_STRING) x = x->a;
    if (x->kind != E_BUILTIN) return 0;
    nm = builtins[x->bi].name;
    if (name_eq(nm, "Mid") && x->list.n == 3 && x->list.v[2]->kind == E_CONST && x->list.v[2]->cv.i == 1 &&
        x->list.v[0]->ty->kind == T_STRING && x->list.v[1]->ty->kind == T_LONG) {
        *ps = x->list.v[0]; *pi = x->list.v[1];
        return 1;
    }
    if (name_eq(nm, "Left") && x->list.n == 2 && x->list.v[1]->kind == E_CONST && x->list.v[1]->cv.i == 1 &&
        x->list.v[0]->ty->kind == T_STRING) {
        *ps = x->list.v[0]; *pi = NULL;
        return 1;
    }
    return 0;
}

static Node *long_const(Node *at, int64_t v)
{
    CVal cv;
    memset(&cv, 0, sizeof cv);
    cv.type = T_LONG;
    cv.i = v;
    return mk_const_node(at, &cv);
}

static Node *bare_builtin(Ctx *c, Node *at, int bi);

/* __ascat / __charat(s, i): the byte at i, no one-character string */
static Node *char_at_node(Ctx *c, Node *at, const char *fn, Node *str, Node *idx)
{
    Node *n = bare_builtin(c, at, builtin_find(fn));
    nl_push(&n->list, str);
    nl_push(&n->list, idx ? idx : long_const(at, 1));
    return n;
}

/* Mid$(s, i, 1) = "x" / Left$(s, 1) <> "x" (binary compare): a byte compare */
static Node *char_compare(Ctx *c, Node *e)
{
    Node *str, *idx, *k;
    int swap = 0;
    if ((e->op != OP_EQ && e->op != OP_NE) || e->text) return NULL;
    if (e->b->kind == E_CONST && e->b->ty->kind == T_STRING && e->b->cv.slen == 1 && one_char_of(e->a, &str, &idx)) k = e->b;
    else if (e->a->kind == E_CONST && e->a->ty->kind == T_STRING && e->a->cv.slen == 1 && one_char_of(e->b, &str, &idx)) { k = e->a; swap = 1; }
    else return NULL;
    (void)swap;
    e->a = char_at_node(c, e, "__charat", str, idx);
    e->b = long_const(k, (unsigned char)k->cv.s[0]);
    e->ty = &ty_boolean;
    return e;
}

static Node *check_binop(Ctx *c, Node *e)
{
    Type *ta, *tb, *rt = NULL;
    e->a = check_value(c, e->a);
    e->b = check_value(c, e->b);
    e->text = c->mod->opt_text;
    ta = e->a->ty;
    tb = e->b->ty;
    if (ta->kind == T_UDT || tb->kind == T_UDT || ta->kind == T_ARRAY || tb->kind == T_ARRAY) {
        if (!(e->op == OP_IS)) {
            ERR(c, e, "type mismatch: operator cannot be applied to %s and %s", type_name(ta), type_name(tb));
            e->ty = &ty_variant;
            return e;
        }
    }
    if (e->op == OP_IS) {
        if ((ta->kind != T_OBJECT && ta->kind != T_VARIANT) || (tb->kind != T_OBJECT && tb->kind != T_VARIANT))
            ERR(c, e, "'Is' needs object operands");
        e->a = coerce(c, e->a, ta->kind == T_VARIANT ? &ty_variant : &ty_object);
        e->b = coerce(c, e->b, tb->kind == T_VARIANT ? &ty_variant : &ty_object);
        if (e->a->ty->kind != e->b->ty->kind) {
            e->a = coerce(c, e->a, &ty_variant);
            e->b = coerce(c, e->b, &ty_variant);
        }
        e->ty = &ty_boolean;
        return e;
    }
    /* Variant (or object default member) arithmetic happens at run time */
    if (is_varlike(ta) || is_varlike(tb) || (e->a->kind == E_CONST && (e->a->cv.is_null || e->a->cv.is_empty)) ||
        (e->b->kind == E_CONST && (e->b->cv.is_null || e->b->cv.is_empty))) {
        e->a = coerce(c, e->a, &ty_variant);
        e->b = coerce(c, e->b, &ty_variant);
        if (e->op == OP_LIKE) {
            e->a = coerce(c, e->a, &ty_string);
            e->b = coerce(c, e->b, &ty_string);
            e->ty = &ty_boolean;
            return e;
        }
        e->ty = &ty_variant;
        return e;
    }
    switch (e->op) {
    case OP_ADD:
        if (ta->kind == T_STRING && tb->kind == T_STRING) { e->op = OP_CAT; rt = &ty_string; break; }
        /* fallthrough */
    case OP_SUB: case OP_MUL:
        if (ta->kind == T_STRING || tb->kind == T_STRING) {
            rt = &ty_double;
            if (ta->kind == T_DATE || tb->kind == T_DATE) rt = &ty_date;
        } else rt = arith_type(ta, tb);
        if (e->op == OP_SUB && ta->kind == T_DATE && tb->kind == T_DATE) rt = &ty_double;
        if (e->op == OP_MUL && rt->kind == T_DATE) rt = &ty_double;
        if (rt->kind == T_DATE) {
            e->a = coerce(c, e->a, &ty_double);
            e->b = coerce(c, e->b, &ty_double);
        } else {
            e->a = coerce(c, e->a, rt);
            e->b = coerce(c, e->b, rt);
        }
        break;
    case OP_DIV: {
        int ka = ta->kind, kb = tb->kind;
        int small_a = ka == T_SINGLE || ka == T_BYTE || ka == T_INTEGER || ka == T_BOOLEAN;
        int small_b = kb == T_SINGLE || kb == T_BYTE || kb == T_INTEGER || kb == T_BOOLEAN;
        if ((ka == T_SINGLE || kb == T_SINGLE) && small_a && small_b) rt = &ty_single;
        else rt = &ty_double;
        e->a = coerce(c, e->a, rt);
        e->b = coerce(c, e->b, rt);
        break;
    }
    case OP_POW:
        rt = &ty_double;
        e->a = coerce(c, e->a, rt);
        e->b = coerce(c, e->b, rt);
        break;
    case OP_IDIV: case OP_MOD:
        rt = int_op_type(type_is_integral(ta) ? ta : &ty_long, type_is_integral(tb) ? tb : &ty_long);
        e->a = coerce(c, e->a, rt);
        e->b = coerce(c, e->b, rt);
        break;
    case OP_CAT:
        rt = &ty_string;
        e->a = coerce(c, e->a, rt);
        e->b = coerce(c, e->b, rt);
        break;
    case OP_EQ: case OP_NE: case OP_LT: case OP_GT: case OP_LE: case OP_GE: {
        Type *ct;
        if (ta->kind == T_STRING && tb->kind == T_STRING) ct = &ty_string;
        else if (ta->kind == T_STRING || tb->kind == T_STRING) {
            Type *o = ta->kind == T_STRING ? tb : ta;
            ct = (o->kind == T_DATE) ? &ty_date : (o->kind == T_BOOLEAN ? &ty_boolean : &ty_double);
            if (o->kind == T_CURRENCY) ct = &ty_currency;
        } else if (ta->kind == T_BOOLEAN && tb->kind == T_BOOLEAN) ct = &ty_integer;
        else {
            ct = arith_type(ta, tb);
            if (ct->kind == T_DATE) ct = &ty_double;
            if (ct->kind == T_BYTE) ct = &ty_integer;
        }
        e->a = coerce(c, e->a, ct);
        e->b = coerce(c, e->b, ct);
        rt = &ty_boolean;
        if (ct->kind == T_STRING && char_compare(c, e)) return e;
        break;
    }
    case OP_LIKE:
        e->a = coerce(c, e->a, &ty_string);
        e->b = coerce(c, e->b, &ty_string);
        rt = &ty_boolean;
        break;
    case OP_AND: case OP_OR: case OP_XOR: case OP_EQV: case OP_IMP:
        if (ta->kind == T_BOOLEAN && tb->kind == T_BOOLEAN) rt = &ty_boolean;
        else rt = int_op_type(type_is_integral(ta) ? ta : &ty_long, type_is_integral(tb) ? tb : &ty_long);
        e->a = coerce(c, e->a, rt);
        e->b = coerce(c, e->b, rt);
        break;
    default:
        rt = &ty_variant;
    }
    e->ty = rt;
    return fold_binop(c, e);
}

static Node *check_unop(Ctx *c, Node *e)
{
    Type *t;
    e->a = check_value(c, e->a);
    t = e->a->ty;
    if (t->kind == T_UDT || t->kind == T_ARRAY) {
        ERR(c, e, "type mismatch: operator cannot be applied to %s", type_name(t));
        e->ty = &ty_variant;
        return e;
    }
    if (is_varlike(t) || (e->a->kind == E_CONST && (e->a->cv.is_null || e->a->cv.is_empty))) {
        e->a = coerce(c, e->a, &ty_variant);
        e->ty = &ty_variant;
        if (e->op == OP_PLUS) return e->a;
        return e;
    }
    if (e->op == OP_PLUS) {
        if (t->kind == T_STRING) return coerce(c, e->a, &ty_double);
        return e->a;
    }
    if (e->op == OP_NEG) {
        Type *rt = t;
        if (t->kind == T_BYTE || t->kind == T_BOOLEAN) rt = &ty_integer;
        if (t->kind == T_STRING) rt = &ty_double;
        e->a = coerce(c, e->a, rt);
        e->ty = rt;
        if (e->a->kind == E_CONST) {
            CVal r = e->a->cv;
            if (cv_is_int(&r)) {
                if (fits(r.type, -r.i)) { r.i = -r.i; return mk_const_node(e, &r); }
                /* -32768: literal 32768 is Long; - of Long 32768 */
                return e;
            }
            if (r.type == T_DOUBLE || r.type == T_SINGLE || r.type == T_CURRENCY || r.type == T_DATE) { r.d = -r.d; return mk_const_node(e, &r); }
        }
        return e;
    }
    /* Not */
    {
        Type *rt = t->kind == T_BOOLEAN ? &ty_boolean : int_op_type(type_is_integral(t) ? t : &ty_long, NULL);
        e->a = coerce(c, e->a, rt);
        e->ty = rt;
        if (e->a->kind == E_CONST) {
            CVal r = e->a->cv;
            r.i = ~r.i;
            if (rt->kind == T_BYTE) r.i &= 255;
            return mk_const_node(e, &r);
        }
        return e;
    }
}

/* ---------- calls ---------- */

static Node *default_arg(Ctx *c, Node *at, Param *pa)
{
    Node *n;
    if (pa->has_def) {
        n = mk_const_node(at, &pa->def);
        return coerce(c, n, pa->ty);
    }
    if (pa->ty->kind == T_VARIANT) {
        n = node_new(E_MISSING, at->file, at->line, at->col);
        n->ty = &ty_variant;
        return n;
    }
    {
        /* typed Optional without default: the type's zero value */
        CVal v;
        memset(&v, 0, sizeof v);
        v.type = pa->ty->kind;
        if (pa->ty->kind == T_OBJECT) { v.type = T_OBJECT; v.is_nothing = 1; }
        if (pa->ty->kind == T_STRING) { v.s = xstrdup(""); v.slen = 0; }
        n = mk_const_node(at, &v);
        n->ty = pa->ty;
        return n;
    }
}

/* argument for a ByRef parameter: pass the variable itself when the types match */
static Node *byref_arg(Ctx *c, Node *arg, Param *pa, Proc *pr)
{
    Node *a = arg;
    int paren = arg->kind == E_PAREN;
    if (paren) {
        a = check_value(c, arg->a);
        a->flags |= NF_PARENARG;
        return coerce(c, a, pa->ty);
    }
    a = check_expr(c, arg, M_ARG);
    if (pa->ty->kind == T_ARRAY) {
        if (a->ty->kind == T_ARRAY) {
            if (!type_eq(a->ty->elem, pa->ty->elem) && pa->ty->elem->kind != T_VARIANT && pr->kind != PK_DECLARE)
                ERR(c, arg, "ByRef argument type mismatch: %s passed for %s", type_name(a->ty), type_name(pa->ty));
            if (!type_eq(a->ty->elem, pa->ty->elem)) ERR(c, arg, "ByRef argument type mismatch: %s passed for %s", type_name(a->ty), type_name(pa->ty));
            if (!is_lvalue(a)) ERR(c, arg, "an array argument must be an array variable");
            a->flags |= NF_BYREF;
            return a;
        }
        ERR(c, arg, "type mismatch: array required for parameter '%s'", pa->name);
        return a;
    }
    if (is_lvalue(a) && type_eq(a->ty, pa->ty) && !(a->ty->kind == T_STRING && a->ty->fixlen)) {
        a->flags |= NF_BYREF;
        return a;
    }
    if (is_lvalue(a) && pa->ty->kind != T_VARIANT && a->kind == E_VAR && pr->kind != PK_DECLARE &&
        a->ty->kind != T_UDT && !(a->ty->kind == T_OBJECT && pa->ty->kind == T_OBJECT)) {
        ERR(c, arg, "ByRef argument type mismatch: %s variable passed for %s parameter '%s'",
            type_name(a->ty), type_name(pa->ty), pa->name);
        return a;
    }
    if (pa->ty->kind == T_UDT) {
        if (!type_eq(a->ty, pa->ty)) ERR(c, arg, "type mismatch: %s passed for %s", type_name(a->ty), type_name(pa->ty));
        return a;
    }
    return coerce(c, a, pa->ty);
}

Node *make_call(Ctx *c, Node *at, Proc *pr, NodeList *args, Node *self, int mode)
{
    Node *n = node_new(self ? E_MCALL : E_CALL, at->file, at->line, at->col);
    Node **slots;
    int i, np = pr->nparams, nargs = args ? args->n : 0;
    int pa_index = -1;
    n->proc = pr;
    n->a = self;
    n->ty = pr->ret ? pr->ret : &ty_void;
    if (self && pr->cls) n->cls = pr->cls;
    if (mode == M_VALUE && !pr->ret) {
        ERR(c, at, "'%s' is a Sub and does not return a value", pr->name);
        n->ty = &ty_variant;
    }
    if (np && pr->params[np - 1].paramarray) pa_index = np - 1;
    slots = (Node **)xcalloc((size_t)(np + 1), sizeof(Node *));
    /* positional, then named */
    for (i = 0; i < nargs; i++) {
        Node *a = args->v[i];
        if (a->kind == E_NAMEDARG) {
            int k, found = 0;
            for (k = 0; k < np; k++)
                if (name_eq(pr->params[k].name, a->name)) {
                    if (slots[k]) ERR(c, a, "argument '%s' given twice", a->name);
                    slots[k] = a->a;
                    found = 1;
                }
            if (!found) ERR(c, a, "'%s' has no parameter named '%s'", pr->name, a->name);
            continue;
        }
        if (pa_index >= 0 && i >= pa_index) break;
        if (i >= np) {
            ERR(c, a, "too many arguments to '%s' (expected %d)", pr->name, np);
            break;
        }
        slots[i] = a;
    }
    for (i = 0; i < np; i++) {
        Param *pa = &pr->params[i];
        Node *a = slots[i];
        if (i == pa_index) {
            Node *arr = node_new(E_ARRAYLIT, at->file, at->line, at->col);
            int k;
            for (k = pa_index; k < nargs; k++) {
                Node *x = args->v[k];
                if (x->kind == E_NAMEDARG) continue;
                if (x->kind == E_MISSING) { x->ty = &ty_variant; nl_push(&arr->list, x); continue; }
                nl_push(&arr->list, coerce(c, check_value(c, x), &ty_variant));
            }
            arr->ty = type_array(&ty_variant, 1);
            nl_push(&n->list, arr);
            continue;
        }
        if (!a || a->kind == E_MISSING) {
            if (!pa->optional) {
                ERR(c, a ? a : at, "argument '%s' of '%s' is not optional", pa->name, pr->name);
                nl_push(&n->list, default_arg(c, at, pa));
                continue;
            }
            nl_push(&n->list, default_arg(c, a ? a : at, pa));
            continue;
        }
        if (pa->byref) nl_push(&n->list, byref_arg(c, a, pa, pr));
        else {
            Node *v = check_value(c, a);
            if (pa->ty->kind == T_UDT && !type_eq(v->ty, pa->ty))
                ERR(c, a, "type mismatch: %s passed for %s", type_name(v->ty), type_name(pa->ty));
            nl_push(&n->list, coerce(c, v, pa->ty));
        }
    }
    free(slots);
    return n;
}

/* ---------- builtins ---------- */

static Type *bi_param_type(char ch)
{
    switch (ch) {
    case 's': return &ty_string;
    case 'l': case 'T': return &ty_long;
    case 'i': return &ty_integer;
    case 'd': return &ty_double;
    case 'f': return &ty_single;
    case 'D': return &ty_date;
    case 'b': return &ty_boolean;
    case 'c': return &ty_currency;
    case 'v': return &ty_variant;
    default: return NULL;
    }
}

static const char *nth_default(const char *defs, int k, int *len)
{
    const char *p = defs;
    while (k-- > 0) {
        const char *q = strchr(p, ',');
        if (!q) { *len = 0; return ""; }
        p = q + 1;
    }
    {
        const char *q = strchr(p, ',');
        *len = q ? (int)(q - p) : (int)strlen(p);
    }
    return p;
}

static Node *bi_default(Ctx *c, Node *at, const Builtin *b, int k)
{
    int len;
    const char *d = nth_default(b->defaults, k, &len);
    char ch = b->params[k];
    CVal v;
    memset(&v, 0, sizeof v);
    if (len == 1 && d[0] == 'M') {
        Node *n = node_new(E_MISSING, at->file, at->line, at->col);
        n->ty = &ty_variant;
        return n;
    }
    if (len == 1 && d[0] == 'T') {
        v.type = T_LONG;
        v.i = c->mod->opt_text;
        return mk_const_node(at, &v);
    }
    if (ch == 's') {
        v.type = T_STRING;
        v.s = xstrndup(d, (size_t)len);
        v.slen = len;
        return mk_const_node(at, &v);
    }
    v.type = T_LONG;
    v.i = strtol(d, NULL, 10);
    return coerce(c, mk_const_node(at, &v), bi_param_type(ch) ? bi_param_type(ch) : &ty_long);
}

static Node *array_arg(Ctx *c, Node *a)
{
    Node *v = check_expr(c, a, M_ARG);
    if (v->ty->kind == T_ARRAY) return v;
    if (v->ty->kind == T_VARIANT) return v;
    ERR(c, a, "type mismatch: array required");
    return v;
}

static Node *make_builtin(Ctx *c, Node *at, int bi, NodeList *args, int mode, char suffix)
{
    const Builtin *b = &builtins[bi];
    Node *n = node_new(E_BUILTIN, at->file, at->line, at->col);
    int nargs = args ? args->n : 0, i, np = (int)strlen(b->params);
    n->bi = bi;
    n->name = (char *)b->name;
    n->ty = b->ret == T_ARRAY ? type_array(&ty_string, 1) : type_prim(b->ret);
    n->text = c->mod->opt_text;
    if (suffix == '$' && !(b->flags & BIF_STRSUFFIX)) ERR(c, at, "'%s$' is not a function", b->name);
    if (mode == M_VALUE && b->ret == T_VOID) ERR(c, at, "'%s' does not return a value", b->name);
    /* trailing missing args */
    while (nargs > 0 && args->v[nargs - 1]->kind == E_MISSING && nargs > b->minargs) nargs--;
    if (nargs < b->minargs || nargs > b->maxargs) {
        ERR(c, at, "wrong number of arguments to '%s'", b->name);
        n->ty = n->ty->kind == T_VOID ? &ty_void : n->ty;
        return n;
    }
    /* InStr([start,] s1, s2[, compare]) */
    if (name_eq(b->name, "InStr") && nargs == 2) {
        CVal one;
        memset(&one, 0, sizeof one);
        one.type = T_LONG;
        one.i = 1;
        nl_push(&n->list, mk_const_node(at, &one));
        nl_push(&n->list, coerce(c, check_value(c, args->v[0]), &ty_string));
        nl_push(&n->list, coerce(c, check_value(c, args->v[1]), &ty_string));
        nl_push(&n->list, bi_default(c, at, b, 3));
        return n;
    }
    if (b->flags & BIF_VARARGS) {
        int start = 0;
        if (np) {
            nl_push(&n->list, coerce(c, check_value(c, args->v[0]), bi_param_type(b->params[0])));
            start = 1;
        }
        for (i = start; i < nargs; i++) {
            if (args->v[i]->kind == E_MISSING) { ERR(c, args->v[i], "argument required"); continue; }
            nl_push(&n->list, coerce(c, check_value(c, args->v[i]), &ty_variant));
        }
        return n;
    }
    for (i = 0; i < np; i++) {
        char ch = b->params[i];
        Node *a = i < nargs ? args->v[i] : NULL;
        if (a && a->kind == E_NAMEDARG) a = a->a;
        if (!a || a->kind == E_MISSING) {
            if (i < b->minargs) { ERR(c, at, "argument %d of '%s' is required", i + 1, b->name); continue; }
            nl_push(&n->list, bi_default(c, at, b, i));
            continue;
        }
        if (ch == 'a') { nl_push(&n->list, array_arg(c, a)); continue; }
        if (ch == 'r') {
            /* VarPtr(variable): the variable itself, by reference */
            Node *v = check_expr(c, a, M_ARG);
            if (!is_lvalue(v)) ERR(c, a, "'%s' needs a variable", b->name);
            v->flags |= NF_BYREF;
            nl_push(&n->list, v);
            continue;
        }
        nl_push(&n->list, coerce(c, check_value(c, a), bi_param_type(ch)));
    }
    /* extra ignored args (helpfile etc.) are still evaluated */
    for (; i < nargs; i++) if (args->v[i]->kind != E_MISSING) nl_push(&n->list2, check_value(c, args->v[i]));
    return n;
}

/* conversion functions CInt & co. */
static Type *conv_fn_type(const char *name)
{
    static const struct { const char *n; int t; } tab[] = {
        {"CInt", T_INTEGER}, {"CLng", T_LONG}, {"CSng", T_SINGLE}, {"CDbl", T_DOUBLE},
        {"CStr", T_STRING}, {"CBool", T_BOOLEAN}, {"CByte", T_BYTE}, {"CDate", T_DATE},
        {"CVDate", T_DATE}, {"CVar", T_VARIANT}, {"CCur", T_CURRENCY},
        {NULL, 0}
    };
    int i;
    for (i = 0; tab[i].n; i++) if (name_eq(tab[i].n, name)) return type_prim(tab[i].t);
    return NULL;
}

static Node *special_builtin(Ctx *c, Node *at, const char *name, NodeList *args, int mode, char suffix, int *handled);

/* a type named in a .bbx signature */
static Type *ext_type(Ctx *c, Node *at, const char *name)
{
    Node *tn = node_new(E_NAME, at->file, at->line, at->col);
    tn->name = (char *)name;
    return resolve_type(c, tn, 0, NULL);
}

/* a call of an extension function: arguments converted to the declared types (then passed as
   Variants), the result converted from the Variant it returns */
static Node *ext_call(Ctx *c, Node *e, ExtFunc *xf, NodeList *args, int mode)
{
    Node *n = node_new(E_EXTCALL, e->file, e->line, e->col);
    int i, na = args ? args->n : 0;
    n->name = xf->name;
    if (na != xf->np) ERR(c, e, "'%s' takes %d argument%s, not %d", xf->name, xf->np, xf->np == 1 ? "" : "s", na);
    for (i = 0; i < na && i < xf->np; i++) {
        Node *a = args->v[i];
        if (a->kind == E_MISSING || a->kind == E_NAMEDARG) { ERR(c, a, "argument %d of '%s' is required", i + 1, xf->name); continue; }
        nl_push(&n->list, coerce(c, coerce(c, check_value(c, a), ext_type(c, e, xf->p[i].type)), &ty_variant));
    }
    if (!xf->ret) {
        if (mode == M_VALUE) ERR(c, e, "'%s' does not return a value", xf->name);
        n->ty = &ty_void;
        return n;
    }
    n->ty = &ty_variant;
    return coerce(c, n, ext_type(c, e, xf->ret));
}

/* ---------- names ---------- */

static Node *err_prop(Ctx *c, Node *at, const char *member, NodeList *args, int mode);

/* resolve a bare name, possibly applied to args (args NULL = no parentheses) */
static Node *resolve_name(Ctx *c, Node *e, NodeList *args, int mode)
{
    Sym *s = scope_find(c->scope, e->name);
    int bi;
    if (s && s->is_retvar && args && s->proc) {
        /* F(...) inside F: a recursive call */
        {
            Sym *ps = scope_find(c->mod->scope, e->name);
            if (ps && ps->kind == SK_PROC) s = ps;
            else if (ps && ps->kind == SK_PROPGROUP) s = ps;
        }
    }
    if (s && s->kind == SK_VAR && s->is_retvar && mode == M_STMT && !args) {
        /* "F" as a statement inside F: a call */
        Sym *ps = scope_find(c->mod->scope, e->name);
        if (ps && ps->kind == SK_PROC) s = ps;
    }
    if (s) {
        Type *st = suffix_type(e->suffix);
        if (st && s->kind == SK_VAR && !type_eq(st, s->ty) && s->ty->kind != T_ARRAY)
            ERR(c, e, "type suffix '%c' does not match the declared type of '%s'", e->suffix, e->name);
        switch (s->kind) {
        case SK_VAR: {
            Node *v = mk_var(e, s);
            if (s->storage == ST_GLOBAL) {
                if (!s->user) s->user = c->proc;
                else if (s->user != c->proc) s->shared = 1;
            }
            if (s->storage == ST_FIELD && c->cls == NULL) ERR(c, e, "'%s' is an instance variable", s->name);
            if (!args) return v;
            if (s->ty->kind == T_ARRAY) {
                Node *ix = node_new(E_INDEX, e->file, e->line, e->col);
                int i;
                ix->a = v;
                ix->ty = s->ty->elem;
                if (s->ty->ndims && args->n != s->ty->ndims)
                    ERR(c, e, "wrong number of dimensions for array '%s'", s->name);
                for (i = 0; i < args->n; i++) {
                    if (args->v[i]->kind == E_MISSING) { ERR(c, args->v[i], "array index required"); continue; }
                    nl_push(&ix->list, coerce(c, check_value(c, args->v[i]), &ty_long));
                }
                return ix;
            }
            if (s->ty->kind == T_VARIANT || s->ty->kind == T_OBJECT) {
                Node *l = node_new(E_LATE, e->file, e->line, e->col);
                int i;
                l->a = v;
                l->name = xstrdup("");
                l->ty = &ty_variant;
                l->argc_kind = BB_INV_GET | BB_INV_METHOD;
                for (i = 0; i < args->n; i++) nl_push(&l->list, coerce(c, check_value(c, args->v[i]), &ty_variant));
                return l;
            }
            if (s->ty->kind == T_STRING && args->n == 0) return v;
            ERR(c, e, "'%s' is not an array or a function", s->name);
            return v;
        }
        case SK_CONST:
            if (args) ERR(c, e, "constant '%s' cannot be called", s->name);
            {
                Node *k = mk_const_node(e, &s->cv);
                k->sym = s;             /* which constant (vbNullString passes 0 to a Declare) */
                if (s->ty) k->ty = s->ty;
                if (s->cv.is_nothing) k->ty = &ty_object;
                return k;
            }
        case SK_PROC:
            if (s->proc->cls && !c->cls) { ERR(c, e, "'%s' is a method", s->name); return e; }
            {
                Node *me = NULL;
                if (s->proc->cls) { me = node_new(E_ME, e->file, e->line, e->col); me->ty = type_object(c->cls); }
                {
                    Node *r = make_call(c, e, s->proc, args, NULL, mode);
                    (void)me;
                    return r;
                }
            }
        case SK_PROPGROUP: {
            Proc *pr = (mode == M_LVAL) ? s->plet : (mode == M_SETLVAL ? s->pset : s->pget);
            if (mode == M_LVAL || mode == M_SETLVAL) {
                /* caller completes the Let/Set call with the value */
                Node *pn = node_new(E_DEFPROP, e->file, e->line, e->col);
                pn->sym = s;
                pn->list = args ? *args : pn->list;
                pn->ty = s->pget ? s->pget->ret : &ty_variant;
                return pn;
            }
            if (!pr) { ERR(c, e, "property '%s' has no Get", s->name); return e; }
            return make_call(c, e, pr, args, NULL, mode == M_STMT ? M_VALUE : mode);
        }
        case SK_CLASS: case SK_UDT: case SK_ENUM: case SK_MODULE:
            ERR(c, e, "'%s' is a type or module name, not a value", s->name);
            e->ty = &ty_variant;
            return e;
        default: break;
        }
    }
    /* conversions */
    {
        Type *ct = conv_fn_type(e->name);
        if (ct) {
            Node *v;
            if (!args || args->n != 1 || args->v[0]->kind == E_MISSING) {
                ERR(c, e, "'%s' takes one argument", e->name);
                e->ty = ct;
                return e;
            }
            v = check_value(c, args->v[0]);
            if (ct->kind == T_VARIANT) return coerce(c, v, ct);
            {
                Node *r = coerce_explicit(c, v, ct);
                if (r == v) {
                    /* same type: still a value, not an lvalue */
                    Node *k = node_new(E_CONV, e->file, e->line, e->col);
                    k->a = v;
                    k->ty = ct;
                    k->flags |= NF_ISDEFAULT;
                    if (v->kind == E_CONST) return v;
                    return k;
                }
                return r;
            }
        }
    }
    if (name_eq(e->name, "Err") && !s) return err_prop(c, e, "Number", args, mode);
    {
        int handled = 0;
        Node *r = special_builtin(c, e, e->name, args, mode, e->suffix, &handled);
        if (handled) return r;
    }
    bi = builtin_find(e->name);
    if (bi >= 0) {
        Node *n = make_builtin(c, e, bi, args, mode, e->suffix);
        Node *str, *idx;
        /* Asc(Mid$(s, i, 1)), Asc(Left$(s, 1)): the byte */
        if (name_eq(builtins[bi].name, "Asc") && n->list.n == 1 && one_char_of(n->list.v[0], &str, &idx))
            return char_at_node(c, e, "__ascat", str, idx);
        return n;
    }
    {
        /* a function of a linked extension (its .bbx) or Declare ... Lib "C" */
        ExtFunc *xf = ext_func_find(c->prog, e->name);
        if (xf) return ext_call(c, e, xf, args, mode);
    }
    /* implicit declaration */
    if (args) {
        ERR(c, e, "Sub, Function or array '%s' is not defined", e->name);
        e->ty = &ty_variant;
        return e;
    }
    if (c->mod->opt_explicit) {
        ERR(c, e, "variable '%s' is not defined", e->name);
        s = declare_implicit(c, e);
        return mk_var(e, s);
    }
    if (mode == M_STMT) {
        ERR(c, e, "Sub '%s' is not defined", e->name);
        e->ty = &ty_variant;
        return e;
    }
    s = declare_implicit(c, e);
    return mk_var(e, s);
}

/* ---------- Err ---------- */

enum { ERRP_NUMBER = 1, ERRP_DESC, ERRP_SOURCE, ERRP_RAISE, ERRP_CLEAR, ERRP_LASTDLL, ERRP_HELPFILE, ERRP_HELPCTX };

static Node *err_prop(Ctx *c, Node *at, const char *member, NodeList *args, int mode)
{
    Node *n = node_new(E_ERRPROP, at->file, at->line, at->col);
    int i;
    if (name_eq(member, "Number")) { n->op = ERRP_NUMBER; n->ty = &ty_long; }
    else if (name_eq(member, "Description")) { n->op = ERRP_DESC; n->ty = &ty_string; }
    else if (name_eq(member, "Source")) { n->op = ERRP_SOURCE; n->ty = &ty_string; }
    else if (name_eq(member, "LastDllError")) { n->op = ERRP_LASTDLL; n->ty = &ty_long; }
    else if (name_eq(member, "HelpFile")) { n->op = ERRP_HELPFILE; n->ty = &ty_string; }
    else if (name_eq(member, "HelpContext")) { n->op = ERRP_HELPCTX; n->ty = &ty_long; }
    else if (name_eq(member, "Clear")) { n->op = ERRP_CLEAR; n->ty = &ty_void; }
    else if (name_eq(member, "Raise")) {
        n->op = ERRP_RAISE;
        n->ty = &ty_void;
        if (!args || args->n < 1 || args->v[0]->kind == E_MISSING) { ERR(c, at, "Err.Raise needs an error number"); return n; }
        for (i = 0; i < 3; i++) {
            Node *a = args && i < args->n ? args->v[i] : NULL;
            if (a && a->kind == E_NAMEDARG) a = a->a;
            if (!a || a->kind == E_MISSING) {
                Node *m = node_new(E_MISSING, at->file, at->line, at->col);
                m->ty = &ty_variant;
                nl_push(&n->list, m);
            } else nl_push(&n->list, coerce(c, check_value(c, a), i == 0 ? &ty_long : &ty_variant));
        }
        return n;
    } else {
        ERR(c, at, "the Err object has no member '%s'", member);
        n->ty = &ty_variant;
        return n;
    }
    if (mode == M_VALUE && n->ty->kind == T_VOID) ERR(c, at, "Err.%s has no value", member);
    return n;
}

/* ---------- members ---------- */

static Sym *class_member(ClassInfo *cls, const char *name)
{
    if (!cls || !cls->mod) return NULL;
    return scope_find_local(cls->mod->scope, name);
}

static Node *late(Ctx *c, Node *at, Node *obj, const char *name, NodeList *args, int kind)
{
    Node *l = node_new(E_LATE, at->file, at->line, at->col);
    int i;
    l->a = obj;
    l->name = xstrdup(name);
    l->ty = &ty_variant;
    l->argc_kind = kind;
    if (args)
        for (i = 0; i < args->n; i++) {
            Node *a = args->v[i];
            if (a->kind == E_NAMEDARG) { ERR(c, a, "named arguments are not supported in late-bound calls"); a = a->a; }
            if (a->kind == E_MISSING) { a->ty = &ty_variant; nl_push(&l->list, a); continue; }
            nl_push(&l->list, coerce(c, check_value(c, a), &ty_variant));
        }
    return l;
}

static Node *index_node(Ctx *c, Node *at, Node *arr, NodeList *args)
{
    Node *ix = node_new(E_INDEX, at->file, at->line, at->col);
    int i;
    ix->a = arr;
    ix->ty = arr->ty->elem;
    if (arr->ty->ndims && args->n != arr->ty->ndims) ERR(c, at, "wrong number of dimensions");
    for (i = 0; i < args->n; i++) nl_push(&ix->list, coerce(c, check_value(c, args->v[i]), &ty_long));
    return ix;
}

static Node *resolve_member(Ctx *c, Node *e, Node *base, const char *name, NodeList *args, int mode)
{
    Type *t = base->ty;
    if (t->kind == T_UDT) {
        Udt *u = t->udt;
        int i;
        for (i = 0; i < u->nfields; i++)
            if (name_eq(u->fields[i].name, name)) {
                Node *f = node_new(E_FIELD, e->file, e->line, e->col);
                f->a = base;
                f->field = i;
                f->udt = u;
                f->ty = u->fields[i].ty;
                if (args) {
                    if (f->ty->kind == T_ARRAY) return index_node(c, e, f, args);
                    ERR(c, e, "field '%s' is not an array", name);
                }
                return f;
            }
        ERR(c, e, "type '%s' has no field '%s'", u->name, name);
        e->ty = &ty_variant;
        return e;
    }
    if (t->kind == T_OBJECT && t->cls && t->cls->xcls) {
        /* a linked extension's class: the member must be in its .bbx; called by name */
        ExtMember *m = ext_member_find(t->cls->xcls, name);
        int kind = BB_INV_GET | BB_INV_METHOD;
        if (!m) {
            ERR(c, e, "'%s' is not a member of %s", name, t->cls->name);
            e->ty = &ty_variant;
            return e;
        }
        if ((mode == M_LVAL || mode == M_SETLVAL) && m->kind != 1)
            ERR(c, e, "%s.%s is %s", t->cls->name, m->name, m->kind == 2 ? "read-only" : "a method");
        if (mode == M_STMT) kind = BB_INV_METHOD;
        if (mode == M_LVAL) kind = BB_INV_LET;
        if (mode == M_SETLVAL) kind = BB_INV_SET;
        return late(c, e, base, name, args, kind);
    }
    if (t->kind == T_OBJECT && t->cls && t->cls->rtcls) {
        /* Engine3D / Canvas / Audio: the member must exist (its id comes from the class's find) */
        const bb_class *rc = (const bb_class *)t->cls->rtcls;
        int32_t id = rc->find(rc, name);
        int kind = BB_INV_GET | BB_INV_METHOD;
        Node *l;
        if (id == BB_NOMEMBER) {
            ERR(c, e, "'%s' is not a member of %s", name, t->cls->name);
            e->ty = &ty_variant;
            return e;
        }
        if (mode == M_STMT) kind = BB_INV_METHOD;
        if (mode == M_LVAL) kind = BB_INV_LET;
        if (mode == M_SETLVAL) kind = BB_INV_SET;
        l = late(c, e, base, name, args, kind);
        l->rtid = id + 1;
        l->cls = t->cls;
        return l;
    }
    if (t->kind == T_OBJECT && t->cls && !t->cls->builtin) {
        ClassInfo *cls = t->cls;
        Sym *m = class_member(cls, name);
        int inside = c->cls == cls;
        if (!m || (!m->is_public && !inside) || (m->kind == SK_PROC && m->proc->kind == PK_EVENT)) {
            ERR(c, e, "class '%s' has no public member '%s'", cls->name, name);
            e->ty = &ty_variant;
            return e;
        }
        if (m->kind == SK_VAR) {
            Node *f = node_new(E_MFIELD, e->file, e->line, e->col);
            if (cls->is_interface) ERR(c, e, "fields of interface class '%s' cannot be accessed through it", cls->name);
            f->a = base;
            f->sym = m;
            f->cls = cls;
            f->ty = m->ty;
            if (args) {
                if (f->ty->kind == T_ARRAY) return index_node(c, e, f, args);
                if (f->ty->kind == T_VARIANT || f->ty->kind == T_OBJECT) return late(c, e, f, "", args, BB_INV_GET | BB_INV_METHOD);
                ERR(c, e, "'%s' is not an array", name);
            }
            return f;
        }
        if (m->kind == SK_PROPGROUP) {
            if (mode == M_LVAL || mode == M_SETLVAL) {
                Node *pn = node_new(E_DEFPROP, e->file, e->line, e->col);
                pn->sym = m;
                pn->a = base;
                pn->cls = cls;
                if (args) pn->list = *args;
                pn->ty = m->pget ? m->pget->ret : &ty_variant;
                return pn;
            }
            if (!m->pget) { ERR(c, e, "property '%s' is write-only", name); e->ty = &ty_variant; return e; }
            return make_call(c, e, m->pget, args, base, M_VALUE);
        }
        if (m->kind == SK_PROC) return make_call(c, e, m->proc, args, base, mode == M_STMT ? M_STMT : M_VALUE);
        ERR(c, e, "'%s' is not a member", name);
        e->ty = &ty_variant;
        return e;
    }
    if (t->kind == T_OBJECT || t->kind == T_VARIANT) {
        int kind = BB_INV_GET | BB_INV_METHOD;
        if (mode == M_STMT) kind = BB_INV_METHOD;
        if (mode == M_LVAL) kind = BB_INV_LET;
        if (mode == M_SETLVAL) kind = BB_INV_SET;
        return late(c, e, base, name, args, kind);
    }
    ERR(c, e, "invalid qualifier: %s has no members", type_name(t));
    e->ty = &ty_variant;
    return e;
}

/* base of a dotted name: Enum.Member, Module.Name, Err.X, or a value */
static Node *resolve_dot(Ctx *c, Node *e, NodeList *args, int mode)
{
    Node *base = e->a;
    if (!base) {
        if (!c->withs.n) {
            ERR(c, e, "'.%s' outside a With block", e->name);
            e->ty = &ty_variant;
            return e;
        }
        base = mk_var(e, c->withs.v[c->withs.n - 1]->sym);
        return resolve_member(c, e, base, e->name, args, mode);
    }
    if (base->kind == E_NAME) {
        Sym *s = scope_find(c->scope, base->name);
        if (!s && name_eq(base->name, "Err")) return err_prop(c, e, e->name, args, mode);
        if (!s && (name_eq(base->name, "App") || name_eq(base->name, "Clipboard") || name_eq(base->name, "Printer"))) {
            const char *on = name_eq(base->name, "App") ? "App" : name_eq(base->name, "Clipboard") ? "Clipboard" : "Printer";
            char *bn = xsprintf("__%s.%s", on, e->name);
            int bi = builtin_find(bn);
            /* App.Title = x: assignments go to the runtime's App object */
            if (bi >= 0 && (mode == M_LVAL || mode == M_SETLVAL)) bi = -1;
            if (bi < 0) {
                if (name_eq(base->name, "App") && (name_eq(e->name, "Major") || name_eq(e->name, "Minor") || name_eq(e->name, "Revision"))) {
                    /* the project's Version= (0 without one) */
                    CVal z;
                    memset(&z, 0, sizeof z);
                    z.type = T_INTEGER;
                    z.i = name_eq(e->name, "Major") ? c->prog->ver_major : name_eq(e->name, "Minor") ? c->prog->ver_minor : c->prog->ver_rev;
                    return mk_const_node(e, &z);
                }
                /* the other members are late bound on the runtime's App / Clipboard / Printer
                   object (docs/ui.md: ToolType, ARexxPort, ShowHelp, SetPicture, ...) */
                {
                    char *on2 = xsprintf("__%sObject", on);
                    int ob = builtin_find(on2);
                    if (ob >= 0) return resolve_member(c, e, make_builtin(c, base, ob, NULL, M_VALUE, 0), e->name, args, mode);
                }
                ERR(c, e, "the %s object has no member '%s'", base->name, e->name);
                e->ty = &ty_variant;
                return e;
            }
            return make_builtin(c, e, bi, args, mode, 0);
        }
        if (s && s->kind == SK_ENUM) {
            Sym *m = scope_find(c->scope, e->name);
            if (m && m->kind == SK_CONST && m->udt == (Udt *)s) return mk_const_node(e, &m->cv);
            /* enum member lookup by owner */
            {
                int i;
                Module *mm = s->mod;
                (void)mm;
                for (i = 0; i < s->bounds.n; i++) {
                    Sym *ms = s->bounds.v[i]->sym;
                    if (name_eq(ms->name, e->name)) { Node *k = mk_const_node(e, &ms->cv); k->ty = &ty_long; return k; }
                }
            }
            ERR(c, e, "enum '%s' has no member '%s'", s->name, e->name);
            e->ty = &ty_long;
            return e;
        }
        if (s && s->kind == SK_MODULE) {
            Module *m = s->mod;
            Sym *ms = scope_find_local(m->scope, e->name);
            Node tmp;
            if (!ms || (!ms->is_public && m != c->mod)) {
                ERR(c, e, "module '%s' has no public member '%s'", m->name, e->name);
                e->ty = &ty_variant;
                return e;
            }
            {
                Scope *old = c->scope;
                Node *r;
                memset(&tmp, 0, sizeof tmp);
                c->scope = m->scope;
                tmp = *e;
                tmp.kind = E_NAME;
                tmp.suffix = 0;
                r = resolve_name(c, &tmp, args, mode);
                c->scope = old;
                return r;
            }
        }
    }
    base = check_expr(c, base, M_ARG);
    if (base->ty->kind == T_VOID) {
        ERR(c, e, "invalid use of a Sub");
        e->ty = &ty_variant;
        return e;
    }
    return resolve_member(c, e, base, e->name, args, mode);
}

static Node *resolve_apply(Ctx *c, Node *e, int mode)
{
    Node *f = e->a;
    if (e->flags & NF_ISDEFAULT) {
        /* a!key */
        Node *b = check_value(c, f);
        if (b->ty->kind != T_OBJECT && b->ty->kind != T_VARIANT) ERR(c, e, "'!' needs an object");
        return late(c, e, b, "", &e->list, BB_INV_GET | BB_INV_METHOD);
    }
    if (f->kind == E_NAME) return resolve_name(c, f, &e->list, mode);
    if (f->kind == E_DOT) return resolve_dot(c, f, &e->list, mode);
    if (f->kind == E_ME) {
        ERR(c, e, "'Me' cannot be called");
        e->ty = &ty_variant;
        return e;
    }
    {
        Node *b = check_value(c, f);
        if (b->ty->kind == T_ARRAY) return index_node(c, e, b, &e->list);
        if (b->ty->kind == T_VARIANT || b->ty->kind == T_OBJECT)
            return late(c, e, b, "", &e->list, BB_INV_GET | BB_INV_METHOD);
        ERR(c, e, "expression cannot be indexed or called");
        e->ty = &ty_variant;
        return e;
    }
}

/* ---------- special builtins with type-dependent behaviour ---------- */

static Node *bare_builtin(Ctx *c, Node *at, int bi)
{
    Node *n = node_new(E_BUILTIN, at->file, at->line, at->col);
    n->bi = bi;
    n->name = (char *)builtins[bi].name;
    n->ty = type_prim(builtins[bi].ret);
    n->text = c->mod->opt_text;
    return n;
}

static Node *special_builtin(Ctx *c, Node *at, const char *name, NodeList *args, int mode, char suffix, int *handled)
{
    int bi = builtin_find(name);
    Node *a0;
    *handled = 0;
    if (bi < 0 || !(builtins[bi].flags & BIF_SPECIAL)) return NULL;
    if (name_eq(name, "Array") || name_eq(name, "Choose") || name_eq(name, "InStr")) return NULL;
    if (!args || args->n < 1 || args->v[0]->kind == E_MISSING) return NULL;
    *handled = 1;
    if (name_eq(name, "Len")) {
        if (args->n != 1) { ERR(c, at, "Len takes one argument"); at->ty = &ty_long; return at; }
        a0 = check_expr(c, args->v[0], M_ARG);
        if (a0->ty->kind == T_STRING) {
            Node *n = bare_builtin(c, at, bi);
            nl_push(&n->list, a0);
            n->ty = &ty_long;
            return n;
        }
        if (type_is_numeric(a0->ty) && a0->ty->kind != T_DATE) {
            CVal v;
            memset(&v, 0, sizeof v);
            v.type = T_LONG;
            switch (a0->ty->kind) {
            case T_BYTE: v.i = 1; break;
            case T_BOOLEAN: case T_INTEGER: v.i = 2; break;
            case T_LONG: case T_SINGLE: v.i = 4; break;
            default: v.i = 8;
            }
            if (a0->ty->kind == T_DATE) v.i = 8;
            return mk_const_node(at, &v);
        }
        if (a0->ty->kind == T_UDT) {
            /* VB: size of the record; we report the sum of field sizes like Put writes */
            CVal v;
            int i, sz = 0;
            memset(&v, 0, sizeof v);
            v.type = T_LONG;
            for (i = 0; i < a0->ty->udt->nfields; i++) {
                Type *ft = a0->ty->udt->fields[i].ty;
                switch (ft->kind) {
                case T_BYTE: sz += 1; break;
                case T_BOOLEAN: case T_INTEGER: sz += 2; break;
                case T_LONG: case T_SINGLE: sz += 4; break;
                case T_STRING: sz += ft->fixlen ? ft->fixlen : 4; break;
                default: sz += 8;
                }
            }
            v.i = sz;
            return mk_const_node(at, &v);
        }
        {
            /* Variant etc: Len(CStr(x)) */
            Node *n = bare_builtin(c, at, bi);
            nl_push(&n->list, coerce(c, a0, &ty_string));
            n->ty = &ty_long;
            return n;
        }
    }
    if (name_eq(name, "LBound") || name_eq(name, "UBound")) {
        Node *n = make_builtin(c, at, bi, args, mode, suffix);
        return n;
    }
    if (name_eq(name, "IsMissing") || name_eq(name, "IsEmpty") || name_eq(name, "IsNull") ||
        name_eq(name, "IsObject") || name_eq(name, "IsArray") || name_eq(name, "TypeName") ||
        name_eq(name, "VarType")) {
        Node *n;
        a0 = check_expr(c, args->v[0], M_ARG);
        if (a0->ty->kind == T_UDT) {
            CVal v;
            memset(&v, 0, sizeof v);
            if (name_eq(name, "TypeName")) { v.type = T_STRING; v.s = xstrdup(a0->ty->udt->name); v.slen = (int)strlen(v.s); }
            else if (name_eq(name, "VarType")) { v.type = T_INTEGER; v.i = 36; }
            else { v.type = T_BOOLEAN; v.i = 0; }
            return mk_const_node(at, &v);
        }
        if (name_eq(name, "IsArray") && a0->ty->kind == T_ARRAY) {
            CVal v;
            memset(&v, 0, sizeof v);
            v.type = T_BOOLEAN;
            v.i = -1;
            return mk_const_node(at, &v);
        }
        if (name_eq(name, "TypeName") && a0->ty->kind == T_OBJECT && a0->ty->cls == NULL && a0->kind == E_CONST) {
            CVal v;
            memset(&v, 0, sizeof v);
            v.type = T_STRING; v.s = xstrdup("Nothing"); v.slen = 7;
            return mk_const_node(at, &v);
        }
        n = bare_builtin(c, at, bi);
        nl_push(&n->list, coerce(c, a0, &ty_variant));
        return n;
    }
    if (name_eq(name, "Abs") || name_eq(name, "Int") || name_eq(name, "Fix") || name_eq(name, "Sgn") || name_eq(name, "Round")) {
        Node *n = make_builtin(c, at, bi, args, mode, suffix);
        Type *at0;
        if (n->list.n < 1) return n;
        at0 = n->list.v[0]->kind == E_CONV ? n->list.v[0]->a->ty : n->list.v[0]->ty;
        if (name_eq(name, "Sgn")) { n->ty = &ty_variant; return coerce(c, n, &ty_integer); }
        if ((name_eq(name, "Int") || name_eq(name, "Fix")) && n->list.n == 1) {
            /* typed: Int / Fix of a Byte, Integer or Long is the value; of a Double or Single a
               Double op (register form in the VM and JIT, no Variant) */
            Node *x = n->list.v[0]->kind == E_CONV ? n->list.v[0]->a : n->list.v[0];
            if (at0->kind == T_BYTE || at0->kind == T_INTEGER || at0->kind == T_LONG) {
                if (x->kind == E_VAR || x->kind == E_INDEX || x->kind == E_FIELD || x->kind == E_MFIELD) {
                    Node *k = node_new(E_CONV, at->file, at->line, at->col);     /* a value, not the variable */
                    k->a = x;
                    k->ty = x->ty;
                    k->flags |= NF_PARENARG;
                    return k;
                }
                return x;
            }
            if (at0->kind == T_DOUBLE || at0->kind == T_SINGLE) {
                Node *m = bare_builtin(c, at, builtin_find(name_eq(name, "Fix") ? "__fixd" : "__intd"));
                nl_push(&m->list, coerce(c, x, &ty_double));
                return at0->kind == T_SINGLE ? coerce(c, m, &ty_single) : m;
            }
        }
        if (type_is_numeric(at0) && at0->kind != T_BOOLEAN) {
            n->ty = &ty_variant;
            if (name_eq(name, "Round") && type_is_integral(at0)) return coerce(c, n, at0);
            if ((name_eq(name, "Abs")) && at0->kind == T_BYTE) return coerce(c, n, &ty_byte);
            return coerce(c, n, name_eq(name, "Round") && at0->kind != T_SINGLE && at0->kind != T_CURRENCY ? &ty_double : at0);
        }
        if (at0->kind == T_STRING) { n->ty = &ty_variant; return coerce(c, n, &ty_double); }
        return n;
    }
    *handled = 0;
    return NULL;
}

/* ---------- main dispatcher ---------- */

static Node *parse_date_const(Ctx *c, Node *e)
{
    CVal v;
    bb_errframe f;
    memset(&v, 0, sizeof v);
    v.type = T_DATE;
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        bb_str *s = bb_str_from_c(e->name);
        v.d = bb_str_to_date(s);
        bb_str_release(s);
        bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        ERR(c, e, "invalid date literal #%s#", e->name);
    }
    return mk_const_node(e, &v);
}

Node *check_expr(Ctx *c, Node *e, int mode)
{
    CVal v;
    memset(&v, 0, sizeof v);
    /* already checked (a node passed through twice, e.g. a property Let's value) */
    if (e->ty && e->kind != E_INT && e->kind != E_FLT) return e;
    switch (e->kind) {
    case E_INT:
        v.type = e->ty->kind;
        v.i = e->ival;
        return mk_const_node(e, &v);
    case E_FLT:
        v.type = e->ty->kind;
        v.d = e->ty->kind == T_SINGLE ? (float)e->fval : e->fval;
        return mk_const_node(e, &v);
    case E_STR:
        v.type = T_STRING;
        v.s = e->name;
        v.slen = e->slen;
        return mk_const_node(e, &v);
    case E_BOOL:
        v.type = T_BOOLEAN;
        v.i = e->ival;
        return mk_const_node(e, &v);
    case E_DATE:
        return parse_date_const(c, e);
    case E_NOTHING:
        v.type = T_OBJECT;
        v.is_nothing = 1;
        return mk_const_node(e, &v);
    case E_EMPTY:
        v.type = T_VARIANT;
        v.is_empty = 1;
        return mk_const_node(e, &v);
    case E_NULL:
        v.type = T_VARIANT;
        v.is_null = 1;
        return mk_const_node(e, &v);
    case E_CONST: case E_VAR: case E_CONV:
        return e;
    case E_PAREN: {
        Node *r = check_expr(c, e->a, M_VALUE);
        if (r->kind == E_VAR || r->kind == E_INDEX || r->kind == E_FIELD || r->kind == E_MFIELD) {
            /* (x): a value, not the variable */
            Node *k = node_new(E_CONV, e->file, e->line, e->col);
            k->a = r;
            k->ty = r->ty;
            k->flags |= NF_PARENARG;
            if (r->ty->kind == T_UDT || r->ty->kind == T_ARRAY) return r;
            return k;
        }
        return r;
    }
    case E_NAME:
        return resolve_name(c, e, NULL, mode);
    case E_DOT:
        return resolve_dot(c, e, NULL, mode);
    case E_APPLY:
        return resolve_apply(c, e, mode);
    case E_UN:
        return check_unop(c, e);
    case E_BIN:
        return check_binop(c, e);
    case E_ME:
        if (!c->cls && c->mod->is_form && c->mod->form_name) {
            Sym *fs = scope_find_local(c->mod->scope, c->mod->form_name);
            if (fs) return mk_var(e, fs);
        }
        if (!c->cls) {
            ERR(c, e, "'Me' is only valid in a class module");
            e->ty = &ty_object;
            return e;
        }
        e->ty = type_object(c->cls);
        return e;
    case E_NEW: {
        ClassInfo *cls = find_class(c, e->name);
        if (!cls) {
            ERR(c, e, "class '%s' is not defined", e->name);
            e->ty = &ty_object;
            return e;
        }
        if (IS_REGCLS(cls)) ERR(c, e, "use CreateObject(\"Boing.%s\") to make a %s", cls->name, cls->name);
        e->cls = cls;
        e->ty = type_object(cls);
        return e;
    }
    case E_TYPEOF: {
        ClassInfo *cls = find_class(c, e->name);
        e->a = check_value(c, e->a);
        if (e->a->ty->kind != T_OBJECT && e->a->ty->kind != T_VARIANT) ERR(c, e, "TypeOf needs an object");
        e->a = coerce(c, e->a, &ty_object);
        if (!cls) ERR(c, e, "class '%s' is not defined", e->name);
        else if (IS_REGCLS(cls)) ERR(c, e, "TypeOf ... Is %s is not supported: compare TypeName(x) with \"%s\"", cls->name, cls->name);
        e->cls = cls;
        e->ty = &ty_boolean;
        return e;
    }
    case E_MISSING:
        if (mode != M_ARG) ERR(c, e, "argument expected");
        e->ty = &ty_variant;
        return e;
    case E_NAMEDARG:
        ERR(c, e, "named argument not allowed here");
        e->ty = &ty_variant;
        return e;
    case E_ADDROF: {
        /* a module procedure's native entry point (callback.c) */
        Sym *s = scope_find(c->scope, e->name);
        e->ty = &ty_long;
        if (!s || s->kind != SK_PROC || !s->proc || s->proc->cls || s->proc->kind == PK_DECLARE || s->proc->kind == PK_EVENT) {
            ERR(c, e, "AddressOf needs the name of a Sub or Function in a module");
            return e;
        }
        if (s->proc->nparams > 8) ERR(c, e, "AddressOf: a callback can have at most 8 parameters");
        e->proc = s->proc;
        return e;
    }
    default:
        ERR(c, e, "invalid expression");
        e->ty = &ty_variant;
        return e;
    }
}

Node *check_value(Ctx *c, Node *e)
{
    Node *r = check_expr(c, e, M_VALUE);
    if (!r->ty) r->ty = &ty_variant;
    if (r->ty->kind == T_VOID && r->kind != E_ERRPROP) {
        if (r->kind == E_CALL || r->kind == E_MCALL || r->kind == E_BUILTIN) {
            /* message already given by make_call/make_builtin */
        } else ERR(c, e, "expression has no value");
        r->ty = &ty_variant;
    }
    if (r->kind == E_DEFPROP) {
        ERR(c, e, "property cannot be read");
        r->ty = &ty_variant;
    }
    return r;
}
