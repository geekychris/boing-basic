/* util.c - memory, buffers, diagnostics, scopes, types */
#include "bbc.h"
#include "../runtime/boing.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <ctype.h>

void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p) { fprintf(stderr, "boing: out of memory\n"); exit(20); }
    return p;
}
void *xcalloc(size_t n, size_t m)
{
    void *p = calloc(n ? n : 1, m ? m : 1);
    if (!p) { fprintf(stderr, "boing: out of memory\n"); exit(20); }
    return p;
}
void *xrealloc(void *p, size_t n)
{
    p = realloc(p, n ? n : 1);
    if (!p) { fprintf(stderr, "boing: out of memory\n"); exit(20); }
    return p;
}
char *xstrdup(const char *s) { return xstrndup(s, strlen(s)); }
char *xstrndup(const char *s, size_t n)
{
    char *p = (char *)xmalloc(n + 1);
    memcpy(p, s, n);
    p[n] = 0;
    return p;
}
char *xsprintf(const char *fmt, ...)
{
    va_list ap;
    int n;
    char *p;
    va_start(ap, fmt);
    n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    p = (char *)xmalloc((size_t)n + 1);
    va_start(ap, fmt);
    vsnprintf(p, (size_t)n + 1, fmt, ap);
    va_end(ap);
    return p;
}
int name_eq(const char *a, const char *b) { return strcasecmp(a, b) == 0; }
char *str_lower(const char *s)
{
    char *p = xstrdup(s), *q;
    for (q = p; *q; q++) *q = (char)tolower((unsigned char)*q);
    return p;
}

void nl_push(NodeList *l, Node *n)
{
    if (l->n == l->cap) {
        l->cap = l->cap ? l->cap * 2 : 4;
        l->v = (Node **)xrealloc(l->v, sizeof(Node *) * (size_t)l->cap);
    }
    l->v[l->n++] = n;
}

void buf_put(Buf *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2 + 256;
        b->p = (char *)xrealloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = 0;
}
void buf_puts(Buf *b, const char *s) { buf_put(b, s, strlen(s)); }
void buf_printf(Buf *b, const char *fmt, ...)
{
    va_list ap;
    char tmp[512];
    int n;
    va_start(ap, fmt);
    n = vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    if (n < (int)sizeof tmp) { buf_put(b, tmp, (size_t)n); return; }
    {
        char *p = (char *)xmalloc((size_t)n + 1);
        va_start(ap, fmt);
        vsnprintf(p, (size_t)n + 1, fmt, ap);
        va_end(ap);
        buf_put(b, p, (size_t)n);
        free(p);
    }
}
/* VB passes variables to late-bound calls by reference (the callee's ByRef parameters
   change them): the variable under the Variant conversion, unless parenthesised */
Node *late_byref_var(Node *x)
{
    Node *v = x;
    if (v->flags & NF_PARENARG) return NULL;
    if (v->kind == E_CONV && v->ty->kind == T_VARIANT) v = v->a;
    if (v->kind != E_VAR || (v->flags & NF_PARENARG)) return NULL;
    switch (v->ty->kind) {
    case T_ARRAY: case T_UDT: case T_ANY: return NULL;
    default: break;
    }
    if (v->sym->kind != SK_VAR) return NULL;
    return v;
}

void buf_free(Buf *b) { free(b->p); b->p = NULL; b->n = b->cap = 0; }

const char *file_name(Program *p, int file)
{
    return file >= 0 && file < p->nfiles ? p->files[file] : "?";
}

static void vdiag(Program *p, const char *kind, int file, int line, int col, const char *fmt, va_list ap)
{
    char msg[1024];
    vsnprintf(msg, sizeof msg, fmt, ap);
    if (p->diag_buf) buf_printf(p->diag_buf, "%s:%d:%d: %s: %s\n", file_name(p, file), line, col, kind, msg);
    else fprintf(p->diag_out ? p->diag_out : stderr, "%s:%d:%d: %s: %s\n", file_name(p, file), line, col, kind, msg);
}

