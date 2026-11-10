/* encode.c - text encodings (docs/encoding.md):
 *   Utf8Encode(s)            Latin-1 (the Amiga's character set) -> UTF-8 bytes
 *   Utf8Decode(s [, repl])   UTF-8 -> Latin-1; characters beyond Latin-1 become repl ("?"),
 *                            invalid sequences too
 *   Base64Encode(s [, lineLen]) / Base64Decode(s)
 *   UrlEncode(s) / UrlDecode(s)      percent-encoding (RFC 3986); UrlDecode also reads + as space
 *   HexEncode(s) / HexDecode(s)
 * Strings are byte strings, so these work on binary data too. Bad input to the decoders raises
 * error 31301 with what was wrong. */
#include "boing.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { E_DECODE = 31301 };

typedef struct {
    char *p;
    size_t n, cap;
} buf;

static void put(buf *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        size_t c = b->cap ? b->cap : 64;
        while (c < b->n + n + 1) c *= 2;
        b->p = realloc(b->p, c);
        b->cap = c;
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
}

static void putc_(buf *b, char c)
{
    if (b->n + 2 > b->cap) put(b, &c, 1);
    else b->p[b->n++] = c;
}

static bb_str *done(buf *b)
{
    bb_str *s = bb_str_new(b->p ? b->p : "", (int32_t)b->n);
    free(b->p);
    return s;
}

static void decode_fail(buf *b, const char *what, int32_t at)
{
    char m[160];
    free(b->p);
    snprintf(m, sizeof m, "%s at character %ld", what, (long)at + 1);
    bb_raise(E_DECODE, m);
}

bb_str *bb_utf8encode(bb_str *s)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    for (int32_t i = 0; i < n; i++) {
        if (p[i] < 0x80) putc_(&b, (char)p[i]);
        else {
            putc_(&b, (char)(0xC0 | (p[i] >> 6)));
            putc_(&b, (char)(0x80 | (p[i] & 0x3F)));
        }
    }
    return done(&b);
}

bb_str *bb_utf8decode(bb_str *s, bb_str *repl)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    const char *r = bb_str_ptr(repl);
    int32_t rl = bb_str_len(repl);
    buf b = { 0 };
    for (int32_t i = 0; i < n;) {
        unsigned char c = p[i];
        unsigned long cp;
        int len;
        if (c < 0x80) {
            putc_(&b, (char)c);
            i++;
            continue;
        }
        if (c >= 0xC2 && c <= 0xDF) { cp = c & 0x1F; len = 2; }
        else if (c >= 0xE0 && c <= 0xEF) { cp = c & 0x0F; len = 3; }
        else if (c >= 0xF0 && c <= 0xF4) { cp = c & 0x07; len = 4; }
        else { put(&b, r, rl); i++; continue; }        /* not a lead byte */
        int ok = i + len <= n;
        for (int k = 1; ok && k < len; k++) {
            if ((p[i + k] & 0xC0) != 0x80) ok = 0;
            else cp = (cp << 6) | (p[i + k] & 0x3F);
        }
        if (ok && ((len == 3 && cp < 0x800) || (len == 4 && (cp < 0x10000 || cp > 0x10FFFF)) ||
                   (cp >= 0xD800 && cp < 0xE000)))
            ok = 0;                                   /* overlong, out of range, surrogate */
        if (!ok) {
            put(&b, r, rl);
            i++;
            continue;
        }
        if (cp < 0x100) putc_(&b, (char)cp);
        else put(&b, r, rl);
        i += len;
    }
    return done(&b);
}

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

bb_str *bb_base64encode(bb_str *s, bb_long linelen)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    long col = 0;
    if (linelen < 0) bb_raise(5, NULL);
    linelen &= ~3L;                                   /* whole groups of 4 per line */
    for (int32_t i = 0; i < n; i += 3) {
        unsigned long v = (unsigned long)p[i] << 16;
        if (i + 1 < n) v |= (unsigned long)p[i + 1] << 8;
        if (i + 2 < n) v |= p[i + 2];
        char o[4] = { B64[(v >> 18) & 63], B64[(v >> 12) & 63], i + 1 < n ? B64[(v >> 6) & 63] : '=',
                      i + 2 < n ? B64[v & 63] : '=' };
        if (linelen && col >= linelen) {
            putc_(&b, '\r');
            putc_(&b, '\n');
            col = 0;
        }
        put(&b, o, 4);
        col += 4;
    }
    return done(&b);
}

bb_str *bb_base64decode(bb_str *s)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    unsigned long v = 0;
    int bits = 0, pad = 0;
    for (int32_t i = 0; i < n; i++) {
        unsigned char c = p[i];
        int d = 0;
        if (c == ' ' || c == '\r' || c == '\n' || c == '\t') continue;
        if (c == '=') { pad++; continue; }
        if (pad) decode_fail(&b, "Base64: data after the '=' padding", i);
        if (c >= 'A' && c <= 'Z') d = c - 'A';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 26;
        else if (c >= '0' && c <= '9') d = c - '0' + 52;
        else if (c == '+' || c == '-') d = 62;          /* '-' and '_': the URL-safe alphabet */
        else if (c == '/' || c == '_') d = 63;
        else decode_fail(&b, "Base64: a character that isn't Base64", i);
        v = (v << 6) | (unsigned long)d;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            putc_(&b, (char)((v >> bits) & 0xFF));
        }
    }
    if (bits >= 6) decode_fail(&b, "Base64: the data is cut short", n - 1);
    return done(&b);
}

static int unreserved(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' ||
           c == '.' || c == '~';
}

bb_str *bb_urlencode(bb_str *s)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    for (int32_t i = 0; i < n; i++) {
        if (unreserved(p[i])) putc_(&b, (char)p[i]);
        else {
            char o[4];
            snprintf(o, sizeof o, "%%%02X", p[i]);
            put(&b, o, 3);
        }
    }
    return done(&b);
}

static int hexval(unsigned char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bb_str *bb_urldecode(bb_str *s)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    for (int32_t i = 0; i < n; i++) {
        if (p[i] == '+') putc_(&b, ' ');
        else if (p[i] == '%') {
            int h = i + 2 < n ? hexval(p[i + 1]) : -1, l = i + 2 < n ? hexval(p[i + 2]) : -1;
            if (h < 0 || l < 0) decode_fail(&b, "URL: '%' isn't followed by two hex digits", i);
            putc_(&b, (char)(h * 16 + l));
            i += 2;
        } else
            putc_(&b, (char)p[i]);
    }
    return done(&b);
}

bb_str *bb_hexencode(bb_str *s)
{
    static const char H[] = "0123456789ABCDEF";
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    for (int32_t i = 0; i < n; i++) {
        putc_(&b, H[p[i] >> 4]);
        putc_(&b, H[p[i] & 15]);
    }
    return done(&b);
}

bb_str *bb_hexdecode(bb_str *s)
{
    const unsigned char *p = (const unsigned char *)bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    buf b = { 0 };
    int hi = -1;
    for (int32_t i = 0; i < n; i++) {
        if (p[i] == ' ' || p[i] == '\r' || p[i] == '\n' || p[i] == '\t' || p[i] == ':') continue;
        int v = hexval(p[i]);
        if (v < 0) decode_fail(&b, "hex: a character that isn't a hex digit", i);
        if (hi < 0) hi = v;
        else {
            putc_(&b, (char)(hi * 16 + v));
            hi = -1;
        }
    }
    if (hi >= 0) decode_fail(&b, "hex: an odd number of digits", n - 1);
    return done(&b);
}
