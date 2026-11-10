/* io.c - console, Print, Input and files */
#include "boing.h"
#include "platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include "fpath.h"

#define MAXFILES 512

typedef struct bfile {
    FILE *fp;
    int mode;
    int32_t reclen;
    int32_t col;
    char *path;
} bfile;

static bfile files[MAXFILES];

/* console state */
static char conbuf[4096];
static size_t conlen;
static int32_t concol;
static char *conline;      /* pending Input line (console) */
static size_t conpos;

void bb_console_flush(void)
{
    if (conlen) { bb_plat_write(conbuf, conlen); conlen = 0; }
    bb_plat_flush();
}

static void con_write(const char *p, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) {
        if (p[i] == '\n' || p[i] == '\r') concol = 0; else concol++;
    }
    if (conlen + n > sizeof conbuf) bb_console_flush();
    if (n > sizeof conbuf) { bb_plat_write(p, n); return; }
    memcpy(conbuf + conlen, p, n);
    conlen += n;
    if (memchr(p, '\n', n)) bb_console_flush();
}

static bfile *getfile(bb_long fn)
{
    if (fn < 1 || fn >= MAXFILES) bb_raise(52, NULL);
    if (!files[fn].fp) bb_raise(52, NULL);
    return &files[fn];
}

static void out(int fn, const char *p, size_t n)
{
    bfile *f;
    size_t i;
    if (fn <= 0) { con_write(p, n); return; }
    f = getfile(fn);
    if (!(f->mode & (BB_FM_OUTPUT | BB_FM_APPEND))) bb_raise(54, NULL);
    if (n && fwrite(p, 1, n, f->fp) != n) bb_raise(57, NULL);
    for (i = 0; i < n; i++) { if (p[i] == '\n') f->col = 0; else f->col++; }
}

static int32_t col_of(int fn) { return fn <= 0 ? concol : getfile(fn)->col; }

void bb_print_cstr(int fn, const char *s) { out(fn, s, strlen(s)); }
void bb_print_str(int fn, const bb_str *s) { out(fn, bb_str_ptr(s), (size_t)bb_str_len(s)); }

/* Print / Str style: no leading zero before the decimal point (" .5", "-.25") */
const char *bb_num_strip0_(const bb_str *s, int32_t *len)
{
    const char *p = bb_str_ptr(s);
    int32_t n = bb_str_len(s);
    if (n >= 2 && p[0] == '0' && p[1] == '.') { *len = n - 1; return p + 1; }
    if (n >= 3 && p[0] == '-' && p[1] == '0' && p[2] == '.') { *len = n - 1; return NULL; }
    *len = n;
    return p;
}

static void print_num(int fn, bb_str *s)
{
    int32_t n;
    const char *p = bb_num_strip0_(s, &n);
    if (bb_str_len(s) && s->data[0] != '-') out(fn, " ", 1);
    if (p) out(fn, p, (size_t)n);
    else { out(fn, "-", 1); out(fn, s->data + 2, (size_t)(n - 1)); }
    out(fn, " ", 1);
    bb_str_release(s);
}

void bb_print_long(int fn, bb_long l) { print_num(fn, bb_str_from_long(l)); }
void bb_print_double(int fn, bb_double d) { print_num(fn, bb_str_from_double(d)); }
void bb_print_single(int fn, bb_single f) { print_num(fn, bb_str_from_single(f)); }
void bb_print_cur(int fn, bb_cur c) { print_num(fn, bb_str_from_cur(c)); }
void bb_print_date(int fn, bb_date d) { bb_str *s = bb_str_from_date(d); bb_print_str(fn, s); bb_str_release(s); }
void bb_print_bool(int fn, bb_bool b) { bb_print_cstr(fn, b ? "True" : "False"); }

