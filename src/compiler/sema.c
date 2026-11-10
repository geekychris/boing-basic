/* sema.c - declarations, statements and the program-level checks */
#include "sema.h"
#include "../runtime/boing.h"
#include "../runtime/boing_ext.h"
#include <stdlib.h>
#include <string.h>

int proc_local_add(Proc *pr, Sym *s)
{
    if (pr->nlocals == pr->caplocals) {
        pr->caplocals = pr->caplocals ? pr->caplocals * 2 : 16;
        pr->locals = (Sym **)xrealloc(pr->locals, sizeof(Sym *) * (size_t)pr->caplocals);
    }
    s->index = pr->nlocals;
    s->proc = pr;
    pr->locals[pr->nlocals++] = s;
    return s->index;
}

static Sym *new_sym(int kind, const char *name, Node *at)
{
    Sym *s = (Sym *)xcalloc(1, sizeof(Sym));
    s->kind = kind;
    s->name = (char *)name;
    if (at) { s->line = at->line; s->col = at->col; s->file = at->file; }
    return s;
}

static void add_global(Program *p, Sym *s)
{
    p->globals = (Sym **)xrealloc(p->globals, sizeof(Sym *) * (size_t)(p->nglobals + 1));
    s->index = p->nglobals;
    p->globals[p->nglobals++] = s;
}

static void add_proc(Program *p, Proc *pr)
{
    p->procs = (Proc **)xrealloc(p->procs, sizeof(Proc *) * (size_t)(p->nprocs + 1));
    pr->index = p->nprocs;
    p->procs[p->nprocs++] = pr;
    if (pr->mod) {
        pr->mod->procs = (Proc **)xrealloc(pr->mod->procs, sizeof(Proc *) * (size_t)(pr->mod->nprocs + 1));
        pr->mod->procs[pr->mod->nprocs++] = pr;
    }
}

/* define in the right scope; duplicate check */
static int define(Ctx *c, Scope *sc, Sym *s, Node *at)
{
    Sym *old = scope_find_local(sc, s->name);
    if (old) {
        if (old->kind == SK_PROPGROUP && s->kind == SK_PROPGROUP) return 1;
        ERR(c, at, "'%s' is already defined (line %d)", s->name, old->line);
        return 0;
    }
    scope_add(sc, s);
    return 1;
}

/* ---------- types ---------- */

Type *default_type(Ctx *c, const char *name);
static Type *resolve_type_n(Ctx *c, Node *tn, char suffix, int *fixlen, const char *name);
Type *resolve_type(Ctx *c, Node *tn, char suffix, int *fixlen) { return resolve_type_n(c, tn, suffix, fixlen, NULL); }

/* name: the declared name, for DefInt etc. when there is neither As nor a suffix */
static Type *resolve_type_n(Ctx *c, Node *tn, char suffix, int *fixlen, const char *name)
{
    const char *n;
    Sym *s;
    if (fixlen) *fixlen = 0;
    if (!tn) {
        Type *t = suffix_type(suffix);
        return t ? t : default_type(c, name);
    }
    if (suffix) ERR(c, tn, "a variable with a type suffix cannot have an As clause");
    n = tn->name;
    if (name_eq(n, "Integer")) return &ty_integer;
    if (name_eq(n, "Long")) return &ty_long;
    if (name_eq(n, "Single")) return &ty_single;
    if (name_eq(n, "Double")) return &ty_double;
    if (name_eq(n, "Currency")) return &ty_currency;
    if (name_eq(n, "Boolean")) return &ty_boolean;
    if (name_eq(n, "Byte")) return &ty_byte;
    if (name_eq(n, "Date")) return &ty_date;
    if (name_eq(n, "Variant")) return &ty_variant;
    if (name_eq(n, "Object")) return &ty_object;
    if (name_eq(n, "Any")) { Type *t = (Type *)xcalloc(1, sizeof(Type)); t->kind = T_ANY; return t; }
    if (name_eq(n, "String")) {
        if (tn->b) {
            Node *e = check_value(c, tn->b);
            if (e->kind != E_CONST || (e->cv.type != T_INTEGER && e->cv.type != T_LONG) || e->cv.i < 1 || e->cv.i > 65535) {
                ERR(c, tn, "String * n needs a constant length");
                return &ty_string;
            }
            {
                Type *t = (Type *)xcalloc(1, sizeof(Type));
                t->kind = T_STRING;
                t->fixlen = (int)e->cv.i;
                if (fixlen) *fixlen = t->fixlen;
                return t;
            }
        }
        return &ty_string;
    }
    s = scope_find(c->scope, n);
    if (s && s->kind == SK_UDT) return type_udt(s->udt);
    if (s && s->kind == SK_CLASS) return type_object(s->cls);
    if (s && s->kind == SK_ENUM) return &ty_long;
    if (s && s->kind == SK_MODULE && s->cls) return type_object(s->cls);    /* dictionary.bas: As Dictionary */
    ERR(c, tn, "type '%s' is not defined", n);
    return &ty_variant;
}

/* ---------- constants ---------- */

static int eval_const_expr(Ctx *c, Node *e, Type *want, CVal *out)
{
    Node *r = check_value(c, e);
    if (want) r = coerce(c, r, want);
    if (r->kind != E_CONST) {
        ERR(c, e, "constant expression required");
        return 0;
    }
    *out = r->cv;
    return 1;
}

static void declare_const(Ctx *c, Scope *sc, Node *d, int is_public)
{
    Sym *s = new_sym(SK_CONST, d->name, d);
    Type *t = d->a ? resolve_type(c, d->a, d->suffix, NULL) : suffix_type(d->suffix);
    CVal v;
    if (!eval_const_expr(c, d->c, t, &v)) { memset(&v, 0, sizeof v); v.type = T_INTEGER; }
    s->cv = v;
    s->ty = t ? t : cval_type(&v);
    s->is_public = is_public;
    s->mod = c->mod;
    define(c, sc, s, d);
}

/* ---------- variables ---------- */

static void array_bounds(Ctx *c, Sym *s, Node *d)
{
    int i;
    s->ndims = d->list.n;
    for (i = 0; i < d->list.n; i++) {
        Node *b = d->list.v[i];
        CVal lo, hi;
        memset(&lo, 0, sizeof lo);
        lo.type = T_LONG;
        lo.i = c->mod->opt_base;
        if (b->a && !eval_const_expr(c, b->a, &ty_long, &lo)) return;
        if (!eval_const_expr(c, b->b, &ty_long, &hi)) return;
        if (hi.i < lo.i) ERR(c, d, "array upper bound is below the lower bound");
        nl_push(&s->bounds, mk_const_node(d, &lo));
        nl_push(&s->bounds, mk_const_node(d, &hi));
    }
}

static Sym *make_var(Ctx *c, Node *d, int storage)
{
    Sym *s = new_sym(SK_VAR, d->name, d);
    int fl;
    Type *t = resolve_type_n(c, d->a, d->suffix, &fl, d->name);
    s->storage = storage;
    s->mod = c->mod;
    if (d->flags & NF_ARRAY) {
        if (d->list.n > BB_MAXDIMS) ERR(c, d, "too many dimensions");
        if (d->list.n) { s->fixed_array = 1; array_bounds(c, s, d); }
        t = type_array(t, d->list.n);
    }
    if (d->flags & NF_NEW) {
        if (t->kind != T_OBJECT || !t->cls) ERR(c, d, "'As New' needs a class");
        else s->is_new = 1;     /* registered classes too: created by name (bb_ext_create) */
    }
    if (d->flags & NF_WITHEVENTS) {
        if (t->kind != T_OBJECT || !t->cls) ERR(c, d, "WithEvents needs a class type");
        else if (IS_REGCLS(t->cls) && !t->cls->nevents) ERR(c, d, "WithEvents: the class %s has no events", t->cls->name);
        s->withevents = 1;
    }
    s->ty = t;
    s->is_public = (d->flags & NF_PUBLIC) != 0;
    return s;
}

/* ---------- procedures ---------- */

static Proc *make_proc(Ctx *c, Node *d, int kind)
{
    Proc *pr = (Proc *)xcalloc(1, sizeof(Proc));
    int i;
    pr->name = d->name;
    pr->kind = kind;
    pr->mod = c->mod;
    pr->cls = c->mod->cls;
    pr->decl = d;
    pr->line = d->line;
    pr->file = d->file;
    pr->vslot = -1;
    pr->is_public = !(d->flags & NF_PRIVATE);
    if (kind == PK_DECLARE) pr->is_public = !(d->flags & NF_PRIVATE) && !c->mod->cls;
    pr->all_static = (d->flags & NF_STATIC) != 0;
    pr->nparams = d->list.n;
    pr->params = (Param *)xcalloc((size_t)(pr->nparams + 1), sizeof(Param));
    pr->min_args = 0;
    for (i = 0; i < d->list.n; i++) {
        Node *pn = d->list.v[i];
        Param *pa = &pr->params[i];
        Type *t = resolve_type_n(c, pn->a, pn->suffix, NULL, pn->name);
        pa->name = pn->name;
        pa->line = pn->line;
        pa->col = pn->col;
        pa->optional = (pn->ival & 1) != 0;
        pa->paramarray = (pn->ival & 2) != 0;
        if (pn->flags & NF_ARRAY) t = type_array(t, 0);
        if (pa->paramarray) {
            if (i != d->list.n - 1) ERR(c, pn, "ParamArray must be the last parameter");
            if (!(pn->flags & NF_ARRAY) || t->elem->kind != T_VARIANT) ERR(c, pn, "ParamArray must be a Variant array");
            pa->byref = 1;
            t = type_array(&ty_variant, 1);
        } else pa->byref = pn->op != 0;
        if (t->kind == T_ARRAY && !pa->byref) { ERR(c, pn, "arrays cannot be passed ByVal"); pa->byref = 1; }
        if (t->kind == T_UDT && !pa->byref && kind != PK_DECLARE) { ERR(c, pn, "user-defined types cannot be passed ByVal"); pa->byref = 1; }
        pa->ty = t;
        if (pn->c) {
            if (!pa->optional) ERR(c, pn, "only Optional parameters can have defaults");
            if (eval_const_expr(c, pn->c, t->kind == T_VARIANT ? NULL : t, &pa->def)) pa->has_def = 1;
        }
        if (!pa->optional && !pa->paramarray) {
            if (i > 0 && pr->params[i - 1].optional) ERR(c, pn, "parameter '%s' must be Optional (it follows an Optional one)", pa->name);
            pr->min_args = i + 1;
        }
    }
    if (kind == PK_FUNCTION || kind == PK_PGET || (kind == PK_DECLARE && d->op == PK_FUNCTION)) {
        int fl;
        pr->ret = resolve_type_n(c, d->a, d->suffix, &fl, d->name);
        if (d->a && (d->flags & NF_ARRAY)) pr->ret = type_array(pr->ret, 0);
        if (kind == PK_DECLARE) pr->is_func_declare = 1;
    }
    if (kind == PK_PLET || kind == PK_PSET) {
        if (pr->nparams < 1) ERR(c, d, "Property %s needs at least one parameter", kind == PK_PLET ? "Let" : "Set");
    }
    return pr;
}

