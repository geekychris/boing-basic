/* csv.c - Boing.Csv, reading and writing comma-separated values (docs/csv.md):
 *
 *     Dim csv As Csv
 *     Set csv = CreateObject("Csv")
 *     csv.HasHeader = True
 *     csv.Open "data.csv"
 *     Do While csv.ReadRecord()
 *         Print csv.Field("Name"); " "; csv.Field(2)
 *     Loop
 *     csv.Close
 *
 * Quoted fields may hold the delimiter, quotes ("" for one) and line breaks. Line ends LF,
 * CRLF or CR; a UTF-8 byte order mark at the start is skipped. A file is read into memory when
 * opened. Writing quotes a field only when it needs it (or always with QuoteAll). */
#include "boing.h"

#include <stdio.h>
#include "fpath.h"           /* "DH1:/name" -> "DH1:name" on AmigaOS */
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum {
    M_OPEN = 1, M_LOADTEXT, M_READRECORD, M_FIELD, P_FIELDS, P_HEADERS, M_READALL, M_CREATE, M_WRITERECORD,
    M_FORMATRECORD, M_PARSELINE, M_CLOSE, M_COLUMN, P_TEXT,
    P_DELIMITER, P_QUOTE, P_HASHEADER, P_FIELDCOUNT, P_RECORDNUMBER, P_LINENUMBER, P_ATEND, P_QUOTEALL,
    P_LINEENDING, P_TRIMFIELDS,
};
static const struct { const char *name; int id; } members[] = {
    {"Open", M_OPEN}, {"LoadText", M_LOADTEXT}, {"ReadRecord", M_READRECORD}, {"Field", M_FIELD},
    {"Fields", P_FIELDS}, {"Headers", P_HEADERS}, {"ReadAll", M_READALL}, {"Create", M_CREATE},
    {"WriteRecord", M_WRITERECORD}, {"FormatRecord", M_FORMATRECORD}, {"ParseLine", M_PARSELINE},
    {"Close", M_CLOSE}, {"ColumnIndex", M_COLUMN}, {"Text", P_TEXT},
    {"Delimiter", P_DELIMITER}, {"Quote", P_QUOTE}, {"HasHeader", P_HASHEADER}, {"FieldCount", P_FIELDCOUNT},
    {"RecordNumber", P_RECORDNUMBER}, {"LineNumber", P_LINENUMBER}, {"AtEnd", P_ATEND}, {"QuoteAll", P_QUOTEALL},
    {"LineEnding", P_LINEENDING}, {"TrimFields", P_TRIMFIELDS},
};

typedef struct { char *p; long n, cap; } sbuf;

typedef struct {
    bb_obj hdr;
    char delim, quote;
    int has_header, quote_all, trim;
    bb_str *eol;                /* LineEnding for writing (default LF) */
    /* reading */
    char *text;                 /* the whole input */
    long len, pos;
    int loaded;
    long line;                  /* line number of the current record's start (1-based) */
    long next_line;
    long recno;
    bb_str **fields;
    int nfields, capfields;
    bb_str **headers;
    int nheaders;
    int header_read;
    /* writing */
    FILE *out;
    sbuf wtext;                 /* Text: what was written when no file is open */
} csv_obj;

static const bb_class csv_class;

static void sb_add(sbuf *b, const char *p, long n)
{
    if (n <= 0) return;
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2 + 64;
        b->p = (char *)realloc(b->p, (size_t)b->cap);
    }
    memcpy(b->p + b->n, p, (size_t)n);
    b->n += n;
    b->p[b->n] = 0;
}

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static char *cstr(const bb_str *s)
{
    long n = bb_str_len(s);
    char *o = malloc((size_t)n + 1);
    memcpy(o, bb_str_ptr(s), (size_t)n);
    o[n] = 0;
    return o;
}

static void clear_fields(csv_obj *c)
{
    int i;
    for (i = 0; i < c->nfields; i++) bb_str_release(c->fields[i]);
    c->nfields = 0;
}