void bb_print_value(int fn, const bb_value *v)
{
    bb_value t;
    v = bb_v_deref(v, &t);
    switch (v->type) {
    case BB_EMPTY: break;
    case BB_NULL: bb_print_cstr(fn, "Null"); break;
    case BB_INTEGER: bb_print_long(fn, v->u.i); break;
    case BB_LONG: bb_print_long(fn, v->u.l); break;
    case BB_BYTE: bb_print_long(fn, v->u.by); break;
    case BB_SINGLE: bb_print_single(fn, v->u.f); break;
    case BB_DOUBLE: bb_print_double(fn, v->u.d); break;
    case BB_CURRENCY: bb_print_cur(fn, v->u.c); break;
    case BB_DECIMAL: print_num(fn, bb_dec_to_str(v)); break;
    case BB_DATE: bb_print_date(fn, v->u.dt); break;
    case BB_BOOLEAN: bb_print_bool(fn, v->u.b); break;
    case BB_STRING: bb_print_str(fn, v->u.s); break;
    case BB_ERROR: { char b[32]; snprintf(b, sizeof b, "Error %ld", (long)v->u.l); bb_print_cstr(fn, b); break; }
    default: {
        bb_str *s = bb_v_to_str(v);
        bb_print_str(fn, s);
        bb_str_release(s);
    }
    }
}

void bb_print_comma(int fn)
{
    int32_t n = 14 - col_of(fn) % 14;
    while (n-- > 0) out(fn, " ", 1);
}

void bb_print_nl(int fn) { out(fn, "\n", 1); }

void bb_print_spc(int fn, bb_long n) { while (n-- > 0) out(fn, " ", 1); }

void bb_print_tab(int fn, bb_long n)
{
    int32_t c = col_of(fn);
    if (n < 1) n = 1;
    if (c > n - 1) { out(fn, "\n", 1); c = 0; }
    while (c++ < n - 1) out(fn, " ", 1);
}

void bb_write_value(int fn, const bb_value *v, int last)
{
    bb_value t;
    v = bb_v_deref(v, &t);
    switch (v->type) {
    case BB_EMPTY: break;
    case BB_NULL: bb_print_cstr(fn, "#NULL#"); break;
    case BB_BOOLEAN: bb_print_cstr(fn, v->u.b ? "#TRUE#" : "#FALSE#"); break;
    case BB_STRING: out(fn, "\"", 1); bb_print_str(fn, v->u.s); out(fn, "\"", 1); break;
    case BB_DATE: {
        bb_date d = v->u.dt;
        char b[64];
        snprintf(b, sizeof b, "#%04ld-%02ld-%02ld %02ld:%02ld:%02ld#", (long)bb_year(d), (long)bb_month(d),
                 (long)bb_day(d), (long)bb_hour(d), (long)bb_minute(d), (long)bb_second(d));
        bb_print_cstr(fn, b);
        break;
    }
    case BB_ERROR: { char b[32]; snprintf(b, sizeof b, "#ERROR %ld#", (long)v->u.l); bb_print_cstr(fn, b); break; }
    default: {
        bb_str *s = bb_v_to_str(v);
        bb_print_str(fn, s);
        bb_str_release(s);
    }
    }
    if (last) out(fn, "\n", 1); else out(fn, ",", 1);
}

/* ---- input ---- */

/* read a raw line from a file or the console; NULL at EOF */
static char *read_line(int fn, size_t *len)
{
    if (fn <= 0) {
        char *l = NULL;
        bb_console_flush();
        if (!bb_plat_read_line(&l, len)) return NULL;
        concol = 0;
        return l;
    } else {
        bfile *f = getfile(fn);
        size_t cap = 128, n = 0;
        char *b;
        int c;
        if (!(f->mode & (BB_FM_INPUT | BB_FM_BINARY))) bb_raise(54, NULL);
        c = getc(f->fp);
        if (c == EOF) return NULL;
        b = (char *)malloc(cap);
        while (c != EOF && c != '\n') {
            if (c == '\r') {
                int d = getc(f->fp);
                if (d != '\n' && d != EOF) ungetc(d, f->fp);
                break;
            }
            if (n + 1 >= cap) { cap *= 2; b = (char *)realloc(b, cap); }
            b[n++] = (char)c;
            c = getc(f->fp);
        }
        b[n] = 0;
        *len = n;
        return b;
    }
}

bb_str *bb_input_line(int fn)
{
    size_t n;
    char *l = read_line(fn, &n);
    bb_str *s;
    if (!l) bb_raise(62, NULL);
    s = bb_str_new(l, (int32_t)n);
    free(l);
    return s;
}

