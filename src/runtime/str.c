/* str.c - strings and the string built-ins */
#include "boing.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

bb_str *bb_str_alloc(int32_t len)
{
    bb_str *s;
    if (len < 0) bb_raise(5, NULL);
    if (len == 0) return NULL;
    s = (bb_str *)bb_small_alloc(sizeof(bb_str) + (size_t)len);
    if (!s) bb_raise(14, NULL);
    s->ref = 1;
    s->len = len;
    s->data[len] = 0;
    return s;
}

bb_str *bb_str_new(const char *p, int32_t len)
{
    bb_str *s = bb_str_alloc(len);
    if (s) { if (p) memcpy(s->data, p, (size_t)len); else memset(s->data, 0, (size_t)len); }
    return s;
}

bb_str *bb_str_from_c(const char *c) { return c ? bb_str_new(c, (int32_t)strlen(c)) : NULL; }

bb_str *bb_str_lit(const char *p, int32_t len)
{
    bb_str *s = bb_str_new(p, len);
    if (s) s->ref = -1;
    return s;
}

void bb_str_free_(bb_str *s) { bb_small_free(s); }
void bb_raise5_(void) { bb_raise(5, NULL); }

/* one-character strings, immortal and shared: Chr$, and Mid$ / Left$ / Right$ of one character */
static struct { int32_t ref, len; char data[4]; } chr1[256];
bb_str *bb_str_char(int c)
{
    c &= 255;
    if (!chr1[c].len) { chr1[c].ref = -1; chr1[c].len = 1; chr1[c].data[0] = (char)c; chr1[c].data[1] = 0; }
    return (bb_str *)(void *)&chr1[c];
}

bb_str *bb_str_concat(bb_str *a, bb_str *b)
{
    int32_t la = bb_str_len(a), lb = bb_str_len(b);
    bb_str *s;
    if (!lb) return bb_str_retain(a);
    if (!la) return bb_str_retain(b);
    s = bb_str_alloc(la + lb);
    memcpy(s->data, a->data, (size_t)la);
    memcpy(s->data + la, b->data, (size_t)lb);
    return s;
}

/* Latin-1 aware case mapping */
static int lc(int c)
{
    c &= 0xff;
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
    return c;
}
static int uc(int c)
{
    c &= 0xff;
    if (c >= 'a' && c <= 'z') return c - 32;
    if (c >= 0xE0 && c <= 0xFE && c != 0xF7) return c - 32;
    return c;
}

int bb_str_cmp(const bb_str *a, const bb_str *b, int text)
{
    int32_t la = bb_str_len(a), lb = bb_str_len(b), n = la < lb ? la : lb, i;
    const unsigned char *pa = (const unsigned char *)bb_str_ptr(a), *pb = (const unsigned char *)bb_str_ptr(b);
    for (i = 0; i < n; i++) {
        int ca = pa[i], cb = pb[i];
        if (text) { ca = lc(ca); cb = lc(cb); }
        if (ca != cb) return ca < cb ? -1 : 1;
    }
    return la == lb ? 0 : (la < lb ? -1 : 1);
}

int bb_str_eq(const bb_str *a, const bb_str *b)
{
    int32_t la = bb_str_len(a);
    if (la != bb_str_len(b)) return 0;
    return la == 0 || a == b || memcmp(a->data, b->data, (size_t)la) == 0;
}

bb_str *bb_str_fixlen(bb_str *s, int32_t n)
{
    int32_t l = bb_str_len(s);
    bb_str *r;
    if (l == n) return bb_str_retain(s);
    r = bb_str_alloc(n);
    if (!r) return NULL;
    memcpy(r->data, bb_str_ptr(s), (size_t)(l < n ? l : n));
    if (l < n) memset(r->data + l, ' ', (size_t)(n - l));
    return r;
}

/* ---- built-ins ---- */

bb_long bb_len(const bb_str *s) { return bb_str_len(s); }

bb_str *bb_left(bb_str *s, bb_long n)
{
    if (n < 0) bb_raise(5, NULL);
    if (n >= bb_str_len(s)) return bb_str_retain(s);
    if (n == 1) return bb_str_char((unsigned char)s->data[0]);
    return bb_str_new(bb_str_ptr(s), n);
}

