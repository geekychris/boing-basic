/* zio.h - deflate compression for Compress/Decompress, the Zip class (zip.c) and gzip
 * Content-Encoding in Http: os4/zio_os4.c on z.library (opened on first use), posix/zio_posix.c
 * on the system's zlib loaded with dlopen (so programs built by `boing build` don't link it).
 * Formats: BB_Z_ZLIB (RFC 1950), BB_Z_GZIP (RFC 1952), BB_Z_RAW (RFC 1951, as in ZIP files);
 * BB_Z_AUTO for decompressing gzip or zlib, whichever it is. */
#ifndef BB_ZIO_H
#define BB_ZIO_H
#include <stdint.h>

enum { BB_Z_ZLIB = 0, BB_Z_GZIP = 1, BB_Z_RAW = 2, BB_Z_AUTO = 3 };
#define BB_E_ZIP 31501          /* corrupt data / not a ZIP file */
#define BB_E_NOZLIB 31502       /* no zlib / z.library */

/* 1 if compression is available, else 0 with the reason in why */
int bb_z_available(char *why, int whylen);
/* compress in[0..inlen) (level 0-9, -1 default) into a malloc'd *out: 0 or an error number */
int bb_z_compress(const void *in, long inlen, int level, int format, char **out, long *outlen, char *err, int errlen);
/* decompress; *out malloc'd. expect (> 0) is the expected size when known (ZIP), else 0.
   *used (may be NULL) receives how many input bytes the stream took. 0 or an error number. */
int bb_z_decompress(const void *in, long inlen, int format, long expect, char **out, long *outlen, long *used,
                    char *err, int errlen);
uint32_t bb_z_crc32(uint32_t crc, const void *p, long n);   /* start with crc 0; works without zlib too */

#endif
