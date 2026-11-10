/* counter.c - a sample Boing BASIC extension in C (docs/extensions.md): a class Counter and a
 * function Clamp. Its descriptor is counter.bbx; a project links it with Extension=counter. */
#include "boing_ext.h"

/* an instance: the object header first, then the class's own data */
typedef struct counter { bb_obj hdr; long value, count; } counter;

enum { M_ADD, M_RESET, P_VALUE, P_COUNT };
static const bb_member counter_members[] = {
    {"Add", M_ADD, BB_INV_METHOD | BB_INV_GET}, {"Reset", M_RESET, BB_INV_METHOD},
    {"Value", P_VALUE, BB_INV_GET | BB_INV_LET}, {"Count", P_COUNT, BB_INV_GET},
};

static void counter_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    counter *c = (counter *)self;
    switch (id) {
    case M_ADD:
        if (argc != 1) bb_raise(450, NULL);
        c->value += bb_arg_long(argv, 0);
        c->count++;
        *ret = bb_ret_long(c->value);
        return;
    case M_RESET: c->value = 0; c->count = 0; return;
    case P_VALUE:
        if (kind & BB_INV_LET) c->value = bb_arg_long(argv, argc - 1);      /* the new value comes last */
        else *ret = bb_ret_long(c->value);
        return;
    case P_COUNT: *ret = bb_ret_long(c->count); return;
    }
    bb_raise(438, NULL);
}

BB_CLASS(counter_class, "Counter", counter, counter_members, counter_invoke, NULL);

static bb_obj *new_counter(void) { return bb_obj_new(&counter_class); }

/* Clamp(x, lo, hi): the arguments arrive as the .bbx says (Longs) */
static bb_value clamp(int argc, bb_value *argv)
{
    bb_long x = bb_arg_long(argv, 0), lo = bb_arg_long(argv, 1), hi = bb_arg_long(argv, 2);
    (void)argc;
    return bb_ret_long(x < lo ? lo : x > hi ? hi : x);
}

BB_EXTENSION(counter)
{
    bb_register_class("Counter", &counter_class, new_counter);
    bb_register_function("Clamp", clamp);
}
