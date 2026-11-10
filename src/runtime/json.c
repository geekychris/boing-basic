/* json.c - JsonParse and JsonStringify (docs/json.md).
 *
 *   JsonParse(text) As Variant      objects -> Dictionary, arrays -> Variant arrays (0-based),
 *                                   strings -> String (UTF-8 bytes as in the text; \u escapes are
 *                                   written as UTF-8), integers that fit -> Long, other numbers
 *                                   -> Double, true/false -> Boolean, null -> Null
 *   JsonStringify(value [, indent]) Dictionary -> object, arrays and Collections -> arrays,
 *                                   numbers, strings, Boolean, Null/Empty -> null, Date -> ISO 8601
 *
 * Errors: 31201 "JSON: ... at line L, column C" (parse); 31202 (a value that can't be JSON:
 * other objects, multi-dimensional arrays, nesting deeper than 512 or a cycle). */
#include "boing.h"
#include "dict.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JSON_MAXDEPTH 512
enum { E_PARSE = 31201, E_VALUE = 31202 };

/* --- a growable byte buffer ---------------------------------------------------------------- */

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

static void putc_(buf *b, char c) { put(b, &c, 1); }
static void puts_(buf *b, const char *s) { put(b, s, strlen(s)); }

static void put_utf8(buf *b, unsigned long cp)
{
    char o[4];
    if (cp < 0x80) putc_(b, (char)cp);
    else if (cp < 0x800) {
        o[0] = (char)(0xC0 | (cp >> 6));
        o[1] = (char)(0x80 | (cp & 0x3F));
        put(b, o, 2);
    } else if (cp < 0x10000) {
        o[0] = (char)(0xE0 | (cp >> 12));
        o[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        o[2] = (char)(0x80 | (cp & 0x3F));
        put(b, o, 3);
    } else {
        o[0] = (char)(0xF0 | (cp >> 18));
        o[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        o[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        o[3] = (char)(0x80 | (cp & 0x3F));
        put(b, o, 4);
    }
}

/* --- parsing -------------------------------------------------------------------------------- */

/* Parsed values live on a stack until their container takes them, so an error (a long jump)
 * can release everything parsed so far. */
typedef struct {
    const char *s, *e, *p;
    int depth;
    bb_value *st;
    int32_t top, cap;
} parser;

static void push(parser *ps, bb_value v)
{
    if (ps->top == ps->cap) {
        ps->cap = ps->cap ? ps->cap * 2 : 64;
        ps->st = realloc(ps->st, ps->cap * sizeof *ps->st);
    }
    ps->st[ps->top++] = v;
}

static void fail(parser *ps, const char *what)
{
    int line = 1, col = 1;
    for (const char *q = ps->s; q < ps->p && q < ps->e; q++) {
        if (*q == '\n') {
            line++;
            col = 1;
        } else
            col++;
    }
    char m[200], near[24] = "the end of the text";
    if (ps->p < ps->e) {
        unsigned char c = (unsigned char)*ps->p;
        if (c >= 32 && c < 127) snprintf(near, sizeof near, "'%c'", c);
        else snprintf(near, sizeof near, "byte %d", c);
    }
    snprintf(m, sizeof m, "JSON: %s at line %d, column %d (found %s)", what, line, col, near);
    bb_raise(E_PARSE, m);
}

static void ws(parser *ps)
{
    while (ps->p < ps->e && (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r')) ps->p++;
}

static int hex4(parser *ps, unsigned long *out)
{
    unsigned long v = 0;
    for (int i = 0; i < 4; i++) {
        if (ps->p >= ps->e) return 0;
        char c = *ps->p++;
        v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0';
        else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
        else return 0;
    }
    *out = v;
    return 1;
}

static bb_str *parse_string(parser *ps)
{
    buf b = { 0 };
    ps->p++;                                        /* the opening quote */
    for (;;) {
        if (ps->p >= ps->e) {
            free(b.p);
            fail(ps, "unterminated string");
        }
        unsigned char c = (unsigned char)*ps->p;
        if (c == '"') {
            ps->p++;
            break;
        }
        if (c < 0x20) {
            free(b.p);
            fail(ps, "a control character in a string");
        }
        if (c != '\\') {
            const char *q = ps->p;                  /* copy a run of plain bytes */
            while (q < ps->e && *q != '"' && *q != '\\' && (unsigned char)*q >= 0x20) q++;
            put(&b, ps->p, q - ps->p);
            ps->p = q;
            continue;
        }
        ps->p++;
        if (ps->p >= ps->e) {
            free(b.p);
            fail(ps, "unterminated string");
        }
        char esc = *ps->p++;
        switch (esc) {
        case '"': putc_(&b, '"'); break;
        case '\\': putc_(&b, '\\'); break;
        case '/': putc_(&b, '/'); break;
        case 'b': putc_(&b, '\b'); break;
        case 'f': putc_(&b, '\f'); break;
        case 'n': putc_(&b, '\n'); break;
        case 'r': putc_(&b, '\r'); break;
        case 't': putc_(&b, '\t'); break;
        case 'u': {
            unsigned long cp, lo;
            if (!hex4(ps, &cp)) {
                free(b.p);
                fail(ps, "a bad \\u escape");
            }
            if (cp >= 0xD800 && cp < 0xDC00) {      /* a surrogate pair */
                if (ps->e - ps->p >= 6 && ps->p[0] == '\\' && ps->p[1] == 'u') {
                    ps->p += 2;
                    if (hex4(ps, &lo) && lo >= 0xDC00 && lo < 0xE000) cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    else cp = 0xFFFD;
                } else
                    cp = 0xFFFD;
            } else if (cp >= 0xDC00 && cp < 0xE000)
                cp = 0xFFFD;
            put_utf8(&b, cp);
            break;
        }
        default:
            ps->p--;
            free(b.p);
            fail(ps, "a bad escape in a string");
        }
    }
    bb_str *s = bb_str_new(b.p ? b.p : "", (int32_t)b.n);
    free(b.p);
    return s;
}

static bb_value parse_number(parser *ps)
{
    const char *st = ps->p;
    int integer = 1;
    if (ps->p < ps->e && *ps->p == '-') ps->p++;
    if (ps->p >= ps->e || !(*ps->p >= '0' && *ps->p <= '9')) fail(ps, "a bad number");
    if (*ps->p == '0') ps->p++;
    else
        while (ps->p < ps->e && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    if (ps->p < ps->e && *ps->p == '.') {
        integer = 0;
        ps->p++;
        if (ps->p >= ps->e || !(*ps->p >= '0' && *ps->p <= '9')) fail(ps, "a bad number");
        while (ps->p < ps->e && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    if (ps->p < ps->e && (*ps->p == 'e' || *ps->p == 'E')) {
        integer = 0;
        ps->p++;
        if (ps->p < ps->e && (*ps->p == '+' || *ps->p == '-')) ps->p++;
        if (ps->p >= ps->e || !(*ps->p >= '0' && *ps->p <= '9')) fail(ps, "a bad number");
        while (ps->p < ps->e && *ps->p >= '0' && *ps->p <= '9') ps->p++;
    }
    char tmp[64];
    size_t n = ps->p - st;
    if (n >= sizeof tmp) {
        char *big = malloc(n + 1);
        memcpy(big, st, n);
        big[n] = 0;
        double d = strtod(big, NULL);
        free(big);
        return bb_v_double(d);
    }
    memcpy(tmp, st, n);
    tmp[n] = 0;
    if (integer) {
        long long v = strtoll(tmp, NULL, 10);
        if (v >= -2147483647LL - 1 && v <= 2147483647LL && !(v == 0 && tmp[0] == '-')) return bb_v_long((bb_long)v);
    }
    return bb_v_double(strtod(tmp, NULL));
}

static int lit(parser *ps, const char *w)
{
    size_t n = strlen(w);
    if ((size_t)(ps->e - ps->p) >= n && !memcmp(ps->p, w, n)) {
        ps->p += n;
        return 1;
    }
    return 0;
}

/* parse one value and push it */
static void parse_value(parser *ps)
{
    ws(ps);
    if (ps->p >= ps->e) fail(ps, "a value is missing");
    char c = *ps->p;
    if (c == '{') {
        if (++ps->depth > JSON_MAXDEPTH) fail(ps, "nested too deeply");
        ps->p++;
        int32_t at = ps->top;
        push(ps, bb_v_obj(bb_dict_new()));
        ws(ps);
        if (ps->p < ps->e && *ps->p == '}') ps->p++;
        else
            for (;;) {
                ws(ps);
                if (ps->p >= ps->e || *ps->p != '"') fail(ps, "a key (a string) was expected");
                push(ps, bb_v_str(parse_string(ps)));
                ws(ps);
                if (ps->p >= ps->e || *ps->p != ':') fail(ps, "':' was expected");
                ps->p++;
                parse_value(ps);
                bb_dict_set(ps->st[at].u.o, &ps->st[ps->top - 2], &ps->st[ps->top - 1]);
                bb_v_release(&ps->st[--ps->top]);
                bb_v_release(&ps->st[--ps->top]);
                ws(ps);
                if (ps->p < ps->e && *ps->p == ',') {
                    ps->p++;
                    continue;
                }
                if (ps->p < ps->e && *ps->p == '}') {
                    ps->p++;
                    break;
                }
                fail(ps, "',' or '}' was expected");
            }
        ps->depth--;
        return;
    }
    if (c == '[') {
        if (++ps->depth > JSON_MAXDEPTH) fail(ps, "nested too deeply");
        ps->p++;
        int32_t base = ps->top;
        ws(ps);
        if (ps->p < ps->e && *ps->p == ']') ps->p++;
        else
            for (;;) {
                parse_value(ps);
                ws(ps);
                if (ps->p < ps->e && *ps->p == ',') {
                    ps->p++;
                    continue;
                }
                if (ps->p < ps->e && *ps->p == ']') {
                    ps->p++;
                    break;
                }
                fail(ps, "',' or ']' was expected");
            }
        int32_t n = ps->top - base;
        bb_array *a = bb_arr_new1(BB_VARIANT, 0, n - 1);
        for (int32_t i = 0; i < n; i++) {
            bb_value *dst = (bb_value *)bb_arr_elem1(a, i);
            *dst = ps->st[base + i];                /* moved */
        }
        ps->top = base;
        push(ps, bb_v_arr(a));
        ps->depth--;
        return;
    }
    if (c == '"') {
        push(ps, bb_v_str(parse_string(ps)));
        return;
    }
    if (c == '-' || (c >= '0' && c <= '9')) {
        push(ps, parse_number(ps));
        return;
    }
    if (lit(ps, "true")) push(ps, bb_v_bool(1));
    else if (lit(ps, "false")) push(ps, bb_v_bool(0));
    else if (lit(ps, "null")) push(ps, bb_v_null());
    else fail(ps, "a value was expected");
}

bb_value bb_jsonparse(bb_str *text)
{
    parser ps;
    memset(&ps, 0, sizeof ps);
    ps.s = ps.p = bb_str_ptr(text);
    ps.e = ps.s + bb_str_len(text);
    if (ps.e - ps.p >= 3 && !memcmp(ps.p, "\xEF\xBB\xBF", 3)) ps.p += 3;     /* a UTF-8 BOM */
    bb_errframe f;
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        parse_value(&ps);
        ws(&ps);
        if (ps.p < ps.e) fail(&ps, "text after the value");
        bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        while (ps.top > 0) bb_v_release(&ps.st[--ps.top]);
        free(ps.st);
        bb_rethrow();
    }
    bb_value v = ps.st[0];
    free(ps.st);
    return v;
}

/* --- stringify ------------------------------------------------------------------------------ */

static void str_json(buf *b, const char *s, int32_t n)
{
    putc_(b, '"');
    for (int32_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"': puts_(b, "\\\""); break;
        case '\\': puts_(b, "\\\\"); break;
        case '\n': puts_(b, "\\n"); break;
        case '\r': puts_(b, "\\r"); break;
        case '\t': puts_(b, "\\t"); break;
        case '\b': puts_(b, "\\b"); break;
        case '\f': puts_(b, "\\f"); break;
        default:
            if (c < 0x20) {
                char e[8];
                snprintf(e, sizeof e, "\\u%04x", c);
                puts_(b, e);
            } else
                putc_(b, (char)c);                  /* bytes >= 0x80 as they are (UTF-8 text) */
        }
    }
    putc_(b, '"');
}

static void newline(buf *b, int indent, int depth)
{
    if (!indent) return;
    putc_(b, '\n');
    for (int i = 0; i < indent * depth; i++) putc_(b, ' ');
}

static void num_json(buf *b, double d)
{
    char t[40];
    if (!isfinite(d)) {
        puts_(b, "null");
        return;
    }
    if (d == floor(d) && fabs(d) < 1e15) snprintf(t, sizeof t, "%.0f", d);
    else {
        snprintf(t, sizeof t, "%.15g", d);
        if (strtod(t, NULL) != d) snprintf(t, sizeof t, "%.17g", d);
    }
    puts_(b, t);
}

/* a Date as ISO 8601 "yyyy-mm-ddThh:mm:ss" (days since 1899-12-30, the fraction is the time) */
static void date_json(buf *b, double dt)
{
    double day = floor(dt);
    long secs = (long)floor((dt - day) * 86400.0 + 0.5);
    if (secs >= 86400) {
        day += 1;
        secs -= 86400;
    }
    long z = (long)day - 25569 + 719468;            /* 1899-12-30 is 25569 days before 1970-01-01 */
    long era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned long doe = (unsigned long)(z - era * 146097);
    unsigned long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long y = (long)yoe + era * 400;
    unsigned long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    unsigned long mp = (5 * doy + 2) / 153;
    unsigned long d = doy - (153 * mp + 2) / 5 + 1;
    unsigned long m = mp < 10 ? mp + 3 : mp - 9;
    char t[40];
    snprintf(t, sizeof t, "\"%04ld-%02lu-%02luT%02ld:%02ld:%02ld\"", y + (m <= 2), m, d, secs / 3600, (secs / 60) % 60,
             secs % 60);
    puts_(b, t);
}

static void val_json(buf *b, const bb_value *v0, int indent, int depth);

static void seq_json(buf *b, const bb_value *seq, int indent, int depth)
{
    bb_foreach fe;
    bb_value item;
    int first = 1;
    putc_(b, '[');
    bb_foreach_begin(&fe, seq);
    while (bb_foreach_next(&fe, &item)) {
        if (!first) putc_(b, ',');
        first = 0;
        newline(b, indent, depth + 1);
        val_json(b, &item, indent, depth + 1);
        bb_v_release(&item);
    }
    bb_foreach_end(&fe);
    if (!first) newline(b, indent, depth);
    putc_(b, ']');
}

static void val_json(buf *b, const bb_value *v0, int indent, int depth)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    if (depth > JSON_MAXDEPTH) bb_raise(E_VALUE, "JSON: nested too deeply (or a Dictionary contains itself)");
    if (v->type & BB_ARRAY) {
        if (v->u.a && v->u.a->ndims > 1) bb_raise(E_VALUE, "JSON: only one-dimensional arrays can be written");
        if (!v->u.a) {
            puts_(b, "[]");
            return;
        }
        seq_json(b, v, indent, depth);
        return;
    }
    switch (v->type) {
    case BB_EMPTY:
    case BB_NULL: puts_(b, "null"); return;
    case BB_BOOLEAN: puts_(b, v->u.b ? "true" : "false"); return;
    case BB_STRING: str_json(b, bb_str_ptr(v->u.s), bb_str_len(v->u.s)); return;
    case BB_DATE: date_json(b, v->u.dt); return;
    case BB_INTEGER: case BB_LONG: case BB_BYTE: case BB_SINGLE: case BB_DOUBLE: case BB_CURRENCY: case BB_DECIMAL:
        num_json(b, bb_v_to_double(v));
        return;
    case BB_OBJECT:
        if (!v->u.o) {
            puts_(b, "null");
            return;
        }
        if (bb_is_dict(v->u.o)) {
            int32_t n = bb_dict_count(v->u.o);
            putc_(b, '{');
            for (int32_t i = 0; i < n; i++) {
                const bb_value *k, *val;
                bb_dict_entry(v->u.o, i, &k, &val);
                if (i) putc_(b, ',');
                newline(b, indent, depth + 1);
                if (k->type == BB_STRING) str_json(b, bb_str_ptr(k->u.s), bb_str_len(k->u.s));
                else if (k->type == BB_OBJECT) bb_raise(E_VALUE, "JSON: object keys can't be written");
                else {
                    bb_str *ks = bb_v_to_str(k);    /* numbers become string keys */
                    str_json(b, bb_str_ptr(ks), bb_str_len(ks));
                    bb_str_release(ks);
                }
                putc_(b, ':');
                if (indent) putc_(b, ' ');
                val_json(b, val, indent, depth + 1);
            }
            if (n) newline(b, indent, depth);
            putc_(b, '}');
            return;
        }
        if (v->u.o->cls->iterate) {                 /* a Collection (anything For Each can walk) */
            seq_json(b, v, indent, depth);
            return;
        }
        {
            char m[160];
            snprintf(m, sizeof m, "JSON: a value of type %s can't be written", v->u.o->cls->name);
            bb_raise(E_VALUE, m);
        }
    default:
        bb_raise(E_VALUE, "JSON: this value can't be written");
    }
}

bb_str *bb_jsonstringify(const bb_value *v, bb_long indent)
{
    buf b = { 0 };
    bb_errframe f;
    if (indent < 0 || indent > 16) bb_raise(5, "the indent must be 0 to 16");
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        val_json(&b, v, (int)indent, 0);
        bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        free(b.p);
        bb_rethrow();
    }
    bb_str *s = bb_str_new(b.p ? b.p : "", (int32_t)b.n);
    free(b.p);
    return s;
}