void bb_input_prompt(bb_str *prompt, int question)
{
    bb_print_str(0, prompt);
    if (question) bb_print_cstr(0, "? ");
    bb_console_flush();
}

/* character source for Input field parsing */
typedef struct src { int fn; bfile *f; } src;
static int sgetc(src *s)
{
    if (s->fn <= 0) {
        if (!conline) {
            size_t n;
            conline = read_line(0, &n);
            conpos = 0;
            if (!conline) return EOF;
        }
        if (conline[conpos] == 0) return '\n';
        return (unsigned char)conline[conpos++];
    }
    return getc(s->f->fp);
}
static void sungetc(src *s, int c)
{
    if (c == EOF) return;
    if (s->fn <= 0) { if (conline && conpos > 0 && c != '\n') conpos--; return; }
    ungetc(c, s->f->fp);
}

bb_value bb_input_field(int fn, int variant)
{
    src s;
    int c, quoted = 0;
    size_t cap = 64, n = 0;
    char *b;
    bb_value r;
    s.fn = fn;
    s.f = fn > 0 ? getfile(fn) : NULL;
    if (s.f && !(s.f->mode & (BB_FM_INPUT | BB_FM_BINARY))) bb_raise(54, NULL);
    do c = sgetc(&s); while (c == ' ' || c == '\t');
    if (c == EOF) bb_raise(62, NULL);
    if (fn <= 0 && c == '\n' && conline && conline[conpos] == 0) {
        /* console: an exhausted line yields an empty field, then needs a new line */
        free(conline); conline = NULL;
        do c = sgetc(&s); while (c == ' ' || c == '\t');
        if (c == EOF) bb_raise(62, NULL);
    }
    b = (char *)malloc(cap);
    if (c == '"') {
        quoted = 1;
        while ((c = sgetc(&s)) != EOF && c != '"' && !(fn <= 0 && c == '\n')) {
            if (n + 1 >= cap) { cap *= 2; b = (char *)realloc(b, cap); }
            b[n++] = (char)c;
        }
        /* skip to the separator */
        do c = sgetc(&s); while (c == ' ' || c == '\t');
    } else {
        while (c != EOF && c != ',' && c != '\n' && c != '\r') {
            if (n + 1 >= cap) { cap *= 2; b = (char *)realloc(b, cap); }
            b[n++] = (char)c;
            c = sgetc(&s);
        }
        while (n && (b[n - 1] == ' ' || b[n - 1] == '\t')) n--;
    }
    if (c == '\r') { int d = sgetc(&s); if (d != '\n') sungetc(&s, d); }
    if (fn <= 0 && c == '\n' && conline) { free(conline); conline = NULL; }
    b[n] = 0;
    r = bb_v_str(bb_str_new(b, (int32_t)n));
    if (!quoted) {
        /* what Write # writes: #TRUE#, #FALSE#, #NULL#, #date# (for typed targets too) */
        double d;
        if (strcasecmp(b, "#TRUE#") == 0) { bb_v_release(&r); r = bb_v_bool(1); }
        else if (strcasecmp(b, "#FALSE#") == 0) { bb_v_release(&r); r = bb_v_bool(0); }
        else if (strcasecmp(b, "#NULL#") == 0) { bb_v_release(&r); r = bb_v_null(); }
        else if (n > 2 && b[0] == '#' && b[n - 1] == '#') {
            bb_str *ds = bb_str_new(b + 1, (int32_t)n - 2);
            bb_v_release(&r);
            r = bb_v_date(bb_str_to_date(ds));
            bb_str_release(ds);
        } else if (variant) {
            if (n == 0) { bb_v_release(&r); r = bb_v_empty(); }
            else if (bb_parse_number(b, (int32_t)n, &d)) { bb_v_release(&r); r = bb_v_double(d); }
        }
    }
    free(b);
    return r;
}

void bb_input_end(int fn)
{
    if (fn <= 0 && conline) { free(conline); conline = NULL; }
}

