/* vm.c - the Boing BASIC bytecode interpreter */
#include "bytecode.h"
#include "../compiler/bbc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <stddef.h>

const char *const bb_opnames[] = {
#define OP_NAME(n, k) #n,
    BB_OPCODES(OP_NAME)
#undef OP_NAME
};
const int bb_opwords[] = {
#define OP_W(n, k) k,
    BB_OPCODES(OP_W)
#undef OP_W
};

enum {
#define BI(id, name, ret, mn, mx, params, defs, cfn, flags, vm) BI_##id,
#include "../compiler/builtins.def"
#undef BI
    BI__COUNT
};

typedef struct Frame {
    VMProc *proc;
    int32_t pidx;
    int32_t *pc;            /* current instruction (saved per instruction) */
    int32_t *ret;           /* return address in the caller */
    bb_value *base;
    int handler_mode;
    int32_t handler_pc;
    int in_handler;
    int32_t err_pc;         /* offset of the failing instruction */
    int32_t gs_base;
    bb_value keep;          /* keeps a temporary object alive (MFIELD on an rvalue) */
    int fn;                 /* file number register for Print/Input */
} Frame;

typedef struct VM {
    VMImage *img;
    bb_value *stack, *stack_end;
    bb_value *sp;
    Frame *frames;
    int nframes, maxframes;
    bb_value *globals;
    int32_t *gosub;
    int ngosub, capgosub;
} VM;

typedef struct VMObj {
    bb_obj hdr;
    VMClass *vc;
    bb_value f[1];
} VMObj;

typedef struct WevConn { bb_obj *src; bb_sink *sink; } WevConn;

static VM *g_vm;

static void vm_exec(VM *vm, int entry);
static void vm_call_proc(VM *vm, int32_t pidx, bb_obj *me, int argc, bb_value *argv, bb_value *ret);

/* ---------- slots ---------- */

static const bb_udt_desc *udt_desc(VM *vm, int idx) { return idx >= 0 ? &vm->img->udts[idx].desc : NULL; }

static int udt_index_of(VM *vm, const bb_udt_desc *d)
{
    if (!d) return -1;
    return (int)(((const char *)d - (const char *)&vm->img->udts[0].desc) / (ptrdiff_t)sizeof(VMUdt));
}

static void *raw(bb_value *slot, int vt)
{
    if (vt == BB_VARIANT) return slot;
    if (vt == BB_UDT) return bb_v_udt_data(slot);
    return &slot->u;
}

static bb_obj *new_object(VM *vm, int cls);

static void init_slot(VM *vm, bb_value *v, const VMSlot *s)
{
    *v = bb_v_make(BB_EMPTY);
    if (s->isref) return;
    if (s->vt == BB_UDT) { *v = bb_v_udt_new(udt_desc(vm, s->udt)); return; }
    if (s->vt & BB_ARRAY) {
        v->type = s->vt;
        if (s->ndims) {
            v->u.a = bb_arr_new(BB_BASETYPE(s->vt), udt_desc(vm, s->udt), s->ndims, s->lb, s->ub);
            v->u.a->fixed = 1;
        }
        return;
    }
    if (s->vt == BB_VARIANT) return;
    v->type = s->vt;
    if (s->vt == BB_STRING && s->fixlen) v->u.s = bb_str_fixlen(NULL, s->fixlen);
    if (s->vt == BB_OBJECT && s->newcls) v->u.o = s->newcls < 0 ? bb_collection_new() : new_object(vm, s->newcls - 1);
}

static void release_slot(bb_value *v)
{
    if (v->type & BB_REF) { v->type = BB_EMPTY; return; }
    bb_v_release(v);
}

/* ---------- UDT layout (host sizes) ---------- */

static void type_size_align(VM *vm, int vt, int udt, int32_t *size, int32_t *align);

static void layout_udt(VM *vm, int idx)
{
    VMUdt *u = &vm->img->udts[idx];
    int32_t off = 0, maxa = 1, i;
    if (u->rtfields) return;
    u->rtfields = (bb_field *)xcalloc((size_t)u->nfields + 1, sizeof(bb_field));
    for (i = 0; i < u->nfields; i++) {
        VMSlot *s = &u->fields[i];
        bb_field *f = &u->rtfields[i];
        int32_t sz, al;
        int k;
        type_size_align(vm, (s->vt & BB_ARRAY) ? BB_ARRAY : s->vt, s->udt, &sz, &al);
        off = (off + al - 1) / al * al;
        f->name = s->name;
        f->type = s->vt;
        f->fixlen = (uint16_t)s->fixlen;
        f->offset = off;
        f->udt = s->udt >= 0 ? udt_desc(vm, s->udt) : NULL;
        f->ndims = s->ndims;
        for (k = 0; k < s->ndims; k++) { f->lb[k] = s->lb[k]; f->ub[k] = s->ub[k]; }
        off += sz;
        if (al > maxa) maxa = al;
    }
    off = (off + maxa - 1) / maxa * maxa;
    u->desc.name = u->name;
    u->desc.size = off;
    u->desc.nfields = u->nfields;
    u->desc.fields = u->rtfields;
}

static void type_size_align(VM *vm, int vt, int udt, int32_t *size, int32_t *align)
{
    switch (vt) {
    case BB_BYTE: *size = *align = 1; return;
    case BB_INTEGER: case BB_BOOLEAN: *size = *align = 2; return;
    case BB_LONG: case BB_SINGLE: *size = *align = 4; return;
    case BB_DOUBLE: case BB_DATE: case BB_CURRENCY: *size = 8; *align = (int32_t)offsetof(struct { char c; double d; }, d); return;
    case BB_VARIANT: *size = (int32_t)sizeof(bb_value); *align = 8; return;
    case BB_UDT: {
        int32_t i, a = 1;
        layout_udt(vm, udt);
        for (i = 0; i < vm->img->udts[udt].nfields; i++) {
            int32_t s2, a2;
            VMSlot *f = &vm->img->udts[udt].fields[i];
            type_size_align(vm, (f->vt & BB_ARRAY) ? BB_ARRAY : f->vt, f->udt, &s2, &a2);
            if (a2 > a) a = a2;
        }
        *size = vm->img->udts[udt].desc.size;
        *align = a;
        return;
    }
    default: *size = *align = (int32_t)sizeof(void *); return;
    }
}

/* ---------- objects ---------- */

static int32_t vmobj_find(const bb_class *cls, const char *name)
{
    VMClass *vc = (VMClass *)cls->user;
    int32_t i;
    if (!name || !*name) {
        for (i = 0; i < vc->nmembers; i++)
            if (strcasecmp(vc->members[i].name, "Item") == 0 || strcasecmp(vc->members[i].name, "Value") == 0) return i;
        return BB_NOMEMBER;
    }
    for (i = 0; i < vc->nmembers; i++) if (strcasecmp(vc->members[i].name, name) == 0) return i;
    return BB_NOMEMBER;
}

static void vmobj_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    VMObj *o = (VMObj *)self;
    VMClass *vc = o->vc;
    VMMember *m;
    int32_t p = -1;
    if (id < 0 || id >= vc->nmembers) bb_raise(438, NULL);
    m = &vc->members[id];
    if (m->field >= 0) {
        VMSlot *s = &vc->fields[m->field];
        bb_value *fv = &o->f[m->field];
        if (kind & (BB_INV_LET | BB_INV_SET)) {
            bb_value ref;
            if (argc != 1) bb_raise(450, NULL);
            ref = bb_v_ref(s->vt, raw(fv, s->vt));
            bb_v_store_ref(&ref, &argv[0]);
            if (s->vt == BB_STRING && s->fixlen) bb_str_set(&fv->u.s, bb_str_fixlen(fv->u.s, s->fixlen));
            return;
        }
        if (argc == 0) { *ret = bb_elem_load(s->vt, raw(fv, s->vt)); return; }
        if (s->vt & BB_ARRAY) {
            bb_value view = bb_v_make(s->vt);
            view.u.a = fv->u.a;
            *ret = bb_v_index(&view, argc, argv);
            return;
        }
        if (s->vt == BB_VARIANT || s->vt == BB_OBJECT) { *ret = bb_v_index(fv, argc, argv); return; }
        bb_raise(450, NULL);
    }
    if (kind & BB_INV_LET) p = m->plet >= 0 ? m->plet : -1;
    else if (kind & BB_INV_SET) p = m->pset >= 0 ? m->pset : m->plet;
    else if (kind & BB_INV_METHOD) p = m->method >= 0 ? m->method : m->pget;
    else if (kind & BB_INV_GET) p = m->pget >= 0 ? m->pget : m->method;
    if (p < 0) bb_raise(438, NULL);
    vm_call_proc(g_vm, p, self, argc, argv, ret);
}

