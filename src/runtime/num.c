/* num.c - numeric conversion, formatting and parsing */
#include "boing.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

double bb_round_even(double d)
{
    double f = floor(d), r = d - f;
    if (r > 0.5) return f + 1;
    if (r < 0.5) return f;
    return fmod(f, 2.0) == 0 ? f : f + 1;
}

bb_int bb_cint(double d)
{
    double r;
    if (d != d) bb_overflow();
    r = bb_round_even(d);
    if (r < -32768.0 || r > 32767.0) bb_overflow();
    return (bb_int)r;
}

bb_long bb_clng(double d)
{
    double r;
    if (d != d) bb_overflow();
    r = bb_round_even(d);
    if (r < -2147483648.0 || r > 2147483647.0) bb_overflow();
    return (bb_long)r;
}

bb_byte bb_cbyte(double d)
{
    double r;
    if (d != d) bb_overflow();
    r = bb_round_even(d);
    if (r < 0 || r > 255.0) bb_overflow();
    return (bb_byte)r;
}

bb_single bb_csng(double d)
{
    if (d > 3.402823466e38 || d < -3.402823466e38) bb_overflow();
    return (bb_single)d;
}

bb_double bb_chk_double(bb_double d)
{
    if (isinf(d) || d != d) bb_overflow();
    return d;
}

#define CUR_MAX 922337203685477.5807
bb_cur bb_ccur(double d)
{
    double r = d * 10000.0;
    if (d != d || r >= 9.2233720368547758e18 || r <= -9.2233720368547758e18) bb_overflow();
    return (bb_cur)bb_round_even(r);
}

bb_cur bb_cur_from_long(bb_long l) { return (bb_cur)l * BB_CUR_SCALE; }
double bb_cur_to_double(bb_cur c) { return (double)c / 10000.0; }

bb_cur bb_cur_add(bb_cur a, bb_cur b)
{
    bb_cur r = (bb_cur)((uint64_t)a + (uint64_t)b);
    if ((a >= 0) == (b >= 0) && (r >= 0) != (a >= 0)) bb_overflow();
    return r;
}

bb_cur bb_cur_sub(bb_cur a, bb_cur b)
{
    bb_cur r = (bb_cur)((uint64_t)a - (uint64_t)b);
    if ((a >= 0) != (b >= 0) && (r >= 0) != (a >= 0)) bb_overflow();
    return r;
}

bb_cur bb_cur_mul(bb_cur a, bb_cur b)
{
    /* exact when the product fits in 63 bits, else via long double */
    int64_t lim = 3037000499LL;
    if (a > -lim && a < lim && b > -lim && b < lim) {
        int64_t p = a * b, q = p / 10000, rem = p % 10000;
        /* banker's rounding of the division */
        if (rem < 0) rem = -rem;
        if (rem > 5000 || (rem == 5000 && (q & 1))) q += (p < 0) ? -1 : 1;
        return q;
    }
    return bb_ccur(((double)a / 10000.0) * ((double)b / 10000.0));
}

bb_cur bb_cur_div(bb_cur a, bb_cur b)
{
    if (b == 0) bb_raise(11, NULL);
    return bb_ccur((double)a / (double)b);
}

double bb_fdiv(double a, double b)
{
    if (b == 0) {
        if (a == 0) bb_overflow();
        bb_raise(11, NULL);
    }
    return bb_chk_double(a / b);
}

double bb_pow(double a, double b)
{
    double r;
    if (a < 0 && b != floor(b)) bb_raise(5, NULL);
    if (a == 0 && b < 0) bb_raise(5, NULL);
    r = pow(a, b);
    return bb_chk_double(r);
}

bb_long bb_idiv_l(bb_long a, bb_long b)
{
    if (b == 0) bb_raise(11, NULL);
    if (a == INT32_MIN && b == -1) bb_overflow();
    return a / b;
}

bb_long bb_mod_l(bb_long a, bb_long b)
{
    if (b == 0) bb_raise(11, NULL);
    if (b == -1) return 0;
    return a % b;
}

