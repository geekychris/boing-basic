/* counter.c - a sample Boing BASIC extension in C (docs/extensions.md): a class Counter and a
 * function Clamp. Its descriptor is counter.bbx; a project links it with Extension=counter. */
#include "boing_ext.h"
#include <string.h>
#include <strings.h>

typedef struct counter { bb_obj hdr; long value, count; } counter;

enum { M_ADD, M_RESET, P_VALUE, P_COUNT };
static const bb_member members[] = {
    {"Add", M_ADD, BB_INV_METHOD | BB_INV_GET}, {"Reset", M_RESET, BB_INV_METHOD},
    {"Value", P_VALUE, BB_INV_GET | BB_INV_LET}, {"Count", P_COUNT, BB_INV_GET},
};

static int32_t c_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void c_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    counter *c = (counter *)self;
    switch (id) {
    case M_ADD:
        if (argc != 1) bb_raise(450, NULL);
        c->value += bb_v_to_long(&argv[0]);
        c->count++;
        *ret = bb_v_long(c->value);
        return;
    case M_RESET: c->value = 0; c->count = 0; return;
    case P_VALUE:
        if (kind & BB_INV_LET) c->value = bb_v_to_long(&argv[argc - 1]);
        else *ret = bb_v_long(c->value);
        return;
    case P_COUNT: *ret = bb_v_long(c->count); return;
    }
    bb_raise(438, NULL);
}

static const bb_class counter_class = {
    "Counter", sizeof(counter), c_find, c_invoke, NULL, NULL, members, 4, NULL, 0, NULL, NULL
};

static bb_obj *new_counter(void) { return bb_obj_new(&counter_class); }

/* Clamp(x, lo, hi): the arguments arrive as the .bbx says (Longs) */
static bb_value clamp(int argc, bb_value *argv)
{
    long x = argv[0].u.l, lo = argv[1].u.l, hi = argv[2].u.l;
    (void)argc;
    return bb_v_long(x < lo ? lo : x > hi ? hi : x);
}

BB_EXTENSION(counter)
{
    bb_register_class("Counter", &counter_class, new_counter);
    bb_register_function("Clamp", clamp);
}
