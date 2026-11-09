/* vm.c - the Boing BASIC bytecode interpreter */
#include "bytecode.h"
#include "jit.h"
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
    int32_t retdst;         /* R_CALLS: caller slot for the result (-1: push it) */
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

#ifdef BB_OPTIME
/* build with -DBB_OPTIME -DBB_NO_THREADED: time spent per opcode on stderr at exit */
#if defined(__PPC__) || defined(__powerpc__)
static inline uint32_t bb_optime_now(void) { uint32_t t; __asm__ volatile("mftb %0" : "=r"(t)); return t; }
#else
#include <time.h>
static inline uint32_t bb_optime_now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (uint32_t)(ts.tv_sec * 1000000000ull + ts.tv_nsec); }
#endif
static unsigned long long vm_optime[I__COUNT], vm_optime_cnt[I__COUNT];
static int vm_optime_prev;
static uint32_t vm_optime_t;
static void vm_optime_dump(void)
{
    int i, j, idx[I__COUNT];
    unsigned long long tot = 0;
    for (i = 0; i < I__COUNT; i++) { idx[i] = i; tot += vm_optime[i]; }
    for (i = 0; i < I__COUNT; i++)
        for (j = i + 1; j < I__COUNT; j++)
            if (vm_optime[idx[j]] > vm_optime[idx[i]]) { int t = idx[i]; idx[i] = idx[j]; idx[j] = t; }
    for (i = 0; i < 25 && vm_optime[idx[i]]; i++)
        fprintf(stderr, "time %-12s %12llu ticks %5.1f%%  n=%llu  %.1f/op\n", bb_opnames[idx[i]], vm_optime[idx[i]],
                100.0 * (double)vm_optime[idx[i]] / (double)tot, vm_optime_cnt[idx[i]], (double)vm_optime[idx[i]] / (double)(vm_optime_cnt[idx[i]] ? vm_optime_cnt[idx[i]] : 1));
}
#endif

#ifdef BB_OPSTATS
/* build with -DBB_OPSTATS -DBB_NO_THREADED: dynamic opcode counts on stderr at exit */
static unsigned long long vm_opstats[I__COUNT];
static unsigned long long *vm_pcstats;     /* per bytecode offset */
static unsigned long long *vm_pairs;       /* consecutive op pairs */
static int vm_prevop;
static VMImage *vm_stats_img;
static void vm_opstats_dump(void)
{
    int i, j, idx[I__COUNT];
    unsigned long long tot = 0;
    for (i = 0; i < I__COUNT; i++) { idx[i] = i; tot += vm_opstats[i]; }
    for (i = 0; i < I__COUNT; i++)
        for (j = i + 1; j < I__COUNT; j++)
            if (vm_opstats[idx[j]] > vm_opstats[idx[i]]) { int t = idx[i]; idx[i] = idx[j]; idx[j] = t; }
    for (i = 0; i < 40 && vm_opstats[idx[i]]; i++)
        fprintf(stderr, "%-12s %12llu %5.1f%%\n", bb_opnames[idx[i]], vm_opstats[idx[i]], 100.0 * (double)vm_opstats[idx[i]] / (double)tot);
    if (vm_pairs) {
        int a, b, k;
        for (k = 0; k < 25; k++) {
            unsigned long long best = 0;
            int ba = 0, bb = 0;
            for (a = 0; a < I__COUNT; a++)
                for (b = 0; b < I__COUNT; b++)
                    if (vm_pairs[a * I__COUNT + b] > best) { best = vm_pairs[a * I__COUNT + b]; ba = a; bb = b; }
            if (!best) break;
            fprintf(stderr, "pair %-12s %-12s %12llu %5.1f%%\n", bb_opnames[ba], bb_opnames[bb], best, 100.0 * (double)best / (double)tot);
            vm_pairs[ba * I__COUNT + bb] = 0;
        }
    }
    if (vm_pcstats && vm_stats_img) {
        /* per procedure */
        VMImage *img = vm_stats_img;
        int32_t p, pc;
        for (p = 0; p < img->nprocs; p++) {
            int32_t a = img->procs[p].code, b = img->ncode, k;
            unsigned long long n = 0;
            if (a < 0) continue;
            for (k = 0; k < img->nprocs; k++) if (img->procs[k].code > a && img->procs[k].code < b) b = img->procs[k].code;
            for (pc = a; pc < b; pc++) n += vm_pcstats[pc];
            if (n * 100 > tot) fprintf(stderr, "proc %-16s %12llu %5.1f%%\n", img->procs[p].name, n, 100.0 * (double)n / (double)tot);
        }
    }
}
#endif

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
    /* As New objects are created on first use (I_AUTONEW) */
}

static inline void release_slot(bb_value *v)
{
    uint16_t t = v->type;
    if (t <= BB_DATE || t == BB_BOOLEAN || t == BB_BYTE || (t & BB_REF)) { v->type = BB_EMPTY; return; }
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
    f->proc = p;
    f->pidx = pidx;
    f->base = base;
    f->pc = vm->img->code + p->code;
    f->ret = NULL;
    f->handler_mode = OE_NONE;
    f->handler_pc = 0;
    f->in_handler = 0;
    f->err_pc = 0;
    f->keep.type = BB_EMPTY;
    f->fn = 0;
    f->retdst = -1;
    f->gs_base = vm->ngosub;
    if (p->rt_plain) {
        /* no ByRef parameters, only simple locals */
        for (i = p->nparams; i < p->hidden; i++) {
            base[i].type = p->slots[i].vt == BB_VARIANT ? BB_EMPTY : p->slots[i].vt;
            base[i].flags = 0;
            base[i].u.c = 0;
        }
        vm->sp = base + p->nlocals;
        return f;
    }
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
    }
    vm->sp = base + p->nlocals;
    return f;
}

/* plain procedures: one copy of a template sets up every slot after the parameters */
static inline Frame *push_plain(VM *vm, VMProc *p, int32_t pidx, bb_value *base)
{
    Frame *f;
    if (BB_UNLIKELY(vm->nframes >= vm->maxframes || base + p->nlocals + 64 >= vm->stack_end)) bb_raise(28, NULL);
    f = &vm->frames[vm->nframes++];
    f->proc = p;
    f->pidx = pidx;
    f->base = base;
    f->pc = vm->img->code + p->code;
    f->ret = NULL;
    f->handler_mode = OE_NONE;
    f->in_handler = 0;
    f->keep.type = BB_EMPTY;
    f->fn = 0;
    f->retdst = -1;
    f->gs_base = vm->ngosub;
    memcpy(base + p->nparams, p->rt_tmpl, sizeof(bb_value) * (size_t)(p->nlocals - p->nparams));
    vm->sp = base + p->nlocals;
    return f;
}

/* hidden slots: initialised before params are processed */
static void prep_hidden(VM *vm, VMProc *p, bb_value *base)
{
    int32_t i;
    /* hidden by-ref slots start Empty; register temporaries carry their type tag */
    for (i = p->hidden; i < p->nlocals; i++) {
        int vt = p->slots[i].vt;
        base[i] = bb_v_make((uint16_t)(vt == BB_INTEGER || vt == BB_LONG || vt == BB_DOUBLE || vt == BB_SINGLE ? vt : BB_EMPTY));
    }
    (void)vm;
}

