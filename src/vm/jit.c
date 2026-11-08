/* jit.c - region selection, translation of register ops, code memory, cache (docs/jit.md) */
#include "jit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

#if defined(__aarch64__) && defined(__APPLE__)
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#define JIT_HOST_BACKEND (&jit_arm64)
#elif defined(__aarch64__) && defined(__linux__)
#include <sys/mman.h>
#define JIT_HOST_BACKEND (&jit_arm64)
#elif defined(__amigaos4__)
#include <proto/exec.h>
#define JIT_HOST_BACKEND (&jit_ppc32)
#else
#define JIT_HOST_BACKEND NULL
#endif

int jit_threshold = 2;
static int g_enabled = 0;

int jit_enabled(void) { return g_enabled && JIT_HOST_BACKEND != NULL; }
void jit_set_enabled(int on) { g_enabled = on; }

/* ---------- the assembler buffer ---------- */

int ja_label(JA *a)
{
    if (a->nlab >= JMAXLAB) { a->err = 1; return 0; }
    a->lab[a->nlab] = -1;
    return a->nlab++;
}

static void ja_grow(JA *a, int n)
{
    if (a->n + n > a->cap) {
        a->cap = (a->n + n) * 2 + 256;
        a->buf = (unsigned char *)realloc(a->buf, (size_t)a->cap);
        if (!a->buf) { a->err = 1; a->n = 0; a->cap = 0; }
    }
}

void ja_emit32(JA *a, uint32_t w)
{
    ja_grow(a, 4);
    if (a->err) return;
    memcpy(a->buf + a->n, &w, 4);
    a->n += 4;
}

void ja_emit32be(JA *a, uint32_t w)
{
    ja_grow(a, 4);
    if (a->err) return;
    a->buf[a->n] = (unsigned char)(w >> 24);
    a->buf[a->n + 1] = (unsigned char)(w >> 16);
    a->buf[a->n + 2] = (unsigned char)(w >> 8);
    a->buf[a->n + 3] = (unsigned char)w;
    a->n += 4;
}

void ja_fixup(JA *a, int at, int label, int kind)
{
    if (a->nfix >= (int)(sizeof a->fix / sizeof a->fix[0])) { a->err = 1; return; }
    a->fix[a->nfix].at = at;
    a->fix[a->nfix].label = label;
    a->fix[a->nfix].kind = kind;
    a->nfix++;
}

/* ---------- translation ---------- */

#define SLOT_U(s) ((int32_t)(s) * 16 + 8)
#define SLOT_T(s) ((int32_t)(s) * 16)

typedef struct T {
    JA *a;
    const JBackend *be;
    VMImage *img;
    int32_t start, end;
    int *oplab;                 /* label per bytecode offset in the region */
    int32_t *exitpc;            /* exits: label -> pc */
    int *exitlab;
    int nexit;
} T;

static int exit_to(T *t, int32_t pc)
{
    int i;
    for (i = 0; i < t->nexit; i++) if (t->exitpc[i] == pc) return t->exitlab[i];
    t->exitpc = (int32_t *)realloc(t->exitpc, sizeof(int32_t) * (size_t)(t->nexit + 1));
    t->exitlab = (int *)realloc(t->exitlab, sizeof(int) * (size_t)(t->nexit + 1));
    t->exitpc[t->nexit] = pc;
    t->exitlab[t->nexit] = ja_label(t->a);
    return t->exitlab[t->nexit++];
}

/* branch to bytecode target (inside the region or out of it); backward branches poll */
static void branch_to(T *t, int32_t from, int32_t target)
{
    const JBackend *be = t->be;
    if (target <= from) be->poll(t->a, exit_to(t, target));
    if (target >= t->start && target < t->end && t->oplab[target - t->start] >= 0) be->b(t->a, t->oplab[target - t->start]);
    else be->b(t->a, exit_to(t, target));
}

extern const int bb_vmobj_f_offset;

/* base register and offset of an operand's bb_value; a field of Me loads Me into JP2 */
static void base_of_t(T *t, int32_t opnd, int *base, int32_t *off)
{
    if (opnd >= 0) { *base = JB_L; *off = opnd * 16; }
    else if (opnd > BB_ME_OPND) { *base = JB_G; *off = (-1 - opnd) * 16; }
    else {
        t->be->ldp(t->a, JP2, JB_L, 8);             /* slot 0 holds Me */
        *base = JP2;
        *off = bb_vmobj_f_offset + (BB_ME_OPND - opnd) * 16;
    }
}
#define base_of(o, b, f) base_of_t(t, (o), (b), (f))

