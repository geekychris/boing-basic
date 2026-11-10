/* dict.c - Boing.Dictionary (docs/dictionary.md):
 *
 *     Dim d As Dictionary
 *     Set d = CreateObject("Dictionary")
 *     d("apple") = 3                      ' Item is the default member: adds or replaces
 *     If d.Exists("apple") Then Print d("apple")
 *     For Each k In d: Print k; " = "; d(k): Next
 *
 * Keys are strings, numbers (all numeric types: 1, 1& and 1# are the same key) or objects (by
 * identity); entries keep insertion order. CompareMode = 1 makes string keys case-insensitive.
 * Open addressing over an index table; the entries array is compacted when half of it is
 * removed entries. */
#include "dict.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

enum { K_NUM = 1, K_STR, K_OBJ, K_EMPTY };

typedef struct {
    bb_value key, value;
    uint32_t hash;
    uint8_t kind;               /* K_..., 0 = removed */
} entry;

typedef struct {
    bb_obj hdr;
    entry *e;
    int32_t n, cap;             /* entries used (with removed ones) / allocated */
    int32_t live;
    int32_t *idx;               /* index table: entry number + 1, 0 = empty, -1 = removed */
    int32_t isize;              /* power of two */
    int text;                   /* CompareMode: 0 binary, 1 text */
} dict;

enum {
    P_ITEM = 0 /* default member */, M_ADD = 1, M_EXISTS, M_REMOVE, M_REMOVEALL, M_KEYS, M_ITEMS, P_COUNT,
    P_COMPAREMODE, P_KEY,
};

static const struct { const char *name; int id; } members[] = {
    {"Item", P_ITEM}, {"Add", M_ADD}, {"Exists", M_EXISTS}, {"Remove", M_REMOVE}, {"RemoveAll", M_REMOVEALL},
    {"Keys", M_KEYS}, {"Items", M_ITEMS}, {"Count", P_COUNT}, {"CompareMode", P_COMPAREMODE}, {"Key", P_KEY},
};

/* --- keys --------------------------------------------------------------------------------- */

static uint32_t fnv(const unsigned char *p, size_t n, int fold)
{
    uint32_t h = 2166136261u;
    while (n--) {
        unsigned char c = *p++;
        if (fold) c = (unsigned char)tolower(c);
        h = (h ^ c) * 16777619u;
    }
    return h;
}

/* classify a key: its kind and hash; error 5 for keys that can't be (arrays, Null) */
static int key_kind(const dict *d, const bb_value *k, uint32_t *hash)
{
    switch (k->type) {
    case BB_EMPTY:
        *hash = 0x9e3779b9u;
        return K_EMPTY;
    case BB_STRING:
        *hash = fnv((const unsigned char *)bb_str_ptr(k->u.s), bb_str_len(k->u.s), d->text);
        return K_STR;
    case BB_OBJECT: {
        uintptr_t p = (uintptr_t)k->u.o;
        *hash = (uint32_t)(p >> 3) * 2654435761u;
        return K_OBJ;
    }
    case BB_INTEGER: case BB_LONG: case BB_SINGLE: case BB_DOUBLE: case BB_CURRENCY: case BB_DATE:
    case BB_BOOLEAN: case BB_BYTE: case BB_DECIMAL: {
        double x = bb_v_to_double(k);
        if (x == 0) x = 0;                          /* -0 and 0 are one key */
        if (x == floor(x) && fabs(x) < 9e15) {
            long long i = (long long)x;
            *hash = fnv((const unsigned char *)&i, sizeof i, 0);
        } else
            *hash = fnv((const unsigned char *)&x, sizeof x, 0);
        return K_NUM;
    }
    default:
        bb_raise(5, "a Dictionary key must be a string, a number or an object");
    }
}

static int key_eq(const dict *d, const entry *e, int kind, const bb_value *k)
{
    if (e->kind != kind) return 0;
    switch (kind) {
    case K_EMPTY: return 1;
    case K_STR: return bb_str_cmp(e->key.u.s, k->u.s, d->text) == 0;
    case K_OBJ: return e->key.u.o == k->u.o;
    case K_NUM: return bb_v_to_double(&e->key) == bb_v_to_double(k);
    }
    return 0;
}

/* --- table -------------------------------------------------------------------------------- */

