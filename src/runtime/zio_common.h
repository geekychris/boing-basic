/* zio_common.h - the zlib stream loop shared by os4/zio_os4.c and posix/zio_posix.c. Before
 * including it, define ZSTREAM (the z_stream type), Z_DEFLATEINIT2(s, level, wbits),
 * Z_INFLATEINIT2(s, wbits), Z_DEFLATE(s, flush), Z_INFLATE(s, flush), Z_DEFLATEEND(s),
 * Z_INFLATEEND(s) and zio_ready(err, errlen). */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define ZC_OK 0
#define ZC_STREAM_END 1
#define ZC_NEED_DICT 2
#define ZC_BUF_ERROR (-5)
#define ZC_FINISH 4
#define ZC_NO_FLUSH 0

static int wbits_of(int format, int decompress)
{
    if (format == BB_Z_GZIP) return 15 + 16;
    if (format == BB_Z_RAW) return -15;
    if (format == BB_Z_AUTO && decompress) return 15 + 32;
    return 15;
}

int bb_z_compress(const void *in, long inlen, int level, int format, char **out, long *outlen, char *err, int errlen)
{
    ZSTREAM s;
    long cap = inlen + inlen / 1000 + 64, n = 0;
    char *buf;
    int r;
    *out = NULL;
    *outlen = 0;
    if (!zio_ready(err, errlen)) return BB_E_NOZLIB;
    memset(&s, 0, sizeof s);
    if (level < -1 || level > 9) level = -1;
    if (Z_DEFLATEINIT2(&s, level, wbits_of(format, 0)) != ZC_OK) {
        snprintf(err, (size_t)errlen, "can't start compressing");
        return 7;
    }
    buf = malloc((size_t)cap);
    s.next_in = (void *)in;
    s.avail_in = (unsigned)inlen;
    for (;;) {
        s.next_out = (void *)(buf + n);
        s.avail_out = (unsigned)(cap - n);
        r = Z_DEFLATE(&s, ZC_FINISH);
        n = cap - s.avail_out;
        if (r == ZC_STREAM_END) break;
        if (r != ZC_OK && r != ZC_BUF_ERROR) {
            Z_DEFLATEEND(&s);
            free(buf);
            snprintf(err, (size_t)errlen, "compressing failed");
            return BB_E_ZIP;
        }
        cap *= 2;
        buf = realloc(buf, (size_t)cap);
    }
    Z_DEFLATEEND(&s);
    *out = buf;
    *outlen = n;
    return 0;
}

int bb_z_decompress(const void *in, long inlen, int format, long expect, char **out, long *outlen, long *used,
                    char *err, int errlen)
{
    ZSTREAM s;
    long cap = expect > 0 ? expect + 1 : inlen * 4 + 256, n = 0;
    char *buf;
    int r;
    *out = NULL;
    *outlen = 0;
    if (!zio_ready(err, errlen)) return BB_E_NOZLIB;
    memset(&s, 0, sizeof s);
    if (Z_INFLATEINIT2(&s, wbits_of(format, 1)) != ZC_OK) {
        snprintf(err, (size_t)errlen, "can't start decompressing");
        return 7;
    }
    buf = malloc((size_t)cap);
    s.next_in = (void *)in;
    s.avail_in = (unsigned)inlen;
    for (;;) {
        s.next_out = (void *)(buf + n);
        s.avail_out = (unsigned)(cap - n);
        r = Z_INFLATE(&s, ZC_NO_FLUSH);
        n = cap - s.avail_out;
        if (r == ZC_STREAM_END) break;
        if (r == ZC_OK && s.avail_out == 0) {
            cap *= 2;
            buf = realloc(buf, (size_t)cap);
            continue;
        }
        if (r == ZC_OK || r == ZC_BUF_ERROR) {
            if (s.avail_in == 0) {
                Z_INFLATEEND(&s);
                free(buf);
                snprintf(err, (size_t)errlen, "the compressed data ends too early");
                return BB_E_ZIP;
            }
            cap *= 2;
            buf = realloc(buf, (size_t)cap);
            continue;
        }
        Z_INFLATEEND(&s);
        free(buf);
        snprintf(err, (size_t)errlen, r == ZC_NEED_DICT ? "the data needs a dictionary" : "the compressed data is corrupt");
        return BB_E_ZIP;
    }
    if (used) *used = inlen - (long)s.avail_in;
    Z_INFLATEEND(&s);
    *out = buf;
    *outlen = n;
    return 0;
}

uint32_t bb_z_crc32(uint32_t crc, const void *p, long n)
{
    static uint32_t tab[256];
    static int ready;
    const unsigned char *b = p;
    long i;
    if (!ready) {
        uint32_t c, k;
        int j;
        for (k = 0; k < 256; k++) {
            c = k;
            for (j = 0; j < 8; j++) c = c & 1 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            tab[k] = c;
        }
        ready = 1;
    }
    crc = ~crc;
    for (i = 0; i < n; i++) crc = tab[(crc ^ b[i]) & 255] ^ (crc >> 8);
    return ~crc;
}