/* JP0 = the bb_array of an array operand (exit if not allocated) */
static void load_array(T *t, int32_t opnd, int ex)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    int base, plain = ja_label(a);
    int32_t off;
    base_of(opnd, &base, &off);
    be->ldp(a, JP0, base, off + 8);
    be->ld16u(a, JI4, base, off);
    be->cmpiu(a, JI4, BB_REF);
    be->bcond(a, JC_LTU, plain);
    be->ldp(a, JP0, JP0, 0);
    be->bind(a, plain);
    be->bnullp(a, JP0, ex);
}

static int vt_shift(int vt) { return vt == BB_LONG || vt == BB_SINGLE ? 2 : vt == BB_DOUBLE ? 3 : 1; }

/* JP1 = address of element (i) or (i, j); JI3 index registers given */
static void elem1(T *t, int ri, int vt, int ex)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    be->ld16u(a, JI4, JP0, (int32_t)offsetof(bb_array, ndims));
    be->cmpi(a, JI4, 1);
    be->bcond(a, JC_NE, ex);
    be->ld32(a, JI3, JP0, (int32_t)offsetof(bb_array, dims));
    be->sub(a, JI3, ri, JI3);
    be->ld32(a, JI4, JP0, (int32_t)(offsetof(bb_array, dims) + offsetof(bb_dim, count)));
    be->cmpu(a, JI3, JI4);
    be->bcond(a, JC_GEU, ex);
    be->ldp(a, JP1, JP0, (int32_t)offsetof(bb_array, data));
    if (vt == BB_UDT) {
        be->ld32(a, JI4, JP0, (int32_t)offsetof(bb_array, esize));
        be->mul(a, JI3, JI3, JI4);
        be->addp_idx(a, JP1, JP1, JI3, 0);
    } else be->addp_idx(a, JP1, JP1, JI3, vt_shift(vt));
}

/* JP1 += offset of field f; JP2 holds the bb_udt_desc pointer */
static void field_off(T *t, int f)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    be->ldp(a, JP2, JP2, (int32_t)offsetof(bb_udt_desc, fields));
    be->ld32(a, JI4, JP2, f * (int32_t)sizeof(bb_field) + (int32_t)offsetof(bb_field, offset));
    be->addp_idx(a, JP1, JP1, JI4, 0);
}

/* JP1 = data of a UDT variable operand, JP2 = its descriptor */
static void udt_var(T *t, int32_t opnd)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    int base, box = ja_label(a), done = ja_label(a);
    int32_t off;
    base_of(opnd, &base, &off);
    be->ldp(a, JP1, base, off + 8);
    be->ld16u(a, JI4, base, off);
    be->cmpiu(a, JI4, BB_REF);
    be->bcond(a, JC_LTU, box);
    /* reference: descriptor = &ctx->udts[aux].desc */
    be->ld32(a, JI4, base, off + 4);
    be->li(a, JI3, (int32_t)sizeof(VMUdt));
    be->mul(a, JI4, JI4, JI3);
    be->ldp(a, JP2, JB_CTX, (int32_t)offsetof(bb_jitctx, udts));
    be->addp_idx(a, JP2, JP2, JI4, 0);
    be->addp_off(a, JP2, JP2, (int32_t)offsetof(VMUdt, desc));
    be->b(a, done);
    be->bind(a, box);
    be->ldp(a, JP2, JP1, (int32_t)offsetof(bb_udtbox, desc));
    be->addp_off(a, JP1, JP1, (int32_t)offsetof(bb_udtbox, data));
    be->bind(a, done);
}

static void load_elem(T *t, int vt, int dslot)
{
    const JBackend *be = t->be;
    if (vt == BB_LONG || vt == BB_SINGLE) { be->ld32(t->a, JI0, JP1, 0); be->st32(t->a, JI0, JB_L, SLOT_U(dslot)); }
    else if (vt == BB_DOUBLE) { be->ldf(t->a, JF0, JP1, 0); be->stf(t->a, JF0, JB_L, SLOT_U(dslot)); }
    else { be->ld16s(t->a, JI0, JP1, 0); be->st16(t->a, JI0, JB_L, SLOT_U(dslot)); }
}

static void store_elem(T *t, int vt, int sslot)
{
    const JBackend *be = t->be;
    if (vt == BB_LONG || vt == BB_SINGLE) { be->ld32(t->a, JI0, JB_L, SLOT_U(sslot)); be->st32(t->a, JI0, JP1, 0); }
    else if (vt == BB_DOUBLE) { be->ldf(t->a, JF0, JB_L, SLOT_U(sslot)); be->stf(t->a, JF0, JP1, 0); }
    else { be->ld16s(t->a, JI0, JB_L, SLOT_U(sslot)); be->st16(t->a, JI0, JP1, 0); }
}

