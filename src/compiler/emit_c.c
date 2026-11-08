/* emit_c.c - typed AST -> C for `boing build` / `boing emit-c`
 *
 * One C file per program. Statically typed variables become C variables;
 * Strings, Objects, Variants and arrays go through libboing with explicit
 * ownership: every statement evaluates its sub-expressions into temporaries
 * (in evaluation order) and releases them at the end of the statement.
 */
#include "bbc.h"
#include "../runtime/boing.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

int is_lvalue(Node *e);

typedef struct EC {
    Program *p;
    Buf *out;
    Buf body;               /* current procedure body */
    Buf decl;               /* current procedure temporaries */
    Buf pre;                /* current statement: code before the action */
    Buf rel;                /* current statement: releases */
    Proc *proc;
    int ntemp;
    int nlabel;
    int indent;
    int line, file;
    int debug;
    int multi_file;
    int handler;            /* proc has On Error */
    int resume;             /* proc needs statement labels */
    int nstmt;
    int loops[64], loopk[64], nloops;
    int *gosub_ids; int ngosub, capgosub;
    int **wev_global;       /* unused */
    int has_me;
    Buf sdecl;              /* members of the procedure's cleanup struct (refcounted locals/temps) */
    Buf sclean;             /* their releases, in the cleanup function */
    Buf stemp;              /* releases of the statement temporaries among them (error handlers) */
    int nsmem;
} EC;

/* ---------- small helpers ---------- */

static void out(EC *e, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void out(EC *e, const char *fmt, ...)
{
    char tmp[4096];
    va_list ap;
    int i;
    for (i = 0; i < e->indent; i++) buf_puts(&e->body, "    ");
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    buf_puts(&e->body, tmp);
    buf_puts(&e->body, "\n");
}

static void pre(EC *e, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void pre(EC *e, const char *fmt, ...)
{
    char tmp[4096];
    va_list ap;
    int i;
    for (i = 0; i < e->indent; i++) buf_puts(&e->pre, "    ");
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    buf_puts(&e->pre, tmp);
    buf_puts(&e->pre, "\n");
}

static void rel(EC *e, const char *s)
{
    int i;
    for (i = 0; i < e->indent; i++) buf_puts(&e->rel, "    ");
    buf_puts(&e->rel, s);
    buf_puts(&e->rel, "\n");
}

static void flush_pre(EC *e)
{
    if (e->pre.n) buf_put(&e->body, e->pre.p, e->pre.n);
    e->pre.n = 0;
    if (e->pre.p) e->pre.p[0] = 0;
}

static void flush_rel(EC *e)
{
    if (e->rel.n) buf_put(&e->body, e->rel.p, e->rel.n);
    e->rel.n = 0;
    if (e->rel.p) e->rel.p[0] = 0;
}

static char *cident(const char *s)
{
    Buf b = {0, 0, 0};
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (isalnum(c) && c < 128) { char ch = (char)tolower(c); buf_put(&b, &ch, 1); }
        else if (c == '_') buf_puts(&b, "_");
        else buf_printf(&b, "_x%02x", c);
    }
    return b.p ? b.p : xstrdup("_");
}

static char *cstrlit(const char *s, int len)
{
    Buf b = {0, 0, 0};
    int i;
    buf_puts(&b, "\"");
    for (i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') buf_printf(&b, "\\%c", c);
        else if (c == '?') buf_puts(&b, "\\?");
        else if (c >= 32 && c < 127) buf_put(&b, (const char *)&c, 1);
        else buf_printf(&b, "\\%03o", c);
    }
    buf_puts(&b, "\"");
    return b.p;
}

static int is_scalar(Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: case T_BYTE: case T_INTEGER: case T_LONG: case T_SINGLE: case T_DOUBLE:
    case T_CURRENCY: case T_DATE: return 1;
    default: return 0;
    }
}

static char *udt_cname(Udt *u) { return xsprintf("U%d_%s", u->index, cident(u->name)); }
static char *cls_cname(ClassInfo *c) { return xsprintf("C%d_%s", c->index, cident(c->name)); }

static const char *ctype(Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: return "bb_bool";
    case T_BYTE: return "bb_byte";
    case T_INTEGER: return "bb_int";
    case T_LONG: return "bb_long";
    case T_SINGLE: return "bb_single";
    case T_DOUBLE: return "bb_double";
    case T_CURRENCY: return "bb_cur";
    case T_DATE: return "bb_date";
    case T_STRING: return "bb_str *";
    case T_OBJECT: return "bb_obj *";
    case T_ARRAY: return "bb_array *";
    case T_UDT: return udt_cname(t->udt);
    default: return "bb_value";
    }
}

static const char *vtname(Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: return "BB_BOOLEAN";
    case T_BYTE: return "BB_BYTE";
    case T_INTEGER: return "BB_INTEGER";
    case T_LONG: return "BB_LONG";
    case T_SINGLE: return "BB_SINGLE";
    case T_DOUBLE: return "BB_DOUBLE";
    case T_CURRENCY: return "BB_CURRENCY";
    case T_DATE: return "BB_DATE";
    case T_STRING: return "BB_STRING";
    case T_OBJECT: return "BB_OBJECT";
    case T_UDT: return "BB_UDT";
    case T_ARRAY: return xsprintf("(BB_ARRAY | %s)", vtname(t->elem));
    default: return "BB_VARIANT";
    }
}

static char *udt_desc_ref(Type *t)
{
    Udt *u = t->kind == T_UDT ? t->udt : (t->kind == T_ARRAY && t->elem->kind == T_UDT ? t->elem->udt : NULL);
    return u ? xsprintf("&%s_desc", udt_cname(u)) : xstrdup("NULL");
}

static char *zero_init(Type *t)
{
    switch (t->kind) {
    case T_STRING: case T_OBJECT: case T_ARRAY: return xstrdup("NULL");
    case T_VARIANT: return xstrdup("{0, 0, 0, {0}}");
    case T_UDT: return xstrdup("{0}");
    default: return xstrdup("0");
    }
}

static char *release_code(Type *t, const char *x)
{
    switch (t->kind) {
    case T_STRING: return xsprintf("bb_str_set((bb_str **)&%s, NULL);", x);
    case T_OBJECT: return xsprintf("bb_obj_set((bb_obj **)&%s, NULL);", x);
    case T_VARIANT: return xsprintf("bb_v_release((bb_value *)&%s);", x);
    case T_ARRAY: return xsprintf("bb_arr_free(%s); %s = NULL;", x, x);
    case T_UDT: return xsprintf("bb_udt_clear(&%s_desc, (void *)&%s);", udt_cname(t->udt), x);
    default: return NULL;
    }
}

static char *struct_member(EC *e, Type *t, const char *name)
{
    char *r = release_code(t, xsprintf("c->%s", name));
    buf_printf(&e->sdecl, "    %s %s;\n", t->kind == T_UDT ? udt_cname(t->udt) : ctype(t), name);
    if (r) buf_printf(&e->sclean, "    %s\n", r);
    e->nsmem++;
    return xsprintf("bbL.%s", name);
}

/* bb_value name[n] in the cleanup struct */
static char *varr_temp(EC *e, int n)
{
    char *name = xsprintf("t%d", e->ntemp++);
    if (n < 1) n = 1;
    buf_printf(&e->sdecl, "    bb_value %s[%d];\n", name, n);
    buf_printf(&e->sclean, "    { int i; for (i = 0; i < %d; i++) bb_v_release(&c->%s[i]); }\n", n, name);
    buf_printf(&e->stemp, "    { int i; for (i = 0; i < %d; i++) bb_v_release(&c->%s[i]); }\n", n, name);
    e->nsmem++;
    return xsprintf("bbL.%s", name);
}

static int is_refty(Type *t);

static char *new_temp(EC *e, Type *t, int release)
{
    char *n;
    if (is_refty(t) && release) {
        /* owned: on the cleanup chain (borrowed temps are plain locals) */
        char *nm = xsprintf("t%d", e->ntemp++);
        char *m = struct_member(e, t, nm);
        char *r = release_code(t, m);
        char *rc = release_code(t, xsprintf("c->%s", nm));
        if (rc) buf_printf(&e->stemp, "    %s\n", rc);
        if (r) rel(e, r);
        return m;
    }
    n = xsprintf("t%d", e->ntemp++);
    if (t->kind == T_UDT) buf_printf(&e->decl, "    %s %s; memset(&%s, 0, sizeof %s);\n", ctype(t), n, n, n);
    else buf_printf(&e->decl, "    %s %s = %s;\n", ctype(t), n, zero_init(t));
    if (release) {
        char *r = release_code(t, n);
        if (r) rel(e, r);
    }
    return n;
}

/* ---------- names ---------- */

static char *sym_cname(EC *e, Sym *s)
{
    if (s->cname) return s->cname;
    switch (s->storage) {
    case ST_GLOBAL: case ST_STATIC:
        s->cname = xsprintf("g%d_%s", s->index, cident(s->name));
        break;
    case ST_FIELD:
        s->cname = xsprintf("f_%s", cident(s->name));
        break;
    default:
        if (s->name[0] == '$') s->cname = xsprintf("s%d", s->index);
        else s->cname = xsprintf("l_%s", cident(s->name));
    }
    (void)e;
    return s->cname;
}

static char *proc_cname(Proc *p)
{
    if (!p->cname) p->cname = xsprintf("p%d_%s", p->index, p->kind == PK_MAIN ? "main" : cident(p->name));
    return p->cname;
}

static int sym_is_ref(Sym *s) { return (s->storage == ST_PARAM || s->storage == ST_LOCAL) && s->byref; }

/* ---------- expressions ---------- */

typedef struct R { char *s; int own; } R;

static R prod(EC *e, Node *n);
static char *val(EC *e, Node *n);
static char *own(EC *e, Node *n);
static char *lval(EC *e, Node *n);
static char *addr(EC *e, Node *n);

static R mkr(char *s, int own_) { R r; r.s = s; r.own = own_; return r; }

static int is_refty(Type *t) { return t->kind == T_STRING || t->kind == T_OBJECT || t->kind == T_VARIANT || t->kind == T_ARRAY || t->kind == T_UDT; }

/* borrowed (or scalar) value; Variants as pointers */
static char *val(EC *e, Node *n)
{
    R r = prod(e, n);
    Type *t = n->ty;
    if (!is_refty(t)) return r.s;
    if (!r.own) return r.s;
    {
        char *tn = new_temp(e, t, 1);
        if (t->kind == T_UDT) {
            pre(e, "%s = %s;", tn, r.s);
            return tn;
        }
        pre(e, "%s = %s;", tn, r.s);
        if (t->kind == T_VARIANT) return xsprintf("(&%s)", tn);
        return tn;
    }
}

/* owned value (Variants as values) */
static char *own(EC *e, Node *n)
{
    R r = prod(e, n);
    Type *t = n->ty;
    if (!is_refty(t) || r.own) return r.s;
    switch (t->kind) {
    case T_STRING: return xsprintf("bb_str_retain(%s)", r.s);
    case T_OBJECT: return xsprintf("bb_obj_retain(%s)", r.s);
    case T_VARIANT: return xsprintf("bb_v_dup(%s)", r.s);
    case T_ARRAY: return xsprintf("bb_arr_copy(%s)", r.s);
    default: return r.s;
    }
}

static char *index_expr(EC *e, Node *n)
{
    char *a = val(e, n->a);
    Type *et = n->ty;
    int i;
    if (n->list.n == 1) return xsprintf("(*(%s *)bb_arr_elem1(%s, %s))", et->kind == T_UDT ? udt_cname(et->udt) : ctype(et), a, val(e, n->list.v[0]));
    if (n->list.n == 2)
        return xsprintf("(*(%s *)bb_arr_elem2(%s, %s, %s))", et->kind == T_UDT ? udt_cname(et->udt) : ctype(et), a,
                        val(e, n->list.v[0]), val(e, n->list.v[1]));
    {
        Buf b = {0, 0, 0};
        buf_printf(&b, "(*(%s *)bb_arr_elem(%s, %d, (int32_t[]){", et->kind == T_UDT ? udt_cname(et->udt) : ctype(et), a, n->list.n);
        for (i = 0; i < n->list.n; i++) buf_printf(&b, "%s%s", i ? ", " : "", val(e, n->list.v[i]));
        buf_puts(&b, "}))");
        return b.p;
    }
}

static char *lval(EC *e, Node *n)
{
    switch (n->kind) {
    case E_VAR: {
        Sym *s = n->sym;
        char *c = sym_cname(e, s);
        if (s->storage == ST_FIELD) return xsprintf("((%s *)self)->%s", cls_cname(s->cls), c);
        if (sym_is_ref(s)) return xsprintf("(*%s)", c);
        return c;
    }
    case E_INDEX: return index_expr(e, n);
    case E_FIELD: {
        char *b;
        if (is_lvalue(n->a)) b = lval(e, n->a);
        else b = val(e, n->a);
        return xsprintf("(%s).f_%s", b, cident(n->udt->fields[n->field].name));
    }
    case E_MFIELD:
        return xsprintf("((%s *)bb_obj_check(%s))->%s", cls_cname(n->cls), val(e, n->a), sym_cname(e, n->sym));
    default:
        return val(e, n);
    }
}

static char *addr(EC *e, Node *n)
{
    Type *t = n->ty;
    const char *ct = t->kind == T_UDT ? udt_cname(t->udt) : ctype(t);
    if (n->kind == E_VAR && n->sym->is_new && t->kind == T_OBJECT && t->cls)
        /* passing an As New variable creates its object too */
        pre(e, "(void)bb_autonew((bb_obj **)&%s, %s);", lval(e, n), t->cls->builtin ? "bb_collection_new" : xsprintf("%s_new", cls_cname(t->cls)));
    if (n->kind == E_VAR && sym_is_ref(n->sym)) return sym_cname(e, n->sym);
    if (is_lvalue(n)) return xsprintf("((%s *)&%s)", ct, lval(e, n));
    /* rvalue: through a temporary */
    {
        char *tn = new_temp(e, t, 1);
        if (t->kind == T_VARIANT) pre(e, "%s = %s;", tn, own(e, n));
        else if (is_refty(t) && t->kind != T_UDT) pre(e, "%s = %s;", tn, own(e, n));
        else pre(e, "%s = %s;", tn, val(e, n));
        return xsprintf("(&%s)", tn);
    }
}

static char *const_expr(EC *e, Node *n);

static char *dbl_lit(double d)
{
    char b[64];
    snprintf(b, sizeof b, "%.17g", d);
    if (!strchr(b, '.') && !strchr(b, 'e') && !strchr(b, 'n') && !strchr(b, 'i')) strcat(b, ".0");
    return xstrdup(b);
}

static int lit_index(EC *e, const char *s, int len);

