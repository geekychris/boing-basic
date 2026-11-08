/* decimal.c - VB's Decimal: a Variant subtype (VarType 14), 96-bit unsigned mantissa, scale
 * 0..28 (value = mantissa / 10^scale) and a sign. Stored in a bb_value as VB stores it in a
 * VARIANT: flags = scale | sign bit, aux = high 32 bits, u.c = low 64 bits.
 * All arithmetic on 32-bit limbs (no 128-bit integers on 32-bit PPC). Results that do not fit
 * lose scale (banker's rounding); a result that does not fit at scale 0 is error 6.
 */
#include "boing.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define NL 7                    /* wide limbs: 224 bits, room for 96x96 products and scaling */
#define DEC_SIGN 0x8000

typedef struct { uint32_t m[NL]; int scale, neg; } wide;

/* ---- wide unsigned integers ---- */
static int w_zero(const uint32_t *m) { int i; for (i = 0; i < NL; i++) if (m[i]) return 0; return 1; }
static int w_fits96(const uint32_t *m) { int i; for (i = 3; i < NL; i++) if (m[i]) return 0; return 1; }
static int w_cmp(const uint32_t *a, const uint32_t *b)
{
    int i;
    for (i = NL - 1; i >= 0; i--) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    return 0;
}
static void w_add(uint32_t *r, const uint32_t *a, const uint32_t *b)
{
    uint64_t c = 0;
    int i;
    for (i = 0; i < NL; i++) { c += (uint64_t)a[i] + b[i]; r[i] = (uint32_t)c; c >>= 32; }
}
static void w_sub(uint32_t *r, const uint32_t *a, const uint32_t *b)     /* a >= b */
{
    int64_t c = 0;
    int i;
    for (i = 0; i < NL; i++) { c += (int64_t)a[i] - b[i]; r[i] = (uint32_t)c; c = c < 0 ? -1 : 0; }
}
/* m *= k; returns 1 on overflow out of NL limbs */
static int w_mul_small(uint32_t *m, uint32_t k)
{
    uint64_t c = 0;
    int i;
    for (i = 0; i < NL; i++) { c += (uint64_t)m[i] * k; m[i] = (uint32_t)c; c >>= 32; }
    return c != 0;
}
/* m /= k; returns the remainder */
static uint32_t w_div_small(uint32_t *m, uint32_t k)
{
    uint64_t r = 0;
    int i;
    for (i = NL - 1; i >= 0; i--) { r = (r << 32) | m[i]; m[i] = (uint32_t)(r / k); r %= k; }
    return (uint32_t)r;
}
static void w_mul(uint32_t *r, const uint32_t *a, const uint32_t *b)     /* 96 x 96 bits */
{
    int i, j;
    memset(r, 0, sizeof(uint32_t) * NL);
    for (i = 0; i < 3; i++) {
        uint64_t c = 0;
        for (j = 0; j < 3 && i + j < NL; j++) {
            c += (uint64_t)a[i] * b[j] + r[i + j];
            r[i + j] = (uint32_t)c;
            c >>= 32;
        }
        if (i + 3 < NL) r[i + 3] = (uint32_t)c;
    }
}
static void w_shl1(uint32_t *m)
{
    int i;
    for (i = NL - 1; i > 0; i--) m[i] = (m[i] << 1) | (m[i - 1] >> 31);
    m[0] <<= 1;
}
/* q = a / b, r = a % b (b != 0), bit by bit */
static void w_divmod(const uint32_t *a, const uint32_t *b, uint32_t *q, uint32_t *r)
{
    int i;
    memset(q, 0, sizeof(uint32_t) * NL);
    memset(r, 0, sizeof(uint32_t) * NL);
    for (i = NL * 32 - 1; i >= 0; i--) {
        w_shl1(r);
        r[0] |= (a[i / 32] >> (i % 32)) & 1;
        if (w_cmp(r, b) >= 0) { w_sub(r, r, b); q[i / 32] |= 1u << (i % 32); }
    }
}