static void reindex(dict *d, int32_t isize)
{
    free(d->idx);
    d->isize = isize;
    d->idx = calloc(isize, sizeof *d->idx);
    for (int32_t i = 0; i < d->n; i++) {
        if (!d->e[i].kind) continue;
        uint32_t m = isize - 1, j = d->e[i].hash & m;
        while (d->idx[j]) j = (j + 1) & m;
        d->idx[j] = i + 1;
    }
}

/* the entry number of key, or -1; *slot gets the index slot (found, or where it would go) */
static int32_t lookup(dict *d, const bb_value *key0, int *kind, uint32_t *hash, int32_t *slot)
{
    bb_value t;
    const bb_value *key = bb_v_deref(key0, &t);
    *kind = key_kind(d, key, hash);
    if (!d->isize) {
        *slot = -1;
        return -1;
    }
    uint32_t m = d->isize - 1, j = *hash & m;
    int32_t first_free = -1;
    for (;;) {
        int32_t v = d->idx[j];
        if (v == 0) {
            *slot = first_free >= 0 ? first_free : (int32_t)j;
            return -1;
        }
        if (v < 0) {
            if (first_free < 0) first_free = (int32_t)j;
        } else {
            entry *e = &d->e[v - 1];
            if (e->hash == *hash && key_eq(d, e, *kind, key)) {
                *slot = (int32_t)j;
                return v - 1;
            }
        }
        j = (j + 1) & m;
    }
}

static void compact(dict *d)
{
    int32_t w = 0;
    for (int32_t i = 0; i < d->n; i++)
        if (d->e[i].kind) d->e[w++] = d->e[i];
    d->n = w;
    reindex(d, d->isize);
}

static void insert(dict *d, const bb_value *key0, const bb_value *value)
{
    bb_value t;
    const bb_value *key = bb_v_deref(key0, &t);
    int kind;
    uint32_t hash;
    int32_t slot;
    int32_t i = lookup(d, key, &kind, &hash, &slot);
    if (i >= 0) {
        bb_v_assign(&d->e[i].value, value);
        return;
    }
    int moved = 0;
    if (d->n + 1 > d->cap) {
        if (d->live < d->n / 2 && d->n > 16) {
            compact(d);
            moved = 1;
        }
        if (d->n + 1 > d->cap) {
            d->cap = d->cap ? d->cap * 2 : 8;
            d->e = realloc(d->e, d->cap * sizeof *d->e);
        }
    }
    if ((d->n + 1) * 2 > d->isize) {               /* keep the index at most half full */
        reindex(d, d->isize ? d->isize * 2 : 16);
        moved = 1;
    }
    if (moved) lookup(d, key, &kind, &hash, &slot);
    entry *e = &d->e[d->n];
    bb_v_copy(&e->key, key);
    bb_v_copy(&e->value, value);
    e->hash = hash;
    e->kind = (uint8_t)kind;
    d->idx[slot] = ++d->n;
    d->live++;
}

static void remove_at(dict *d, int32_t i, int32_t slot)
{
    bb_v_release(&d->e[i].key);
    bb_v_release(&d->e[i].value);
    d->e[i].kind = 0;
    d->idx[slot] = -1;
    d->live--;
}

static void clear(dict *d)
{
    for (int32_t i = 0; i < d->n; i++)
        if (d->e[i].kind) {
            bb_v_release(&d->e[i].key);
            bb_v_release(&d->e[i].value);
        }
    free(d->e);
    free(d->idx);
    d->e = NULL;
    d->idx = NULL;
    d->n = d->cap = d->live = d->isize = 0;
}

/* --- C API (json.c) ------------------------------------------------------------------------ */

void bb_dict_set(bb_obj *o, const bb_value *key, const bb_value *value) { insert((dict *)o, key, value); }

const bb_value *bb_dict_get(bb_obj *o, const bb_value *key)
{
    int kind;
    uint32_t hash;
    int32_t slot;
    int32_t i = lookup((dict *)o, key, &kind, &hash, &slot);
    return i >= 0 ? &((dict *)o)->e[i].value : NULL;
}

int32_t bb_dict_count(bb_obj *o) { return ((dict *)o)->live; }

void bb_dict_entry(bb_obj *o, int32_t n, const bb_value **key, const bb_value **value)
{
    dict *d = (dict *)o;
    for (int32_t i = 0; i < d->n; i++)
        if (d->e[i].kind && n-- == 0) {
            *key = &d->e[i].key;
            *value = &d->e[i].value;
            return;
        }
    bb_raise(9, NULL);
}