static void declare_proc(Ctx *c, Node *d)
{
    Module *m = c->mod;
    Proc *pr = make_proc(c, d, d->op);
    Scope *target = m->scope;
    pr->defined = 1;
    add_proc(c->prog, pr);
    if (pr->kind == PK_PGET || pr->kind == PK_PLET || pr->kind == PK_PSET) {
        Sym *g = scope_find_local(m->scope, pr->name);
        if (g && g->kind != SK_PROPGROUP) { ERR(c, d, "'%s' is already defined (line %d)", pr->name, g->line); return; }
        if (!g) {
            g = new_sym(SK_PROPGROUP, pr->name, d);
            g->mod = m;
            g->is_public = pr->is_public;
            scope_add(m->scope, g);
            if (!m->is_class && pr->is_public) {
                Sym *gg = scope_find_local(c->prog->global, pr->name);
                if (!gg) scope_add(c->prog->global, g);
            }
        }
        if (pr->kind == PK_PGET) { if (g->pget) ERR(c, d, "duplicate Property Get '%s'", pr->name); g->pget = pr; }
        if (pr->kind == PK_PLET) { if (g->plet) ERR(c, d, "duplicate Property Let '%s'", pr->name); g->plet = pr; }
        if (pr->kind == PK_PSET) { if (g->pset) ERR(c, d, "duplicate Property Set '%s'", pr->name); g->pset = pr; }
        if (pr->is_public) g->is_public = 1;
        if (m->cls) {
            m->cls->methods = (Proc **)xrealloc(m->cls->methods, sizeof(Proc *) * (size_t)(m->cls->nmethods + 1));
            m->cls->methods[m->cls->nmethods++] = pr;
        }
        return;
    }
    {
        Sym *s = new_sym(SK_PROC, pr->name, d);
        s->proc = pr;
        s->mod = m;
        s->is_public = pr->is_public;
        if (!define(c, target, s, d)) return;
        if (!m->is_class && pr->is_public) {
            Sym *gg = scope_find_local(c->prog->global, pr->name);
            if (gg && gg->kind == SK_PROC) {
                /* same public name in two modules: callers elsewhere must qualify (sema_expr) */
                if (!gg->ambig) gg->ambig = m;
            } else if (!gg) scope_add(c->prog->global, s);
        }
    }
    if (m->cls) {
        m->cls->methods = (Proc **)xrealloc(m->cls->methods, sizeof(Proc *) * (size_t)(m->cls->nmethods + 1));
        m->cls->methods[m->cls->nmethods++] = pr;
        if (name_eq(pr->name, "Class_Initialize")) m->cls->init = pr;
        if (name_eq(pr->name, "Class_Terminate")) m->cls->term = pr;
    }
}

/* ---------- pass 1: names ---------- */

static void declare_names(Program *p, Module *m)
{
    Ctx cx, *c = &cx;
    int i;
    memset(c, 0, sizeof cx);
    c->prog = p;
    c->mod = m;
    c->scope = m->scope;
    for (i = 0; i < m->decls.n; i++) {
        Node *d = m->decls.v[i];
        if (d->kind == D_TYPE) {
            Udt *u = (Udt *)xcalloc(1, sizeof(Udt));
            Sym *s = new_sym(SK_UDT, d->name, d);
            u->name = d->name;
            u->mod = m;
            u->is_public = !(d->flags & NF_PRIVATE);
            u->line = d->line;
            u->file = d->file;
            u->index = p->nudts;
            p->udts = (Udt **)xrealloc(p->udts, sizeof(Udt *) * (size_t)(p->nudts + 1));
            p->udts[p->nudts++] = u;
            s->udt = u;
            s->mod = m;
            s->is_public = u->is_public;
            d->udt = u;
            if (define(c, m->scope, s, d) && u->is_public && !m->is_class) {
                if (!scope_find_local(p->global, s->name)) scope_add(p->global, s);
            }
        } else if (d->kind == D_ENUM) {
            Sym *s = new_sym(SK_ENUM, d->name, d);
            s->mod = m;
            s->is_public = !(d->flags & NF_PRIVATE);
            d->sym = s;
            if (define(c, m->scope, s, d) && s->is_public && !m->is_class)
                if (!scope_find_local(p->global, s->name)) scope_add(p->global, s);
        }
    }
}

/* ---------- pass 2: signatures, variables, constants ---------- */

static void declare_members(Program *p, Module *m)
{
    Ctx cx, *c = &cx;
    int i, j;
    memset(c, 0, sizeof cx);
    c->prog = p;
    c->mod = m;
    c->cls = m->cls;
    c->scope = m->scope;
    for (i = 0; i < m->decls.n; i++) {
        Node *d = m->decls.v[i];
        switch (d->kind) {
        case D_TYPE: {
            Udt *u = d->udt;
            if (!u) break;
            u->nfields = d->list.n;
            u->fields = (UField *)xcalloc((size_t)(u->nfields + 1), sizeof(UField));
            for (j = 0; j < d->list.n; j++) {
                Node *f = d->list.v[j];
                UField *uf = &u->fields[j];
                int fl, k;
                uf->name = f->name;
                uf->line = f->line;
                uf->ty = resolve_type(c, f->a, f->suffix, &fl);
                uf->fixlen = fl;
                if (uf->ty->kind == T_UDT && uf->ty->udt == u) ERR(c, f, "type '%s' cannot contain itself", u->name);
                for (k = 0; k < j; k++) if (name_eq(u->fields[k].name, uf->name)) ERR(c, f, "duplicate field '%s'", uf->name);
                if (f->flags & NF_ARRAY) {
                    Sym tmp;
                    memset(&tmp, 0, sizeof tmp);
                    if (f->list.n) {
                        array_bounds(c, &tmp, f);
                        uf->ndims = tmp.ndims;
                        for (k = 0; k < tmp.ndims && k < 8; k++) {
                            uf->lb[k] = (int)tmp.bounds.v[2 * k]->cv.i;
                            uf->ub[k] = (int)tmp.bounds.v[2 * k + 1]->cv.i;
                        }
                    }
                    uf->ty = type_array(uf->ty, f->list.n);
                }
            }
            break;
        }
        case D_ENUM: {
            int64_t next = 0;
            Sym *es = d->sym;
            if (!es) break;
            for (j = 0; j < d->list.n; j++) {
                Node *mn = d->list.v[j];
                Sym *s = new_sym(SK_CONST, mn->name, mn);
                Node *holder = node_new(S_NOP, mn->file, mn->line, mn->col);
                CVal v;
                memset(&v, 0, sizeof v);
                v.type = T_LONG;
                if (mn->c) { if (eval_const_expr(c, mn->c, &ty_long, &v)) next = v.i; }
                v.type = T_LONG;
                v.i = next;
                next++;
                s->cv = v;
                s->ty = &ty_long;
                s->mod = m;
                s->is_public = es->is_public;
                s->udt = (Udt *)es;
                holder->sym = s;
                nl_push(&es->bounds, holder);
                /* members are also plain constants */
                if (!scope_find_local(m->scope, s->name)) scope_add(m->scope, s);
                if (es->is_public && !m->is_class && !scope_find_local(p->global, s->name)) scope_add(p->global, s);
            }
            break;
        }
        case D_CONST:
            for (j = 0; j < d->list.n; j++) {
                Node *cd = d->list.v[j];
                int pub = (d->flags & NF_PUBLIC) != 0;
                declare_const(c, m->scope, cd, pub);
                if (pub && !m->is_class) {
                    Sym *s = scope_find_local(m->scope, cd->name);
                    if (s && !scope_find_local(p->global, s->name)) scope_add(p->global, s);
                }
            }
            break;
        case D_DIM:
            for (j = 0; j < d->list.n; j++) {
                Node *vd = d->list.v[j];
                Sym *s;
                if (m->is_class) {
                    s = make_var(c, vd, ST_FIELD);
                    s->cls = m->cls;
                    if (!define(c, m->scope, s, vd)) continue;
                    s->index = m->cls->nfields;
                    m->cls->fields = (Sym **)xrealloc(m->cls->fields, sizeof(Sym *) * (size_t)(m->cls->nfields + 1));
                    m->cls->fields[m->cls->nfields++] = s;
                    if (s->withevents) {
                        m->cls->wevars = (Sym **)xrealloc(m->cls->wevars, sizeof(Sym *) * (size_t)(m->cls->nwevars + 1));
                        m->cls->wevars[m->cls->nwevars++] = s;
                    }
                } else {
                    s = make_var(c, vd, ST_GLOBAL);
                    if (!define(c, m->scope, s, vd)) continue;
                    add_global(p, s);
                    if (s->is_public) {
                        Sym *old = scope_find_local(p->global, s->name);
                        if (old) ERR(c, vd, "public variable '%s' is already defined in another module", s->name);
                        else scope_add(p->global, s);
                    }
                }
            }
            break;
        case D_PROC:
            declare_proc(c, d);
            break;
        case D_DECLARE: {
            Proc *pr = make_proc(c, d, PK_DECLARE);
            Sym *s = new_sym(SK_PROC, pr->name, d);
            pr->cls = NULL;
            pr->lib = d->b ? d->b->name : xstrdup("");
            pr->alias = d->c ? d->c->name : pr->name;
            pr->iface = d->d ? d->d->name : xstrdup("main");
            pr->version = (int)d->ival;
            if (d->op == PK_FUNCTION && !pr->ret) pr->ret = &ty_variant;
            if (!strcmp(pr->lib, "C")) {
                /* Lib "C": ByVal numbers, Booleans and Strings; the same for the result */
                int k;
                pr->clib = 1;
                for (k = 0; k < pr->nparams; k++) {
                    Param *pa = &pr->params[k];
                    int tk = pa->ty->kind;
                    if (pa->byref || pa->optional || pa->paramarray) ERR(c, d, "Lib \"C\" parameters must be ByVal (%s)", pa->name);
                    else if (tk != T_LONG && tk != T_INTEGER && tk != T_BYTE && tk != T_BOOLEAN && tk != T_SINGLE && tk != T_DOUBLE && tk != T_STRING)
                        ERR(c, d, "Lib \"C\" parameter %s: only Long, Integer, Byte, Boolean, Single, Double or String", pa->name);
                }
                if (pr->ret) {
                    int tk = pr->ret->kind;
                    if (tk == T_VARIANT) ERR(c, d, "a Lib \"C\" Function needs an As type");
                    else if (tk != T_LONG && tk != T_INTEGER && tk != T_BYTE && tk != T_BOOLEAN && tk != T_SINGLE && tk != T_DOUBLE && tk != T_STRING)
                        ERR(c, d, "a Lib \"C\" Function returns Long, Integer, Byte, Boolean, Single, Double or String");
                }
            }
            add_proc(p, pr);
            s->proc = pr;
            s->mod = m;
            s->is_public = pr->is_public;
            if (define(c, m->scope, s, d) && pr->is_public && !scope_find_local(p->global, s->name))
                scope_add(p->global, s);
            break;
        }
        case D_EVENT: {
            Proc *pr;
            Sym *s;
            if (!m->cls) { ERR(c, d, "Event is only allowed in a class module"); break; }
            pr = make_proc(c, d, PK_EVENT);
            pr->event_index = m->cls->nevents;
            pr->is_public = 1;
            m->cls->events = (Proc **)xrealloc(m->cls->events, sizeof(Proc *) * (size_t)(m->cls->nevents + 1));
            m->cls->events[m->cls->nevents++] = pr;
            s = new_sym(SK_PROC, pr->name, d);
            s->proc = pr;
            s->mod = m;
            s->is_public = 0;
            define(c, m->scope, s, d);
            break;
        }
        case D_IMPLEMENTS:
            break;  /* after all classes exist */
        default:
            break;
        }
    }
}