static char *const_expr(EC *e, Node *n)
{
    CVal *v = &n->cv;
    if (v->is_nothing || n->ty->kind == T_OBJECT) return xstrdup("((bb_obj *)0)");
    if (v->is_null) return xstrdup("(&bb_vk_null)");
    if (v->is_empty) return xstrdup("(&bb_vk_empty)");
    switch (v->type) {
    case T_INTEGER: return xsprintf("((bb_int)%lld)", (long long)v->i);
    case T_LONG: return v->i == INT32_MIN ? xstrdup("((bb_long)(-2147483647 - 1))") : xsprintf("((bb_long)%lld)", (long long)v->i);
    case T_BOOLEAN: return xstrdup(v->i ? "BB_TRUE" : "BB_FALSE");
    case T_BYTE: return xsprintf("((bb_byte)%lld)", (long long)v->i);
    case T_SINGLE: return xsprintf("((bb_single)%s)", dbl_lit(v->d));
    case T_DOUBLE: return xsprintf("((bb_double)%s)", dbl_lit(v->d));
    case T_DATE: return xsprintf("((bb_date)%s)", dbl_lit(v->d));
    case T_CURRENCY: {
        double x = v->d * 10000.0;
        long long c = (long long)(x + (x >= 0 ? 0.5 : -0.5));
        return xsprintf("((bb_cur)%lldLL)", c);
    }
    case T_STRING: return xsprintf("bb_k[%d]", lit_index(e, v->s, v->slen));
    default: return xstrdup("(&bb_vk_empty)");
    }
}

/* literal table */
static char **lits;
static int *litlens;
static int nlits, caplits;

static int lit_index(EC *e, const char *s, int len)
{
    int i;
    (void)e;
    for (i = 0; i < nlits; i++) if (litlens[i] == len && memcmp(lits[i], s, (size_t)len) == 0) return i;
    if (nlits == caplits) {
        caplits = caplits ? caplits * 2 : 64;
        lits = (char **)xrealloc(lits, sizeof(char *) * (size_t)caplits);
        litlens = (int *)xrealloc(litlens, sizeof(int) * (size_t)caplits);
    }
    lits[nlits] = xstrndup(s, (size_t)len);
    litlens[nlits] = len;
    return nlits++;
}

/* conversion of an already-produced value of type `from` (expression x) to `to` */
static R conv_scalar(EC *e, Node *src, Type *to)
{
    Type *from = src->ty;
    int fk = from->kind, tk = to->kind;
    char *x;
    if (fk == T_VARIANT) {
        char *p = val(e, src);
        switch (tk) {
        case T_BOOLEAN: return mkr(xsprintf("bb_v_to_bool(%s)", p), 0);
        case T_BYTE: return mkr(xsprintf("bb_v_to_byte(%s)", p), 0);
        case T_INTEGER: return mkr(xsprintf("bb_v_to_int(%s)", p), 0);
        case T_LONG: return mkr(xsprintf("bb_v_to_long(%s)", p), 0);
        case T_SINGLE: return mkr(xsprintf("bb_v_to_single(%s)", p), 0);
        case T_DOUBLE: return mkr(xsprintf("bb_v_to_double(%s)", p), 0);
        case T_CURRENCY: return mkr(xsprintf("bb_v_to_cur(%s)", p), 0);
        case T_DATE: return mkr(xsprintf("bb_v_to_date(%s)", p), 0);
        case T_STRING: return mkr(xsprintf("bb_v_to_str(%s)", p), 1);
        case T_OBJECT:
            if (to->cls && !to->cls->builtin) return mkr(xsprintf("bb_chkcls(bb_v_to_obj(%s), &%s_class)", p, cls_cname(to->cls)), 1);
            return mkr(xsprintf("bb_v_to_obj(%s)", p), 1);
        case T_ARRAY: return mkr(xsprintf("bb_v_to_array(%s, %s)", p, vtname(to->elem)), 1);
        default: break;
        }
    }
    if (tk == T_VARIANT) {
        switch (fk) {
        case T_BOOLEAN: x = val(e, src); return mkr(xsprintf("bb_v_bool(%s)", x), 1);
        case T_BYTE: return mkr(xsprintf("bb_v_byte(%s)", val(e, src)), 1);
        case T_INTEGER: return mkr(xsprintf("bb_v_int(%s)", val(e, src)), 1);
        case T_LONG: return mkr(xsprintf("bb_v_long(%s)", val(e, src)), 1);
        case T_SINGLE: return mkr(xsprintf("bb_v_single(%s)", val(e, src)), 1);
        case T_DOUBLE: return mkr(xsprintf("bb_v_double(%s)", val(e, src)), 1);
        case T_CURRENCY: return mkr(xsprintf("bb_v_cur(%s)", val(e, src)), 1);
        case T_DATE: return mkr(xsprintf("bb_v_date(%s)", val(e, src)), 1);
        case T_STRING: return mkr(xsprintf("bb_v_str(%s)", own(e, src)), 1);
        case T_OBJECT: return mkr(xsprintf("bb_v_obj(%s)", own(e, src)), 1);
        case T_ARRAY: return mkr(xsprintf("bb_v_arr(%s)", own(e, src)), 1);
        default: break;
        }
    }
    if (tk == T_OBJECT) {
        if (to->cls && !to->cls->builtin) return mkr(xsprintf("bb_chkcls(%s, &%s_class)", val(e, src), cls_cname(to->cls)), 0);
        return mkr(val(e, src), 0);
    }
    if (tk == T_ARRAY) return mkr(val(e, src), 0);
    if (fk == T_STRING) {
        char *s = val(e, src);
        switch (tk) {
        case T_BOOLEAN: return mkr(xsprintf("bb_str_to_bool(%s)", s), 0);
        case T_BYTE: return mkr(xsprintf("bb_cbyte(bb_str_to_double(%s))", s), 0);
        case T_INTEGER: return mkr(xsprintf("bb_cint(bb_str_to_double(%s))", s), 0);
        case T_LONG: return mkr(xsprintf("bb_clng(bb_str_to_double(%s))", s), 0);
        case T_SINGLE: return mkr(xsprintf("bb_csng(bb_str_to_double(%s))", s), 0);
        case T_DOUBLE: return mkr(xsprintf("bb_str_to_double(%s)", s), 0);
        case T_CURRENCY: return mkr(xsprintf("bb_ccur(bb_str_to_double(%s))", s), 0);
        case T_DATE: return mkr(xsprintf("bb_str_to_date(%s)", s), 0);
        case T_STRING: return mkr(s, 0);
        default: break;
        }
    }
    if (tk == T_STRING) {
        x = val(e, src);
        switch (fk) {
        case T_BOOLEAN: return mkr(xsprintf("bb_str_from_bool(%s)", x), 1);
        case T_BYTE: case T_INTEGER: case T_LONG: return mkr(xsprintf("bb_str_from_long(%s)", x), 1);
        case T_SINGLE: return mkr(xsprintf("bb_str_from_single(%s)", x), 1);
        case T_DOUBLE: return mkr(xsprintf("bb_str_from_double(%s)", x), 1);
        case T_CURRENCY: return mkr(xsprintf("bb_str_from_cur(%s)", x), 1);
        case T_DATE: return mkr(xsprintf("bb_str_from_date(%s)", x), 1);
        default: break;
        }
    }
    /* numeric <-> numeric */
    x = val(e, src);
    if (fk == T_CURRENCY) {
        if (tk == T_CURRENCY) return mkr(x, 0);
        x = xsprintf("bb_cur_to_double(%s)", x);
        fk = T_DOUBLE;
    }
    switch (tk) {
    case T_BOOLEAN: return mkr(xsprintf("((%s) != 0 ? BB_TRUE : BB_FALSE)", x), 0);
    case T_BYTE:
        if (fk == T_BOOLEAN || fk == T_INTEGER || fk == T_LONG) return mkr(xsprintf("bb_l2by(%s)", x), 0);
        return mkr(xsprintf("bb_cbyte(%s)", x), 0);
    case T_INTEGER:
        if (fk == T_BYTE || fk == T_BOOLEAN) return mkr(xsprintf("((bb_int)%s)", x), 0);
        if (fk == T_LONG) return mkr(xsprintf("bb_l2i(%s)", x), 0);
        return mkr(xsprintf("bb_cint(%s)", x), 0);
    case T_LONG:
        if (fk == T_BYTE || fk == T_BOOLEAN || fk == T_INTEGER) return mkr(xsprintf("((bb_long)%s)", x), 0);
        return mkr(xsprintf("bb_clng(%s)", x), 0);
    case T_SINGLE:
        if (fk == T_DOUBLE || fk == T_DATE) return mkr(xsprintf("bb_csng(%s)", x), 0);
        return mkr(xsprintf("((bb_single)%s)", x), 0);
    case T_DOUBLE: case T_DATE: return mkr(xsprintf("((bb_double)%s)", x), 0);
    case T_CURRENCY:
        if (fk == T_BYTE || fk == T_BOOLEAN || fk == T_INTEGER || fk == T_LONG) return mkr(xsprintf("bb_cur_from_long(%s)", x), 0);
        return mkr(xsprintf("bb_ccur(%s)", x), 0);
    default: break;
    }
    diag(e->p, src->file, src->line, src->col, "internal: no C conversion from %s to %s", type_name(src->ty), type_name(to));
    return mkr(x, 0);
}

static const char *cmp_c(int op)
{
    switch (op) {
    case OP_EQ: return "==";
    case OP_NE: return "!=";
    case OP_LT: return "<";
    case OP_GT: return ">";
    case OP_LE: return "<=";
    default: return ">=";
    }
}

static const char *cmp_bb(int op)
{
    switch (op) {
    case OP_EQ: return "BB_CMP_EQ";
    case OP_NE: return "BB_CMP_NE";
    case OP_LT: return "BB_CMP_LT";
    case OP_GT: return "BB_CMP_GT";
    case OP_LE: return "BB_CMP_LE";
    default: return "BB_CMP_GE";
    }
}

static R binop(EC *e, Node *n)
{
    Type *ot = n->a->ty;
    int k = n->ty->kind;
    char *a, *b;
    if (k == T_VARIANT) {
        const char *fn;
        a = val(e, n->a);
        b = val(e, n->b);
        if (n->op >= OP_EQ && n->op <= OP_GE) return mkr(xsprintf("bb_v_cmp(%s, %s, %s, %d)", cmp_bb(n->op), a, b, n->text), 1);
        switch (n->op) {
        case OP_ADD: fn = "bb_v_add"; break;
        case OP_SUB: fn = "bb_v_sub"; break;
        case OP_MUL: fn = "bb_v_mul"; break;
        case OP_DIV: fn = "bb_v_div"; break;
        case OP_IDIV: fn = "bb_v_idiv"; break;
        case OP_MOD: fn = "bb_v_mod"; break;
        case OP_POW: fn = "bb_v_pow"; break;
        case OP_CAT: fn = "bb_v_cat"; break;
        case OP_AND: fn = "bb_v_and"; break;
        case OP_OR: fn = "bb_v_or"; break;
        case OP_XOR: fn = "bb_v_xor"; break;
        case OP_EQV: fn = "bb_v_eqv"; break;
        default: fn = "bb_v_imp"; break;
        }
        return mkr(xsprintf("%s(%s, %s)", fn, a, b), 1);
    }
    if (n->op == OP_IS) {
        a = val(e, n->a);
        b = val(e, n->b);
        if (n->a->ty->kind == T_VARIANT) return mkr(xsprintf("bb_v_is(%s, %s)", a, b), 0);
        return mkr(xsprintf("((%s) == (%s) ? BB_TRUE : BB_FALSE)", a, b), 0);
    }
    a = val(e, n->a);
    b = val(e, n->b);
    switch (n->op) {
    case OP_ADD: case OP_SUB: case OP_MUL: {
        const char *o = n->op == OP_ADD ? "+" : n->op == OP_SUB ? "-" : "*";
        const char *nm = n->op == OP_ADD ? "add" : n->op == OP_SUB ? "sub" : "mul";
        switch (k) {
        case T_BYTE: return mkr(xsprintf("bb_%s_by(%s, %s)", nm, a, b), 0);
        case T_INTEGER: return mkr(xsprintf("bb_%s_i(%s, %s)", nm, a, b), 0);
        case T_LONG: return mkr(xsprintf("bb_%s_l(%s, %s)", nm, a, b), 0);
        case T_SINGLE: return mkr(xsprintf("bb_csng((double)(%s) %s (double)(%s))", a, o, b), 0);
        case T_DOUBLE: return mkr(xsprintf("bb_dchk((%s) %s (%s))", a, o, b), 0);
        case T_CURRENCY: return mkr(xsprintf("bb_cur_%s(%s, %s)", nm, a, b), 0);
        case T_DATE: return mkr(xsprintf("((bb_date)bb_dchk((double)(%s) %s (double)(%s)))", a, o, b), 0);
        default: break;
        }
        break;
    }
    case OP_DIV:
        if (k == T_SINGLE) return mkr(xsprintf("bb_csng(bb_div_d((double)(%s), (double)(%s)))", a, b), 0);
        return mkr(xsprintf("bb_div_d(%s, %s)", a, b), 0);
    case OP_POW: return mkr(xsprintf("bb_pow(%s, %s)", a, b), 0);
    case OP_IDIV:
        if (k == T_LONG) return mkr(xsprintf("bb_idiv_lx(%s, %s)", a, b), 0);
        if (k == T_BYTE) return mkr(xsprintf("((bb_byte)bb_idiv_ix(%s, %s))", a, b), 0);
        return mkr(xsprintf("bb_idiv_ix(%s, %s)", a, b), 0);
    case OP_MOD:
        if (k == T_LONG) return mkr(xsprintf("bb_mod_lx(%s, %s)", a, b), 0);
        if (k == T_BYTE) return mkr(xsprintf("((bb_byte)bb_mod_ix(%s, %s))", a, b), 0);
        return mkr(xsprintf("bb_mod_ix(%s, %s)", a, b), 0);
    case OP_CAT: return mkr(xsprintf("bb_str_concat(%s, %s)", a, b), 1);
    case OP_LIKE: return mkr(xsprintf("bb_like(%s, %s, %d)", a, b, n->text), 0);
    case OP_AND: case OP_OR: case OP_XOR: case OP_EQV: case OP_IMP: {
        const char *ct = ctype(n->ty);
        switch (n->op) {
        case OP_AND: return mkr(xsprintf("((%s)((%s) & (%s)))", ct, a, b), 0);
        case OP_OR: return mkr(xsprintf("((%s)((%s) | (%s)))", ct, a, b), 0);
        case OP_XOR: return mkr(xsprintf("((%s)((%s) ^ (%s)))", ct, a, b), 0);
        case OP_EQV: return mkr(xsprintf("((%s)~((%s) ^ (%s)))", ct, a, b), 0);
        default: return mkr(xsprintf("((%s)(~(%s) | (%s)))", ct, a, b), 0);
        }
    }
    default:
        if (n->op >= OP_EQ && n->op <= OP_GE) {
            if (ot->kind == T_STRING) {
                if ((n->op == OP_EQ || n->op == OP_NE) && !n->text)
                    return mkr(xsprintf("(%sbb_str_eq(%s, %s) ? BB_TRUE : BB_FALSE)", n->op == OP_NE ? "!" : "", a, b), 0);
                return mkr(xsprintf("(bb_str_cmp(%s, %s, %d) %s 0 ? BB_TRUE : BB_FALSE)", a, b, n->text, cmp_c(n->op)), 0);
            }
            return mkr(xsprintf("((%s) %s (%s) ? BB_TRUE : BB_FALSE)", a, cmp_c(n->op), b), 0);
        }
    }
    diag(e->p, n->file, n->line, n->col, "internal: no C code for operator %d on %s", n->op, type_name(n->ty));
    return mkr(xstrdup("0"), 0);
}