static int cond_neg(int c)
{
    switch (c) {
    case JC_EQ: return JC_NE;
    case JC_NE: return JC_EQ;
    case JC_LT: return JC_GE;
    case JC_GE: return JC_LT;
    case JC_GT: return JC_LE;
    case JC_LE: return JC_GT;
    case JC_LTU: return JC_GEU;
    default: return JC_LTU;
    }
}

static int cond_of(int cmp)
{
    switch (cmp) {
    case BB_CMP_EQ: return JC_EQ;
    case BB_CMP_NE: return JC_NE;
    case BB_CMP_LT: return JC_LT;
    case BB_CMP_GT: return JC_GT;
    case BB_CMP_LE: return JC_LE;
    default: return JC_GE;
    }
}

/* integer ops: load operands (slot or immediate), compute, check, store */
enum { K_I, K_L };
static void ld_int(T *t, int k, int r, int32_t slot)
{
    if (k == K_L) t->be->ld32(t->a, r, JB_L, SLOT_U(slot));
    else t->be->ld16s(t->a, r, JB_L, SLOT_U(slot));
}
static void st_int(T *t, int k, int r, int32_t slot)
{
    if (k == K_L) t->be->st32(t->a, r, JB_L, SLOT_U(slot));
    else t->be->st16(t->a, r, JB_L, SLOT_U(slot));
}

static void int_op(T *t, int32_t pc, int k, int what, int form, const int32_t *w)
{
    /* form: 0 RR, 1 RI, 2 IR; what: 0 add 1 sub 2 mul 3 idiv 4 mod 5 and 6 or 7 xor */
    const JBackend *be = t->be;
    JA *a = t->a;
    int ex = exit_to(t, pc);
    if (form == 2) be->li(a, JI0, w[2]); else ld_int(t, k, JI0, w[2]);
    if (form == 1) be->li(a, JI1, w[3]); else ld_int(t, k, JI1, w[3]);
    switch (what) {
    case 0: if (k == K_L) be->add_ovf(a, JI2, JI0, JI1, ex); else be->add(a, JI2, JI0, JI1); break;
    case 1: if (k == K_L) be->sub_ovf(a, JI2, JI0, JI1, ex); else be->sub(a, JI2, JI0, JI1); break;
    case 2: if (k == K_L) be->mul_ovf(a, JI2, JI0, JI1, ex); else be->mul(a, JI2, JI0, JI1); break;
    case 3: case 4:
        be->cmpi(a, JI1, 0);
        be->bcond(a, JC_EQ, ex);
        if (k == K_L) { be->cmpi(a, JI1, -1); be->bcond(a, JC_EQ, ex); }
        if (what == 3) be->sdiv(a, JI2, JI0, JI1); else be->srem(a, JI2, JI0, JI1);
        break;
    case 5: be->and_(a, JI2, JI0, JI1); break;
    case 6: be->or_(a, JI2, JI0, JI1); break;
    default: be->xor_(a, JI2, JI0, JI1); break;
    }
    if (k == K_I && what <= 3) be->fit16(a, JI2, ex);
    st_int(t, k, JI2, w[1]);
}

static void dbl_op(T *t, int32_t pc, int what, int form, const int32_t *w)
{
    /* form: 0 RR, 1 RK, 2 KR; what: 0 add 1 sub 2 mul 3 div */
    const JBackend *be = t->be;
    JA *a = t->a;
    int ex = exit_to(t, pc);
    if (form == 2) be->ldf(a, JF0, JB_K, SLOT_U(w[2])); else be->ldf(a, JF0, JB_L, SLOT_U(w[2]));
    if (form == 1) be->ldf(a, JF1, JB_K, SLOT_U(w[3])); else be->ldf(a, JF1, JB_L, SLOT_U(w[3]));
    if (what == 3) be->fbzero(a, JF1, ex);
    be->fop(a, what, JF2, JF0, JF1);
    be->fchk(a, JF2, ex);
    be->stf(a, JF2, JB_L, SLOT_U(w[1]));
}