static inline void pop_frame(VM *vm)
{
    Frame *f = &vm->frames[vm->nframes - 1];
    int32_t i, n = f->proc->nlocals;
    bb_value *b = f->base;
    for (i = 0; i < n; i++) release_slot(&b[i]);
    if (f->keep.type != BB_EMPTY) bb_v_release(&f->keep);
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
    bb_value back[16];          /* ByRef through a reference of another type: copied back */
    int nback = 0, backi[16];
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
        if (p->param_byref[k] && (a->type & BB_REF) && nback < 16 && !(vt & BB_ARRAY) && vt != BB_UDT) {
            back[nback] = vt == BB_VARIANT ? bb_v_dup(bb_v_deref(a, &tmp)) : bb_v_convert(a, vt);
            backi[nback] = i;
            base[k] = bb_v_ref((uint16_t)vt, raw(&back[nback], vt));
            nback++;
            continue;
        }
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
    for (i = 0; i < nback; i++) {
        bb_v_store_ref(&argv[backi[i]], &back[i]);
        bb_v_release(&back[i]);
    }
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
            if (*pa && (*pa)->fixed) bb_raise(10, NULL);
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

/* Ctrl-C polling at loop back-edges and calls */
static void vm_poll(VM *vm)
{
    Frame *f = &vm->frames[vm->nframes - 1];
    int32_t pc = (int32_t)(f->pc - vm->img->code);
    bb_file = vm->img->files[f->proc->file];
    bb_line = f->proc->nlines ? f->proc->lines[line_index(f->proc, pc)].line : 0;
    bb_poll_slow();
}
#define POLL() do { if (BB_UNLIKELY(--bb_poll_count < 0)) { fr->pc = pc; vm->sp = sp; vm_poll(vm); } } while (0)
/* a taken backward branch: poll, then enter compiled code for the loop if it is hot */
/* run compiled code from loop head bt_ (jf_ its code), and on into other compiled loop
   heads it leaves for (an outer loop) */
#define JITCHAIN(bt0_, jf0_) { int32_t bt_ = (bt0_); bb_jitfn jf_ = (jf0_); \
    while (jf_) { int32_t np_; jc.L = L; \
        if (BB_UNLIKELY(jit_logging)) jit_log("call @%ld fn=%p ctx=%p L=%p", (long)bt_, (void *)jf_, (void *)&jc, (void *)L); \
        if (BB_UNLIKELY(jit_stats != NULL)) jit_stats[bt_]++; \
        np_ = jf_(&jc); \
        if (BB_UNLIKELY(jit_logging)) jit_log("ret %ld", (long)np_); \
        pc = code + np_; \
        /* left from the middle (an op it hands to the interpreter) more often than not: the \
           compiled code is not paying for itself here; switch it off */ \
        if (np_ > bt_ && np_ < img->jitend[bt_] && ++img->jitexit[bt_] * 2 > ++img->jitent[bt_] && img->jitent[bt_] >= 32) { \
            img->jitcode[bt_] = NULL; img->jitno[bt_] = 1; \
            if (BB_UNLIKELY(jit_logging)) jit_log("off @%ld: %lu exits in %lu entries", (long)bt_, (unsigned long)img->jitexit[bt_], (unsigned long)img->jitent[bt_]); } \
        else if (!(np_ > bt_ && np_ < img->jitend[bt_])) img->jitent[bt_]++; \
        if (np_ == bt_ || bb_poll_count < 0) break; \
        jf_ = img->jitcode[np_]; \
        if (!jf_ && !img->jitno[np_]) jf_ = jit_hot(img, fr->proc, np_); \
        bt_ = np_; } }
/* a taken backward branch: poll, then enter compiled code for the loop if it is hot */
#define BACKJUMP(t_) { int32_t tj_ = (t_); POLL(); pc = code + tj_; \
    if (BB_UNLIKELY(jit_on)) { bb_jitfn j0_ = img->jitcode[tj_]; \
        if (!j0_ && !img->jitno[tj_]) j0_ = jit_hot(img, fr->proc, tj_); \
        JITCHAIN(tj_, j0_) } }
/* entering a loop body at pc: straight into its code if it is already compiled */
#define JITENTER() { if (BB_UNLIKELY(jit_on)) { int32_t te_ = (int32_t)(pc - code); bb_jitfn j0_ = img->jitcode[te_]; \
        if (j0_) JITCHAIN(te_, j0_) } }

/* register-form helpers */
const int bb_vmobj_f_offset = (int)offsetof(VMObj, f);

/* BOING_JIT_STATS=1: entries into compiled code per region, on stderr at exit */
static uint32_t *jit_stats;
static VMImage *jit_stats_img;
static void jit_stats_dump(void)
{
    VMImage *img = jit_stats_img;
    int32_t pc, i;
    unsigned long long tot = 0;
    for (pc = 0; pc < img->ncode; pc++) {
        const char *nm = "?";
        if (!jit_stats[pc]) continue;
        tot += jit_stats[pc];
        for (i = 0; i < img->nprocs; i++)
            if (img->procs[i].code >= 0 && img->procs[i].code <= pc) {
                int32_t best = img->procs[i].code, k;
                for (k = 0; k < img->nprocs; k++) if (img->procs[k].code > best && img->procs[k].code <= pc) best = img->procs[k].code;
                if (best == img->procs[i].code) { nm = img->procs[i].name; break; }
            }
        fprintf(stderr, "jit stats: %-16s @%-6ld entries %lu exits-mid %lu%s\n", nm, (long)pc, (unsigned long)jit_stats[pc],
                img->jitexit ? (unsigned long)img->jitexit[pc] : 0ul, img->jitcode && !img->jitcode[pc] ? " (off)" : "");
    }
    fprintf(stderr, "jit stats: %llu entries into compiled code\n", tot);
}

BB_INLINE bb_array *rarr(bb_value *L, bb_value *G, int32_t o)
{
    bb_value *v = o >= 0 ? &L[o] : o > BB_ME_OPND ? &G[-1 - o] : &((VMObj *)L[0].u.o)->f[BB_ME_OPND - o];
    return (v->type & BB_REF) ? *(bb_array **)v->u.p : v->u.a;
}

BB_INLINE char *rudt(VM *vm, bb_value *L, bb_value *G, int32_t o, const bb_udt_desc **d)
{
    bb_value *v = o >= 0 ? &L[o] : &G[-1 - o];
    if (v->type & BB_REF) { *d = &vm->img->udts[v->aux].desc; return (char *)v->u.p; }
    *d = ((bb_udtbox *)v->u.p)->desc;
    return (char *)bb_v_udt_data(v);
}

BB_INLINE void rload(bb_value *d, int vt, void *p)
{
    switch (vt) {
    case BB_LONG: d->type = BB_LONG; d->u.l = *(int32_t *)p; break;
    case BB_DOUBLE: d->type = BB_DOUBLE; d->u.d = *(double *)p; break;
    case BB_BOOLEAN: d->type = BB_BOOLEAN; d->u.b = *(bb_bool *)p; break;
    case BB_SINGLE: d->type = BB_SINGLE; d->u.f = *(bb_single *)p; break;
    default: d->type = BB_INTEGER; d->u.i = *(bb_int *)p; break;
    }
}