static void wev_disconnect(bb_value *hidden)
{
    WevConn *c = (WevConn *)hidden->u.p;
    if (!c) return;
    if (c->src) {
        bb_event_disconnect(c->src, c->sink);
        bb_obj_release(c->src);
    }
    free(c);
    hidden->u.p = NULL;
}

static void vmobj_terminate(bb_obj *self)
{
    VMObj *o = (VMObj *)self;
    VMClass *vc = o->vc;
    int32_t i;
    if (vc->term_proc >= 0) {
        bb_value r = bb_v_empty();
        vm_call_proc(g_vm, vc->term_proc, self, 0, NULL, &r);
        bb_v_release(&r);
    }
    for (i = 0; i < g_vm->img->nwevs; i++) {
        VMWev *w = &g_vm->img->wevs[i];
        if (w->in_class >= 0 && &g_vm->img->classes[w->in_class] == vc) wev_disconnect(&o->f[w->hidden]);
    }
    for (i = 0; i < vc->nfields; i++) release_slot(&o->f[i]);
}

static bb_obj *new_object(VM *vm, int cls)
{
    VMClass *vc = &vm->img->classes[cls];
    VMObj *o = (VMObj *)bb_obj_new(&vc->rt);
    int32_t i;
    o->vc = vc;
    for (i = 0; i < vc->nfields; i++) init_slot(vm, &o->f[i], &vc->fields[i]);
    if (vc->init_proc >= 0) {
        bb_value r = bb_v_empty();
        vm_call_proc(vm, vc->init_proc, &o->hdr, 0, NULL, &r);
        bb_v_release(&r);
    }
    return &o->hdr;
}

static int is_vmobj(VM *vm, bb_obj *o)
{
    return o && o->cls->invoke == vmobj_invoke && (VMImage *)0 != vm->img;
}

/* ---------- For Each iterator object ---------- */

typedef struct FeObj { bb_obj hdr; bb_foreach fe; bb_value hold; int active; } FeObj;
static void fe_terminate(bb_obj *self)
{
    FeObj *f = (FeObj *)self;
    if (f->active) bb_foreach_end(&f->fe);
    bb_v_release(&f->hold);
}
static const bb_class fe_class = {"ForEach", sizeof(FeObj), NULL, NULL, fe_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL};

/* ---------- events ---------- */

static void vm_fire(bb_sink *s, int32_t event, const char *name, int argc, bb_value *argv)
{
    VMWev *w = &g_vm->img->wevs[s->tag];
    int32_t p;
    bb_value r = bb_v_empty();
    (void)name;
    if (event < 0) return;
    p = w->handler[event];
    if (p < 0) return;
    vm_call_proc(g_vm, p, w->in_class >= 0 ? (bb_obj *)s->ctx : NULL, argc, argv, &r);
    bb_v_release(&r);
}

/* ---------- builtins ---------- */

static bb_array *arr_arg(bb_value *v)
{
    if (v->type & BB_REF) {
        if (BB_BASETYPE(v->type) == BB_VARIANT && !(v->type & BB_ARRAY)) return bb_v_array((bb_value *)v->u.p);
        return *(bb_array **)v->u.p;
    }
    if (v->type & BB_ARRAY) return v->u.a;
    bb_raise(13, NULL);
    return NULL;
}

#define S(n) (args[n].u.s)
#define L(n) (args[n].u.l)
#define I(n) (args[n].u.i)
#define D(n) (args[n].u.d)
#define F(n) (args[n].u.f)
#define B(n) (args[n].u.b)
#define V(n) ((const bb_value *)&args[n])
#define A(n) arr_arg(&args[n])
#define RS(x) (*ret = bb_v_str(x))
#define RL(x) (*ret = bb_v_long(x))
#define RI(x) (*ret = bb_v_int(x))
#define RD(x) (*ret = bb_v_double(bb_chk_double(x)))
#define RF(x) (*ret = bb_v_single(x))
#define RDT(x) (*ret = bb_v_date(x))
#define RB(x) do { bb_value rb_ = bb_v_make(BB_BOOLEAN); rb_.u.b = (x); *ret = rb_; } while (0)
#define RV(x) (*ret = (x))
#define RA(x) (*ret = bb_v_arr(x))
#define RN(x) ((void)(x))

static void call_builtin(int bi, int argc, bb_value *args, bb_value *ret)
{
    (void)argc;
    switch (bi) {
#define BI(id, name, rt, mn, mx, params, defs, cfn, flags, vm) case BI_##id: vm; break;
#include "../compiler/builtins.def"
#undef BI
    default: bb_raise(51, NULL);
    }
}

#undef S
#undef L
#undef I
#undef D
#undef F
#undef B
#undef V
#undef A

/* ---------- frames ---------- */

static Frame *push_frame(VM *vm, int32_t pidx, bb_value *base)
{
    VMProc *p = &vm->img->procs[pidx];
    Frame *f;
    int32_t i;
    if (vm->nframes >= vm->maxframes || base + p->nlocals + 64 >= vm->stack_end) bb_raise(28, NULL);
    f = &vm->frames[vm->nframes++];
    memset(f, 0, sizeof *f);
    f->proc = p;
    f->pidx = pidx;
    f->base = base;
    f->pc = vm->img->code + p->code;
    f->gs_base = vm->ngosub;
    /* by-reference parameters that got a value: keep it in a hidden slot */
    {
        int32_t h = p->hidden;
        for (i = 0; i < p->nparams; i++) {
            if (!p->param_byref[i]) continue;
            if (!(base[i].type & BB_REF)) {
                bb_value *hv = &base[h];
                int vt = p->slots[h].vt;
                *hv = base[i];
                if (vt == BB_UDT && hv->type != BB_UDT) bb_raise(13, NULL);
                if ((vt & BB_ARRAY) && !(hv->type & BB_ARRAY)) {
                    /* Variant holding an array passed to an array parameter */
                }
                base[i] = bb_v_ref((uint16_t)vt, raw(hv, vt));
                if (vt == BB_UDT) base[i].aux = p->slots[h].udt;
            }
            h++;
        }
        for (i = p->nparams; i < p->hidden; i++) init_slot(vm, &base[i], &p->slots[i]);
        for (i = p->hidden; i < p->nlocals; i++) {
            /* hidden slots of params that were real refs stay Empty */
            if (base + i >= vm->sp) base[i] = bb_v_empty();
        }
    }
    vm->sp = base + p->nlocals;
    return f;
}

/* hidden slots: initialised before params are processed */
static void prep_hidden(VM *vm, VMProc *p, bb_value *base)
{
    int32_t i;
    for (i = p->hidden; i < p->nlocals; i++) base[i] = bb_v_empty();
    (void)vm;
}

static void pop_frame(VM *vm)
{
    Frame *f = &vm->frames[vm->nframes - 1];
    int32_t i;
    for (i = 0; i < f->proc->nlocals; i++) release_slot(&f->base[i]);
    bb_v_release(&f->keep);
    vm->ngosub = f->gs_base;
    if (f->in_handler) bb_err_clear();
    vm->nframes--;
}

static int line_index(VMProc *p, int32_t pc)
{
    int lo = 0, hi = p->nlines - 1, r = 0;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (p->lines[mid].pc <= pc) { r = mid; lo = mid + 1; } else hi = mid - 1;
    }
    return r;
}

static void locate(VM *vm, Frame *f)
{
    int32_t pc = (int32_t)(f->pc - vm->img->code);
    VMProc *p = f->proc;
    if (bb_err.located) return;
    bb_err.located = 1;
    bb_err.file = vm->img->files[p->file];
    bb_err.line = p->nlines ? p->lines[line_index(p, pc)].line : 0;
}

/* ---------- calling from C ---------- */

static bb_value default_for(VM *vm, VMProc *p, int i)
{
    int32_t d = p->param_def[i];
    if (d >= 0) return bb_v_dup(&vm->img->consts[d]);
    if (d == -2) return bb_v_missing();
    if (d == -3) {
        bb_value v = bb_v_make(BB_EMPTY);
        init_slot(vm, &v, &p->slots[i]);
        return v;
    }
    bb_raise(449, NULL);
    return bb_v_empty();
}