static void clear_reader(csv_obj *c)
{
    int i;
    clear_fields(c);
    for (i = 0; i < c->nheaders; i++) bb_str_release(c->headers[i]);
    free(c->headers);
    c->headers = NULL;
    c->nheaders = 0;
    free(c->text);
    c->text = NULL;
    c->len = c->pos = 0;
    c->loaded = 0;
    c->line = 0;
    c->next_line = 1;
    c->recno = 0;
    c->header_read = 0;
}

static void add_field(csv_obj *c, const char *p, long n)
{
    if (c->trim) {
        while (n > 0 && (*p == ' ' || *p == '\t')) p++, n--;
        while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == '\t')) n--;
    }
    if (c->nfields == c->capfields) {
        c->capfields = c->capfields ? c->capfields * 2 : 16;
        c->fields = (bb_str **)realloc(c->fields, sizeof(bb_str *) * (size_t)c->capfields);
    }
    c->fields[c->nfields++] = bb_str_new(p, (int32_t)n);
}

/* parse one record from text[*pos..len) into c->fields; 0 at the end of the input */
static int parse_record(csv_obj *c, const char *text, long len, long *pos, long *lineno)
{
    sbuf f = {NULL, 0, 0};
    long i = *pos;
    clear_fields(c);
    if (i >= len) return 0;
    for (;;) {
        f.n = 0;
        if (c->quote && i < len && text[i] == c->quote) {
            /* quoted field: up to the closing quote; "" is one quote */
            i++;
            for (;;) {
                long st = i;
                while (i < len && text[i] != c->quote) {
                    if (text[i] == '\n') (*lineno)++;
                    i++;
                }
                sb_add(&f, text + st, i - st);
                if (i >= len) break;                    /* unterminated: take what's there */
                if (i + 1 < len && text[i + 1] == c->quote) {
                    sb_add(&f, &c->quote, 1);
                    i += 2;
                    continue;
                }
                i++;                                    /* the closing quote */
                break;
            }
            /* anything up to the delimiter after the closing quote is kept (lenient) */
            {
                long st = i;
                while (i < len && text[i] != c->delim && text[i] != '\n' && text[i] != '\r') i++;
                sb_add(&f, text + st, i - st);
            }
            add_field(c, f.p ? f.p : "", f.n);
            /* a quoted field isn't trimmed inside its quotes; add_field trimmed only outer blanks */
        } else {
            long st = i;
            while (i < len && text[i] != c->delim && text[i] != '\n' && text[i] != '\r') i++;
            add_field(c, text + st, i - st);
        }
        if (i >= len) break;
        if (text[i] == c->delim) {
            i++;
            if (i >= len) {             /* a delimiter at the very end: one more empty field */
                add_field(c, "", 0);
                break;
            }
            continue;
        }
        /* line end */
        if (text[i] == '\r' && i + 1 < len && text[i + 1] == '\n') i++;
        i++;
        (*lineno)++;
        break;
    }
    free(f.p);
    *pos = i;
    return 1;
}

static void load(csv_obj *c, char *text, long len)
{
    clear_reader(c);
    c->text = text;
    c->len = len;
    c->loaded = 1;
    if (len >= 3 && (unsigned char)text[0] == 0xEF && (unsigned char)text[1] == 0xBB && (unsigned char)text[2] == 0xBF)
        c->pos = 3;
}

/* skip completely empty lines between records */
static int read_record(csv_obj *c)
{
    for (;;) {
        long ln = c->next_line;
        if (!c->loaded || c->pos >= c->len) {
            clear_fields(c);
            return 0;
        }
        if (c->text[c->pos] == '\n' || c->text[c->pos] == '\r') {
            if (c->text[c->pos] == '\r' && c->pos + 1 < c->len && c->text[c->pos + 1] == '\n') c->pos++;
            c->pos++;
            c->next_line++;
            continue;
        }
        parse_record(c, c->text, c->len, &c->pos, &c->next_line);
        c->line = ln;
        return 1;
    }
}

static void read_header(csv_obj *c)
{
    if (!c->has_header || c->header_read || !c->loaded) return;
    c->header_read = 1;
    if (read_record(c)) {
        c->headers = c->fields;
        c->nheaders = c->nfields;
        c->fields = NULL;
        c->nfields = c->capfields = 0;
    }
}

