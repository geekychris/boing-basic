/* jit_arm64.c - JIT backend for AArch64 (used on the Mac to test the translator)
 *
 * Registers: x0 ctx, x1 L, x2 G, x3 K; JI0..JI4 = w9..w13; JP0..JP2 = x14..x16;
 * x17 / w8 / d3 scratch; JF0..JF2 = d0..d2. Leaf code: no stack frame. */
#include "jit.h"
#include <string.h>

enum { FX_B26 = 1, FX_B19 };

static int ir(int r) { return 9 + r; }
static int pr(int p)
{
    switch (p) {
    case JB_L: return 1;
    case JB_G: return 2;
    case JB_K: return 3;
    case JB_CTX: return 0;
    default: return 14 + p;
    }
}
static int fr(int f) { return f; }

#define E(w) ja_emit32(a, (uint32_t)(w))
#define X17 17

static void movw(JA *a, int rd, uint32_t v)
{
    E(0x52800000u | ((v & 0xffff) << 5) | (uint32_t)rd);                 /* movz wd, lo */
    if (v >> 16) E(0x72a00000u | (((v >> 16) & 0xffff) << 5) | (uint32_t)rd);   /* movk wd, hi, lsl 16 */
}

static void movx(JA *a, int rd, int64_t v)
{
    uint64_t u = (uint64_t)v;
    int i, first = 1;
    for (i = 0; i < 4; i++) {
        uint32_t part = (uint32_t)((u >> (16 * i)) & 0xffff);
        if (!part && !(first && i == 3)) continue;
        if (first) { E(0xd2800000u | ((uint32_t)i << 21) | (part << 5) | (uint32_t)rd); first = 0; }
        else E(0xf2800000u | ((uint32_t)i << 21) | (part << 5) | (uint32_t)rd);
    }
    if (first) E(0xd2800000u | (uint32_t)rd);
}

/* load/store with base + offset: scaled imm12 if possible, else x17 = off, register form */
static void ldst(JA *a, uint32_t immop, uint32_t regop, int scale, int rt, int base, int32_t off)
{
    int rn = pr(base);
    if (off >= 0 && (off % scale) == 0 && off / scale < 4096) {
        E(immop | ((uint32_t)(off / scale) << 10) | ((uint32_t)rn << 5) | (uint32_t)rt);
        return;
    }
    movx(a, X17, off);
    E(regop | ((uint32_t)X17 << 16) | ((uint32_t)rn << 5) | (uint32_t)rt);
}

static void a_entry(JA *a)
{
    E(0xf9400001u | (0 << 10));         /* ldr x1, [x0, #0] */
    E(0xf9400402u);                     /* ldr x2, [x0, #8] */
    E(0xf9400803u);                     /* ldr x3, [x0, #16] */
}

static void a_ret_pc(JA *a, int32_t pc)
{
    movw(a, 0, (uint32_t)pc);
    E(0xd65f03c0u);
}

static void a_ld16s(JA *a, int r, int b, int32_t off) { ldst(a, 0x79c00000u, 0x78e06800u, 2, ir(r), b, off); }
static void a_ld16u(JA *a, int r, int b, int32_t off) { ldst(a, 0x79400000u, 0x78606800u, 2, ir(r), b, off); }
static void a_st16(JA *a, int r, int b, int32_t off) { ldst(a, 0x79000000u, 0x78206800u, 2, ir(r), b, off); }
static void a_ld32(JA *a, int r, int b, int32_t off) { ldst(a, 0xb9400000u, 0xb8606800u, 4, ir(r), b, off); }
static void a_st32(JA *a, int r, int b, int32_t off) { ldst(a, 0xb9000000u, 0xb8206800u, 4, ir(r), b, off); }
static void a_ldp(JA *a, int p, int b, int32_t off) { ldst(a, 0xf9400000u, 0xf8606800u, 8, pr(p), b, off); }
static void a_ldf(JA *a, int f, int b, int32_t off) { ldst(a, 0xfd400000u, 0xfc606800u, 8, fr(f), b, off); }
static void a_stf(JA *a, int f, int b, int32_t off) { ldst(a, 0xfd000000u, 0xfc206800u, 8, fr(f), b, off); }