bb_str *bb_right(bb_str *s, bb_long n)
{
    int32_t l = bb_str_len(s);
    if (n < 0) bb_raise(5, NULL);
    if (n >= l) return bb_str_retain(s);
    if (n == 1) return bb_str_char((unsigned char)s->data[l - 1]);
    return bb_str_new(s->data + l - n, n);
}

bb_str *bb_mid(bb_str *s, bb_long start, bb_long len)
{
    int32_t l = bb_str_len(s);
    if (start < 1) bb_raise(5, NULL);
    if (start > l) return NULL;
    if (len < 0 || len > l - start + 1) len = l - start + 1;
    if (start == 1 && len == l) return bb_str_retain(s);
    if (len == 1) return bb_str_char((unsigned char)s->data[start - 1]);
    return bb_str_new(s->data + start - 1, len);
}

void bb_mid_assign(bb_str **dst, bb_long start, bb_long len, bb_str *repl)
{
    int32_t l = bb_str_len(*dst), rl = bb_str_len(repl);
    bb_str *n;
    if (start < 1 || start > l) bb_raise(5, NULL);
    if (len < 0 || len > rl) len = rl;
    if (len > l - start + 1) len = l - start + 1;
    n = bb_str_new((*dst)->data, l);
    memcpy(n->data + start - 1, bb_str_ptr(repl), (size_t)len);
    bb_str_set(dst, n);
}

static int match_at(const char *h, const char *f, int32_t n, int text)
{
    int32_t i;
    if (!text) return memcmp(h, f, (size_t)n) == 0;
    for (i = 0; i < n; i++) if (lc(h[i]) != lc(f[i])) return 0;
    return 1;
}

bb_long bb_instr(bb_long start, bb_str *s, bb_str *find, int text)
{
    int32_t l = bb_str_len(s), fl = bb_str_len(find), i;
    if (start < 1) bb_raise(5, NULL);
    if (start > l) return 0;
    if (fl == 0) return start;
    for (i = start - 1; i + fl <= l; i++)
        if (match_at(s->data + i, find->data, fl, text)) return i + 1;
    return 0;
}

bb_long bb_instrrev(bb_str *s, bb_str *find, bb_long start, int text)
{
    int32_t l = bb_str_len(s), fl = bb_str_len(find), i;
    if (start == 0 || start < -1) bb_raise(5, NULL);
    if (start == -1) start = l;
    if (start > l) return 0;
    if (fl == 0) return start;
    for (i = start - fl; i >= 0; i--)
        if (match_at(s->data + i, find->data, fl, text)) return i + 1;
    return 0;
}

static bb_str *map_case(bb_str *s, int (*f)(int))
{
    int32_t l = bb_str_len(s), i;
    bb_str *r;
    if (!l) return NULL;
    r = bb_str_alloc(l);
    for (i = 0; i < l; i++) r->data[i] = (char)f(s->data[i]);
    return r;
}

bb_str *bb_lcase(bb_str *s) { return map_case(s, lc); }
bb_str *bb_ucase(bb_str *s) { return map_case(s, uc); }

static bb_str *trim(bb_str *s, int left, int right)
{
    int32_t a = 0, b = bb_str_len(s);
    while (left && a < b && s->data[a] == ' ') a++;
    while (right && b > a && s->data[b - 1] == ' ') b--;
    if (a == 0 && b == bb_str_len(s)) return bb_str_retain(s);
    return bb_str_new(s->data + a, b - a);
}

bb_str *bb_trim(bb_str *s) { return trim(s, 1, 1); }
bb_str *bb_ltrim(bb_str *s) { return trim(s, 1, 0); }
bb_str *bb_rtrim(bb_str *s) { return trim(s, 0, 1); }

bb_str *bb_space(bb_long n)
{
    bb_str *r;
    if (n < 0) bb_raise(5, NULL);
    r = bb_str_alloc(n);
    if (r) memset(r->data, ' ', (size_t)n);
    return r;
}

bb_str *bb_string_n(bb_long n, const bb_value *ch)
{
    bb_value tmp;
    const bb_value *v = bb_v_deref(ch, &tmp);
    int c;
    bb_str *r;
    if (n < 0) bb_raise(5, NULL);
    if (v->type == BB_NULL) bb_raise(94, NULL);
    if (v->type == BB_STRING) {
        if (!bb_str_len(v->u.s)) bb_raise(5, NULL);
        c = (unsigned char)v->u.s->data[0];
    } else {
        c = (int)(bb_v_to_long(v) & 0xff);
    }
    r = bb_str_alloc(n);
    if (r) memset(r->data, c, (size_t)n);
    return r;
}