bb_long bb_msgbox(const bb_value *prompt, bb_long buttons, const bb_value *title)
{
    bb_str *p = bb_v_to_str(prompt), *t = NULL;
    bb_value tt;
    long r;
    if (title && bb_v_deref(title, &tt)->type != BB_ERROR) t = bb_v_to_str(title);
    bb_console_flush();
    r = bb_plat_msgbox(bb_str_ptr(p), (long)buttons, t ? bb_str_ptr(t) : "");
    concol = 0;
    bb_str_release(p); bb_str_release(t);
    return (bb_long)r;
}

bb_str *bb_inputbox(const bb_value *prompt, const bb_value *title, const bb_value *def)
{
    bb_str *p = bb_v_to_str(prompt), *t = NULL, *d = NULL, *r;
    bb_value tt;
    char *res;
    if (title && bb_v_deref(title, &tt)->type != BB_ERROR) t = bb_v_to_str(title);
    if (def && bb_v_deref(def, &tt)->type != BB_ERROR) d = bb_v_to_str(def);
    bb_console_flush();
    res = bb_plat_inputbox(bb_str_ptr(p), t ? bb_str_ptr(t) : "", d ? bb_str_ptr(d) : "");
    concol = 0;
    r = res ? bb_str_from_c(res) : NULL;
    free(res);
    bb_str_release(p); bb_str_release(t); bb_str_release(d);
    return r;
}

/* ---- files ---- */

void bb_open(bb_str *path, int mode, int access, bb_long fn, bb_long reclen)
{
    const char *m;
    FILE *fp;
    long sz;
    /* access (Open ... Access): 0 none given, 1 Read, 2 Write, 3 Read Write */
    if (fn < 1 || fn >= MAXFILES) bb_raise(52, NULL);
    if (files[fn].fp) bb_raise(55, NULL);
    if (!bb_str_len(path)) bb_raise(75, NULL);
    switch (mode) {
    case BB_FM_INPUT: m = "rb"; break;
    case BB_FM_OUTPUT: m = "wb"; break;
    case BB_FM_APPEND: m = "ab"; break;
    default: /* binary / random: read-write, create if missing; Access Read: an existing file
                only (error 53, as VB), read-only */
        if (access == 1) {
            if (bb_plat_file_size(bb_str_ptr(path), &sz) != 0) bb_raise(53, NULL);
            m = "rb";
        } else m = bb_plat_file_size(bb_str_ptr(path), &sz) == 0 ? "r+b" : "w+b";
        break;
    }
    fp = fopen(bb_str_ptr(path), m);
    if (!fp && (mode == BB_FM_BINARY || mode == BB_FM_RANDOM)) fp = fopen(bb_str_ptr(path), "rb");
    if (!fp) bb_raise(mode == BB_FM_INPUT ? 53 : 75, NULL);
    files[fn].fp = fp;
    files[fn].mode = mode;
    files[fn].reclen = reclen > 0 ? reclen : (mode == BB_FM_RANDOM ? 128 : 1);
    files[fn].col = 0;
    files[fn].path = strdup(bb_str_ptr(path));
}

void bb_close(bb_long fn)
{
    if (fn == 0) { bb_close_all(); return; }
    if (fn < 1 || fn >= MAXFILES) bb_raise(52, NULL);
    if (!files[fn].fp) return;
    fclose(files[fn].fp);
    free(files[fn].path);
    memset(&files[fn], 0, sizeof files[fn]);
}

void bb_close_all(void)
{
    int i;
    for (i = 1; i < MAXFILES; i++) if (files[i].fp) bb_close(i);
}

bb_long bb_freefile(void)
{
    int i;
    for (i = 1; i < 256; i++) if (!files[i].fp) return i;
    bb_raise(67, NULL);
    return 0;
}

bb_bool bb_eof(bb_long fn)
{
    bfile *f = getfile(fn);
    int c;
    if (f->mode & (BB_FM_OUTPUT | BB_FM_APPEND)) return BB_TRUE;
    c = getc(f->fp);
    if (c == EOF) return BB_TRUE;
    ungetc(c, f->fp);
    return BB_FALSE;
}

