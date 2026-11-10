/* mathx.c - a Boing BASIC extension in C: the functions Clamp and Lerp, and a class Stats that
 * keeps the count, mean, minimum and maximum of the numbers added to it. */
#include "boing_ext.h"

/* ---- functions: the arguments arrive converted to the types in mathx.bbx (Doubles) ---- */

static bb_value clamp(int argc, bb_value *argv)
{
    double x = bb_arg_double(argv, 0), lo = bb_arg_double(argv, 1), hi = bb_arg_double(argv, 2);
    (void)argc;
    return bb_ret_double(x < lo ? lo : x > hi ? hi : x);
}

static bb_value lerp(int argc, bb_value *argv)
{
    double a = bb_arg_double(argv, 0), b = bb_arg_double(argv, 1), t = bb_arg_double(argv, 2);
    (void)argc;
    return bb_ret_double(a + (b - a) * t);
}

/* ---- the class: an instance is a bb_obj header followed by our own fields ---- */

typedef struct stats {
    bb_obj hdr;                 /* must come first */
    long count;
    double sum, min, max;
    bb_str *name;               /* a string we keep: released in stats_terminate */
} stats;

enum { M_ADD, M_CLEAR, P_COUNT, P_MEAN, P_MIN, P_MAX, P_NAME };
enum { EV_NEWMAX };             /* events: numbered in the order of mathx.bbx's event lines */

static const bb_member stats_members[] = {
    {"Add", M_ADD, BB_INV_METHOD}, {"Clear", M_CLEAR, BB_INV_METHOD},
    {"Count", P_COUNT, BB_INV_GET}, {"Mean", P_MEAN, BB_INV_GET},
    {"Min", P_MIN, BB_INV_GET}, {"Max", P_MAX, BB_INV_GET},
    {"Name", P_NAME, BB_INV_GET | BB_INV_LET},
};

/* a method call or a property read/write; a property's new value is the last argument */
static void stats_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    stats *s = (stats *)self;
    switch (id) {
    case M_ADD: {
        double x = bb_arg_double(argv, 0);
        if (s->count == 0 || x < s->min) s->min = x;
        int newmax = s->count == 0 || x > s->max;
        if (newmax) s->max = x;
        s->sum += x;
        s->count++;
        if (newmax) {                                     /* tell the program: NewMax(x) */
            bb_value a[1];
            a[0] = bb_ret_double(x);
            bb_event_raise(self, EV_NEWMAX, "NewMax", 1, a);
        }
        return;
    }
    case M_CLEAR: s->count = 0; s->sum = s->min = s->max = 0; return;
    case P_COUNT: *ret = bb_ret_long(s->count); return;
    case P_MEAN:
        if (s->count == 0) bb_raise(11, "Stats.Mean: no numbers added yet");   /* division by zero */
        *ret = bb_ret_double(s->sum / s->count);
        return;
    case P_MIN: *ret = bb_ret_double(s->min); return;
    case P_MAX: *ret = bb_ret_double(s->max); return;
    case P_NAME:
        if (kind & BB_INV_LET) {                          /* s.Name = value */
            int32_t len;
            const char *p = bb_arg_str(argv, argc - 1, &len);
            bb_str_release(s->name);
            s->name = bb_str_new(p, len);                 /* keep our own copy */
        } else {                                          /* reading s.Name */
            *ret = bb_ret_strn(bb_str_ptr(s->name), bb_str_len(s->name));
        }
        return;
    }
    bb_raise(438, NULL);                                  /* object doesn't support this */
}

static void stats_terminate(bb_obj *self)
{
    bb_str_release(((stats *)self)->name);
}

BB_CLASS(stats_class, "Stats", stats, stats_members, stats_invoke, stats_terminate);

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