bb_str *bb_replace(bb_str *s, bb_str *find, bb_str *with, bb_long start, bb_long count, int text)
{
    int32_t l = bb_str_len(s), fl = bb_str_len(find), wl = bb_str_len(with), i, n = 0, cap;
    char *buf;
    bb_str *r;
    if (start < 1) bb_raise(5, NULL);
    if (start > l) return NULL;
    if (fl == 0 || count == 0) return bb_str_new(s->data + start - 1, l - start + 1);
    cap = l + 16;
    buf = (char *)malloc((size_t)cap);
    for (i = start - 1; i < l;) {
        if ((count < 0 || count > 0) && i + fl <= l && match_at(s->data + i, find->data, fl, text)) {
            while (n + wl + 1 > cap) { cap *= 2; buf = (char *)realloc(buf, (size_t)cap); }
            if (wl) memcpy(buf + n, with->data, (size_t)wl);
            n += wl; i += fl;
            if (count > 0) count--;
        } else {
            if (n + 2 > cap) { cap *= 2; buf = (char *)realloc(buf, (size_t)cap); }
            buf[n++] = s->data[i++];
        }
    }
    r = bb_str_new(buf, n);
    free(buf);
    return r;
}

bb_array *bb_split(bb_str *s, bb_str *delim, bb_long limit, int text)
{
    int32_t l = bb_str_len(s), dl = bb_str_len(delim), i, from = 0, n = 0;
    bb_array *a;
    int32_t lb = 0, ub;
    if (l == 0) { ub = -1; return bb_arr_new(BB_STRING, NULL, 1, &lb, &ub); }
    /* count */
    if (dl == 0) n = 1;
    else {
        n = 1;
        for (i = 0; i + dl <= l;) {
            if ((limit < 0 || n < limit) && match_at(s->data + i, delim->data, dl, text)) { n++; i += dl; }
            else i++;
        }
    }
    ub = n - 1;
    a = bb_arr_new(BB_STRING, NULL, 1, &lb, &ub);
    if (dl == 0) { ((bb_str **)a->data)[0] = bb_str_retain(s); return a; }
    n = 0;
    for (i = 0; i + dl <= l;) {
        if (n < ub && match_at(s->data + i, delim->data, dl, text)) {
            ((bb_str **)a->data)[n++] = bb_str_new(s->data + from, i - from);
            i += dl; from = i;
        } else i++;
    }
    ((bb_str **)a->data)[n] = bb_str_new(s->data + from, l - from);
    return a;
}

bb_str *bb_join(const bb_array *a, bb_str *delim)
{
    int32_t i, total = 0, dl = bb_str_len(delim), pos = 0;
    bb_str **parts, *r;
    if (!a) bb_raise(13, NULL);
    if (a->ndims != 1) bb_raise(5, NULL);
    if (a->count == 0) return NULL;
    parts = (bb_str **)malloc(sizeof(bb_str *) * (size_t)a->count);
    for (i = 0; i < a->count; i++) {
        const char *p = (const char *)a->data + (size_t)i * a->esize;
        if (a->etype == BB_STRING) parts[i] = bb_str_retain(*(bb_str *const *)p);
        else if (a->etype == BB_VARIANT) parts[i] = bb_v_to_str((const bb_value *)p);
        else { free(parts); bb_raise(13, NULL); }
        total += bb_str_len(parts[i]) + (i ? dl : 0);
    }
    r = bb_str_alloc(total);
    for (i = 0; i < a->count; i++) {
        if (i && dl) { memcpy(r->data + pos, delim->data, (size_t)dl); pos += dl; }
        if (bb_str_len(parts[i])) { memcpy(r->data + pos, parts[i]->data, (size_t)parts[i]->len); pos += parts[i]->len; }
        bb_str_release(parts[i]);
    }
    free(parts);
    return r;
}

bb_long bb_strcomp(bb_str *a, bb_str *b, bb_long mode)
{
    int c = bb_str_cmp(a, b, mode == 1);
    return c < 0 ? -1 : c > 0 ? 1 : 0;
}

bb_str *bb_strreverse(bb_str *s)
{
    int32_t l = bb_str_len(s), i;
    bb_str *r;
    if (!l) return NULL;
    r = bb_str_alloc(l);
    for (i = 0; i < l; i++) r->data[i] = s->data[l - 1 - i];
    return r;
}