/* divide by 10^n with banker's rounding (n >= 1) */
static void w_round_div10(uint32_t *m, int n)
{
    uint32_t rem = 0, sticky = 0;
    int i;
    for (i = 0; i < n; i++) {
        if (rem) sticky = 1;
        rem = w_div_small(m, 10);
    }
    /* rem: the last digit removed; sticky: anything below it */
    if (rem > 5 || (rem == 5 && (sticky || (m[0] & 1)))) {
        uint32_t one[NL] = {1};
        w_add(m, m, one);
    }
}

/* make w fit: scale <= 28 and 96 bits, dropping digits with one banker's rounding over all
   of them; error 6 if it does not fit at scale 0 */
static void w_normalize(wide *w)
{
    for (;;) {
        uint32_t t[NL];
        int n = 0;
        memcpy(t, w->m, sizeof t);
        while ((w->scale - n > 28 || !w_fits96(t)) && w->scale - n > 0) { w_div_small(t, 10); n++; }
        if (n == 0) break;
        w_round_div10(w->m, n);
        w->scale -= n;
        if (w_fits96(w->m) && w->scale <= 28) break;      /* rounding up can carry over: again */
    }
    if (!w_fits96(w->m)) bb_overflow();
    if (w_zero(w->m)) w->neg = 0;
}

static void w_from_value(wide *w, const bb_value *v)
{
    memset(w, 0, sizeof *w);
    w->scale = v->flags & 0xff;
    w->neg = (v->flags & DEC_SIGN) != 0;
    w->m[0] = (uint32_t)(uint64_t)v->u.c;
    w->m[1] = (uint32_t)((uint64_t)v->u.c >> 32);
    w->m[2] = (uint32_t)v->aux;
}

static bb_value w_to_value(wide *w)
{
    bb_value v = bb_v_make(BB_DECIMAL);
    w_normalize(w);
    v.flags = (uint16_t)(w->scale | (w->neg ? DEC_SIGN : 0));
    v.aux = (int32_t)w->m[2];
    v.u.c = (bb_cur)(((uint64_t)w->m[1] << 32) | w->m[0]);
    return v;
}

/* bring both to the same scale (the larger), in wide precision */
static void w_align(wide *a, wide *b)
{
    while (a->scale < b->scale) { w_mul_small(a->m, 10); a->scale++; }
    while (b->scale < a->scale) { w_mul_small(b->m, 10); b->scale++; }
}

/* ---- conversions ---- */

static void w_from_i64(wide *w, int64_t x, int scale)
{
    uint64_t u = x < 0 ? (uint64_t)0 - (uint64_t)x : (uint64_t)x;
    memset(w, 0, sizeof *w);
    w->neg = x < 0;
    w->m[0] = (uint32_t)u;
    w->m[1] = (uint32_t)(u >> 32);
    w->scale = scale;
}

/* text: [+-]digits[.digits][E[+-]n]; returns 0 if not a number */
static int w_from_text(wide *w, const char *s)
{
    int any = 0, exp = 0, dot = 0, digits = 0, dropped = 0;
    memset(w, 0, sizeof *w);
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '-' || *s == '+') { w->neg = *s == '-'; s++; }
    for (; *s; s++) {
        if (*s == '.' && !dot) { dot = 1; continue; }
        if (*s < '0' || *s > '9') break;
        any = 1;
        if (digits == 0 && *s == '0') { if (dot) w->scale++; continue; }
        if (digits < 29) {
            uint32_t d[NL] = {0};
            d[0] = (uint32_t)(*s - '0');
            w_mul_small(w->m, 10);
            w_add(w->m, w->m, d);
            digits++;
            if (dot) w->scale++;
        } else {
            /* beyond 29 significant digits: round on the first dropped one */
            if (!dot) exp++;
            if (!dropped) {
                dropped = 1;
                if (*s >= '5') { uint32_t one[NL] = {1}; w_add(w->m, w->m, one); }
            }
        }
    }
    if (!any) return 0;
    if (*s == 'e' || *s == 'E') {
        int sg = 1, e = 0;
        s++;
        if (*s == '-' || *s == '+') { sg = *s == '-' ? -1 : 1; s++; }
        while (*s >= '0' && *s <= '9') e = e * 10 + (*s++ - '0');
        exp += sg * e;
    }
    while (*s == ' ' || *s == '\t') s++;
    if (*s) return 0;
    w->scale -= exp;
    while (w->scale < 0) { if (w_mul_small(w->m, 10)) bb_overflow(); w->scale++; }
    return 1;
}

