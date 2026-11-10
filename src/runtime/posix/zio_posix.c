/* zio.h on POSIX hosts: the system's zlib, loaded with dlopen on first use (libz is part of
 * macOS and nearly every Linux), so neither libboing nor native programs link against it. */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "../zio.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* zlib's z_stream (the layout every zlib 1.x uses) */
typedef struct {
    const unsigned char *next_in;
    unsigned avail_in;
    unsigned long total_in;
    unsigned char *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state;
    void *zalloc, *zfree, *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} zs;

static struct {
    int tried, ok;
    char why[160];
    int (*deflateInit2_)(zs *, int, int, int, int, int, const char *, int);
    int (*inflateInit2_)(zs *, int, const char *, int);
    int (*deflate)(zs *, int);
    int (*inflate)(zs *, int);
    int (*deflateEnd)(zs *);
    int (*inflateEnd)(zs *);
    const char *(*zlibVersion)(void);
} zl;

static int zio_ready(char *err, int errlen)
{
    static const char *const names[] = {"libz.1.dylib", "/usr/lib/libz.1.dylib", "libz.so.1", "libz.so", NULL};
    void *h = NULL;
    int i;
    if (!zl.tried) {
        zl.tried = 1;
        for (i = 0; names[i] && !h; i++) h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
        if (!h) snprintf(zl.why, sizeof zl.why, "compression needs zlib (libz), which isn't installed");
        else {
#define L(f) *(void **)&zl.f = dlsym(h, #f);
            L(deflateInit2_) L(inflateInit2_) L(deflate) L(inflate) L(deflateEnd) L(inflateEnd) L(zlibVersion)
#undef L
            if (!zl.deflateInit2_ || !zl.inflateInit2_ || !zl.deflate || !zl.inflate || !zl.deflateEnd ||
                !zl.inflateEnd || !zl.zlibVersion)
                snprintf(zl.why, sizeof zl.why, "the zlib found lacks functions");
            else
                zl.ok = 1;
        }
    }
    if (!zl.ok && err) snprintf(err, (size_t)errlen, "%s", zl.why);
    return zl.ok;
}

int bb_z_available(char *why, int whylen) { return zio_ready(why, whylen); }

#define ZSTREAM zs
#define Z_DEFLATEINIT2(s, level, wbits) zl.deflateInit2_((s), (level), 8, (wbits), 8, 0, zl.zlibVersion(), (int)sizeof(zs))
#define Z_INFLATEINIT2(s, wbits) zl.inflateInit2_((s), (wbits), zl.zlibVersion(), (int)sizeof(zs))
#define Z_DEFLATE(s, f) zl.deflate((s), (f))
#define Z_INFLATE(s, f) zl.inflate((s), (f))
#define Z_DEFLATEEND(s) zl.deflateEnd(s)
#define Z_INFLATEEND(s) zl.inflateEnd(s)
#include "../zio_common.h"