static void vm_call_proc(VM *vm, int32_t pidx, bb_obj *me, int argc, bb_value *argv, bb_value *ret)
{
    VMProc *p = &vm->img->procs[pidx];
    bb_value *base = vm->sp;
    int i, k = 0, me1 = p->cls >= 0 ? 1 : 0;
    if (p->code < 0) bb_raise(35, NULL);
    if (argc > p->nparams - me1) bb_raise(450, NULL);
    if (base + p->nlocals + 64 >= vm->stack_end) bb_raise(28, NULL);
    if (me1) base[k++] = bb_v_obj(bb_obj_retain(me));
    for (i = 0; i < p->nparams - me1; i++, k++) {
        int vt = p->slots[k].vt;
        bb_value *a = i < argc ? &argv[i] : NULL;
        bb_value tmp;
        if (!a || (a->type == BB_ERROR && (a->flags & BB_VF_MISSING) && vt != BB_VARIANT)) {
            vm->sp = base + k;
            base[k] = default_for(vm, p, k);
            continue;
        }
        if (p->param_byref[k] && (a->type & BB_REF) && (a->type == (BB_REF | vt) || (vt == BB_VARIANT && BB_BASETYPE(a->type) == BB_VARIANT))) {
            base[k] = *a;
            continue;
        }
        vm->sp = base + k;
        if (vt == BB_VARIANT) base[k] = bb_v_dup(bb_v_deref(a, &tmp));
        else if (vt & BB_ARRAY) {
            const bb_value *d = bb_v_deref(a, &tmp);
            if (!(d->type & BB_ARRAY)) bb_raise(13, NULL);
            base[k] = bb_v_dup(d);
        } else base[k] = bb_v_convert(a, vt);
    }
    vm->sp = base + p->nparams;
    prep_hidden(vm, p, base);
    {
        int entry = vm->nframes;
        Frame *f = push_frame(vm, pidx, base);
        f->ret = NULL;
        vm_exec(vm, entry);
    }
    /* result left at base[0] for functions */
    if (p->ret_slot >= 0) { *ret = *base; vm->sp = base; }
    else vm->sp = base;
}

/* ---------- arithmetic helpers ---------- */

static double getd(const bb_value *v)
{
    switch (v->type) {
    case BB_SINGLE: return v->u.f;
    case BB_DOUBLE: case BB_DATE: return v->u.d;
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_LONG: return v->u.l;
    case BB_BYTE: return v->u.by;
    case BB_CURRENCY: return (double)v->u.c / 10000.0;
    default: return bb_v_to_double(v);
    }
}

static int32_t geti(const bb_value *v)
{
    switch (v->type) {
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_BYTE: return v->u.by;
    case BB_LONG: return v->u.l;
    default: return bb_v_to_long(v);
    }
}

static int cmp_res(int op, int c)
{
    switch (op) {
    case BB_CMP_EQ: return c == 0;
    case BB_CMP_NE: return c != 0;
    case BB_CMP_LT: return c < 0;
    case BB_CMP_GT: return c > 0;
    case BB_CMP_LE: return c <= 0;
    default: return c >= 0;
    }
}

static bb_value int_tagged(int32_t r, int vt)
{
    bb_value v = bb_v_make((uint16_t)vt);
    switch (vt) {
    case BB_BOOLEAN: v.u.b = (bb_bool)r; break;
    case BB_BYTE: v.u.by = (bb_byte)r; break;
    case BB_INTEGER: v.u.i = (bb_int)r; break;
    default: v.u.l = r; break;
    }
    return v;
}

static int truth(const bb_value *v)
{
    if (v->type == BB_BOOLEAN) return v->u.b != 0;
    return bb_v_truth(v);
}

/* store owned value v into raw storage of type vt */
static void store_raw(VM *vm, void *p, int vt, bb_value v, int aux)
{
    switch (vt) {
    case BB_BYTE: *(bb_byte *)p = v.type == BB_BYTE ? v.u.by : bb_v_to_byte(&v); break;
    case BB_INTEGER: *(bb_int *)p = v.type == BB_INTEGER ? v.u.i : bb_v_to_int(&v); break;
    case BB_BOOLEAN: *(bb_bool *)p = v.type == BB_BOOLEAN ? v.u.b : bb_v_to_bool(&v); break;
    case BB_LONG: *(bb_long *)p = v.type == BB_LONG ? v.u.l : bb_v_to_long(&v); break;
    case BB_SINGLE: *(bb_single *)p = v.type == BB_SINGLE ? v.u.f : bb_v_to_single(&v); break;
    case BB_DOUBLE: *(bb_double *)p = v.type == BB_DOUBLE ? v.u.d : bb_v_to_double(&v); break;
    case BB_DATE: *(bb_date *)p = v.type == BB_DATE ? v.u.dt : bb_v_to_date(&v); break;
    case BB_CURRENCY: *(bb_cur *)p = v.type == BB_CURRENCY ? v.u.c : bb_v_to_cur(&v); break;
    case BB_STRING:
        if (v.type == BB_STRING) bb_str_set((bb_str **)p, v.u.s);
        else { bb_str_set((bb_str **)p, bb_v_to_str(&v)); bb_v_release(&v); }
        return;
    case BB_OBJECT:
        if (v.type == BB_OBJECT) bb_obj_set((bb_obj **)p, v.u.o);
        else { bb_obj_set((bb_obj **)p, bb_v_to_obj(&v)); bb_v_release(&v); }
        return;
    case BB_VARIANT:
        if (v.type & BB_REF) { bb_value t2; bb_v_set((bb_value *)p, bb_v_dup(bb_v_deref(&v, &t2))); return; }
        bb_v_set((bb_value *)p, v);
        return;
    case BB_UDT: {
        const bb_udt_desc *d = udt_desc(vm, aux);
        if (v.type != BB_UDT) bb_raise(13, NULL);
        if (!d) d = ((bb_udtbox *)v.u.p)->desc;
        bb_udt_copy(d, p, bb_v_udt_data(&v));
        bb_v_release(&v);
        return;
    }
    default:
        if (vt & BB_ARRAY) {
            bb_array **pa = (bb_array **)p;
            if (!(v.type & BB_ARRAY)) bb_raise(13, NULL);
            if (*pa && (*pa)->fixed) { bb_v_release(&v); bb_raise(10, NULL); }
            bb_arr_free(*pa);
            *pa = v.u.a;
            return;
        }
        bb_raise(13, NULL);
    }
    bb_v_release(&v);
}

static bb_value load_raw(VM *vm, void *p, int vt, int aux)
{
    if (vt == BB_UDT) {
        const bb_udt_desc *d = udt_desc(vm, aux);
        bb_value n = bb_v_udt_new(d);
        bb_udt_copy(d, bb_v_udt_data(&n), p);
        return n;
    }
    return bb_elem_load(vt, p);
}

/* ---------- the interpreter ---------- */

#define PUSH(v) (*sp++ = (v))
#define POP() (*--sp)
#define TOP (sp[-1])
#define NEXT() (pc++, *pc)