bb_str *bb_chr(bb_long code)
{
    if (code < 0 || code > 255) bb_raise(5, NULL);
    return bb_str_char((int)code);
}

bb_long bb_asc(bb_str *s)
{
    if (!bb_str_len(s)) bb_raise(5, NULL);
    return (unsigned char)s->data[0];
}

bb_str *bb_lset(bb_str *dst, bb_str *src) { return bb_str_fixlen(src, bb_str_len(dst)); }

bb_str *bb_rset(bb_str *dst, bb_str *src)
{
    int32_t n = bb_str_len(dst), l = bb_str_len(src);
    bb_str *r;
    if (l >= n) return bb_str_new(bb_str_ptr(src), n);
    r = bb_str_alloc(n);
    memset(r->data, ' ', (size_t)(n - l));
    memcpy(r->data + n - l, bb_str_ptr(src), (size_t)l);
    return r;
}

/* ---- Like ---- */

static int like_match(const unsigned char *s, const unsigned char *se,
                      const unsigned char *p, const unsigned char *pe, int text)
{
    while (p < pe) {
        unsigned c = *p;
        if (c == '*') {
            p++;
            while (p < pe && *p == '*') p++;
            if (p == pe) return 1;
            for (; s <= se; s++)
                if (like_match(s, se, p, pe, text)) return 1;
            return 0;
        }
        if (s >= se) return 0;
        if (c == '?') { s++; p++; continue; }
        if (c == '#') { if (!isdigit(*s)) return 0; s++; p++; continue; }
        if (c == '[') {
            int neg = 0, ok = 0;
            unsigned sc = text ? (unsigned)lc(*s) : *s;
            p++;
            if (p < pe && *p == '!') { neg = 1; p++; }
            while (p < pe && *p != ']') {
                unsigned lo = *p++, hi = lo;
                if (p + 1 < pe && *p == '-' && p[1] != ']') { hi = p[1]; p += 2; }
                if (text) { lo = (unsigned)lc((int)lo); hi = (unsigned)lc((int)hi); }
                if (sc >= lo && sc <= hi) ok = 1;
            }
            if (p >= pe) bb_raise(93, NULL);
            p++;
            if (ok == neg) return 0;
            s++;
            continue;
        }
        if (text ? lc(c) != lc(*s) : c != *s) return 0;
        s++; p++;
    }
    return s == se;
}

bb_bool bb_like(bb_str *s, bb_str *pattern, int text)
{
    const unsigned char *sp = (const unsigned char *)bb_str_ptr(s);
    const unsigned char *pp = (const unsigned char *)bb_str_ptr(pattern);
    return like_match(sp, sp + bb_str_len(s), pp, pp + bb_str_len(pattern), text) ? BB_TRUE : BB_FALSE;
}

/* Filter(source, match [, include [, compare]]): the elements of a 1-D String or Variant array
   that contain match (include True) or don't; a String array, 0 To -1 when none */
bb_array *bb_filter(const bb_array *a, bb_str *match, bb_bool include, int text)
{
    int32_t i, n = 0, lb = 0, ub;
    bb_str **keep;
    bb_array *r;
    if (!a) bb_raise(13, NULL);
    if (a->ndims != 1) bb_raise(5, NULL);
    keep = (bb_str **)malloc(sizeof(bb_str *) * (size_t)(a->count + 1));
    for (i = 0; i < a->count; i++) {
        const char *p = (const char *)a->data + (size_t)i * a->esize;
        bb_str *s;
        int found;
        if (a->etype == BB_STRING) s = bb_str_retain(*(bb_str *const *)p);
        else if (a->etype == BB_VARIANT) s = bb_v_to_str((const bb_value *)p);
        else { int32_t k; for (k = 0; k < n; k++) bb_str_release(keep[k]); free(keep); bb_raise(13, NULL); }
        found = bb_instr(1, s, match, text) > 0;
        if ((found != 0) == (include != 0)) keep[n++] = s;
        else bb_str_release(s);
    }
    ub = n - 1;
    r = bb_arr_new(BB_STRING, NULL, 1, &lb, &ub);
    for (i = 0; i < n; i++) ((bb_str **)r->data)[i] = keep[i];
    free(keep);
    return r;
}
