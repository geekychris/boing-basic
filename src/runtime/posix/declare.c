/* Declare on hosts without Amiga libraries: nothing can be resolved. */
#include "../bb_declare.h"

#include <stddef.h>

int bb_decl_resolve(const char *lib, const char *iface, int version, const char *name, const char *alias,
                    bb_decl **out)
{
    (void)lib; (void)iface; (void)version; (void)name; (void)alias;
    *out = NULL;
    return 48;
}

uint32_t bb_decl_call(const bb_decl *d, int argc, const uint32_t *argv)
{
    (void)d; (void)argc; (void)argv;
    return 0;
}

void *bb_decl_interface(const bb_decl *d) { (void)d; return NULL; }
void bb_decl_cleanup(void) {}
