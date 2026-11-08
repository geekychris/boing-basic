/* emit_bc.c - typed AST -> VM bytecode */
#include "bbc.h"
#include "../vm/bytecode.h"

int is_lvalue(Node *e);
#include <stdlib.h>
#include <string.h>

typedef struct Patch { int *v; int n, cap; } Patch;
static void patch_add(Patch *p, int at)
{
    if (p->n == p->cap) { p->cap = p->cap ? p->cap * 2 : 8; p->v = (int *)xrealloc(p->v, sizeof(int) * (size_t)p->cap); }
    p->v[p->n++] = at;
}

typedef struct Loop { int kind; Patch exits; } Loop;

typedef struct E {
    Program *prog;
    VMImage *img;
    Proc *proc;
    VMProc *vp;
    int me;                 /* 1 if slot 0 is Me */
    Loop loops[64];
    int nloops;
    int *label_pc;
    Patch *label_refs;
    Patch exitp;
    int nlines, caplines;
    VMLine *lines;
    int *wev_hidden_global;     /* per program global: hidden sink global index, -1 */
    int **wev_hidden_field;     /* per class: per field: hidden field index, -1 */
    int *wev_of_global;         /* per global: wev index */
    int **wev_of_field;
    int used_keep;              /* statement used the frame's keep-alive slot */
} E;

static int emit_w(E *e, int32_t w)
{
    VMImage *g = e->img;
    if (g->ncode == g->capcode) {
        g->capcode = g->capcode ? g->capcode * 2 : 4096;
        g->code = (int32_t *)xrealloc(g->code, sizeof(int32_t) * (size_t)g->capcode);
    }
    g->code[g->ncode] = w;
    return g->ncode++;
}
static void op0(E *e, int op) { emit_w(e, op); }
static void op1(E *e, int op, int a) { emit_w(e, op); emit_w(e, a); }
static void op2(E *e, int op, int a, int b) { emit_w(e, op); emit_w(e, a); emit_w(e, b); }
static void op3(E *e, int op, int a, int b, int c) { emit_w(e, op); emit_w(e, a); emit_w(e, b); emit_w(e, c); }
static int here(E *e) { return e->img->ncode; }

/* jump with a forward target: returns the operand position */
static int jump(E *e, int op) { emit_w(e, op); return emit_w(e, 0); }
static void set_target(E *e, int at, int target) { e->img->code[at] = target; }
static void patch_all(E *e, Patch *p, int target) { int i; for (i = 0; i < p->n; i++) set_target(e, p->v[i], target); p->n = 0; }

static int add_const(E *e, bb_value v)
{
    VMImage *g = e->img;
    if (g->nconsts == g->capconsts) {
        g->capconsts = g->capconsts ? g->capconsts * 2 : 64;
        g->consts = (bb_value *)xrealloc(g->consts, sizeof(bb_value) * (size_t)g->capconsts);
    }
    g->consts[g->nconsts] = v;
    return g->nconsts++;
}

static int str_const(E *e, const char *s, int len)
{
    int i;
    for (i = 0; i < e->img->nconsts; i++) {
        bb_value *c = &e->img->consts[i];
        if (c->type == BB_STRING && bb_str_len(c->u.s) == len && memcmp(bb_str_ptr(c->u.s), s, (size_t)len) == 0) return i;
    }
    return add_const(e, bb_v_str(bb_str_lit(s, len)));
}

static void line(E *e, Node *s)
{
    if (e->nlines && e->lines[e->nlines - 1].pc == here(e)) { e->lines[e->nlines - 1].line = s->line; return; }
    if (e->nlines == e->caplines) {
        e->caplines = e->caplines ? e->caplines * 2 : 64;
        e->lines = (VMLine *)xrealloc(e->lines, sizeof(VMLine) * (size_t)e->caplines);
    }
    e->lines[e->nlines].pc = here(e);
    e->lines[e->nlines].line = s->line;
    e->nlines++;
}

/* ---------- types and slots ---------- */

static int vt_of(Type *t) { return type_vartype(t); }

static int is_scalar(Type *t)
{
    switch (t->kind) {
    case T_BOOLEAN: case T_BYTE: case T_INTEGER: case T_LONG: case T_SINGLE: case T_DOUBLE:
    case T_CURRENCY: case T_DATE: return 1;
    default: return 0;
    }
}

static int udt_index(Type *t)
{
    if (t->kind == T_UDT) return t->udt->index;
    if (t->kind == T_ARRAY && t->elem->kind == T_UDT) return t->elem->udt->index;
    return -1;
}

static void fill_slot(VMSlot *s, Sym *sym, Type *t)
{
    int i;
    memset(s, 0, sizeof *s);
    s->vt = (uint16_t)vt_of(t);
    s->udt = (int16_t)udt_index(t);
    s->fixlen = (int16_t)(t->kind == T_STRING ? t->fixlen : 0);
    if (sym) {
        s->name = sym->name;
        if (sym->fixed_array) {
            s->ndims = (int16_t)sym->ndims;
            for (i = 0; i < sym->ndims; i++) {
                s->lb[i] = (int32_t)sym->bounds.v[2 * i]->cv.i;
                s->ub[i] = (int32_t)sym->bounds.v[2 * i + 1]->cv.i;
            }
        }
        if ((sym->storage == ST_PARAM && sym->byref) || sym->byref) s->isref = 1;
    }
}

static int slot_of(E *e, Sym *s) { return s->index + e->me; }

static int is_ref_slot(Sym *s) { return (s->storage == ST_PARAM || s->storage == ST_LOCAL) && s->byref; }

/* ---------- expressions ---------- */

static void expr(E *e, Node *n);
static void addr(E *e, Node *n);
static void stmt(E *e, Node *s);

static void load_var(E *e, Sym *s)
{
    Type *t = s->ty;
    int vt = vt_of(t);
    switch (s->storage) {
    case ST_LOCAL: case ST_PARAM:
        if (is_ref_slot(s)) { op2(e, I_LDR, slot_of(e, s), vt); return; }
        if (is_scalar(t)) op1(e, I_LDL, slot_of(e, s));
        else if (t->kind == T_STRING) op1(e, I_LDLS, slot_of(e, s));
        else op1(e, I_LDLV, slot_of(e, s));
        return;
    case ST_GLOBAL: case ST_STATIC:
        if (is_scalar(t)) op1(e, I_LDG, s->index);
        else if (t->kind == T_STRING) op1(e, I_LDGS, s->index);
        else op1(e, I_LDGV, s->index);
        return;
    case ST_FIELD:
        op1(e, is_scalar(t) ? I_LDF : I_LDFV, s->index);
        return;
    }
}