static R unop(EC *e, Node *n)
{
    int k = n->ty->kind;
    if (k == T_VARIANT) {
        char *a = val(e, n->a);
        return mkr(xsprintf("%s(%s)", n->op == OP_NEG ? "bb_v_neg" : "bb_v_not", a), 1);
    }
    {
        char *a = val(e, n->a);
        if (n->op == OP_NEG) {
            switch (k) {
            case T_INTEGER: return mkr(xsprintf("bb_neg_i(%s)", a), 0);
            case T_LONG: return mkr(xsprintf("bb_neg_l(%s)", a), 0);
            case T_CURRENCY: return mkr(xsprintf("bb_cur_sub(0, %s)", a), 0);
            case T_SINGLE: return mkr(xsprintf("((bb_single)-(%s))", a), 0);
            default: return mkr(xsprintf("(-(%s))", a), 0);
            }
        }
        return mkr(xsprintf("((%s)~(%s))", ctype(n->ty), a), 0);
    }
}

/* argument list for a call to pr (n->list holds one node per parameter) */
static char *call_args(EC *e, Proc *pr, Node *n, const char *self)
{
    Buf b = {0, 0, 0};
    int i, first = 1;
    if (self) { buf_puts(&b, self); first = 0; }
    for (i = 0; i < n->list.n && i < pr->nparams; i++) {
        Node *a = n->list.v[i];
        Param *pa = &pr->params[i];
        char *s;
        if (!first) buf_puts(&b, ", ");
        first = 0;
        if (a->kind == E_ARRAYLIT) {
            char *tn = new_temp(e, pa->ty, 1);
            int k;
            pre(e, "%s = bb_arr_new1(BB_VARIANT, 0, %d);", tn, a->list.n - 1);
            for (k = 0; k < a->list.n; k++) {
                Node *x = a->list.v[k];
                if (x->kind == E_MISSING) pre(e, "((bb_value *)%s->data)[%d] = bb_v_missing();", tn, k);
                else pre(e, "((bb_value *)%s->data)[%d] = %s;", tn, k, own(e, x));
            }
            s = xsprintf("&%s", tn);
        } else if (pa->byref) {
            if ((a->flags & NF_BYREF) || (a->ty->kind == T_UDT && is_lvalue(a))) s = addr(e, a);
            else {
                /* value for a ByRef parameter: a temporary */
                char *tn = new_temp(e, pa->ty, 1);
                if (a->kind == E_MISSING) pre(e, "%s = bb_v_missing();", tn);
                else if (pa->ty->kind == T_UDT) pre(e, "bb_udt_copy(%s, &%s, &%s);", udt_desc_ref(pa->ty), tn, val(e, a));
                else if (is_refty(pa->ty)) pre(e, "%s = %s;", tn, own(e, a));
                else pre(e, "%s = %s;", tn, val(e, a));
                if (pa->ty->kind == T_UDT) {
                    /* the temp must be initialised for bb_udt_copy */
                    pre(e, "%s", "");
                }
                s = xsprintf("&%s", tn);
            }
        } else {
            if (a->kind == E_MISSING) s = xstrdup("bb_v_missing()");
            else if (is_refty(pa->ty)) s = own(e, a);
            else s = val(e, a);
        }
        buf_puts(&b, s);
    }
    return b.p ? b.p : xstrdup("");
}

static R call(EC *e, Node *n)
{
    Proc *pr = n->proc;
    char *args;
    if (pr->kind == PK_DECLARE) {
        Buf b = {0, 0, 0};
        int i;
        for (i = 0; i < n->list.n; i++) {
            Node *a = n->list.v[i];
            char *s;
            if (a->flags & NF_BYREF) s = xsprintf("(uint32_t)(uintptr_t)%s", addr(e, a));
            else if (a->ty->kind == T_STRING) s = xsprintf("(uint32_t)(uintptr_t)bb_str_ptr(%s)", val(e, a));
            else if (a->ty->kind == T_OBJECT) s = xsprintf("(uint32_t)(uintptr_t)%s", val(e, a));
            else if (a->ty->kind == T_VARIANT || a->ty->kind == T_ANY) s = xsprintf("(uint32_t)bb_v_to_long(%s)", val(e, a));
            else if (is_scalar(a->ty)) s = xsprintf("(uint32_t)(int32_t)(%s)", val(e, a));
            else s = xsprintf("(uint32_t)(uintptr_t)%s", addr(e, a));
            buf_printf(&b, "%s%s", i ? ", " : "", s);
        }
        {
            char *callx = xsprintf("bb_declare_call(&bb_decl%d, %d, (const uint32_t[]){%s%s})", pr->index, n->list.n,
                                   b.p ? b.p : "", n->list.n ? "" : "0");
            if (!pr->ret) return mkr(callx, 0);
            if (pr->ret->kind == T_VARIANT) return mkr(xsprintf("bb_v_long((bb_long)%s)", callx), 1);
            {
                char *tn = new_temp(e, pr->ret, 0);
                pre(e, "%s = (%s)(int32_t)%s;", tn, ctype(pr->ret), callx);
                return mkr(tn, 0);
            }
        }
    }
    args = call_args(e, pr, n, pr->cls ? "self" : NULL);
    {
        char *callx = xsprintf("%s(%s)", proc_cname(pr), args);
        if (!pr->ret || (n->flags & NF_VOIDCALL)) return mkr(callx, pr->ret && is_refty(pr->ret));
        if (is_refty(pr->ret)) return mkr(callx, 1);
        {
            char *tn = new_temp(e, pr->ret, 0);
            pre(e, "%s = %s;", tn, callx);
            return mkr(tn, 0);
        }
    }
}

static R mcall(EC *e, Node *n)
{
    Proc *pr = n->proc;
    char *obj = val(e, n->a), *args, *callx, *ot;
    Node *rv = n->a;
    /* VB keeps the object alive for the call: unless the receiver is a local variable (which
       the method cannot reach), hold a reference, so `Set g = Nothing` inside it is safe */
    int local = (rv->kind == E_VAR && (rv->sym->storage == ST_LOCAL || rv->sym->storage == ST_PARAM) && !rv->sym->byref) ||
                rv->kind == E_ME;
    if (local) {
        ot = new_temp(e, &ty_object, 0);
        pre(e, "%s = bb_obj_check(%s);", ot, obj);
    } else {
        ot = new_temp(e, &ty_object, 1);
        pre(e, "%s = bb_obj_retain(bb_obj_check(%s));", ot, obj);
    }
    args = call_args(e, pr, n, ot);
    if (pr->cls->is_interface && pr->vslot >= 0)
        callx = xsprintf("((const struct V%d *)bb_vtbl(%s, &%s_class))->m%d(%s)", pr->cls->index, ot, cls_cname(pr->cls), pr->vslot, args);
    else
        callx = xsprintf("%s(%s)", proc_cname(pr), args);
    if (!pr->ret || (n->flags & NF_VOIDCALL)) return mkr(callx, pr->ret && is_refty(pr->ret));
    if (is_refty(pr->ret)) return mkr(callx, 1);
    {
        char *tn = new_temp(e, pr->ret, 0);
        pre(e, "%s = %s;", tn, callx);
        return mkr(tn, 0);
    }
}

static char *arr_of(EC *e, Node *a)
{
    if (a->ty->kind == T_ARRAY) return val(e, a);
    return xsprintf("bb_v_array(%s)", val(e, a));
}

static R builtin(EC *e, Node *n)
{
    const Builtin *b = &builtins[n->bi];
    Buf ab = {0, 0, 0};
    int i;
    const char *nm = b->name;
    /* extra (ignored) arguments are still evaluated */
    for (i = 0; i < n->list2.n; i++) {
        char *x = val(e, n->list2.v[i]);
        pre(e, "(void)(%s);", x);
    }
    if (!b->cfn[0]) {
        char *p = val(e, n->list.v[0]);
        if (name_eq(nm, "IsEmpty")) return mkr(xsprintf("(bb_v_deref(%s, &bb_vtmp)->type == BB_EMPTY ? BB_TRUE : BB_FALSE)", p), 0);
        if (name_eq(nm, "IsNull")) return mkr(xsprintf("(bb_v_deref(%s, &bb_vtmp)->type == BB_NULL ? BB_TRUE : BB_FALSE)", p), 0);
        if (name_eq(nm, "IsObject")) return mkr(xsprintf("(bb_v_deref(%s, &bb_vtmp)->type == BB_OBJECT ? BB_TRUE : BB_FALSE)", p), 0);
        if (name_eq(nm, "IsArray")) return mkr(xsprintf("((bb_v_deref(%s, &bb_vtmp)->type & BB_ARRAY) ? BB_TRUE : BB_FALSE)", p), 0);
        if (name_eq(nm, "IsMissing")) return mkr(xsprintf("(((%s)->type == BB_ERROR && ((%s)->flags & BB_VF_MISSING)) ? BB_TRUE : BB_FALSE)", p, p), 0);
    }
    if (b->flags & BIF_VARARGS) {
        int start = b->params[0] ? 1 : 0, cnt = n->list.n - start;
        char *arr = varr_temp(e, cnt);
        for (i = 0; i < cnt; i++) {
            pre(e, "%s[%d] = %s;", arr, i, own(e, n->list.v[start + i]));
            rel(e, xsprintf("bb_v_release(&%s[%d]);", arr, i));
        }
        if (name_eq(nm, "Choose")) return mkr(xsprintf("bb_choose(%s, %d, %s)", val(e, n->list.v[0]), cnt, arr), 1);
        return mkr(xsprintf("bb_array_fn(%d, %s)", cnt, arr), 1);
    }
    for (i = 0; i < n->list.n; i++) {
        Node *a = n->list.v[i];
        char pc = b->params[i];
        char *s;
        if (pc == 'a') s = arr_of(e, a);
        else if (a->kind == E_MISSING) s = xstrdup("&bb_vk_missing");
        else s = val(e, a);
        if (pc == 'T') s = xsprintf("(int)(%s)", s);
        if (pc == 'l' && (name_eq(nm, "LBound") || name_eq(nm, "UBound"))) s = xsprintf("(int)(%s)", s);
        buf_printf(&ab, "%s%s", i ? ", " : "", s);
    }
    {
        char *callx = xsprintf("%s(%s)", b->cfn, ab.p ? ab.p : "");
        switch (b->ret) {
        case T_STRING: case T_VARIANT: case T_ARRAY: return mkr(callx, 1);
        case T_VOID: return mkr(callx, 0);
        case T_INTEGER: return mkr(xsprintf("((bb_int)%s)", callx), 0);
        case T_DOUBLE:
            if (b->cfn[0] != 'b') return mkr(xsprintf("bb_dchk(%s)", callx), 0);
            return mkr(callx, 0);
        default: return mkr(callx, 0);
        }
    }
}

static R late(EC *e, Node *n)
{
    int i, cnt = n->list.n;
    char *arr = varr_temp(e, cnt);
    char *recv, *site;
    recv = val(e, n->a);
    for (i = 0; i < cnt; i++) {
        Node *x = n->list.v[i];
        Node *rv = x->kind == E_MISSING ? NULL : late_byref_var(x);
        if (x->kind == E_MISSING) pre(e, "%s[%d] = bb_v_missing();", arr, i);
        else if (rv) pre(e, "%s[%d] = bb_v_ref(%s, %s);", arr, i, vtname(rv->ty), addr(e, rv));   /* by reference */
        else pre(e, "%s[%d] = %s;", arr, i, own(e, x));
        rel(e, xsprintf("bb_v_release(&%s[%d]);", arr, i));
    }
    if (n->name[0] == 0 && n->a->ty->kind == T_VARIANT && (n->argc_kind & (BB_INV_GET | BB_INV_METHOD)))
        return mkr(xsprintf("bb_v_index(%s, %d, %s)", recv, cnt, arr), 1);
    site = xsprintf("bb_site%d", e->ntemp++);
    buf_printf(&e->decl, "    static bb_site %s;\n", site);
    if (n->a->ty->kind == T_VARIANT)
        return mkr(xsprintf("bb_v_invoke_site(%s, &%s, %s, %d, %d, %s)", recv, site, cstrlit(n->name, (int)strlen(n->name)), n->argc_kind, cnt, arr), 1);
    return mkr(xsprintf("bb_invoke_site(%s, &%s, %s, %d, %d, %s)", recv, site, cstrlit(n->name, (int)strlen(n->name)), n->argc_kind, cnt, arr), 1);
}

