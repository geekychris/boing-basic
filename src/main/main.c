/* main.c - the `boing` command line */
#include "../compiler/bbc.h"
#include "../vm/bytecode.h"
#include "../vm/jit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../runtime/bb_sys.h"
#include "../compiler/rtmembers.h"

#ifndef BOING_VERSION
#define BOING_VERSION "0.1"
#endif

static void usage(void)
{
    fprintf(stderr,
            "Boing BASIC " BOING_VERSION "\n"
            "usage:\n"
            "  boing run   [--error-file F] prog.bas|prog.bbp|prog.bbc [args]   compile to bytecode and run\n"
            "  boing build prog.bas|prog.bbp [-o out] [--keep-c] [--debug] [--opt 0|1|2|s] [--target host|os4]\n"
            "  boing check prog.bas|prog.bbp                    check only (file:line:col: error: ...)\n"
            "  boing compile prog.bas -o prog.bbc               write a bytecode file\n"
            "  boing emit-c prog.bas [-o prog.c]                write the generated C\n"
            "  boing symbols file.bas|file.cls                  list declarations for an IDE\n"
            "  boing disasm prog.bas                            show the bytecode\n  boing members [Engine3D|Canvas|Audio|Http]       members of the runtime classes (completion)\n");
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
#ifdef __amigaos4__
    /* AmigaOS: PROGDIR: is the directory boing was loaded from (no PATH variable, and "."
       isn't the current directory there); the BOING: assign, if any, wins */
    (void)argv0; (void)slash;
    {
        /* gcc and its tools don't know PROGDIR: (it's per process): hand them the real path */
        /* never access() a volume that may not exist: AmigaDOS asks the user to insert it */
        const char *assign = bb_sys_probe("BOING:include/boing.h") ? "BOING:" : "PROGDIR:";
        char *real = bb_sys_real_path(assign);
        (void)buf;
        return real ? real : xstrdup(assign);
    }
#endif
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
    /* --opt N / BOING_OPT: the C optimisation level (-O2 by default; -O0 compiles fastest,
       which matters with the SDK GCC on the Amiga) */
    const char *optenv = getenv("BOING_OPT");
    const char *opt = optenv && *optenv ? xsprintf("-O%s", optenv[0] == '-' ? optenv + 2 : optenv) : "-O2";
    FILE *f;
    int rc;
    if (p->nerrors) return 1;
    if (out) outp = xstrdup(out);
    else {
        const char *d = strrchr(src, '.');
        outp = d ? xstrndup(src, (size_t)(d - src)) : xsprintf("%s.out", src);
    }
    cpath = xsprintf("%s.c", outp);
    p->c_name = cpath;
    if (!emit_c(p, &c, debug)) return 1;
    f = fopen(cpath, "wb");
    if (!f) { fprintf(stderr, "boing: cannot write %s\n", cpath); return 1; }
    fwrite(c.p, 1, c.n, f);
    fclose(f);
    dir = exe_dir(argv0);
    /* "Work:Boing" + "/include"; but "PROGDIR:" + "include" */
    {
        size_t dl = strlen(dir);
        const char *sep = dl && (dir[dl - 1] == ':' || dir[dl - 1] == '/') ? "" : "/";
        inc = xsprintf("%s%sinclude", dir, sep);
        /* libboing.a in <dir>/lib/ (BOING:lib/, docs/os4.md) or beside boing */
        lib = file_exists(xsprintf("%s%slib/libboing.a", dir, sep)) ? xsprintf("%s%slib", dir, sep) : xsprintf("%s", dir);
    }
    if (!file_exists(xsprintf("%s/boing.h", inc))) {
        /* installed layout: bin/boing, lib/libboing.a, include/boing/boing.h */
        char *alt = xsprintf("%s/../include/boing", dir);
        if (file_exists(xsprintf("%s/boing.h", alt))) { inc = alt; lib = xsprintf("%s/../lib", dir); }
    }
    if (!cc || !*cc) {
#ifdef __amigaos4__
        /* the SDK's native GCC 11; a shell without sdk-startup has no path to it */
        cc = bb_sys_probe("SDK:gcc/bin/gcc") ? "SDK:gcc/bin/gcc" : "gcc";
#else
        cc = "cc";
#endif
    }
#ifdef __amigaos4__
    /* never -mcpu=440/440fp: GCC then inlines string functions with dlmzb., which only the
       440/460 has (real X5000, A1222 and G3/G4 machines crash); see docs/os4.md */
    /* AmigaDOS only strips quotes that open an argument: quote the whole "-I..." / "-L..." */
    cmd = xsprintf("%s -mcrt=newlib -mcpu=powerpc %s -D__USE_OLD_TIMEVAL__ \"-I%s\" \"%s\" -o \"%s\" \"-L%s\" "
                   "-lboing -lauto -lm %s", cc, debug ? "-gstabs -O0" : opt, inc, cpath, outp, lib, extra ? extra : "");   /* AmiForge's debugger reads stabs */
#else
    cmd = xsprintf("%s %s -I\"%s\" \"%s\" -o \"%s\" -L\"%s\" -lboing -lm %s", cc,
                   debug ? "-g -O0" : opt, inc, cpath, outp, lib, extra ? extra : "");
#endif
    rc = system(cmd);
    if (!keep_c) remove(cpath);
    if (rc != 0) {
        fprintf(stderr, "boing: C compiler failed: %s\n", cmd);
        return 1;
    }
    return 0;
}