static void resolve_implements(Program *p, Module *m)
{
    Ctx cx, *c = &cx;
    int i;
    memset(c, 0, sizeof cx);
    c->prog = p;
    c->mod = m;
    c->scope = m->scope;
    for (i = 0; i < m->decls.n; i++) {
        Node *d = m->decls.v[i];
        ClassInfo *iface;
        if (d->kind != D_IMPLEMENTS) continue;
        if (!m->cls) { ERR(c, d, "Implements is only allowed in a class module"); continue; }
        iface = find_class(c, d->name);
        if (!iface || iface->builtin || IS_REGCLS(iface)) { ERR(c, d, "class '%s' is not defined", d->name); continue; }
        if (iface == m->cls) { ERR(c, d, "a class cannot implement itself"); continue; }
        iface->is_interface = 1;
        m->cls->impls = (ClassInfo **)xrealloc(m->cls->impls, sizeof(ClassInfo *) * (size_t)(m->cls->nimpls + 1));
        m->cls->impls[m->cls->nimpls++] = iface;
    }
}

/* public members of a class get vtable slots, in declaration order */
static void layout_class(Program *p, ClassInfo *cls)
{
    int i;
    (void)p;
    for (i = 0; i < cls->nmethods; i++) {
        Proc *pr = cls->methods[i];
        if (!pr->is_public) continue;
        pr->vslot = cls->nvtbl;
        cls->vtbl = (Proc **)xrealloc(cls->vtbl, sizeof(Proc *) * (size_t)(cls->nvtbl + 1));
        cls->vtbl[cls->nvtbl++] = pr;
    }
}

static int same_signature(Proc *a, Proc *b)
{
    int i;
    if (a->nparams != b->nparams) return 0;
    if ((a->ret == NULL) != (b->ret == NULL)) return 0;
    if (a->ret && !type_eq(a->ret, b->ret)) return 0;
    for (i = 0; i < a->nparams; i++) {
        if (!type_eq(a->params[i].ty, b->params[i].ty)) return 0;
        if (a->params[i].byref != b->params[i].byref) return 0;
    }
    return 1;
}

static void check_implements(Program *p, ClassInfo *cls)
{
    int i, j, k;
    for (i = 0; i < cls->nimpls; i++) {
        ClassInfo *I = cls->impls[i];
        for (j = 0; j < I->nvtbl; j++) {
            Proc *ip = I->vtbl[j], *found = NULL;
            char *want = xsprintf("%s_%s", I->name, ip->name);
            for (k = 0; k < cls->nmethods; k++) {
                Proc *cp = cls->methods[k];
                if (cp->kind == ip->kind && name_eq(cp->name, want)) found = cp;
            }
            if (!found)
                diag(p, cls->mod->file, 1, 1, "class '%s' must implement '%s' (%s of interface '%s')",
                     cls->name, want, ip->kind == PK_PGET ? "Property Get" : ip->kind == PK_PLET ? "Property Let" :
                     ip->kind == PK_PSET ? "Property Set" : ip->kind == PK_SUB ? "Sub" : "Function", I->name);
            else if (!same_signature(found, ip))
                diag(p, found->file, found->line, 1, "'%s' does not match the declaration in interface '%s'", want, I->name);
            else {
                found->impl_of = ip;
                found->impl_iface = I;
            }
            free(want);
        }
        for (j = 0; j < I->nfields; j++)
            if (I->fields[j]->is_public)
                diag(p, I->mod->file, I->fields[j]->line, 1,
                     "public variable '%s' in interface class '%s' is not supported; use properties", I->fields[j]->name, I->name);
    }
}

/* ---------- statements ---------- */

static void check_stmt(Ctx *c, Node *s, NodeList *out);

void check_block(Ctx *c, NodeList *body)
{
    NodeList out = {0, 0, 0};
    int i;
    for (i = 0; i < body->n; i++) check_stmt(c, body->v[i], &out);
    free(body->v);
    *body = out;
}

static Sym *find_label(Ctx *c, Node *at, const char *name)
{
    int i;
    for (i = 0; i < c->proc->nlabels; i++)
        if (name_eq(c->proc->labels[i]->name, name)) return c->proc->labels[i];
    ERR(c, at, "label '%s' is not defined in this procedure", name);
    return NULL;
}

static void collect_labels(Ctx *c, NodeList *body)
{
    int i;
    for (i = 0; i < body->n; i++) {
        Node *s = body->v[i];
        if (!s) continue;
        if (s->kind == S_LABEL) {
            int k;
            Sym *l;
            for (k = 0; k < c->proc->nlabels; k++)
                if (name_eq(c->proc->labels[k]->name, s->name)) { ERR(c, s, "label '%s' defined twice", s->name); break; }
            l = new_sym(SK_LABEL, s->name, s);
            l->label_id = c->proc->nlabels;
            c->proc->labels = (Sym **)xrealloc(c->proc->labels, sizeof(Sym *) * (size_t)(c->proc->nlabels + 1));
            c->proc->labels[c->proc->nlabels++] = l;
            s->sym = l;
            c->proc->has_labels = 1;
        }
        collect_labels(c, &s->list);
        collect_labels(c, &s->list2);
        /* If branches keep their bodies in list2 of the branch nodes (Case bodies too, but the
           recursion above already walks a Case node's list2: walking it here as well made a
           label inside a Case "defined twice") */
        if (s->kind == S_IF) {
            int k;
            for (k = 0; k < s->list.n; k++) collect_labels(c, &s->list.v[k]->list2);
        }
    }
}

static Node *mk_stmt(int kind, Node *at)
{
    return node_new(kind, at->file, at->line, at->col);
}

/* complete a property/late "target = value" into a call statement */
static Node *assign_to_prop(Ctx *c, Node *s, Node *t, Node *val, int is_set)
{
    Node *st = mk_stmt(S_EXPR, s);
    if (t->kind == E_DEFPROP) {
        Sym *g = t->sym;
        Proc *pr = is_set ? g->pset : g->plet;
        NodeList args = t->list;
        Node *call;
        if (!pr && !is_set && g->pset && val->ty->kind == T_OBJECT) pr = g->pset;
        if (!pr) {
            ERR(c, s, "property '%s' has no Property %s", g->name, is_set ? "Set" : "Let");
            return NULL;
        }
        /* the value is the last parameter: pass it as an already-checked node */
        {
            NodeList a2 = {0, 0, 0};
            int i;
            for (i = 0; i < args.n; i++) nl_push(&a2, args.v[i]);
            nl_push(&a2, val);
            call = make_call(c, s, pr, &a2, t->a, M_STMT);
        }
        st->a = call;
        return st;
    }
    if (t->kind == E_LATE) {
        t->argc_kind = is_set ? BB_INV_SET : BB_INV_LET;
        nl_push(&t->list, coerce(c, val, &ty_variant));
        t->flags |= NF_VOIDCALL;
        st->a = t;
        return st;
    }
    return NULL;
}

/* obj(k)(i) = v, d("a")(1) = v: the inner value is an array (or another indexable Variant) that
   obj(k) returns as a copy; store into it and put it back: t = obj(k): t(i) = v: obj(k) = t
   (deeper chains go through the same steps) */