static void w_from(wide *w, const bb_value *v)
{
    bb_value t;
    char buf[64];
    v = bb_v_deref(v, &t);
    switch (v->type) {
    case BB_DECIMAL: w_from_value(w, v); return;
    case BB_EMPTY: w_from_i64(w, 0, 0); return;
    case BB_BYTE: w_from_i64(w, v->u.by, 0); return;
    case BB_INTEGER: case BB_BOOLEAN: w_from_i64(w, v->u.i, 0); return;
    case BB_LONG: w_from_i64(w, v->u.l, 0); return;
    case BB_CURRENCY: w_from_i64(w, v->u.c, 4); return;
    case BB_SINGLE:
        /* VB: 7 significant digits from a Single, 15 from a Double */
        if (v->u.f - v->u.f != 0) bb_overflow();
        snprintf(buf, sizeof buf, "%.7g", (double)v->u.f);
        if (!w_from_text(w, buf)) bb_raise(13, NULL);
        return;
    case BB_DOUBLE: case BB_DATE:
        if (v->u.d - v->u.d != 0) bb_overflow();
        snprintf(buf, sizeof buf, "%.15g", v->u.d);
        if (!w_from_text(w, buf)) bb_raise(13, NULL);
        return;
    case BB_STRING:
        if (!w_from_text(w, bb_str_ptr(v->u.s))) bb_raise(13, NULL);
        return;
    case BB_NULL: bb_raise(94, NULL);
    default: bb_raise(13, NULL);
    }
}

bb_value bb_cdec(const bb_value *v)
{
    wide w;
    bb_value t;
    if (bb_v_deref(v, &t)->type == BB_DECIMAL) return *bb_v_deref(v, &t);
    w_from(&w, v);
    return w_to_value(&w);
}

/* digits with the decimal point, trailing fraction zeros removed */
static int w_text(const bb_value *v, char *out)
{
    wide w;
    char dig[40];
    int n = 0, i, p = 0, intd;
    w_from_value(&w, v);
    do { dig[n++] = (char)('0' + w_div_small(w.m, 10)); } while (!w_zero(w.m));
    while (n <= w.scale) dig[n++] = '0';
    /* dig is reversed; strip trailing fraction zeros */
    i = 0;
    while (i < w.scale && dig[i] == '0') i++;
    if (w.neg) out[p++] = '-';
    intd = n - w.scale;
    {
        int k;
        for (k = n - 1; k >= n - intd; k--) out[p++] = dig[k];
        if (i < w.scale) {
            out[p++] = '.';
            for (k = w.scale - 1; k >= i; k--) out[p++] = dig[k];
        }
    }
    out[p] = 0;
    return p;
}

bb_str *bb_dec_to_str(const bb_value *v)
{
    char buf[48];
    w_text(v, buf);
    return bb_str_from_c(buf);
}

double bb_dec_to_double(const bb_value *v)
{
    char buf[48];
    w_text(v, buf);
    return strtod(buf, NULL);
}

/* ---- arithmetic ---- */

