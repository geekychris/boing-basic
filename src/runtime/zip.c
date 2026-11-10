/* zip.c - compression for Boing BASIC (docs/zip.md):
 *
 *   Compress(data [, format [, level]]), Decompress(data [, format]), CRC32(data)   functions
 *   Boing.Zip   ZIP archives: list, extract, create (stored or deflated entries)
 *
 *     Dim z As Zip
 *     Set z = CreateObject("Zip")
 *     z.Open "RAM:pack.zip"
 *     For i = 0 To z.Count - 1: Print z.Name(i); z.Size(i): Next
 *     z.ExtractAll "RAM:out/"
 *
 * Deflate itself is zio.h (z.library on AmigaOS, the system zlib on the host). ZIP64, encryption
 * and multi-disk archives aren't supported. */
#include "boing.h"
#include "bb_sys.h"
#include "platform.h"
#include "zio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* ---- the functions ---- */

static void raise_z(int rc, const char *err)
{
    if (rc == 7) bb_raise(7, NULL);
    bb_raise(rc, err);
}

bb_str *bb_compress(const bb_str *data, bb_long format, bb_long level)
{
    char *out, err[200];
    long n;
    int rc;
    bb_str *r;
    if (format < 0 || format > 2) bb_raise(5, "format: zipGzip, zipZlib or zipDeflate");
    rc = bb_z_compress(bb_str_ptr(data), bb_str_len(data), (int)level, (int)format, &out, &n, err, sizeof err);
    if (rc) raise_z(rc, err);
    r = bb_str_new(out, (int32_t)n);
    free(out);
    return r;
}

bb_str *bb_decompress(const bb_str *data, bb_long format)
{
    char *out, err[200];
    long n;
    int rc;
    bb_str *r;
    if (format < 0 || format > 3) bb_raise(5, "format: zipGzip, zipZlib, zipDeflate or zipAuto");
    rc = bb_z_decompress(bb_str_ptr(data), bb_str_len(data), (int)format, 0, &out, &n, NULL, err, sizeof err);
    if (rc) raise_z(rc, err);
    r = bb_str_new(out, (int32_t)n);
    free(out);
    return r;
}

bb_long bb_crc32(const bb_str *data)
{
    return (bb_long)bb_z_crc32(0, bb_str_ptr(data), bb_str_len(data));
}

/* ---- ZIP archives ---- */

typedef struct {
    char *name;
    uint16_t method, flags, mtime, mdate;
    uint32_t crc, csize, usize, offset;     /* offset of the local header */
} zentry;

enum {
    M_OPEN = 1, M_CREATE, M_CLOSE, M_NAME, M_SIZE, M_COMPRESSEDSIZE, M_ISFOLDER, M_INDEXOF, M_READ, M_EXTRACT,
    M_EXTRACTALL, M_ADDFILE, M_ADDTEXT, M_ADDFOLDER, M_FILEDATE,
    P_COUNT, P_LEVEL, P_PATH,
};
static const struct { const char *name; int id; } members[] = {
    {"Open", M_OPEN}, {"Create", M_CREATE}, {"Close", M_CLOSE}, {"Name", M_NAME}, {"Size", M_SIZE},
    {"CompressedSize", M_COMPRESSEDSIZE}, {"IsFolder", M_ISFOLDER}, {"IndexOf", M_INDEXOF}, {"Read", M_READ},
    {"Extract", M_EXTRACT}, {"ExtractAll", M_EXTRACTALL}, {"AddFile", M_ADDFILE}, {"AddText", M_ADDTEXT},
    {"AddFolder", M_ADDFOLDER}, {"FileDate", M_FILEDATE},
    {"Count", P_COUNT}, {"Level", P_LEVEL}, {"Path", P_PATH},
};

typedef struct {
    bb_obj hdr;
    FILE *f;
    int writing;
    zentry *e;
    int n, cap;
    int level;
    char *path;
} zip_obj;

static const bb_class zip_class;

static unsigned rd16(const unsigned char *p) { return p[0] | (p[1] << 8); }
static uint32_t rd32(const unsigned char *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static void wr16(unsigned char *p, unsigned v) { p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8); }
static void wr32(unsigned char *p, uint32_t v) { wr16(p, v & 0xFFFF); wr16(p + 2, v >> 16); }

static void free_entries(zip_obj *z)
{
    int i;
    for (i = 0; i < z->n; i++) free(z->e[i].name);
    z->n = 0;
}

