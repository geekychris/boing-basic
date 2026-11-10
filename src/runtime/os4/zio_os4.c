/* zio.h on AmigaOS 4: z.library (zlib 1.2.11 as a shared library, in the SDK's interfaces),
 * opened on first use through a private interface pointer, like bsdsocket in net_os4.c, so a
 * program that never compresses doesn't need it. */
#include "../zio.h"

#include <stdio.h>
#include <stdlib.h>

#include <exec/exec.h>
#include <proto/exec.h>
#include <libraries/z.h>
#include <interfaces/z.h>

static struct Library *zbase;
static struct ZIFace *IZl;
static int ztried;

static void zio_cleanup(void)
{
    if (IZl) IExec->DropInterface((struct Interface *)IZl);
    if (zbase) IExec->CloseLibrary(zbase);
    IZl = NULL;
    zbase = NULL;
}

static int zio_ready(char *err, int errlen)
{
    if (!ztried) {
        ztried = 1;
        zbase = IExec->OpenLibrary("z.library", 53);
        if (zbase) IZl = (struct ZIFace *)IExec->GetInterface(zbase, "main", 1, NULL);
        if (IZl) atexit(zio_cleanup);
    }
    if (!IZl && err) snprintf(err, (size_t)errlen, "compression needs z.library (LIBS:z.library, version 53 or newer)");
    return IZl != NULL;
}

int bb_z_available(char *why, int whylen) { return zio_ready(why, whylen); }

#define ZSTREAM z_stream
#define Z_DEFLATEINIT2(s, level, wbits) IZl->DeflateInit2((s), (level), Z_DEFLATED, (wbits), 8, Z_DEFAULT_STRATEGY)
#define Z_INFLATEINIT2(s, wbits) IZl->InflateInit2((s), (wbits))
#define Z_DEFLATE(s, f) IZl->Deflate((s), (f))
#define Z_INFLATE(s, f) IZl->Inflate((s), (f))
#define Z_DEFLATEEND(s) IZl->DeflateEnd(s)
#define Z_INFLATEEND(s) IZl->InflateEnd(s)
#include "../zio_common.h"