static void for_test(T *t, int k, int32_t pc, int32_t c, int32_t l, int32_t s, int32_t target, int inc)
{
    /* chk: if (s >= 0 ? c > l : c < l) goto target
     * inc: c += s (overflow: exit before storing); if !(s >= 0 ? c > l : c < l) goto target */
    const JBackend *be = t->be;
    JA *a = t->a;
    int neg = ja_label(a), next = ja_label(a), go = ja_label(a), ex = exit_to(t, pc);
    ld_int(t, k, JI0, c);
    ld_int(t, k, JI1, l);
    ld_int(t, k, JI2, s);
    if (inc) {
        if (k == K_L) be->add_ovf(a, JI0, JI0, JI2, ex);
        else { be->add(a, JI0, JI0, JI2); be->fit16(a, JI0, ex); }
        st_int(t, k, JI0, c);
    }
    be->cmpi(a, JI2, 0);
    be->bcond(a, JC_LT, neg);
    be->cmp(a, JI0, JI1);
    if (inc) be->bcond(a, JC_GT, next); else be->bcond(a, JC_GT, go);
    if (inc) be->b(a, go); else be->b(a, next);
    be->bind(a, neg);
    be->cmp(a, JI0, JI1);
    if (inc) be->bcond(a, JC_LT, next); else be->bcond(a, JC_LT, go);
    if (inc) be->b(a, go); else be->b(a, next);
    be->bind(a, go);
    branch_to(t, pc, target);
    be->bind(a, next);
}

static void for_test_d(T *t, int32_t pc, int32_t c, int32_t l, int32_t s, int32_t target, int inc)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    int neg = ja_label(a), next = ja_label(a), go = ja_label(a);
    (void)pc;
    be->ldf(a, JF0, JB_L, SLOT_U(c));
    be->ldf(a, JF1, JB_L, SLOT_U(l));
    be->ldf(a, JF2, JB_L, SLOT_U(s));
    if (inc) { be->fop(a, 0, JF0, JF0, JF2); be->stf(a, JF0, JB_L, SLOT_U(c)); }
    /* s < 0 ? (store 0.0 in JF1 temporarily is not possible: compare with ctx->zero) */
    be->ldf(a, JF1, JB_CTX, (int32_t)offsetof(bb_jitctx, zero));
    be->fcmp_b(a, JC_LT, JF2, JF1, neg);
    be->ldf(a, JF1, JB_L, SLOT_U(l));
    be->fcmp_b(a, JC_GT, JF0, JF1, inc ? next : go);
    be->b(a, inc ? go : next);
    be->bind(a, neg);
    be->ldf(a, JF1, JB_L, SLOT_U(l));
    be->fcmp_b(a, JC_LT, JF0, JF1, inc ? next : go);
    be->b(a, inc ? go : next);
    be->bind(a, go);
    branch_to(t, pc, target);
    be->bind(a, next);
}