static R prod(EC *e, Node *n)
{
    switch (n->kind) {
    case E_CONST: return mkr(const_expr(e, n), 0);
    case E_VAR:
        if (n->sym->is_new && n->ty->kind == T_OBJECT && n->ty->cls)
            /* As New: created on first use */
            return mkr(xsprintf("bb_autonew((bb_obj **)&%s, %s)", lval(e, n),
                                n->ty->cls->builtin ? "bb_collection_new" : xsprintf("%s_new", cls_cname(n->ty->cls))), 0);
        if (n->ty->kind == T_VARIANT) {
            if (sym_is_ref(n->sym)) return mkr(sym_cname(e, n->sym), 0);
            return mkr(xsprintf("((bb_value *)&%s)", lval(e, n)), 0);
        }
        return mkr(lval(e, n), 0);
    case E_INDEX: case E_FIELD: case E_MFIELD:
        if (n->kind == E_MFIELD && n->sym->is_new && n->ty->kind == T_OBJECT && n->ty->cls)
            return mkr(xsprintf("bb_autonew((bb_obj **)&%s, %s)", lval(e, n),
                                n->ty->cls->builtin ? "bb_collection_new" : xsprintf("%s_new", cls_cname(n->ty->cls))), 0);
        if (n->ty->kind == T_VARIANT) return mkr(xsprintf("(&%s)", lval(e, n)), 0);
        return mkr(lval(e, n), 0);
    case E_CONV: {
        Type *to = n->ty, *from = n->a->ty;
        if ((n->flags & NF_PARENARG) && type_eq(to, from)) {
            R r = prod(e, n->a);
            return r;
        }
        if (to->kind == T_STRING && to->fixlen) {
            char *s = from->kind == T_STRING ? val(e, n->a) : NULL;
            if (!s) {
                Node tmp = *n;
                tmp.ty = &ty_string;
                {
                    R r = conv_scalar(e, n->a, &ty_string);
                    char *tn;
                    if (r.own) { tn = new_temp(e, &ty_string, 1); pre(e, "%s = %s;", tn, r.s); s = tn; }
                    else s = r.s;
                }
            }
            return mkr(xsprintf("bb_str_fixlen(%s, %d)", s, to->fixlen), 1);
        }
        if (type_eq(to, from)) return prod(e, n->a);
        return conv_scalar(e, n->a, to);
    }
    case E_BIN: return binop(e, n);
    case E_UN: return unop(e, n);
    case E_CALL: return call(e, n);
    case E_MCALL: return mcall(e, n);
    case E_BUILTIN: return builtin(e, n);
    case E_LATE: return late(e, n);
    case E_NEW:
        if (n->cls->builtin) return mkr(xstrdup("bb_collection_new()"), 1);
        return mkr(xsprintf("%s_new()", cls_cname(n->cls)), 1);
    case E_TYPEOF: {
        char *o = val(e, n->a);
        if (!n->cls) return mkr(xstrdup("BB_FALSE"), 0);
        if (n->cls->builtin) return mkr(xsprintf("(bb_obj_is(%s, &bb_collection_class) ? BB_TRUE : BB_FALSE)", o), 0);
        return mkr(xsprintf("(bb_obj_is(%s, &%s_class) ? BB_TRUE : BB_FALSE)", o, cls_cname(n->cls)), 0);
    }
    case E_ME: return mkr(xstrdup("self"), 0);
    case E_MISSING: return mkr(xstrdup("bb_v_missing()"), 1);
    case E_ERRPROP:
        switch (n->op) {
        case 1: return mkr(xstrdup("bb_err_number()"), 0);
        case 2: return mkr(xstrdup("bb_err_description()"), 1);
        case 3: return mkr(xstrdup("bb_err_source()"), 1);
        case 4: {
            char *a = val(e, n->list.v[0]), *b, *c;
            b = n->list.v[1]->kind == E_MISSING ? xstrdup("&bb_vk_missing") : val(e, n->list.v[1]);
            c = n->list.v[2]->kind == E_MISSING ? xstrdup("&bb_vk_missing") : val(e, n->list.v[2]);
            return mkr(xsprintf("bb_err_raise_v(%s, %s, %s)", a, b, c), 0);
        }
        case 5: return mkr(xstrdup("bb_err_clear()"), 0);
        case 7: return mkr(xstrdup("bb_k_empty"), 0);
        default: return mkr(xstrdup("((bb_long)0)"), 0);
        }
    default:
        diag(e->p, n->file, n->line, n->col, "internal: cannot emit C for expression kind %d", n->kind);
        return mkr(xstrdup("0"), 0);
    }
}

/* ---------- statements ---------- */

static void stmt(EC *e, Node *s);

static void block(EC *e, NodeList *b)
{
    int i;
    for (i = 0; i < b->n; i++) stmt(e, b->v[i]);
}

static void line_marker(EC *e, Node *s)
{
    if (e->resume) {
        e->nstmt++;
        out(e, "bb_S%d: bb_stmt = %d;", e->nstmt, e->nstmt);
    }
    if (!e->debug || s->line != e->line || s->file != e->file) {
        buf_printf(&e->body, "#line %d %s\n", s->line, cstrlit(file_name(e->p, s->file), (int)strlen(file_name(e->p, s->file))));
        e->line = s->line;
        e->file = s->file;
    }
    if (e->multi_file) out(e, "bb_line = %d; bb_file = bb_files[%d];", s->line, s->file);
    else out(e, "bb_line = %d;", s->line);
}

