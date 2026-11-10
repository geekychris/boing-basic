/* sbuilder.c - Boing.StringBuilder (docs/stringbuilder.md): building a long String piece by
 * piece without copying it each time (s = s & x copies s on every step; Append adds to a growing
 * buffer, so building n pieces costs O(total length), not O(n * length)).
 *
 *     Dim sb As StringBuilder
 *     Set sb = CreateObject("StringBuilder")
 *     For i = 1 To 10000: sb.Append CStr(i): sb.Append ",": Next
 *     s = sb.ToString                 ' or just sb: ToString is the default member
 */
#include "boing.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct {
    bb_obj hdr;
    char *p;
    int32_t n, cap;
} sbuilder;

enum { P_TOSTRING = 0, M_APPEND = 1, M_APPENDLINE, M_INSERT, M_REMOVE, M_REPLACE, M_CLEAR, P_LENGTH, P_CAPACITY,
       M_CHAR };

static const struct { const char *name; int id; } members[] = {
    {"ToString", P_TOSTRING}, {"Append", M_APPEND}, {"AppendLine", M_APPENDLINE}, {"Insert", M_INSERT},
    {"Remove", M_REMOVE}, {"Replace", M_REPLACE}, {"Clear", M_CLEAR}, {"Length", P_LENGTH},
    {"Capacity", P_CAPACITY}, {"Char", M_CHAR},
};

static void reserve(sbuilder *b, int64_t need)
{
    if (need > 0x7FFFFFF0) bb_raise(7, NULL);
    if (need <= b->cap) return;
    int64_t c = b->cap ? b->cap : 64;
    while (c < need) c *= 2;
    if (c > 0x7FFFFFF0) c = 0x7FFFFFF0;
    char *np = realloc(b->p, (size_t)c);
    if (!np) bb_raise(7, NULL);
    b->p = np;
    b->cap = (int32_t)c;
}

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static void insert_at(sbuilder *b, int32_t pos, const char *s, int32_t n)
{
    reserve(b, (int64_t)b->n + n);
    memmove(b->p + pos + n, b->p + pos, b->n - pos);
    memcpy(b->p + pos, s, n);
    b->n += n;
}

static int32_t sb_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return P_TOSTRING;
    for (size_t i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void sb_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    sbuilder *b = (sbuilder *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    bb_str *s, *w;
    int32_t a, c;
    switch (id) {
    case P_TOSTRING:
        if (set) bb_raise(383, NULL);
        *ret = bb_v_str(bb_str_new(b->p ? b->p : "", b->n));
        return;
    case M_APPEND:
        for (int i = 0; i < argc; i++) {             /* Append a, b, c appends them all */
            s = arg_str(argc, argv, i);
            insert_at(b, b->n, bb_str_ptr(s), bb_str_len(s));
            bb_str_release(s);
        }
        *ret = bb_v_obj(bb_obj_retain(self));        /* so calls can be chained */
        return;
    case M_APPENDLINE:
        if (argc) {
            s = arg_str(argc, argv, 0);
            insert_at(b, b->n, bb_str_ptr(s), bb_str_len(s));
            bb_str_release(s);
        }
        insert_at(b, b->n, "\n", 1);
        *ret = bb_v_obj(bb_obj_retain(self));
        return;
    case M_INSERT:                                   /* Insert pos, s: pos 1 = at the start */
        a = arg_long(argc, argv, 0);
        if (a < 1 || a > b->n + 1) bb_raise(5, "the position is outside the text");
        s = arg_str(argc, argv, 1);
        insert_at(b, a - 1, bb_str_ptr(s), bb_str_len(s));
        bb_str_release(s);
        return;
    case M_REMOVE:                                   /* Remove start, count */
        a = arg_long(argc, argv, 0);
        c = arg_long(argc, argv, 1);
        if (a < 1 || c < 0 || (int64_t)a - 1 + c > b->n) bb_raise(5, "the range is outside the text");
        memmove(b->p + a - 1, b->p + a - 1 + c, b->n - (a - 1 + c));
        b->n -= c;
        return;
    case M_REPLACE: {                                /* Replace find, with: every occurrence */
        s = arg_str(argc, argv, 0);
        w = arg_str(argc, argv, 1);
        int32_t fl = bb_str_len(s), wl = bb_str_len(w), count = 0;
        if (fl == 0) {
            bb_str_release(s);
            bb_str_release(w);
            bb_raise(5, "the text to replace is empty");
        }
        const char *f = bb_str_ptr(s);
        char *out = malloc((size_t)b->n * (wl > fl ? (wl / fl + 1) : 1) + 1);
        int32_t o = 0;
        for (int32_t i = 0; i < b->n;) {
            if (i + fl <= b->n && !memcmp(b->p + i, f, fl)) {
                memcpy(out + o, bb_str_ptr(w), wl);
                o += wl;
                i += fl;
                count++;
            } else
                out[o++] = b->p[i++];
        }
        free(b->p);
        b->p = out;
        b->n = o;
        b->cap = o + 1;
        bb_str_release(s);
        bb_str_release(w);
        *ret = bb_v_long(count);
        return;
    }
    case M_CLEAR:
        b->n = 0;
        return;
    case P_LENGTH:
        if (set) {                                   /* shorten (or pad with spaces) */
            a = arg_long(argc, argv, argc - 1);
            if (a < 0) bb_raise(380, NULL);
            reserve(b, a);
            if (a > b->n) memset(b->p + b->n, ' ', a - b->n);
            b->n = a;
        } else
            *ret = bb_v_long(b->n);
        return;
    case P_CAPACITY:
        if (set) reserve(b, arg_long(argc, argv, argc - 1));
        else *ret = bb_v_long(b->cap);
        return;
    case M_CHAR:                                     /* Char(pos) / Char(pos) = "x" */
        a = arg_long(argc, argv, 0);
        if (a < 1 || a > b->n) bb_raise(5, "the position is outside the text");
        if (set) {
            s = arg_str(argc, argv, argc - 1);
            if (bb_str_len(s) != 1) {
                bb_str_release(s);
                bb_raise(5, "Char(pos) = takes one character");
            }
            b->p[a - 1] = bb_str_ptr(s)[0];
            bb_str_release(s);
        } else
            *ret = bb_v_str(bb_str_new(b->p + a - 1, 1));
        return;
    }
    bb_raise(438, NULL);
}

static void sb_terminate(bb_obj *self) { free(((sbuilder *)self)->p); }

static const bb_class sb_class = {
    "StringBuilder", sizeof(sbuilder), sb_find, sb_invoke, sb_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

const bb_class *bb_sbuilder_class(void) { return &sb_class; }
bb_obj *bb_sbuilder_new(void) { return bb_obj_new(&sb_class); }
