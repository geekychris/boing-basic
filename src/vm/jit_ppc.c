/* jit_ppc.c - JIT backend for 32-bit PowerPC (AmigaOS 4, SysV ABI, generic -mcpu=powerpc)
 *
 * Registers: r3 ctx (and the return value), r4 L, r5 G, r6 K; JI0..JI4 = r7..r11;
 * JP0..JP2 = r12, r14, r15 (r14/r15 saved); r16 (saved) and r0 scratch; JF0..JF2 = f0..f2,
 * f3/f4 scratch. A 32-byte stack frame holds r14..r16.
 * Signed overflow: XER is cleared on entry and the "o." forms set SO, tested with bso.
 * Only instructions every 32-bit PowerPC has (no fsqrt, no 64-bit ops, no 440 dlmzb).
 * Code is emitted big-endian, so the host can generate it for disassembly tests. */
#include "jit.h"
#include <string.h>
#include <stddef.h>

enum { FX_B24 = 1, FX_B14 };

#define E(w) ja_emit32be(a, (uint32_t)(w))
#define R0 0
#define R16 16

static int ir(int r) { return 7 + r; }
static int pr(int p)
{
    switch (p) {
    case JB_L: return 4;
    case JB_G: return 5;
    case JB_K: return 6;
    case JB_CTX: return 3;
    case JP0: return 12;
    case JP1: return 14;
    default: return 15;
    }
}
static int fr(int f) { return f; }

static uint32_t D(int op, int d, int ra, int32_t imm) { return ((uint32_t)op << 26) | ((uint32_t)d << 21) | ((uint32_t)ra << 16) | ((uint32_t)imm & 0xffff); }
static uint32_t X(int d, int ra, int rb, int xo) { return (31u << 26) | ((uint32_t)d << 21) | ((uint32_t)ra << 16) | ((uint32_t)rb << 11) | ((uint32_t)xo << 1); }
static uint32_t XO(int d, int ra, int rb, int oe, int xo, int rc) { return X(d, ra, rb, 0) | ((uint32_t)oe << 10) | ((uint32_t)xo << 1) | (uint32_t)rc; }

static void li32(JA *a, int r, int32_t v)
{
    if (v >= -32768 && v <= 32767) { E(D(14, r, 0, v)); return; }         /* li */
    E(D(15, r, 0, (int32_t)((uint32_t)v >> 16)));                        /* lis */
    if (v & 0xffff) E(D(24, r, r, v & 0xffff));                           /* ori */
}

/* D-form load/store with any offset (X-form through r16 when large) */
static void ldst(JA *a, int dop, int xop, int rt, int base, int32_t off)
{
    int ra = pr(base);
    if (off >= -32768 && off <= 32767) { E(D(dop, rt, ra, off)); return; }
    li32(a, R16, off);
    E(X(rt, ra, R16, xop));
}

static void p_entry(JA *a)
{
    E(D(37, 1, 1, -32));            /* stwu r1, -32(r1) */
    E(D(36, 14, 1, 8));             /* stw r14, 8(r1) */
    E(D(36, 15, 1, 12));
    E(D(36, 16, 1, 16));
    E(D(14, R0, 0, 0));             /* li r0, 0 */
    E(X(R0, 1, 0, 467));            /* mtxer r0 (spr 1) */
    E(D(32, 4, 3, (int32_t)offsetof(bb_jitctx, L)));
    E(D(32, 5, 3, (int32_t)offsetof(bb_jitctx, G)));
    E(D(32, 6, 3, (int32_t)offsetof(bb_jitctx, K)));
}

static void p_ret_pc(JA *a, int32_t pc)
{
    li32(a, 3, pc);
    E(D(32, 14, 1, 8));
    E(D(32, 15, 1, 12));
    E(D(32, 16, 1, 16));
    E(D(14, 1, 1, 32));             /* addi r1, r1, 32 */
    E(0x4e800020u);                 /* blr */
}