void diag(Program *p, int file, int line, int col, const char *fmt, ...)
{
    va_list ap;
    p->nerrors++;
    if (p->nerrors > p->max_errors) return;
    va_start(ap, fmt);
    vdiag(p, "error", file, line, col, fmt, ap);
    va_end(ap);
}

void diag_warn(Program *p, int file, int line, int col, const char *fmt, ...)
{
    va_list ap;
    p->nwarnings++;
    va_start(ap, fmt);
    vdiag(p, "warning", file, line, col, fmt, ap);
    va_end(ap);
}

Node *node_new(int kind, int file, int line, int col)
{
    Node *n = (Node *)xcalloc(1, sizeof(Node));
    n->kind = kind;
    n->file = file;
    n->line = line;
    n->col = col;
    return n;
}

/* ---------- scopes ---------- */

static unsigned hash_name(const char *s)
{
    unsigned h = 2166136261u;
    for (; *s; s++) h = (h ^ (unsigned)tolower((unsigned char)*s)) * 16777619u;
    return h;
}

Scope *scope_new(Scope *parent)
{
    Scope *s = (Scope *)xcalloc(1, sizeof(Scope));
    s->parent = parent;
    s->cap = 16;
    s->tab = (ScopeEnt **)xcalloc((size_t)s->cap, sizeof(ScopeEnt *));
    return s;
}

Sym *scope_find_local(Scope *s, const char *name)
{
    ScopeEnt *e;
    for (e = s->tab[hash_name(name) & (unsigned)(s->cap - 1)]; e; e = e->next)
        if (name_eq(e->sym->name, name)) return e->sym;
    return NULL;
}

Sym *scope_find(Scope *s, const char *name)
{
    for (; s; s = s->parent) {
        Sym *e = scope_find_local(s, name);
        if (e) return e;
    }
    return NULL;
}

/* a symbol may be in several scopes (module and global): entries are separate */
void scope_add(Scope *s, Sym *sym)
{
    unsigned h;
    ScopeEnt *n;
    if (s->n * 2 >= s->cap) {
        int oc = s->cap, i;
        ScopeEnt **old = s->tab;
        s->cap *= 2;
        s->tab = (ScopeEnt **)xcalloc((size_t)s->cap, sizeof(ScopeEnt *));
        for (i = 0; i < oc; i++) {
            ScopeEnt *e = old[i], *nx;
            for (; e; e = nx) {
                nx = e->next;
                h = hash_name(e->sym->name) & (unsigned)(s->cap - 1);
                e->next = s->tab[h];
                s->tab[h] = e;
            }
        }
        free(old);
    }
    n = (ScopeEnt *)xcalloc(1, sizeof(ScopeEnt));
    n->sym = sym;
    h = hash_name(sym->name) & (unsigned)(s->cap - 1);
    n->next = s->tab[h];
    s->tab[h] = n;
    s->n++;
}

/* ---------- types ---------- */

Type ty_void = {T_VOID, 0, 0, 0, 0, 0}, ty_boolean = {T_BOOLEAN, 0, 0, 0, 0, 0},
     ty_byte = {T_BYTE, 0, 0, 0, 0, 0}, ty_integer = {T_INTEGER, 0, 0, 0, 0, 0},
     ty_long = {T_LONG, 0, 0, 0, 0, 0}, ty_single = {T_SINGLE, 0, 0, 0, 0, 0},
     ty_double = {T_DOUBLE, 0, 0, 0, 0, 0}, ty_currency = {T_CURRENCY, 0, 0, 0, 0, 0},
     ty_date = {T_DATE, 0, 0, 0, 0, 0}, ty_string = {T_STRING, 0, 0, 0, 0, 0},
     ty_variant = {T_VARIANT, 0, 0, 0, 0, 0}, ty_object = {T_OBJECT, 0, 0, 0, 0, 0};