static void late_let(Ctx *c, Node *s, Node *t, Node *v, NodeList *out)
{
    Node *inner = t->a;
    if (t->kind == E_LATE && !t->name[0] && inner && inner->kind == E_LATE && inner->list.n > 0 &&
        inner->ty->kind == T_VARIANT) {
        Sym *tmp = new_temp(c, &ty_variant, s);
        Node *st1 = mk_stmt(S_LET, s), *l = node_new(E_LATE, s->file, s->line, s->col), *back;
        Node *st;
        int i;
        st1->a = mk_var(s, tmp);
        st1->b = inner;
        nl_push(out, st1);
        l->a = mk_var(s, tmp);
        l->name = xstrdup("");
        l->ty = &ty_variant;
        for (i = 0; i < t->list.n; i++) nl_push(&l->list, t->list.v[i]);
        st = assign_to_prop(c, s, l, v, 0);
        if (st) nl_push(out, st);
        back = node_new(E_LATE, s->file, s->line, s->col);
        *back = *inner;
        memset(&back->list, 0, sizeof back->list);
        for (i = 0; i < inner->list.n; i++) nl_push(&back->list, inner->list.v[i]);
        late_let(c, s, back, mk_var(s, tmp), out);
        return;
    }
    {
        Node *st = assign_to_prop(c, s, t, v, 0);
        if (st) nl_push(out, st);
    }
}

static void check_let(Ctx *c, Node *s, NodeList *out)
{
    Node *t, *v;
    /* Mid(s, a, b) = x */
    if (s->a->kind == E_APPLY && s->a->a->kind == E_NAME && name_eq(s->a->a->name, "Mid") &&
        !scope_find(c->scope, "Mid")) {
        Node *m = mk_stmt(S_MIDASSIGN, s);
        NodeList *args = &s->a->list;
        if (args->n < 2 || args->n > 3) { ERR(c, s, "Mid statement needs 2 or 3 arguments"); return; }
        m->a = check_expr(c, args->v[0], M_ARG);
        if (!is_lvalue(m->a) || (m->a->ty->kind != T_STRING && m->a->ty->kind != T_VARIANT)) ERR(c, s, "Mid statement needs a string variable");
        m->b = coerce(c, check_value(c, args->v[1]), &ty_long);
        if (args->n == 3 && args->v[2]->kind != E_MISSING) m->c = coerce(c, check_value(c, args->v[2]), &ty_long);
        m->d = coerce(c, check_value(c, s->b), &ty_string);
        nl_push(out, m);
        return;
    }
    t = check_expr(c, s->a, M_LVAL);
    v = check_value(c, s->b);
    if (t->kind == E_DEFPROP || t->kind == E_LATE) {
        Node *st;
        if (t->kind == E_DEFPROP && v->ty->kind == T_OBJECT && t->sym->pset && !t->sym->plet) {
            ERR(c, s, "use Set to assign an object to property '%s'", t->sym->name);
            return;
        }
        if (t->kind == E_LATE) { late_let(c, s, t, v, out); return; }
        st = assign_to_prop(c, s, t, v, 0);
        if (st) nl_push(out, st);
        return;
    }
    if (t->kind == E_ERRPROP) {
        if (t->op != 1 && t->op != 2 && t->op != 3) { ERR(c, s, "this Err property cannot be assigned"); return; }
        s->a = t;
        s->b = coerce(c, v, t->ty);
        nl_push(out, s);
        return;
    }
    if (!is_lvalue(t)) {
        if (t->kind == E_CONST) ERR(c, s, "cannot assign to a constant");
        else if (t->kind == E_CALL || t->kind == E_MCALL) ERR(c, s, "cannot assign to function '%s'", t->proc->name);
        else ERR(c, s, "invalid assignment target");
        return;
    }
    if (t->kind == E_VAR && t->sym->kind == SK_VAR && t->sym->storage == ST_PARAM && 0) {}
    if (t->ty->kind == T_OBJECT && v->ty->kind != T_OBJECT) {
        /* obj = value: the object's default property */
        Node *l = node_new(E_LATE, s->file, s->line, s->col);
        Node *st = mk_stmt(S_EXPR, s);
        l->a = t;
        l->name = xstrdup("");
        l->ty = &ty_variant;
        l->argc_kind = BB_INV_LET;
        l->flags |= NF_VOIDCALL;
        nl_push(&l->list, coerce(c, v, &ty_variant));
        st->a = l;
        nl_push(out, st);
        return;
    }
    if (t->ty->kind == T_OBJECT && v->ty->kind == T_OBJECT && !(v->kind == E_CONST && 0)) {
        ERR(c, s, "use Set to assign an object reference");
        return;
    }
    if (t->ty->kind == T_ARRAY) {
        if (t->kind == E_VAR && t->sym->fixed_array) ERR(c, s, "cannot assign to a fixed-size array");
    }
    s->a = t;
    s->b = coerce(c, v, t->ty);
    nl_push(out, s);
}

static void check_set(Ctx *c, Node *s, NodeList *out)
{
    Node *t = check_expr(c, s->a, M_SETLVAL), *v;
    if (s->b->kind == E_NEW) v = check_expr(c, s->b, M_VALUE);
    else v = check_value(c, s->b);
    if (v->ty->kind != T_OBJECT && v->ty->kind != T_VARIANT) {
        ERR(c, s->b, "object required for Set (found %s)", type_name(v->ty));
        return;
    }
    if (t->kind == E_DEFPROP || t->kind == E_LATE) {
        Node *st = assign_to_prop(c, s, t, v, 1);
        if (st) nl_push(out, st);
        return;
    }
    if (!is_lvalue(t)) { ERR(c, s, "invalid Set target"); return; }
    if (t->ty->kind != T_OBJECT && t->ty->kind != T_VARIANT) {
        ERR(c, s, "Set needs an object variable ('%s' is %s)", t->kind == E_VAR ? t->sym->name : "target", type_name(t->ty));
        return;
    }
    s->a = t;
    s->b = coerce(c, v, t->ty);
    nl_push(out, s);
}

static Node *as_call_stmt(Ctx *c, Node *s)
{
    Node *e = check_expr(c, s->a, M_STMT);
    switch (e->kind) {
    case E_CALL: case E_MCALL: case E_BUILTIN: case E_LATE:
        e->flags |= NF_VOIDCALL;
        if (e->kind == E_LATE && e->argc_kind == (BB_INV_GET | BB_INV_METHOD)) e->argc_kind = BB_INV_METHOD;
        s->a = e;
        return s;
    case E_ERRPROP:
        if (e->op != 4 && e->op != 5) { ERR(c, s, "invalid statement: Err.%s is a property", "x"); return NULL; }
        s->a = e;
        return s;
    case E_NAME: case E_DOT:
        return NULL;   /* error already reported */
    case E_VAR:
        if (e->sym->implicit) return NULL;
        ERR(c, s, "'%s' is a variable, not a Sub (missing '='?)", e->sym->name);
        return NULL;
    default:
        ERR(c, s, "invalid statement");
        return NULL;
    }
}

static Node *lvalue_of(Ctx *c, Node *e, const char *what)
{
    Node *t = check_expr(c, e, M_ARG);
    if (!is_lvalue(t)) ERR(c, e, "%s needs a variable", what);
    return t;
}

/* a Dim'd local with the name of a module-level or Public constant hides it in the
   procedure (legal VB, names are case-insensitive: `Dim acc` and `Const ACC`): a warning.
   Not for parameters: a parameter named like a constant is common and seldom a mistake */
static void warn_hides_const(Ctx *c, const char *name, int file, int line, int col)
{
    Sym *g = scope_find(c->proc->mod->scope, name);
    if (!g || g->kind != SK_CONST || !g->mod) return;
    diag_warn(c->prog, file, line, col, "local '%s' hides constant '%s' (line %d)", name, g->name, g->line);
}

static void check_dim_local(Ctx *c, Node *s, NodeList *out)
{
    int i;
    for (i = 0; i < s->list.n; i++) {
        Node *d = s->list.v[i];
        int is_static = (s->flags & NF_STATIC) || c->proc->all_static;
        Sym *v = make_var(c, d, is_static ? ST_STATIC : ST_LOCAL);
        if (v->withevents) ERR(c, d, "WithEvents is only allowed at module level");
        if (scope_find_local(c->proc->scope, d->name)) {
            Sym *o = scope_find_local(c->proc->scope, d->name);
            ERR(c, d, "'%s' is already declared in this procedure (line %d)", d->name, o->line);
            continue;
        }
        warn_hides_const(c, d->name, d->file, d->line, d->col);
        scope_add(c->proc->scope, v);
        v->proc = c->proc;
        if (is_static) {
            v->name = d->name;
            add_global(c->prog, v);
            v->cname = xsprintf("%s_%s", c->proc->name, d->name);
        } else proc_local_add(c->proc, v);
        if (0 && !is_static && (v->is_new)) {
            /* As New: create when the Dim runs */
            Node *st = mk_stmt(S_SET, d);
            Node *nw = node_new(E_NEW, d->file, d->line, d->col);
            nw->cls = v->ty->cls;
            nw->ty = v->ty;
            st->a = mk_var(d, v);
            st->b = nw;
            nl_push(out, st);
        }
    }
    (void)out;
}