static int translate(T *t, int32_t pc)
{
    const JBackend *be = t->be;
    JA *a = t->a;
    const int32_t *w = t->img->code + pc;
    int op = w[0], ex;
    switch (op) {
    case I_R_MOV: be->copy16(a, JB_L, SLOT_T(w[1]), JB_L, SLOT_T(w[2])); return 1;
    case I_R_MOVI_I: be->li(a, JI0, w[2]); be->st16(a, JI0, JB_L, SLOT_U(w[1])); return 1;
    case I_R_MOVI_L: be->li(a, JI0, w[2]); be->st32(a, JI0, JB_L, SLOT_U(w[1])); return 1;
    case I_R_MOVK: be->copy16(a, JB_L, SLOT_T(w[1]), JB_K, SLOT_T(w[2])); return 1;
    case I_R_ADD_LRR: int_op(t, pc, K_L, 0, 0, w); return 1;
    case I_R_ADD_LRI: int_op(t, pc, K_L, 0, 1, w); return 1;
    case I_R_SUB_LRR: int_op(t, pc, K_L, 1, 0, w); return 1;
    case I_R_SUB_LRI: int_op(t, pc, K_L, 1, 1, w); return 1;
    case I_R_SUB_LIR: int_op(t, pc, K_L, 1, 2, w); return 1;
    case I_R_MUL_LRR: int_op(t, pc, K_L, 2, 0, w); return 1;
    case I_R_MUL_LRI: int_op(t, pc, K_L, 2, 1, w); return 1;
    case I_R_IDIV_LRR: int_op(t, pc, K_L, 3, 0, w); return 1;
    case I_R_IDIV_LRI: int_op(t, pc, K_L, 3, 1, w); return 1;
    case I_R_MOD_LRR: int_op(t, pc, K_L, 4, 0, w); return 1;
    case I_R_MOD_LRI: int_op(t, pc, K_L, 4, 1, w); return 1;
    case I_R_AND_LRR: int_op(t, pc, K_L, 5, 0, w); return 1;
    case I_R_AND_LRI: int_op(t, pc, K_L, 5, 1, w); return 1;
    case I_R_OR_LRR: int_op(t, pc, K_L, 6, 0, w); return 1;
    case I_R_OR_LRI: int_op(t, pc, K_L, 6, 1, w); return 1;
    case I_R_XOR_LRR: int_op(t, pc, K_L, 7, 0, w); return 1;
    case I_R_XOR_LRI: int_op(t, pc, K_L, 7, 1, w); return 1;
    case I_R_ADD_IRR: int_op(t, pc, K_I, 0, 0, w); return 1;
    case I_R_ADD_IRI: int_op(t, pc, K_I, 0, 1, w); return 1;
    case I_R_SUB_IRR: int_op(t, pc, K_I, 1, 0, w); return 1;
    case I_R_SUB_IRI: int_op(t, pc, K_I, 1, 1, w); return 1;
    case I_R_SUB_IIR: int_op(t, pc, K_I, 1, 2, w); return 1;
    case I_R_MUL_IRR: int_op(t, pc, K_I, 2, 0, w); return 1;
    case I_R_MUL_IRI: int_op(t, pc, K_I, 2, 1, w); return 1;
    case I_R_IDIV_IRR: int_op(t, pc, K_I, 3, 0, w); return 1;
    case I_R_IDIV_IRI: int_op(t, pc, K_I, 3, 1, w); return 1;
    case I_R_MOD_IRR: int_op(t, pc, K_I, 4, 0, w); return 1;
    case I_R_MOD_IRI: int_op(t, pc, K_I, 4, 1, w); return 1;
    case I_R_AND_IRR: int_op(t, pc, K_I, 5, 0, w); return 1;
    case I_R_AND_IRI: int_op(t, pc, K_I, 5, 1, w); return 1;
    case I_R_OR_IRR: int_op(t, pc, K_I, 6, 0, w); return 1;
    case I_R_OR_IRI: int_op(t, pc, K_I, 6, 1, w); return 1;
    case I_R_XOR_IRR: int_op(t, pc, K_I, 7, 0, w); return 1;
    case I_R_XOR_IRI: int_op(t, pc, K_I, 7, 1, w); return 1;
    case I_R_NEG_L: case I_R_NEG_I: {
        int k = op == I_R_NEG_L ? K_L : K_I;
        ex = exit_to(t, pc);
        ld_int(t, k, JI0, w[2]);
        be->cmpi(a, JI0, k == K_L ? INT32_MIN : -32768);
        be->bcond(a, JC_EQ, ex);
        be->neg(a, JI0, JI0);
        st_int(t, k, JI0, w[1]);
        return 1;
    }
    case I_R_ADD_DRR: dbl_op(t, pc, 0, 0, w); return 1;
    case I_R_ADD_DRK: dbl_op(t, pc, 0, 1, w); return 1;
    case I_R_SUB_DRR: dbl_op(t, pc, 1, 0, w); return 1;
    case I_R_SUB_DRK: dbl_op(t, pc, 1, 1, w); return 1;
    case I_R_SUB_DKR: dbl_op(t, pc, 1, 2, w); return 1;
    case I_R_MUL_DRR: dbl_op(t, pc, 2, 0, w); return 1;
    case I_R_MUL_DRK: dbl_op(t, pc, 2, 1, w); return 1;
    case I_R_DIV_DRR: dbl_op(t, pc, 3, 0, w); return 1;
    case I_R_DIV_DRK: dbl_op(t, pc, 3, 1, w); return 1;
    case I_R_DIV_DKR: dbl_op(t, pc, 3, 2, w); return 1;
    case I_R_NEG_D:
        be->ldf(a, JF0, JB_L, SLOT_U(w[2]));
        be->fneg(a, JF0, JF0);
        be->stf(a, JF0, JB_L, SLOT_U(w[1]));
        return 1;
    case I_R_CVT_LD: case I_R_CVT_ID:
        ld_int(t, op == I_R_CVT_LD ? K_L : K_I, JI0, w[2]);
        be->fcvt(a, JF0, JI0);
        be->stf(a, JF0, JB_L, SLOT_U(w[1]));
        return 1;
    case I_R_CVT_IL:
        ld_int(t, K_I, JI0, w[2]);
        be->st32(a, JI0, JB_L, SLOT_U(w[1]));
        return 1;
    case I_R_JCMP_LRR: case I_R_JCMP_LRI: case I_R_JCMP_IRR: case I_R_JCMP_IRI: {
        int k = (op == I_R_JCMP_LRR || op == I_R_JCMP_LRI) ? K_L : K_I, imm = op == I_R_JCMP_LRI || op == I_R_JCMP_IRI;
        int skip = ja_label(a);
        ld_int(t, k, JI0, w[2]);
        if (imm) be->cmpi(a, JI0, w[3]);
        else { ld_int(t, k, JI1, w[3]); be->cmp(a, JI0, JI1); }
        /* not taken: skip; taken: branch (with poll if backward) */
        be->bcond(a, cond_neg(cond_of(w[1])), skip);
        branch_to(t, pc, w[4]);
        be->bind(a, skip);
        return 1;
    }
    case I_R_JCMP_DRR: case I_R_JCMP_DRK: {
        int go = ja_label(a), skip = ja_label(a);
        be->ldf(a, JF0, JB_L, SLOT_U(w[2]));
        be->ldf(a, JF1, op == I_R_JCMP_DRK ? JB_K : JB_L, SLOT_U(w[3]));
        be->fcmp_b(a, cond_of(w[1]), JF0, JF1, go);
        be->b(a, skip);
        be->bind(a, go);
        branch_to(t, pc, w[4]);
        be->bind(a, skip);
        return 1;
    }
    case I_R_JNZ: case I_R_JZ: {
        int skip = ja_label(a);
        be->ld16s(a, JI0, JB_L, SLOT_U(w[1]));
        be->cmpi(a, JI0, 0);
        be->bcond(a, op == I_R_JNZ ? JC_EQ : JC_NE, skip);
        branch_to(t, pc, w[2]);
        be->bind(a, skip);
        return 1;
    }
    case I_R_FORCHK_I: for_test(t, K_I, pc, w[1], w[2], w[3], w[4], 0); return 1;
    case I_R_FORCHK_L: for_test(t, K_L, pc, w[1], w[2], w[3], w[4], 0); return 1;
    case I_R_FORINC_I: for_test(t, K_I, pc, w[1], w[2], w[3], w[4], 1); return 1;
    case I_R_FORINC_L: for_test(t, K_L, pc, w[1], w[2], w[3], w[4], 1); return 1;
    case I_R_FORCHK_D: for_test_d(t, pc, w[1], w[2], w[3], w[4], 0); return 1;
    case I_R_FORINC_D: for_test_d(t, pc, w[1], w[2], w[3], w[4], 1); return 1;
    case I_R_LDE1: case I_R_STE1: {
        int vt = w[1], st = op == I_R_STE1;
        ex = exit_to(t, pc);
        load_array(t, st ? w[2] : w[3], ex);
        be->ld32(a, JI0, JB_L, SLOT_U(st ? w[3] : w[4]));
        elem1(t, JI0, vt, ex);
        if (st) store_elem(t, vt, w[4]); else load_elem(t, vt, w[2]);
        return 1;
    }
    case I_R_LDE2: case I_R_STE2: {
        int vt = w[1], st = op == I_R_STE2;
        ex = exit_to(t, pc);
        load_array(t, st ? w[2] : w[3], ex);
        be->ld32(a, JI0, JB_L, SLOT_U(st ? w[3] : w[4]));
        be->ld32(a, JI1, JB_L, SLOT_U(st ? w[4] : w[5]));
        /* elem2 uses JI1..JI4 for bounds: keep the indices in JI0 and a copy of j */
        be->ld32(a, JI2, JB_L, SLOT_U(st ? w[4] : w[5]));
        {
            /* elem2 clobbers JI1: pass j in a register it reads first */
            int rj = JI2;
            const JBackend *b2 = be;
            int32_t d0 = (int32_t)offsetof(bb_array, dims), d1 = d0 + (int32_t)sizeof(bb_dim), cnt = (int32_t)offsetof(bb_dim, count);
            b2->ld16u(a, JI4, JP0, (int32_t)offsetof(bb_array, ndims));
            b2->cmpi(a, JI4, 2);
            b2->bcond(a, JC_NE, ex);
            b2->ld32(a, JI3, JP0, d0);
            b2->sub(a, JI3, JI0, JI3);
            b2->ld32(a, JI4, JP0, d0 + cnt);
            b2->cmpu(a, JI3, JI4);
            b2->bcond(a, JC_GEU, ex);
            b2->ld32(a, JI1, JP0, d1);
            b2->sub(a, rj, rj, JI1);
            b2->ld32(a, JI1, JP0, d1 + cnt);
            b2->cmpu(a, rj, JI1);
            b2->bcond(a, JC_GEU, ex);
            b2->mul(a, rj, rj, JI4);
            b2->add(a, JI3, JI3, rj);
            b2->ldp(a, JP1, JP0, (int32_t)offsetof(bb_array, data));
            b2->addp_idx(a, JP1, JP1, JI3, vt_shift(vt));
        }
        if (st) store_elem(t, vt, w[5]); else load_elem(t, vt, w[2]);
        return 1;
    }
    case I_R_LDEF1: case I_R_STEF1: {
        int vt = w[1], st = op == I_R_STEF1;
        ex = exit_to(t, pc);
        load_array(t, st ? w[2] : w[3], ex);
        be->ld32(a, JI0, JB_L, SLOT_U(st ? w[3] : w[4]));
        elem1(t, JI0, BB_UDT, ex);
        be->ldp(a, JP2, JP0, (int32_t)offsetof(bb_array, udt));
        field_off(t, st ? w[4] : w[5]);
        if (st) store_elem(t, vt, w[5]); else load_elem(t, vt, w[2]);
        return 1;
    }
    case I_R_JMP:
        branch_to(t, pc, w[1]);
        return 1;
    case I_R_SQRT_D: {
        int ok = ja_label(a);
        ex = exit_to(t, pc);
        if (!be->fsqrt) return 0;
        be->ldf(a, JF0, JB_L, SLOT_U(w[2]));
        be->ldf(a, JF1, JB_CTX, (int32_t)offsetof(bb_jitctx, zero));
        be->fcmp_b(a, JC_GE, JF0, JF1, ok);
        be->b(a, ex);
        be->bind(a, ok);
        be->fsqrt(a, JF0, JF0);
        be->stf(a, JF0, JB_L, SLOT_U(w[1]));
        return 1;
    }
    case I_R_LDREF:
        be->ldp(a, JP1, JB_L, SLOT_U(w[3]));
        load_elem(t, w[1], w[2]);
        return 1;
    case I_R_STREF:
        be->ldp(a, JP1, JB_L, SLOT_U(w[2]));
        store_elem(t, w[1], w[3]);
        return 1;
    case I_R_LDF: case I_R_STF: {
        int vt = w[1], st = op == I_R_STF;
        udt_var(t, st ? w[2] : w[3]);
        field_off(t, st ? w[3] : w[4]);
        if (st) store_elem(t, vt, w[4]); else load_elem(t, vt, w[2]);
        return 1;
    }
    default:
        return 0;
    }
}