/* value on the stack -> variable (not UDTs, see assign) */
static void store_var(E *e, Sym *s)
{
    Type *t = s->ty;
    switch (s->storage) {
    case ST_LOCAL: case ST_PARAM:
        if (is_ref_slot(s)) { op2(e, I_STR, slot_of(e, s), vt_of(t)); return; }
        if (is_scalar(t)) op1(e, I_STL, slot_of(e, s));
        else if (t->kind == T_STRING) op1(e, I_STLS, slot_of(e, s));
        else op1(e, I_STLV, slot_of(e, s));
        return;
    case ST_GLOBAL: case ST_STATIC:
        if (is_scalar(t)) op1(e, I_STG, s->index);
        else if (t->kind == T_STRING) op1(e, I_STGS, s->index);
        else op1(e, I_STGV, s->index);
        return;
    case ST_FIELD:
        op1(e, is_scalar(t) ? I_STF : I_STFV, s->index);
        return;
    }
}

static void addr(E *e, Node *n)
{
    switch (n->kind) {
    case E_VAR: {
        Sym *s = n->sym;
        int vt = vt_of(s->ty);
        switch (s->storage) {
        case ST_LOCAL: case ST_PARAM:
            if (is_ref_slot(s)) op1(e, I_LDL, slot_of(e, s));
            else op2(e, I_LADDR, slot_of(e, s), vt);
            return;
        case ST_GLOBAL: case ST_STATIC:
            op2(e, I_GADDR, s->index, vt);
            return;
        case ST_FIELD:
            op2(e, I_FADDR, s->index, vt);
            return;
        }
        return;
    }
    case E_INDEX: {
        int i;
        if (!is_lvalue(n->a)) e->used_keep = 1;
        addr(e, n->a);
        for (i = 0; i < n->list.n; i++) expr(e, n->list.v[i]);
        op1(e, I_ELEM, n->list.n);
        return;
    }
    case E_FIELD:
        if (!is_lvalue(n->a)) e->used_keep = 1;
        if (n->a->kind == E_VAR || n->a->kind == E_INDEX || n->a->kind == E_FIELD || n->a->kind == E_MFIELD) addr(e, n->a);
        else expr(e, n->a);
        op2(e, I_UFIELD, n->udt->index, n->field);
        return;
    case E_MFIELD:
        e->used_keep = 1;
        expr(e, n->a);
        op3(e, I_MFIELD, n->cls->index, n->sym->index, vt_of(n->ty));
        return;
    case E_ME:
        op2(e, I_LADDR, 0, BB_OBJECT);
        return;
    default:
        /* an rvalue: the VM keeps it in a temporary and passes its address */
        expr(e, n);
        return;
    }
}

static void push_const(E *e, Node *n)
{
    CVal *v = &n->cv;
    bb_value k;
    if (v->is_nothing || (n->ty->kind == T_OBJECT)) { op0(e, I_PUSHNOTHING); return; }
    if (v->is_null) { op0(e, I_PUSHNULL); return; }
    if (v->is_empty) { op0(e, I_PUSHEMPTY); return; }
    switch (v->type) {
    case T_INTEGER: op1(e, I_PUSHI, (int32_t)v->i); return;
    case T_LONG: op1(e, I_PUSHL, (int32_t)v->i); return;
    case T_BOOLEAN: op1(e, I_PUSHB, v->i ? -1 : 0); return;
    case T_BYTE: k = bb_v_byte((bb_byte)v->i); break;
    case T_SINGLE: k = bb_v_single((float)v->d); break;
    case T_DOUBLE: k = bb_v_double(v->d); break;
    case T_DATE: k = bb_v_date(v->d); break;
    case T_CURRENCY: k = bb_v_cur((bb_cur)(v->d * 10000.0 + (v->d >= 0 ? 0.5 : -0.5))); break;
    case T_STRING: op1(e, I_PUSHK, str_const(e, v->s, v->slen)); return;
    default: op0(e, I_PUSHEMPTY); return;
    }
    op1(e, I_PUSHK, add_const(e, k));
}

static int arith_op(int op, int kind)
{
#define AR(o, b, i, l, f, d, c) case o: switch (kind) { case T_BYTE: return b; case T_INTEGER: case T_BOOLEAN: return i; case T_LONG: return l; case T_SINGLE: return f; case T_DOUBLE: return d; case T_CURRENCY: return c; default: return -1; }
    switch (op) {
    AR(OP_ADD, I_ADD_B, I_ADD_I, I_ADD_L, I_ADD_F, I_ADD_D, I_ADD_C)
    AR(OP_SUB, I_SUB_B, I_SUB_I, I_SUB_L, I_SUB_F, I_SUB_D, I_SUB_C)
    AR(OP_MUL, I_MUL_B, I_MUL_I, I_MUL_L, I_MUL_F, I_MUL_D, I_MUL_C)
    default: return -1;
    }
#undef AR
}

static int cmp_code(int op)
{
    switch (op) {
    case OP_EQ: return BB_CMP_EQ;
    case OP_NE: return BB_CMP_NE;
    case OP_LT: return BB_CMP_LT;
    case OP_GT: return BB_CMP_GT;
    case OP_LE: return BB_CMP_LE;
    default: return BB_CMP_GE;
    }
}

static int is_cmp(int op) { return op >= OP_EQ && op <= OP_GE; }

static int varith_code(int op)
{
    switch (op) {
    case OP_ADD: return VA_ADD; case OP_SUB: return VA_SUB; case OP_MUL: return VA_MUL;
    case OP_DIV: return VA_DIV; case OP_IDIV: return VA_IDIV; case OP_MOD: return VA_MOD;
    case OP_POW: return VA_POW; case OP_AND: return VA_AND; case OP_OR: return VA_OR;
    case OP_XOR: return VA_XOR; case OP_EQV: return VA_EQV; case OP_IMP: return VA_IMP;
    default: return -1;
    }
}

static int logic_code(int op)
{
    switch (op) {
    case OP_AND: return LG_AND; case OP_OR: return LG_OR; case OP_XOR: return LG_XOR;
    case OP_EQV: return LG_EQV; default: return LG_IMP;
    }
}