static void check_redim(Ctx *c, Node *s, NodeList *out)
{
    int i, j;
    for (i = 0; i < s->list.n; i++) {
        Node *d = s->list.v[i];
        Node *t;
        Type *elem = NULL;
        if (d->b->kind == E_NAME && !scope_find(c->scope, d->b->name)) {
            /* ReDim declares a dynamic array */
            Sym *v = new_sym(SK_VAR, d->b->name, d);
            Type *et = resolve_type_n(c, d->a, d->b->suffix, NULL, d->b->name);
            v->ty = type_array(et, d->list.n);
            v->storage = ST_LOCAL;
            v->mod = c->mod;
            scope_add(c->proc->scope, v);
            proc_local_add(c->proc, v);
        }
        t = check_expr(c, d->b, M_ARG);
        if (!is_lvalue(t)) { ERR(c, d, "ReDim needs an array variable"); continue; }
        if (t->ty->kind == T_ARRAY) {
            elem = t->ty->elem;
            if (t->kind == E_VAR && t->sym->fixed_array) { ERR(c, d, "array '%s' is fixed-size and cannot be ReDim'd", t->sym->name); continue; }
            if (t->ty->ndims && t->ty->ndims != d->list.n && t->kind == E_VAR) {
                ERR(c, d, "ReDim cannot change the number of dimensions of '%s'", t->sym->name);
            }
        } else if (t->ty->kind == T_VARIANT) {
            elem = &ty_variant;
        } else { ERR(c, d, "ReDim needs an array ('%s' is %s)", t->kind == E_VAR ? t->sym->name : "target", type_name(t->ty)); continue; }
        if (d->a) {
            Type *dt = resolve_type(c, d->a, 0, NULL);
            if (!type_eq(dt, elem) && t->ty->kind == T_ARRAY) ERR(c, d, "ReDim cannot change the element type");
            if (t->ty->kind == T_VARIANT) elem = dt;
        }
        if (d->list.n > BB_MAXDIMS || d->list.n < 1) ERR(c, d, "bad number of dimensions");
        d->b = t;
        d->ty = elem;
        for (j = 0; j < d->list.n; j++) {
            Node *b = d->list.v[j];
            if (b->a) b->a = coerce(c, check_value(c, b->a), &ty_long);
            else {
                CVal v;
                memset(&v, 0, sizeof v);
                v.type = T_LONG;
                v.i = c->mod->opt_base;
                b->a = mk_const_node(b, &v);
            }
            b->b = coerce(c, check_value(c, b->b), &ty_long);
        }
    }
    nl_push(out, s);
}

static int in_loop(Ctx *c, int kind) { return kind == EXIT_FOR ? c->in_loop_for > 0 : c->in_loop_do > 0; }

static Node *mk_bin(Ctx *c, Node *at, int op, Node *a, Node *b)
{
    Node *n = node_new(E_BIN, at->file, at->line, at->col);
    n->op = op;
    n->a = a;
    n->b = b;
    return check_expr(c, n, M_VALUE);
}

static void check_stmt(Ctx *c, Node *s, NodeList *out)
{
    int i;
    if (!s) return;
    switch (s->kind) {
    case S_LET:
        check_let(c, s, out);
        return;
    case S_SET:
        check_set(c, s, out);
        return;
    case S_EXPR: {
        Node *r = as_call_stmt(c, s);
        if (r) nl_push(out, r);
        return;
    }
    case S_DIM:
        check_dim_local(c, s, out);
        return;
    case S_CONST:
        for (i = 0; i < s->list.n; i++) declare_const(c, c->proc->scope, s->list.v[i], 0);
        return;
    case S_REDIM:
        check_redim(c, s, out);
        return;
    case S_ERASE:
        for (i = 0; i < s->list.n; i++) {
            Node *t = lvalue_of(c, s->list.v[i], "Erase");
            if (t->ty->kind != T_ARRAY && t->ty->kind != T_VARIANT) ERR(c, s, "Erase needs an array");
            s->list.v[i] = t;
        }
        break;
    case S_IF:
        for (i = 0; i < s->list.n; i++) {
            Node *br = s->list.v[i];
            br->a = conv_to_bool_cond(c, br->a);
            check_block(c, &br->list);
        }
        check_block(c, &s->list2);
        break;
    case S_SELECT: {
        Node *sel = check_value(c, s->a);
        Sym *t;
        if (sel->ty->kind == T_UDT || sel->ty->kind == T_ARRAY) ERR(c, s, "Select Case needs a simple value");
        if (sel->ty->kind == T_OBJECT) sel = coerce(c, sel, &ty_variant);
        t = new_temp(c, sel->ty->fixlen ? &ty_string : sel->ty, s);
        s->a = sel;
        s->sym = t;
        s->text = c->mod->opt_text;
        for (i = 0; i < s->list.n; i++) {
            Node *cs = s->list.v[i];
            int k;
            NodeList conds = {0, 0, 0};
            for (k = 0; k < cs->list.n; k++) {
                Node *ce = cs->list.v[k], *cond;
                if (ce->kind == E_CASEIS) cond = mk_bin(c, ce, ce->op, mk_var(ce, t), ce->a);
                else if (ce->kind == E_CASERANGE) {
                    Node *lo = mk_bin(c, ce, OP_GE, mk_var(ce, t), ce->a);
                    Node *hi = mk_bin(c, ce, OP_LE, mk_var(ce, t), ce->b);
                    Node *n = node_new(E_BIN, ce->file, ce->line, ce->col);
                    n->op = OP_AND;
                    n->a = lo->ty->kind == T_BOOLEAN ? lo : coerce(c, lo, &ty_variant);
                    n->b = hi->ty->kind == T_BOOLEAN ? hi : coerce(c, hi, &ty_variant);
                    n->ty = (n->a->ty->kind == T_BOOLEAN && n->b->ty->kind == T_BOOLEAN) ? &ty_boolean : &ty_variant;
                    if (n->ty->kind == T_VARIANT) { n->a = coerce(c, n->a, &ty_variant); n->b = coerce(c, n->b, &ty_variant); }
                    cond = n;
                } else cond = mk_bin(c, ce, OP_EQ, mk_var(ce, t), ce);
                nl_push(&conds, cond);
            }
            free(cs->list.v);
            cs->list = conds;
            check_block(c, &cs->list2);
        }
        break;
    }
    case S_FOR: {
        Node *ctr = lvalue_of(c, s->a, "For");
        Type *t = ctr->ty;
        Sym *lim, *stp;
        if (!type_is_numeric(t) && t->kind != T_VARIANT) {
            ERR(c, s, "For loop counter must be numeric (found %s)", type_name(t));
            t = &ty_variant;
        }
        if (t->kind == T_BOOLEAN) ERR(c, s, "For loop counter cannot be Boolean");
        s->a = ctr;
        s->b = coerce(c, check_value(c, s->b), t);
        s->c = coerce(c, check_value(c, s->c), t);
        if (s->d) s->d = coerce(c, check_value(c, s->d), t);
        else {
            CVal one;
            memset(&one, 0, sizeof one);
            one.type = T_INTEGER;
            one.i = 1;
            s->d = coerce(c, mk_const_node(s, &one), t);
        }
        lim = new_temp(c, t, s);
        stp = new_temp(c, t, s);
        s->list2.n = 0;
        nl_push(&s->list2, mk_var(s, lim));
        nl_push(&s->list2, mk_var(s, stp));
        c->in_loop_for++;
        check_block(c, &s->list);
        c->in_loop_for--;
        break;
    }
    case S_FOREACH: {
        Node *var = lvalue_of(c, s->a, "For Each");
        Node *coll = check_expr(c, s->b, M_ARG);
        Sym *st;
        if (coll->ty->kind != T_ARRAY && coll->ty->kind != T_VARIANT && coll->ty->kind != T_OBJECT)
            ERR(c, s, "For Each needs an array, collection or object (found %s)", type_name(coll->ty));
        if (coll->ty->kind == T_ARRAY && coll->ty->elem->kind == T_UDT)
            ERR(c, s, "For Each over an array of user-defined types is not supported");
        if (var->ty->kind == T_UDT || var->ty->kind == T_ARRAY) ERR(c, s, "For Each variable must be a Variant, object or simple type");
        s->a = var;
        s->b = coll;
        st = new_temp(c, &ty_object, s);
        s->sym = st;
        c->in_loop_for++;
        check_block(c, &s->list);
        c->in_loop_for--;
        break;
    }
    case S_DO:
        if (s->a) s->a = conv_to_bool_cond(c, s->a);
        c->in_loop_do++;
        check_block(c, &s->list);
        c->in_loop_do--;
        break;
    case S_EXIT:
        switch (s->op) {
        case EXIT_FOR: case EXIT_DO:
            if (!in_loop(c, s->op)) ERR(c, s, "Exit %s outside a %s loop", s->op == EXIT_FOR ? "For" : "Do", s->op == EXIT_FOR ? "For" : "Do");
            break;
        case EXIT_SUB:
            if (c->proc->kind != PK_SUB && c->proc->kind != PK_MAIN) ERR(c, s, "Exit Sub outside a Sub");
            break;
        case EXIT_FUNCTION:
            if (c->proc->kind != PK_FUNCTION) ERR(c, s, "Exit Function outside a Function");
            break;
        case EXIT_PROPERTY:
            if (c->proc->kind != PK_PGET && c->proc->kind != PK_PLET && c->proc->kind != PK_PSET) ERR(c, s, "Exit Property outside a Property");
            break;
        }
        break;
    case S_GOTO: case S_GOSUB:
        s->sym = find_label(c, s, s->name);
        if (s->kind == S_GOSUB) c->proc->has_gosub = 1;
        break;
    case S_RETURN:
        c->proc->has_gosub = 1;
        break;
    case S_LABEL:
        break;
    case S_ONGOTO:
        s->a = coerce(c, check_value(c, s->a), &ty_long);
        for (i = 0; i < s->list.n; i++) s->list.v[i]->sym = find_label(c, s->list.v[i], s->list.v[i]->name);
        if (s->op) c->proc->has_gosub = 1;
        break;
    case S_ONERROR:
        c->proc->has_onerror = 1;
        if (s->op == ONERR_GOTO) s->sym = find_label(c, s, s->name);
        if (s->op == ONERR_RESUMENEXT) c->proc->has_resume = 1;
        break;
    case S_RESUME:
        c->proc->has_onerror = 1;
        if (s->op == RES_LABEL) s->sym = find_label(c, s, s->name);
        else c->proc->has_resume = 1;
        break;
    case S_PRINT:
        if (s->a) s->a = coerce(c, check_value(c, s->a), &ty_long);
        for (i = 0; i < s->list.n; i++) {
            Node *it = s->list.v[i];
            if (!it->a) continue;
            it->a = check_value(c, it->a);
            if (it->ival != PI_EXPR) it->a = coerce(c, it->a, &ty_long);
            else if (it->a->ty->kind == T_UDT || it->a->ty->kind == T_ARRAY) ERR(c, it, "cannot print %s", type_name(it->a->ty));
            else if (it->a->ty->kind == T_OBJECT) it->a = coerce(c, it->a, &ty_variant);
        }
        break;
    case S_WRITE:
        s->a = coerce(c, check_value(c, s->a), &ty_long);
        for (i = 0; i < s->list.n; i++) s->list.v[i] = coerce(c, check_value(c, s->list.v[i]), &ty_variant);
        break;
    case S_INPUT:
        if (s->a) s->a = coerce(c, check_value(c, s->a), &ty_long);
        if (s->b) s->b = check_value(c, s->b);
        for (i = 0; i < s->list.n; i++) {
            Node *t = lvalue_of(c, s->list.v[i], "Input");
            if (t->ty->kind == T_UDT || t->ty->kind == T_ARRAY || t->ty->kind == T_OBJECT) ERR(c, t, "cannot Input into %s", type_name(t->ty));
            s->list.v[i] = t;
        }
        break;
    case S_LINEINPUT:
        if (s->a) s->a = coerce(c, check_value(c, s->a), &ty_long);
        if (s->b) s->b = check_value(c, s->b);
        s->c = lvalue_of(c, s->c, "Line Input");
        if (s->c->ty->kind != T_STRING && s->c->ty->kind != T_VARIANT) ERR(c, s, "Line Input needs a String or Variant variable");
        break;
    case S_OPEN:
        s->a = coerce(c, check_value(c, s->a), &ty_string);
        s->b = coerce(c, check_value(c, s->b), &ty_long);
        if (s->c) s->c = coerce(c, check_value(c, s->c), &ty_long);
        break;
    case S_CLOSE:
        for (i = 0; i < s->list.n; i++) s->list.v[i] = coerce(c, check_value(c, s->list.v[i]), &ty_long);
        break;
    case S_GET: case S_PUT:
        s->a = coerce(c, check_value(c, s->a), &ty_long);
        if (s->b) s->b = coerce(c, check_value(c, s->b), &ty_long);
        if (s->kind == S_GET) s->c = lvalue_of(c, s->c, "Get");
        else {
            Node *v = check_expr(c, s->c, M_ARG);
            if (!is_lvalue(v)) {
                /* put an expression: through a temp */
                Sym *t = new_temp(c, v->ty->kind == T_VOID ? &ty_variant : v->ty, s);
                Node *as = mk_stmt(S_LET, s);
                as->a = mk_var(s, t);
                as->b = v;
                nl_push(out, as);
                v = mk_var(s, t);
            }
            s->c = v;
        }
        if (s->c->ty->kind == T_OBJECT) ERR(c, s, "cannot Get/Put an object");
        break;
    case S_SEEK:
        s->a = coerce(c, check_value(c, s->a), &ty_long);
        s->b = coerce(c, check_value(c, s->b), &ty_long);
        break;
    case S_END: case S_STOP: case S_NOP:
        break;
    case S_ERROR:
        s->a = coerce(c, check_value(c, s->a), &ty_long);
        break;
    case S_NAME:
        s->a = coerce(c, check_value(c, s->a), &ty_string);
        s->b = coerce(c, check_value(c, s->b), &ty_string);
        break;
    case S_LSET: case S_RSET: {
        Node *t = lvalue_of(c, s->a, s->kind == S_LSET ? "LSet" : "RSet");
        Node *v = check_value(c, s->b);
        Node *call = node_new(E_BUILTIN, s->file, s->line, s->col);
        if (t->ty->kind != T_STRING) { ERR(c, s, "LSet/RSet needs a String variable"); return; }
        call->bi = builtin_find(s->kind == S_LSET ? "__lset" : "__rset");
        call->ty = &ty_string;
        nl_push(&call->list, t);
        nl_push(&call->list, coerce(c, v, &ty_string));
        s->kind = S_LET;
        s->a = t;
        s->b = call;
        nl_push(out, s);
        return;
    }
    case S_MIDASSIGN:
        break;
    case S_WITH: {
        Node *w = check_expr(c, s->a, M_ARG);
        Sym *t;
        if (w->ty->kind == T_UDT) {
            if (!is_lvalue(w)) ERR(c, s, "With on a user-defined type needs a variable");
            t = new_temp(c, w->ty, s);
            t->byref = 1;       /* holds the address of the record */
        } else if (w->ty->kind == T_OBJECT || w->ty->kind == T_VARIANT) {
            t = new_temp(c, w->ty, s);
        } else {
            ERR(c, s, "With needs an object or a user-defined type (found %s)", type_name(w->ty));
            t = new_temp(c, &ty_variant, s);
        }
        s->a = w;
        s->sym = t;
        {
            Node *ref = mk_var(s, t);
            nl_push(&c->withs, ref);
            check_block(c, &s->list);
            c->withs.n--;
        }
        break;
    }
    case S_RAISEEVENT: {
        Proc *ev = NULL;
        int k;
        if (!c->cls) { ERR(c, s, "RaiseEvent is only allowed in a class module"); return; }
        for (k = 0; k < c->cls->nevents; k++)
            if (name_eq(c->cls->events[k]->name, s->name)) ev = c->cls->events[k];
        if (!ev) { ERR(c, s, "event '%s' is not declared in class '%s'", s->name, c->cls->name); return; }
        if (s->list.n > ev->nparams) { ERR(c, s, "too many arguments for event '%s'", ev->name); return; }
        s->proc = ev;
        for (k = 0; k < ev->nparams; k++) {
            Param *pa = &ev->params[k];
            Node *a = k < s->list.n ? s->list.v[k] : NULL;
            Node *v;
            if (!a || a->kind == E_MISSING) {
                if (!pa->optional) ERR(c, s, "argument '%s' of event '%s' is missing", pa->name, ev->name);
                v = node_new(E_MISSING, s->file, s->line, s->col);
                v->ty = &ty_variant;
                if (k < s->list.n) s->list.v[k] = v; else nl_push(&s->list, v);
                continue;
            }
            v = check_expr(c, a, M_ARG);
            if (pa->byref && is_lvalue(v) && type_eq(v->ty, pa->ty)) v->flags |= NF_BYREF;
            else v = coerce(c, v, pa->ty);
            s->list.v[k] = v;
        }
        break;
    }
    default:
        ERR(c, s, "statement not supported here");
        return;
    }
    nl_push(out, s);
}