static void p_ld16s(JA *a, int r, int b, int32_t off) { ldst(a, 42, 343, ir(r), b, off); }
static void p_ld16u(JA *a, int r, int b, int32_t off) { ldst(a, 40, 279, ir(r), b, off); }
static void p_st16(JA *a, int r, int b, int32_t off) { ldst(a, 44, 407, ir(r), b, off); }
static void p_ld32(JA *a, int r, int b, int32_t off) { ldst(a, 32, 23, ir(r), b, off); }
static void p_st32(JA *a, int r, int b, int32_t off) { ldst(a, 36, 151, ir(r), b, off); }
static void p_ldp(JA *a, int p, int b, int32_t off) { ldst(a, 32, 23, pr(p), b, off); }
static void p_ldf(JA *a, int f, int b, int32_t off) { ldst(a, 50, 599, fr(f), b, off); }
static void p_stf(JA *a, int f, int b, int32_t off) { ldst(a, 54, 727, fr(f), b, off); }

static void p_copy16(JA *a, int db, int32_t doff, int sb, int32_t soff)
{
    /* through f3: two doubles (bit patterns are copied unchanged by lfd/stfd) */
    ldst(a, 50, 599, 3, sb, soff);
    ldst(a, 54, 727, 3, db, doff);
    ldst(a, 50, 599, 3, sb, soff + 8);
    ldst(a, 54, 727, 3, db, doff + 8);
}

static void p_li(JA *a, int r, int32_t imm) { li32(a, ir(r), imm); }

static void bc(JA *a, int bo, int bi, int label)
{
    ja_fixup(a, a->n, label, FX_B14);
    E((16u << 26) | ((uint32_t)bo << 21) | ((uint32_t)bi << 16));
}
#define BSO(l) bc(a, 12, 3, (l))