static void vm_exec(VM *vm, int entry)
{
    VMImage *img = vm->img;
    int32_t *code = img->code;
    bb_errframe ef;
    Frame *volatile fr0 = NULL;
    (void)fr0;
    bb_frame_push(&ef);
    if (setjmp(ef.jb) != 0) {
        /* run-time error */
        Frame *f;
        int i, handled = 0;
        bb_errtop = &ef;   /* still ours */
        if (vm->nframes > entry) locate(vm, &vm->frames[vm->nframes - 1]);
        for (i = vm->nframes - 1; i >= entry && !handled; i--) {
            f = &vm->frames[i];
            if (f->handler_mode != OE_NONE && !f->in_handler) {
                int li;
                while (vm->nframes - 1 > i) pop_frame(vm);
                vm->sp = f->base + f->proc->nlocals;
                f->err_pc = (int32_t)(f->pc - code);
                li = line_index(f->proc, f->err_pc);
                bb_err.line = f->proc->nlines ? f->proc->lines[li].line : 0;
                if (f->handler_mode == OE_GOTO) {
                    f->in_handler = 1;
                    f->pc = code + f->handler_pc;
                } else {
                    f->pc = code + (li + 1 < f->proc->nlines ? f->proc->lines[li + 1].pc : f->proc->lines[li].pc);
                }
                handled = 1;
            }
        }
        if (!handled) {
            while (vm->nframes > entry) pop_frame(vm);
            bb_frame_pop(&ef);
            bb_rethrow();
        }
    }
    {
        Frame *fr = &vm->frames[vm->nframes - 1];
        int32_t *pc = fr->pc;
        bb_value *sp = vm->sp;
        bb_value *L = fr->base;
        bb_value *G = vm->globals;
#define SYNC() (vm->sp = sp)
#define RELOAD() (fr = &vm->frames[vm->nframes - 1], pc = fr->pc, sp = vm->sp, L = fr->base)
        for (;;) {
            int32_t op = *pc;
            fr->pc = pc;
            vm->sp = sp;
            switch (op) {
            case I_NOP: pc++; break;
            case I_PUSHI: PUSH(bb_v_int((bb_int)pc[1])); pc += 2; break;
            case I_PUSHL: PUSH(bb_v_long(pc[1])); pc += 2; break;
            case I_PUSHB: { bb_value v = bb_v_make(BB_BOOLEAN); v.u.b = (bb_bool)pc[1]; PUSH(v); pc += 2; break; }
            case I_PUSHK: PUSH(img->consts[pc[1]]); pc += 2; break;
            case I_PUSHEMPTY: PUSH(bb_v_empty()); pc++; break;
            case I_PUSHNULL: PUSH(bb_v_null()); pc++; break;
            case I_PUSHNOTHING: PUSH(bb_v_obj(NULL)); pc++; break;
            case I_PUSHMISSING: PUSH(bb_v_missing()); pc++; break;
            case I_POP: sp--; release_slot(sp); pc++; break;
            case I_DUP: { bb_value v = bb_v_dup(&TOP); PUSH(v); pc++; break; }
            case I_SWAP: { bb_value t = sp[-1]; sp[-1] = sp[-2]; sp[-2] = t; pc++; break; }

            case I_LDL: PUSH(L[pc[1]]); pc += 2; break;
            case I_LDLS: { bb_value v = L[pc[1]]; bb_str_retain(v.u.s); PUSH(v); pc += 2; break; }
            case I_LDLV: { bb_value v; bb_v_copy(&v, &L[pc[1]]); PUSH(v); pc += 2; break; }
            case I_STL: { bb_value v = POP(); bb_value *d = &L[pc[1]]; d->u = v.u; d->type = v.type; pc += 2; break; }
            case I_STLS: { bb_value v = POP(); bb_value *d = &L[pc[1]]; bb_str_set(&d->u.s, v.type == BB_STRING ? v.u.s : NULL); d->type = BB_STRING; pc += 2; break; }
            case I_STLV: { bb_value v = POP(); bb_v_set(&L[pc[1]], v); pc += 2; break; }
            case I_LDG: PUSH(G[pc[1]]); pc += 2; break;
            case I_LDGS: { bb_value v = G[pc[1]]; bb_str_retain(v.u.s); PUSH(v); pc += 2; break; }
            case I_LDGV: { bb_value v; bb_v_copy(&v, &G[pc[1]]); PUSH(v); pc += 2; break; }
            case I_STG: { bb_value v = POP(); G[pc[1]].u = v.u; G[pc[1]].type = v.type; pc += 2; break; }
            case I_STGS: { bb_value v = POP(); bb_str_set(&G[pc[1]].u.s, v.type == BB_STRING ? v.u.s : NULL); G[pc[1]].type = BB_STRING; pc += 2; break; }
            case I_STGV: { bb_value v = POP(); bb_v_set(&G[pc[1]], v); pc += 2; break; }
            case I_LDF: case I_LDFV: {
                VMObj *o = (VMObj *)L[0].u.o;
                bb_value v;
                bb_obj_check(&o->hdr);
                if (op == I_LDF) v = o->f[pc[1]]; else bb_v_copy(&v, &o->f[pc[1]]);
                PUSH(v);
                pc += 2;
                break;
            }
            case I_STF: case I_STFV: {
                VMObj *o = (VMObj *)L[0].u.o;
                bb_value v = POP();
                if (op == I_STF) { o->f[pc[1]].u = v.u; o->f[pc[1]].type = v.type; }
                else if (o->vc->fields[pc[1]].vt == BB_STRING) {
                    bb_str_set(&o->f[pc[1]].u.s, v.type == BB_STRING ? v.u.s : NULL);
                    o->f[pc[1]].type = BB_STRING;
                } else bb_v_set(&o->f[pc[1]], v);
                pc += 2;
                break;
            }
            case I_LADDR: {
                bb_value r = bb_v_ref((uint16_t)pc[2], raw(&L[pc[1]], pc[2]));
                if (pc[2] == BB_UDT) r.aux = fr->proc->slots[pc[1]].udt;
                PUSH(r);
                pc += 3;
                break;
            }
            case I_GADDR: {
                bb_value r = bb_v_ref((uint16_t)pc[2], raw(&G[pc[1]], pc[2]));
                if (pc[2] == BB_UDT) r.aux = img->globals[pc[1]].udt;
                PUSH(r);
                pc += 3;
                break;
            }
            case I_FADDR: {
                VMObj *o = (VMObj *)L[0].u.o;
                bb_value r = bb_v_ref((uint16_t)pc[2], raw(&o->f[pc[1]], pc[2]));
                if (pc[2] == BB_UDT) r.aux = o->vc->fields[pc[1]].udt;
                PUSH(r);
                pc += 3;
                break;
            }
            case I_LDR: {
                bb_value *r = &L[pc[1]];
                PUSH(load_raw(vm, r->u.p, pc[2], r->aux));
                pc += 3;
                break;
            }
            case I_STR: {
                bb_value v = POP();
                bb_value *r = &L[pc[1]];
                store_raw(vm, r->u.p, pc[2], v, r->aux);
                pc += 3;
                break;
            }
            case I_LDIND: {
                bb_value r = POP();
                bb_value v = load_raw(vm, r.u.p, pc[1], r.aux);
                PUSH(v);
                pc += 2;
                break;
            }
            case I_STIND: {
                bb_value v = POP(), r = POP();
                store_raw(vm, r.u.p, pc[1], v, r.aux);
                pc += 2;
                break;
            }
            case I_ELEM: {
                int n = pc[1], i;
                int32_t idx[BB_MAXDIMS];
                bb_value r;
                bb_array *a;
                void *ep;
                for (i = n - 1; i >= 0; i--) { bb_value x = POP(); idx[i] = x.type == BB_LONG ? x.u.l : bb_v_to_long(&x); }
                r = POP();
                if (r.type & BB_REF) {
                    if ((r.type & BB_ARRAY)) a = *(bb_array **)r.u.p;
                    else a = bb_v_array((bb_value *)r.u.p);
                } else {
                    /* array rvalue: keep it alive */
                    bb_v_set(&fr->keep, r);
                    a = r.u.a;
                }
                if (n == 1) ep = bb_arr_elem1(a, idx[0]);
                else ep = bb_arr_elem(a, n, idx);
                r = bb_v_ref(a->etype, ep);
                r.aux = udt_index_of(vm, a->udt);
                PUSH(r);
                pc += 2;
                break;
            }
            case I_UFIELD: {
                bb_value r = POP();
                VMUdt *u = &img->udts[pc[1]];
                bb_field *f = &u->rtfields[pc[2]];
                char *base;
                if (r.type & BB_REF) base = (char *)r.u.p;
                else { bb_v_set(&fr->keep, r); base = (char *)bb_v_udt_data(&fr->keep); }
                r = bb_v_ref((f->type & BB_ARRAY) ? f->type : f->type, base + f->offset);
                r.aux = udt_index_of(vm, f->udt);
                PUSH(r);
                pc += 3;
                break;
            }
            case I_MFIELD: {
                bb_value o = POP(), r;
                VMObj *ob;
                if (o.type != BB_OBJECT || !o.u.o) { bb_v_release(&o); bb_raise(91, NULL); }
                ob = (VMObj *)o.u.o;
                bb_v_set(&fr->keep, o);
                r = bb_v_ref((uint16_t)pc[3], raw(&ob->f[pc[2]], pc[3]));
                r.aux = ob->vc->fields[pc[2]].udt;
                PUSH(r);
                pc += 4;
                break;
            }

            /* typed arithmetic */
#define BINI(name, expr_) case name: { bb_value b = POP(); bb_value *a = &TOP; expr_; pc++; break; }
            BINI(I_ADD_B, a->u.by = bb_add_by(a->u.by, b.u.by))
            BINI(I_SUB_B, a->u.by = bb_sub_by(a->u.by, b.u.by))
            BINI(I_MUL_B, a->u.by = bb_mul_by(a->u.by, b.u.by))
            BINI(I_ADD_I, a->u.i = bb_add_i(a->u.i, b.u.i); a->type = BB_INTEGER)
            BINI(I_SUB_I, a->u.i = bb_sub_i(a->u.i, b.u.i); a->type = BB_INTEGER)
            BINI(I_MUL_I, a->u.i = bb_mul_i(a->u.i, b.u.i); a->type = BB_INTEGER)
            BINI(I_IDIV_I, a->u.i = bb_idiv_i(a->u.i, b.u.i); a->type = BB_INTEGER)
            BINI(I_MOD_I, a->u.i = bb_mod_i(a->u.i, b.u.i); a->type = BB_INTEGER)
            BINI(I_ADD_L, a->u.l = bb_add_l(a->u.l, b.u.l))
            BINI(I_SUB_L, a->u.l = bb_sub_l(a->u.l, b.u.l))
            BINI(I_MUL_L, a->u.l = bb_mul_l(a->u.l, b.u.l))
            BINI(I_IDIV_L, a->u.l = bb_idiv_l(a->u.l, b.u.l))
            BINI(I_MOD_L, a->u.l = bb_mod_l(a->u.l, b.u.l))
            BINI(I_ADD_F, a->u.f = bb_csng((double)a->u.f + b.u.f))
            BINI(I_SUB_F, a->u.f = bb_csng((double)a->u.f - b.u.f))
            BINI(I_MUL_F, a->u.f = bb_csng((double)a->u.f * b.u.f))
            BINI(I_DIV_F, a->u.f = bb_csng(bb_fdiv(a->u.f, b.u.f)))
            BINI(I_ADD_D, a->u.d = bb_chk_double(a->u.d + b.u.d))
            BINI(I_SUB_D, a->u.d = bb_chk_double(a->u.d - b.u.d))
            BINI(I_MUL_D, a->u.d = bb_chk_double(a->u.d * b.u.d))
            BINI(I_DIV_D, a->u.d = bb_fdiv(a->u.d, b.u.d))
            BINI(I_POW_D, a->u.d = bb_pow(a->u.d, b.u.d))
            BINI(I_ADD_C, a->u.c = bb_cur_add(a->u.c, b.u.c))
            BINI(I_SUB_C, a->u.c = bb_cur_sub(a->u.c, b.u.c))
            BINI(I_MUL_C, a->u.c = bb_cur_mul(a->u.c, b.u.c))
            BINI(I_ADD_DT, a->u.d = bb_chk_double(getd(a) + getd(&b)); a->type = BB_DATE)
            BINI(I_SUB_DT, a->u.d = bb_chk_double(getd(a) - getd(&b)); a->type = BB_DATE)
            case I_NEG_I: TOP.u.i = bb_neg_i(TOP.u.i); pc++; break;
            case I_NEG_L: TOP.u.l = bb_neg_l(TOP.u.l); pc++; break;
            case I_NEG_F: TOP.u.f = -TOP.u.f; pc++; break;
            case I_NEG_D: TOP.u.d = -getd(&TOP); TOP.type = BB_DOUBLE; pc++; break;
            case I_NEG_C: TOP.u.c = bb_cur_sub(0, TOP.u.c); pc++; break;
            case I_CAT: {
                bb_value b = POP();
                bb_value *a = &TOP;
                bb_str *r = bb_str_concat(a->u.s, b.u.s);
                bb_str_release(a->u.s);
                bb_str_release(b.u.s);
                a->u.s = r;
                pc++;
                break;
            }
            case I_LIKE: {
                bb_value b = POP();
                bb_value *a = &TOP;
                bb_bool r = bb_like(a->u.s, b.u.s, pc[1]);
                bb_str_release(a->u.s);
                bb_str_release(b.u.s);
                a->type = BB_BOOLEAN;
                a->u.c = 0;
                a->u.b = r;
                pc += 2;
                break;
            }
            case I_CMP_I: { bb_value b = POP(); bb_value *a = &TOP; int32_t x = geti(a), y = geti(&b); a->type = BB_BOOLEAN; a->u.b = cmp_res(pc[1], x < y ? -1 : x > y) ? BB_TRUE : BB_FALSE; pc += 2; break; }
            case I_CMP_L: { bb_value b = POP(); bb_value *a = &TOP; int32_t x = a->u.l, y = b.u.l; a->type = BB_BOOLEAN; a->u.b = cmp_res(pc[1], x < y ? -1 : x > y) ? BB_TRUE : BB_FALSE; pc += 2; break; }
            case I_CMP_D: { bb_value b = POP(); bb_value *a = &TOP; double x = getd(a), y = getd(&b); a->type = BB_BOOLEAN; a->u.b = cmp_res(pc[1], x < y ? -1 : x > y) ? BB_TRUE : BB_FALSE; pc += 2; break; }
            case I_CMP_C: { bb_value b = POP(); bb_value *a = &TOP; bb_cur x = a->u.c, y = b.u.c; a->type = BB_BOOLEAN; a->u.c = 0; a->u.b = cmp_res(pc[1], x < y ? -1 : x > y) ? BB_TRUE : BB_FALSE; pc += 2; break; }
            case I_CMP_S: {
                bb_value b = POP();
                bb_value *a = &TOP;
                int c = (pc[1] == BB_CMP_EQ || pc[1] == BB_CMP_NE) && !pc[2] ? !bb_str_eq(a->u.s, b.u.s) : bb_str_cmp(a->u.s, b.u.s, pc[2]);
                bb_str_release(a->u.s);
                bb_str_release(b.u.s);
                a->type = BB_BOOLEAN;
                a->u.c = 0;
                a->u.b = cmp_res(pc[1], c) ? BB_TRUE : BB_FALSE;
                pc += 3;
                break;
            }
            case I_LOGIC: {
                bb_value b = POP();
                bb_value *a = &TOP;
                int32_t x = geti(a), y = geti(&b), r;
                switch (pc[1]) {
                case LG_AND: r = x & y; break;
                case LG_OR: r = x | y; break;
                case LG_XOR: r = x ^ y; break;
                case LG_EQV: r = ~(x ^ y); break;
                default: r = (~x) | y; break;
                }
                *a = int_tagged(r, pc[2]);
                pc += 3;
                break;
            }
            case I_NOT: { int32_t x = geti(&TOP); TOP = int_tagged(~x, pc[1]); pc += 2; break; }
            case I_VARITH: {
                bb_value b = POP(), a = POP(), r;
                switch (pc[1]) {
                case VA_ADD: r = bb_v_add(&a, &b); break;
                case VA_SUB: r = bb_v_sub(&a, &b); break;
                case VA_MUL: r = bb_v_mul(&a, &b); break;
                case VA_DIV: r = bb_v_div(&a, &b); break;
                case VA_IDIV: r = bb_v_idiv(&a, &b); break;
                case VA_MOD: r = bb_v_mod(&a, &b); break;
                case VA_POW: r = bb_v_pow(&a, &b); break;
                case VA_AND: r = bb_v_and(&a, &b); break;
                case VA_OR: r = bb_v_or(&a, &b); break;
                case VA_XOR: r = bb_v_xor(&a, &b); break;
                case VA_EQV: r = bb_v_eqv(&a, &b); break;
                default: r = bb_v_imp(&a, &b); break;
                }
                bb_v_release(&a);
                bb_v_release(&b);
                PUSH(r);
                pc += 2;
                break;
            }
            case I_VCMP: {
                bb_value b = POP(), a = POP(), r;
                sp += 2; SYNC();  /* keep them owned on the stack while comparing (errors) */
                r = bb_v_cmp(pc[1], &a, &b, pc[2]);
                sp -= 2;
                bb_v_release(&a);
                bb_v_release(&b);
                PUSH(r);
                pc += 3;
                break;
            }
            case I_VNEG: { bb_value a = POP(); bb_value r = bb_v_neg(&a); bb_v_release(&a); PUSH(r); pc++; break; }
            case I_VNOT: { bb_value a = POP(); bb_value r = bb_v_not(&a); bb_v_release(&a); PUSH(r); pc++; break; }
            case I_VCAT: { bb_value b = POP(), a = POP(); bb_value r = bb_v_cat(&a, &b); bb_v_release(&a); bb_v_release(&b); PUSH(r); pc++; break; }
            case I_IS: {
                bb_value b = POP(), a = POP();
                bb_value ta, tb;
                const bb_value *x = bb_v_deref(&a, &ta), *y = bb_v_deref(&b, &tb);
                int r;
                if ((x->type != BB_OBJECT && x->type != BB_EMPTY) || (y->type != BB_OBJECT && y->type != BB_EMPTY)) {
                    bb_v_release(&a); bb_v_release(&b);
                    bb_raise(424, NULL);
                }
                r = (x->type == BB_OBJECT ? x->u.o : NULL) == (y->type == BB_OBJECT ? y->u.o : NULL);
                bb_v_release(&a);
                bb_v_release(&b);
                PUSH(bb_v_bool(r));
                pc++;
                break;
            }
            case I_TYPEOF: {
                bb_value a = POP();
                bb_obj *o = a.type == BB_OBJECT ? a.u.o : NULL;
                int r;
                if (pc[1] == -1) r = o && o->cls == &bb_collection_class;
                else if (pc[1] == -2) r = 0;
                else r = bb_obj_is(o, &img->classes[pc[1]].rt);
                bb_v_release(&a);
                PUSH(bb_v_bool(r));
                pc += 2;
                break;
            }
            case I_CVT: {
                bb_value *a = &TOP;
                int vt = pc[1];
                if (a->type != vt) {
                    bb_value r = bb_v_convert(a, vt);
                    bb_v_release(a);
                    *a = r;
                }
                pc += 2;
                break;
            }
            case I_CVTFIX: {
                bb_value *a = &TOP;
                bb_str *s = bb_str_fixlen(a->u.s, pc[1]);
                bb_str_release(a->u.s);
                a->u.s = s;
                pc += 2;
                break;
            }
            case I_CHKCLS: {
                bb_value *a = &TOP;
                if (a->type == BB_OBJECT && a->u.o && !bb_obj_is(a->u.o, &img->classes[pc[1]].rt)) bb_raise(13, NULL);
                pc += 2;
                break;
            }
            case I_CVTARR: {
                bb_value *a = &TOP;
                if (!(a->type & BB_ARRAY)) bb_raise(13, NULL);
                if (pc[1] != BB_VARIANT && BB_BASETYPE(a->type) != pc[1]) bb_raise(13, NULL);
                pc += 2;
                break;
            }

            case I_JMP: pc = code + pc[1]; break;
            case I_JF: { bb_value v = POP(); int t = truth(&v); release_slot(&v); pc = t ? pc + 2 : code + pc[1]; break; }
            case I_JT: { bb_value v = POP(); int t = truth(&v); release_slot(&v); pc = t ? code + pc[1] : pc + 2; break; }

            case I_FORCHK_I: { bb_int c = L[pc[1]].u.i, l = L[pc[2]].u.i, s = L[pc[3]].u.i; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_I: { bb_value *cv = &L[pc[1]]; bb_int l = L[pc[2]].u.i, s = L[pc[3]].u.i; cv->u.i = bb_add_i(cv->u.i, s); pc = ((s >= 0) ? cv->u.i > l : cv->u.i < l) ? pc + 5 : code + pc[4]; break; }
            case I_FORCHK_L: { bb_long c = L[pc[1]].u.l, l = L[pc[2]].u.l, s = L[pc[3]].u.l; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_L: { bb_value *cv = &L[pc[1]]; bb_long l = L[pc[2]].u.l, s = L[pc[3]].u.l; cv->u.l = bb_add_l(cv->u.l, s); pc = ((s >= 0) ? cv->u.l > l : cv->u.l < l) ? pc + 5 : code + pc[4]; break; }
            case I_FORCHK_D: { double c = L[pc[1]].u.d, l = L[pc[2]].u.d, s = L[pc[3]].u.d; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_D: { bb_value *cv = &L[pc[1]]; double l = L[pc[2]].u.d, s = L[pc[3]].u.d; cv->u.d = cv->u.d + s; pc = ((s >= 0) ? cv->u.d > l : cv->u.d < l) ? pc + 5 : code + pc[4]; break; }
            case I_FORCHKV: {
                bb_value s = POP(), l = POP(), c = POP(), zero = bb_v_int(0);
                int done;
                int sg = bb_v_compare(&s, &zero, 0);
                int cm = bb_v_compare(&c, &l, 0);
                done = sg >= 0 ? cm == 1 : cm == -1;
                bb_v_release(&s); bb_v_release(&l); bb_v_release(&c);
                pc = done ? code + pc[1] : pc + 2;
                break;
            }

            case I_CALL: {
                int32_t pidx = pc[1];
                VMProc *p = &img->procs[pidx];
                bb_value *base = sp - p->nparams;
                int32_t *ret = pc + 2;
                SYNC();
                prep_hidden(vm, p, base);
                fr = push_frame(vm, pidx, base);
                fr->ret = ret;
                pc = fr->pc;
                sp = vm->sp;
                L = fr->base;
                break;
            }
            case I_CALLM: {
                int32_t cls = pc[1], slot = pc[2], argc = pc[3], pidx;
                bb_value *base = sp - argc - 1;
                bb_obj *o = base->type == BB_OBJECT ? base->u.o : NULL;
                VMProc *p;
                if (!o) bb_raise(91, NULL);
                if (slot < 0) pidx = -1 - slot;
                else {
                    VMObj *vo = (VMObj *)o;
                    int j;
                    if (!is_vmobj(vm, o)) bb_raise(438, NULL);
                    if (vo->vc == &img->classes[cls]) pidx = vo->vc->vtbl[slot];
                    else {
                        pidx = -1;
                        for (j = 0; j < vo->vc->nifaces; j++)
                            if (vo->vc->iface_cls[j] == cls) pidx = vo->vc->iface_vtbl[j][slot];
                        if (pidx < 0) bb_raise(438, NULL);
                    }
                }
                p = &img->procs[pidx];
                (void)p;
                SYNC();
                prep_hidden(vm, p, base);
                {
                    int32_t *ret = pc + 4;
                    fr = push_frame(vm, pidx, base);
                    fr->ret = ret;
                }
                pc = fr->pc;
                sp = vm->sp;
                L = fr->base;
                break;
            }
            case I_CALLB: {
                int argc = pc[2], i;
                bb_value *args = sp - argc, r = bb_v_empty();
                call_builtin(pc[1], argc, args, &r);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                sp = args;
                if (pc[3]) PUSH(r); else bb_v_release(&r);
                pc += 4;
                break;
            }
            case I_CALLD: {
                int argc = pc[2] & 0xffff, hasret = (pc[2] >> 16) != 0, i;
                bb_value *args = sp - argc;
                uint32_t w[16];
                uint32_t r;
                for (i = 0; i < argc && i < 16; i++) {
                    bb_value *a = &args[i];
                    if (a->type & BB_REF) w[i] = (uint32_t)(uintptr_t)a->u.p;
                    else if (a->type == BB_STRING) w[i] = (uint32_t)(uintptr_t)bb_str_ptr(a->u.s);
                    else if (a->type == BB_OBJECT) w[i] = (uint32_t)(uintptr_t)a->u.o;
                    else w[i] = (uint32_t)bb_v_to_long(a);
                }
                r = bb_declare_call(&img->decls[pc[1]], argc, w);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                sp = args;
                if (hasret) PUSH(bb_v_long((bb_long)r));
                pc += 3;
                break;
            }
            case I_INVOKE: {
                int argc = pc[3], i;
                bb_value *args = sp - argc, *recv = args - 1, r;
                bb_str *name = img->consts[pc[1]].u.s;
                r = bb_v_invoke(recv, bb_str_ptr(name), pc[2], argc, args);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                release_slot(recv);
                sp = recv;
                PUSH(r);
                pc += 4;
                break;
            }
            case I_VINDEX: {
                int argc = pc[1], i;
                bb_value *args = sp - argc, *recv = args - 1, r;
                r = bb_v_index(recv, argc, args);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                release_slot(recv);
                sp = recv;
                PUSH(r);
                pc += 2;
                break;
            }
            case I_VSTOREIDX: {
                int argc = pc[1], i;
                bb_value *val = sp - 1, *args = val - argc, *ref = args - 1;
                bb_v_index_store((bb_value *)ref->u.p, argc, args, val);
                release_slot(val);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                sp = ref;
                pc += 2;
                break;
            }
            case I_NEW: {
                bb_obj *o;
                o = new_object(vm, pc[1]);
                PUSH(bb_v_obj(o));
                pc += 2;
                break;
            }
            case I_NEWCOLL: PUSH(bb_v_obj(bb_collection_new())); pc++; break;
            case I_RET: {
                VMProc *p = fr->proc;
                bb_value *base = fr->base, rv = bb_v_empty();
                int32_t *ret = fr->ret;
                int has = p->ret_slot >= 0;
                if (has) { rv = base[p->ret_slot]; base[p->ret_slot] = bb_v_empty(); }
                SYNC();
                pop_frame(vm);
                sp = base;
                if (has) PUSH(rv);
                vm->sp = sp;
                if (vm->nframes <= entry) {
                    bb_frame_pop(&ef);
                    return;
                }
                fr = &vm->frames[vm->nframes - 1];
                L = fr->base;
                pc = ret;
                break;
            }
            case I_END: bb_frame_pop(&ef); bb_end(); break;
            case I_STOP: bb_frame_pop(&ef); bb_console_flush(); bb_print_cstr(0, "Stop\n"); bb_exit(0); break;

            case I_ONERR:
                fr->handler_mode = pc[1];
                fr->handler_pc = pc[2];
                if (!fr->in_handler) bb_err_clear();
                pc += 3;
                break;
            case I_RESUME: {
                VMProc *p = fr->proc;
                int li;
                if (!fr->in_handler && pc[1] != RS_LABEL) bb_raise(20, NULL);
                li = line_index(p, fr->err_pc);
                fr->in_handler = 0;
                bb_err_clear();
                if (pc[1] == RS_PLAIN) pc = code + p->lines[li].pc;
                else if (pc[1] == RS_NEXT) pc = code + (li + 1 < p->nlines ? p->lines[li + 1].pc : p->lines[li].pc);
                else pc = code + pc[2];
                sp = fr->base + p->nlocals;
                break;
            }
            case I_ERRRAISE: pc++; break;
            case I_ERROP:
                switch (pc[1]) {
                case EO_NUMBER: PUSH(bb_v_long(bb_err_number())); break;
                case EO_DESC: PUSH(bb_v_str(bb_err_description())); break;
                case EO_SOURCE: PUSH(bb_v_str(bb_err_source())); break;
                case EO_SETNUMBER: { bb_value v = POP(); bb_err_set_number(v.u.l); break; }
                case EO_SETDESC: { bb_value v = POP(); bb_err_set_description(v.u.s); bb_v_release(&v); break; }
                case EO_SETSOURCE: { bb_value v = POP(); bb_err_set_source(v.u.s); bb_v_release(&v); break; }
                case EO_CLEAR: bb_err_clear(); break;
                case EO_RAISE: {
                    bb_value d = POP(), s = POP(), n = POP();
                    sp += 3; SYNC();
                    bb_err_raise_v(n.u.l, &s, &d);
                    break;
                }
                case EO_ERROR: { bb_value v = POP(); bb_raise(v.u.l, NULL); break; }
                }
                pc += 2;
                break;
            case I_GOSUB:
                if (vm->ngosub == vm->capgosub) {
                    vm->capgosub = vm->capgosub ? vm->capgosub * 2 : 64;
                    vm->gosub = (int32_t *)realloc(vm->gosub, sizeof(int32_t) * (size_t)vm->capgosub);
                }
                vm->gosub[vm->ngosub++] = (int32_t)(pc + 2 - code);
                pc = code + pc[1];
                break;
            case I_RETSUB:
                if (vm->ngosub <= fr->gs_base) bb_raise(3, NULL);
                pc = code + vm->gosub[--vm->ngosub];
                break;
            case I_ONGOTO: {
                int n = pc[1] & 0xffff, gs = (pc[1] & 0x10000) != 0;
                bb_value v = POP();
                int32_t k = v.u.l;
                if (k < 0 || k > 255) bb_raise(5, NULL);
                if (k >= 1 && k <= n) {
                    if (gs) {
                        if (vm->ngosub == vm->capgosub) {
                            vm->capgosub = vm->capgosub ? vm->capgosub * 2 : 64;
                            vm->gosub = (int32_t *)realloc(vm->gosub, sizeof(int32_t) * (size_t)vm->capgosub);
                        }
                        vm->gosub[vm->ngosub++] = (int32_t)(pc + 2 + n - code);
                    }
                    pc = code + pc[1 + k];
                } else pc += 2 + n;
                break;
            }

            case I_SETFN: { bb_value v = POP(); fr->fn = (int)v.u.l; pc++; break; }
            case I_PRT: { bb_value v = POP(); sp++; SYNC(); bb_print_value(fr->fn, &v); sp--; release_slot(&v); pc++; break; }
            case I_PRTCOMMA: bb_print_comma(fr->fn); pc++; break;
            case I_PRTNL: bb_print_nl(fr->fn); pc++; break;
            case I_PRTSPC: { bb_value v = POP(); bb_print_spc(fr->fn, v.u.l); pc++; break; }
            case I_PRTTAB: { bb_value v = POP(); bb_print_tab(fr->fn, v.u.l); pc++; break; }
            case I_WRT: { bb_value v = POP(); sp++; SYNC(); bb_write_value(fr->fn, &v, pc[1]); sp--; release_slot(&v); pc += 2; break; }
            case I_INFIELD: PUSH(bb_input_field(fr->fn, pc[1])); pc += 2; break;
            case I_INEND: bb_input_end(fr->fn); pc++; break;
            case I_LINEIN: PUSH(bb_v_str(bb_input_line(fr->fn))); pc++; break;
            case I_PROMPT: { bb_value v = POP(); bb_input_prompt(v.u.s, pc[1]); release_slot(&v); pc += 2; break; }
            case I_OPEN: {
                bb_value rl = POP(), fn = POP(), path = POP();
                sp += 3; SYNC();
                bb_open(path.u.s, pc[1], 0, fn.u.l, rl.u.l);
                sp -= 3;
                release_slot(&path);
                pc += 2;
                break;
            }
            case I_CLOSE: { bb_value v = POP(); bb_close(v.u.l); pc++; break; }
            case I_CLOSEALL: bb_close_all(); pc++; break;
            case I_GETREC: case I_PUTREC: {
                bb_value r = POP(), rec = POP(), fn = POP();
                int vt = pc[1];
                const bb_udt_desc *d = pc[2] >= 0 ? udt_desc(vm, pc[2]) : NULL;
                void *p = r.u.p;
                if (!(r.type & BB_REF)) { bb_v_set(&fr->keep, r); p = (fr->keep.type == BB_UDT) ? bb_v_udt_data(&fr->keep) : (void *)&fr->keep.u; if (vt == BB_VARIANT) p = &fr->keep; }
                if (op == I_GETREC) bb_get(fn.u.l, rec.u.l, vt, d, p);
                else bb_put(fn.u.l, rec.u.l, vt, d, p);
                pc += 3;
                break;
            }
            case I_SEEK: { bb_value pos = POP(), fn = POP(); bb_seek_set(fn.u.l, pos.u.l); pc++; break; }
            case I_NAMEF: {
                bb_value b = POP(), a = POP();
                sp += 2; SYNC();
                bb_name(a.u.s, b.u.s);
                sp -= 2;
                release_slot(&a); release_slot(&b);
                pc++;
                break;
            }
            case I_REDIM: {
                int n = pc[1], pres = pc[2], vt = pc[3], i;
                int32_t lb[BB_MAXDIMS], ub[BB_MAXDIMS];
                bb_value r;
                for (i = n - 1; i >= 0; i--) { bb_value u = POP(), l = POP(); ub[i] = u.u.l; lb[i] = l.u.l; }
                r = POP();
                if (BB_BASETYPE(r.type) == BB_VARIANT && !(r.type & BB_ARRAY)) {
                    bb_value *v = (bb_value *)r.u.p;
                    if (v->type & BB_ARRAY) {
                        bb_arr_redim(&v->u.a, v->u.a ? v->u.a->etype : vt, v->u.a ? v->u.a->udt : udt_desc(vm, pc[4]), n, lb, ub, pres);
                    } else {
                        bb_array *a = NULL;
                        bb_arr_redim(&a, vt, udt_desc(vm, pc[4]), n, lb, ub, 0);
                        bb_v_set(v, bb_v_arr(a));
                    }
                } else bb_arr_redim((bb_array **)r.u.p, vt, udt_desc(vm, pc[4]), n, lb, ub, pres);
                pc += 5;
                break;
            }
            case I_ERASE: {
                bb_value r = POP();
                if (BB_BASETYPE(r.type) == BB_VARIANT && !(r.type & BB_ARRAY)) {
                    bb_value *v = (bb_value *)r.u.p;
                    if (v->type & BB_ARRAY) bb_arr_erase(&v->u.a);
                } else bb_arr_erase((bb_array **)r.u.p);
                pc++;
                break;
            }
            case I_MIDSET: {
                bb_value v = POP(), len = POP(), st = POP(), r = POP();
                sp++; *(sp - 1) = v; SYNC();
                if (BB_BASETYPE(r.type) == BB_VARIANT) {
                    bb_value *x = (bb_value *)r.u.p;
                    if (x->type != BB_STRING) bb_raise(13, NULL);
                    bb_mid_assign(&x->u.s, st.u.l, len.u.l, v.u.s);
                } else bb_mid_assign((bb_str **)r.u.p, st.u.l, len.u.l, v.u.s);
                sp--;
                release_slot(&v);
                pc++;
                break;
            }
            case I_FEBEGIN: {
                bb_value c = POP();
                FeObj *f = (FeObj *)bb_obj_new(&fe_class);
                bb_value view;
                bb_v_set(&L[pc[1]], bb_v_obj(&f->hdr));
                if (c.type & BB_REF) {
                    if (c.type & BB_ARRAY) { view = bb_v_make((uint16_t)(c.type & ~BB_REF)); view.u.a = *(bb_array **)c.u.p; }
                    else view = *(bb_value *)c.u.p;
                    bb_foreach_begin(&f->fe, &view);
                } else {
                    f->hold = c;
                    bb_foreach_begin(&f->fe, &f->hold);
                }
                f->active = 1;
                pc += 2;
                break;
            }
            case I_FENEXT: {
                FeObj *f = (FeObj *)L[pc[1]].u.o;
                bb_value out;
                if (bb_foreach_next(&f->fe, &out)) { PUSH(out); pc += 3; }
                else pc = code + pc[2];
                break;
            }
            case I_FEEND: bb_v_set(&L[pc[1]], bb_v_empty()); pc += 2; break;
            case I_RAISEEV: {
                int argc = pc[3], i;
                bb_value *args = sp - argc;
                VMClass *vc = &img->classes[pc[1]];
                bb_event_raise(L[0].u.o, pc[2], vc->events[pc[2]], argc, args);
                for (i = 0; i < argc; i++) release_slot(&args[i]);
                sp = args;
                pc += 4;
                break;
            }
            case I_WEVCONN: {
                VMWev *w = &img->wevs[pc[3]];
                bb_value *var, *hidden;
                WevConn *cn;
                bb_obj *me = NULL;
                if (pc[1]) {
                    VMObj *o = (VMObj *)L[0].u.o;
                    var = &o->f[pc[2]];
                    hidden = &o->f[w->hidden];
                    me = &o->hdr;
                } else {
                    var = &G[pc[2]];
                    hidden = &G[w->hidden];
                }
                wev_disconnect(hidden);
                if (var->type == BB_OBJECT && var->u.o) {
                    cn = (WevConn *)calloc(1, sizeof *cn);
                    cn->src = bb_obj_retain(var->u.o);
                    cn->sink = bb_event_connect(var->u.o, vm_fire, me, pc[3]);
                    hidden->u.p = cn;
                }
                pc += 4;
                break;
            }
            case I_ARRLIT: {
                int n = pc[1], i;
                int32_t lb = 0, ub = n - 1;
                bb_array *a = bb_arr_new(BB_VARIANT, NULL, 1, &lb, &ub);
                bb_value *args = sp - n;
                for (i = 0; i < n; i++) ((bb_value *)a->data)[i] = args[i];
                sp = args;
                PUSH(bb_v_arr(a));
                pc += 2;
                break;
            }
            default:
                fprintf(stderr, "boing vm: bad opcode %ld at %ld\n", (long)op, (long)(pc - code));
                bb_raise(51, NULL);
            }
        }
    }
}

/* ---------- program ops ---------- */

static void *ops_find_proc(const char *module, const char *name)
{
    VMImage *img = g_vm->img;
    int32_t i;
    for (i = 0; i < img->nprocs; i++) {
        VMProc *p = &img->procs[i];
        if (p->code < 0 || p->cls >= 0 || p->kind == PK_MAIN) continue;
        if (strcasecmp(p->name, name) != 0) continue;
        if (module && strcasecmp(img->modules[p->module], module) != 0) continue;
        return (void *)(intptr_t)(i + 1);
    }
    return NULL;
}

static void ops_call_proc(void *proc, int argc, bb_value *argv, bb_value *ret)
{
    vm_call_proc(g_vm, (int32_t)(intptr_t)proc - 1, NULL, argc, argv, ret);
}

static void *ops_find_global(const char *module, const char *name, int *type)
{
    VMImage *img = g_vm->img;
    int32_t i;
    for (i = 0; i < img->nglobals; i++) {
        VMSlot *s = &img->globals[i];
        if (!s->name || strcasecmp(s->name, name) != 0) continue;
        if (module && strcasecmp(img->modules[img->global_mod[i]], module) != 0) continue;
        *type = s->vt;
        return raw(&g_vm->globals[i], s->vt);
    }
    return NULL;
}

static const bb_program_ops vm_ops = {ops_find_proc, ops_call_proc, ops_find_global};

static void prepare(VM *vm)
{
    VMImage *img = vm->img;
    int32_t i, j;
    for (i = 0; i < img->nudts; i++) layout_udt(vm, i);
    for (i = 0; i < img->nclasses; i++) {
        VMClass *vc = &img->classes[i];
        bb_class *c = &vc->rt;
        memset(c, 0, sizeof *c);
        c->name = vc->name;
        c->size = (uint32_t)(offsetof(VMObj, f) + sizeof(bb_value) * (size_t)(vc->nfields ? vc->nfields : 1));
        c->find = vmobj_find;
        c->invoke = vmobj_invoke;
        c->terminate = vmobj_terminate;
        c->user = vc;
        vc->rt_ifaces = (bb_iface *)xcalloc((size_t)vc->nifaces + 1, sizeof(bb_iface));
        for (j = 0; j < vc->nifaces; j++) vc->rt_ifaces[j].iface = &img->classes[vc->iface_cls[j]].rt;
        c->ifaces = vc->rt_ifaces;
        c->nifaces = vc->nifaces;
    }
    vm->globals = (bb_value *)xcalloc((size_t)img->nglobals + 1, sizeof(bb_value));
}

int vm_run(VMImage *img, int argc, char **argv)
{
    VM vm;
    int32_t i;
    memset(&vm, 0, sizeof vm);
    vm.img = img;
    g_vm = &vm;
    bb_rt_init(argc, argv);
    prepare(&vm);
    {
        size_t n = (size_t)(img->stack > 65536 ? img->stack / 16 : 16384);
        if (n < 16384) n = 16384;
        vm.stack = (bb_value *)xcalloc(n, sizeof(bb_value));
        vm.stack_end = vm.stack + n;
        vm.sp = vm.stack;
        vm.maxframes = 4096;
        vm.frames = (Frame *)xcalloc((size_t)vm.maxframes, sizeof(Frame));
    }
    bb_set_program(&vm_ops);
    {
        bb_errframe f;
        bb_frame_push(&f);
        if (setjmp(f.jb) == 0) {
            for (i = 0; i < img->nglobals; i++) init_slot(&vm, &vm.globals[i], &img->globals[i]);
            if (img->startup >= 0) {
                bb_value r = bb_v_empty();
                vm_call_proc(&vm, img->startup, NULL, 0, NULL, &r);
                bb_v_release(&r);
            }
            bb_frame_pop(&f);
        } else {
            bb_frame_pop(&f);
            bb_fatal_error();
        }
    }
    bb_rt_shutdown();
    return 0;
}

/* ---------- disassembler ---------- */

void vm_disasm(VMImage *img, FILE *out)
{
    int32_t i;
    for (i = 0; i < img->nprocs; i++) {
        VMProc *p = &img->procs[i];
        int32_t pc, end = img->ncode;
        int k;
        if (p->code < 0) continue;
        for (k = 0; k < img->nprocs; k++) if (img->procs[k].code > p->code && img->procs[k].code < end) end = img->procs[k].code;
        fprintf(out, "proc %ld %s (params %ld, locals %ld)\n", (long)i, p->name, (long)p->nparams, (long)p->nlocals);
        for (pc = p->code; pc < end;) {
            int32_t op = img->code[pc], n, j;
            if (op < 0 || op >= I__COUNT) { fprintf(out, "  %5ld  ???\n", (long)pc); pc++; continue; }
            n = bb_opwords[op];
            if (op == I_ONGOTO) n = 1 + (img->code[pc + 1] & 0xffff);
            fprintf(out, "  %5ld  %-10s", (long)pc, bb_opnames[op]);
            for (j = 1; j <= n; j++) fprintf(out, " %ld", (long)img->code[pc + j]);
            fprintf(out, "\n");
            pc += 1 + n;
        }
    }
}
