/* jit.h - the Boing BASIC template JIT for register-form bytecode (docs/jit.md)
 *
 * A region is a run of register ops (opcodes >= I_R_FIRST) starting at a hot loop head.
 * Compiled regions are called with a context and return the bytecode offset at which
 * the interpreter continues. Every slow path (overflow, division by zero, a bad index,
 * the Ctrl-C poll) leaves *before* the op takes effect, so the interpreter re-executes
 * that op and behaves exactly as without the JIT.
 */
#ifndef BB_JIT_H
#define BB_JIT_H

#include "bytecode.h"

typedef struct bb_jitctx {
    bb_value *L;                /* frame slots */
    bb_value *G;                /* globals */
    const bb_value *K;          /* constants */
    int32_t *poll;              /* &bb_poll_count */
    const VMUdt *udts;          /* UDT descriptors (field offsets) */
    double scratch;             /* PPC: int <-> double conversion */
    double zero;                /* 0.0 */
} bb_jitctx;

typedef int32_t (*bb_jitfn)(bb_jitctx *ctx);

/* ---- the assembler interface each backend implements ---- */

typedef struct JA JA;
enum { JI0, JI1, JI2, JI3, JI4, JNI };           /* 32-bit integer registers */
enum { JP0, JP1, JP2, JNP };                     /* pointer registers */
enum { JF0, JF1, JF2, JNF };                     /* double registers */
enum { JB_L = 100, JB_G, JB_K, JB_CTX };          /* base registers (as "pointer" operands) */
enum { JC_EQ, JC_NE, JC_LT, JC_GT, JC_LE, JC_GE, JC_LTU, JC_GEU };

typedef struct JBackend {
    const char *name;
    void (*entry)(JA *a);
    void (*ret_pc)(JA *a, int32_t pc);           /* return pc to the interpreter */
    /* loads/stores: base is a pointer register (JP*) or JB_*; off a byte offset */
    void (*ld16s)(JA *a, int r, int base, int32_t off);
    void (*ld16u)(JA *a, int r, int base, int32_t off);
    void (*st16)(JA *a, int r, int base, int32_t off);
    void (*ld32)(JA *a, int r, int base, int32_t off);
    void (*st32)(JA *a, int r, int base, int32_t off);
    void (*ldp)(JA *a, int p, int base, int32_t off);
    void (*ldf)(JA *a, int f, int base, int32_t off);
    void (*stf)(JA *a, int f, int base, int32_t off);
    void (*copy16)(JA *a, int dbase, int32_t doff, int sbase, int32_t soff);
    void (*li)(JA *a, int r, int32_t imm);
    /* d = a op b; the _ovf forms branch to label on signed overflow */
    void (*add_ovf)(JA *a, int d, int x, int y, int label);
    void (*sub_ovf)(JA *a, int d, int x, int y, int label);
    void (*mul_ovf)(JA *a, int d, int x, int y, int label);
    void (*add)(JA *a, int d, int x, int y);
    void (*sub)(JA *a, int d, int x, int y);
    void (*mul)(JA *a, int d, int x, int y);
    void (*and_)(JA *a, int d, int x, int y);
    void (*or_)(JA *a, int d, int x, int y);
    void (*xor_)(JA *a, int d, int x, int y);
    void (*neg)(JA *a, int d, int x);
    void (*sdiv)(JA *a, int d, int x, int y);    /* y != 0, not (MIN, -1) */
    void (*srem)(JA *a, int d, int x, int y);
    void (*fit16)(JA *a, int r, int label);      /* branch to label if r is not an Integer */
    void (*cmp)(JA *a, int x, int y);
    void (*cmpi)(JA *a, int x, int32_t imm);     /* any imm */
    void (*bcond)(JA *a, int cond, int label);   /* after cmp/cmpi */
    void (*b)(JA *a, int label);
    void (*bnullp)(JA *a, int p, int label);     /* branch if pointer is NULL */
    /* pointers: p = base + (idx << shift) (idx zero-extended); p = base + off */
    void (*addp_idx)(JA *a, int p, int base, int idx, int shift);
    void (*addp_off)(JA *a, int p, int base, int32_t off);
    /* doubles */
    void (*fop)(JA *a, int op, int d, int x, int y);   /* op: 0 add 1 sub 2 mul 3 div */
    void (*fneg)(JA *a, int d, int x);
    void (*fcvt)(JA *a, int f, int r);           /* f = (double)r */
    void (*fchk)(JA *a, int f, int label);       /* branch if f is not finite */
    void (*fbzero)(JA *a, int f, int label);     /* branch if f == 0 */
    void (*fcmp_b)(JA *a, int cond, int x, int y, int label);  /* branch if x cond y (ordered) */
    void (*poll)(JA *a, int label);              /* --*ctx->poll < 0: branch */
    /* code buffer */
    void (*bind)(JA *a, int label);
    void (*finish)(JA *a);                       /* resolve branches */
    void (*fsqrt)(JA *a, int d, int x);          /* NULL if the CPU has none */
} JBackend;

#define JMAXLAB 4096
struct JA {
    unsigned char *buf;
    int n, cap;
    int err;
    const JBackend *be;
    int lab[JMAXLAB];           /* native offset of each label, -1 = unbound */
    int nlab;
    struct { int at, label, kind; } fix[JMAXLAB * 2];
    int nfix;
};

int ja_label(JA *a);
void ja_emit32(JA *a, uint32_t w);              /* native byte order of the target */
void ja_emit32be(JA *a, uint32_t w);            /* big-endian (PPC) */
void ja_fixup(JA *a, int at, int label, int kind);

extern const JBackend jit_arm64;
extern const JBackend jit_ppc32;

/* ---- VM side ---- */
int jit_compile_region(const JBackend *be, VMImage *img, VMProc *p, int32_t start, JA *a, int32_t *end_out);
bb_jitfn jit_get(VMImage *img, VMProc *p, int32_t start);  /* compile once (NULL if not possible) */
bb_jitfn jit_hot(VMImage *img, VMProc *p, int32_t target);  /* count a back-edge; code when hot */
void jit_init(void);
int jit_enabled(void);
void jit_set_enabled(int on);
extern int jit_threshold;

#endif