static zentry *add_entry(zip_obj *z)
{
    if (z->n == z->cap) {
        z->cap = z->cap ? z->cap * 2 : 16;
        z->e = realloc(z->e, sizeof(zentry) * (size_t)z->cap);
    }
    memset(&z->e[z->n], 0, sizeof(zentry));
    return &z->e[z->n++];
}

static void zclose(zip_obj *z);

static void bad_zip(zip_obj *z, const char *why)
{
    char m[200];
    snprintf(m, sizeof m, "not a ZIP file, or a damaged one: %s", why);
    if (z->f && !z->writing) {
        fclose(z->f);
        z->f = NULL;
    }
    free_entries(z);
    bb_raise(BB_E_ZIP, m);
}

static void read_directory(zip_obj *z)
{
    unsigned char buf[65536 + 22];
    long size, start, i, n;
    unsigned char *eocd = NULL;
    uint32_t cdoff, cdsize;
    unsigned count;
    fseek(z->f, 0, SEEK_END);
    size = ftell(z->f);
    if (size < 22) bad_zip(z, "too short");
    start = size > (long)sizeof buf ? size - (long)sizeof buf : 0;
    fseek(z->f, start, SEEK_SET);
    n = (long)fread(buf, 1, (size_t)(size - start), z->f);
    for (i = n - 22; i >= 0; i--)
        if (buf[i] == 'P' && buf[i + 1] == 'K' && buf[i + 2] == 5 && buf[i + 3] == 6) {
            eocd = buf + i;
            break;
        }
    if (!eocd) bad_zip(z, "no end of central directory");
    count = rd16(eocd + 10);
    cdsize = rd32(eocd + 12);
    cdoff = rd32(eocd + 16);
    if (cdoff == 0xFFFFFFFFu || count == 0xFFFF) bad_zip(z, "ZIP64 archives aren't supported");
    if ((long)cdoff + (long)cdsize > size) bad_zip(z, "the directory is outside the file");
    {
        unsigned char *cd = malloc(cdsize + 1), *p;
        unsigned k;
        fseek(z->f, (long)cdoff, SEEK_SET);
        if (fread(cd, 1, cdsize, z->f) != cdsize) {
            free(cd);
            bad_zip(z, "can't read the directory");
        }
        p = cd;
        for (k = 0; k < count; k++) {
            zentry *e;
            unsigned nl, xl, cl;
            if (p + 46 > cd + cdsize || rd32(p) != 0x02014b50) {
                free(cd);
                bad_zip(z, "a broken directory entry");
            }
            nl = rd16(p + 28);
            xl = rd16(p + 30);
            cl = rd16(p + 32);
            if (p + 46 + nl + xl + cl > cd + cdsize) {
                free(cd);
                bad_zip(z, "a broken directory entry");
            }
            e = add_entry(z);
            e->flags = (uint16_t)rd16(p + 8);
            e->method = (uint16_t)rd16(p + 10);
            e->mtime = (uint16_t)rd16(p + 12);
            e->mdate = (uint16_t)rd16(p + 14);
            e->crc = rd32(p + 16);
            e->csize = rd32(p + 20);
            e->usize = rd32(p + 24);
            e->offset = rd32(p + 42);
            e->name = malloc(nl + 1);
            memcpy(e->name, p + 46, nl);
            e->name[nl] = 0;
            p += 46 + nl + xl + cl;
        }
        free(cd);
    }
}