bb_long bb_lof(bb_long fn)
{
    bfile *f = getfile(fn);
    long pos = ftell(f->fp), end;
    fflush(f->fp);
    fseek(f->fp, 0, SEEK_END);
    end = ftell(f->fp);
    fseek(f->fp, pos, SEEK_SET);
    return (bb_long)end;
}

bb_long bb_seek_get(bb_long fn)
{
    bfile *f = getfile(fn);
    long pos = ftell(f->fp);
    if (f->mode == BB_FM_RANDOM) return (bb_long)(pos / f->reclen + 1);
    return (bb_long)pos + 1;
}

bb_long bb_loc(bb_long fn)
{
    bfile *f = getfile(fn);
    long pos = ftell(f->fp);
    if (f->mode == BB_FM_RANDOM) return (bb_long)(pos / f->reclen);
    if (f->mode == BB_FM_BINARY) return (bb_long)pos;
    return (bb_long)((pos + 127) / 128);
}

void bb_seek_set(bb_long fn, bb_long pos)
{
    bfile *f = getfile(fn);
    if (pos < 1) bb_raise(63, NULL);
    if (f->mode == BB_FM_RANDOM) fseek(f->fp, (long)(pos - 1) * f->reclen, SEEK_SET);
    else fseek(f->fp, (long)(pos - 1), SEEK_SET);
}

/* little-endian binary encoding, like VB's files */
static void put_le(FILE *fp, uint64_t v, int n)
{
    int i;
    for (i = 0; i < n; i++) putc((int)((v >> (8 * i)) & 0xff), fp);
}
static uint64_t get_le(FILE *fp, int n)
{
    uint64_t v = 0;
    int i, c;
    for (i = 0; i < n; i++) {
        c = getc(fp);
        if (c == EOF) c = 0;
        v |= (uint64_t)(c & 0xff) << (8 * i);
    }
    return v;
}

static void put_item(bfile *f, int t, const bb_udt_desc *udt, const void *p, int fixlen, int in_udt);
static void get_item(bfile *f, int t, const bb_udt_desc *udt, void *p, int fixlen, int in_udt);

static void put_udt(bfile *f, const bb_udt_desc *d, const void *p)
{
    int32_t i, k;
    for (i = 0; i < d->nfields; i++) {
        const bb_field *fl = &d->fields[i];
        const char *q = (const char *)p + fl->offset;
        if (fl->type & BB_ARRAY) {
            const bb_array *a = *(bb_array *const *)q;
            if (a) for (k = 0; k < a->count; k++)
                put_item(f, a->etype, a->udt, (const char *)a->data + (size_t)k * a->esize, 0, 1);
        } else put_item(f, fl->type, fl->udt, q, fl->fixlen, 1);
    }
}

static void get_udt(bfile *f, const bb_udt_desc *d, void *p)
{
    int32_t i, k;
    for (i = 0; i < d->nfields; i++) {
        const bb_field *fl = &d->fields[i];
        char *q = (char *)p + fl->offset;
        if (fl->type & BB_ARRAY) {
            bb_array *a = *(bb_array **)q;
            if (a) for (k = 0; k < a->count; k++)
                get_item(f, a->etype, a->udt, (char *)a->data + (size_t)k * a->esize, 0, 1);
        } else get_item(f, fl->type, fl->udt, q, fl->fixlen, 1);
    }
}