/* the statement's prelude, then its action line, then releases */
static void action(EC *e, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void action(EC *e, const char *fmt, ...)
{
    char tmp[8192];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    flush_pre(e);
    out(e, "%s", tmp);
    flush_rel(e);
}


/* assignment of an owned / borrowed value of n->ty to lvalue t */
static void assign(EC *e, Node *t, Node *v)
{
    Type *ty = t->ty;
    char *lv, *x;
    switch (ty->kind) {
    case T_STRING:
        x = own(e, v);
        lv = lval(e, t);
        action(e, "bb_str_set((bb_str **)&%s, %s);", lv, x);
        return;
    case T_OBJECT:
        x = own(e, v);
        lv = lval(e, t);
        action(e, "bb_obj_set((bb_obj **)&%s, %s);", lv, x);
        return;
    case T_VARIANT:
        x = own(e, v);
        lv = lval(e, t);
        action(e, "bb_v_set((bb_value *)&%s, %s);", lv, x);
        return;
    case T_ARRAY: {
        R r = prod(e, v);
        lv = lval(e, t);
        if (r.own) action(e, "bb_arr_set((bb_array **)&%s, %s);", lv, r.s);
        else action(e, "bb_arr_assign((bb_array **)&%s, %s);", lv, r.s);
        return;
    }
    case T_UDT:
        x = val(e, v);
        lv = lval(e, t);
        action(e, "bb_udt_copy(&%s_desc, (void *)&%s, (const void *)&%s);", udt_cname(ty->udt), lv, x);
        return;
    default:
        x = val(e, v);
        lv = lval(e, t);
        action(e, "%s = %s;", lv, x);
    }
}

/* store an owned bb_value (C expression of a temp variable) into lvalue t, converting */
static void store_from_variant(EC *e, Node *t, const char *tv)
{
    Type *ty = t->ty;
    char *lv = lval(e, t);
    switch (ty->kind) {
    case T_VARIANT: action(e, "bb_v_set((bb_value *)&%s, %s); %s = bb_v_empty();", lv, tv, tv); return;
    case T_STRING:
        if (ty->fixlen) action(e, "bb_str_set((bb_str **)&%s, bb_str_fixlen(bb_v_to_str(&%s), %d)); bb_v_release(&%s);", lv, tv, ty->fixlen, tv);
        else action(e, "bb_str_set((bb_str **)&%s, bb_v_to_str(&%s)); bb_v_release(&%s);", lv, tv, tv);
        return;
    case T_OBJECT:
        if (ty->cls && !ty->cls->builtin)
            action(e, "bb_obj_set((bb_obj **)&%s, bb_chkcls(bb_v_to_obj(&%s), &%s_class)); bb_v_release(&%s);", lv, tv, cls_cname(ty->cls), tv);
        else action(e, "bb_obj_set((bb_obj **)&%s, bb_v_to_obj(&%s)); bb_v_release(&%s);", lv, tv, tv);
        return;
    case T_BOOLEAN: action(e, "%s = bb_v_to_bool(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_BYTE: action(e, "%s = bb_v_to_byte(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_INTEGER: action(e, "%s = bb_v_to_int(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_LONG: action(e, "%s = bb_v_to_long(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_SINGLE: action(e, "%s = bb_v_to_single(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_DOUBLE: action(e, "%s = bb_v_to_double(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_CURRENCY: action(e, "%s = bb_v_to_cur(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    case T_DATE: action(e, "%s = bb_v_to_date(&%s); bb_v_release(&%s);", lv, tv, tv); return;
    default:
        diag(e->p, t->file, t->line, t->col, "internal: cannot store a Variant into %s", type_name(ty));
    }
}

static char *cond_c(EC *e, Node *c)
{
    if (c->ty->kind == T_VARIANT) return xsprintf("bb_v_truth(%s)", val(e, c));
    return val(e, c);
}

static void print_item(EC *e, const char *fn, Node *x)
{
    char *v = val(e, x);
    switch (x->ty->kind) {
    case T_BYTE: case T_INTEGER: case T_LONG: action(e, "bb_print_long(%s, %s);", fn, v); break;
    case T_BOOLEAN: action(e, "bb_print_bool(%s, %s);", fn, v); break;
    case T_SINGLE: action(e, "bb_print_single(%s, %s);", fn, v); break;
    case T_DOUBLE: action(e, "bb_print_double(%s, %s);", fn, v); break;
    case T_CURRENCY: action(e, "bb_print_cur(%s, %s);", fn, v); break;
    case T_DATE: action(e, "bb_print_date(%s, %s);", fn, v); break;
    case T_STRING: action(e, "bb_print_str(%s, %s);", fn, v); break;
    default: action(e, "bb_print_value(%s, %s);", fn, v); break;
    }
}

static int push_loop(EC *e, int kind)
{
    int id = e->nlabel++;
    e->loops[e->nloops] = id;
    e->loopk[e->nloops] = kind;
    e->nloops++;
    return id;
}

static const char *step_add(Type *t)
{
    switch (t->kind) {
    case T_BYTE: return "bb_add_by";
    case T_INTEGER: return "bb_add_i";
    case T_LONG: return "bb_add_l";
    case T_SINGLE: return "bb_add_f";
    case T_CURRENCY: return "bb_cur_add";
    default: return NULL;
    }
}

static void for_stmt(EC *e, Node *s)
{
    Node *ctr = s->a, *lim = s->list2.v[0], *stp = s->list2.v[1];
    Type *t = ctr->ty;
    int id;
    char *cv, *lv, *sv, *xs, *xl, *xa;
    int const_step = 0;
    double step = 0;
    if (s->d->kind == E_CONST && s->d->cv.type != T_STRING) {
        const_step = 1;
        step = (s->d->cv.type == T_INTEGER || s->d->cv.type == T_LONG || s->d->cv.type == T_BYTE) ? (double)s->d->cv.i : s->d->cv.d;
    }
    if (t->kind == T_VARIANT) {
        assign(e, ctr, s->b);
        lv = lval(e, lim);
        xl = own(e, s->c);
        action(e, "bb_v_set((bb_value *)&%s, %s);", lv, xl);
        sv = lval(e, stp);
        xs = own(e, s->d);
        action(e, "bb_v_set((bb_value *)&%s, %s);", sv, xs);
        id = push_loop(e, EXIT_FOR);
        out(e, "for (;;) {");
        e->indent++;
        out(e, "bb_poll();");
        cv = val(e, ctr);
        action(e, "if (bb_for_done_v(%s, (bb_value *)&%s, (bb_value *)&%s)) break;", cv, lv, sv);
        block(e, &s->list);
        cv = val(e, ctr);
        action(e, "bb_v_set((bb_value *)&%s, bb_v_add(%s, (bb_value *)&%s));", lval(e, ctr), cv, sv);
        e->indent--;
        out(e, "}");
        out(e, "bb_X%d: ;", id);
        e->nloops--;
        return;
    }
    /* VB: start, end and step are evaluated once */
    {
        char *a = val(e, s->b);
        flush_pre(e);
        xa = xstrdup(a);
        lv = lval(e, lim);
        xl = val(e, s->c);
        flush_pre(e);
        out(e, "%s = %s;", lv, xl);
        sv = lval(e, stp);
        xs = val(e, s->d);
        flush_pre(e);
        out(e, "%s = %s;", sv, xs);
        cv = lval(e, ctr);
        out(e, "%s = %s;", cv, xa);
        flush_rel(e);
    }
    id = push_loop(e, EXIT_FOR);
    {
        const char *add = step_add(t);
        char *inc = add ? xsprintf("%s = %s(%s, %s)", cv, add, cv, sv) : xsprintf("%s = %s + %s", cv, cv, sv);
        char *test;
        if (const_step) test = xsprintf("%s %s %s", cv, step >= 0 ? "<=" : ">=", lv);
        else test = xsprintf("(%s >= 0 ? %s <= %s : %s >= %s)", sv, cv, lv, cv, lv);
        out(e, "for (; %s; %s) {", test, inc);
    }
    e->indent++;
    out(e, "bb_poll();");
    block(e, &s->list);
    e->indent--;
    out(e, "}");
    out(e, "bb_X%d: ;", id);
    e->nloops--;
}

static void foreach_stmt(EC *e, Node *s)
{
    int id = e->nlabel++, k;
    char *fe = xsprintf("fe%d", id), *fv = xsprintf("fv%d", id), *src;
    Buf saved_rel;
    buf_printf(&e->decl, "    bb_foreach %s; bb_value %s = {0, 0, 0, {0}};\n", fe, fv);
    if (s->b->ty->kind == T_ARRAY) {
        char *a = val(e, s->b);
        char *view = xsprintf("av%d", id);
        buf_printf(&e->decl, "    bb_value %s;\n", view);
        pre(e, "%s = bb_v_make((uint16_t)(BB_ARRAY | %s)); %s.u.a = %s;", view, vtname(s->b->ty->elem), view, a);
        src = xsprintf("&%s", view);
    } else if (s->b->ty->kind == T_OBJECT) {
        char *o = val(e, s->b);
        char *view = xsprintf("av%d", id);
        buf_printf(&e->decl, "    bb_value %s;\n", view);
        pre(e, "%s = bb_v_obj(%s);", view, o);
        src = xsprintf("&%s", view);
    } else src = val(e, s->b);
    flush_pre(e);
    out(e, "bb_foreach_begin(&%s, %s);", fe, src);
    /* the collection's temporaries live until the loop ends */
    saved_rel = e->rel;
    memset(&e->rel, 0, sizeof e->rel);
    k = e->nloops;
    e->loops[k] = id;
    e->loopk[k] = EXIT_FOR;
    e->nloops++;
    out(e, "while (bb_foreach_next(&%s, &%s)) {", fe, fv);
    e->indent++;
    out(e, "bb_poll();");
    store_from_variant(e, s->a, fv);
    block(e, &s->list);
    e->indent--;
    out(e, "}");
    out(e, "bb_X%d: ;", id);
    e->nloops--;
    out(e, "bb_foreach_end(&%s); bb_v_release(&%s);", fe, fv);
    if (saved_rel.n) buf_put(&e->body, saved_rel.p, saved_rel.n);
    buf_free(&saved_rel);
}

static int find_loop(EC *e, int kind)
{
    int k;
    for (k = e->nloops - 1; k >= 0; k--) if (e->loopk[k] == kind) return e->loops[k];
    return -1;
}

static void gosub_add(EC *e, int id)
{
    if (e->ngosub == e->capgosub) {
        e->capgosub = e->capgosub ? e->capgosub * 2 : 16;
        e->gosub_ids = (int *)xrealloc(e->gosub_ids, sizeof(int) * (size_t)e->capgosub);
    }
    e->gosub_ids[e->ngosub++] = id;
}

static void stmt(EC *e, Node *s)
{
    int i;
    line_marker(e, s);
    switch (s->kind) {
    case S_LET: case S_SET:
        if (s->a->kind == E_ERRPROP) {
            char *x = val(e, s->b);
            if (s->a->op == 1) action(e, "bb_err_set_number(%s);", x);
            else if (s->a->op == 2) action(e, "bb_err_set_description(%s);", x);
            else action(e, "bb_err_set_source(%s);", x);
            return;
        }
        assign(e, s->a, s->b);
        if (s->kind == S_SET && s->a->kind == E_VAR && s->a->sym->withevents) {
            Sym *v = s->a->sym;
            if (v->storage == ST_FIELD)
                out(e, "bb_wev_connect(&((%s *)self)->wev_%s, ((%s *)self)->%s, wev_fire_%d_%s, self, 0);",
                    cls_cname(v->cls), cident(v->name), cls_cname(v->cls), sym_cname(e, v), v->cls->index, cident(v->name));
            else
                out(e, "bb_wev_connect(&wevg%d, %s, wev_fireg%d, NULL, 0);", v->index, sym_cname(e, v), v->index);
        }
        return;
    case S_EXPR: {
        Node *x = s->a;
        if (x->kind == E_LATE && x->name[0] == 0 && (x->argc_kind & (BB_INV_LET | BB_INV_SET)) &&
            x->a->ty->kind == T_VARIANT && is_lvalue(x->a)) {
            int cnt = x->list.n;
            char *arr = varr_temp(e, cnt);
            char *target;
            for (i = 0; i < cnt; i++) {
                pre(e, "%s[%d] = %s;", arr, i, own(e, x->list.v[i]));
                rel(e, xsprintf("bb_v_release(&%s[%d]);", arr, i));
            }
            target = addr(e, x->a);
            action(e, "bb_v_index_store(%s, %d, %s, &%s[%d]);", target, cnt - 1, arr, arr, cnt - 1);
            return;
        }
        {
            R r = prod(e, x);
            if (r.own && is_refty(x->ty)) {
                char *tn = new_temp(e, x->ty, 1);
                action(e, "%s = %s;", tn, r.s);
            } else action(e, "(void)%s;", r.s);
        }
        return;
    }
    case S_IF: {
        int depth = 0;
        for (i = 0; i < s->list.n; i++) {
            Node *br = s->list.v[i];
            char *c = cond_c(e, br->a);
            char *cn = xsprintf("c%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", cn);
            if (i > 0) { out(e, "} else {"); e->indent++; depth++; line_marker(e, br); }
            action(e, "%s = %s;", cn, c);
            out(e, "if (%s) {", cn);
            e->indent++;
            block(e, &br->list);
            e->indent--;
        }
        if (s->list2.n) {
            out(e, "} else {");
            e->indent++;
            block(e, &s->list2);
            e->indent--;
        }
        out(e, "}");
        while (depth-- > 0) { e->indent--; out(e, "}"); }
        return;
    }
    case S_SELECT: {
        int endl = e->nlabel++;
        Sym *t = s->sym;
        Node tv;
        memset(&tv, 0, sizeof tv);
        tv.kind = E_VAR;
        tv.sym = t;
        tv.ty = t->ty;
        assign(e, &tv, s->a);
        for (i = 0; i < s->list.n; i++) {
            Node *cs = s->list.v[i];
            int match = e->nlabel++, next = e->nlabel++, k;
            if (cs->flags & NF_CASEELSE) {
                block(e, &cs->list2);
                continue;
            }
            for (k = 0; k < cs->list.n; k++) {
                char *c = cond_c(e, cs->list.v[k]);
                char *cn = xsprintf("c%d", e->ntemp++);
                buf_printf(&e->decl, "    int %s;\n", cn);
                action(e, "%s = %s;", cn, c);
                out(e, "if (%s) goto bb_L%d;", cn, match);
            }
            out(e, "goto bb_L%d;", next);
            out(e, "bb_L%d: ;", match);
            e->indent++;
            block(e, &cs->list2);
            e->indent--;
            out(e, "goto bb_L%d;", endl);
            out(e, "bb_L%d: ;", next);
        }
        out(e, "bb_L%d: ;", endl);
        return;
    }
    case S_FOR: for_stmt(e, s); return;
    case S_FOREACH: foreach_stmt(e, s); return;
    case S_DO: {
        int id = push_loop(e, EXIT_DO);
        out(e, "for (;;) {");
        e->indent++;
        out(e, "bb_poll();");
        if (s->op == DO_PRE_WHILE || s->op == DO_PRE_UNTIL) {
            char *c = cond_c(e, s->a);
            char *cn = xsprintf("c%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", cn);
            action(e, "%s = %s;", cn, c);
            out(e, "if (%s%s) break;", s->op == DO_PRE_WHILE ? "!" : "", cn);
        }
        block(e, &s->list);
        if (s->op == DO_POST_WHILE || s->op == DO_POST_UNTIL) {
            char *c, *cn;
            line_marker(e, s->a);
            c = cond_c(e, s->a);
            cn = xsprintf("c%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", cn);
            action(e, "%s = %s;", cn, c);
            out(e, "if (%s%s) break;", s->op == DO_POST_WHILE ? "!" : "", cn);
        }
        e->indent--;
        out(e, "}");
        out(e, "bb_X%d: ;", id);
        e->nloops--;
        return;
    }
    case S_EXIT:
        if (s->op == EXIT_FOR || s->op == EXIT_DO) out(e, "goto bb_X%d;", find_loop(e, s->op));
        else out(e, "goto bb_exit;");
        return;
    case S_GOTO: out(e, "goto bb_lab%d;", s->sym ? s->sym->label_id : 0); return;
    case S_GOSUB: {
        int id = e->nlabel++;
        gosub_add(e, id);
        out(e, "if (bb_gsp >= 64) bb_raise(28, NULL);");
        out(e, "bb_gs[bb_gsp++] = %d; goto bb_lab%d;", id, s->sym ? s->sym->label_id : 0);
        out(e, "bb_R%d: ;", id);
        return;
    }
    case S_RETURN: out(e, "goto bb_gsret;"); return;
    case S_LABEL:
        if (s->sym) out(e, "bb_lab%d: ;", s->sym->label_id);
        return;
    case S_ONGOTO: {
        char *x = val(e, s->a);
        int id = e->nlabel++;
        action(e, "switch (%s) {", x);
        for (i = 0; i < s->list.n; i++) {
            if (s->op) {
                gosub_add(e, id * 1000 + i);
                out(e, "case %d: bb_gs[bb_gsp++] = %d; goto bb_lab%d;", i + 1, id * 1000 + i, s->list.v[i]->sym ? s->list.v[i]->sym->label_id : 0);
            } else out(e, "case %d: goto bb_lab%d;", i + 1, s->list.v[i]->sym ? s->list.v[i]->sym->label_id : 0);
        }
        out(e, "default: break;");
        out(e, "}");
        if (s->op) {
            out(e, "goto bb_L%d;", id);
            for (i = 0; i < s->list.n; i++) out(e, "bb_R%d: goto bb_L%d;", id * 1000 + i, id);
            out(e, "bb_L%d: ;", id);
        }
        return;
    }
    case S_ONERROR:
        if (s->op == ONERR_GOTO) out(e, "bb_mode = 1; bb_hlabel = %d; if (!bb_inh) bb_err_clear();", s->sym ? s->sym->label_id : 0);
        else if (s->op == ONERR_RESUMENEXT) out(e, "bb_mode = 2; if (!bb_inh) bb_err_clear();");
        else out(e, "bb_mode = 0; if (!bb_inh) bb_err_clear();");
        return;
    case S_RESUME:
        if (s->op == RES_LABEL) out(e, "bb_inh = 0; bb_err_clear(); goto bb_lab%d;", s->sym ? s->sym->label_id : 0);
        else if (s->op == RES_NEXT) out(e, "if (!bb_inh) bb_raise(20, NULL); bb_inh = 0; bb_err_clear(); bb_rs = bb_estmt + 1; goto bb_resume;");
        else out(e, "if (!bb_inh) bb_raise(20, NULL); bb_inh = 0; bb_err_clear(); bb_rs = bb_estmt; goto bb_resume;");
        return;
    case S_PRINT: {
        char *fn;
        int last = PSEP_NONE;
        if (s->a) {
            char *x = val(e, s->a);
            fn = xsprintf("fn%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", fn);
            action(e, "%s = (int)%s;", fn, x);
        } else fn = xstrdup((s->flags & NF_DEBUG) ? "-1" : "0");
        for (i = 0; i < s->list.n; i++) {
            Node *it = s->list.v[i];
            if (it->ival == PI_EXPR && it->a) print_item(e, fn, it->a);
            else if (it->ival == PI_SPC) action(e, "bb_print_spc(%s, %s);", fn, it->a ? val(e, it->a) : "1");
            else if (it->ival == PI_TAB) {
                if (it->a) action(e, "bb_print_tab(%s, %s);", fn, val(e, it->a));
                else action(e, "bb_print_comma(%s);", fn);
            }
            if (it->op == PSEP_COMMA) out(e, "bb_print_comma(%s);", fn);
            last = it->op;
            if (it->ival == PI_TAB && !it->a && it->op == PSEP_NONE) last = PSEP_SEMI;
        }
        if (last == PSEP_NONE) out(e, "bb_print_nl(%s);", fn);
        return;
    }
    case S_WRITE: {
        char *x = val(e, s->a);
        char *fn = xsprintf("fn%d", e->ntemp++);
        buf_printf(&e->decl, "    int %s;\n", fn);
        action(e, "%s = (int)%s;", fn, x);
        if (!s->list.n) { out(e, "bb_print_nl(%s);", fn); return; }
        for (i = 0; i < s->list.n; i++) {
            char *v = val(e, s->list.v[i]);
            action(e, "bb_write_value(%s, %s, %d);", fn, v, i == s->list.n - 1);
        }
        return;
    }
    case S_INPUT: {
        char *fn;
        if (s->b) action(e, "bb_input_prompt(%s, %d);", val(e, s->b), (s->flags & NF_QUESTION) != 0);
        else if (!s->a) out(e, "bb_input_prompt(NULL, 1);");
        if (s->a) {
            char *x = val(e, s->a);
            fn = xsprintf("fn%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", fn);
            action(e, "%s = (int)%s;", fn, x);
        } else fn = xstrdup("0");
        for (i = 0; i < s->list.n; i++) {
            Node *t = s->list.v[i];
            char *tv = struct_member(e, &ty_variant, xsprintf("t%d", e->ntemp++));
            out(e, "%s = bb_input_field(%s, %d);", tv, fn, t->ty->kind == T_VARIANT);
            store_from_variant(e, t, tv);
        }
        out(e, "bb_input_end(%s);", fn);
        return;
    }
    case S_LINEINPUT: {
        char *fn, *tv;
        if (s->b) action(e, "bb_input_prompt(%s, 0);", val(e, s->b));
        if (s->a) {
            char *x = val(e, s->a);
            fn = xsprintf("fn%d", e->ntemp++);
            buf_printf(&e->decl, "    int %s;\n", fn);
            action(e, "%s = (int)%s;", fn, x);
        } else fn = xstrdup("0");
        tv = struct_member(e, &ty_variant, xsprintf("t%d", e->ntemp++));
        out(e, "%s = bb_v_str(bb_input_line(%s));", tv, fn);
        store_from_variant(e, s->c, tv);
        return;
    }
    case S_OPEN: {
        char *path = val(e, s->a), *fnx = val(e, s->b), *rl = s->c ? val(e, s->c) : xstrdup("0");
        action(e, "bb_open(%s, %d, 0, %s, %s);", path, s->op, fnx, rl);
        return;
    }
    case S_CLOSE:
        if (!s->list.n) { out(e, "bb_close_all();"); return; }
        for (i = 0; i < s->list.n; i++) action(e, "bb_close(%s);", val(e, s->list.v[i]));
        return;
    case S_GET: case S_PUT: {
        char *fnx = val(e, s->a), *rec = s->b ? val(e, s->b) : xstrdup("0"), *p = addr(e, s->c);
        Type *t = s->c->ty;
        const char *vt = t->kind == T_ARRAY ? xsprintf("(BB_ARRAY | %s)", vtname(t->elem)) : vtname(t);
        action(e, "%s(%s, %s, %s, %s, %s);", s->kind == S_GET ? "bb_get" : "bb_put", fnx, rec, vt, udt_desc_ref(t), p);
        return;
    }
    case S_SEEK: action(e, "bb_seek_set(%s, %s);", val(e, s->a), val(e, s->b)); return;
    case S_NAME: action(e, "bb_name(%s, %s);", val(e, s->a), val(e, s->b)); return;
    case S_REDIM:
        for (i = 0; i < s->list.n; i++) {
            Node *d = s->list.v[i];
            Buf lb = {0, 0, 0}, ub = {0, 0, 0};
            int k;
            char *target;
            for (k = 0; k < d->list.n; k++) {
                buf_printf(&lb, "%s%s", k ? ", " : "", val(e, d->list.v[k]->a));
                buf_printf(&ub, "%s%s", k ? ", " : "", val(e, d->list.v[k]->b));
            }
            target = addr(e, d->b);
            if (d->b->ty->kind == T_VARIANT)
                action(e, "bb_v_redim(%s, %s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}, %d);", target,
                       vtname(d->ty), udt_desc_ref(d->ty), d->list.n, lb.p, ub.p, (s->flags & NF_PRESERVE) != 0);
            else
                action(e, "bb_arr_redim(%s, %s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}, %d);", target,
                       vtname(d->ty), udt_desc_ref(d->ty), d->list.n, lb.p, ub.p, (s->flags & NF_PRESERVE) != 0);
        }
        return;
    case S_ERASE:
        for (i = 0; i < s->list.n; i++) {
            Node *t = s->list.v[i];
            char *a = addr(e, t);
            if (t->ty->kind == T_VARIANT) action(e, "bb_v_erase(%s);", a);
            else action(e, "bb_arr_erase(%s);", a);
        }
        return;
    case S_MIDASSIGN: {
        char *a = addr(e, s->a), *st = val(e, s->b), *ln = s->c ? val(e, s->c) : xstrdup("-1"), *v = val(e, s->d);
        if (s->a->ty->kind == T_VARIANT) action(e, "bb_v_mid_assign(%s, %s, %s, %s);", a, st, ln, v);
        else action(e, "bb_mid_assign(%s, %s, %s, %s);", a, st, ln, v);
        return;
    }
    case S_END: out(e, "bb_end();"); return;
    case S_STOP: out(e, "bb_print_cstr(0, \"Stop\\n\"); bb_exit(0);"); return;
    case S_WITH: {
        Sym *t = s->sym;
        char *tn = sym_cname(e, t);
        if (t->byref) action(e, "%s = %s;", tn, addr(e, s->a));
        else if (t->ty->kind == T_OBJECT) action(e, "bb_obj_set(&%s, %s);", tn, own(e, s->a));
        else action(e, "bb_v_set(&%s, %s);", tn, own(e, s->a));
        block(e, &s->list);
        if (!t->byref) {
            if (t->ty->kind == T_OBJECT) out(e, "bb_obj_set(&%s, NULL);", tn);
            else out(e, "bb_v_release(&%s);", tn);
        }
        return;
    }
    case S_RAISEEVENT: {
        int cnt = s->list.n;
        char *arr = varr_temp(e, cnt);
        for (i = 0; i < cnt; i++) {
            Node *a = s->list.v[i];
            if (a->flags & NF_BYREF) pre(e, "%s[%d] = bb_v_ref(%s, %s);", arr, i, vtname(a->ty), addr(e, a));
            else if (a->kind == E_MISSING) pre(e, "%s[%d] = bb_v_missing();", arr, i);
            else {
                Node conv;
                memset(&conv, 0, sizeof conv);
                conv.kind = E_CONV;
                conv.a = a;
                conv.ty = &ty_variant;
                if (a->ty->kind == T_VARIANT) pre(e, "%s[%d] = %s;", arr, i, own(e, a));
                else pre(e, "%s[%d] = %s;", arr, i, own(e, &conv));
                rel(e, xsprintf("bb_v_release(&%s[%d]);", arr, i));
            }
        }
        action(e, "bb_event_raise(self, %d, %s, %d, %s);", s->proc->event_index,
               cstrlit(s->proc->name, (int)strlen(s->proc->name)), cnt, arr);
        return;
    }
    case S_ERROR: action(e, "bb_raise(%s, NULL);", val(e, s->a)); return;
    case S_NOP: case S_DIM: case S_CONST: return;
    default:
        diag(e->p, s->file, s->line, s->col, "internal: cannot emit C for statement kind %d", s->kind);
    }
}

/* ---------- procedures ---------- */

static char *param_decl(Param *pa, Sym *s, EC *e)
{
    Type *t = pa->ty;
    const char *ct = t->kind == T_UDT ? udt_cname(t->udt) : ctype(t);
    if (pa->byref) return xsprintf("%s *%s", ct, sym_cname(e, s));
    return xsprintf("%s %s", ct, sym_cname(e, s));
}

static char *proc_sig(EC *e, Proc *pr, int named)
{
    Buf b = {0, 0, 0};
    int i, first = 1;
    const char *rt = pr->ret ? (pr->ret->kind == T_UDT ? udt_cname(pr->ret->udt) : ctype(pr->ret)) : "void";
    buf_printf(&b, "static %s %s(", rt, named ? proc_cname(pr) : "");
    if (pr->cls) { buf_puts(&b, "bb_obj *self"); first = 0; }
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        if (!first) buf_puts(&b, ", ");
        first = 0;
        if (pa->sym) buf_puts(&b, param_decl(pa, pa->sym, e));
        else {
            const char *ct = pa->ty->kind == T_UDT ? udt_cname(pa->ty->udt) : ctype(pa->ty);
            buf_printf(&b, "%s %sa%d", ct, pa->byref ? "*" : "", i);
        }
    }
    if (first) buf_puts(&b, "void");
    buf_puts(&b, ")");
    return b.p;
}

static void local_init(EC *e, Buf *d, Sym *s, int vol)
{
    Type *t = s->ty;
    char *n = sym_cname(e, s);
    const char *v = vol ? "volatile " : "";
    if (t->kind == T_UDT) {
        if (s->byref) { buf_printf(d, "    %s *%s = NULL;\n", udt_cname(t->udt), n); return; }
        buf_printf(d, "    %s%s %s;\n", v, udt_cname(t->udt), n);
        buf_printf(d, "    bb_udt_init(&%s_desc, (void *)&%s);\n", udt_cname(t->udt), n);
        return;
    }
    if (s->byref) { buf_printf(d, "    %s *%s = NULL;\n", ctype(t), n); return; }
    if (t->kind == T_STRING || t->kind == T_OBJECT || t->kind == T_ARRAY) buf_printf(d, "    %s%s%s = NULL;\n", ctype(t), vol ? " volatile " : "", n);
    else if (t->kind == T_VARIANT) buf_printf(d, "    %sbb_value %s = {0, 0, 0, {0}};\n", v, n);
    else buf_printf(d, "    %s%s %s = 0;\n", v, ctype(t), n);
    if (t->kind == T_STRING && t->fixlen) buf_printf(d, "    %s = bb_str_fixlen(NULL, %d);\n", n, t->fixlen);
    if (t->kind == T_ARRAY && s->fixed_array) {
        Buf lb = {0, 0, 0}, ub = {0, 0, 0};
        int k;
        for (k = 0; k < s->ndims; k++) {
            buf_printf(&lb, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k]->cv.i);
            buf_printf(&ub, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k + 1]->cv.i);
        }
        buf_printf(d, "    %s = bb_arr_new(%s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}); %s->fixed = 1;\n",
                   n, vtname(t->elem), udt_desc_ref(t), s->ndims, lb.p, ub.p, n);
    }
}

/* initialisation of a local kept in the cleanup struct (zeroed by memset) */
static void local_init_struct(EC *e, Buf *d, Sym *s)
{
    Type *t = s->ty;
    char *n = sym_cname(e, s);
    if (t->kind == T_UDT) { buf_printf(d, "    bb_udt_init(&%s_desc, (void *)&%s);\n", udt_cname(t->udt), n); return; }
    if (t->kind == T_STRING && t->fixlen) buf_printf(d, "    %s = bb_str_fixlen(NULL, %d);\n", n, t->fixlen);
    if (t->kind == T_ARRAY && s->fixed_array) {
        Buf lb = {0, 0, 0}, ub = {0, 0, 0};
        int k;
        for (k = 0; k < s->ndims; k++) {
            buf_printf(&lb, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k]->cv.i);
            buf_printf(&ub, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k + 1]->cv.i);
        }
        buf_printf(d, "    %s = bb_arr_new(%s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}); %s->fixed = 1;\n",
                   n, vtname(t->elem), udt_desc_ref(t), s->ndims, lb.p, ub.p, n);
    }
}

static void emit_proc(EC *e, Proc *pr)
{
    Buf d = {0, 0, 0};
    int i;
    e->proc = pr;
    e->ntemp = 0;
    e->nloops = 0;
    e->handler = pr->has_onerror;
    e->resume = pr->has_onerror && pr->has_resume;
    e->nstmt = 0;
    e->ngosub = 0;
    e->line = -1;
    e->file = -1;
    Buf sinit = {0, 0, 0};
    buf_free(&e->body);
    buf_free(&e->decl);
    buf_free(&e->sdecl);
    buf_free(&e->sclean);
    buf_free(&e->stemp);
    e->nsmem = 0;
    e->pre.n = 0;
    e->rel.n = 0;
    e->indent = 1;
    /* refcounted locals live in a struct on the cleanup chain (released if an error unwinds) */
    for (i = 0; i < pr->nlocals; i++) {
        Sym *s = pr->locals[i];
        if (s->storage != ST_LOCAL || s->byref || !is_refty(s->ty)) continue;
        s->cname = struct_member(e, s->ty, sym_cname(e, s));
        local_init_struct(e, &sinit, s);
    }
    block(e, &pr->body);
    /* other locals (params are in the signature) */
    for (i = 0; i < pr->nlocals; i++) {
        Sym *s = pr->locals[i];
        if (s->storage == ST_PARAM) continue;
        if (s->storage == ST_LOCAL && !s->byref && is_refty(s->ty)) continue;
        local_init(e, &d, s, e->handler && !s->byref);
    }
    if (e->nsmem) {
        buf_printf(e->out, "\nstruct L%d {\n", pr->index);
        buf_put(e->out, e->sdecl.p, e->sdecl.n);
        buf_printf(e->out, "};\nstatic void cleanup%d(void *ctx)\n{\n    struct L%d *c = (struct L%d *)ctx;\n", pr->index, pr->index, pr->index);
        buf_put(e->out, e->sclean.p, e->sclean.n);
        buf_puts(e->out, "}\n");
        if (e->handler && e->stemp.n) {
            /* an error caught here: the failing statement's temporaries */
            buf_printf(e->out, "static void cleanup%d_t(struct L%d *c)\n{\n", pr->index, pr->index);
            buf_put(e->out, e->stemp.p, e->stemp.n);
            buf_puts(e->out, "}\n");
        }
    }
    buf_printf(e->out, "\n%s\n{\n", proc_sig(e, pr, 1));
    if (e->nsmem) {
        buf_printf(e->out, "    struct L%d bbL;\n    bb_cleanup bbC;\n", pr->index);
        buf_puts(e->out, "    memset((void *)&bbL, 0, sizeof bbL);\n");
    }
    buf_put(e->out, d.p ? d.p : "", d.n);
    buf_put(e->out, e->decl.p ? e->decl.p : "", e->decl.n);
    if (e->nsmem) {
        buf_put(e->out, sinit.p ? sinit.p : "", sinit.n);
        buf_printf(e->out, "    bbC.prev = bb_cleanups; bbC.fn = cleanup%d; bbC.ctx = (void *)&bbL; bb_cleanups = &bbC;\n", pr->index);
    }
    buf_free(&sinit);
    if (pr->has_gosub) buf_puts(e->out, "    int bb_gs[64]; int bb_gsp = 0;\n");
    if (e->handler) {
        buf_puts(e->out, "    bb_errframe bb_ef;\n    volatile int bb_mode = 0, bb_hlabel = -1, bb_inh = 0, bb_stmt = 0, bb_estmt = 0, bb_rs = 0;\n");
        buf_puts(e->out, "    (void)bb_estmt; (void)bb_rs;\n    bb_frame_push(&bb_ef);\n");
        buf_puts(e->out, "    if (BB_SETJMP(bb_ef.jb)) {\n");
        buf_puts(e->out, "        bb_errtop = &bb_ef;\n");
        if (e->nsmem && e->stemp.n) buf_printf(e->out, "        cleanup%d_t(&bbL);\n", pr->index);
        buf_puts(e->out, "        if (bb_mode == 0 || bb_inh) { bb_frame_pop(&bb_ef); bb_rethrow(); }\n");
        buf_puts(e->out, "        bb_estmt = bb_stmt;\n");
        if (e->resume) buf_puts(e->out, "        if (bb_mode == 2) { bb_rs = bb_estmt + 1; goto bb_resume; }\n");
        buf_puts(e->out, "        bb_inh = 1;\n        switch (bb_hlabel) {\n");
        for (i = 0; i < pr->nlabels; i++) buf_printf(e->out, "        case %d: goto bb_lab%d;\n", i, i);
        buf_puts(e->out, "        default: bb_frame_pop(&bb_ef); bb_rethrow();\n        }\n    }\n");
    }
    if (pr->mod) buf_printf(e->out, "    bb_file = bb_files[%d];\n", pr->mod->file);
    buf_puts(e->out, "    bb_enter();\n");
    buf_put(e->out, e->body.p ? e->body.p : "", e->body.n);
    if (e->resume) {
        int k;
        buf_printf(e->out, "    bb_S%d: ;\n", e->nstmt + 1);
        buf_puts(e->out, "    goto bb_exit;\nbb_resume:\n    switch (bb_rs) {\n");
        for (k = 1; k <= e->nstmt + 1; k++) buf_printf(e->out, "    case %d: goto bb_S%d;\n", k, k);
        buf_puts(e->out, "    default: goto bb_exit;\n    }\n");
    }
    if (pr->has_gosub) {
        buf_puts(e->out, "    goto bb_exit;\nbb_gsret:\n    if (bb_gsp <= 0) bb_raise(3, NULL);\n    switch (bb_gs[--bb_gsp]) {\n");
        for (i = 0; i < e->ngosub; i++) buf_printf(e->out, "    case %d: goto bb_R%d;\n", e->gosub_ids[i], e->gosub_ids[i]);
        buf_puts(e->out, "    }\n");
    }
    buf_puts(e->out, "bb_exit: ;\n");
    if (e->nsmem) buf_puts(e->out, "    bb_cleanups = bbC.prev;\n");
    if (e->handler) buf_puts(e->out, "    bb_frame_pop(&bb_ef);\n    if (bb_inh) bb_err_clear();\n");
    for (i = 0; i < pr->nlocals; i++) {
        Sym *s = pr->locals[i];
        char *r;
        if (s == pr->retvar) continue;
        if (s->byref) continue;
        r = release_code(s->ty, sym_cname(e, s));
        if (r) buf_printf(e->out, "    %s\n", r);
    }
    if (pr->retvar) {
        if (e->handler && pr->ret->kind == T_VARIANT) buf_printf(e->out, "    return *(bb_value *)&%s;\n", sym_cname(e, pr->retvar));
        else if (e->handler && pr->ret->kind == T_UDT) buf_printf(e->out, "    return *(%s *)&%s;\n", udt_cname(pr->ret->udt), sym_cname(e, pr->retvar));
        else buf_printf(e->out, "    return %s;\n", sym_cname(e, pr->retvar));
    }
    buf_puts(e->out, "}\n");
    buf_free(&d);
}

/* ---------- generic wrappers: call a proc with Variant arguments ---------- */

static char *from_variant(Type *t, const char *p)
{
    switch (t->kind) {
    case T_BOOLEAN: return xsprintf("bb_v_to_bool(%s)", p);
    case T_BYTE: return xsprintf("bb_v_to_byte(%s)", p);
    case T_INTEGER: return xsprintf("bb_v_to_int(%s)", p);
    case T_LONG: return xsprintf("bb_v_to_long(%s)", p);
    case T_SINGLE: return xsprintf("bb_v_to_single(%s)", p);
    case T_DOUBLE: return xsprintf("bb_v_to_double(%s)", p);
    case T_CURRENCY: return xsprintf("bb_v_to_cur(%s)", p);
    case T_DATE: return xsprintf("bb_v_to_date(%s)", p);
    case T_STRING: return xsprintf("bb_v_to_str(%s)", p);
    case T_OBJECT: return xsprintf("bb_v_to_obj(%s)", p);
    case T_ARRAY: return xsprintf("bb_v_to_array(%s, %s)", p, vtname(t->elem));
    default: return xsprintf("bb_v_dup(bb_v_deref(%s, &bb_vtmp))", p);
    }
}

static char *to_variant(Type *t, const char *x)
{
    switch (t->kind) {
    case T_BOOLEAN: return xsprintf("bb_v_bool(%s)", x);
    case T_BYTE: return xsprintf("bb_v_byte(%s)", x);
    case T_INTEGER: return xsprintf("bb_v_int(%s)", x);
    case T_LONG: return xsprintf("bb_v_long(%s)", x);
    case T_SINGLE: return xsprintf("bb_v_single(%s)", x);
    case T_DOUBLE: return xsprintf("bb_v_double(%s)", x);
    case T_CURRENCY: return xsprintf("bb_v_cur(%s)", x);
    case T_DATE: return xsprintf("bb_v_date(%s)", x);
    case T_STRING: return xsprintf("bb_v_str(%s)", x);
    case T_OBJECT: return xsprintf("bb_v_obj(%s)", x);
    case T_ARRAY: return xsprintf("bb_v_arr(%s)", x);
    default: return xstrdup(x);
    }
}

static char *default_c(EC *e, Param *pa)
{
    Node tmp;
    if (!pa->optional) return xstrdup("(bb_raise(449, NULL), 0)");
    if (pa->has_def) {
        memset(&tmp, 0, sizeof tmp);
        tmp.kind = E_CONST;
        tmp.cv = pa->def;
        tmp.ty = type_prim(pa->def.type);
        if (pa->def.is_null || pa->def.is_empty) return xstrdup(pa->def.is_null ? "bb_v_null()" : "bb_v_empty()");
        if (pa->def.type == T_STRING) return xsprintf("bb_str_retain(%s)", const_expr(e, &tmp));
        if (pa->ty->kind == T_VARIANT) return to_variant(type_prim(pa->def.type), const_expr(e, &tmp));
        return const_expr(e, &tmp);
    }
    if (pa->ty->kind == T_VARIANT) return xstrdup("bb_v_missing()");
    if (pa->ty->kind == T_STRING || pa->ty->kind == T_OBJECT || pa->ty->kind == T_ARRAY) return xstrdup("NULL");
    return xstrdup("0");
}

static void emit_wrapper(EC *e, Proc *pr)
{
    Buf *o = e->out;
    int i;
    buf_printf(o, "\nstatic void w%d(bb_obj *self, int argc, bb_value *argv, bb_value *ret)\n{\n", pr->index);
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        Type *t = pa->ty;
        const char *ct = t->kind == T_UDT ? udt_cname(t->udt) : ctype(t);
        if (t->kind == T_UDT) buf_printf(o, "    %s *a%d = NULL;\n", ct, i);
        else {
            buf_printf(o, "    %s v%d = %s;\n", ct, i, zero_init(t));
            if (pa->byref) buf_printf(o, "    %s *a%d = &v%d;\n", ct, i, i);
        }
    }
    buf_printf(o, "    (void)self; (void)ret;\n    if (argc > %d) bb_raise(450, NULL);\n", pr->nparams);
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        Type *t = pa->ty;
        buf_printf(o, "    if (argc > %d && !(argv[%d].type == BB_ERROR && (argv[%d].flags & BB_VF_MISSING) && %d)) {\n", i, i, i, t->kind != T_VARIANT);
        if (pa->byref) {
            if (t->kind == T_UDT)
                buf_printf(o, "        if (argv[%d].type == (BB_REF | BB_UDT)) a%d = (%s *)argv[%d].u.p; else bb_raise(13, NULL);\n", i, i, udt_cname(t->udt), i);
            else {
                buf_printf(o, "        if (argv[%d].type == (BB_REF | %s)) a%d = (%s *)argv[%d].u.p;\n", i, vtname(t), i, ctype(t), i);
                buf_printf(o, "        else v%d = %s;\n", i, from_variant(t, xsprintf("&argv[%d]", i)));
            }
        } else buf_printf(o, "        v%d = %s;\n", i, from_variant(t, xsprintf("&argv[%d]", i)));
        if (t->kind == T_UDT || !pa->optional) buf_puts(o, "    } else bb_raise(449, NULL);\n");
        else buf_printf(o, "    } else v%d = %s;\n", i, default_c(e, pa));
    }
    {
        Buf call = {0, 0, 0};
        buf_printf(&call, "%s(", proc_cname(pr));
        if (pr->cls) buf_puts(&call, "self");
        for (i = 0; i < pr->nparams; i++)
            buf_printf(&call, "%s%s%d", (i || pr->cls) ? ", " : "", pr->params[i].byref ? "a" : "v", i);
        buf_puts(&call, ")");
        if (pr->ret && pr->ret->kind != T_UDT) buf_printf(o, "    *ret = %s;\n", to_variant(pr->ret, call.p));
        else if (pr->ret) buf_printf(o, "    { %s r = %s; bb_udt_clear(&%s_desc, &r); bb_raise(458, NULL); }\n", udt_cname(pr->ret->udt), call.p, udt_cname(pr->ret->udt));
        else buf_printf(o, "    %s;\n", call.p);
    }
    /* ByRef through a reference of another type (an event's Long for an Integer
     * parameter): copy the value back, as VB does for ByRef Variants */
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        Type *t = pa->ty;
        char *cp;
        if (!pa->byref || t->kind == T_UDT || t->kind == T_ARRAY) continue;
        switch (t->kind) {
        case T_STRING: cp = xsprintf("bb_v_str(bb_str_retain(v%d))", i); break;
        case T_OBJECT: cp = xsprintf("bb_v_obj(bb_obj_retain(v%d))", i); break;
        case T_VARIANT: cp = xsprintf("bb_v_dup(&v%d)", i); break;
        default: cp = to_variant(t, xsprintf("v%d", i));
        }
        buf_printf(o, "    if (argc > %d && (argv[%d].type & BB_REF) && a%d == &v%d) { bb_value cb = %s; bb_v_store_ref(&argv[%d], &cb); bb_v_release(&cb); }\n",
                   i, i, i, i, cp, i);
    }
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        char *r;
        if (pa->ty->kind == T_UDT) continue;
        if (!pa->byref && is_refty(pa->ty)) continue;   /* the callee released it */
        r = release_code(pa->ty, xsprintf("v%d", i));
        if (r) buf_printf(o, "    %s\n", r);
    }
    buf_puts(o, "}\n");
}