static const JBackend *g_be_for_scan;
static int region_end(VMImage *img, VMProc *p, int32_t start)
{
    int32_t pc = start, limit = img->ncode, i;
    for (i = 0; i < img->nprocs; i++) {
        int32_t c = img->procs[i].code;
        if (c > p->code && c < limit) limit = c;
    }
    while (pc < limit) {
        int op = img->code[pc];
        if (op < I_R_FIRST || op >= I__COUNT) break;
        if (op == I_R_SQRT_D && g_be_for_scan && !g_be_for_scan->fsqrt) break;
        if (op == I_R_CALLS || op == I_R_RET || op >= I_R_ADD_FRR) break;
        pc += 1 + bb_opwords[op];
    }
    return pc;
}

int jit_compile_region(const JBackend *be, VMImage *img, VMProc *p, int32_t start, JA *a, int32_t *end_out)
{
    T t;
    int32_t pc, end;
    int i, ok = 1;
    g_be_for_scan = be;
    end = region_end(img, p, start);
    (void)0;
    if (end <= start) return 0;
    {
        /* worth it only if the loop's back-edge is inside the region */
        int back = 0;
        for (pc = start; pc < end; pc += 1 + bb_opwords[img->code[pc]]) {
            const int32_t *w = img->code + pc;
            int32_t tg = -1;
            switch (w[0]) {
            case I_R_JCMP_LRR: case I_R_JCMP_LRI: case I_R_JCMP_IRR: case I_R_JCMP_IRI: case I_R_JCMP_DRR: case I_R_JCMP_DRK: tg = w[4]; break;
            case I_R_FORINC_I: case I_R_FORINC_L: case I_R_FORINC_D: tg = w[4]; break;
            case I_R_JNZ: case I_R_JZ: tg = w[2]; break;
            case I_R_JMP: tg = w[1]; break;
            default: break;
            }
            if (tg == start) back = 1;
        }
        if (!back) return 0;
    }
    memset(&t, 0, sizeof t);
    memset(a, 0, sizeof *a);
    a->be = be;
    t.a = a;
    t.be = be;
    t.img = img;
    t.start = start;
    t.end = end;
    t.oplab = (int *)malloc(sizeof(int) * (size_t)(end - start + 1));
    for (i = 0; i < end - start; i++) t.oplab[i] = -1;
    for (pc = start; pc < end; pc += 1 + bb_opwords[img->code[pc]]) t.oplab[pc - start] = ja_label(a);
    be->entry(a);
    for (pc = start; pc < end && ok; pc += 1 + bb_opwords[img->code[pc]]) {
        be->bind(a, t.oplab[pc - start]);
        ok = translate(&t, pc);
    }
    if (ok) {
        be->ret_pc(a, end);             /* fell off the region */
        for (i = 0; i < t.nexit; i++) {
            be->bind(a, t.exitlab[i]);
            be->ret_pc(a, t.exitpc[i]);
        }
        be->finish(a);
    }
    free(t.oplab);
    free(t.exitpc);
    free(t.exitlab);
    if (end_out) *end_out = end;
    return ok && !a->err;
}