static void put_item(bfile *f, int t, const bb_udt_desc *udt, const void *p, int fixlen, int in_udt)
{
    FILE *fp = f->fp;
    union { float f; uint32_t u; } fu;
    union { double d; uint64_t u; } du;
    switch (t) {
    case BB_BYTE: putc(*(const bb_byte *)p, fp); break;
    case BB_INTEGER: case BB_BOOLEAN: put_le(fp, (uint16_t)*(const bb_int *)p, 2); break;
    case BB_LONG: put_le(fp, (uint32_t)*(const bb_long *)p, 4); break;
    case BB_SINGLE: fu.f = *(const bb_single *)p; put_le(fp, fu.u, 4); break;
    case BB_DOUBLE: case BB_DATE: du.d = *(const bb_double *)p; put_le(fp, du.u, 8); break;
    case BB_CURRENCY: put_le(fp, (uint64_t)*(const bb_cur *)p, 8); break;
    case BB_STRING: {
        const bb_str *s = *(bb_str *const *)p;
        int32_t l = bb_str_len(s);
        if (fixlen) {
            int32_t k;
            fwrite(bb_str_ptr(s), 1, (size_t)(l < fixlen ? l : fixlen), fp);
            for (k = l; k < fixlen; k++) putc(' ', fp);
            break;
        }
        if (f->mode == BB_FM_RANDOM || in_udt) put_le(fp, (uint32_t)l, 2);
        fwrite(bb_str_ptr(s), 1, (size_t)l, fp);
        break;
    }
    case BB_VARIANT: {
        const bb_value *v = (const bb_value *)p;
        bb_value tmp;
        v = bb_v_deref(v, &tmp);
        put_le(fp, v->type, 2);
        if (v->type == BB_STRING) {
            int32_t l = bb_str_len(v->u.s);
            put_le(fp, (uint32_t)l, 2);
            fwrite(bb_str_ptr(v->u.s), 1, (size_t)l, fp);
        } else if (v->type != BB_EMPTY && v->type != BB_NULL && !(v->type & BB_ARRAY) && v->type != BB_OBJECT)
            put_item(f, v->type, NULL, &v->u, 0, in_udt);
        break;
    }
    case BB_UDT: put_udt(f, udt, p); break;
    default: bb_raise(13, NULL);
    }
}

static void get_item(bfile *f, int t, const bb_udt_desc *udt, void *p, int fixlen, int in_udt)
{
    FILE *fp = f->fp;
    union { float f; uint32_t u; } fu;
    union { double d; uint64_t u; } du;
    switch (t) {
    case BB_BYTE: { int c = getc(fp); *(bb_byte *)p = (bb_byte)(c == EOF ? 0 : c); break; }
    case BB_INTEGER: case BB_BOOLEAN: *(bb_int *)p = (bb_int)(uint16_t)get_le(fp, 2); break;
    case BB_LONG: *(bb_long *)p = (bb_long)(uint32_t)get_le(fp, 4); break;
    case BB_SINGLE: fu.u = (uint32_t)get_le(fp, 4); *(bb_single *)p = fu.f; break;
    case BB_DOUBLE: case BB_DATE: du.u = get_le(fp, 8); *(bb_double *)p = du.d; break;
    case BB_CURRENCY: *(bb_cur *)p = (bb_cur)get_le(fp, 8); break;
    case BB_STRING: {
        bb_str **sp = (bb_str **)p;
        int32_t l;
        bb_str *s;
        if (fixlen) l = fixlen;
        else if (f->mode == BB_FM_RANDOM || in_udt) l = (int32_t)get_le(fp, 2);
        else l = bb_str_len(*sp);      /* binary: as many bytes as the string holds */
        s = bb_str_alloc(l);
        if (l) {
            size_t got = fread(s->data, 1, (size_t)l, fp);
            if (got < (size_t)l) memset(s->data + got, 0, (size_t)l - got);
        }
        bb_str_set(sp, s);
        break;
    }
    case BB_VARIANT: {
        bb_value *v = (bb_value *)p;
        int vt = (int)get_le(fp, 2);
        bb_v_release(v);
        if (vt == BB_STRING) {
            int32_t l = (int32_t)get_le(fp, 2);
            bb_str *s = bb_str_alloc(l);
            if (l && fread(s->data, 1, (size_t)l, fp) != (size_t)l) { /* short read */ }
            *v = bb_v_str(s);
        } else if (vt == BB_EMPTY || vt == BB_NULL) {
            *v = bb_v_make((uint16_t)vt);
        } else {
            *v = bb_v_make((uint16_t)vt);
            get_item(f, vt, NULL, &v->u, 0, in_udt);
        }
        break;
    }
    case BB_UDT: get_udt(f, udt, p); break;
    default: bb_raise(13, NULL);
    }
}

