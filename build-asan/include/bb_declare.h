/* Calls to OS library functions for `Declare ... Lib "x.library" Interface "main"`.
 * Implemented per platform: src/runtime/os4/declare.c (AmigaOS 4: OpenLibrary + GetInterface,
 * call through the interface's function table) and src/runtime/posix/declare.c (no OS
 * libraries: every resolve fails with 453).
 *
 * Arguments and the result are 32-bit words; the caller marshals BASIC values (ByVal String ->
 * pointer to a NUL-terminated copy, ByRef -> pointer to a temporary copied back, ...). */
#ifndef BB_DECLARE_H
#define BB_DECLARE_H

#include <stdint.h>

#define BB_DECL_MAX_ARGS 12

typedef struct bb_decl bb_decl;

/* Find a function. lib: "dos.library"; iface: "main" (NULL = "main"); version: the minimum
 * library version (0 = any); name: the Declare's name; alias: its Alias string or NULL
 * ("#n" = slot n, otherwise the real function name). The library is opened on the first
 * resolve and stays open until bb_decl_cleanup().
 * Returns 0 and *out, or a VB error number: 48 "Error in loading DLL" (library or interface
 * can't be opened), 453 "Can't find DLL entry point" (no such function). */
int bb_decl_resolve(const char *lib, const char *iface, int version, const char *name, const char *alias,
                    bb_decl **out);

/* Call it with argc (0..BB_DECL_MAX_ARGS) 32-bit arguments. */
uint32_t bb_decl_call(const bb_decl *d, int argc, const uint32_t *argv);

/* The library base / interface pointer of a resolved function (for VarPtr-style use). */
void *bb_decl_interface(const bb_decl *d);

/* Close every library opened for Declares (at program end). */
void bb_decl_cleanup(void);

#endif