/* ---------- code memory ---------- */

static unsigned char *arena;
static size_t arena_size, arena_used;

static void *code_alloc(size_t n)
{
    void *p;
    n = (n + 15) & ~(size_t)15;
    if (!arena) {
        arena_size = 4u << 20;
#if defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
        {
            int flags = MAP_PRIVATE | MAP_ANON;
#ifdef __APPLE__
            flags |= MAP_JIT;
#endif
            arena = (unsigned char *)mmap(NULL, arena_size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);
            if (arena == MAP_FAILED) arena = NULL;
        }
#elif defined(__amigaos4__)
        arena = (unsigned char *)IExec->AllocVecTags((uint32)arena_size, AVT_Type, MEMF_EXECUTABLE, AVT_Lock, FALSE, TAG_DONE);
#endif
        if (!arena) { arena_size = 0; return NULL; }
    }
    if (arena_used + n > arena_size) return NULL;
    p = arena + arena_used;
    arena_used += n;
    return p;
}

static void *install(JA *a)
{
    void *p = code_alloc((size_t)a->n);
    if (!p) return NULL;
#if defined(__aarch64__) && defined(__APPLE__)
    pthread_jit_write_protect_np(0);
    memcpy(p, a->buf, (size_t)a->n);
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(p, (size_t)a->n);
#elif defined(__aarch64__) && defined(__linux__)
    memcpy(p, a->buf, (size_t)a->n);
    __builtin___clear_cache((char *)p, (char *)p + a->n);
#elif defined(__amigaos4__)
    memcpy(p, a->buf, (size_t)a->n);
    IExec->CacheClearE(p, (uint32)a->n, CACRF_ClearD | CACRF_ClearI);
#else
    memcpy(p, a->buf, (size_t)a->n);
#endif
    return p;
}