/* --- the class ---------------------------------------------------------------------------- */

static int32_t d_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return P_ITEM;
    for (size_t i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static bb_value array_of(dict *d, int keys)
{
    bb_array *a = bb_arr_new1(BB_VARIANT, 0, d->live - 1);
    int32_t k = 0;
    for (int32_t i = 0; i < d->n; i++)
        if (d->e[i].kind) {
            bb_value *dst = (bb_value *)bb_arr_elem1(a, k++);
            bb_v_assign(dst, keys ? &d->e[i].key : &d->e[i].value);
        }
    return bb_v_arr(a);
}

static void need(int argc, int n)
{
    if (argc < n) bb_raise(450, NULL);
}

static void d_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    dict *d = (dict *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    int k;
    uint32_t h;
    int32_t slot, i;
    bb_value t;
    switch (id) {
    case P_ITEM:
        if (set) {
            need(argc, 2);
            insert(d, &argv[0], bb_v_deref(&argv[argc - 1], &t));
        } else {
            need(argc, 1);
            i = lookup(d, &argv[0], &k, &h, &slot);
            if (i >= 0) bb_v_copy(ret, &d->e[i].value);     /* a missing key reads as Empty */
        }
        return;
    case M_ADD:
        need(argc, 2);
        if (lookup(d, &argv[0], &k, &h, &slot) >= 0) bb_raise(457, "the key is already in the Dictionary");
        insert(d, &argv[0], bb_v_deref(&argv[1], &t));
        return;
    case M_EXISTS:
        need(argc, 1);
        *ret = bb_v_bool(lookup(d, &argv[0], &k, &h, &slot) >= 0);
        return;
    case M_REMOVE:
        need(argc, 1);
        i = lookup(d, &argv[0], &k, &h, &slot);
        if (i < 0) bb_raise(5, "the key isn't in the Dictionary");
        remove_at(d, i, slot);
        return;
    case M_REMOVEALL:
        clear(d);
        return;
    case M_KEYS: *ret = array_of(d, 1); return;
    case M_ITEMS: *ret = array_of(d, 0); return;
    case P_COUNT:
        if (set) bb_raise(383, NULL);
        *ret = bb_v_long(d->live);
        return;
    case P_COMPAREMODE:
        if (set) {
            int32_t m = (int32_t)bb_v_to_long(bb_v_deref(&argv[argc - 1], &t));
            if (m < 0 || m > 1) bb_raise(380, NULL);
            if (d->live) bb_raise(5, "CompareMode can only be changed while the Dictionary is empty");
            d->text = m;
        } else
            *ret = bb_v_long(d->text);
        return;
    case P_KEY: {                                   /* d.Key(old) = new: renames, keeping the place */
        if (!set) bb_raise(438, NULL);
        need(argc, 2);
        i = lookup(d, &argv[0], &k, &h, &slot);
        if (i < 0) bb_raise(5, "the key isn't in the Dictionary");
        const bb_value *nk = bb_v_deref(&argv[argc - 1], &t);
        int32_t s2;
        int k2;
        uint32_t h2;
        if (lookup(d, nk, &k2, &h2, &s2) >= 0) bb_raise(457, "the key is already in the Dictionary");
        /* keep the order: replace in place and rebuild the index */
        bb_value old = d->e[i].key;
        bb_v_copy(&d->e[i].key, nk);
        bb_v_release(&old);
        d->e[i].kind = (uint8_t)k2;
        d->e[i].hash = h2;
        reindex(d, d->isize);
        return;
    }
    }
    bb_raise(438, NULL);
}

static void d_terminate(bb_obj *self) { clear((dict *)self); }

/* For Each k In d: the keys, in insertion order */
static int d_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    dict *d = (dict *)self;
    int32_t i = state->type == BB_LONG ? state->u.l : 0;
    while (i < d->n && !d->e[i].kind) i++;
    if (i >= d->n) return 0;
    bb_v_copy(out, &d->e[i].key);
    *state = bb_v_long(i + 1);
    return 1;
}

static const bb_class dict_class = {
    "Dictionary", sizeof(dict), d_find, d_invoke, d_terminate, d_iterate, NULL, 0, NULL, 0, NULL, NULL
};

const bb_class *bb_dict_class(void) { return &dict_class; }
bb_obj *bb_dict_new(void) { return bb_obj_new(&dict_class); }
int bb_is_dict(const bb_obj *o) { return o && o->cls == &dict_class; }