bb_int bb_idiv_i(bb_int a, bb_int b)
{
    if (b == 0) bb_raise(11, NULL);
    if (a == -32768 && b == -1) bb_overflow();
    return (bb_int)(a / b);
}

bb_int bb_mod_i(bb_int a, bb_int b)
{
    if (b == 0) bb_raise(11, NULL);
    if (b == -1) return 0;
    return (bb_int)(a % b);
}

/* ---- formatting ---- */

bb_str *bb_str_from_long(bb_long l)
{
    char buf[16];
    snprintf(buf, sizeof buf, "%ld", (long)l);
    return bb_str_from_c(buf);
}

/* %G output tidied to VB's style: 1E+20, 1.5E-07, no "-0" */
static void fmt_g(char *buf, size_t n, double d, int digits)
{
    char *e;
    if (d == 0) { strcpy(buf, "0"); return; }
    snprintf(buf, n, "%.*G", digits, d);
    e = strchr(buf, 'E');
    if (e) {
        /* exponent at least 2 digits: %G already does E+20 / E-07 */
        char *m = e - 1;
        (void)m;
    }
}

bb_str *bb_str_from_double(bb_double d)
{
    char buf[48];
    fmt_g(buf, sizeof buf, d, 15);
    return bb_str_from_c(buf);
}

bb_str *bb_str_from_single(bb_single f)
{
    char buf[48];
    fmt_g(buf, sizeof buf, (double)f, 7);
    return bb_str_from_c(buf);
}

bb_str *bb_str_from_cur(bb_cur c)
{
    char buf[48];
    uint64_t u = c < 0 ? (uint64_t)(-(c + 1)) + 1 : (uint64_t)c;
    uint64_t ip = u / 10000, fp = u % 10000;
    int n;
    n = snprintf(buf, sizeof buf, "%s%llu", c < 0 ? "-" : "", (unsigned long long)ip);
    if (fp) {
        char f[8];
        int k;
        snprintf(f, sizeof f, "%04u", (unsigned)fp);
        for (k = 3; k > 0 && f[k] == '0'; k--) f[k] = 0;
        snprintf(buf + n, sizeof buf - (size_t)n, ".%s", f);
    }
    return bb_str_from_c(buf);
}

bb_str *bb_str_from_bool(bb_bool b) { return bb_str_from_c(b ? "True" : "False"); }

/* Parse a whole string as a number (CDbl / IsNumeric rules). */
int bb_parse_number(const char *p, int32_t len, double *out)
{
    const char *e = p + len;
    char buf[128];
    int n = 0, digits = 0, neg = 0;
    while (p < e && isspace((unsigned char)*p)) p++;
    while (e > p && isspace((unsigned char)e[-1])) e--;
    if (p >= e) return 0;
    if (*p == '+' || *p == '-') { neg = (*p == '-'); p++; }
    if (p + 1 < e && *p == '&' && (p[1] == 'H' || p[1] == 'h' || p[1] == 'O' || p[1] == 'o')) {
        int base = (p[1] == 'H' || p[1] == 'h') ? 16 : 8;
        unsigned long v = 0;
        p += 2;
        if (p >= e) return 0;
        for (; p < e; p++) {
            int c = toupper((unsigned char)*p), dv;
            if (c >= '0' && c <= '9') dv = c - '0';
            else if (base == 16 && c >= 'A' && c <= 'F') dv = c - 'A' + 10;
            else return 0;
            if (dv >= base) return 0;
            v = v * (unsigned long)base + (unsigned long)dv;
        }
        /* &H values are 16- or 32-bit signed like VB */
        if (v <= 0xffffUL) *out = (double)(int16_t)(uint16_t)v;
        else *out = (double)(int32_t)(uint32_t)v;
        if (neg) *out = -*out;
        return 1;
    }
    if (neg) buf[n++] = '-';
    while (p < e && n < 120) {
        char c = *p;
        if (isdigit((unsigned char)c)) { buf[n++] = c; digits++; p++; }
        else if (c == ',' && digits) p++;   /* thousands separator */
        else break;
    }
    if (p < e && *p == '.') {
        buf[n++] = *p++;
        while (p < e && isdigit((unsigned char)*p) && n < 120) { buf[n++] = *p++; digits++; }
    }
    if (!digits) return 0;
    if (p < e && (*p == 'e' || *p == 'E' || *p == 'd' || *p == 'D')) {
        int ed = 0;
        buf[n++] = 'e'; p++;
        if (p < e && (*p == '+' || *p == '-')) buf[n++] = *p++;
        while (p < e && isdigit((unsigned char)*p) && n < 126) { buf[n++] = *p++; ed++; }
        if (!ed) return 0;
    }
    if (p != e) return 0;
    buf[n] = 0;
    *out = strtod(buf, NULL);
    return 1;
}