/* ---------- declarations ---------- */

static void emit_udts(EC *e)
{
    Program *p = e->p;
    int i, j, done = 0;
    int *emitted = (int *)xcalloc((size_t)p->nudts + 1, sizeof(int));
    for (i = 0; i < p->nudts; i++) buf_printf(e->out, "typedef struct %s %s;\n", udt_cname(p->udts[i]), udt_cname(p->udts[i]));
    /* structs in dependency order */
    while (done < p->nudts) {
        int progress = 0;
        for (i = 0; i < p->nudts; i++) {
            Udt *u = p->udts[i];
            int ok = 1;
            if (emitted[i]) continue;
            for (j = 0; j < u->nfields; j++)
                if (u->fields[j].ty->kind == T_UDT && !emitted[u->fields[j].ty->udt->index]) ok = 0;
            if (!ok) continue;
            buf_printf(e->out, "struct %s {\n", udt_cname(u));
            for (j = 0; j < u->nfields; j++) {
                UField *f = &u->fields[j];
                buf_printf(e->out, "    %s f_%s;\n", f->ty->kind == T_UDT ? udt_cname(f->ty->udt) : ctype(f->ty), cident(f->name));
            }
            if (!u->nfields) buf_puts(e->out, "    int dummy_;\n");
            buf_puts(e->out, "};\n");
            emitted[i] = 1;
            done++;
            progress = 1;
        }
        if (!progress) break;
    }
    for (i = 0; i < p->nudts; i++) buf_printf(e->out, "static const bb_udt_desc %s_desc;\n", udt_cname(p->udts[i]));
    for (i = 0; i < p->nudts; i++) {
        Udt *u = p->udts[i];
        char *cn = udt_cname(u);
        buf_printf(e->out, "static const bb_field %s_fields[] = {\n", cn);
        for (j = 0; j < u->nfields; j++) {
            UField *f = &u->fields[j];
            Type *ft = f->ty;
            int k;
            Buf lb = {0, 0, 0}, ub = {0, 0, 0};
            for (k = 0; k < 8; k++) {
                buf_printf(&lb, "%s%d", k ? ", " : "", k < f->ndims ? f->lb[k] : 0);
                buf_printf(&ub, "%s%d", k ? ", " : "", k < f->ndims ? f->ub[k] : 0);
            }
            buf_printf(e->out, "    {\"%s\", %s, %d, offsetof(%s, f_%s), %s, %d, {%s}, {%s}},\n", f->name, vtname(ft), f->fixlen,
                       cn, cident(f->name), udt_desc_ref(ft), f->ndims, lb.p, ub.p);
        }
        if (!u->nfields) buf_puts(e->out, "    {\"\", 0, 0, 0, NULL, 0, {0}, {0}}\n");
        buf_puts(e->out, "};\n");
        buf_printf(e->out, "static const bb_udt_desc %s_desc = {\"%s\", sizeof(%s), %d, %s_fields};\n", cn, u->name, cn, u->nfields, cn);
    }
    free(emitted);
}