static void binop(E *e, Node *n)
{
    Type *ot = n->a->ty;
    int k;
    expr(e, n->a);
    expr(e, n->b);
    if (n->ty->kind == T_VARIANT) {
        if (is_cmp(n->op)) { op2(e, I_VCMP, cmp_code(n->op), n->text); return; }
        if (n->op == OP_CAT) { op0(e, I_VCAT); return; }
        op1(e, I_VARITH, varith_code(n->op));
        return;
    }
    switch (n->op) {
    case OP_ADD: case OP_SUB: case OP_MUL:
        if (n->ty->kind == T_DATE) { op0(e, n->op == OP_SUB ? I_SUB_DT : I_ADD_DT); if (n->op == OP_MUL) op1(e, I_CVT, BB_DATE); return; }
        k = arith_op(n->op, n->ty->kind);
        op0(e, k);
        return;
    case OP_DIV: op0(e, n->ty->kind == T_SINGLE ? I_DIV_F : I_DIV_D); return;
    case OP_POW: op0(e, I_POW_D); return;
    case OP_IDIV: case OP_MOD:
        if (n->ty->kind == T_LONG) op0(e, n->op == OP_IDIV ? I_IDIV_L : I_MOD_L);
        else {
            op0(e, n->op == OP_IDIV ? I_IDIV_I : I_MOD_I);
            if (n->ty->kind == T_BYTE) op1(e, I_CVT, BB_BYTE);
        }
        return;
    case OP_CAT: op0(e, I_CAT); return;
    case OP_LIKE: op1(e, I_LIKE, n->text); return;
    case OP_IS: op0(e, I_IS); return;
    case OP_AND: case OP_OR: case OP_XOR: case OP_EQV: case OP_IMP:
        op2(e, I_LOGIC, logic_code(n->op), vt_of(n->ty));
        return;
    default:
        if (is_cmp(n->op)) {
            switch (ot->kind) {
            case T_STRING: op2(e, I_CMP_S, cmp_code(n->op), n->text); return;
            case T_LONG: op1(e, I_CMP_L, cmp_code(n->op)); return;
            case T_BOOLEAN: case T_BYTE: case T_INTEGER: op1(e, I_CMP_I, cmp_code(n->op)); return;
            case T_CURRENCY: op1(e, I_CMP_C, cmp_code(n->op)); return;
            default: op1(e, I_CMP_D, cmp_code(n->op)); return;
            }
        }
    }
}

static void unop(E *e, Node *n)
{
    expr(e, n->a);
    if (n->ty->kind == T_VARIANT) { op0(e, n->op == OP_NEG ? I_VNEG : I_VNOT); return; }
    if (n->op == OP_NEG) {
        switch (n->ty->kind) {
        case T_INTEGER: op0(e, I_NEG_I); return;
        case T_LONG: op0(e, I_NEG_L); return;
        case T_SINGLE: op0(e, I_NEG_F); return;
        case T_CURRENCY: op0(e, I_NEG_C); return;
        case T_DATE: op0(e, I_NEG_D); op1(e, I_CVT, BB_DATE); return;
        default: op0(e, I_NEG_D); return;
        }
    }
    op1(e, I_NOT, vt_of(n->ty));
}

static void conv(E *e, Node *n)
{
    Type *from = n->a->ty, *to = n->ty;
    expr(e, n->a);
    if (to->kind == T_VARIANT) return;
    if (to->kind == T_ARRAY) { op1(e, I_CVTARR, vt_of(to->elem)); return; }
    if (to->kind == T_OBJECT) {
        if (from->kind != T_OBJECT) op1(e, I_CVT, BB_OBJECT);
        if (to->cls && !to->cls->builtin) op1(e, I_CHKCLS, to->cls->index);
        return;
    }
    if (type_eq(from, to) && !(to->kind == T_STRING && to->fixlen)) return;
    if (from->kind != to->kind) op1(e, I_CVT, vt_of(to));
    if (to->kind == T_STRING && to->fixlen) op1(e, I_CVTFIX, to->fixlen);
}

static void args_for_params(E *e, Node *n, Proc *pr)
{
    int i;
    for (i = 0; i < n->list.n; i++) {
        Node *a = n->list.v[i];
        if (a->flags & NF_BYREF) addr(e, a);
        else if (i < pr->nparams && pr->params[i].byref && (a->ty->kind == T_UDT)) addr(e, a);
        else expr(e, a);
    }
}

static void call(E *e, Node *n)
{
    Proc *pr = n->proc;
    if (pr->kind == PK_DECLARE) {
        int i;
        for (i = 0; i < n->list.n; i++) {
            Node *a = n->list.v[i];
            if (a->flags & NF_BYREF) addr(e, a); else expr(e, a);
        }
        op2(e, I_CALLD, pr->index, n->list.n | (pr->ret ? 0x10000 : 0));
        if (pr->ret && pr->ret->kind != T_LONG && pr->ret->kind != T_VARIANT) op1(e, I_CVT, vt_of(pr->ret));
        return;
    }
    if (pr->cls) op1(e, I_LDLV, 0);       /* Me */
    args_for_params(e, n, pr);
    op1(e, I_CALL, pr->index);
}

static void mcall(E *e, Node *n)
{
    Proc *pr = n->proc;
    expr(e, n->a);
    args_for_params(e, n, pr);
    if (pr->vslot < 0 || !pr->cls->is_interface) op3(e, I_CALLM, pr->cls->index, -1 - pr->index, n->list.n);
    else op3(e, I_CALLM, pr->cls->index, pr->vslot, n->list.n);
}

static void builtin(E *e, Node *n)
{
    const Builtin *b = &builtins[n->bi];
    int i;
    for (i = 0; i < n->list.n; i++) {
        Node *a = n->list.v[i];
        char pc = (b->flags & BIF_VARARGS) ? (i == 0 && b->params[0] ? b->params[0] : 'v') : b->params[i];
        if (pc == 'a' && (a->kind == E_VAR || a->kind == E_FIELD || a->kind == E_MFIELD || a->kind == E_INDEX)) addr(e, a);
        else expr(e, a);
    }
    for (i = 0; i < n->list2.n; i++) { expr(e, n->list2.v[i]); op0(e, I_POP); }
    op3(e, I_CALLB, n->bi, n->list.n, b->ret != T_VOID);
}

static void late_call(E *e, Node *n)
{
    int i;
    if (n->name[0] == 0 && (n->argc_kind & (BB_INV_GET | BB_INV_METHOD)) && n->a->ty->kind == T_VARIANT) {
        expr(e, n->a);
        for (i = 0; i < n->list.n; i++) expr(e, n->list.v[i]);
        op1(e, I_VINDEX, n->list.n);
        return;
    }
    expr(e, n->a);
    for (i = 0; i < n->list.n; i++) expr(e, n->list.v[i]);
    op3(e, I_INVOKE, str_const(e, n->name, (int)strlen(n->name)), n->argc_kind, n->list.n);
}

