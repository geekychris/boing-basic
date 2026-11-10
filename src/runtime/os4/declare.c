/* Declare on AmigaOS 4: open the library (or device), get the interface and call the function
 * through the interface's function table.
 *
 * An OS4 interface is `struct InterfaceData Data;` followed by one function pointer per
 * method, in the order of the SDK's interfaces/<lib>.xml (Obtain, Release, Expunge, Clone,
 * then the library's own functions). Slot n is the n-th pointer. Every function takes the
 * interface itself as its first argument (Self). */
#include "../bb_declare.h"
#include "os4_slots.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <exec/interfaces.h>
#include <proto/exec.h>

struct opened {
    struct opened *next;
    char *lib, *iface;
    struct Library *base;
    struct Interface *ifc;
    struct IORequest *io;       /* devices */
    struct MsgPort *port;
};

struct bb_decl {
    struct Interface *ifc;
    void *fn;
    int slot;
};

static struct opened *opened;

static struct opened *open_interface(const char *lib, const char *iface, int version)
{
    for (struct opened *o = opened; o; o = o->next)
        if (!strcasecmp(o->lib, lib) && !strcasecmp(o->iface, iface))
            return version > 0 && o->base->lib_Version < version ? NULL : o;
    struct opened *o = calloc(1, sizeof *o);
    if (!o) return NULL;
    size_t n = strlen(lib);
    if (n > 7 && !strcasecmp(lib + n - 7, ".device")) {
        /* a device's interface: open unit 0 just to reach the device base */
        o->port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
        o->io = o->port ? IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, 256, ASOIOR_ReplyPort, o->port,
                                                    TAG_DONE)
                        : NULL;
        if (o->io && IExec->OpenDevice(lib, 0, o->io, 0) == 0) {
            o->base = (struct Library *)o->io->io_Device;
        } else {
            if (o->io) IExec->FreeSysObject(ASOT_IOREQUEST, o->io);
            if (o->port) IExec->FreeSysObject(ASOT_PORT, o->port);
            free(o);
            return NULL;
        }
    } else {
        o->base = IExec->OpenLibrary(lib, version > 0 ? version : 0);
        if (!o->base) { free(o); return NULL; }
        if (version > 0 && o->base->lib_Version < version) {
            IExec->CloseLibrary(o->base);
            free(o);
            return NULL;
        }
    }
    o->ifc = IExec->GetInterface(o->base, iface, 1, NULL);
    if (!o->ifc) {
        if (o->io) {
            IExec->CloseDevice(o->io);
            IExec->FreeSysObject(ASOT_IOREQUEST, o->io);
            IExec->FreeSysObject(ASOT_PORT, o->port);
        } else
            IExec->CloseLibrary(o->base);
        free(o);
        return NULL;
    }
    o->lib = strdup(lib);
    o->iface = strdup(iface);
    o->next = opened;
    opened = o;
    return o;
}

static int cmp_slot(const char *lib, const char *iface, const char *name, const struct bb_slot *s)
{
    int c = strcasecmp(lib, s->lib);
    if (!c) c = strcasecmp(iface, s->iface);
    if (!c) c = strcasecmp(name, s->name);
    return c;
}

static int find_slot(const char *lib, const char *iface, const char *name)
{
    int lo = 0, hi = bb_num_slots - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        int c = cmp_slot(lib, iface, name, &bb_slots[mid]);
        if (!c) return bb_slots[mid].slot;
        if (c < 0) hi = mid - 1;
        else lo = mid + 1;
    }
    return -1;
}

int bb_decl_resolve(const char *lib, const char *iface, int version, const char *name, const char *alias,
                    bb_decl **out)
{
    *out = NULL;
    if (!iface || !*iface) iface = "main";
    int slot = -1;
    if (alias && alias[0] == '#') slot = atoi(alias + 1);
    else slot = find_slot(lib, iface, alias && *alias ? alias : name);
    struct opened *o;
    if (slot < 4) {
        /* not found, or Obtain/Release/Expunge/Clone: 48 if the library itself does not open (a
           misspelt name), else 453 (no such function in it) */
        o = open_interface(lib, iface, version);
        return o ? 453 : 48;
    }
    o = open_interface(lib, iface, version);
    if (!o) return 48;
    /* Data.PositiveSize: InterfaceData + the function vector */
    uint32 size = o->ifc->Data.PositiveSize;
    if (size && sizeof(struct InterfaceData) + (slot + 1) * sizeof(void *) > size) return 453;
    void **vec = (void **)((char *)o->ifc + sizeof(struct InterfaceData));
    if (!vec[slot]) return 453;
    struct bb_decl *d = malloc(sizeof *d);
    if (!d) return 7;               /* Out of memory */
    d->ifc = o->ifc;
    d->fn = vec[slot];
    d->slot = slot;
    *out = d;
    return 0;
}

/* All arguments are 32-bit integers in r4..r10 and then on the stack (Self in r3). Under the
 * SysV PPC ABI the caller owns the argument area, so calling a function with more arguments
 * than it takes is harmless: one stub with Self + 12 covers every function. */
typedef uint32 (*call12)(struct Interface *, uint32, uint32, uint32, uint32, uint32, uint32, uint32, uint32,
                         uint32, uint32, uint32, uint32);

uint32_t bb_decl_call(const bb_decl *d, int argc, const uint32_t *argv)
{
    uint32 a[BB_DECL_MAX_ARGS] = { 0 };
    if (argc > BB_DECL_MAX_ARGS) argc = BB_DECL_MAX_ARGS;
    for (int i = 0; i < argc; i++) a[i] = argv[i];
    call12 f = (call12)d->fn;
    return f(d->ifc, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]);
}

void *bb_decl_interface(const bb_decl *d) { return d ? d->ifc : NULL; }

void bb_decl_cleanup(void)
{
    while (opened) {
        struct opened *o = opened;
        opened = o->next;
        IExec->DropInterface(o->ifc);
        if (o->io) {
            IExec->CloseDevice(o->io);
            IExec->FreeSysObject(ASOT_IOREQUEST, o->io);
            IExec->FreeSysObject(ASOT_PORT, o->port);
        } else
            IExec->CloseLibrary(o->base);
        free(o->lib);
        free(o->iface);
        free(o);
    }
}