static int w_signed_cmp(wide *a, wide *b)
{
    int c;
    if (w_zero(a->m) && w_zero(b->m)) return 0;
    if (a->neg != b->neg) return a->neg ? -1 : 1;
    w_align(a, b);
    c = w_cmp(a->m, b->m);
    return a->neg ? -c : c;
}

int bb_dec_compare(const bb_value *a, const bb_value *b)
{
    wide x, y;
    w_from(&x, a);
    w_from(&y, b);
    return w_signed_cmp(&x, &y);
}

static bb_value w_addsub(wide *x, wide *y, int sub)
{
    wide r;
    if (sub) y->neg = !y->neg;
    w_align(x, y);
    memset(&r, 0, sizeof r);
    r.scale = x->scale;
    if (x->neg == y->neg) { w_add(r.m, x->m, y->m); r.neg = x->neg; }
    else if (w_cmp(x->m, y->m) >= 0) { w_sub(r.m, x->m, y->m); r.neg = x->neg; }
    else { w_sub(r.m, y->m, x->m); r.neg = y->neg; }
    return w_to_value(&r);
}

bb_value bb_dec_arith(int op, const bb_value *a, const bb_value *b)
{
    wide x, y, r;
    w_from(&x, a);
    w_from(&y, b);
    switch (op) {
    case 0: return w_addsub(&x, &y, 0);
    case 1: return w_addsub(&x, &y, 1);
    case 2:
        memset(&r, 0, sizeof r);
        w_mul(r.m, x.m, y.m);
        r.scale = x.scale + y.scale;
        r.neg = x.neg != y.neg;
        return w_to_value(&r);
    default: {
        /* division: as many digits as fit (scale <= 28), banker's rounding */
        uint32_t q[NL], rem[NL], b10[NL];
        if (w_zero(y.m)) {
            if (w_zero(x.m)) bb_overflow();
            bb_raise(11, NULL);
        }
        memset(&r, 0, sizeof r);
        r.neg = x.neg != y.neg;
        w_divmod(x.m, y.m, q, rem);
        r.scale = x.scale - y.scale;
        memcpy(r.m, q, sizeof q);
        while (!w_zero(rem) && r.scale < 28) {
            uint32_t t[NL], d[NL], q2[NL];
            memcpy(t, r.m, sizeof t);
            if (w_mul_small(t, 10) || !w_fits96(t)) break;
            w_mul_small(rem, 10);
            w_divmod(rem, y.m, q2, d);
            w_add(t, t, q2);
            if (!w_fits96(t)) break;
            memcpy(r.m, t, sizeof t);
            memcpy(rem, d, sizeof d);
            r.scale++;
        }
        /* round on the remainder: 2*rem vs divisor */
        memcpy(b10, rem, sizeof b10);
        w_shl1(b10);
        {
            int c = w_cmp(b10, y.m);
            if (c > 0 || (c == 0 && (r.m[0] & 1))) { uint32_t one[NL] = {1}; w_add(r.m, r.m, one); }
        }
        while (r.scale < 0) { if (w_mul_small(r.m, 10)) bb_overflow(); r.scale++; }
        return w_to_value(&r);
    }
    }
}

bb_value bb_dec_neg(const bb_value *a)
{
    bb_value v = *a;
    if (v.aux || v.u.c) v.flags ^= DEC_SIGN;
    return v;
}

bb_value bb_dec_abs(const bb_value *a)
{
    bb_value v = *a;
    v.flags &= (uint16_t)~DEC_SIGN;
    return v;
}

/* Fix (toward zero) and Int (toward -infinity) */
bb_value bb_dec_trunc(const bb_value *a, int floor_)
{
    wide w;
    uint32_t dropped = 0;
    w_from_value(&w, a);
    while (w.scale > 0) { if (w_div_small(w.m, 10)) dropped = 1; w.scale--; }
    if (floor_ && w.neg && dropped) { uint32_t one[NL] = {1}; w_add(w.m, w.m, one); }
    return w_to_value(&w);
}