#ifdef __amigaos4__
/* the shell gives a command this much stack (the compiler and the VM recurse); see also
   tools/stackcheck.sh, which keeps every frame small for launchers that ignore the cookie */
static const char __attribute__((used)) boing_stack_cookie[] = "$STACK:1048576";
#endif

/* the directory of the program file (App.Path under `boing run`): "DH1:a/b.bbp" -> "DH1:a",
   "DH1:b.bbp" -> "DH1:", "b.bbp" -> the current directory */
static char *program_dir(const char *path)
{
    char *d = strdup(path), *s = strrchr(d, '/'), *c = strrchr(d, ':');
    if (c && (!s || c > s)) c[1] = 0;
    else if (s && s == d) s[1] = 0;
    else if (s) *s = 0;
#ifdef __amigaos4__
    else d[0] = 0;              /* "" locks the current directory */
#else
    else strcpy(d, ".");
#endif
    return d;
}

int main(int argc, char **argv)
{
    const char *cmd;
    if (argc < 2) usage();
    cmd = argv[1];
    if (!strcmp(cmd, "--version") || !strcmp(cmd, "version")) { printf("Boing BASIC " BOING_VERSION "\n"); return 0; }
    if (argc < 3 && strcmp(cmd, "members")) usage();
    if (!strcmp(cmd, "members")) {
        /* boing members [Class]: the members of the runtime classes (Engine3D, Canvas, Audio), one per
           line "Class<TAB>Name<TAB>method|property", for AmiForge's completion; each name is checked
           against the class's own find() (exit 1 if one does not resolve) */
        size_t i;
        int bad = 0;
        const char *want = argc > 2 ? argv[2] : NULL;
        if (want && !strncasecmp(want, "Boing.", 6)) want += 6;
        for (i = 0; i < sizeof bb_rtmembers / sizeof bb_rtmembers[0]; i++) {
            const bb_class *rc = bb_runtime_class(bb_rtmembers[i].cls);
            if (want && strcasecmp(want, bb_rtmembers[i].cls)) continue;
            if (!rc || rc->find(rc, bb_rtmembers[i].name) == BB_NOMEMBER) {
                fprintf(stderr, "boing members: %s.%s does not resolve\n", bb_rtmembers[i].cls, bb_rtmembers[i].name);
                bad = 1;
                continue;
            }
            printf("%s\t%s\t%s\n", bb_rtmembers[i].cls, bb_rtmembers[i].name, bb_rtmembers[i].kind);
        }
        return bad;
    }
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
        /* options before the program: --error-file FILE */
        while (argc > 3 && argv[2][0] == '-') {
            if (!strcmp(argv[2], "--error-file") && argc > 4) {
                setenv("BOING_ERROR_FILE", argv[3], 1);
                remove(argv[3]);
                argv += 2; argc -= 2;
            } else if (!strcmp(argv[2], "--jit") || !strcmp(argv[2], "--no-jit")) {
                setenv("BOING_JIT", argv[2][2] == 'j' ? "1" : "0", 1);
                argv += 1; argc -= 1;
            } else if (!strcmp(argv[2], "--jit-force")) {
                setenv("BOING_JIT", "force", 1);
                argv += 1; argc -= 1;
            } else if (!strcmp(argv[2], "-v") || !strcmp(argv[2], "--verbose")) {
                setenv("BOING_VERBOSE", "1", 1);
                argv += 1; argc -= 1;
            } else { fprintf(stderr, "boing: unknown option %s\n", argv[2]); return 5; }
        }
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
        bb_rt_set_app_dir(program_dir(argv[2]));
        return vm_run(img, argc - 2, argv + 2);
    }
    if (!strcmp(cmd, "jitdump")) {
        /* boing jitdump prog.bas out.bin [ppc|arm64]: compile every loop region with a JIT
         * backend and write the raw code (for disassembly: objdump -D -b binary) */
        Program *p;
        VMImage *img;
        const JBackend *be = (argc > 4 && !strcmp(argv[4], "arm64")) ? &jit_arm64 : &jit_ppc32;
        FILE *f;
        int32_t i, pc;
        if (argc < 4) usage();
        p = load(argv[2]);
        if (p->nerrors) return 1;
        img = emit_bytecode(p);
        if (!img) return 1;
        f = fopen(argv[3], "wb");
        if (!f) return 1;
        for (i = 0; i < img->nprocs; i++) {
            VMProc *vp = &img->procs[i];
            int32_t end = img->ncode, k;
            if (vp->code < 0) continue;
            for (k = 0; k < img->nprocs; k++) if (img->procs[k].code > vp->code && img->procs[k].code < end) end = img->procs[k].code;
            for (pc = vp->code; pc < end; pc += 1 + bb_opwords[img->code[pc]]) {
                const int32_t *w = img->code + pc;
                int32_t tg = -1;
                JA *a = (JA *)calloc(1, sizeof(JA));   /* ~112 KB: never on the stack (OS4 runs us on 64 KB) */
                switch (w[0]) {
                case I_R_FORINC_I: case I_R_FORINC_L: case I_R_FORINC_D: case I_R_JCMP_LRR: case I_R_JCMP_LRI:
                case I_R_JCMP_IRR: case I_R_JCMP_IRI: case I_R_JCMP_DRR: case I_R_JCMP_DRK: case I_R_JCMP_FRR: tg = w[4]; break;
                case I_R_JNZ: case I_R_JZ: tg = w[2]; break;
                case I_R_JMP: tg = w[1]; break;
                case I_R_JF1Z: tg = w[5]; break;
                case I_R_FORSKIPF: tg = w[4]; break;
                case I_R_JCMPF1_LI: tg = w[6]; break;
                /* resume points after a call / Sqr (the VM re-enters compiled code there) */
                case I_R_CALLS: case I_R_SQRT_D: tg = pc + 1 + bb_opwords[w[0]]; break;
                default: break;
                }
                if (!a) return 7;
                if (tg < 0 || (tg > pc && w[0] != I_R_CALLS && w[0] != I_R_SQRT_D)) { free(a); continue; }
                if (jit_compile_region(be, img, vp, tg, a, NULL)) {
                    fprintf(stderr, "%s @%ld: %d bytes at offset %ld\n", vp->name, (long)tg, a->n, ftell(f));
                    fwrite(a->buf, 1, (size_t)a->n, f);
                }
                free(a->buf);
                free(a);
            }
        }
        fclose(f);
        return 0;
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
        const char *out = NULL, *target = NULL;
        int i, keep = 0, debug = 0;
        for (i = 3; i < argc; i++) {
            if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
            else if (!strcmp(argv[i], "--keep-c")) keep = 1;
            else if (!strcmp(argv[i], "--debug")) debug = 1;
            else if (!strcmp(argv[i], "--target") && i + 1 < argc) target = argv[++i];
            else if (!strcmp(argv[i], "--opt") && i + 1 < argc) setenv("BOING_OPT", argv[++i], 1);
            else { fprintf(stderr, "boing: unknown option %s\n", argv[i]); return 5; }
        }
        if (target && strcmp(target, "os4") == 0) {
            /* cross build from the host: tools/boing-build-os4.sh (Docker) */
            char *dir = exe_dir(argv[0]);
            char *script = xsprintf("%s/../tools/boing-build-os4.sh", dir);
            char *c;
            if (!file_exists(script)) { fprintf(stderr, "boing: %s not found\n", script); return 10; }
            c = xsprintf("BOING=\"%s/boing\" sh \"%s\" \"%s\"%s%s%s%s%s", dir, script, argv[2], out ? " -o \"" : "", out ? out : "",
                         out ? "\"" : "", keep ? " --keep-c" : "", debug ? " --debug" : "");
            return system(c) == 0 ? 0 : 1;
        }
        if (target && strcmp(target, "host") != 0) { fprintf(stderr, "boing: unknown target %s (host, os4)\n", target); return 5; }
        return cmd_build(argv[0], argv[2], out, keep, debug);
    }
    usage();
    return 5;
}