static void emit_class_decls(EC *e)
{
    Program *p = e->p;
    int i, j;
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        char *cn = cls_cname(c);
        buf_printf(e->out, "typedef struct %s {\n    bb_obj hdr;\n", cn);
        for (j = 0; j < c->nfields; j++) {
            Sym *f = c->fields[j];
            Type *t = f->ty;
            buf_printf(e->out, "    %s %s;\n", t->kind == T_UDT ? udt_cname(t->udt) : ctype(t), sym_cname(e, f));
            if (f->withevents) buf_printf(e->out, "    bb_wevconn wev_%s;\n", cident(f->name));
        }
        buf_printf(e->out, "} %s;\n", cn);
        buf_printf(e->out, "static bb_class %s_class;\n", cn);
        buf_printf(e->out, "static bb_obj *%s_new(void);\n", cn);
    }
}

static void emit_vtbl_types(EC *e)
{
    Program *p = e->p;
    int i, j;
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        if (!c->is_interface) continue;
        buf_printf(e->out, "struct V%d {\n", c->index);
        for (j = 0; j < c->nvtbl; j++) {
            Proc *pr = c->vtbl[j];
            char *sig = proc_sig(e, pr, 0);
            /* "static R (params)" -> "R (*mN)(params)" */
            char *paren = strchr(sig, '(');
            const char *rt = pr->ret ? (pr->ret->kind == T_UDT ? udt_cname(pr->ret->udt) : ctype(pr->ret)) : "void";
            buf_printf(e->out, "    %s (*m%d)%s;\n", rt, j, paren ? paren : "(void)");
        }
        if (!c->nvtbl) buf_puts(e->out, "    void (*m0)(void);\n");
        buf_puts(e->out, "};\n");
    }
}

static void emit_class_impl(EC *e)
{
    Program *p = e->p;
    int i, j, k;
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        char *cn = cls_cname(c);
        int nmem = 0;
        /* member table */
        typedef struct M { const char *name; int field; Proc *method, *pget, *plet, *pset; } M;
        M *mems = (M *)xcalloc((size_t)(c->nfields + c->nmethods) + 1, sizeof(M));
        for (j = 0; j < c->nfields; j++) {
            if (!c->fields[j]->is_public) continue;
            mems[nmem].name = c->fields[j]->name;
            mems[nmem].field = j;
            nmem++;
        }
        for (j = 0; j < c->nmethods; j++) {
            Proc *pr = c->methods[j];
            M *m = NULL;
            if (!pr->is_public) continue;
            for (k = 0; k < nmem; k++) if (name_eq(mems[k].name, pr->name)) m = &mems[k];
            if (!m) { m = &mems[nmem++]; m->name = pr->name; m->field = -1; }
            switch (pr->kind) {
            case PK_PGET: m->pget = pr; break;
            case PK_PLET: m->plet = pr; break;
            case PK_PSET: m->pset = pr; break;
            default: m->method = pr;
            }
        }
        for (j = 0; j < nmem; j++) if (mems[j].field < 0) {
            /* nothing */
        }
        /* find */
        buf_printf(e->out, "\nstatic int32_t %s_find(const bb_class *cls, const char *name)\n{\n", cn);
        buf_puts(e->out, "    static const char *const names[] = {");
        for (j = 0; j < nmem; j++) buf_printf(e->out, "%s\"%s\"", j ? ", " : "", mems[j].name);
        if (!nmem) buf_puts(e->out, "NULL");
        buf_puts(e->out, "};\n    int32_t i;\n    (void)cls;\n");
        buf_printf(e->out, "    if (!name || !*name) {\n        for (i = 0; i < %d; i++) if (!strcasecmp(names[i], \"Item\") || !strcasecmp(names[i], \"Value\")) return i;\n        return BB_NOMEMBER;\n    }\n", nmem);
        buf_printf(e->out, "    for (i = 0; i < %d; i++) if (!strcasecmp(names[i], name)) return i;\n    return BB_NOMEMBER;\n}\n", nmem);
        /* invoke */
        buf_printf(e->out, "static void %s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)\n{\n", cn);
        buf_printf(e->out, "    %s *o = (%s *)self;\n    (void)o;\n    switch (id) {\n", cn, cn);
        for (j = 0; j < nmem; j++) {
            M *m = &mems[j];
            buf_printf(e->out, "    case %d:\n", j);
            if (m->field >= 0) {
                Sym *f = c->fields[m->field];
                Type *t = f->ty;
                char *fl = xsprintf("o->%s", sym_cname(e, f));
                if (t->kind == T_UDT) { buf_puts(e->out, "        bb_raise(458, NULL);\n"); continue; }
                buf_puts(e->out, "        if (kind & (BB_INV_LET | BB_INV_SET)) {\n");
                buf_printf(e->out, "            bb_value r = bb_v_ref(%s, &%s);\n            if (argc != 1) bb_raise(450, NULL);\n            bb_v_store_ref(&r, &argv[0]);\n", vtname(t), fl);
                if (t->kind == T_STRING && t->fixlen) buf_printf(e->out, "            bb_str_set(&%s, bb_str_fixlen(%s, %d));\n", fl, fl, t->fixlen);
                buf_puts(e->out, "            return;\n        }\n");
                if (t->kind == T_ARRAY) buf_printf(e->out, "        if (argc) { bb_value v = bb_v_arr(NULL); v.u.a = %s; *ret = bb_v_index(&v, argc, argv); return; }\n", fl);
                else if (t->kind == T_VARIANT || t->kind == T_OBJECT) buf_printf(e->out, "        if (argc) { bb_value v = %s; *ret = bb_v_index(&v, argc, argv); return; }\n", t->kind == T_VARIANT ? fl : xsprintf("bb_v_obj(%s)", fl));
                buf_printf(e->out, "        *ret = bb_elem_load(%s, &%s);\n        return;\n", vtname(t), fl);
            } else {
                if (m->plet) buf_printf(e->out, "        if (kind & BB_INV_LET) { w%d(self, argc, argv, ret); return; }\n", m->plet->index);
                if (m->pset) buf_printf(e->out, "        if (kind & BB_INV_SET) { w%d(self, argc, argv, ret); return; }\n", m->pset->index);
                else if (m->plet) buf_printf(e->out, "        if (kind & BB_INV_SET) { w%d(self, argc, argv, ret); return; }\n", m->plet->index);
                if (m->method) buf_printf(e->out, "        if (kind & (BB_INV_METHOD | BB_INV_GET)) { w%d(self, argc, argv, ret); return; }\n", m->method->index);
                if (m->pget) buf_printf(e->out, "        if (kind & (BB_INV_METHOD | BB_INV_GET)) { w%d(self, argc, argv, ret); return; }\n", m->pget->index);
                buf_puts(e->out, "        break;\n");
            }
        }
        buf_puts(e->out, "    default: break;\n    }\n    bb_raise(438, NULL);\n}\n");
        /* terminate */
        buf_printf(e->out, "static void %s_terminate(bb_obj *self)\n{\n    %s *o = (%s *)self;\n", cn, cn, cn);
        if (c->term) buf_printf(e->out, "    %s(self);\n", proc_cname(c->term));
        for (j = 0; j < c->nfields; j++) {
            Sym *f = c->fields[j];
            char *r;
            if (f->withevents) buf_printf(e->out, "    bb_wev_disconnect(&o->wev_%s);\n", cident(f->name));
            r = release_code(f->ty, xsprintf("o->%s", sym_cname(e, f)));
            if (r) buf_printf(e->out, "    %s\n", r);
        }
        buf_puts(e->out, "    (void)o;\n}\n");
        /* vtables */
        if (c->is_interface) {
            buf_printf(e->out, "static const struct V%d %s_vtbl = {", c->index, cn);
            for (j = 0; j < c->nvtbl; j++) buf_printf(e->out, "%s%s", j ? ", " : "", proc_cname(c->vtbl[j]));
            if (!c->nvtbl) buf_puts(e->out, "NULL");
            buf_puts(e->out, "};\n");
        }
        for (j = 0; j < c->nimpls; j++) {
            ClassInfo *I = c->impls[j];
            buf_printf(e->out, "static const struct V%d %s_as_%d = {", I->index, cn, I->index);
            for (k = 0; k < I->nvtbl; k++) {
                int m;
                Proc *impl = NULL;
                for (m = 0; m < c->nmethods; m++) if (c->methods[m]->impl_of == I->vtbl[k]) impl = c->methods[m];
                buf_printf(e->out, "%s%s", k ? ", " : "", impl ? proc_cname(impl) : "NULL");
            }
            if (!I->nvtbl) buf_puts(e->out, "NULL");
            buf_puts(e->out, "};\n");
        }
        if (c->nimpls) {
            buf_printf(e->out, "static const bb_iface %s_ifaces[] = {", cn);
            for (j = 0; j < c->nimpls; j++) buf_printf(e->out, "%s{&%s_class, &%s_as_%d}", j ? ", " : "", cls_cname(c->impls[j]), cn, c->impls[j]->index);
            buf_puts(e->out, "};\n");
        }
        buf_printf(e->out, "static bb_class %s_class = {\"%s\", sizeof(%s), %s_find, %s_invoke, %s_terminate, NULL, NULL, 0, %s, %d, %s, NULL};\n",
                   cn, c->name, cn, cn, cn, cn, c->nimpls ? xsprintf("%s_ifaces", cn) : "NULL", c->nimpls,
                   c->is_interface ? xsprintf("&%s_vtbl", cn) : "NULL");
        /* constructor */
        buf_printf(e->out, "static BB_UNUSED bb_obj *%s_new(void)\n{\n    %s *o = (%s *)bb_obj_new(&%s_class);\n", cn, cn, cn, cn);
        for (j = 0; j < c->nfields; j++) {
            Sym *f = c->fields[j];
            Type *t = f->ty;
            char *fl = xsprintf("o->%s", sym_cname(e, f));
            if (t->kind == T_UDT) buf_printf(e->out, "    bb_udt_init(&%s_desc, &%s);\n", udt_cname(t->udt), fl);
            if (t->kind == T_STRING && t->fixlen) buf_printf(e->out, "    %s = bb_str_fixlen(NULL, %d);\n", fl, t->fixlen);
            if (t->kind == T_ARRAY && f->fixed_array) {
                Buf lb = {0, 0, 0}, ub = {0, 0, 0};
                for (k = 0; k < f->ndims; k++) {
                    buf_printf(&lb, "%s%lld", k ? ", " : "", (long long)f->bounds.v[2 * k]->cv.i);
                    buf_printf(&ub, "%s%lld", k ? ", " : "", (long long)f->bounds.v[2 * k + 1]->cv.i);
                }
                buf_printf(e->out, "    %s = bb_arr_new(%s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}); %s->fixed = 1;\n",
                           fl, vtname(t->elem), udt_desc_ref(t), f->ndims, lb.p, ub.p, fl);
            }
        }
        if (c->init) buf_printf(e->out, "    %s(&o->hdr);\n", proc_cname(c->init));
        buf_puts(e->out, "    return &o->hdr;\n}\n");
        free(mems);
    }
}