/* the uncompressed data of entry i, malloc'd (raises on errors) */
static char *entry_data(zip_obj *z, int i, long *len)
{
    zentry *e = &z->e[i];
    unsigned char lh[30];
    char *comp, *out = NULL, err[200];
    long outlen = 0;
    int rc;
    if (!z->f || z->writing) bb_raise(5, "the archive isn't open for reading");
    if (e->flags & 1) bad_zip(z, "encrypted entries aren't supported");
    if (e->method != 0 && e->method != 8) {
        char m[100];
        snprintf(m, sizeof m, "compression method %u isn't supported (only stored and deflated)", (unsigned)e->method);
        bb_raise(BB_E_ZIP, m);
    }
    fseek(z->f, (long)e->offset, SEEK_SET);
    if (fread(lh, 1, 30, z->f) != 30 || rd32(lh) != 0x04034b50) bad_zip(z, "a broken local header");
    fseek(z->f, (long)e->offset + 30 + (long)rd16(lh + 26) + (long)rd16(lh + 28), SEEK_SET);
    comp = malloc((size_t)e->csize + 1);
    if (fread(comp, 1, e->csize, z->f) != e->csize) {
        free(comp);
        bad_zip(z, "the data of an entry is cut short");
    }
    if (e->method == 0) {
        out = comp;
        outlen = (long)e->csize;
    } else {
        rc = bb_z_decompress(comp, (long)e->csize, BB_Z_RAW, (long)e->usize, &out, &outlen, NULL, err, sizeof err);
        free(comp);
        if (rc) raise_z(rc, err);
    }
    if ((uint32_t)outlen != e->usize || bb_z_crc32(0, out, outlen) != e->crc) {
        free(out);
        {
            char m[300];
            snprintf(m, sizeof m, "%.200s is damaged (wrong size or CRC)", e->name);
            bb_raise(BB_E_ZIP, m);
        }
    }
    *len = outlen;
    return out;
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static char *arg_c(int argc, bb_value *argv, int i)
{
    bb_str *s = arg_str(argc, argv, i);
    char *c = malloc((size_t)bb_str_len(s) + 1);
    memcpy(c, bb_str_ptr(s), (size_t)bb_str_len(s));
    c[bb_str_len(s)] = 0;
    bb_str_release(s);
    return c;
}

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

/* an entry by index (from 0) or by name */
static int entry_arg(zip_obj *z, int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    int k;
    if (i >= argc) bb_raise(450, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_STRING) {
        for (k = 0; k < z->n; k++)
            if ((int32_t)strlen(z->e[k].name) == bb_str_len(v->u.s) && !memcmp(z->e[k].name, bb_str_ptr(v->u.s), (size_t)bb_str_len(v->u.s)))
                return k;
        {
            char m[300];
            snprintf(m, sizeof m, "no %.200s in the archive", bb_str_ptr(v->u.s));
            bb_raise(53, m);
        }
    }
    k = (int)bb_v_to_long(v);
    if (k < 0 || k >= z->n) bb_raise(9, NULL);
    return k;
}

/* dir + name in the platform's form; dir may end with / or : (AmigaOS volumes) */
static char *join(const char *dir, const char *name)
{
    size_t dl = strlen(dir);
    char *p = malloc(dl + strlen(name) + 2);
    strcpy(p, dir);
    if (dl && dir[dl - 1] != '/' && dir[dl - 1] != ':') strcat(p, "/");
    strcat(p, name);
    return p;
}

static void mkdirs_for(char *path, int include_last)
{
    char *p;
    for (p = path; *p; p++)
        if (*p == '/' && p > path && p[-1] != ':' && p[-1] != '/') {
            *p = 0;
            if (bb_sys_getattr(path) < 0) bb_sys_mkdir(path);
            *p = '/';
        }
    if (include_last && bb_sys_getattr(path) < 0) bb_sys_mkdir(path);
}

/* names that would leave the destination: absolute, a volume, or .. */
static int unsafe_name(const char *n)
{
    const char *p = n;
    if (n[0] == '/' || n[0] == '\\' || strchr(n, ':')) return 1;
    while (*p) {
        const char *s = p;
        while (*p && *p != '/' && *p != '\\') p++;
        if (p - s == 2 && s[0] == '.' && s[1] == '.') return 1;
        if (*p) p++;
    }
    return 0;
}

static void write_file(const char *path, const char *data, long len)
{
    FILE *f = fopen(path, "wb");
    if (!f) bb_raise(75, NULL);
    if (len > 0 && fwrite(data, 1, (size_t)len, f) != (size_t)len) {
        fclose(f);
        bb_raise(61, NULL);
    }
    if (fclose(f)) bb_raise(61, NULL);
}

static void extract_one(zip_obj *z, int i, const char *dest)
{
    zentry *e = &z->e[i];
    size_t nl = strlen(e->name);
    char *data;
    long len;
    bb_cleanup cl;
    if (nl && e->name[nl - 1] == '/') {             /* a folder */
        char *d = strdup(dest);
        size_t dl = strlen(d);
        if (dl > 1 && d[dl - 1] == '/' && d[dl - 2] != ':') d[dl - 1] = 0;
        mkdirs_for(d, 1);
        free(d);
        return;
    }
    {
        char *tmp = strdup(dest);
        mkdirs_for(tmp, 0);
        free(tmp);
    }
    data = entry_data(z, i, &len);
    cl.prev = bb_cleanups;
    cl.fn = free;
    cl.ctx = data;
    bb_cleanups = &cl;
    write_file(dest, data, len);
    bb_cleanups = cl.prev;
    free(data);
}

/* MS-DOS date and time of now */
static void dos_now(uint16_t *t, uint16_t *d)
{
    bb_tm tm;
    bb_plat_localtime(&tm);
    *t = (uint16_t)((tm.hour << 11) | (tm.minute << 5) | (tm.second / 2));
    *d = (uint16_t)(((tm.year - 1980 < 0 ? 0 : tm.year - 1980) << 9) | (tm.month << 5) | tm.day);
}

static void add_data(zip_obj *z, const char *name, const char *data, long len)
{
    unsigned char lh[30];
    zentry *e;
    char *comp = NULL, err[200];
    long clen = 0;
    int method = 0, rc;
    size_t nl = strlen(name);
    if (!z->f || !z->writing) bb_raise(5, "the archive isn't open for writing (Create)");
    if (!nl || nl > 65535 || unsafe_name(name)) bb_raise(5, "a bad name for an entry (empty, absolute or with ..)");
    if (len > 0 && z->level != 0 && !(nl && name[nl - 1] == '/')) {
        rc = bb_z_compress(data, len, z->level, BB_Z_RAW, &comp, &clen, err, sizeof err);
        if (rc) raise_z(rc, err);
        if (clen < len) method = 8;
        else {
            free(comp);
            comp = NULL;
        }
    }
    e = add_entry(z);
    e->name = strdup(name);
    e->method = (uint16_t)method;
    e->flags = 0;
    dos_now(&e->mtime, &e->mdate);
    e->crc = bb_z_crc32(0, data, len);
    e->usize = (uint32_t)len;
    e->csize = (uint32_t)(method ? clen : len);
    e->offset = (uint32_t)ftell(z->f);
    wr32(lh, 0x04034b50);
    wr16(lh + 4, 20);
    wr16(lh + 6, e->flags);
    wr16(lh + 8, e->method);
    wr16(lh + 10, e->mtime);
    wr16(lh + 12, e->mdate);
    wr32(lh + 14, e->crc);
    wr32(lh + 18, e->csize);
    wr32(lh + 22, e->usize);
    wr16(lh + 26, (unsigned)nl);
    wr16(lh + 28, 0);
    if (fwrite(lh, 1, 30, z->f) != 30 || fwrite(name, 1, nl, z->f) != nl ||
        (e->csize && fwrite(method ? comp : data, 1, e->csize, z->f) != e->csize)) {
        free(comp);
        bb_raise(61, NULL);
    }
    free(comp);
}

static char *read_file(const char *path, long *len)
{
    FILE *f = fopen(path, "rb");
    long n;
    char *b;
    if (!f) bb_raise(53, NULL);
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b = malloc((size_t)n + 1);
    if (n > 0 && fread(b, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(b);
        bb_raise(57, NULL);
    }
    fclose(f);
    *len = n;
    return b;
}

static void add_file(zip_obj *z, const char *path, const char *name)
{
    long len;
    char *data = read_file(path, &len);
    bb_cleanup cl;
    cl.prev = bb_cleanups;
    cl.fn = free;
    cl.ctx = data;
    bb_cleanups = &cl;
    add_data(z, name, data, len);
    bb_cleanups = cl.prev;
    free(data);
}

/* a folder with everything in it; names start with prefix ("" or "dir/") */
static void add_folder(zip_obj *z, const char *dir, const char *prefix, int depth)
{
    char *pat = join(dir, "*"), *nm;
    char **names = NULL;
    int n = 0, i;
    if (depth > 32) return;
    for (nm = bb_sys_dir_first(pat, 16); nm; nm = bb_sys_dir_next()) {
        if (!strcmp(nm, ".") || !strcmp(nm, "..")) {
            free(nm);
            continue;
        }
        names = realloc(names, sizeof(char *) * (size_t)(n + 1));
        names[n++] = nm;
    }
    free(pat);
    for (i = 0; i < n; i++) {
        char *full = join(dir, names[i]), *zn = malloc(strlen(prefix) + strlen(names[i]) + 2);
        sprintf(zn, "%s%s", prefix, names[i]);
        if (bb_sys_getattr(full) >= 0 && (bb_sys_getattr(full) & 16)) {
            strcat(zn, "/");
            add_data(z, zn, "", 0);
            add_folder(z, full, zn, depth + 1);
        } else
            add_file(z, full, zn);
        free(full);
        free(zn);
        free(names[i]);
    }
    free(names);
}

static void zclose(zip_obj *z)
{
    if (z->f && z->writing) {
        /* the central directory and its end record */
        uint32_t cdoff = (uint32_t)ftell(z->f), cdsize = 0;
        unsigned char h[46], end[22];
        int i, bad = 0;
        for (i = 0; i < z->n; i++) {
            zentry *e = &z->e[i];
            size_t nl = strlen(e->name);
            memset(h, 0, sizeof h);
            wr32(h, 0x02014b50);
            wr16(h + 4, 20);            /* made by: MS-DOS, version 2.0 */
            wr16(h + 6, 20);
            wr16(h + 8, e->flags);
            wr16(h + 10, e->method);
            wr16(h + 12, e->mtime);
            wr16(h + 14, e->mdate);
            wr32(h + 16, e->crc);
            wr32(h + 20, e->csize);
            wr32(h + 24, e->usize);
            wr16(h + 28, (unsigned)nl);
            wr32(h + 38, nl && e->name[nl - 1] == '/' ? 0x10 : 0);   /* external attributes: folder */
            wr32(h + 42, e->offset);
            if (fwrite(h, 1, 46, z->f) != 46 || fwrite(e->name, 1, nl, z->f) != nl) bad = 1;
            cdsize += 46 + (uint32_t)nl;
        }
        memset(end, 0, sizeof end);
        wr32(end, 0x06054b50);
        wr16(end + 8, (unsigned)z->n);
        wr16(end + 10, (unsigned)z->n);
        wr32(end + 12, cdsize);
        wr32(end + 16, cdoff);
        if (fwrite(end, 1, 22, z->f) != 22) bad = 1;
        if (fclose(z->f)) bad = 1;
        z->f = NULL;
        free_entries(z);
        if (bad) bb_raise(61, NULL);
        return;
    }
    if (z->f) fclose(z->f);
    z->f = NULL;
    free_entries(z);
}

static void z_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    zip_obj *z = (zip_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char *a, *b;
    int i;
    switch (id) {
    case M_OPEN:
    case M_CREATE:
        a = arg_c(argc, argv, 0);
        zclose(z);
        z->f = fopen(a, id == M_OPEN ? "rb" : "wb");
        free(z->path);
        z->path = a;
        if (!z->f) bb_raise(id == M_OPEN ? 53 : 75, NULL);
        z->writing = id == M_CREATE;
        if (id == M_OPEN) read_directory(z);
        return;
    case M_CLOSE:
        zclose(z);
        return;
    case P_COUNT:
        *ret = bb_v_long(z->n);
        return;
    case P_PATH:
        *ret = bb_v_str(bb_str_from_c(z->path ? z->path : ""));
        return;
    case P_LEVEL:
        if (set) {
            int32_t l = arg_long(argc, argv, argc - 1);
            if (l < 0 || l > 9) bb_raise(380, "Level is 0 (store) to 9");
            z->level = (int)l;
        } else
            *ret = bb_v_long(z->level);
        return;
    case M_NAME:
        *ret = bb_v_str(bb_str_from_c(z->e[entry_arg(z, argc, argv, 0)].name));
        return;
    case M_SIZE:
        *ret = bb_v_double((double)z->e[entry_arg(z, argc, argv, 0)].usize);
        return;
    case M_COMPRESSEDSIZE:
        *ret = bb_v_double((double)z->e[entry_arg(z, argc, argv, 0)].csize);
        return;
    case M_ISFOLDER: {
        const char *n = z->e[entry_arg(z, argc, argv, 0)].name;
        *ret = bb_v_bool(*n && n[strlen(n) - 1] == '/');
        return;
    }
    case M_FILEDATE: {
        zentry *e = &z->e[entry_arg(z, argc, argv, 0)];
        int y = 1980 + (e->mdate >> 9), mo = (e->mdate >> 5) & 15, d = e->mdate & 31;
        int h = e->mtime >> 11, mi = (e->mtime >> 5) & 63, s = (e->mtime & 31) * 2;
        if (mo < 1) mo = 1;
        if (d < 1) d = 1;
        *ret = bb_v_date(bb_dateserial(y, mo, d) + (h * 3600 + mi * 60 + s) / 86400.0);
        return;
    }
    case M_INDEXOF: {
        bb_str *s = arg_str(argc, argv, 0);
        int found = -1;
        for (i = 0; i < z->n && found < 0; i++)
            if ((int32_t)strlen(z->e[i].name) == bb_str_len(s) && !strncasecmp(z->e[i].name, bb_str_ptr(s), (size_t)bb_str_len(s)))
                found = i;
        bb_str_release(s);
        *ret = bb_v_long(found);
        return;
    }
    case M_READ: {
        long len;
        char *d = entry_data(z, entry_arg(z, argc, argv, 0), &len);
        *ret = bb_v_str(bb_str_new(d, (int32_t)len));
        free(d);
        return;
    }
    case M_EXTRACT: {           /* Extract entry, path: one entry to a file */
        int k = entry_arg(z, argc, argv, 0);
        a = arg_c(argc, argv, 1);
        {
            bb_cleanup cl;
            cl.prev = bb_cleanups;
            cl.fn = free;
            cl.ctx = a;
            bb_cleanups = &cl;
            extract_one(z, k, a);
            bb_cleanups = cl.prev;
        }
        free(a);
        return;
    }
    case M_EXTRACTALL: {        /* ExtractAll folder: everything, with its folders; returns the count */
        int count = 0;
        a = arg_c(argc, argv, 0);
        for (i = 0; i < z->n; i++) {
            char *dest;
            bb_cleanup cl;
            if (unsafe_name(z->e[i].name)) continue;       /* never outside the folder */
            dest = join(a, z->e[i].name);
            cl.prev = bb_cleanups;
            cl.fn = free;
            cl.ctx = dest;
            bb_cleanups = &cl;
            extract_one(z, i, dest);
            bb_cleanups = cl.prev;
            free(dest);
            count++;
        }
        free(a);
        *ret = bb_v_long(count);
        return;
    }
    case M_ADDFILE: {           /* AddFile path [, nameInArchive] */
        a = arg_c(argc, argv, 0);
        if (present(argc, argv, 1)) b = arg_c(argc, argv, 1);
        else {
            const char *base = a + strlen(a);
            while (base > a && base[-1] != '/' && base[-1] != ':') base--;
            b = strdup(base);
        }
        {
            bb_cleanup c1, c2;
            c1.prev = bb_cleanups;
            c1.fn = free;
            c1.ctx = a;
            c2.prev = &c1;
            c2.fn = free;
            c2.ctx = b;
            bb_cleanups = &c2;
            add_file(z, a, b);
            bb_cleanups = c1.prev;
        }
        free(a);
        free(b);
        return;
    }
    case M_ADDTEXT: {           /* AddText name, data */
        bb_str *d;
        a = arg_c(argc, argv, 0);
        d = arg_str(argc, argv, 1);
        {
            bb_cleanup c1;
            c1.prev = bb_cleanups;
            c1.fn = free;
            c1.ctx = a;
            bb_cleanups = &c1;
            add_data(z, a, bb_str_ptr(d), bb_str_len(d));
            bb_cleanups = c1.prev;
        }
        free(a);
        bb_str_release(d);
        return;
    }
    case M_ADDFOLDER: {         /* AddFolder path [, nameInArchive] */
        char *prefix;
        a = arg_c(argc, argv, 0);
        if (bb_sys_getattr(a) < 0 || !(bb_sys_getattr(a) & 16)) {
            free(a);
            bb_raise(76, NULL);
        }
        if (present(argc, argv, 1)) b = arg_c(argc, argv, 1);
        else b = strdup("");
        prefix = malloc(strlen(b) + 2);
        strcpy(prefix, b);
        if (*prefix && prefix[strlen(prefix) - 1] != '/') strcat(prefix, "/");
        if (*prefix) add_data(z, prefix, "", 0);
        add_folder(z, a, prefix, 0);
        free(a);
        free(b);
        free(prefix);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t z_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void z_terminate(bb_obj *self)
{
    zip_obj *z = (zip_obj *)self;
    /* an archive being written is finished (as Close does), errors ignored */
    bb_errframe f;
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        zclose(z);
        bb_frame_pop(&f);
    } else
        bb_frame_pop(&f);
    free(z->e);
    free(z->path);
}

static const bb_class zip_class = {
    "Zip", sizeof(zip_obj), z_find, z_invoke, z_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_zip_class(void) { return &zip_class; }
bb_obj *bb_zip_new(void)
{
    zip_obj *z = (zip_obj *)bb_obj_new(&zip_class);
    z->level = 6;
    return &z->hdr;
}