static void expr(E *e, Node *n)
{
    switch (n->kind) {
    case E_CONST: push_const(e, n); return;
    case E_VAR: load_var(e, n->sym); return;
    case E_INDEX: case E_FIELD: case E_MFIELD:
        addr(e, n);
        op1(e, I_LDIND, vt_of(n->ty));
        return;
    case E_CONV: conv(e, n); return;
    case E_BIN: binop(e, n); return;
    case E_UN: unop(e, n); return;
    case E_CALL: call(e, n); return;
    case E_MCALL: mcall(e, n); return;
    case E_BUILTIN: builtin(e, n); return;
    case E_LATE: late_call(e, n); return;
    case E_NEW:
        if (n->cls->builtin) op0(e, I_NEWCOLL);
        else op1(e, I_NEW, n->cls->index);
        return;
    case E_TYPEOF:
        expr(e, n->a);
        op1(e, I_TYPEOF, n->cls ? (n->cls->builtin ? -1 : n->cls->index) : -2);
        return;
    case E_ME: op1(e, I_LDLV, 0); return;
    case E_MISSING: op0(e, I_PUSHMISSING); return;
    case E_ARRAYLIT: {
        int i;
        for (i = 0; i < n->list.n; i++) expr(e, n->list.v[i]);
        op1(e, I_ARRLIT, n->list.n);
        return;
    }
    case E_ERRPROP:
        switch (n->op) {
        case 1: op1(e, I_ERROP, EO_NUMBER); return;
        case 2: op1(e, I_ERROP, EO_DESC); return;
        case 3: op1(e, I_ERROP, EO_SOURCE); return;
        case 4: {
            int i;
            for (i = 0; i < 3; i++) expr(e, n->list.v[i]);
            op1(e, I_ERROP, EO_RAISE);
            return;
        }
        case 5: op1(e, I_ERROP, EO_CLEAR); return;
        case 7: op1(e, I_PUSHK, str_const(e, "", 0)); return;
        default: op1(e, I_PUSHL, 0); return;
        }
    default:
        diag(e->prog, n->file, n->line, n->col, "internal: cannot emit expression kind %d", n->kind);
        op0(e, I_PUSHEMPTY);
    }
}

/* does the expression leave a value on the stack? */
static int has_value(Node *n)
{
    switch (n->kind) {
    case E_CALL: case E_MCALL: return n->proc->ret != NULL && n->proc->kind != PK_SUB;
    case E_BUILTIN: return builtins[n->bi].ret != T_VOID;
    case E_LATE: return 1;
    case E_ERRPROP: return n->op != 4 && n->op != 5;
    default: return 1;
    }
}

/* ---------- assignment ---------- */

static int simple_target(Node *t)
{
    return t->kind == E_VAR && t->ty->kind != T_UDT;
}

static void assign(E *e, Node *t, Node *v)
{
    if (simple_target(t)) {
        expr(e, v);
        store_var(e, t->sym);
        return;
    }
    addr(e, t);
    expr(e, v);
    op1(e, I_STIND, vt_of(t->ty));
}

/* store the value on the stack (already converted) into lvalue t */
static void store_top(E *e, Node *t)
{
    if (simple_target(t)) { store_var(e, t->sym); return; }
    addr(e, t);
    op0(e, I_SWAP);
    op1(e, I_STIND, vt_of(t->ty));
}

static int wev_index_of(E *e, Sym *s, int *hidden, int *is_field)
{
    if (s->storage == ST_FIELD) {
        int ci = s->cls->index;
        *is_field = 1;
        *hidden = e->wev_hidden_field[ci][s->index];
        return e->wev_of_field[ci][s->index];
    }
    *is_field = 0;
    *hidden = e->wev_hidden_global[s->index];
    return e->wev_of_global[s->index];
}

/* ---------- statements ---------- */

static Loop *push_loop(E *e, int kind)
{
    Loop *l = &e->loops[e->nloops++];
    memset(l, 0, sizeof *l);
    l->kind = kind;
    return l;
}

static void pop_loop(E *e, int target)
{
    Loop *l = &e->loops[--e->nloops];
    patch_all(e, &l->exits, target);
    free(l->exits.v);
}

static void block(E *e, NodeList *b)
{
    int i;
    for (i = 0; i < b->n; i++) stmt(e, b->v[i]);
}

static void cond_jump_false(E *e, Node *c, Patch *p)
{
    expr(e, c);
    patch_add(p, jump(e, I_JF));
}

static int fast_for_kind(Node *ctr)
{
    Sym *s;
    if (ctr->kind != E_VAR) return 0;
    s = ctr->sym;
    if ((s->storage != ST_LOCAL && s->storage != ST_PARAM) || is_ref_slot(s)) return 0;
    switch (s->ty->kind) {
    case T_INTEGER: return 1;
    case T_LONG: return 2;
    case T_DOUBLE: return 3;
    default: return 0;
    }
}

static void for_stmt(E *e, Node *s)
{
    Node *ctr = s->a, *lim = s->list2.v[0], *stp = s->list2.v[1];
    int kind = fast_for_kind(ctr);
    Loop *l;
    int top, chk;
    /* VB evaluates start, end and step once, before the loop */
    if (kind) {
        expr(e, s->b);
        store_var(e, ctr->sym);
        expr(e, s->c);
        store_var(e, lim->sym);
        expr(e, s->d);
        store_var(e, stp->sym);
        {
            int chkop = kind == 1 ? I_FORCHK_I : kind == 2 ? I_FORCHK_L : I_FORCHK_D;
            int incop = kind == 1 ? I_FORINC_I : kind == 2 ? I_FORINC_L : I_FORINC_D;
            int c = slot_of(e, ctr->sym), lm = slot_of(e, lim->sym), st = slot_of(e, stp->sym);
            emit_w(e, chkop); emit_w(e, c); emit_w(e, lm); emit_w(e, st);
            chk = emit_w(e, 0);
            l = push_loop(e, EXIT_FOR);
            patch_add(&l->exits, chk);
            top = here(e);
            block(e, &s->list);
            emit_w(e, incop); emit_w(e, c); emit_w(e, lm); emit_w(e, st); emit_w(e, top);
            pop_loop(e, here(e));
        }
        return;
    }
    expr(e, s->c);
    store_var(e, lim->sym);
    expr(e, s->d);
    store_var(e, stp->sym);
    assign(e, ctr, s->b);
    l = push_loop(e, EXIT_FOR);
    top = here(e);
    expr(e, ctr);
    load_var(e, lim->sym);
    load_var(e, stp->sym);
    patch_add(&l->exits, jump(e, I_FORCHKV));
    block(e, &s->list);
    {
        /* ctr = ctr + step */
        Node add;
        Node stpv;
        memset(&add, 0, sizeof add);
        memset(&stpv, 0, sizeof stpv);
        stpv.kind = E_VAR;
        stpv.sym = stp->sym;
        stpv.ty = stp->sym->ty;
        add.kind = E_BIN;
        add.op = OP_ADD;
        add.a = ctr;
        add.b = &stpv;
        add.ty = ctr->ty;
        if (ctr->ty->kind == T_DATE) add.ty = &ty_date;
        if (ctr->ty->kind == T_DATE) {
            expr(e, ctr); op1(e, I_CVT, BB_DOUBLE);
            load_var(e, stp->sym); op1(e, I_CVT, BB_DOUBLE);
            op0(e, I_ADD_DT);
            store_top(e, ctr);
        } else {
            expr(e, &add);
            store_top(e, ctr);
        }
    }
    op1(e, I_JMP, top);
    pop_loop(e, here(e));
}

