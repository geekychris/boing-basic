/* main.c - the `boing` command line */
#include "../compiler/bbc.h"
#include "../vm/bytecode.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef BOING_VERSION
#define BOING_VERSION "0.1"
#endif

static void usage(void)
{
    fprintf(stderr,
            "Boing BASIC " BOING_VERSION "\n"
            "usage:\n"
            "  boing run   prog.bas|prog.bbp|prog.bbc [args]   compile to bytecode and run\n"
            "  boing build prog.bas|prog.bbp [-o out] [--keep-c] [--debug]   native executable\n"
            "  boing check prog.bas|prog.bbp                    check only (file:line:col: error: ...)\n"
            "  boing compile prog.bas -o prog.bbc               write a bytecode file\n"
            "  boing emit-c prog.bas [-o prog.c]                write the generated C\n"
            "  boing symbols file.bas|file.cls                  list declarations for an IDE\n"
            "  boing disasm prog.bas                            show the bytecode\n");
    exit(5);
}

static Program *load(const char *path)
{
    Program *p = prog_new();
    prog_load_file(p, path);
    if (p->nerrors) return p;
    prog_compile(p);
    return p;
}

static int has_ext(const char *s, const char *ext)
{
    size_t n = strlen(s), e = strlen(ext);
    return n > e && strcasecmp(s + n - e, ext) == 0;
}

/* directory holding the boing executable (for libboing.a and headers) */
static char *exe_dir(const char *argv0)
{
    const char *home = getenv("BOING_HOME");
    char buf[2048];
    const char *slash;
    if (home && *home) return xstrdup(home);
    if (strchr(argv0, '/') || strchr(argv0, ':')) snprintf(buf, sizeof buf, "%s", argv0);
    else {
        /* search PATH */
        const char *path = getenv("PATH");
        buf[0] = 0;
        if (path) {
            char *pp = xstrdup(path), *save = NULL, *d;
            for (d = strtok_r(pp, ":", &save); d; d = strtok_r(NULL, ":", &save)) {
                char cand[2048];
                snprintf(cand, sizeof cand, "%s/%s", d, argv0);
                if (access(cand, X_OK) == 0) { snprintf(buf, sizeof buf, "%s", cand); break; }
            }
            free(pp);
        }
        if (!buf[0]) return xstrdup(".");
    }
    slash = strrchr(buf, '/');
    if (!slash) return xstrdup(".");
    return xstrndup(buf, (size_t)(slash - buf));
}

static int file_exists(const char *p) { return access(p, R_OK) == 0; }