static void p_add_ovf(JA *a, int d, int x, int y, int l) { E(XO(ir(d), ir(x), ir(y), 1, 266, 1)); BSO(l); }
static void p_sub_ovf(JA *a, int d, int x, int y, int l) { E(XO(ir(d), ir(y), ir(x), 1, 40, 1)); BSO(l); }   /* subfo. d = x - y */
static void p_mul_ovf(JA *a, int d, int x, int y, int l) { E(XO(ir(d), ir(x), ir(y), 1, 235, 1)); BSO(l); }
static void p_add(JA *a, int d, int x, int y) { E(XO(ir(d), ir(x), ir(y), 0, 266, 0)); }
static void p_sub(JA *a, int d, int x, int y) { E(XO(ir(d), ir(y), ir(x), 0, 40, 0)); }
static void p_mul(JA *a, int d, int x, int y) { E(XO(ir(d), ir(x), ir(y), 0, 235, 0)); }
static void p_and(JA *a, int d, int x, int y) { E(X(ir(x), ir(d), ir(y), 28)); }       /* and ra, rs, rb */
static void p_or(JA *a, int d, int x, int y) { E(X(ir(x), ir(d), ir(y), 444)); }
static void p_xor(JA *a, int d, int x, int y) { E(X(ir(x), ir(d), ir(y), 316)); }
static void p_neg(JA *a, int d, int x) { E(XO(ir(d), ir(x), 0, 0, 104, 0)); }
static void p_sdiv(JA *a, int d, int x, int y) { E(XO(ir(d), ir(x), ir(y), 0, 491, 0)); }
static void p_srem(JA *a, int d, int x, int y)
{
    E(XO(R0, ir(x), ir(y), 0, 491, 0));          /* divw r0, x, y */
    E(XO(R0, R0, ir(y), 0, 235, 0));             /* mullw r0, r0, y */
    E(XO(ir(d), R0, ir(x), 0, 40, 0));           /* subf d, r0, x  (x - r0) */
}
static void p_fit16(JA *a, int r, int l)
{
    E(X(ir(r), R0, 0, 922));                     /* extsh r0, r */
    E(X(0, R0, ir(r), 0));                       /* cmpw cr0, r0, r */
    bc(a, 4, 2, l);                              /* bne */
}
static void p_cmp(JA *a, int x, int y) { E(X(0, ir(x), ir(y), 0)); }
static void p_cmpu(JA *a, int x, int y) { E(X(0, ir(x), ir(y), 32)); }
static void p_cmpi(JA *a, int x, int32_t imm)
{
    if (imm >= -32768 && imm <= 32767) { E(D(11, 0, ir(x), imm)); return; }
    li32(a, R0, imm);
    E(X(0, ir(x), R0, 0));
}
static void p_cmpiu(JA *a, int x, int32_t imm)
{
    if (imm >= 0 && imm <= 65535) { E(D(10, 0, ir(x), imm)); return; }
    li32(a, R0, imm);
    E(X(0, ir(x), R0, 32));
}
static void p_bcond(JA *a, int c, int l)
{
    switch (c) {
    case JC_EQ: bc(a, 12, 2, l); break;
    case JC_NE: bc(a, 4, 2, l); break;
    case JC_LT: case JC_LTU: bc(a, 12, 0, l); break;
    case JC_GE: case JC_GEU: bc(a, 4, 0, l); break;
    case JC_GT: bc(a, 12, 1, l); break;
    default: bc(a, 4, 1, l); break;           /* LE */
    }
}
static void p_b(JA *a, int l) { ja_fixup(a, a->n, l, FX_B24); E(18u << 26); }
static void p_bnullp(JA *a, int p, int l) { E(D(11, 0, pr(p), 0)); bc(a, 12, 2, l); }
static void p_addp_idx(JA *a, int p, int b, int idx, int shift)
{
    if (shift) {
        /* rlwinm r0, idx, shift, 0, 31-shift (slwi) */
        E((21u << 26) | ((uint32_t)ir(idx) << 21) | ((uint32_t)R0 << 16) | ((uint32_t)shift << 11) | (0u << 6) | ((uint32_t)(31 - shift) << 1));
        E(XO(pr(p), pr(b), R0, 0, 266, 0));
    } else E(XO(pr(p), pr(b), ir(idx), 0, 266, 0));
}
static void p_addp_off(JA *a, int p, int b, int32_t off)
{
    if (off >= -32768 && off <= 32767) { E(D(14, pr(p), pr(b), off)); return; }
    li32(a, R16, off);
    E(XO(pr(p), pr(b), R16, 0, 266, 0));
}
static void p_fop(JA *a, int op, int d, int x, int y)
{
    uint32_t base = (63u << 26) | ((uint32_t)fr(d) << 21) | ((uint32_t)fr(x) << 16);
    switch (op) {
    case 0: E(base | ((uint32_t)fr(y) << 11) | (21u << 1)); break;
    case 1: E(base | ((uint32_t)fr(y) << 11) | (20u << 1)); break;
    case 2: E(base | ((uint32_t)fr(y) << 6) | (25u << 1)); break;   /* fmul: frC */
    default: E(base | ((uint32_t)fr(y) << 11) | (18u << 1)); break;
    }
}
static void p_fneg(JA *a, int d, int x) { E((63u << 26) | ((uint32_t)fr(d) << 21) | ((uint32_t)fr(x) << 11) | (40u << 1)); }
static void p_fcvt(JA *a, int f, int r)
{
    /* (double)r = bits(0x43300000, r ^ 0x80000000) - 2^52 - 2^31 */
    int32_t s = (int32_t)offsetof(bb_jitctx, scratch), m = (int32_t)offsetof(bb_jitctx, magic);
    E(D(15, R0, 0, 0x4330));                      /* lis r0, 0x4330 */
    E(D(36, R0, 3, s));                           /* stw r0, scratch(r3) */
    E(D(27, ir(r), R16, 0x8000));                 /* xoris r16, r, 0x8000 */
    E(D(36, R16, 3, s + 4));                      /* stw r16, scratch+4(r3) */
    E(D(50, fr(f), 3, s));                        /* lfd f, scratch(r3) */
    E(D(50, 4, 3, m));                            /* lfd f4, magic(r3) */
    E((63u << 26) | ((uint32_t)fr(f) << 21) | ((uint32_t)fr(f) << 16) | (4u << 11) | (20u << 1));   /* fsub f, f, f4 */
}
static void fcmpu(JA *a, int x, int y) { E((63u << 26) | ((uint32_t)fr(x) << 16) | ((uint32_t)fr(y) << 11)); }
static void p_fchk(JA *a, int f, int l)
{
    E((63u << 26) | (3u << 21) | ((uint32_t)fr(f) << 16) | ((uint32_t)fr(f) << 11) | (20u << 1));   /* fsub f3, f, f */
    fcmpu(a, 3, 3);
    bc(a, 4, 2, l);                               /* bne: not equal or unordered */
}
static void p_fbzero(JA *a, int f, int l)
{
    E(D(50, 4, 3, (int32_t)offsetof(bb_jitctx, zero)));   /* lfd f4, zero(r3) */
    fcmpu(a, fr(f), 4);
    bc(a, 12, 2, l);
}
static void p_fcmp_b(JA *a, int c, int x, int y, int l)
{
    fcmpu(a, fr(x), fr(y));
    switch (c) {
    case JC_EQ: bc(a, 12, 2, l); break;
    case JC_NE: bc(a, 4, 2, l); break;
    case JC_LT: bc(a, 12, 0, l); break;
    case JC_GT: bc(a, 12, 1, l); break;
    case JC_LE: E((19u << 26) | (2u << 21) | (0u << 16) | (2u << 11) | (449u << 1)); bc(a, 12, 2, l); break;  /* cror eq, lt, eq */
    default: E((19u << 26) | (2u << 21) | (1u << 16) | (2u << 11) | (449u << 1)); bc(a, 12, 2, l); break;     /* cror eq, gt, eq */
    }
}
static void p_poll(JA *a, int l)
{
    E(D(32, R16, 3, (int32_t)offsetof(bb_jitctx, poll)));   /* lwz r16, poll(r3) */
    E(D(32, R0, R16, 0));                                   /* lwz r0, 0(r16) */
    E(D(13, R0, R0, -1));                                   /* addic. r0, r0, -1 */
    E(D(36, R0, R16, 0));                                   /* stw r0, 0(r16) */
    bc(a, 12, 0, l);                                        /* blt */
}
static void p_bind(JA *a, int l) { a->lab[l] = a->n; }
static void p_finish(JA *a)
{
    int i;
    for (i = 0; i < a->nfix; i++) {
        int at = a->fix[i].at, to = a->lab[a->fix[i].label];
        uint32_t w;
        int32_t d;
        if (to < 0) { a->err = 1; return; }
        d = to - at;
        w = ((uint32_t)a->buf[at] << 24) | ((uint32_t)a->buf[at + 1] << 16) | ((uint32_t)a->buf[at + 2] << 8) | a->buf[at + 3];
        if (a->fix[i].kind == FX_B24) {
            if (d < -(1 << 25) || d >= (1 << 25)) { a->err = 1; return; }
            w |= (uint32_t)d & 0x03fffffcu;
        } else {
            if (d < -32768 || d > 32767) { a->err = 1; return; }
            w |= (uint32_t)d & 0xfffcu;
        }
        a->buf[at] = (unsigned char)(w >> 24);
        a->buf[at + 1] = (unsigned char)(w >> 16);
        a->buf[at + 2] = (unsigned char)(w >> 8);
        a->buf[at + 3] = (unsigned char)w;
    }
}

const JBackend jit_ppc32 = {
    "ppc32", p_entry, p_ret_pc, p_ld16s, p_ld16u, p_st16, p_ld32, p_st32, p_ldp, p_ldf, p_stf, p_copy16, p_li,
    p_add_ovf, p_sub_ovf, p_mul_ovf, p_add, p_sub, p_mul, p_and, p_or, p_xor, p_neg, p_sdiv, p_srem, p_fit16,
    p_cmp, p_cmpi, p_cmpu, p_cmpiu, p_bcond, p_b, p_bnullp, p_addp_idx, p_addp_off, p_fop, p_fneg, p_fcvt, p_fchk,
    p_fbzero, p_fcmp_b, p_poll, p_bind, p_finish, NULL
};