static void a_copy16(JA *a, int db, int32_t doff, int sb, int32_t soff)
{
    /* through w8/x8 (x17 is used for large offsets) */
    ldst(a, 0xf9400000u, 0xf8606800u, 8, 8, sb, soff);
    ldst(a, 0xf9000000u, 0xf8206800u, 8, 8, db, doff);
    ldst(a, 0xf9400000u, 0xf8606800u, 8, 8, sb, soff + 8);
    ldst(a, 0xf9000000u, 0xf8206800u, 8, 8, db, doff + 8);
}

static void a_li(JA *a, int r, int32_t imm) { movw(a, ir(r), (uint32_t)imm); }

static void bcond_raw(JA *a, int cc, int label)
{
    ja_fixup(a, a->n, label, FX_B19);
    E(0x54000000u | (uint32_t)cc);
}

static void a_add_ovf(JA *a, int d, int x, int y, int l) { E(0x2b000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); bcond_raw(a, 6, l); }
static void a_sub_ovf(JA *a, int d, int x, int y, int l) { E(0x6b000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); bcond_raw(a, 6, l); }
static void a_mul_ovf(JA *a, int d, int x, int y, int l)
{
    E(0x9b207c00u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | X17);   /* smull x17, wx, wy */
    E(0xeb20c000u | (X17 << 16) | (X17 << 5) | 31);                           /* cmp x17, w17, sxtw */
    bcond_raw(a, 1, l);                                                         /* b.ne */
    E(0x2a0003e0u | (X17 << 16) | (uint32_t)ir(d));                            /* mov wd, w17 */
}
static void a_add(JA *a, int d, int x, int y) { E(0x0b000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_sub(JA *a, int d, int x, int y) { E(0x4b000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_mul(JA *a, int d, int x, int y) { E(0x1b007c00u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_and(JA *a, int d, int x, int y) { E(0x0a000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_or(JA *a, int d, int x, int y) { E(0x2a000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_xor(JA *a, int d, int x, int y) { E(0x4a000000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_neg(JA *a, int d, int x) { E(0x4b0003e0u | ((uint32_t)ir(x) << 16) | (uint32_t)ir(d)); }
static void a_sdiv(JA *a, int d, int x, int y) { E(0x1ac00c00u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | (uint32_t)ir(d)); }
static void a_srem(JA *a, int d, int x, int y)
{
    E(0x1ac00c00u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5) | X17);                            /* sdiv w17, x, y */
    E(0x1b008000u | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 10) | (X17 << 5) | (uint32_t)ir(d));  /* msub d, w17, y, x */
}
static void a_fit16(JA *a, int r, int l)
{
    E(0x13003c00u | ((uint32_t)ir(r) << 5) | X17);                         /* sxth w17, wr */
    E(0x6b00001fu | ((uint32_t)ir(r) << 16) | (X17 << 5));                 /* cmp w17, wr */
    bcond_raw(a, 1, l);
}
static void a_cmp(JA *a, int x, int y) { E(0x6b00001fu | ((uint32_t)ir(y) << 16) | ((uint32_t)ir(x) << 5)); }
static void a_cmpi(JA *a, int x, int32_t imm)
{
    if (imm >= 0 && imm < 4096) E(0x7100001fu | ((uint32_t)imm << 10) | ((uint32_t)ir(x) << 5));
    else if (imm < 0 && imm > -4096) E(0x3100001fu | ((uint32_t)(-imm) << 10) | ((uint32_t)ir(x) << 5));   /* cmn */
    else if (imm > 0 && (imm & 0xfff) == 0 && imm < (1 << 24)) E(0x7140001fu | ((uint32_t)(imm >> 12) << 10) | ((uint32_t)ir(x) << 5));
    else { movw(a, X17, (uint32_t)imm); E(0x6b00001fu | (X17 << 16) | ((uint32_t)ir(x) << 5)); }
}
static void a_bcond(JA *a, int c, int l)
{
    static const int cc[] = {0, 1, 11, 12, 13, 10, 3, 2};   /* EQ NE LT GT LE GE LO HS */
    bcond_raw(a, cc[c], l);
}
static void a_b(JA *a, int l) { ja_fixup(a, a->n, l, FX_B26); E(0x14000000u); }
static void a_bnullp(JA *a, int p, int l) { ja_fixup(a, a->n, l, FX_B19); E(0xb4000000u | (uint32_t)pr(p)); }
static void a_addp_idx(JA *a, int p, int b, int idx, int shift)
{
    E(0x8b204000u | ((uint32_t)ir(idx) << 16) | ((uint32_t)shift << 10) | ((uint32_t)pr(b) << 5) | (uint32_t)pr(p));
}
static void a_addp_off(JA *a, int p, int b, int32_t off)
{
    if (off >= 0 && off < 4096) { E(0x91000000u | ((uint32_t)off << 10) | ((uint32_t)pr(b) << 5) | (uint32_t)pr(p)); return; }
    movx(a, X17, off);
    E(0x8b000000u | (X17 << 16) | ((uint32_t)pr(b) << 5) | (uint32_t)pr(p));
}
static void a_fop(JA *a, int op, int d, int x, int y)
{
    static const uint32_t o[] = {0x1e602800u, 0x1e603800u, 0x1e600800u, 0x1e601800u};
    E(o[op] | ((uint32_t)fr(y) << 16) | ((uint32_t)fr(x) << 5) | (uint32_t)fr(d));
}
static void a_fneg(JA *a, int d, int x) { E(0x1e614000u | ((uint32_t)fr(x) << 5) | (uint32_t)fr(d)); }
static void a_fcvt(JA *a, int f, int r) { E(0x1e620000u | ((uint32_t)ir(r) << 5) | (uint32_t)fr(f)); }
static void a_fchk(JA *a, int f, int l)
{
    E(0x1e603800u | ((uint32_t)fr(f) << 16) | ((uint32_t)fr(f) << 5) | 3);   /* fsub d3, f, f */
    E(0x1e602000u | (3 << 16) | (3 << 5));                                  /* fcmp d3, d3 */
    bcond_raw(a, 1, l);                                                      /* b.ne (also unordered) */
}
static void a_fbzero(JA *a, int f, int l)
{
    E(0x1e602008u | ((uint32_t)fr(f) << 5));     /* fcmp df, #0.0 */
    bcond_raw(a, 0, l);
}
static void a_fcmp_b(JA *a, int c, int x, int y, int l)
{
    static const int cc[] = {0, 1, 4, 12, 9, 10, 3, 2};    /* EQ NE MI GT LS GE (ordered) */
    E(0x1e602000u | ((uint32_t)fr(y) << 16) | ((uint32_t)fr(x) << 5));
    bcond_raw(a, cc[c], l);
}
static void a_poll(JA *a, int l)
{
    E(0xf9400c11u);                 /* ldr x17, [x0, #24] */
    E(0xb9400228u);                 /* ldr w8, [x17] */
    E(0x71000508u);                 /* subs w8, w8, #1 */
    E(0xb9000228u);                 /* str w8, [x17] */
    bcond_raw(a, 4, l);             /* b.mi */
}
static void a_fsqrt(JA *a, int d, int x) { E(0x1e61c000u | ((uint32_t)fr(x) << 5) | (uint32_t)fr(d)); }
static void a_bind(JA *a, int l) { a->lab[l] = a->n; }
static void a_finish(JA *a)
{
    int i;
    for (i = 0; i < a->nfix; i++) {
        int at = a->fix[i].at, to = a->lab[a->fix[i].label];
        uint32_t w;
        int32_t d;
        if (to < 0) { a->err = 1; return; }
        d = (to - at) / 4;
        memcpy(&w, a->buf + at, 4);
        if (a->fix[i].kind == FX_B26) w |= (uint32_t)d & 0x3ffffff;
        else w |= ((uint32_t)d & 0x7ffff) << 5;
        memcpy(a->buf + at, &w, 4);
    }
}

const JBackend jit_arm64 = {
    "arm64", a_entry, a_ret_pc, a_ld16s, a_ld16u, a_st16, a_ld32, a_st32, a_ldp, a_ldf, a_stf, a_copy16, a_li,
    a_add_ovf, a_sub_ovf, a_mul_ovf, a_add, a_sub, a_mul, a_and, a_or, a_xor, a_neg, a_sdiv, a_srem, a_fit16,
    a_cmp, a_cmpi, a_cmp, a_cmpi, a_bcond, a_b, a_bnullp, a_addp_idx, a_addp_off, a_fop, a_fneg, a_fcvt, a_fchk, a_fbzero,
    a_fcmp_b, a_poll, a_bind, a_finish, a_fsqrt
};