static int cmd_build(const char *argv0, const char *src, const char *out, int keep_c, int debug)
{
    Program *p = load(src);
    Buf c = {0, 0, 0};
    char *cpath, *cmd, *dir, *inc, *lib, *outp;
    const char *cc = getenv("BOING_CC");
    const char *extra = getenv("BOING_CFLAGS");
    FILE *f;
    int rc;
    if (p->nerrors) return 1;
    if (!emit_c(p, &c, debug)) return 1;
    if (out) outp = xstrdup(out);
    else {
        const char *d = strrchr(src, '.');
        outp = d ? xstrndup(src, (size_t)(d - src)) : xsprintf("%s.out", src);
    }
    cpath = xsprintf("%s.c", outp);
    f = fopen(cpath, "wb");
    if (!f) { fprintf(stderr, "boing: cannot write %s\n", cpath); return 1; }
    fwrite(c.p, 1, c.n, f);
    fclose(f);
    dir = exe_dir(argv0);
    inc = xsprintf("%s/include", dir);
    lib = xsprintf("%s", dir);
    if (!file_exists(xsprintf("%s/boing.h", inc))) {
        /* installed layout: bin/boing, lib/libboing.a, include/boing/boing.h */
        char *alt = xsprintf("%s/../include/boing", dir);
        if (file_exists(xsprintf("%s/boing.h", alt))) { inc = alt; lib = xsprintf("%s/../lib", dir); }
    }
    if (!cc || !*cc) {
#ifdef __amigaos4__
        cc = "gcc";
#else
        cc = "cc";
#endif
    }
    cmd = xsprintf("%s %s -I\"%s\" \"%s\" -o \"%s\" -L\"%s\" -lboing -lm %s", cc,
                   debug ? "-g -O0" : "-O2", inc, cpath, outp, lib, extra ? extra : "");
    rc = system(cmd);
    if (!keep_c) remove(cpath);
    if (rc != 0) {
        fprintf(stderr, "boing: C compiler failed: %s\n", cmd);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    const char *cmd;
    if (argc < 2) usage();
    cmd = argv[1];
    if (!strcmp(cmd, "--version") || !strcmp(cmd, "version")) { printf("Boing BASIC " BOING_VERSION "\n"); return 0; }
    if (argc < 3) usage();
    if (!strcmp(cmd, "check")) {
        Program *p = load(argv[2]);
        return p->nerrors ? 1 : 0;
    }
    if (!strcmp(cmd, "symbols")) {
        Program *p = prog_new();
        int i;
        p->diag_out = fopen("/dev/null", "w");
        if (!p->diag_out) p->diag_out = stderr;
        prog_load_file(p, argv[2]);
        for (i = 0; i < p->nmods; i++) print_symbols(p, p->mods[i], stdout);
        return p->nmods ? 0 : 1;
    }
    if (!strcmp(cmd, "run") || !strcmp(cmd, "disasm")) {
        VMImage *img;
        if (has_ext(argv[2], ".bbc")) {
            img = vm_load(argv[2]);
            if (!img) { fprintf(stderr, "%s: error: not a Boing BASIC bytecode file\n", argv[2]); return 20; }
        } else {
            Program *p = load(argv[2]);
            if (p->nerrors) return 20;
            img = emit_bytecode(p);
            if (!img) return 20;
        }
        if (!strcmp(cmd, "disasm")) { vm_disasm(img, stdout); return 0; }
        return vm_run(img, argc - 2, argv + 2);
    }
    if (!strcmp(cmd, "compile")) {
        const char *out = NULL;
        Program *p;
        VMImage *img;
        int i;
        for (i = 3; i < argc; i++) if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        p = load(argv[2]);
        if (p->nerrors) return 1;
        img = emit_bytecode(p);
        if (!img) return 1;
        if (!out) {
            const char *d = strrchr(argv[2], '.');
            out = d ? xsprintf("%.*s.bbc", (int)(d - argv[2]), argv[2]) : xsprintf("%s.bbc", argv[2]);
        }
        return vm_save(img, out) ? 0 : 1;
    }
    if (!strcmp(cmd, "emit-c")) {
        const char *out = NULL;
        Program *p;
        Buf c = {0, 0, 0};
        int i, debug = 0;
        for (i = 3; i < argc; i++) {
            if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
            else if (!strcmp(argv[i], "--debug")) debug = 1;
        }
        p = load(argv[2]);
        if (p->nerrors) return 1;
        if (!emit_c(p, &c, debug)) return 1;
        if (out) {
            FILE *f = fopen(out, "wb");
            if (!f) { fprintf(stderr, "boing: cannot write %s\n", out); return 1; }
            fwrite(c.p, 1, c.n, f);
            fclose(f);
        } else fwrite(c.p, 1, c.n, stdout);
        return 0;
    }
    if (!strcmp(cmd, "build")) {
        const char *out = NULL;
        int i, keep = 0, debug = 0;
        for (i = 3; i < argc; i++) {
            if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
            else if (!strcmp(argv[i], "--keep-c")) keep = 1;
            else if (!strcmp(argv[i], "--debug")) debug = 1;
            else { fprintf(stderr, "boing: unknown option %s\n", argv[i]); return 5; }
        }
        return cmd_build(argv[0], argv[2], out, keep, debug);
    }
    usage();
    return 5;
}