double bb_str_to_double(const bb_str *s)
{
    double d;
    if (!bb_parse_number(bb_str_ptr(s), bb_str_len(s), &d)) bb_raise(13, NULL);
    return d;
}

bb_bool bb_str_to_bool(const bb_str *s)
{
    double d;
    const char *p = bb_str_ptr(s);
    int32_t l = bb_str_len(s);
    while (l && *p == ' ') { p++; l--; }
    while (l && p[l - 1] == ' ') l--;
    if (l == 4 && (p[0] | 32) == 't' && (p[1] | 32) == 'r' && (p[2] | 32) == 'u' && (p[3] | 32) == 'e') return BB_TRUE;
    if (l == 5 && (p[0] | 32) == 'f' && (p[1] | 32) == 'a' && (p[2] | 32) == 'l' && (p[3] | 32) == 's' && (p[4] | 32) == 'e') return BB_FALSE;
    if (!bb_parse_number(p, l, &d)) bb_raise(13, NULL);
    return d != 0 ? BB_TRUE : BB_FALSE;
}

bb_double bb_val(bb_str *s)
{
    const char *p = bb_str_ptr(s), *e = p + bb_str_len(s);
    char buf[128];
    int n = 0, seen_dot = 0, seen_e = 0, digits = 0;
    while (p < e && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) p++;
    if (p + 1 < e && *p == '&') {
        int base = 0;
        unsigned long v = 0;
        if (p[1] == 'H' || p[1] == 'h') base = 16;
        else if (p[1] == 'O' || p[1] == 'o') base = 8;
        if (base) {
            for (p += 2; p < e; p++) {
                int c = toupper((unsigned char)*p), dv;
                if (c >= '0' && c <= '9') dv = c - '0';
                else if (base == 16 && c >= 'A' && c <= 'F') dv = c - 'A' + 10;
                else break;
                if (dv >= base) break;
                v = v * (unsigned long)base + (unsigned long)dv;
            }
            if (v <= 0xffffUL) return (double)(int16_t)(uint16_t)v;
            return (double)(int32_t)(uint32_t)v;
        }
    }
    if (p < e && (*p == '-' || *p == '+')) buf[n++] = *p++;
    for (; p < e && n < 120; p++) {
        char c = *p;
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        if (isdigit((unsigned char)c)) { buf[n++] = c; digits++; }
        else if (c == '.' && !seen_dot && !seen_e) { buf[n++] = c; seen_dot = 1; }
        else if ((c == 'e' || c == 'E' || c == 'd' || c == 'D') && !seen_e && digits) {
            /* only if followed by a digit or sign+digit */
            const char *q = p + 1;
            while (q < e && *q == ' ') q++;
            if (q < e && (*q == '+' || *q == '-')) q++;
            while (q < e && *q == ' ') q++;
            if (q < e && isdigit((unsigned char)*q)) { buf[n++] = 'e'; seen_e = 1; }
            else break;
        }
        else if ((c == '+' || c == '-') && seen_e && (buf[n - 1] == 'e')) buf[n++] = c;
        else break;
    }
    buf[n] = 0;
    if (!digits) return 0;
    return strtod(buf, NULL);
}