static int column_of(csv_obj *c, const bb_str *name)
{
    int i;
    read_header(c);
    for (i = 0; i < c->nheaders; i++)
        if (bb_str_len(c->headers[i]) == bb_str_len(name) &&
            !strncasecmp(bb_str_ptr(c->headers[i]), bb_str_ptr(name), (size_t)bb_str_len(name)))
            return i;
    return -1;
}

static bb_array *str_array(bb_str **items, int n)
{
    bb_array *a = bb_arr_new1(BB_STRING, 0, n - 1);
    int i;
    for (i = 0; i < n; i++) *(bb_str **)bb_arr_elem1(a, i) = bb_str_retain(items[i]);
    return a;
}

/* ---- writing ---- */

static void format_field(csv_obj *c, sbuf *b, const bb_value *v)
{
    bb_str *s;
    const char *p;
    long n, i;
    int need;
    if (v->type == BB_EMPTY || v->type == BB_NULL) {
        if (c->quote_all && c->quote) sb_add(b, (char[]){c->quote, c->quote}, 2);
        return;
    }
    s = bb_v_to_str(v);
    p = bb_str_ptr(s);
    n = bb_str_len(s);
    need = c->quote_all;
    for (i = 0; i < n && !need; i++)
        if (p[i] == c->delim || p[i] == c->quote || p[i] == '\n' || p[i] == '\r') need = 1;
    if (n && (p[0] == ' ' || p[n - 1] == ' ')) need = 1;
    if (!c->quote) need = 0;
    if (!need) sb_add(b, p, n);
    else {
        sb_add(b, &c->quote, 1);
        for (i = 0; i < n; i++) {
            if (p[i] == c->quote) sb_add(b, &c->quote, 1);
            sb_add(b, p + i, 1);
        }
        sb_add(b, &c->quote, 1);
    }
    bb_str_release(s);
}

/* the arguments as one record: one array argument, or each argument a field */
static void format_record(csv_obj *c, sbuf *b, int argc, bb_value *argv)
{
    bb_value t;
    const bb_value *v0 = argc == 1 ? bb_v_deref(&argv[0], &t) : NULL;
    int i;
    if (v0 && (v0->type & BB_ARRAY)) {
        bb_array *a = v0->u.a;
        if (a && a->ndims != 1) bb_raise(5, "WriteRecord takes a one-dimensional array");
        if (a && a->etype == BB_UDT) bb_raise(13, NULL);
        for (i = 0; a && i < a->count; i++) {
            bb_value e;
            if (i) sb_add(b, &c->delim, 1);
            /* element i as a Variant */
            e = bb_elem_load(a->etype, (const char *)a->data + (size_t)i * (size_t)a->esize);
            format_field(c, b, &e);
            bb_v_release(&e);
        }
        return;
    }
    for (i = 0; i < argc; i++) {
        bb_value tt;
        if (i) sb_add(b, &c->delim, 1);
        format_field(c, b, bb_v_deref(&argv[i], &tt));
    }
}

static void sb_free(void *ctx) { free(((sbuf *)ctx)->p); }