BB_INLINE void rstore(int vt, void *p, const bb_value *s)
{
    switch (vt) {
    case BB_LONG: *(int32_t *)p = s->u.l; break;
    case BB_DOUBLE: *(double *)p = s->u.d; break;
    case BB_SINGLE: *(bb_single *)p = s->u.f; break;
    default: *(bb_int *)p = s->u.i; break;
    }
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
    if (BB_SETJMP(ef.jb) != 0) {
        /* run-time error */
        Frame *f;
        int i, handled = 0;
        bb_errtop = &ef;   /* still ours */
        if (vm->nframes > entry) locate(vm, &vm->frames[vm->nframes - 1]);
        for (i = vm->nframes - 1; i >= entry && !handled; i--) {
            f = &vm->frames[i];
            if (f->handler_mode != OE_NONE && !f->in_handler) {
                int li;
                /* release what the failed statements left on the stack (vm->sp is kept
                 * exact: ops that take ownership of popped values sync it first) */
                while (vm->nframes - 1 > i) {
                    Frame *t = &vm->frames[vm->nframes - 1];
                    while (vm->sp > t->base + t->proc->nlocals) release_slot(--vm->sp);
                    pop_frame(vm);
                }
                while (vm->sp > f->base + f->proc->nlocals) release_slot(--vm->sp);
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
            while (vm->nframes > entry) {
                Frame *t = &vm->frames[vm->nframes - 1];
                while (vm->sp > t->base + t->proc->nlocals) release_slot(--vm->sp);
                pop_frame(vm);
            }
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
        int jit_on = jit_enabled() && img->jitno && img->jitcode && img->jitend;
        bb_jitctx jc;
        jc.L = L; jc.G = G; jc.K = img->consts; jc.poll = &bb_poll_count; jc.udts = img->udts; jc.scratch = 0; jc.zero = 0.0; { union { double d; uint64_t u; } m_; m_.u = 0x4330000080000000ULL; jc.magic = m_.d; } jc.fmax = 3.402823466e38;
#define SYNC() (vm->sp = sp)
#define RELOAD() (fr = &vm->frames[vm->nframes - 1], pc = fr->pc, sp = vm->sp, L = fr->base)
        for (;;) {
            int32_t op = *pc;
#ifdef BB_OPTIME
            {
                /* time per op (PPC timebase / host clock), charged to the previous op */
                uint32_t now_ = bb_optime_now();
                vm_optime[vm_optime_prev] += now_ - vm_optime_t;
                vm_optime_cnt[op]++;
                vm_optime_prev = op;
                vm_optime_t = now_;
            }
#endif
#ifdef BB_OPSTATS
            vm_opstats[op]++;
            if (vm_pcstats) vm_pcstats[pc - code]++;
            if (vm_pairs) { vm_pairs[vm_prevop * I__COUNT + op]++; vm_prevop = op; }
#endif
            if (op >= I_R_FIRST) {
                /* register forms: no stack, no tags to check; errors sync pc/sp first */
#if defined(__GNUC__) && !defined(BB_NO_THREADED)
#define RCASE(x) L_##x:
#define RNEXT() do { op = *pc; goto *rtab[op]; } while (0)
#define RSLOW(o_) do { op = (o_); goto rdone; } while (0)
                static void *const rtab[I__COUNT] = {
                    [0 ... I_R_FIRST - 1] = &&rdone,
        [I_R_MOV] = &&L_R_MOV,
        [I_R_MOVI_I] = &&L_R_MOVI_I,
        [I_R_MOVI_L] = &&L_R_MOVI_L,
        [I_R_MOVK] = &&L_R_MOVK,
        [I_R_ADD_LRR] = &&L_R_ADD_LRR,
        [I_R_ADD_LRI] = &&L_R_ADD_LRI,
        [I_R_SUB_LRR] = &&L_R_SUB_LRR,
        [I_R_SUB_LRI] = &&L_R_SUB_LRI,
        [I_R_SUB_LIR] = &&L_R_SUB_LIR,
        [I_R_MUL_LRR] = &&L_R_MUL_LRR,
        [I_R_MUL_LRI] = &&L_R_MUL_LRI,
        [I_R_IDIV_LRR] = &&L_R_IDIV_LRR,
        [I_R_IDIV_LRI] = &&L_R_IDIV_LRI,
        [I_R_MOD_LRR] = &&L_R_MOD_LRR,
        [I_R_MOD_LRI] = &&L_R_MOD_LRI,
        [I_R_AND_LRR] = &&L_R_AND_LRR,
        [I_R_AND_LRI] = &&L_R_AND_LRI,
        [I_R_OR_LRR] = &&L_R_OR_LRR,
        [I_R_OR_LRI] = &&L_R_OR_LRI,
        [I_R_XOR_LRR] = &&L_R_XOR_LRR,
        [I_R_XOR_LRI] = &&L_R_XOR_LRI,
        [I_R_NEG_L] = &&L_R_NEG_L,
        [I_R_ADD_IRR] = &&L_R_ADD_IRR,
        [I_R_ADD_IRI] = &&L_R_ADD_IRI,
        [I_R_SUB_IRR] = &&L_R_SUB_IRR,
        [I_R_SUB_IRI] = &&L_R_SUB_IRI,
        [I_R_SUB_IIR] = &&L_R_SUB_IIR,
        [I_R_MUL_IRR] = &&L_R_MUL_IRR,
        [I_R_MUL_IRI] = &&L_R_MUL_IRI,
        [I_R_IDIV_IRR] = &&L_R_IDIV_IRR,
        [I_R_IDIV_IRI] = &&L_R_IDIV_IRI,
        [I_R_MOD_IRR] = &&L_R_MOD_IRR,
        [I_R_MOD_IRI] = &&L_R_MOD_IRI,
        [I_R_AND_IRR] = &&L_R_AND_IRR,
        [I_R_AND_IRI] = &&L_R_AND_IRI,
        [I_R_OR_IRR] = &&L_R_OR_IRR,
        [I_R_OR_IRI] = &&L_R_OR_IRI,
        [I_R_XOR_IRR] = &&L_R_XOR_IRR,
        [I_R_XOR_IRI] = &&L_R_XOR_IRI,
        [I_R_NEG_I] = &&L_R_NEG_I,
        [I_R_ADD_DRR] = &&L_R_ADD_DRR,
        [I_R_ADD_DRK] = &&L_R_ADD_DRK,
        [I_R_SUB_DRR] = &&L_R_SUB_DRR,
        [I_R_SUB_DRK] = &&L_R_SUB_DRK,
        [I_R_SUB_DKR] = &&L_R_SUB_DKR,
        [I_R_MUL_DRR] = &&L_R_MUL_DRR,
        [I_R_MUL_DRK] = &&L_R_MUL_DRK,
        [I_R_DIV_DRR] = &&L_R_DIV_DRR,
        [I_R_DIV_DRK] = &&L_R_DIV_DRK,
        [I_R_DIV_DKR] = &&L_R_DIV_DKR,
        [I_R_NEG_D] = &&L_R_NEG_D,
        [I_R_CVT_LD] = &&L_R_CVT_LD,
        [I_R_CVT_ID] = &&L_R_CVT_ID,
        [I_R_CVT_IL] = &&L_R_CVT_IL,
        [I_R_JCMP_LRR] = &&L_R_JCMP_LRR,
        [I_R_JCMP_LRI] = &&L_R_JCMP_LRI,
        [I_R_JCMP_IRR] = &&L_R_JCMP_IRR,
        [I_R_JCMP_IRI] = &&L_R_JCMP_IRI,
        [I_R_JCMP_DRR] = &&L_R_JCMP_DRR,
        [I_R_JCMP_DRK] = &&L_R_JCMP_DRK,
        [I_R_LDE1] = &&L_R_LDE1,
        [I_R_STE1] = &&L_R_STE1,
        [I_R_LDE2] = &&L_R_LDE2,
        [I_R_STE2] = &&L_R_STE2,
        [I_R_LDEF1] = &&L_R_LDEF1,
        [I_R_STEF1] = &&L_R_STEF1,
        [I_R_LDF] = &&L_R_LDF,
        [I_R_STF] = &&L_R_STF,
        [I_R_JNZ] = &&L_R_JNZ,
        [I_R_JZ] = &&L_R_JZ,
        [I_R_FORCHK_I] = &&L_R_FORCHK_I,
        [I_R_FORINC_I] = &&L_R_FORINC_I,
        [I_R_FORCHK_L] = &&L_R_FORCHK_L,
        [I_R_FORINC_L] = &&L_R_FORINC_L,
        [I_R_FORCHK_D] = &&L_R_FORCHK_D,
        [I_R_FORINC_D] = &&L_R_FORINC_D,
        [I_R_LDREF] = &&L_R_LDREF,
        [I_R_STREF] = &&L_R_STREF,
        [I_R_JMP] = &&L_R_JMP,
        [I_R_SQRT_D] = &&L_R_SQRT_D,
        [I_R_CALLS] = &&L_R_CALLS,
        [I_R_RET] = &&L_R_RET,
        [I_R_LDMF] = &&L_R_LDMF,
        [I_R_STMF] = &&L_R_STMF,
        [I_R_LDG] = &&L_R_LDG,
        [I_R_JF1Z] = &&L_R_JF1Z,
        [I_R_FORSKIPF] = &&L_R_FORSKIPF,
        [I_R_SHL_LRR] = &&L_R_SHL_LRR,
        [I_R_SHRA_LRR] = &&L_R_SHRA_LRR,
        [I_R_SHRL_LRR] = &&L_R_SHRL_LRR,
        [I_R_JCMPF1_LI] = &&L_R_JCMPF1_LI,
        [I_R_STG] = &&L_R_STG,
        [I_R_ADD_FRR] = &&L_R_ADD_FRR,
        [I_R_SUB_FRR] = &&L_R_SUB_FRR,
        [I_R_MUL_FRR] = &&L_R_MUL_FRR,
        [I_R_DIV_FRR] = &&L_R_DIV_FRR,
        [I_R_NEG_F] = &&L_R_NEG_F,
        [I_R_CVT_IF] = &&L_R_CVT_IF,
        [I_R_CVT_LF] = &&L_R_CVT_LF,
        [I_R_CVT_DF] = &&L_R_CVT_DF,
        [I_R_CVT_FD] = &&L_R_CVT_FD,
        [I_R_JCMP_FRR] = &&L_R_JCMP_FRR
                };
                goto *rtab[op];
#else
#define RCASE(x) case I_##x:
#define RNEXT() continue
#define RSLOW(o_) { op = (o_); break; }
                switch (op) {
#endif
#define RSL(n) (L[pc[n]])
#define RERR(stmt) do { fr->pc = pc; vm->sp = sp; stmt; } while (0)
#define SETL(D_, V_) (L[D_].u.l = (V_))
#define SETI(D_, V_) (L[D_].u.i = (bb_int)(V_))
#define SETD(D_, V_) (L[D_].u.d = (V_))
#define LOVF(r, x, y, OP) if (BB_UNLIKELY(OP(x, y, &r))) RERR(bb_overflow())
#define IFIT(r) if (BB_UNLIKELY(r < -32768 || r > 32767)) RERR(bb_overflow())
#define DCHK(r) if (BB_UNLIKELY(r - r != 0)) RERR(bb_overflow())
                RCASE(R_MOV) L[pc[1]] = L[pc[2]]; pc += 3; RNEXT();
                RCASE(R_MOVI_I) SETI(pc[1], pc[2]); pc += 3; RNEXT();
                RCASE(R_MOVI_L) SETL(pc[1], pc[2]); pc += 3; RNEXT();
                RCASE(R_MOVK) L[pc[1]] = img->consts[pc[2]]; pc += 3; RNEXT();
#define LBIN(NAME, A, B, EXPR) RCASE(NAME) { int32_t x = (A), y = (B), r; EXPR; SETL(pc[1], r); pc += 4; RNEXT(); }
                LBIN(R_ADD_LRR, RSL(2).u.l, RSL(3).u.l, LOVF(r, x, y, __builtin_add_overflow))
                LBIN(R_ADD_LRI, RSL(2).u.l, pc[3], LOVF(r, x, y, __builtin_add_overflow))
                LBIN(R_SUB_LRR, RSL(2).u.l, RSL(3).u.l, LOVF(r, x, y, __builtin_sub_overflow))
                LBIN(R_SUB_LRI, RSL(2).u.l, pc[3], LOVF(r, x, y, __builtin_sub_overflow))
                LBIN(R_SUB_LIR, pc[2], RSL(3).u.l, LOVF(r, x, y, __builtin_sub_overflow))
                LBIN(R_MUL_LRR, RSL(2).u.l, RSL(3).u.l, LOVF(r, x, y, __builtin_mul_overflow))
                LBIN(R_MUL_LRI, RSL(2).u.l, pc[3], LOVF(r, x, y, __builtin_mul_overflow))
                LBIN(R_IDIV_LRR, RSL(2).u.l, RSL(3).u.l, if (BB_UNLIKELY(y == 0 || y == -1)) RERR(r = bb_idiv_l(x, y)); else r = x / y)
                LBIN(R_IDIV_LRI, RSL(2).u.l, pc[3], if (BB_UNLIKELY(y == 0 || y == -1)) RERR(r = bb_idiv_l(x, y)); else r = x / y)
                LBIN(R_MOD_LRR, RSL(2).u.l, RSL(3).u.l, if (BB_UNLIKELY(y == 0 || y == -1)) RERR(r = bb_mod_l(x, y)); else r = x % y)
                LBIN(R_MOD_LRI, RSL(2).u.l, pc[3], if (BB_UNLIKELY(y == 0 || y == -1)) RERR(r = bb_mod_l(x, y)); else r = x % y)
                LBIN(R_AND_LRR, RSL(2).u.l, RSL(3).u.l, r = x & y)
                LBIN(R_AND_LRI, RSL(2).u.l, pc[3], r = x & y)
                LBIN(R_OR_LRR, RSL(2).u.l, RSL(3).u.l, r = x | y)
                LBIN(R_OR_LRI, RSL(2).u.l, pc[3], r = x | y)
                LBIN(R_XOR_LRR, RSL(2).u.l, RSL(3).u.l, r = x ^ y)
                LBIN(R_XOR_LRI, RSL(2).u.l, pc[3], r = x ^ y)
                RCASE(R_NEG_L) { int32_t x = RSL(2).u.l; if (BB_UNLIKELY(x == INT32_MIN)) RERR(bb_overflow()); SETL(pc[1], -x); pc += 3; RNEXT(); }
#define IBIN(NAME, A, B, EXPR) RCASE(NAME) { int32_t x = (A), y = (B), r; EXPR; SETI(pc[1], r); pc += 4; RNEXT(); }
                IBIN(R_ADD_IRR, RSL(2).u.i, RSL(3).u.i, r = x + y; IFIT(r))
                IBIN(R_ADD_IRI, RSL(2).u.i, pc[3], r = x + y; IFIT(r))
                IBIN(R_SUB_IRR, RSL(2).u.i, RSL(3).u.i, r = x - y; IFIT(r))
                IBIN(R_SUB_IRI, RSL(2).u.i, pc[3], r = x - y; IFIT(r))
                IBIN(R_SUB_IIR, pc[2], RSL(3).u.i, r = x - y; IFIT(r))
                IBIN(R_MUL_IRR, RSL(2).u.i, RSL(3).u.i, r = x * y; IFIT(r))
                IBIN(R_MUL_IRI, RSL(2).u.i, pc[3], r = x * y; IFIT(r))
                IBIN(R_IDIV_IRR, RSL(2).u.i, RSL(3).u.i, if (BB_UNLIKELY(y == 0)) RERR(bb_raise(11, NULL)); r = x / y; IFIT(r))
                IBIN(R_IDIV_IRI, RSL(2).u.i, pc[3], if (BB_UNLIKELY(y == 0)) RERR(bb_raise(11, NULL)); r = x / y; IFIT(r))
                IBIN(R_MOD_IRR, RSL(2).u.i, RSL(3).u.i, if (BB_UNLIKELY(y == 0)) RERR(bb_raise(11, NULL)); r = x % y)
                IBIN(R_MOD_IRI, RSL(2).u.i, pc[3], if (BB_UNLIKELY(y == 0)) RERR(bb_raise(11, NULL)); r = x % y)
                IBIN(R_AND_IRR, RSL(2).u.i, RSL(3).u.i, r = x & y)
                IBIN(R_AND_IRI, RSL(2).u.i, pc[3], r = x & y)
                IBIN(R_OR_IRR, RSL(2).u.i, RSL(3).u.i, r = x | y)
                IBIN(R_OR_IRI, RSL(2).u.i, pc[3], r = x | y)
                IBIN(R_XOR_IRR, RSL(2).u.i, RSL(3).u.i, r = x ^ y)
                IBIN(R_XOR_IRI, RSL(2).u.i, pc[3], r = x ^ y)
                RCASE(R_NEG_I) { int32_t x = RSL(2).u.i; if (BB_UNLIKELY(x == -32768)) RERR(bb_overflow()); SETI(pc[1], -x); pc += 3; RNEXT(); }
#define DBIN(NAME, A, B, EXPR) RCASE(NAME) { double x = (A), y = (B), r; EXPR; SETD(pc[1], r); pc += 4; RNEXT(); }
                DBIN(R_ADD_DRR, RSL(2).u.d, RSL(3).u.d, r = x + y; DCHK(r))
                DBIN(R_ADD_DRK, RSL(2).u.d, img->consts[pc[3]].u.d, r = x + y; DCHK(r))
                DBIN(R_SUB_DRR, RSL(2).u.d, RSL(3).u.d, r = x - y; DCHK(r))
                DBIN(R_SUB_DRK, RSL(2).u.d, img->consts[pc[3]].u.d, r = x - y; DCHK(r))
                DBIN(R_SUB_DKR, img->consts[pc[2]].u.d, RSL(3).u.d, r = x - y; DCHK(r))
                DBIN(R_MUL_DRR, RSL(2).u.d, RSL(3).u.d, r = x * y; DCHK(r))
                DBIN(R_MUL_DRK, RSL(2).u.d, img->consts[pc[3]].u.d, r = x * y; DCHK(r))
                DBIN(R_DIV_DRR, RSL(2).u.d, RSL(3).u.d, if (BB_UNLIKELY(y == 0)) RERR(r = bb_fdiv(x, y)); else { r = x / y; DCHK(r); })
                DBIN(R_DIV_DRK, RSL(2).u.d, img->consts[pc[3]].u.d, if (BB_UNLIKELY(y == 0)) RERR(r = bb_fdiv(x, y)); else { r = x / y; DCHK(r); })
                DBIN(R_DIV_DKR, img->consts[pc[2]].u.d, RSL(3).u.d, if (BB_UNLIKELY(y == 0)) RERR(r = bb_fdiv(x, y)); else { r = x / y; DCHK(r); })
                RCASE(R_NEG_D) SETD(pc[1], -RSL(2).u.d); pc += 3; RNEXT();
                RCASE(R_CVT_LD) SETD(pc[1], (double)RSL(2).u.l); pc += 3; RNEXT();
                RCASE(R_CVT_ID) SETD(pc[1], (double)RSL(2).u.i); pc += 3; RNEXT();
                RCASE(R_CVT_IL) SETL(pc[1], (int32_t)RSL(2).u.i); pc += 3; RNEXT();
#define JCMP(NAME, T, A, B) RCASE(NAME) { T x = (A), y = (B); int c_; \
                    switch (pc[1]) { case BB_CMP_EQ: c_ = x == y; break; case BB_CMP_NE: c_ = x != y; break; \
                    case BB_CMP_LT: c_ = x < y; break; case BB_CMP_GT: c_ = x > y; break; \
                    case BB_CMP_LE: c_ = x <= y; break; default: c_ = x >= y; } \
                    if (c_) { int32_t t_ = pc[4]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } else pc += 5; RNEXT(); }
                JCMP(R_JCMP_LRR, int32_t, RSL(2).u.l, RSL(3).u.l)
                JCMP(R_JCMP_LRI, int32_t, RSL(2).u.l, pc[3])
                JCMP(R_JCMP_IRR, int32_t, RSL(2).u.i, RSL(3).u.i)
                JCMP(R_JCMP_IRI, int32_t, RSL(2).u.i, pc[3])
                JCMP(R_JCMP_DRR, double, RSL(2).u.d, RSL(3).u.d)
                JCMP(R_JCMP_DRK, double, RSL(2).u.d, img->consts[pc[3]].u.d)
#define RARR(o) rarr(L, G, (o))
                RCASE(R_LDE1) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[3]); rload(&L[pc[2]], pc[1], bb_arr_elem1(A, RSL(4).u.l)); pc += 5; RNEXT(); }
                RCASE(R_STE1) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[2]); rstore(pc[1], bb_arr_elem1(A, RSL(3).u.l), &RSL(4)); pc += 5; RNEXT(); }
                RCASE(R_LDE2) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[3]); rload(&L[pc[2]], pc[1], bb_arr_elem2(A, RSL(4).u.l, RSL(5).u.l)); pc += 6; RNEXT(); }
                RCASE(R_STE2) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[2]); rstore(pc[1], bb_arr_elem2(A, RSL(3).u.l, RSL(4).u.l), &RSL(5)); pc += 6; RNEXT(); }
                RCASE(R_LDEF1) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[3]); char *ep = (char *)bb_arr_elem1(A, RSL(4).u.l);
                    rload(&L[pc[2]], pc[1], ep + A->udt->fields[pc[5]].offset); pc += 6; RNEXT(); }
                RCASE(R_STEF1) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[2]); char *ep = (char *)bb_arr_elem1(A, RSL(3).u.l);
                    rstore(pc[1], ep + A->udt->fields[pc[4]].offset, &RSL(5)); pc += 6; RNEXT(); }
                RCASE(R_LDF) { const bb_udt_desc *dd; char *p0 = rudt(vm, L, G, pc[3], &dd);
                    rload(&L[pc[2]], pc[1], p0 + dd->fields[pc[4]].offset); pc += 5; RNEXT(); }
                RCASE(R_STF) { const bb_udt_desc *dd; char *p0 = rudt(vm, L, G, pc[2], &dd);
                    rstore(pc[1], p0 + dd->fields[pc[3]].offset, &RSL(4)); pc += 5; RNEXT(); }
                RCASE(R_JNZ) if (RSL(1).u.i) { int32_t t_ = pc[2]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } else pc += 3; RNEXT();
                RCASE(R_JZ) if (!RSL(1).u.i) { int32_t t_ = pc[2]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } else pc += 3; RNEXT();
                RCASE(R_FORCHK_I) { bb_int c = L[pc[1]].u.i, l = L[pc[2]].u.i, st = L[pc[3]].u.i; if ((st >= 0) ? c > l : c < l) pc = code + pc[4]; else { pc += 5; JITENTER() } RNEXT(); }
                RCASE(R_FORCHK_L) { bb_long c = L[pc[1]].u.l, l = L[pc[2]].u.l, st = L[pc[3]].u.l; if ((st >= 0) ? c > l : c < l) pc = code + pc[4]; else { pc += 5; JITENTER() } RNEXT(); }
                RCASE(R_FORCHK_D) { double c = L[pc[1]].u.d, l = L[pc[2]].u.d, st = L[pc[3]].u.d; if ((st >= 0) ? c > l : c < l) pc = code + pc[4]; else { pc += 5; JITENTER() } RNEXT(); }
                RCASE(R_FORINC_I) { bb_value *cv = &L[pc[1]]; int32_t l = L[pc[2]].u.i, st = L[pc[3]].u.i, r = cv->u.i + st;
                    if (BB_UNLIKELY(r < -32768 || r > 32767)) RERR(bb_overflow());
                    cv->u.i = (bb_int)r;
                    if ((st >= 0) ? r > l : r < l) pc += 5; else BACKJUMP(pc[4]) RNEXT(); }
                RCASE(R_FORINC_L) { bb_value *cv = &L[pc[1]]; int32_t l = L[pc[2]].u.l, st = L[pc[3]].u.l, r;
                    if (BB_UNLIKELY(__builtin_add_overflow(cv->u.l, st, &r))) RERR(bb_overflow());
                    cv->u.l = r;
                    if ((st >= 0) ? r > l : r < l) pc += 5; else BACKJUMP(pc[4]) RNEXT(); }
                RCASE(R_FORINC_D) { bb_value *cv = &L[pc[1]]; double l = L[pc[2]].u.d, st = L[pc[3]].u.d;
                    cv->u.d += st;
                    if ((st >= 0) ? cv->u.d > l : cv->u.d < l) pc += 5; else BACKJUMP(pc[4]) RNEXT(); }
                RCASE(R_JMP) { int32_t t_ = pc[1]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } RNEXT();
                RCASE(R_SQRT_D) { double x = RSL(2).u.d; if (BB_UNLIKELY(x < 0)) RERR(bb_raise(5, NULL)); SETD(pc[1], sqrt(x)); pc += 3;
                    /* a JIT without a square root instruction stops at Sqr: continue in the compiled rest */
                    if (BB_UNLIKELY(jit_on) && !img->jitno[pc - code]) { int32_t rp_ = (int32_t)(pc - code); bb_jitfn j0_ = img->jitcode[rp_];
                        if (!j0_) j0_ = jit_hot(img, fr->proc, rp_);
                        JITCHAIN(rp_, j0_) }
                    RNEXT(); }
                RCASE(R_CALLS) {
                    /* call with ByVal scalar arguments from slots; result into slot pc[2] */
                    int32_t pidx = pc[1], n = pc[3], i;
                    VMProc *p = &img->procs[pidx];
                    bb_value *base = sp;
                    POLL();
                    for (i = 0; i < n; i++) {
                        int32_t o_ = pc[4 + i];
                        if (o_ >= 0) base[i] = L[o_];
                        else { bb_value *v_ = &L[-1 - o_]; base[i] = bb_v_ref(v_->type, &v_->u); }
                    }
                    fr->pc = pc;
                    vm->sp = sp + n;
                    {
                        Frame *nf;
                        if (BB_LIKELY(p->rt_tmpl != NULL)) nf = push_plain(vm, p, pidx, base);
                        else { prep_hidden(vm, p, base); nf = push_frame(vm, pidx, base); }
                        nf->ret = pc + 12;
                        nf->retdst = pc[2];
                        fr = nf;
                    }
                    pc = fr->pc;
                    sp = vm->sp;
                    L = fr->base;
                    RNEXT();
                }
                RCASE(R_RET) {
                    /* scalar-only frame returning to bytecode: nothing to release */
                    VMProc *p = fr->proc;
                    if (BB_LIKELY(p->rt_scalar && vm->nframes - 1 > entry && fr->keep.type == BB_EMPTY && !fr->in_handler)) {
                        bb_value *base = fr->base;
                        if (p->cls >= 0) {
                            /* Me (slot 0): the only reference to drop; the result is copied first */
                            bb_value me_ = base[0];
                            if (p->ret_slot >= 0) { bb_value rv_ = base[p->ret_slot]; base[0].type = BB_EMPTY; base[p->ret_slot] = rv_; }
                            if (me_.type == BB_OBJECT && me_.u.o) {
                                fr->pc = pc; vm->sp = sp;
                                bb_obj_release(me_.u.o);
                            }
                        }
                        int32_t rd = fr->retdst, *ret = fr->ret;
                        vm->ngosub = fr->gs_base;
                        vm->nframes--;
                        fr = &vm->frames[vm->nframes - 1];
                        sp = base;
                        if (p->ret_slot >= 0) {
                            bb_value rv = base[p->ret_slot];
                            if (rd >= 0) fr->base[rd] = rv;
                            else *sp++ = rv;
                        }
                        L = fr->base;
                        pc = ret;
                        /* back in a loop body that was cut by this call: its compiled rest */
                        if (BB_UNLIKELY(jit_on) && !img->jitno[ret - code]) { int32_t rp_ = (int32_t)(ret - code); bb_jitfn j0_ = img->jitcode[rp_];
                            if (!j0_) j0_ = jit_hot(img, fr->proc, rp_);
                            JITCHAIN(rp_, j0_) }
                        RNEXT();
                    }
                    RSLOW(I_RET);
                }