static void foreach_stmt(E *e, Node *s)
{
    int slot = slot_of(e, s->sym), top, ex;
    if (s->b->kind == E_VAR && s->b->ty->kind == T_ARRAY) addr(e, s->b);
    else expr(e, s->b);
    op1(e, I_FEBEGIN, slot);
    push_loop(e, EXIT_FOR);
    top = here(e);
    emit_w(e, I_FENEXT);
    emit_w(e, slot);
    ex = emit_w(e, 0);
    if (s->a->ty->kind != T_VARIANT) {
        if (s->a->ty->kind == T_OBJECT) {
            op1(e, I_CVT, BB_OBJECT);
            if (s->a->ty->cls && !s->a->ty->cls->builtin) op1(e, I_CHKCLS, s->a->ty->cls->index);
        } else op1(e, I_CVT, vt_of(s->a->ty));
    }
    store_top(e, s->a);
    if (s->a->kind == E_VAR && s->a->sym->withevents) { /* rare */ }
    block(e, &s->list);
    op1(e, I_JMP, top);
    set_target(e, ex, here(e));
    pop_loop(e, here(e));
    op1(e, I_FEEND, slot);
}

static void label_ref(E *e, Sym *l, int at)
{
    if (!l) return;
    patch_add(&e->label_refs[l->label_id], at);
}

static void stmt1(E *e, Node *s);
static void stmt(E *e, Node *s)
{
    int outer = e->used_keep;
    e->used_keep = 0;
    stmt1(e, s);
    if (e->used_keep) op0(e, I_UNKEEP);
    e->used_keep = outer;
}

static void stmt1(E *e, Node *s)
{
    int i;
    line(e, s);
    switch (s->kind) {
    case S_LET: case S_SET:
        if (s->a->kind == E_ERRPROP) {
            expr(e, s->b);
            op1(e, I_ERROP, s->a->op == 1 ? EO_SETNUMBER : s->a->op == 2 ? EO_SETDESC : EO_SETSOURCE);
            return;
        }
        assign(e, s->a, s->b);
        if (s->kind == S_SET && s->a->kind == E_VAR && s->a->sym->withevents) {
            int hidden, isf, w = wev_index_of(e, s->a->sym, &hidden, &isf);
            op3(e, I_WEVCONN, isf, s->a->sym->index, w);
            (void)hidden;
        }
        return;
    case S_EXPR: {
        Node *x = s->a;
        if (x->kind == E_LATE && x->name[0] == 0 && (x->argc_kind & (BB_INV_LET | BB_INV_SET)) &&
            x->a->ty->kind == T_VARIANT && is_lvalue(x->a)) {
            addr(e, x->a);
            for (i = 0; i < x->list.n; i++) expr(e, x->list.v[i]);
            op1(e, I_VSTOREIDX, x->list.n - 1);
            return;
        }
        expr(e, x);
        if (has_value(x)) op0(e, I_POP);
        return;
    }
    case S_IF: {
        Patch ends = {0, 0, 0};
        for (i = 0; i < s->list.n; i++) {
            Node *br = s->list.v[i];
            Patch nx = {0, 0, 0};
            cond_jump_false(e, br->a, &nx);
            block(e, &br->list);
            if (i < s->list.n - 1 || s->list2.n) patch_add(&ends, jump(e, I_JMP));
            patch_all(e, &nx, here(e));
            free(nx.v);
        }
        block(e, &s->list2);
        patch_all(e, &ends, here(e));
        free(ends.v);
        return;
    }
    case S_SELECT: {
        Patch ends = {0, 0, 0};
        expr(e, s->a);
        if (s->a->ty->kind == T_STRING && s->a->ty->fixlen) {}
        store_var(e, s->sym);
        for (i = 0; i < s->list.n; i++) {
            Node *cs = s->list.v[i];
            if (cs->flags & NF_CASEELSE) { block(e, &cs->list2); continue; }
            {
                Patch body = {0, 0, 0};
                int k, skip;
                for (k = 0; k < cs->list.n; k++) {
                    expr(e, cs->list.v[k]);
                    patch_add(&body, jump(e, I_JT));
                }
                skip = jump(e, I_JMP);
                patch_all(e, &body, here(e));
                free(body.v);
                block(e, &cs->list2);
                patch_add(&ends, jump(e, I_JMP));
                set_target(e, skip, here(e));
            }
        }
        patch_all(e, &ends, here(e));
        free(ends.v);
        return;
    }
    case S_FOR: for_stmt(e, s); return;
    case S_FOREACH: foreach_stmt(e, s); return;
    case S_DO: {
        Loop *l = push_loop(e, EXIT_DO);
        int top = here(e);
        if (s->op == DO_PRE_WHILE || s->op == DO_PRE_UNTIL) {
            expr(e, s->a);
            patch_add(&l->exits, jump(e, s->op == DO_PRE_WHILE ? I_JF : I_JT));
        }
        block(e, &s->list);
        if (s->op == DO_POST_WHILE || s->op == DO_POST_UNTIL) {
            line(e, s->a);
            expr(e, s->a);
            op1(e, s->op == DO_POST_WHILE ? I_JT : I_JF, top);
        } else op1(e, I_JMP, top);
        pop_loop(e, here(e));
        return;
    }
    case S_EXIT:
        if (s->op == EXIT_FOR || s->op == EXIT_DO) {
            int k;
            for (k = e->nloops - 1; k >= 0; k--)
                if (e->loops[k].kind == s->op) { patch_add(&e->loops[k].exits, jump(e, I_JMP)); break; }
            return;
        }
        patch_add(&e->exitp, jump(e, I_JMP));
        return;
    case S_GOTO: label_ref(e, s->sym, jump(e, I_JMP)); return;
    case S_GOSUB: label_ref(e, s->sym, jump(e, I_GOSUB)); return;
    case S_RETURN: op0(e, I_RETSUB); return;
    case S_LABEL:
        if (s->sym) e->label_pc[s->sym->label_id] = here(e);
        return;
    case S_ONGOTO:
        expr(e, s->a);
        op1(e, I_ONGOTO, s->list.n | (s->op ? 0x10000 : 0));
        for (i = 0; i < s->list.n; i++) label_ref(e, s->list.v[i]->sym, emit_w(e, 0));
        return;
    case S_ONERROR:
        emit_w(e, I_ONERR);
        if (s->op == ONERR_GOTO) { emit_w(e, OE_GOTO); label_ref(e, s->sym, emit_w(e, 0)); }
        else { emit_w(e, s->op == ONERR_RESUMENEXT ? OE_RESUMENEXT : OE_NONE); emit_w(e, 0); }
        return;
    case S_RESUME:
        emit_w(e, I_RESUME);
        if (s->op == RES_LABEL) { emit_w(e, RS_LABEL); label_ref(e, s->sym, emit_w(e, 0)); }
        else { emit_w(e, s->op == RES_NEXT ? RS_NEXT : RS_PLAIN); emit_w(e, 0); }
        return;
    case S_PRINT: {
        int last_sep = PSEP_NONE;
        if (s->a) expr(e, s->a); else op1(e, I_PUSHL, (s->flags & NF_DEBUG) ? -1 : 0);
        op0(e, I_SETFN);
        for (i = 0; i < s->list.n; i++) {
            Node *it = s->list.v[i];
            if (it->ival == PI_EXPR && it->a) { expr(e, it->a); op0(e, I_PRT); }
            else if (it->ival == PI_SPC) { if (it->a) expr(e, it->a); else op1(e, I_PUSHL, 1); op0(e, I_PRTSPC); }
            else if (it->ival == PI_TAB) { if (it->a) { expr(e, it->a); op0(e, I_PRTTAB); } else op0(e, I_PRTCOMMA); }
            if (it->op == PSEP_COMMA) op0(e, I_PRTCOMMA);
            last_sep = it->op;
            if (it->ival == PI_TAB && !it->a && it->op == PSEP_NONE) last_sep = PSEP_SEMI;
        }
        if (last_sep == PSEP_NONE) op0(e, I_PRTNL);
        return;
    }
    case S_WRITE:
        expr(e, s->a);
        op0(e, I_SETFN);
        if (!s->list.n) { op0(e, I_PRTNL); return; }
        for (i = 0; i < s->list.n; i++) { expr(e, s->list.v[i]); op1(e, I_WRT, i == s->list.n - 1); }
        return;
    case S_INPUT:
        if (s->b) { expr(e, s->b); op1(e, I_PROMPT, (s->flags & NF_QUESTION) != 0); }
        else if (!s->a) { op1(e, I_PUSHK, str_const(e, "", 0)); op1(e, I_PROMPT, 1); }
        if (s->a) expr(e, s->a); else op1(e, I_PUSHL, 0);
        op0(e, I_SETFN);
        for (i = 0; i < s->list.n; i++) {
            Node *t = s->list.v[i];
            op1(e, I_INFIELD, t->ty->kind == T_VARIANT);
            if (t->ty->kind != T_VARIANT && t->ty->kind != T_STRING) op1(e, I_CVT, vt_of(t->ty));
            if (t->ty->kind == T_STRING && t->ty->fixlen) op1(e, I_CVTFIX, t->ty->fixlen);
            store_top(e, t);
        }
        op0(e, I_INEND);
        return;
    case S_LINEINPUT:
        if (s->b) { expr(e, s->b); op1(e, I_PROMPT, 0); }
        if (s->a) expr(e, s->a); else op1(e, I_PUSHL, 0);
        op0(e, I_SETFN);
        op0(e, I_LINEIN);
        if (s->c->ty->kind == T_STRING && s->c->ty->fixlen) op1(e, I_CVTFIX, s->c->ty->fixlen);
        store_top(e, s->c);
        return;
    case S_OPEN:
        expr(e, s->a);
        expr(e, s->b);
        if (s->c) expr(e, s->c); else op1(e, I_PUSHL, 0);
        op1(e, I_OPEN, s->op);
        return;
    case S_CLOSE:
        if (!s->list.n) { op0(e, I_CLOSEALL); return; }
        for (i = 0; i < s->list.n; i++) { expr(e, s->list.v[i]); op0(e, I_CLOSE); }
        return;
    case S_GET: case S_PUT:
        expr(e, s->a);
        if (s->b) expr(e, s->b); else op1(e, I_PUSHL, 0);
        addr(e, s->c);
        op2(e, s->kind == S_GET ? I_GETREC : I_PUTREC, vt_of(s->c->ty), udt_index(s->c->ty));
        return;
    case S_SEEK:
        expr(e, s->a);
        expr(e, s->b);
        op0(e, I_SEEK);
        return;
    case S_NAME:
        expr(e, s->a);
        expr(e, s->b);
        op0(e, I_NAMEF);
        return;
    case S_REDIM:
        for (i = 0; i < s->list.n; i++) {
            Node *d = s->list.v[i];
            int k;
            addr(e, d->b);
            for (k = 0; k < d->list.n; k++) { expr(e, d->list.v[k]->a); expr(e, d->list.v[k]->b); }
            emit_w(e, I_REDIM);
            emit_w(e, d->list.n);
            emit_w(e, (s->flags & NF_PRESERVE) != 0);
            emit_w(e, vt_of(d->ty));
            emit_w(e, udt_index(d->ty));
        }
        return;
    case S_ERASE:
        for (i = 0; i < s->list.n; i++) { addr(e, s->list.v[i]); op0(e, I_ERASE); }
        return;
    case S_MIDASSIGN:
        addr(e, s->a);
        expr(e, s->b);
        if (s->c) expr(e, s->c); else op1(e, I_PUSHL, -1);
        expr(e, s->d);
        op0(e, I_MIDSET);
        return;
    case S_END: op0(e, I_END); return;
    case S_STOP: op0(e, I_STOP); return;
    case S_WITH: {
        Sym *t = s->sym;
        if (t->byref) { addr(e, s->a); op1(e, I_STL, slot_of(e, t)); }
        else { expr(e, s->a); op1(e, I_STLV, slot_of(e, t)); }
        block(e, &s->list);
        if (!t->byref) { op0(e, I_PUSHEMPTY); op1(e, I_STLV, slot_of(e, t)); }
        else { op0(e, I_PUSHEMPTY); op1(e, I_STL, slot_of(e, t)); }
        return;
    }
    case S_RAISEEVENT:
        for (i = 0; i < s->list.n; i++) {
            Node *a = s->list.v[i];
            if (a->flags & NF_BYREF) addr(e, a); else expr(e, a);
        }
        op3(e, I_RAISEEV, e->proc->cls->index, s->proc->event_index, s->list.n);
        return;
    case S_ERROR:
        expr(e, s->a);
        op1(e, I_ERROP, EO_ERROR);
        return;
    case S_NOP: case S_DIM: case S_CONST:
        return;
    default:
        diag(e->prog, s->file, s->line, s->col, "internal: cannot emit statement kind %d", s->kind);
    }
}

