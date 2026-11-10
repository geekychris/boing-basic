/* mathx.c - a Boing BASIC extension in C: the functions Clamp and Lerp, and a class Stats that
 * keeps the count, mean, minimum and maximum of the numbers added to it. */
#include "boing_ext.h"
#include <strings.h>

/* ---- functions: the arguments arrive converted to the types in mathx.bbx (Doubles) ---- */

static bb_value clamp(int argc, bb_value *argv)
{
    double x = argv[0].u.d, lo = argv[1].u.d, hi = argv[2].u.d;
    (void)argc;
    return bb_v_double(x < lo ? lo : x > hi ? hi : x);
}

static bb_value lerp(int argc, bb_value *argv)
{
    (void)argc;
    return bb_v_double(argv[0].u.d + (argv[1].u.d - argv[0].u.d) * argv[2].u.d);
}

/* ---- the class: an instance is a bb_obj header followed by our own fields ---- */

typedef struct stats {
    bb_obj hdr;                 /* must come first */
    long count;
    double sum, min, max;
    bb_str *name;               /* a reference we own: released in s_terminate */
} stats;

enum { M_ADD, M_CLEAR, P_COUNT, P_MEAN, P_MIN, P_MAX, P_NAME };

static const bb_member members[] = {
    {"Add", M_ADD, BB_INV_METHOD}, {"Clear", M_CLEAR, BB_INV_METHOD},
    {"Count", P_COUNT, BB_INV_GET}, {"Mean", P_MEAN, BB_INV_GET},
    {"Min", P_MIN, BB_INV_GET}, {"Max", P_MAX, BB_INV_GET},
    {"Name", P_NAME, BB_INV_GET | BB_INV_LET},
};

/* name -> member id (the compiler has already checked names against mathx.bbx) */
static int32_t s_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

/* a call or a property read/write; for a write the new value is the last argument */
static void s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    stats *s = (stats *)self;
    switch (id) {
    case M_ADD: {
        double x = bb_v_to_double(&argv[0]);
        if (s->count == 0 || x < s->min) s->min = x;
        if (s->count == 0 || x > s->max) s->max = x;
        s->sum += x;
        s->count++;
        return;
    }
    case M_CLEAR: s->count = 0; s->sum = s->min = s->max = 0; return;
    case P_COUNT: *ret = bb_v_long(s->count); return;
    case P_MEAN:
        if (s->count == 0) bb_raise(11, "Stats.Mean: no numbers added yet");   /* division by zero */
        *ret = bb_v_double(s->sum / s->count);
        return;
    case P_MIN: *ret = bb_v_double(s->min); return;
    case P_MAX: *ret = bb_v_double(s->max); return;
    case P_NAME:
        if (kind & BB_INV_LET) {
            bb_str *old = s->name;
            s->name = bb_v_to_str(&argv[argc - 1]);      /* owned copy of the new value */
            bb_str_release(old);
        } else {
            *ret = bb_v_str(bb_str_from_c(bb_str_ptr(s->name)));
        }
        return;
    }
    bb_raise(438, NULL);                                 /* object doesn't support this */
}

static void s_terminate(bb_obj *self)
{
    bb_str_release(((stats *)self)->name);
}

static const bb_class stats_class = {
    "Stats", sizeof(stats), s_find, s_invoke, s_terminate, NULL,
    members, sizeof members / sizeof members[0], NULL, 0, NULL, NULL
};

static bb_obj *new_stats(void)
{
    return bb_obj_new(&stats_class);     /* zeroed, reference count 1 */
}

BB_EXTENSION(mathx)
{
    bb_register_function("Clamp", clamp);
    bb_register_function("Lerp", lerp);
    bb_register_class("Stats", &stats_class, new_stats);
}