#define SETF(D_, V_) (L[D_].u.f = (V_))
                RCASE(R_ADD_FRR) { double r_ = (double)RSL(2).u.f + RSL(3).u.f; if (BB_UNLIKELY(r_ > 3.402823466e38 || r_ < -3.402823466e38)) RERR(bb_overflow()); SETF(pc[1], (bb_single)r_); pc += 4; RNEXT(); }
                RCASE(R_SUB_FRR) { double r_ = (double)RSL(2).u.f - RSL(3).u.f; if (BB_UNLIKELY(r_ > 3.402823466e38 || r_ < -3.402823466e38)) RERR(bb_overflow()); SETF(pc[1], (bb_single)r_); pc += 4; RNEXT(); }
                RCASE(R_MUL_FRR) { double r_ = (double)RSL(2).u.f * RSL(3).u.f; if (BB_UNLIKELY(r_ > 3.402823466e38 || r_ < -3.402823466e38)) RERR(bb_overflow()); SETF(pc[1], (bb_single)r_); pc += 4; RNEXT(); }
                RCASE(R_DIV_FRR) { double y_ = RSL(3).u.f, r_;
                    if (BB_UNLIKELY(y_ == 0)) RERR(bb_fdiv(RSL(2).u.f, y_));
                    r_ = (double)RSL(2).u.f / y_;
                    if (BB_UNLIKELY(r_ - r_ != 0 || r_ > 3.402823466e38 || r_ < -3.402823466e38)) RERR(bb_overflow());
                    SETF(pc[1], (bb_single)r_); pc += 4; RNEXT(); }
                RCASE(R_NEG_F) SETF(pc[1], -RSL(2).u.f); pc += 3; RNEXT();
                RCASE(R_CVT_IF) SETF(pc[1], (bb_single)RSL(2).u.i); pc += 3; RNEXT();
                RCASE(R_CVT_LF) SETF(pc[1], (bb_single)RSL(2).u.l); pc += 3; RNEXT();
                RCASE(R_CVT_DF) { double x_ = RSL(2).u.d; if (BB_UNLIKELY(x_ > 3.402823466e38 || x_ < -3.402823466e38)) RERR(bb_overflow()); SETF(pc[1], (bb_single)x_); pc += 3; RNEXT(); }
                RCASE(R_CVT_FD) SETD(pc[1], (double)RSL(2).u.f); pc += 3; RNEXT();
                JCMP(R_JCMP_FRR, double, RSL(2).u.f, RSL(3).u.f)
                RCASE(R_LDMF) L[pc[2]] = ((VMObj *)L[0].u.o)->f[pc[3]]; pc += 4; RNEXT();
                RCASE(R_STMF) ((VMObj *)L[0].u.o)->f[pc[2]].u = L[pc[3]].u; pc += 4; RNEXT();
                RCASE(R_LDG) L[pc[2]] = G[pc[3]]; pc += 4; RNEXT();
                /* superinstructions: test a field of arr(i) and branch (For i: If arr(i).active ...) */
                RCASE(R_JF1Z) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[2]); char *ep = (char *)bb_arr_elem1(A, RSL(3).u.l);
                    if ((*(bb_int *)(ep + A->udt->fields[pc[4]].offset) != 0) == (pc[1] != 0)) {
                        int32_t t_ = pc[5]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } else pc += 6; RNEXT(); }
                RCASE(R_SHL_LRR) { int32_t n_ = RSL(3).u.l; if (BB_UNLIKELY((uint32_t)n_ > 31)) RERR(bb_shift_range_error()); SETL(pc[1], bb_shl(RSL(2).u.l, n_)); pc += 4; RNEXT(); }
                RCASE(R_SHRA_LRR) { int32_t n_ = RSL(3).u.l; if (BB_UNLIKELY((uint32_t)n_ > 31)) RERR(bb_shift_range_error()); SETL(pc[1], bb_shra(RSL(2).u.l, n_)); pc += 4; RNEXT(); }
                RCASE(R_SHRL_LRR) { int32_t n_ = RSL(3).u.l; if (BB_UNLIKELY((uint32_t)n_ > 31)) RERR(bb_shift_range_error()); SETL(pc[1], bb_shrl(RSL(2).u.l, n_)); pc += 4; RNEXT(); }
                RCASE(R_FORSKIPF) {
                    /* Next of `For i ...: If arr(i).flag Then ...: Next`: step past the entries whose
                       flag is 0 without dispatching (pc[4] body start = that If, pc[5] its body,
                       pc[6] array, pc[7] field). With the JIT on it is a plain FORINC_L. */
                    bb_value *cv = &L[pc[1]]; int32_t l = L[pc[2]].u.l, st = L[pc[3]].u.l, r;
                    if (BB_UNLIKELY(jit_on)) {
                        if (BB_UNLIKELY(__builtin_add_overflow(cv->u.l, st, &r))) RERR(bb_overflow());
                        cv->u.l = r;
                        if ((st >= 0) ? r > l : r < l) pc += 8; else BACKJUMP(pc[4])
                        RNEXT();
                    }
                    for (;;) {
                        bb_array *A;
                        int32_t k;
                        if (BB_UNLIKELY(__builtin_add_overflow(cv->u.l, st, &r))) RERR(bb_overflow());
                        cv->u.l = r;
                        if ((st >= 0) ? r > l : r < l) { pc += 8; break; }
                        POLL();
                        A = RARR(pc[6]);
                        k = r - (A ? A->dims[0].lbound : 0);
                        if (!A || A->ndims != 1 || k < 0 || k >= A->dims[0].count) { pc = code + pc[4]; break; }  /* the If raises it */
                        if (*(bb_int *)((char *)A->data + (size_t)k * A->esize + A->udt->fields[pc[7]].offset) != 0) { pc = code + pc[5]; break; }
                    }
                    RNEXT();
                }
                RCASE(R_JCMPF1_LI) { fr->pc = pc; vm->sp = sp; bb_array *A = RARR(pc[2]); char *ep = (char *)bb_arr_elem1(A, RSL(3).u.l);
                    int32_t x = *(int32_t *)(ep + A->udt->fields[pc[4]].offset), y = pc[5]; int c_;
                    switch (pc[1]) { case BB_CMP_EQ: c_ = x == y; break; case BB_CMP_NE: c_ = x != y; break;
                    case BB_CMP_LT: c_ = x < y; break; case BB_CMP_GT: c_ = x > y; break;
                    case BB_CMP_LE: c_ = x <= y; break; default: c_ = x >= y; }
                    if (c_) { int32_t t_ = pc[6]; if (t_ <= pc - code) BACKJUMP(t_) else pc = code + t_; } else pc += 7; RNEXT(); }
                RCASE(R_STG) G[pc[2]].u = L[pc[3]].u; pc += 4; RNEXT();
                RCASE(R_LDREF) rload(&L[pc[2]], pc[1], L[pc[3]].u.p); pc += 4; RNEXT();
                RCASE(R_STREF) rstore(pc[1], L[pc[2]].u.p, &L[pc[3]]); pc += 4; RNEXT();
