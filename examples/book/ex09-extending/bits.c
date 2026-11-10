/* bits.c - step 3: a Boing BASIC extension, a BitSet class (one bit per number) */
#include "boing_ext.h"
#include <stdlib.h>

typedef struct bitset { bb_obj hdr; long size; unsigned char *bits; } bitset;

enum { M_RESIZE, M_SETBIT, M_TESTBIT, M_SETEVERY, M_NEXTCLEAR, P_SIZE, P_COUNT };
static const bb_member bitset_members[] = {
    {"Resize", M_RESIZE, BB_INV_METHOD}, {"SetBit", M_SETBIT, BB_INV_METHOD},
    {"TestBit", M_TESTBIT, BB_INV_METHOD}, {"SetEvery", M_SETEVERY, BB_INV_METHOD},
    {"NextClear", M_NEXTCLEAR, BB_INV_METHOD},
    {"Size", P_SIZE, BB_INV_GET}, {"Count", P_COUNT, BB_INV_GET},
};

/* an index the program gave us: error 9 (subscript out of range) if it is outside the set */
static long index_of(bitset *b, const bb_value *v)
{
    long i = bb_arg_long(v, 0);
    if (i < 0 || i >= b->size) bb_raise(9, NULL);
    return i;
}

static void b_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bitset *b = (bitset *)self;
    long i, n, step;
    (void)kind; (void)argc;
    switch (id) {
    case M_RESIZE:
        n = bb_arg_long(argv, 0);
        if (n < 0) bb_raise(5, NULL);                     /* invalid procedure call */
        free(b->bits);
        b->bits = calloc((size_t)(n + 7) / 8 + 1, 1);
        if (!b->bits) { b->size = 0; bb_raise(7, NULL); }  /* out of memory */
        b->size = n;
        return;
    case M_SETBIT: i = index_of(b, &argv[0]); b->bits[i >> 3] |= (unsigned char)(1 << (i & 7)); return;
    case M_TESTBIT: i = index_of(b, &argv[0]); *ret = bb_ret_bool(b->bits[i >> 3] & (1 << (i & 7))); return;
    case M_SETEVERY:                                         /* start, start+step, ... */
        step = bb_arg_long(argv, 1);
        if (step < 1) bb_raise(5, NULL);
        for (i = bb_arg_long(argv, 0); i >= 0 && i < b->size; i += step)
            b->bits[i >> 3] |= (unsigned char)(1 << (i & 7));
        return;
    case M_NEXTCLEAR:                                        /* the first clear bit >= from, or -1 */
        for (i = bb_arg_long(argv, 0); i >= 0 && i < b->size; i++)
            if (!(b->bits[i >> 3] & (1 << (i & 7)))) { *ret = bb_ret_long(i); return; }
        *ret = bb_ret_long(-1);
        return;
    case P_SIZE: *ret = bb_ret_long(b->size); return;
    case P_COUNT:
        for (n = 0, i = 0; i < b->size; i++) n += (b->bits[i >> 3] >> (i & 7)) & 1;
        *ret = bb_ret_long(n);
        return;
    }
    bb_raise(438, NULL);
}

static void b_terminate(bb_obj *self) { free(((bitset *)self)->bits); }

BB_CLASS(bitset_class, "BitSet", bitset, bitset_members, b_invoke, b_terminate);

static bb_obj *new_bitset(void) { return bb_obj_new(&bitset_class); }

BB_EXTENSION(bits)
{
    bb_register_class("BitSet", &bitset_class, new_bitset);
}