static void emit_fire(EC *e, Sym *v, const char *name, const char *ctx_cls)
{
    ClassInfo *src = v->ty->cls;
    Module *m = v->mod;
    int k, j;
    buf_printf(e->out, "\nstatic void %s(bb_sink *s, int32_t ev, const char *name, int argc, bb_value *argv)\n{\n", name);
    buf_puts(e->out, "    bb_value r = {0, 0, 0, {0}};\n    (void)name; (void)s;\n    switch (ev) {\n");
    for (k = 0; k < src->nevents; k++) {
        char *hn = xsprintf("%s_%s", v->name, src->events[k]->name);
        Proc *h = NULL;
        for (j = 0; j < m->nprocs; j++) if (name_eq(m->procs[j]->name, hn) && m->procs[j]->kind == PK_SUB) h = m->procs[j];
        if (h) buf_printf(e->out, "    case %d: w%d(%s, argc, argv, &r); break;\n", k, h->index, ctx_cls ? "(bb_obj *)s->ctx" : "NULL");
    }
    buf_puts(e->out, "    default: break;\n    }\n    bb_v_release(&r);\n}\n");
}

int emit_c(Program *p, Buf *outb, int debug)
{
    EC ex, *e = &ex;
    int i, j;
    memset(e, 0, sizeof ex);
    e->p = p;
    e->out = outb;
    e->debug = debug;
    e->multi_file = p->nmods > 1;
    nlits = 0;
    buf_puts(outb, "/* Generated by Boing BASIC (boing build). Do not edit. */\n");
    buf_puts(outb, "#include \"boing.h\"\n#include <string.h>\n#include <strings.h>\n#include <stddef.h>\n#include <math.h>\n\n");
    buf_puts(outb, "static bb_value bb_vk_empty BB_UNUSED, bb_vk_null BB_UNUSED, bb_vk_missing BB_UNUSED, bb_vtmp BB_UNUSED;\n");
    buf_puts(outb, "static bb_str *bb_k_empty BB_UNUSED;\n");
    buf_printf(outb, "static const char *const bb_files[] = {");
    for (i = 0; i < p->nfiles; i++) buf_printf(outb, "%s%s", i ? ", " : "", cstrlit(p->files[i], (int)strlen(p->files[i])));
    buf_puts(outb, "};\n");
    buf_puts(outb, "#define BB_LITS_PLACEHOLDER\n");
    emit_udts(e);
    emit_class_decls(e);
    emit_vtbl_types(e);
    /* globals */
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        Type *t = s->ty;
        buf_printf(outb, "static %s %s%s;\n", t->kind == T_UDT ? udt_cname(t->udt) : ctype(t), sym_cname(e, s),
                   t->kind == T_VARIANT ? " = {0, 0, 0, {0}}" : "");
        if (s->withevents) buf_printf(outb, "static bb_wevconn wevg%d;\n", s->index);
    }
    /* declares */
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind != PK_DECLARE) continue;
        buf_printf(outb, "static bb_declare bb_decl%d = {\"%s\", %s, %s, %s, %d, %d, NULL};\n", pr->index, pr->name,
                   cstrlit(pr->lib, (int)strlen(pr->lib)), cstrlit(pr->alias, (int)strlen(pr->alias)),
                   cstrlit(pr->iface, (int)strlen(pr->iface)), pr->version, pr->nparams);
    }
    /* prototypes */
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT) continue;
        buf_printf(outb, "%s;\n", proc_sig(e, pr, 0) ? xsprintf("%s", proc_sig(e, pr, 1)) : "");
        buf_printf(outb, "static BB_UNUSED void w%d(bb_obj *self, int argc, bb_value *argv, bb_value *ret);\n", pr->index);
    }
    /* WithEvents fire functions */
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        if (s->withevents) emit_fire(e, s, xsprintf("wev_fireg%d", s->index), NULL);
    }
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        for (j = 0; j < c->nfields; j++)
            if (c->fields[j]->withevents) emit_fire(e, c->fields[j], xsprintf("wev_fire_%d_%s", c->index, cident(c->fields[j]->name)), cls_cname(c));
    }
    /* bodies */
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT) continue;
        emit_proc(e, pr);
    }
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT) continue;
        emit_wrapper(e, pr);
    }
    emit_class_impl(e);
    /* program ops */
    buf_puts(outb, "\nstatic const struct { const char *mod, *name; void (*w)(bb_obj *, int, bb_value *, bb_value *); } bb_procs[] = {\n");
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT || pr->kind == PK_MAIN || pr->cls) continue;
        buf_printf(outb, "    {\"%s\", \"%s\", w%d},\n", pr->mod->name, pr->name, pr->index);
    }
    buf_puts(outb, "    {NULL, NULL, NULL}\n};\n");
    buf_puts(outb, "static const struct { const char *mod, *name; int type; void *p; } bb_globs[] = {\n");
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        if (s->storage != ST_GLOBAL || s->ty->kind == T_UDT) continue;
        buf_printf(outb, "    {\"%s\", \"%s\", %s, (void *)&%s},\n", s->mod->name, s->name, vtname(s->ty), sym_cname(e, s));
    }
    buf_puts(outb, "    {NULL, NULL, 0, NULL}\n};\n");
    buf_puts(outb,
             "static void *bb_find_proc_(const char *mod, const char *name)\n{\n    int i;\n"
             "    for (i = 0; bb_procs[i].name; i++)\n"
             "        if (!strcasecmp(bb_procs[i].name, name) && (!mod || !strcasecmp(bb_procs[i].mod, mod))) return (void *)&bb_procs[i];\n"
             "    return NULL;\n}\n"
             "static void bb_call_proc_(void *proc, int argc, bb_value *argv, bb_value *ret)\n{\n"
             "    ((const struct { const char *mod, *name; void (*w)(bb_obj *, int, bb_value *, bb_value *); } *)proc)->w(NULL, argc, argv, ret);\n}\n"
             "static void *bb_find_global_(const char *mod, const char *name, int *type)\n{\n    int i;\n"
             "    for (i = 0; bb_globs[i].name; i++)\n"
             "        if (!strcasecmp(bb_globs[i].name, name) && (!mod || !strcasecmp(bb_globs[i].mod, mod))) { *type = bb_globs[i].type; return bb_globs[i].p; }\n"
             "    return NULL;\n}\n"
             "static const bb_program_ops bb_ops = {bb_find_proc_, bb_call_proc_, bb_find_global_};\n");
    /* the project's stack size (Stack= in the .bbp); this object comes before libboing,
       so the OS4 loader finds this cookie before the library's default */
    buf_printf(outb, "\n#ifdef __amigaos4__\nstatic const char __attribute__((used)) bb_stack_cookie_[] = \"$STACK:%d\";\n#endif\n",
               e->p->stack > 0 ? e->p->stack : 262144);
    /* main */
    buf_puts(outb, "\nint main(int argc, char **argv)\n{\n    int i;\n    bb_rt_init(argc, argv);\n    bb_set_program(&bb_ops);\n");
    buf_puts(outb, "    bb_vk_null.type = BB_NULL;\n    bb_vk_missing = bb_v_missing();\n");
    buf_printf(outb, "    for (i = 0; i < %d; i++) bb_k[i] = bb_str_lit(bb_klit[i], bb_klen[i]);\n", nlits);
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        Type *t = s->ty;
        char *n = sym_cname(e, s);
        if (t->kind == T_UDT) buf_printf(outb, "    bb_udt_init(&%s_desc, &%s);\n", udt_cname(t->udt), n);
        if (t->kind == T_STRING && t->fixlen) buf_printf(outb, "    %s = bb_str_fixlen(NULL, %d);\n", n, t->fixlen);
        if (t->kind == T_ARRAY && s->fixed_array) {
            Buf lb = {0, 0, 0}, ub = {0, 0, 0};
            int k;
            for (k = 0; k < s->ndims; k++) {
                buf_printf(&lb, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k]->cv.i);
                buf_printf(&ub, "%s%lld", k ? ", " : "", (long long)s->bounds.v[2 * k + 1]->cv.i);
            }
            buf_printf(outb, "    %s = bb_arr_new(%s, %s, %d, (const int32_t[]){%s}, (const int32_t[]){%s}); %s->fixed = 1;\n",
                       n, vtname(t->elem), udt_desc_ref(t), s->ndims, lb.p, ub.p, n);
        }
    }
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        char *text;
        if (!m->is_form) continue;
        text = read_file(m->afg_path, NULL);
        if (!text) { diag(p, m->file, 1, 1, "cannot read form file '%s'", m->afg_path); continue; }
        buf_printf(outb, "    bb_forms_register(%s, %s, %s, %s);\n", cstrlit(m->name, (int)strlen(m->name)),
                   cstrlit(m->form_name, (int)strlen(m->form_name)), cstrlit(text, (int)strlen(text)),
                   cstrlit(m->afg_path, (int)strlen(m->afg_path)));
        free(text);
    }
    if (p->startup && p->startup->is_form && !p->startup_proc)
        buf_printf(outb, "    bb_forms_main(%s);\n", cstrlit(p->startup->name, (int)strlen(p->startup->name)));
    else if (p->startup_proc) buf_printf(outb, "    %s();\n", proc_cname(p->startup_proc));
    buf_puts(outb, "    bb_rt_shutdown();\n    return 0;\n}\n");
    /* literal table: insert at the placeholder */
    {
        Buf l = {0, 0, 0};
        char *pos;
        buf_printf(&l, "static bb_str *bb_k[%d];\nstatic const char *const bb_klit[%d] = {", nlits ? nlits : 1, nlits ? nlits : 1);
        for (i = 0; i < nlits; i++) buf_printf(&l, "%s%s", i ? ", " : "", cstrlit(lits[i], litlens[i]));
        if (!nlits) buf_puts(&l, "\"\"");
        buf_printf(&l, "};\nstatic const int32_t bb_klen[%d] = {", nlits ? nlits : 1);
        for (i = 0; i < nlits; i++) buf_printf(&l, "%s%d", i ? ", " : "", litlens[i]);
        if (!nlits) buf_puts(&l, "0");
        buf_puts(&l, "};\n");
        pos = strstr(outb->p, "#define BB_LITS_PLACEHOLDER\n");
        if (pos) {
            size_t off = (size_t)(pos - outb->p), plen = strlen("#define BB_LITS_PLACEHOLDER\n");
            Buf nb = {0, 0, 0};
            buf_put(&nb, outb->p, off);
            buf_put(&nb, l.p, l.n);
            buf_put(&nb, outb->p + off + plen, outb->n - off - plen);
            buf_free(outb);
            *outb = nb;
        }
        buf_free(&l);
    }
    return p->nerrors == 0;
}