#if !(defined(__GNUC__) && !defined(BB_NO_THREADED))
                default: break;
                }
#endif
            }
#if defined(__GNUC__) && !defined(BB_NO_THREADED)
            if (0) {
            rdone:
                ;
            }
#endif
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
            case I_STL: { L[pc[1]] = POP(); pc += 2; break; }
            case I_STLS: { bb_value v = POP(); SYNC(); bb_value *d = &L[pc[1]]; bb_str_set(&d->u.s, v.type == BB_STRING ? v.u.s : NULL); d->type = BB_STRING; pc += 2; break; }
            case I_STLV: { bb_value v = POP(); SYNC(); bb_v_set(&L[pc[1]], v); pc += 2; break; }
            case I_LDG: PUSH(G[pc[1]]); pc += 2; break;
            case I_LDGS: { bb_value v = G[pc[1]]; bb_str_retain(v.u.s); PUSH(v); pc += 2; break; }
            case I_LDGV: { bb_value v; bb_v_copy(&v, &G[pc[1]]); PUSH(v); pc += 2; break; }
            case I_STG: { G[pc[1]] = POP(); pc += 2; break; }
            case I_STGS: { bb_value v = POP(); SYNC(); bb_str_set(&G[pc[1]].u.s, v.type == BB_STRING ? v.u.s : NULL); G[pc[1]].type = BB_STRING; pc += 2; break; }
            case I_STGV: { bb_value v = POP(); SYNC(); bb_v_set(&G[pc[1]], v); pc += 2; break; }
            case I_AUTONEW: {
                /* As New: create the object on first use (or after Set x = Nothing) */
                bb_value *v = pc[1] == 0 ? &L[pc[2] >> 16] : pc[1] == 1 ? &G[pc[2] >> 16] : &((VMObj *)L[0].u.o)->f[pc[2] >> 16];
                int32_t nc = pc[3];
                if (v->type != BB_OBJECT || !v->u.o) {
                    bb_obj *o;
                    SYNC();
                    o = nc < 0 ? bb_collection_new() : new_object(vm, nc - 1);
                    if (v->type == BB_OBJECT && v->u.o) bb_obj_release(o);     /* created meanwhile */
                    else { v->type = BB_OBJECT; v->u.o = o; }
                }
                pc += 4;
                break;
            }
            case I_STRBUF: {
                /* TOP: reference to a String variable -> pointer to its own bytes (Declare ByVal) */
                bb_value *t = &TOP;
                bb_str **ps = (bb_str **)t->u.p;
                t->type = BB_REF | BB_BYTE;
                t->u.p = bb_decl_strbuf(ps);
                pc++;
                break;
            }
            case I_ADDROF:
                SYNC();
                PUSH(bb_v_long(bb_addressof(bb_str_ptr(img->consts[pc[1]].u.s), bb_str_ptr(img->consts[pc[2]].u.s), pc[3])));
                pc += 4;
                break;
            case I_AUTONEWM: {
                /* As New field of the object on top of the stack */
                bb_value *t = &TOP;
                if (t->type == BB_OBJECT && t->u.o) {
                    bb_value *v = &((VMObj *)t->u.o)->f[pc[1]];
                    if (v->type != BB_OBJECT || !v->u.o) {
                        bb_obj *o;
                        SYNC();
                        o = pc[2] < 0 ? bb_collection_new() : new_object(vm, pc[2] - 1);
                        v = &((VMObj *)TOP.u.o)->f[pc[1]];
                        if (v->type == BB_OBJECT && v->u.o) bb_obj_release(o);
                        else { v->type = BB_OBJECT; v->u.o = o; }
                    }
                }
                pc += 3;
                break;
            }
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
                SYNC();
                if (op == I_STF) o->f[pc[1]] = v;
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
                SYNC();
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
                SYNC();
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
                SYNC();
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
                SYNC();
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
                SYNC();
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
                if ((x->type != BB_OBJECT && x->type != BB_EMPTY) || (y->type != BB_OBJECT && y->type != BB_EMPTY))
                    bb_raise(424, NULL);     /* a and b are still on the stack: released there */
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

            case I_JMP: if (pc[1] <= pc - code) BACKJUMP(pc[1]) else pc = code + pc[1]; break;
            case I_JF: { bb_value v = POP(); int t = truth(&v); release_slot(&v); pc = t ? pc + 2 : code + pc[1]; break; }
            case I_JT: { bb_value v; if (pc[1] <= pc - code) POLL(); v = POP(); int t = truth(&v); release_slot(&v); pc = t ? code + pc[1] : pc + 2; break; }

            case I_FORCHK_I: { bb_int c = L[pc[1]].u.i, l = L[pc[2]].u.i, s = L[pc[3]].u.i; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_I: { POLL(); bb_value *cv = &L[pc[1]]; bb_int l = L[pc[2]].u.i, s = L[pc[3]].u.i; cv->u.i = bb_add_i(cv->u.i, s); pc = ((s >= 0) ? cv->u.i > l : cv->u.i < l) ? pc + 5 : code + pc[4]; break; }
            case I_FORCHK_L: { bb_long c = L[pc[1]].u.l, l = L[pc[2]].u.l, s = L[pc[3]].u.l; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_L: { POLL(); bb_value *cv = &L[pc[1]]; bb_long l = L[pc[2]].u.l, s = L[pc[3]].u.l; cv->u.l = bb_add_l(cv->u.l, s); pc = ((s >= 0) ? cv->u.l > l : cv->u.l < l) ? pc + 5 : code + pc[4]; break; }
            case I_FORCHK_D: { double c = L[pc[1]].u.d, l = L[pc[2]].u.d, s = L[pc[3]].u.d; pc = ((s >= 0) ? c > l : c < l) ? code + pc[4] : pc + 5; break; }
            case I_FORINC_D: { POLL(); bb_value *cv = &L[pc[1]]; double l = L[pc[2]].u.d, s = L[pc[3]].u.d; cv->u.d = cv->u.d + s; pc = ((s >= 0) ? cv->u.d > l : cv->u.d < l) ? pc + 5 : code + pc[4]; break; }
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
                POLL();
                VMProc *p = &img->procs[pidx];
                bb_value *base = sp - p->nparams;
                int32_t *ret = pc + 2;
                SYNC();
                if (BB_LIKELY(p->rt_plain)) fr = push_plain(vm, p, pidx, base);
                else { prep_hidden(vm, p, base); fr = push_frame(vm, pidx, base); }
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
                SYNC();
                {
                    int32_t *ret = pc + 4;
                    if (BB_LIKELY(p->rt_plain)) fr = push_plain(vm, p, pidx, base);
                    else { prep_hidden(vm, p, base); fr = push_frame(vm, pidx, base); }
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
                if (!img->sites) img->sites = (bb_site *)bb_alloc(sizeof(bb_site) * (size_t)(img->nconsts + 1));
                r = bb_v_invoke_site(recv, &img->sites[pc[1]], bb_str_ptr(name), pc[2], argc, args);
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
                int32_t rd = fr->retdst;
                SYNC();
                pop_frame(vm);
                sp = base;
                if (has) {
                    if (rd >= 0) vm->frames[vm->nframes - 1].base[rd] = rv;
                    else PUSH(rv);
                }
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
                SYNC();
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
            case I_LDE1: {
                /* ELEM 1 + LDIND: a(i) of an array variable */
                bb_value ix = POP(), r = POP();
                bb_array *a;
                int32_t i = ix.type == BB_LONG ? ix.u.l : bb_v_to_long(&ix);
                void *ep;
                if (r.type & BB_ARRAY) a = (r.type & BB_REF) ? *(bb_array **)r.u.p : r.u.a;
                else a = bb_v_array((bb_value *)r.u.p);
                ep = bb_arr_elem1(a, i);
                PUSH(load_raw(vm, ep, pc[1], udt_index_of(vm, a->udt)));
                if (!(r.type & BB_REF)) bb_v_release(&r);
                pc += 2;
                break;
            }
            case I_UNKEEP: bb_v_set(&fr->keep, bb_v_empty()); pc++; break;
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
    for (i = 0; i < img->nprocs; i++) {
        VMProc *p = &img->procs[i];
        int32_t k, plain = 1;
        if (p->code < 0) continue;
        p->rt_nbyref = 0;
        for (k = 0; k < p->nparams; k++) if (p->param_byref[k]) p->rt_nbyref++;
        for (k = p->nparams; k < p->hidden; k++) {
            VMSlot *sl = &p->slots[k];
            int vt = sl->vt;
            if (sl->isref || sl->ndims || sl->newcls || sl->fixlen || vt == BB_UDT || (vt & BB_ARRAY)) plain = 0;
        }
        /* plain: simple locals; rt_tmpl also serves R_CALLS, which passes every ByRef
           argument as a reference, so ByRef parameters need no set-up there */
        p->rt_plain = plain && !p->rt_nbyref;
        p->rt_scalar = 0;
        p->rt_tmpl = NULL;
        if (plain) {
            int scalar = 1;
            p->rt_tmpl = (bb_value *)xcalloc((size_t)(p->nlocals - p->nparams) + 1, sizeof(bb_value));
            for (k = p->nparams; k < p->nlocals; k++) {
                int vt = p->slots[k].vt;
                if (k < p->hidden) p->rt_tmpl[k - p->nparams].type = (uint16_t)(vt == BB_VARIANT ? BB_EMPTY : vt);
                else p->rt_tmpl[k - p->nparams].type = (uint16_t)(vt == BB_INTEGER || vt == BB_LONG || vt == BB_DOUBLE || vt == BB_SINGLE ? vt : BB_EMPTY);
            }
            for (k = 0; k < p->nlocals; k++) {
                int vt = p->slots[k].vt;
                int byrefp = k < p->nparams && p->param_byref[k];
                if ((p->slots[k].isref && !byrefp) || !(vt == BB_INTEGER || vt == BB_LONG || vt == BB_SINGLE || vt == BB_DOUBLE ||
                      vt == BB_BOOLEAN || vt == BB_BYTE || vt == BB_CURRENCY || vt == BB_DATE)) scalar = 0;
            }
            if (p->cls >= 0 && p->slots[0].vt == BB_OBJECT) {
                /* Me is released by R_RET itself */
                scalar = 1;
                for (k = 1; k < p->nlocals; k++) {
                    int vt = p->slots[k].vt;
                    int byrefp = k < p->nparams && p->param_byref[k];
                    if ((p->slots[k].isref && !byrefp) || !(vt == BB_INTEGER || vt == BB_LONG || vt == BB_SINGLE || vt == BB_DOUBLE ||
                          vt == BB_BOOLEAN || vt == BB_BYTE || vt == BB_CURRENCY || vt == BB_DATE)) scalar = 0;
                }
            } else if (p->cls >= 0) scalar = 0;
            p->rt_scalar = scalar;
        }
    }
}

int vm_run(VMImage *img, int argc, char **argv)
{
    VM vm;
    int32_t i;
    memset(&vm, 0, sizeof vm);
    vm.img = img;
    g_vm = &vm;
#ifdef BB_OPTIME
    atexit(vm_optime_dump);
#endif
#ifdef BB_OPSTATS
    atexit(vm_opstats_dump);
    vm_pcstats = (unsigned long long *)xcalloc((size_t)img->ncode + 1, sizeof(unsigned long long));
    vm_stats_img = img;
    vm_pairs = (unsigned long long *)xcalloc((size_t)I__COUNT * I__COUNT, sizeof(unsigned long long));
#endif
    bb_rt_init(argc, argv);
    jit_init();
    if (!img->jitno) img->jitno = (unsigned char *)xcalloc((size_t)img->ncode + 1, 1);
    if (!img->jitcode) img->jitcode = (bb_jitfn *)xcalloc((size_t)img->ncode + 1, sizeof(bb_jitfn));
    if (!img->jitend) {
        img->jitend = (int32_t *)xcalloc((size_t)img->ncode + 1, sizeof(int32_t));
        img->jitent = (uint32_t *)xcalloc((size_t)img->ncode + 1, sizeof(uint32_t));
        img->jitexit = (uint32_t *)xcalloc((size_t)img->ncode + 1, sizeof(uint32_t));
    }
    if (getenv("BOING_JIT_STATS") && !jit_stats) {
        jit_stats = (uint32_t *)xcalloc((size_t)img->ncode + 1, sizeof(uint32_t));
        jit_stats_img = img;
        atexit(jit_stats_dump);
    }
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
        if (BB_SETJMP(f.jb) == 0) {
            for (i = 0; i < img->nglobals; i++) init_slot(&vm, &vm.globals[i], &img->globals[i]);
            for (i = 0; i < img->nforms; i++)
                bb_forms_register(img->modules[img->form_mod[i]], img->form_name[i], img->form_afg[i], img->form_path[i]);
            if (img->startup_form >= 0) bb_forms_main(img->modules[img->form_mod[img->startup_form]]);
            else if (img->startup >= 0) {
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
