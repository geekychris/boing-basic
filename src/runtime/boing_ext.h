/* boing_ext.h - linked extensions for Boing BASIC (docs/extensions.md, manual chapter 18).
 *
 * An extension is a C or C++ file that registers classes (for CreateObject and Dim x As Name)
 * and functions (callable like built-ins), plus a descriptor name.bbx that tells the compiler
 * their members and signatures. Native builds link it through the project key Extension=dir/name;
 * for the VM, `boing vm --ext dir/name -o myboing` builds an interpreter that includes it.
 *
 *     #include "boing_ext.h"
 *     static bb_value clamp(int argc, bb_value *argv) { ... return bb_v_long(r); }
 *     BB_EXTENSION(mathx) { bb_register_function("Clamp", clamp); }
 */
#ifndef BOING_EXT_H
#define BOING_EXT_H
#include "boing.h"

#ifdef __cplusplus
extern "C" {
#endif

/* a class: name as in CreateObject("name") / CreateObject("Boing.name") and As name
   (case-insensitive); create makes a new instance (reference count 1) */
void bb_register_class(const char *name, const bb_class *cls, bb_obj *(*create)(void));
/* a function: name as called from BASIC; argv holds the arguments converted to the types in the
   .bbx signature (Variants for As Variant); return an owned value */
typedef bb_value (*bb_ext_fn)(int argc, bb_value *argv);
void bb_register_function(const char *name, bb_ext_fn fn);

/* lookups (the runtime and the compiler use these) */
const bb_class *bb_runtime_class(const char *name);     /* NULL if not registered */
bb_obj *bb_ext_create(const char *name);                /* NULL if not registered */
bb_ext_fn bb_ext_function(const char *name);            /* NULL if not registered */
/* call a registered function (error 453 if it is not linked into this program) */
bb_value bb_ext_call(const char *name, int argc, bb_value *argv);
int bb_ext_class_count(void);
const char *bb_ext_class_name(int i);
int bb_ext_linked(const char *ext);                     /* an extension's init ran */
void bb_ext_mark_linked(const char *ext);

/* the stable helpers for extension code (instead of reading bb_value fields) */
/* arguments: argv[i] as declared in the .bbx (Long, Double, String, Boolean, Object) */
static inline bb_long bb_arg_long(const bb_value *argv, int i) { return bb_v_to_long(&argv[i]); }
static inline double bb_arg_double(const bb_value *argv, int i) { return bb_v_to_double(&argv[i]); }
static inline int bb_arg_bool(const bb_value *argv, int i) { return bb_v_to_bool(&argv[i]) != 0; }
/* a String argument as a C string (valid during the call) and its length (may contain NULs) */
static inline const char *bb_arg_str(const bb_value *argv, int i, int32_t *len)
{
    const bb_str *s = argv[i].type == BB_STRING ? argv[i].u.s : NULL;
    if (len) *len = bb_str_len(s);
    return bb_str_ptr(s);
}
static inline bb_obj *bb_arg_obj(const bb_value *argv, int i) { return argv[i].type == BB_OBJECT ? argv[i].u.o : NULL; }
/* results: return one of these from a function, or store it in *ret from a class's invoke */
static inline bb_value bb_ret_long(bb_long x) { return bb_v_long(x); }
static inline bb_value bb_ret_double(double x) { return bb_v_double(x); }
static inline bb_value bb_ret_bool(int x) { return bb_v_bool(x); }
static inline bb_value bb_ret_str(const char *s) { return bb_v_str(bb_str_from_c(s)); }
static inline bb_value bb_ret_strn(const char *s, int32_t n) { return bb_v_str(bb_str_new(s, n)); }
static inline bb_value bb_ret_obj(bb_obj *owned) { return bb_v_obj(owned); }
static inline bb_value bb_ret_empty(void) { return bb_v_empty(); }
/* errors: bb_raise(number, "message") (does not return) */

/* a class in a few lines: instances are a struct starting with `bb_obj hdr;`; members a
   bb_member table {name, id, BB_INV_xxx kinds}; invoke switches on the id.
     typedef struct { bb_obj hdr; long value; } Counter;
     static const bb_member counter_members[] = {{"Add", 0, BB_INV_METHOD}, ...};
     static void counter_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret);
     BB_CLASS(counter_class, "Counter", Counter, counter_members, counter_invoke, NULL);
   terminate (or NULL) runs when the last reference goes (free what the instance owns). */
#define BB_CLASS(var, name, type, members, invoke, terminate) \
    static const bb_class var = {name, sizeof(type), bb_class_find_default, invoke, terminate, NULL, \
                                 members, (int32_t)(sizeof(members) / sizeof((members)[0])), NULL, 0, NULL, NULL}

/* BB_EXTENSION(name) { ... } defines bb_ext_init_name() (C linkage, also from C++), run once
   before the program starts */
#ifdef __cplusplus
#define BB_EXT_LINKAGE extern "C"
#else
#define BB_EXT_LINKAGE
#endif
#define BB_EXTENSION(name) \
    static void bb_ext_body_##name(void); \
    BB_EXT_LINKAGE void bb_ext_init_##name(void); \
    BB_EXT_LINKAGE void bb_ext_init_##name(void) { bb_ext_mark_linked(#name); bb_ext_body_##name(); } \
    static void bb_ext_body_##name(void)

#ifdef __cplusplus
}
#endif
#endif