Type *type_prim(int k)
{
    switch (k) {
    case T_VOID: return &ty_void;
    case T_BOOLEAN: return &ty_boolean;
    case T_BYTE: return &ty_byte;
    case T_INTEGER: return &ty_integer;
    case T_LONG: return &ty_long;
    case T_SINGLE: return &ty_single;
    case T_DOUBLE: return &ty_double;
    case T_CURRENCY: return &ty_currency;
    case T_DATE: return &ty_date;
    case T_STRING: return &ty_string;
    case T_OBJECT: return &ty_object;
    default: return &ty_variant;
    }
}

Type *type_array(Type *elem, int ndims)
{
    Type *t = (Type *)xcalloc(1, sizeof(Type));
    t->kind = T_ARRAY;
    t->elem = elem;
    t->ndims = ndims;
    return t;
}

Type *type_object(ClassInfo *cls)
{
    Type *t;
    if (!cls) return &ty_object;
    t = (Type *)xcalloc(1, sizeof(Type));
    t->kind = T_OBJECT;
    t->cls = cls;
    return t;
}

Type *type_udt(Udt *u)
{
    Type *t = (Type *)xcalloc(1, sizeof(Type));
    t->kind = T_UDT;
    t->udt = u;
    return t;
}

int type_is_numeric(const Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: case T_BYTE: case T_INTEGER: case T_LONG: case T_SINGLE: case T_DOUBLE:
    case T_CURRENCY: case T_DATE: return 1;
    default: return 0;
    }
}

int type_is_integral(const Type *t)
{
    return t->kind == T_BOOLEAN || t->kind == T_BYTE || t->kind == T_INTEGER || t->kind == T_LONG;
}

int type_eq(const Type *a, const Type *b)
{
    if (a == b) return 1;
    if (a->kind != b->kind) return 0;
    switch (a->kind) {
    case T_OBJECT: return a->cls == b->cls;
    case T_UDT: return a->udt == b->udt;
    case T_ARRAY: return type_eq(a->elem, b->elem);
    default: return 1;
    }
}

const char *type_name(const Type *t)
{
    static char buf[4][128];
    static int k;
    char *b;
    switch (t->kind) {
    case T_VOID: return "Void";
    case T_BOOLEAN: return "Boolean";
    case T_BYTE: return "Byte";
    case T_INTEGER: return "Integer";
    case T_LONG: return "Long";
    case T_SINGLE: return "Single";
    case T_DOUBLE: return "Double";
    case T_CURRENCY: return "Currency";
    case T_DATE: return "Date";
    case T_STRING: return "String";
    case T_VARIANT: return "Variant";
    case T_OBJECT: return t->cls ? t->cls->name : "Object";
    case T_UDT: return t->udt->name;
    case T_ARRAY:
        b = buf[k++ & 3];
        snprintf(b, 128, "%s()", type_name(t->elem));
        return b;
    default: return "?";
    }
}

int type_vartype(const Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: return BB_BOOLEAN;
    case T_BYTE: return BB_BYTE;
    case T_INTEGER: return BB_INTEGER;
    case T_LONG: return BB_LONG;
    case T_SINGLE: return BB_SINGLE;
    case T_DOUBLE: return BB_DOUBLE;
    case T_CURRENCY: return BB_CURRENCY;
    case T_DATE: return BB_DATE;
    case T_STRING: return BB_STRING;
    case T_OBJECT: return BB_OBJECT;
    case T_UDT: return BB_UDT;
    case T_ARRAY: return BB_ARRAY | type_vartype(t->elem);
    default: return BB_VARIANT;
    }
}

/* numeric widening rank */
int type_rank(const Type *t)
{
    switch (t->kind) {
    case T_BYTE: return 1;
    case T_BOOLEAN: case T_INTEGER: return 2;
    case T_LONG: return 3;
    case T_SINGLE: return 4;
    case T_DOUBLE: return 5;
    case T_CURRENCY: return 6;
    case T_DATE: return 7;
    default: return 0;
    }
}