/* ---------- procedure bodies ---------- */

static void check_proc(Program *p, Proc *pr)
{
    Ctx cx, *c = &cx;
    int i;
    memset(c, 0, sizeof cx);
    c->prog = p;
    c->mod = pr->mod;
    c->cls = pr->cls;
    c->proc = pr;
    pr->scope = scope_new(pr->mod->scope);
    c->scope = pr->scope;
    for (i = 0; i < pr->nparams; i++) {
        Param *pa = &pr->params[i];
        Sym *s = new_sym(SK_VAR, pa->name, pr->decl);
        s->line = pa->line;
        s->col = pa->col;
        s->ty = pa->ty;
        s->storage = ST_PARAM;
        s->byref = pa->byref;
        s->optional = pa->optional;
        s->is_param_array = pa->paramarray;
        s->mod = pr->mod;
        pa->sym = s;
        if (scope_find_local(pr->scope, pa->name)) ERR(c, pr->decl, "duplicate parameter '%s'", pa->name);
        scope_add(pr->scope, s);
        proc_local_add(pr, s);
    }
    if (pr->ret) {
        Sym *r = new_sym(SK_VAR, pr->name, pr->decl);
        r->ty = pr->ret;
        r->storage = ST_LOCAL;
        r->is_retvar = 1;
        r->mod = pr->mod;
        pr->retvar = r;
        scope_add(pr->scope, r);
        proc_local_add(pr, r);
    }
    collect_labels(c, &pr->body);
    check_block(c, &pr->body);
}

/* ---------- program ---------- */

static Module *find_module(Program *p, const char *name)
{
    int i;
    for (i = 0; i < p->nmods; i++) if (name_eq(p->mods[i]->name, name)) return p->mods[i];
    return NULL;
}

