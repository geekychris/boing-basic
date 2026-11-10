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
int bb_ext_class_count(void);
const char *bb_ext_class_name(int i);
int bb_ext_linked(const char *ext);                     /* an extension's init ran */
void bb_ext_mark_linked(const char *ext);

/* BB_EXTENSION(name) { ... } defines bb_ext_init_name(), run once before the program starts */
#define BB_EXTENSION(name) \
    static void bb_ext_body_##name(void); \
    void bb_ext_init_##name(void) { bb_ext_mark_linked(#name); bb_ext_body_##name(); } \
    static void bb_ext_body_##name(void)

#ifdef __cplusplus
}
#endif
#endif