void bb_put(bb_long fn, bb_long rec, int t, const bb_udt_desc *udt, const void *p)
{
    bfile *f = getfile(fn);
    if (!(f->mode & (BB_FM_BINARY | BB_FM_RANDOM))) bb_raise(54, NULL);
    if (rec > 0) bb_seek_set(fn, rec);
    else if (rec < 0) bb_raise(63, NULL);
    fseek(f->fp, 0, SEEK_CUR);
    if (t & BB_ARRAY) {
        const bb_array *a = *(bb_array *const *)p;
        int32_t k;
        if (a) for (k = 0; k < a->count; k++) put_item(f, a->etype, a->udt, (const char *)a->data + (size_t)k * a->esize, 0, 0);
    } else put_item(f, t, udt, p, 0, 0);
    if (f->mode == BB_FM_RANDOM) {
        /* pad the record */
        long pos = ftell(f->fp), rs = (pos % f->reclen);
        if (rs) { long k; for (k = rs; k < f->reclen; k++) putc(0, f->fp); }
    }
    fflush(f->fp);
}

void bb_get(bb_long fn, bb_long rec, int t, const bb_udt_desc *udt, void *p)
{
    bfile *f = getfile(fn);
    long start;
    if (!(f->mode & (BB_FM_BINARY | BB_FM_RANDOM))) bb_raise(54, NULL);
    if (rec > 0) bb_seek_set(fn, rec);
    else if (rec < 0) bb_raise(63, NULL);
    fseek(f->fp, 0, SEEK_CUR);
    start = ftell(f->fp);
    if (t & BB_ARRAY) {
        bb_array *a = *(bb_array **)p;
        int32_t k;
        if (a) for (k = 0; k < a->count; k++) get_item(f, a->etype, a->udt, (char *)a->data + (size_t)k * a->esize, 0, 0);
    } else get_item(f, t, udt, p, 0, 0);
    if (f->mode == BB_FM_RANDOM) fseek(f->fp, start + f->reclen, SEEK_SET);
}

bb_str *bb_input_chars(bb_long n, bb_long fn)
{
    bfile *f = getfile(fn);
    bb_str *s;
    size_t got;
    if (n < 0) bb_raise(5, NULL);
    s = bb_str_alloc(n);
    if (!n) return s;
    got = fread(s->data, 1, (size_t)n, f->fp);
    if (got < (size_t)n) { bb_str_release(s); bb_raise(62, NULL); }
    return s;
}

/* ---- file system ---- */

static void fs_check(int err) { if (err) bb_raise(err, NULL); }

/* * and ? (VB), and AmigaDOS's #? (any run) and #c (zero or more c); case-insensitive */
static int wild_match(const char *p, const char *s)
{
    for (; *p; p++, s++) {
        if (*p == '*' || (p[0] == '#' && p[1] == '?')) {
            const char *rest = p + (*p == '*' ? 1 : 2);
            for (; *s; s++) if (wild_match(rest, s)) return 1;
            return wild_match(rest, s);
        }
        if (p[0] == '#' && p[1]) {
            /* #c: zero or more c */
            const char *rest = p + 2;
            for (;;) {
                if (wild_match(rest, s)) return 1;
                if (!*s || tolower((unsigned char)*s) != tolower((unsigned char)p[1])) return 0;
                s++;
            }
        }
        if (!*s) return 0;
        if (*p == '?') continue;
        if (tolower((unsigned char)*p) != tolower((unsigned char)*s)) return 0;
    }
    return *s == 0;
}

static int has_wild(const char *s) { return strpbrk(s, "*?#") != NULL; }

/* split "dir/pat" */
static void split_path(const char *path, char *dir, size_t dn, const char **pat)
{
    const char *slash = strrchr(path, bb_plat_path_sep());
    const char *colon = strrchr(path, ':');
    if (colon && (!slash || colon > slash)) slash = colon;
    if (slash) {
        size_t n = (size_t)(slash - path) + 1;
        if (n >= dn) n = dn - 1;
        memcpy(dir, path, n);
        dir[n] = 0;
        *pat = slash + 1;
    } else {
        dir[0] = 0;
        *pat = path;
    }
}