/* ---------- procedures ---------- */

static void emit_proc(E *e, Proc *pr, VMProc *vp)
{
    int i, nbyref = 0;
    e->proc = pr;
    e->vp = vp;
    e->me = pr->cls ? 1 : 0;
    e->nloops = 0;
    e->nlines = 0;
    e->caplines = 0;
    e->lines = NULL;
    memset(&e->exitp, 0, sizeof e->exitp);
    vp->name = pr->name;
    vp->module = pr->mod->index;
    vp->file = pr->mod->file;
    vp->kind = pr->kind;
    vp->cls = pr->cls ? pr->cls->index : -1;
    vp->is_public = pr->is_public;
    vp->nparams = pr->nparams + e->me;
    for (i = 0; i < pr->nparams; i++) if (pr->params[i].byref) nbyref++;
    vp->nlocals = pr->nlocals + e->me + nbyref;
    vp->hidden = pr->nlocals + e->me;
    vp->slots = (VMSlot *)xcalloc((size_t)(vp->nlocals + 1), sizeof(VMSlot));
    vp->param_byref = (uint8_t *)xcalloc((size_t)(vp->nparams + 1), 1);
    vp->param_def = (int32_t *)xcalloc((size_t)(vp->nparams + 1), sizeof(int32_t));
    if (e->me) { vp->slots[0].vt = BB_OBJECT; vp->slots[0].name = "Me"; vp->param_def[0] = -1; }
    for (i = 0; i < pr->nlocals; i++) fill_slot(&vp->slots[i + e->me], pr->locals[i], pr->locals[i]->ty);
    {
        int k = pr->nlocals + e->me;
        for (i = 0; i < pr->nparams; i++) {
            Param *pa = &pr->params[i];
            vp->param_byref[i + e->me] = (uint8_t)pa->byref;
            if (pa->byref) { fill_slot(&vp->slots[k], NULL, pa->ty); vp->slots[k].name = "$byref"; k++; }
            if (pa->has_def) {
                Node tmp;
                memset(&tmp, 0, sizeof tmp);
                tmp.cv = pa->def;
                tmp.ty = type_prim(pa->def.type);
                if (pa->def.type == T_STRING) vp->param_def[i + e->me] = str_const(e, pa->def.s, pa->def.slen);
                else {
                    bb_value k2;
                    switch (pa->def.type) {
                    case T_INTEGER: k2 = bb_v_int((bb_int)pa->def.i); break;
                    case T_LONG: k2 = bb_v_long((bb_long)pa->def.i); break;
                    case T_BOOLEAN: k2 = bb_v_bool(pa->def.i != 0); break;
                    case T_BYTE: k2 = bb_v_byte((bb_byte)pa->def.i); break;
                    case T_SINGLE: k2 = bb_v_single((float)pa->def.d); break;
                    case T_CURRENCY: k2 = bb_v_cur((bb_cur)(pa->def.d * 10000)); break;
                    case T_DATE: k2 = bb_v_date(pa->def.d); break;
                    default: k2 = pa->def.is_null ? bb_v_null() : pa->def.is_empty ? bb_v_empty() : bb_v_double(pa->def.d);
                    }
                    vp->param_def[i + e->me] = add_const(e, k2);
                }
            } else if (pa->optional) vp->param_def[i + e->me] = pa->ty->kind == T_VARIANT ? -2 : -3;
            else vp->param_def[i + e->me] = -1;
        }
    }
    vp->ret_slot = pr->retvar ? pr->retvar->index + e->me : -1;
    vp->has_onerror = pr->has_onerror;
    vp->code = here(e);
    e->label_pc = (int *)xcalloc((size_t)(pr->nlabels + 1), sizeof(int));
    e->label_refs = (Patch *)xcalloc((size_t)(pr->nlabels + 1), sizeof(Patch));
    block(e, &pr->body);
    patch_all(e, &e->exitp, here(e));
    if (e->nlines == 0 || e->lines[e->nlines - 1].pc != here(e)) {
        Node endn;
        memset(&endn, 0, sizeof endn);
        endn.line = pr->decl ? (int)pr->decl->ival : (pr->body.n ? pr->body.v[pr->body.n - 1]->line : pr->line);
        if (endn.line <= 0) endn.line = pr->line;
        line(e, &endn);
    }
    op0(e, I_RET);
    for (i = 0; i < pr->nlabels; i++) patch_all(e, &e->label_refs[i], e->label_pc[i]);
    vp->lines = e->lines;
    vp->nlines = e->nlines;
    free(e->label_pc);
    free(e->label_refs);
}