/* VB's predefined constants */
static void add_vb_constants(Program *p)
{
    static const struct { const char *name; int type; long long i; const char *s; } k[] = {
        {"vbCrLf", T_STRING, 0, "\r\n"}, {"vbNewLine", T_STRING, 0, "\n"}, {"vbCr", T_STRING, 0, "\r"},
        {"vbLf", T_STRING, 0, "\n"}, {"vbTab", T_STRING, 0, "\t"}, {"vbBack", T_STRING, 0, "\b"},
        {"vbFormFeed", T_STRING, 0, "\f"}, {"vbVerticalTab", T_STRING, 0, "\v"}, {"vbNullString", T_STRING, 0, ""},
        {"vbNullChar", T_STRING, 1, ""},
        {"vbBinaryCompare", T_LONG, 0, 0}, {"vbTextCompare", T_LONG, 1, 0},
        {"vbOKOnly", T_LONG, 0, 0}, {"vbOKCancel", T_LONG, 1, 0}, {"vbAbortRetryIgnore", T_LONG, 2, 0},
        {"vbYesNoCancel", T_LONG, 3, 0}, {"vbYesNo", T_LONG, 4, 0}, {"vbRetryCancel", T_LONG, 5, 0},
        {"vbCritical", T_LONG, 16, 0}, {"vbQuestion", T_LONG, 32, 0}, {"vbExclamation", T_LONG, 48, 0},
        {"vbInformation", T_LONG, 64, 0}, {"vbDefaultButton1", T_LONG, 0, 0}, {"vbDefaultButton2", T_LONG, 256, 0},
        {"vbDefaultButton3", T_LONG, 512, 0}, {"vbOK", T_LONG, 1, 0}, {"vbCancel", T_LONG, 2, 0},
        {"vbAbort", T_LONG, 3, 0}, {"vbRetry", T_LONG, 4, 0}, {"vbIgnore", T_LONG, 5, 0}, {"vbYes", T_LONG, 6, 0},
        {"vbNo", T_LONG, 7, 0},
        {"sockClosed", T_LONG, 0, 0}, {"sockOpen", T_LONG, 1, 0}, {"sockListening", T_LONG, 2, 0},
        {"sockConnecting", T_LONG, 6, 0}, {"sockConnected", T_LONG, 7, 0}, {"sockClosing", T_LONG, 8, 0},
        {"sockError", T_LONG, 9, 0},
        {"logDebug", T_LONG, 10, 0}, {"logInfo", T_LONG, 20, 0}, {"logWarning", T_LONG, 30, 0},
        {"logError", T_LONG, 40, 0}, {"logFatal", T_LONG, 50, 0}, {"logOff", T_LONG, 100, 0},
        {"zipZlib", T_LONG, 0, 0}, {"zipGzip", T_LONG, 1, 0}, {"zipDeflate", T_LONG, 2, 0}, {"zipAuto", T_LONG, 3, 0},
        {"vbEmpty", T_LONG, 0, 0}, {"vbNull", T_LONG, 1, 0}, {"vbInteger", T_LONG, 2, 0}, {"vbLong", T_LONG, 3, 0},
        {"vbSingle", T_LONG, 4, 0}, {"vbDouble", T_LONG, 5, 0}, {"vbCurrency", T_LONG, 6, 0}, {"vbDate", T_LONG, 7, 0},
        {"vbString", T_LONG, 8, 0}, {"vbObject", T_LONG, 9, 0}, {"vbError", T_LONG, 10, 0}, {"vbBoolean", T_LONG, 11, 0},
        {"vbVariant", T_LONG, 12, 0}, {"vbDecimal", T_LONG, 14, 0}, {"vbByte", T_LONG, 17, 0}, {"vbUserDefinedType", T_LONG, 36, 0},
        {"vbArray", T_LONG, 8192, 0},
        {"vbSunday", T_LONG, 1, 0}, {"vbMonday", T_LONG, 2, 0}, {"vbTuesday", T_LONG, 3, 0},
        {"vbWednesday", T_LONG, 4, 0}, {"vbThursday", T_LONG, 5, 0}, {"vbFriday", T_LONG, 6, 0},
        {"vbSaturday", T_LONG, 7, 0}, {"vbUseSystemDayOfWeek", T_LONG, 0, 0},
        {"vbNormal", T_LONG, 0, 0}, {"vbReadOnly", T_LONG, 1, 0}, {"vbHidden", T_LONG, 2, 0},
        {"vbSystem", T_LONG, 4, 0}, {"vbVolume", T_LONG, 8, 0}, {"vbDirectory", T_LONG, 16, 0},
        {"vbArchive", T_LONG, 32, 0}, {"vbObjectError", T_LONG, -2147221504LL, 0},
        {"vbBlack", T_LONG, 0, 0}, {"vbRed", T_LONG, 255, 0}, {"vbGreen", T_LONG, 65280, 0},
        {"vbYellow", T_LONG, 65535, 0}, {"vbBlue", T_LONG, 16711680, 0}, {"vbMagenta", T_LONG, 16711935, 0},
        {"vbCyan", T_LONG, 16776960, 0}, {"vbWhite", T_LONG, 16777215, 0},
        {"vbKeyReturn", T_LONG, 13, 0}, {"vbKeyEscape", T_LONG, 27, 0}, {"vbKeySpace", T_LONG, 32, 0},
        {"vbKeyBack", T_LONG, 8, 0}, {"vbKeyTab", T_LONG, 9, 0}, {"vbKeyLeft", T_LONG, 37, 0},
        {"vbKeyUp", T_LONG, 38, 0}, {"vbKeyRight", T_LONG, 39, 0}, {"vbKeyDown", T_LONG, 40, 0},
        {"vbKeyDelete", T_LONG, 46, 0}, {"vbShiftMask", T_LONG, 1, 0}, {"vbCtrlMask", T_LONG, 2, 0},
        {"vbAltMask", T_LONG, 4, 0}, {"vbKeyInsert", T_LONG, 45, 0}, {"vbKeyHome", T_LONG, 36, 0},
        {"vbKeyEnd", T_LONG, 35, 0}, {"vbKeyPageUp", T_LONG, 33, 0}, {"vbKeyPageDown", T_LONG, 34, 0},
        {"vbKeyShift", T_LONG, 16, 0}, {"vbKeyControl", T_LONG, 17, 0}, {"vbKeyMenu", T_LONG, 18, 0},
        {"vbKeyPause", T_LONG, 19, 0}, {"vbKeyCapital", T_LONG, 20, 0}, {"vbKeyClear", T_LONG, 12, 0},
        {"vbKeyMultiply", T_LONG, 106, 0}, {"vbKeyAdd", T_LONG, 107, 0}, {"vbKeySubtract", T_LONG, 109, 0},
        {"vbKeyDecimal", T_LONG, 110, 0}, {"vbKeyDivide", T_LONG, 111, 0},
        {"vbUnchecked", T_LONG, 0, 0}, {"vbChecked", T_LONG, 1, 0}, {"vbGrayed", T_LONG, 2, 0},
        {"vbLeftButton", T_LONG, 1, 0}, {"vbRightButton", T_LONG, 2, 0}, {"vbMiddleButton", T_LONG, 4, 0},
        {"vbKeyLShift", T_LONG, 160, 0}, {"vbKeyRShift", T_LONG, 161, 0}, {"vbKeyLControl", T_LONG, 162, 0},
        {"vbKeyLMenu", T_LONG, 164, 0}, {"vbKeyRMenu", T_LONG, 165, 0}, {"vbKeyLWin", T_LONG, 91, 0},
        {"vbKeyRWin", T_LONG, 92, 0}, {"vbKeyHelp", T_LONG, 47, 0},
        {"vbDefault", T_LONG, 0, 0}, {"vbArrow", T_LONG, 1, 0}, {"vbCrosshair", T_LONG, 2, 0}, {"vbIbeam", T_LONG, 3, 0},
        {"vbHourglass", T_LONG, 11, 0}, {"vbSizeAll", T_LONG, 15, 0},
        {"vbCFText", T_LONG, 1, 0}, {"vbCFBitmap", T_LONG, 2, 0}, {"vbCFMetafile", T_LONG, 3, 0}, {"vbCFDIB", T_LONG, 8, 0},
        {"vbCFPalette", T_LONG, 9, 0}, {"vbCFEMetafile", T_LONG, 14, 0}, {"vbCFFiles", T_LONG, 15, 0}, {"vbCFRTF", T_LONG, -16639, 0},
        {"vbFormControlMenu", T_LONG, 0, 0}, {"vbFormCode", T_LONG, 1, 0}, {"vbAppWindows", T_LONG, 2, 0}, {"vbAppTaskManager", T_LONG, 3, 0},
        {"vbModal", T_LONG, 1, 0}, {"vbModeless", T_LONG, 0, 0}, {"vbMinimized", T_LONG, 1, 0},
        {"cdlOFNAllowMultiselect", T_LONG, 0x200, 0}, {"cdlOFNOverwritePrompt", T_LONG, 2, 0},
        {"cdlOFNFileMustExist", T_LONG, 0x1000, 0}, {"cdlOFNPathMustExist", T_LONG, 0x800, 0},
        {"cdlOFNNoChangeDir", T_LONG, 8, 0}, {"cdlCancel", T_LONG, 32755, 0},
        {"flexAlignLeft", T_LONG, 0, 0}, {"flexAlignRight", T_LONG, 1, 0}, {"flexAlignCenter", T_LONG, 2, 0},
        {NULL, 0, 0, 0}
    };
    int i;
    for (i = 0; k[i].name; i++) {
        Sym *s = new_sym(SK_CONST, k[i].name, NULL);
        s->is_public = 1;
        s->cv.type = k[i].type;
        if (k[i].type == T_STRING) {
            if (strcmp(k[i].name, "vbNullChar") == 0) { s->cv.s = xstrndup("\0", 1); s->cv.slen = 1; }
            else { s->cv.s = xstrdup(k[i].s); s->cv.slen = (int)strlen(k[i].s); }
        } else s->cv.i = k[i].i;
        s->ty = type_prim(k[i].type);
        scope_add(p->global, s);
    }
    /* vbKeyA..Z, vbKey0..9, vbKeyF1..F16, vbKeyNumpad0..9 */
    for (i = 0; i < 26 + 10 + 16 + 10; i++) {
        char nm[24];
        long v;
        Sym *s;
        if (i < 26) { snprintf(nm, sizeof nm, "vbKey%c", 'A' + i); v = 65 + i; }
        else if (i < 36) { snprintf(nm, sizeof nm, "vbKey%d", i - 26); v = 48 + i - 26; }
        else if (i < 52) { snprintf(nm, sizeof nm, "vbKeyF%d", i - 35); v = 112 + i - 36; }
        else { snprintf(nm, sizeof nm, "vbKeyNumpad%d", i - 52); v = 96 + i - 52; }
        s = new_sym(SK_CONST, xstrdup(nm), NULL);
        s->is_public = 1;
        s->cv.type = T_LONG;
        s->cv.i = v;
        s->ty = type_prim(T_LONG);
        scope_add(p->global, s);
    }
}

/* an event of a registered (runtime or extension) class; np -1 = parameters unknown */
static void add_reg_event(ClassInfo *rc, const char *name, int np)
{
    Proc *pr = (Proc *)xcalloc(1, sizeof(Proc));
    pr->name = xstrdup(name);
    pr->kind = PK_EVENT;
    pr->event_index = rc->nevents;
    pr->is_public = 1;
    pr->vslot = -1;
    pr->nparams = np < 0 ? 0 : np;
    pr->ev_np = np;
    rc->events = (Proc **)xrealloc(rc->events, sizeof(Proc *) * (size_t)(rc->nevents + 1));
    rc->events[rc->nevents++] = pr;
}

static void check_handlers(Program *p, Sym *s)
{
    ClassInfo *src = s->ty && s->ty->kind == T_OBJECT ? s->ty->cls : NULL;
    int k, j;
    if (!src || !src->xcls || !s->mod) return;
    for (k = 0; k < src->nevents; k++) {
        Proc *ev = src->events[k];
        char *hn = xsprintf("%s_%s", s->name, ev->name);
        for (j = 0; j < s->mod->nprocs; j++) {
            Proc *h = s->mod->procs[j];
            if (h->kind == PK_SUB && name_eq(h->name, hn) && ev->ev_np >= 0 && h->nparams != ev->ev_np)
                diag(p, h->file, h->line, 1, "%s handles the event %s.%s, which has %d parameter%s, not %d",
                     h->name, src->name, ev->name, ev->ev_np, ev->ev_np == 1 ? "" : "s", h->nparams);
        }
        free(hn);
    }
}

