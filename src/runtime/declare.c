/* declare.c - Declare'd calls (bb_declare_call, used by the VM and generated C) on top of
 * the platform's call glue in bb_declare.h (os4/declare.c, posix/declare.c). */
#include "boing.h"
#include "bb_declare.h"

uint32_t bb_declare_call(bb_declare *d, int argc, const uint32_t *argv)
{
    if (!d->cache) {
        bb_decl *r = NULL;
        int err = bb_decl_resolve(d->lib, d->iface, d->version, d->name,
                                  d->alias && d->alias != d->name && d->alias[0] ? d->alias : NULL, &r);
        if (err) bb_raise(err, NULL);
        d->cache = r;
    }
    if (argc > BB_DECL_MAX_ARGS) bb_raise(450, NULL);
    return bb_decl_call((const bb_decl *)d->cache, argc, argv);
}