/* ---------- cache: code offset -> compiled region ---------- */

typedef struct JE { int32_t off; int32_t state; bb_jitfn fn; int32_t count; } JE;   /* state: 0 none, 1 compiled, 2 failed */
static JE *cache;
static int32_t cache_cap, cache_n;

static JE *find(int32_t off)
{
    uint32_t h;
    if (!cache) {
        cache_cap = 1024;
        cache = (JE *)calloc((size_t)cache_cap, sizeof(JE));
        for (h = 0; h < (uint32_t)cache_cap; h++) cache[h].off = -1;
    }
    h = ((uint32_t)off * 2654435761u) & (uint32_t)(cache_cap - 1);
    for (;;) {
        if (cache[h].off == off) return &cache[h];
        if (cache[h].off == -1) {
            if (cache_n * 2 >= cache_cap) return NULL;
            cache_n++;
            cache[h].off = off;
            return &cache[h];
        }
        h = (h + 1) & (uint32_t)(cache_cap - 1);
    }
}

void jit_init(void)
{
    const char *e = getenv("BOING_JIT");
    const char *th = getenv("BOING_JIT_THRESHOLD");
    if (e) g_enabled = atoi(e) != 0;
    if (th) jit_threshold = atoi(th);
}

bb_jitfn jit_get(VMImage *img, VMProc *p, int32_t start)
{
    JE *e;
    JA *a;
    const JBackend *be = JIT_HOST_BACKEND;
    if (!be) return NULL;
    e = find(start);
    if (!e) return NULL;
    if (e->state == 1) return e->fn;
    if (e->state == 2) return NULL;
    a = (JA *)calloc(1, sizeof(JA));
    if (jit_compile_region(be, img, p, start, a, NULL)) {
        e->fn = (bb_jitfn)install(a);
        e->state = e->fn ? 1 : 2;
    } else e->state = 2;
    if (e->state == 2 && img->jitno) img->jitno[start] = 1;
    if (e->state == 1 && img->jitcode) img->jitcode[start] = e->fn;
    if (getenv("BOING_JIT_TRACE"))
        fprintf(stderr, "jit: %s @%ld: %s (%d bytes)\n", p->name, (long)start, e->state == 1 ? "compiled" : "not compiled", a->n);
    free(a->buf);
    free(a);
    return e->fn;
}

/* called at a backward branch to `target`: compiled code once the loop is hot */
bb_jitfn jit_hot(VMImage *img, VMProc *p, int32_t target)
{
    JE *e = find(target);
    if (!e) return NULL;
    if (e->state == 1) return e->fn;
    if (e->state == 2) return NULL;
    if (++e->count < jit_threshold) return NULL;
    return jit_get(img, p, target);
}