/* a module-level declaration with the name of another module's Public hides it in this module
   (legal in VB, names are case-insensitive): a warning, it is easy to do by accident */
static void warn_shadows(Program *p)
{
    int i, b;
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        Scope *sc = m->scope;
        if (!sc) continue;
        for (b = 0; b < sc->cap; b++) {
            ScopeEnt *en;
            for (en = sc->tab[b]; en; en = en->next) {
                Sym *s = en->sym, *g;
                if (s->is_public || (s->kind != SK_VAR && s->kind != SK_CONST && s->kind != SK_PROC)) continue;
                g = scope_find_local(p->global, s->name);
                if (!g || g == s || !g->is_public || !g->mod || g->mod == m) continue;
                if (g->kind != SK_VAR && g->kind != SK_CONST && g->kind != SK_PROC) continue;
                diag_warn(p, s->file, s->line, s->col, "'%s' hides the Public '%s' of module %s here", s->name, g->name, g->mod->name);
            }
        }
    }
}

int sema_program(Program *p)
{
    int i;
    ClassInfo *coll;
    add_vb_constants(p);
    /* built-in classes */
    coll = (ClassInfo *)xcalloc(1, sizeof(ClassInfo));
    coll->name = xstrdup("Collection");
    coll->builtin = 1;
    coll->rt_new = "bb_collection_new";
    {
        Sym *s = new_sym(SK_CLASS, coll->name, NULL);
        s->cls = coll;
        s->is_public = 1;
        scope_add(p->global, s);
    }
    /* modules and classes */
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        Sym *s;
        m->scope = scope_new(p->global);
        m->index = i;
        if (m->is_class) {
            ClassInfo *cls = (ClassInfo *)xcalloc(1, sizeof(ClassInfo));
            cls->name = m->name;
            cls->mod = m;
            cls->index = p->nclasses;
            m->cls = cls;
            p->classes = (ClassInfo **)xrealloc(p->classes, sizeof(ClassInfo *) * (size_t)(p->nclasses + 1));
            p->classes[p->nclasses++] = cls;
            s = new_sym(SK_CLASS, m->name, NULL);
            s->cls = cls;
        } else {
            s = new_sym(SK_MODULE, m->name, NULL);
        }
        s->mod = m;
        s->is_public = 1;
        {
            Sym *old = scope_find_local(p->global, m->name);
            if (old && old->kind == SK_CLASS && old->cls && old->cls->builtin)
                diag(p, m->file, 1, 1, "the %s '%s' hides the built-in class %s: rename the %s", m->is_class ? "class" : "module",
                     m->name, old->cls->name, m->is_class ? "class" : "module");
            else if (old) diag(p, m->file, 1, 1, "duplicate module or class name '%s'", m->name);
        }
        if (!scope_find_local(p->global, m->name)) scope_add(p->global, s);
        if (m->is_class && m->mainstmts.n)
            diag(p, m->file, m->mainstmts.v[0]->line, m->mainstmts.v[0]->col, "executable statements are not allowed at class module level");
    }
    /* the runtime's own classes as types (Dim e As Engine3D / As Boing.Engine3D): member names
       checked at compile time; a module or class of the program with the same name wins */
    {
        int k, nk = bb_ext_class_count();
        /* extension classes first (Extension= in the project): members from their .bbx */
        for (k = 0; k < p->nxclasses; k++) {
            ExtClass *xc = p->xclasses[k];
            ClassInfo *rc;
            Sym *s;
            if (scope_find_local(p->global, xc->name)) { diag(p, 0, 1, 1, "extension class '%s' clashes with a name of the program", xc->name); continue; }
            rc = (ClassInfo *)xcalloc(1, sizeof(ClassInfo));
            rc->name = xstrdup(xc->name);
            rc->xcls = xc;
            rc->rtcls = NULL;
            rc->index = -1;
            {
                int q;
                for (q = 0; q < xc->nev; q++) add_reg_event(rc, xc->ev[q].name, xc->ev[q].np);
            }
            s = new_sym(SK_CLASS, rc->name, NULL);
            s->cls = rc;
            s->is_public = 1;
            scope_add(p->global, s);
        }
        for (k = 0; k < nk; k++) {
            const char *rn = bb_ext_class_name(k);
            ClassInfo *rc;
            Sym *s;
            Sym *taken = scope_find_local(p->global, rn);
            if ((taken && taken->kind != SK_MODULE) || !bb_runtime_class(rn)) continue;
            rc = (ClassInfo *)xcalloc(1, sizeof(ClassInfo));
            rc->name = xstrdup(rn);
            rc->rtcls = bb_runtime_class(rn);
            rc->index = -1;         /* the VM's CHKCLS finds it by name (emit_bc) */
            {
                const char *const *ev = bb_runtime_class_events(rn);
                for (; ev && *ev; ev++) add_reg_event(rc, *ev, -1);
            }
            if (taken) {
                /* a module with the class's name (dictionary.bas): the name means the module, but
                   after As and New, where a module can't be meant, the built-in class */
                taken->cls = rc;
                continue;
            }
            s = new_sym(SK_CLASS, rc->name, NULL);
            s->cls = rc;
            s->is_public = 1;
            scope_add(p->global, s);
        }
    }
    for (i = 0; i < p->nmods; i++) declare_names(p, p->mods[i]);
    for (i = 0; i < p->nmods; i++) declare_members(p, p->mods[i]);
    for (i = 0; i < p->nmods; i++) resolve_implements(p, p->mods[i]);
    for (i = 0; i < p->nclasses; i++) layout_class(p, p->classes[i]);
    for (i = 0; i < p->nclasses; i++) check_implements(p, p->classes[i]);
    warn_shadows(p);
    /* form controls: module-level Object variables */
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        int k;
        for (k = 0; k < m->ncontrols; k++) {
            Sym *s;
            if (scope_find_local(m->scope, m->form_controls[k])) continue;
            s = new_sym(SK_VAR, m->form_controls[k], NULL);
            s->ty = &ty_object;
            s->storage = ST_GLOBAL;
            s->mod = m;
            s->is_public = 0;
            s->file = m->file;
            s->line = 1;
            scope_add(m->scope, s);
            add_global(p, s);
            /* the form itself is visible from every module: other.Show */
            if (m->form_name && name_eq(m->form_controls[k], m->form_name)) {
                Sym *gg = scope_find_local(p->global, s->name);
                if (!gg) {
                    s->is_public = 1;
                    scope_add(p->global, s);
                } else if (gg->kind == SK_MODULE && gg->mod == m) {
                    /* window name = the module's own name: X.Caption / Load X reach the form */
                    s->is_public = 1;
                    m->form_var = s;
                } else
                    diag(p, m->file, 1, 1, "the form '%s' has the same name as %s '%s'%s%s: rename the window (window name=) or the other",
                         s->name, gg->kind == SK_PROC ? "the procedure" : gg->kind == SK_MODULE ? "the module" : gg->kind == SK_CLASS ? "the class" : "the Public",
                         gg->name, gg->mod && gg->kind != SK_MODULE && gg->kind != SK_CLASS ? " in module " : "",
                         gg->mod && gg->kind != SK_MODULE && gg->kind != SK_CLASS ? gg->mod->name : "");
            }
        }
    }
    /* module main programs */
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        if (m->mainstmts.n) {
            Proc *pr = (Proc *)xcalloc(1, sizeof(Proc));
            pr->name = xstrdup("$main");
            pr->kind = PK_MAIN;
            pr->mod = m;
            pr->body = m->mainstmts;
            pr->line = m->mainstmts.v[0]->line;
            pr->file = m->file;
            pr->vslot = -1;
            pr->defined = 1;
            add_proc(p, pr);
            m->mainproc = pr;
        }
    }
    /* bodies */
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT) continue;
        if (pr->kind != PK_MAIN) pr->body = pr->decl->list2;
        check_proc(p, pr);
    }
    /* WithEvents handlers of a linked extension's class: the parameter count its .bbx gives */
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        if (s->withevents) check_handlers(p, s);
    }
    for (i = 0; i < p->nclasses; i++) {
        int k;
        for (k = 0; k < p->classes[i]->nfields; k++)
            if (p->classes[i]->fields[k]->withevents) check_handlers(p, p->classes[i]->fields[k]);
    }
    /* module variables used only by their module's main program become its locals
     * (fast slots in the VM, registers in C) */
    {
        int k, n = 0;
        for (k = 0; k < p->nglobals; k++) {
            Sym *s = p->globals[k];
            Proc *mp = s->user;
            if (s->storage == ST_GLOBAL && !s->shared && mp && mp->kind == PK_MAIN && mp->mod == s->mod &&
                !s->is_new && !s->withevents && !s->is_public && !s->mod->is_form) {
                s->storage = ST_LOCAL;
                proc_local_add(mp, s);
                continue;
            }
            p->globals[n] = s;
            s->index = n;
            n++;
        }
        p->nglobals = n;
    }
    /* startup */
    if (!p->startup && p->nmods) p->startup = p->mods[0];
    if (p->startup) {
        if (p->startup->mainproc) p->startup_proc = p->startup->mainproc;
        else {
            Sym *s = scope_find(p->startup->scope, "Main");
            if (s && s->kind == SK_PROC && s->proc->kind == PK_SUB) p->startup_proc = s->proc;
            else {
                int k;
                for (k = 0; k < p->nmods && !p->startup_proc; k++) {
                    Sym *t = scope_find_local(p->mods[k]->scope, "Main");
                    if (t && t->kind == SK_PROC && t->proc->kind == PK_SUB && !p->mods[k]->is_class) p->startup_proc = t->proc;
                }
            }
        }
    }
    /* module-level statements run only as the startup module's program */
    for (i = 0; i < p->nmods; i++) {
        Module *m = p->mods[i];
        if (m->mainproc && m->mainproc != p->startup_proc)
            diag_warn(p, m->file, m->mainproc->line, 1,
                      "module-level statements in '%s' never run (only the startup module's do): move them into a Sub", m->name);
    }
    (void)find_module;
    return p->nerrors == 0;
}