static int find_proc_named(Module *m, const char *name)
{
    int i;
    for (i = 0; i < m->nprocs; i++)
        if (name_eq(m->procs[i]->name, name) && (m->procs[i]->kind == PK_SUB)) return m->procs[i]->index;
    return -1;
}

VMImage *emit_bytecode(Program *p)
{
    E ex, *e = &ex;
    VMImage *g = (VMImage *)xcalloc(1, sizeof(VMImage));
    int i, j, nwev = 0, extra_globals = 0;
    memset(e, 0, sizeof ex);
    e->prog = p;
    e->img = g;
    g->stack = p->stack;
    g->nfiles = p->nfiles;
    g->files = p->files;
    g->nmodules = p->nmods;
    g->modules = (char **)xcalloc((size_t)p->nmods + 1, sizeof(char *));
    for (i = 0; i < p->nmods; i++) g->modules[i] = p->mods[i]->name;
    /* UDTs */
    g->nudts = p->nudts;
    g->udts = (VMUdt *)xcalloc((size_t)p->nudts + 1, sizeof(VMUdt));
    for (i = 0; i < p->nudts; i++) {
        Udt *u = p->udts[i];
        VMUdt *vu = &g->udts[i];
        vu->name = u->name;
        vu->nfields = u->nfields;
        vu->fields = (VMSlot *)xcalloc((size_t)u->nfields + 1, sizeof(VMSlot));
        for (j = 0; j < u->nfields; j++) {
            UField *f = &u->fields[j];
            int k;
            fill_slot(&vu->fields[j], NULL, f->ty);
            vu->fields[j].name = f->name;
            vu->fields[j].fixlen = (int16_t)f->fixlen;
            vu->fields[j].ndims = (int16_t)f->ndims;
            for (k = 0; k < f->ndims; k++) { vu->fields[j].lb[k] = f->lb[k]; vu->fields[j].ub[k] = f->ub[k]; }
        }
    }
    /* WithEvents bookkeeping */
    e->wev_hidden_global = (int *)xcalloc((size_t)p->nglobals + 1, sizeof(int));
    e->wev_of_global = (int *)xcalloc((size_t)p->nglobals + 1, sizeof(int));
    for (i = 0; i < p->nglobals; i++) {
        e->wev_hidden_global[i] = -1;
        e->wev_of_global[i] = -1;
        if (p->globals[i]->withevents) { e->wev_of_global[i] = nwev++; e->wev_hidden_global[i] = p->nglobals + extra_globals++; }
    }
    e->wev_hidden_field = (int **)xcalloc((size_t)p->nclasses + 1, sizeof(int *));
    e->wev_of_field = (int **)xcalloc((size_t)p->nclasses + 1, sizeof(int *));
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        int extra = 0;
        e->wev_hidden_field[i] = (int *)xcalloc((size_t)c->nfields + 1, sizeof(int));
        e->wev_of_field[i] = (int *)xcalloc((size_t)c->nfields + 1, sizeof(int));
        for (j = 0; j < c->nfields; j++) {
            e->wev_hidden_field[i][j] = -1;
            e->wev_of_field[i][j] = -1;
            if (c->fields[j]->withevents) { e->wev_of_field[i][j] = nwev++; e->wev_hidden_field[i][j] = c->nfields + extra++; }
        }
    }
    g->nwevs = nwev;
    g->wevs = (VMWev *)xcalloc((size_t)nwev + 1, sizeof(VMWev));
    /* globals */
    g->nglobals = p->nglobals + extra_globals;
    g->globals = (VMSlot *)xcalloc((size_t)g->nglobals + 1, sizeof(VMSlot));
    g->global_mod = (int32_t *)xcalloc((size_t)g->nglobals + 1, sizeof(int32_t));
    for (i = 0; i < p->nglobals; i++) {
        Sym *s = p->globals[i];
        fill_slot(&g->globals[i], s, s->ty);
        g->globals[i].isref = 0;
        if (s->is_new) g->globals[i].newcls = (int16_t)(s->ty->cls->builtin ? -1 : s->ty->cls->index + 1);
        g->global_mod[i] = s->mod ? s->mod->index : 0;
        if (s->withevents) {
            VMWev *w = &g->wevs[e->wev_of_global[i]];
            ClassInfo *src = s->ty->cls;
            int k;
            w->cls = src->index;
            w->in_class = -1;
            w->hidden = e->wev_hidden_global[i];
            w->handler = (int32_t *)xcalloc((size_t)src->nevents + 1, sizeof(int32_t));
            for (k = 0; k < src->nevents; k++) {
                char *hn = xsprintf("%s_%s", s->name, src->events[k]->name);
                w->handler[k] = find_proc_named(s->mod, hn);
                free(hn);
            }
            g->globals[e->wev_hidden_global[i]].vt = BB_EMPTY;
            g->globals[e->wev_hidden_global[i]].name = "$sink";
        }
    }
    /* classes */
    g->nclasses = p->nclasses;
    g->classes = (VMClass *)xcalloc((size_t)p->nclasses + 1, sizeof(VMClass));
    for (i = 0; i < p->nclasses; i++) {
        ClassInfo *c = p->classes[i];
        VMClass *vc = &g->classes[i];
        int nf = c->nfields, extra = 0, k;
        for (j = 0; j < c->nfields; j++) if (c->fields[j]->withevents) extra++;
        vc->name = c->name;
        vc->nfields = nf + extra;
        vc->fields = (VMSlot *)xcalloc((size_t)vc->nfields + 1, sizeof(VMSlot));
        for (j = 0; j < nf; j++) {
            Sym *s = c->fields[j];
            fill_slot(&vc->fields[j], s, s->ty);
            vc->fields[j].isref = 0;
            if (s->is_new) vc->fields[j].newcls = (int16_t)(s->ty->cls->builtin ? -1 : s->ty->cls->index + 1);
            if (s->withevents) {
                VMWev *w = &g->wevs[e->wev_of_field[i][j]];
                ClassInfo *src = s->ty->cls;
                w->cls = src->index;
                w->in_class = i;
                w->hidden = e->wev_hidden_field[i][j];
                w->handler = (int32_t *)xcalloc((size_t)src->nevents + 1, sizeof(int32_t));
                for (k = 0; k < src->nevents; k++) {
                    char *hn = xsprintf("%s_%s", s->name, src->events[k]->name);
                    w->handler[k] = find_proc_named(c->mod, hn);
                    free(hn);
                }
                vc->fields[e->wev_hidden_field[i][j]].vt = BB_EMPTY;
                vc->fields[e->wev_hidden_field[i][j]].name = "$sink";
            }
        }
        vc->init_proc = c->init ? c->init->index : -1;
        vc->term_proc = c->term ? c->term->index : -1;
        vc->nvtbl = c->nvtbl;
        vc->vtbl = (int32_t *)xcalloc((size_t)c->nvtbl + 1, sizeof(int32_t));
        for (j = 0; j < c->nvtbl; j++) vc->vtbl[j] = c->vtbl[j]->index;
        vc->nifaces = c->nimpls;
        vc->iface_cls = (int32_t *)xcalloc((size_t)c->nimpls + 1, sizeof(int32_t));
        vc->iface_vtbl = (int32_t **)xcalloc((size_t)c->nimpls + 1, sizeof(int32_t *));
        for (j = 0; j < c->nimpls; j++) {
            ClassInfo *I = c->impls[j];
            vc->iface_cls[j] = I->index;
            vc->iface_vtbl[j] = (int32_t *)xcalloc((size_t)I->nvtbl + 1, sizeof(int32_t));
            for (k = 0; k < I->nvtbl; k++) {
                int m;
                vc->iface_vtbl[j][k] = -1;
                for (m = 0; m < c->nmethods; m++)
                    if (c->methods[m]->impl_of == I->vtbl[k]) vc->iface_vtbl[j][k] = c->methods[m]->index;
            }
        }
        vc->nevents = c->nevents;
        vc->events = (char **)xcalloc((size_t)c->nevents + 1, sizeof(char *));
        for (j = 0; j < c->nevents; j++) vc->events[j] = c->events[j]->name;
        /* late-bound member table: public fields and public procs by name */
        vc->members = (VMMember *)xcalloc((size_t)(c->nfields + c->nmethods) + 1, sizeof(VMMember));
        for (j = 0; j < c->nfields; j++) {
            if (!c->fields[j]->is_public) continue;
            VMMember *m = &vc->members[vc->nmembers++];
            m->name = c->fields[j]->name;
            m->field = j;
            m->method = m->pget = m->plet = m->pset = -1;
        }
        for (j = 0; j < c->nmethods; j++) {
            Proc *pr = c->methods[j];
            VMMember *m = NULL;
            if (!pr->is_public) continue;
            for (k = 0; k < vc->nmembers; k++) if (name_eq(vc->members[k].name, pr->name)) m = &vc->members[k];
            if (!m) {
                m = &vc->members[vc->nmembers++];
                m->name = pr->name;
                m->field = -1;
                m->method = m->pget = m->plet = m->pset = -1;
            }
            switch (pr->kind) {
            case PK_PGET: m->pget = pr->index; break;
            case PK_PLET: m->plet = pr->index; break;
            case PK_PSET: m->pset = pr->index; break;
            default: m->method = pr->index;
            }
        }
    }
    /* declares */
    g->ndecls = p->nprocs;
    g->decls = (bb_declare *)xcalloc((size_t)p->nprocs + 1, sizeof(bb_declare));
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind != PK_DECLARE) continue;
        g->decls[i].name = pr->name;
        g->decls[i].lib = pr->lib;
        g->decls[i].alias = pr->alias;
        g->decls[i].iface = pr->iface;
        g->decls[i].version = pr->version;
        g->decls[i].nparams = pr->nparams;
    }
    /* procedures */
    g->nprocs = p->nprocs;
    g->procs = (VMProc *)xcalloc((size_t)p->nprocs + 1, sizeof(VMProc));
    for (i = 0; i < p->nprocs; i++) {
        Proc *pr = p->procs[i];
        if (pr->kind == PK_DECLARE || pr->kind == PK_EVENT) {
            g->procs[i].name = pr->name;
            g->procs[i].kind = pr->kind;
            g->procs[i].code = -1;
            g->procs[i].cls = -1;
            g->procs[i].module = pr->mod->index;
            continue;
        }
        emit_proc(e, pr, &g->procs[i]);
    }
    g->startup = p->startup_proc ? p->startup_proc->index : -1;
    return p->nerrors ? NULL : g;
}