void bb_kill(bb_str *pattern)
{
    const char *p = bb_str_ptr(pattern);
    if (!has_wild(p)) { fs_check(bb_plat_remove(p)); return; }
    {
        char dir[1024], full[2048];
        const char *pat, *name;
        int isdir, n = 0;
        void *h;
        split_path(p, dir, sizeof dir, &pat);
        h = bb_plat_dir_open(dir[0] ? dir : ".");
        if (!h) bb_raise(53, NULL);
        while ((name = bb_plat_dir_next(h, &isdir)) != NULL) {
            if (isdir || !wild_match(pat, name)) continue;
            snprintf(full, sizeof full, "%s%s", dir, name);
            bb_plat_remove(full);
            n++;
        }
        bb_plat_dir_close(h);
        if (!n) bb_raise(53, NULL);
    }
}

void bb_name(bb_str *from, bb_str *to)
{
    long sz;
    if (bb_plat_file_size(bb_str_ptr(to), &sz) == 0) bb_raise(58, NULL);
    fs_check(bb_plat_rename(bb_str_ptr(from), bb_str_ptr(to)));
}
void bb_mkdir(bb_str *path) { fs_check(bb_plat_mkdir(bb_str_ptr(path))); }
void bb_rmdir(bb_str *path) { fs_check(bb_plat_rmdir(bb_str_ptr(path))); }
void bb_chdir(bb_str *path) { fs_check(bb_plat_chdir(bb_str_ptr(path))); }

bb_str *bb_curdir(void)
{
    char buf[1024];
    if (bb_plat_getcwd(buf, sizeof buf)) bb_raise(76, NULL);
    return bb_str_from_c(buf);
}

bb_long bb_filelen(bb_str *path)
{
    long sz;
    fs_check(bb_plat_file_size(bb_str_ptr(path), &sz));
    return (bb_long)sz;
}

void bb_filecopy(bb_str *from, bb_str *to)
{
    FILE *a = fopen(bb_str_ptr(from), "rb"), *b;
    char buf[8192];
    size_t n;
    if (!a) bb_raise(53, NULL);
    b = fopen(bb_str_ptr(to), "wb");
    if (!b) { fclose(a); bb_raise(75, NULL); }
    while ((n = fread(buf, 1, sizeof buf, a)) > 0)
        if (fwrite(buf, 1, n, b) != n) { fclose(a); fclose(b); bb_raise(61, NULL); }
    fclose(a);
    fclose(b);
}

/* Dir state */
static void *dir_h;
static char dir_pat[512];
static bb_long dir_attr;

bb_str *bb_dir(const bb_value *pattern, bb_long attr)
{
    const char *name;
    int isdir;
    bb_value t;
    const bb_value *pv = pattern ? bb_v_deref(pattern, &t) : NULL;
    if (pv && !(pv->type == BB_ERROR && (pv->flags & BB_VF_MISSING))) {
        bb_str *ps = bb_v_to_str(pv);
        char dir[1024];
        const char *pat;
        long sz;
        if (dir_h) { bb_plat_dir_close(dir_h); dir_h = NULL; }
        dir_attr = attr;
        if (!has_wild(bb_str_ptr(ps))) {
            /* plain name: exists? */
            const char *p = bb_str_ptr(ps);
            bb_str *r = NULL;
            if (bb_str_len(ps) && bb_plat_file_size(p, &sz) == 0 && (!bb_plat_is_dir(p) || (attr & 16))) {
                const char *base;
                split_path(p, dir, sizeof dir, &base);
                r = bb_str_from_c(base);
            }
            bb_str_release(ps);
            return r;
        }
        split_path(bb_str_ptr(ps), dir, sizeof dir, &pat);
        snprintf(dir_pat, sizeof dir_pat, "%s", pat);
        dir_h = bb_plat_dir_open(dir[0] ? dir : ".");
        bb_str_release(ps);
        if (!dir_h) return NULL;
    } else if (!dir_h) bb_raise(5, NULL);
    while ((name = bb_plat_dir_next(dir_h, &isdir)) != NULL) {
        if (isdir && !(dir_attr & 16)) continue;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;     /* as on AmigaDOS */
        if (wild_match(dir_pat, name)) return bb_str_from_c(name);
    }
    bb_plat_dir_close(dir_h);
    dir_h = NULL;
    return NULL;
}
