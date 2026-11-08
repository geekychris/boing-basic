/* callback.c - AddressOf: native entry points for BASIC procedures.
 *
 * A fixed pool of C stub functions; AddressOf binds a free stub to a procedure and returns
 * the stub's address. When the OS (a hook, a callback taking up to 8 32-bit arguments) calls
 * the stub, it calls the procedure with Long arguments through bb_call_proc, which catches
 * BASIC errors, so no long jump ever crosses the OS's frames. An error not handled inside
 * the callback is fatal (reported, exit 20), like an error in an event handler. The result
 * is the Function's value as a 32-bit integer (0 for a Sub).
 */
#include "boing.h"
#include <string.h>

#define BB_NCALLBACKS 32
#define CB_ARGS uint32_t a0, uint32_t a1, uint32_t a2, uint32_t a3, uint32_t a4, uint32_t a5, uint32_t a6, uint32_t a7

static struct { void *proc; int nargs; } cbs[BB_NCALLBACKS];

static uint32_t run(int i, CB_ARGS)
{
    uint32_t a[8];
    bb_value argv[8], ret = bb_v_empty();
    int k, n = cbs[i].nargs;
    uint32_t r;
    a[0] = a0; a[1] = a1; a[2] = a2; a[3] = a3; a[4] = a4; a[5] = a5; a[6] = a6; a[7] = a7;
    if (n > 8) n = 8;
    for (k = 0; k < n; k++) argv[k] = bb_v_long((bb_long)a[k]);
    if (bb_call_proc(cbs[i].proc, n, argv, &ret) != 0) bb_fatal_error();
    r = ret.type == BB_EMPTY ? 0 : (uint32_t)bb_v_to_long(&ret);
    bb_v_release(&ret);
    return r;
}

#define STUB(i) static uint32_t cb##i(CB_ARGS) { return run(i, a0, a1, a2, a3, a4, a5, a6, a7); }
STUB(0) STUB(1) STUB(2) STUB(3) STUB(4) STUB(5) STUB(6) STUB(7)
STUB(8) STUB(9) STUB(10) STUB(11) STUB(12) STUB(13) STUB(14) STUB(15)
STUB(16) STUB(17) STUB(18) STUB(19) STUB(20) STUB(21) STUB(22) STUB(23)
STUB(24) STUB(25) STUB(26) STUB(27) STUB(28) STUB(29) STUB(30) STUB(31)

typedef uint32_t (*cbfn)(CB_ARGS);
static const cbfn stubs[BB_NCALLBACKS] = {
    cb0, cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8, cb9, cb10, cb11, cb12, cb13, cb14, cb15,
    cb16, cb17, cb18, cb19, cb20, cb21, cb22, cb23, cb24, cb25, cb26, cb27, cb28, cb29, cb30, cb31
};

void *bb_addressof_ptr(const char *module, const char *name, int nargs)
{
    void *p = bb_find_proc(module, name);
    int i;
    if (!p) bb_raise(453, NULL);
    for (i = 0; i < BB_NCALLBACKS; i++)
        if (cbs[i].proc == p) return (void *)stubs[i];
    for (i = 0; i < BB_NCALLBACKS; i++)
        if (!cbs[i].proc) {
            cbs[i].proc = p;
            cbs[i].nargs = nargs;
            return (void *)stubs[i];
        }
    bb_raise(7, NULL);      /* out of callback slots */
    return NULL;
}

/* AddressOf as a VB Long: the address on 32-bit targets (OS4). On 64-bit hosts only the low
   32 bits fit, which is enough to compare or pass around; Declare'd calls do not exist there. */
bb_long bb_addressof(const char *module, const char *name, int nargs)
{
    return (bb_long)(uint32_t)(uintptr_t)bb_addressof_ptr(module, name, nargs);
}