static void c_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    csv_obj *c = (csv_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    bb_str *s;
    switch (id) {
    case M_OPEN: {
        char *path;
        FILE *f;
        long n;
        char *buf;
        s = arg_str(argc, argv, 0);
        path = cstr(s);
        bb_str_release(s);
        f = fopen(path, "rb");
        free(path);
        if (!f) bb_raise(53, NULL);
        fseek(f, 0, SEEK_END);
        n = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)n + 1);
        if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) {
            fclose(f);
            free(buf);
            bb_raise(57, NULL);
        }
        fclose(f);
        buf[n] = 0;
        load(c, buf, n);
        return;
    }
    case M_LOADTEXT: {
        long n;
        char *buf;
        s = arg_str(argc, argv, 0);
        n = bb_str_len(s);
        buf = malloc((size_t)n + 1);
        memcpy(buf, bb_str_ptr(s), (size_t)n);
        buf[n] = 0;
        bb_str_release(s);
        load(c, buf, n);
        return;
    }
    case M_READRECORD:
        read_header(c);
        if (read_record(c)) {
            c->recno++;
            *ret = bb_v_bool(1);
        } else
            *ret = bb_v_bool(0);
        return;
    case M_FIELD: {
        bb_value t;
        const bb_value *v;
        int i;
        if (argc < 1) bb_raise(450, NULL);
        v = bb_v_deref(&argv[0], &t);
        if (v->type == BB_STRING) {
            i = column_of(c, v->u.s);
            if (i < 0) {
                char msg[300];
                snprintf(msg, sizeof msg, "no column named %.200s", bb_str_ptr(v->u.s));
                bb_raise(5, msg);
            }
        } else {
            i = (int)bb_v_to_long(v);
            if (i < 0) bb_raise(9, NULL);
        }
        *ret = bb_v_str(i < c->nfields ? bb_str_retain(c->fields[i]) : bb_str_from_c(""));
        return;
    }
    case M_COLUMN:
        s = arg_str(argc, argv, 0);
        *ret = bb_v_long(column_of(c, s));
        bb_str_release(s);
        return;
    case P_FIELDS:
        *ret = bb_v_arr(str_array(c->fields, c->nfields));
        return;
    case P_HEADERS:
        read_header(c);
        *ret = bb_v_arr(str_array(c->headers, c->nheaders));
        return;
    case M_READALL: {
        /* the remaining records as a 2-D array (record, field), short records padded with "" */
        bb_str ***rows = NULL;
        int *counts = NULL, nrows = 0, maxf = 0, r, k;
        int32_t lb[2] = {0, 0}, ub[2];
        bb_array *a;
        read_header(c);
        while (read_record(c)) {
            c->recno++;
            rows = realloc(rows, sizeof(*rows) * (size_t)(nrows + 1));
            counts = realloc(counts, sizeof(int) * (size_t)(nrows + 1));
            rows[nrows] = c->fields;
            counts[nrows] = c->nfields;
            if (c->nfields > maxf) maxf = c->nfields;
            nrows++;
            c->fields = NULL;
            c->nfields = c->capfields = 0;
        }
        ub[0] = nrows - 1;
        ub[1] = (maxf ? maxf : 1) - 1;
        a = bb_arr_new(BB_STRING, NULL, 2, lb, ub);
        for (r = 0; r < nrows; r++) {
            for (k = 0; k < counts[r]; k++) *(bb_str **)bb_arr_elem2(a, r, k) = rows[r][k];
            free(rows[r]);
        }
        free(rows);
        free(counts);
        *ret = bb_v_arr(a);
        return;
    }
    case M_CREATE: {
        char *path;
        int append = 0;
        if (present(argc, argv, 1)) {
            bb_value t;
            append = bb_v_to_bool(bb_v_deref(&argv[1], &t)) != 0;
        }
        s = arg_str(argc, argv, 0);
        path = cstr(s);
        bb_str_release(s);
        if (c->out) fclose(c->out);
        c->out = fopen(path, append ? "ab" : "wb");
        free(path);
        if (!c->out) bb_raise(75, NULL);
        return;
    }
    case M_WRITERECORD: {
        sbuf b = {NULL, 0, 0};
        bb_cleanup cl;
        cl.prev = bb_cleanups;
        cl.fn = sb_free;
        cl.ctx = &b;
        bb_cleanups = &cl;
        format_record(c, &b, argc, argv);
        bb_cleanups = cl.prev;
        sb_add(&b, c->eol ? bb_str_ptr(c->eol) : "\n", c->eol ? bb_str_len(c->eol) : 1);
        if (c->out) {
            if (fwrite(b.p, 1, (size_t)b.n, c->out) != (size_t)b.n) {
                free(b.p);
                bb_raise(61, NULL);
            }
        } else
            sb_add(&c->wtext, b.p, b.n);      /* no file: collected in Text */
        free(b.p);
        return;
    }
    case M_FORMATRECORD: {
        sbuf b = {NULL, 0, 0};
        bb_cleanup cl;
        cl.prev = bb_cleanups;
        cl.fn = sb_free;
        cl.ctx = &b;
        bb_cleanups = &cl;
        format_record(c, &b, argc, argv);
        bb_cleanups = cl.prev;
        *ret = bb_v_str(bb_str_new(b.p ? b.p : "", (int32_t)b.n));
        free(b.p);
        return;
    }
    case M_PARSELINE: {
        long pos = 0, ln = 1;
        s = arg_str(argc, argv, 0);
        parse_record(c, bb_str_ptr(s), bb_str_len(s), &pos, &ln);
        bb_str_release(s);
        *ret = bb_v_arr(str_array(c->fields, c->nfields));
        return;
    }
    case P_TEXT:                /* what WriteRecord wrote while no file was open; Text = "" clears it */
        if (set) {
            s = arg_str(argc, argv, argc - 1);
            c->wtext.n = 0;
            sb_add(&c->wtext, bb_str_ptr(s), bb_str_len(s));
            bb_str_release(s);
        } else
            *ret = bb_v_str(bb_str_new(c->wtext.p ? c->wtext.p : "", (int32_t)c->wtext.n));
        return;
    case M_CLOSE:
        if (c->out) {
            int bad = fclose(c->out) != 0;
            c->out = NULL;
            if (bad) bb_raise(61, NULL);
        }
        clear_reader(c);
        return;
    case P_DELIMITER:
    case P_QUOTE: {
        char *f = id == P_DELIMITER ? &c->delim : &c->quote;
        if (set) {
            s = arg_str(argc, argv, argc - 1);
            if (bb_str_len(s) > 1 || (id == P_DELIMITER && bb_str_len(s) != 1)) {
                bb_str_release(s);
                bb_raise(380, id == P_DELIMITER ? "Delimiter is one character" : "Quote is one character or \"\"");
            }
            *f = bb_str_len(s) ? bb_str_ptr(s)[0] : 0;
            bb_str_release(s);
            if (c->delim == c->quote) bb_raise(380, "Delimiter and Quote must differ");
        } else
            *ret = bb_v_str(*f ? bb_str_new(f, 1) : bb_str_from_c(""));
        return;
    }
    case P_HASHEADER:
    case P_QUOTEALL:
    case P_TRIMFIELDS: {
        int *f = id == P_HASHEADER ? &c->has_header : id == P_QUOTEALL ? &c->quote_all : &c->trim;
        if (set) {
            bb_value t;
            *f = bb_v_to_bool(bb_v_deref(&argv[argc - 1], &t)) != 0;
        } else
            *ret = bb_v_bool(*f);
        return;
    }
    case P_LINEENDING:
        if (set) bb_str_set(&c->eol, arg_str(argc, argv, argc - 1));
        else *ret = bb_v_str(c->eol ? bb_str_retain(c->eol) : bb_str_from_c("\n"));
        return;
    case P_FIELDCOUNT:
        *ret = bb_v_long(c->nfields);
        return;
    case P_RECORDNUMBER:
        *ret = bb_v_long(c->recno);
        return;
    case P_LINENUMBER:
        *ret = bb_v_long(c->line);
        return;
    case P_ATEND: {
        long p = c->pos;
        if (c->loaded) {
            read_header(c);
            p = c->pos;
            while (p < c->len && (c->text[p] == '\n' || c->text[p] == '\r')) p++;
        }
        *ret = bb_v_bool(!c->loaded || p >= c->len);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t c_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return M_FIELD;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void c_terminate(bb_obj *self)
{
    csv_obj *c = (csv_obj *)self;
    if (c->out) fclose(c->out);
    clear_reader(c);
    free(c->fields);
    free(c->wtext.p);
    bb_str_release(c->eol);
}

static const bb_class csv_class = {
    "Csv", sizeof(csv_obj), c_find, c_invoke, c_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_csv_class(void) { return &csv_class; }
bb_obj *bb_csv_new(void)
{
    csv_obj *c = (csv_obj *)bb_obj_new(&csv_class);
    c->delim = ',';
    c->quote = '"';
    c->next_line = 1;
    return &c->hdr;
}
