/* main.c - the `boing` command line */
#include "../compiler/bbc.h"
#include "../vm/bytecode.h"
#include "../vm/jit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../runtime/bb_sys.h"
#include "../runtime/boing_ext.h"
#include "../compiler/rtmembers.h"

/* AmigaOS 4's libstdc++ is built with thread support: C++ objects and links need -athread=native */
#ifdef __amigaos4__
#define CXX_THREADS " -athread=native"
#else
#define CXX_THREADS ""
#endif


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
            "  boing disasm prog.bas                            show the bytecode\n  boing extensions                                 the extensions linked into this interpreter\n  boing members [Engine3D|Canvas|Audio|Http]       members of the runtime classes (completion)\n  boing vm [--project P.bbp] [--ext DIR/NAME] [--csource F.c] [--target os4] -o OUT   an interpreter with extensions\n");
    exit(5);
}

static const char *g_argv0 = "boing";
static char *exe_dir(const char *argv0);
static char *home_dir(void) { static char *h; if (!h) h = exe_dir(g_argv0); return h; }

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
    {
        /* the linked extensions' and CSource= files, each compiled to an object (C++ with the C++
           driver); with any C++ the C++ driver links too (its runtime library) */
        Buf objs = {0, 0, 0};
        int k, cxx = 0;
        const char *cxxc = getenv("BOING_CXX");
#ifdef __amigaos4__
        const char *fl = "-mcrt=newlib -mcpu=powerpc -D__USE_OLD_TIMEVAL__", *q1 = "\"-I", *q2 = "\"";
        if (!cxxc || !*cxxc) cxxc = bb_sys_probe("SDK:gcc/bin/g++") ? "SDK:gcc/bin/g++" : "g++";
#else
        const char *fl = "", *q1 = "-I\"", *q2 = "\"";
        if (!cxxc || !*cxxc) cxxc = "c++";
#endif
        const char *o2 = debug ?
#ifdef __amigaos4__
            "-gstabs -O0"
#else
            "-g -O0"
#endif
            : opt;
        buf_puts(&objs, "");
        for (k = 0; k < p->nexts + p->ncsources; k++) {
            const char *f = k < p->nexts ? p->exts[k].src : p->csources[k - p->nexts];
            size_t n2 = strlen(f);
            int isx = (n2 > 4 && !strcasecmp(f + n2 - 4, ".cpp")) || (n2 > 3 && !strcasecmp(f + n2 - 3, ".cc"));
            char *o = xsprintf("%s.x%d.o", outp, k);
            char *c1 = xsprintf("%s %s%s %s %s%s%s -c \"%s\" -o \"%s\"", isx ? cxxc : cc, fl, isx ? CXX_THREADS : "", o2, q1, inc, q2, f, o);
            if (system(c1) != 0) { fprintf(stderr, "boing: %s compiler failed: %s\n", isx ? "C++" : "C", c1); return 1; }
            buf_printf(&objs, " \"%s\"", o);
            if (isx) cxx = 1;
        }
        /* never -mcpu=440/440fp on AmigaOS 4: GCC then inlines string functions with dlmzb., which
           only the 440/460 has (real X5000, A1222 and G3/G4 machines crash); see docs/os4.md.
           AmigaDOS only strips quotes that open an argument: quote the whole "-I..." / "-L..." */
#ifdef __amigaos4__
        cmd = xsprintf("%s %s%s %s %s%s%s %s\"%s\"%s%s -o \"%s\" \"-L%s\" -lboing%s -lauto -lm %s", cxx ? cxxc : cc, fl, cxx ? CXX_THREADS : "", o2, q1, inc, q2,
                       cxx ? "-x c " : "", cpath, cxx ? " -x none" : "", objs.p, outp, lib, bbx_link_flags(p, 1), extra ? extra : "");
#else
        cmd = xsprintf("%s %s %s%s%s %s\"%s\"%s%s -o \"%s\" -L\"%s\" -lboing%s -lm %s", cxx ? cxxc : cc, o2, q1, inc, q2,
                       cxx ? "-x c " : "", cpath, cxx ? " -x none" : "", objs.p, outp, lib, bbx_link_flags(p, 0), extra ? extra : "");
        (void)fl;
#endif
    }
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

#ifdef __amigaos4__
int bb_wb_start(int *argc, char ***argv);     /* wbstart.c: a Workbench project start */
#endif
void bb_vm_ext_init(void);     /* vmext_default.c, or a `boing vm` interpreter's glue */

static const char *glue_ctype(Type *t)
{
    switch (t->kind) {
    case T_INTEGER: return "int16_t";
    case T_BYTE: return "uint8_t";
    case T_BOOLEAN: return "int";
    case T_SINGLE: return "float";
    case T_DOUBLE: return "double";
    case T_STRING: return "const char *";
    default: return "int32_t";
    }
}

/* boing vm [--project P.bbp] [--ext DIR/NAME]... [--csource F.c]... -o OUT: an interpreter with
   linked extensions and CSource= C functions (their Declare ... Lib "C" from the project) */
static int cmd_vm(const char *argv0, int argc, char **argv)
{
    const char *out = NULL, *proj = NULL, *target = NULL;
    char **exts = NULL, **csrc = NULL, *dir, *inc, *lib, *gpath, *cmd;
    int nexts = 0, ncsrc = 0, i, k, cxx = 0;
    Program *p = NULL;
    Buf g = {0, 0, 0}, objs = {0, 0, 0};
    const char *cc = getenv("BOING_CC"), *cxxc = getenv("BOING_CXX");
    FILE *f;
    for (i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "--project") && i + 1 < argc) proj = argv[++i];
        else if (!strcmp(argv[i], "--ext") && i + 1 < argc) { exts = (char **)xrealloc(exts, sizeof(char *) * (size_t)(nexts + 1)); exts[nexts++] = argv[++i]; }
        else if (!strcmp(argv[i], "--csource") && i + 1 < argc) { csrc = (char **)xrealloc(csrc, sizeof(char *) * (size_t)(ncsrc + 1)); csrc[ncsrc++] = argv[++i]; }
        else if (!strcmp(argv[i], "--target") && i + 1 < argc) target = argv[++i];
        else { fprintf(stderr, "boing vm: unknown option %s\n", argv[i]); return 5; }
    }
    if (!out) { fprintf(stderr, "usage: boing vm [--project P.bbp] [--ext DIR/NAME]... [--csource F.c]... -o OUT\n"); return 5; }
    if (proj) {
        p = load(proj);
        if (p->nerrors) return 1;
    }
    /* the sources to compile: --ext DIR/NAME -> DIR/NAME.c or .cpp; the project's own */
    {
        char **src = NULL, **names = NULL;
        int ns = 0, nn = 0;
        Program *xp = prog_new();       /* the --ext descriptors: their link lines */
        char *links_os4, *links_host;
        for (k = 0; k < nexts; k++) {
            char *bx = xsprintf("%s.bbx", exts[k]);
            const char *sl = strrchr(exts[k], '/');
            if (file_exists(bx)) bbx_load(xp, bx, sl ? sl + 1 : exts[k]);
        }
        links_os4 = xsprintf("%s%s", p ? bbx_link_flags(p, 1) : "", bbx_link_flags(xp, 1));
        links_host = xsprintf("%s%s", p ? bbx_link_flags(p, 0) : "", bbx_link_flags(xp, 0));
        (void)links_os4; (void)links_host;
        for (k = 0; k < nexts; k++) {
            const char *b = exts[k], *sl = strrchr(b, '/');
            char *c1 = xsprintf("%s.c", b);
            if (!file_exists(c1)) c1 = xsprintf("%s.cpp", b);
            src = (char **)xrealloc(src, sizeof(char *) * (size_t)(ns + 1)); src[ns++] = c1;
            names = (char **)xrealloc(names, sizeof(char *) * (size_t)(nn + 1)); names[nn++] = xstrdup(sl ? sl + 1 : b);
        }
        for (k = 0; p && k < p->nexts; k++) {
            src = (char **)xrealloc(src, sizeof(char *) * (size_t)(ns + 1)); src[ns++] = p->exts[k].src;
            names = (char **)xrealloc(names, sizeof(char *) * (size_t)(nn + 1)); names[nn++] = p->exts[k].name;
        }
        for (k = 0; k < ncsrc; k++) { src = (char **)xrealloc(src, sizeof(char *) * (size_t)(ns + 1)); src[ns++] = csrc[k]; }
        for (k = 0; p && k < p->ncsources; k++) { src = (char **)xrealloc(src, sizeof(char *) * (size_t)(ns + 1)); src[ns++] = p->csources[k]; }
        /* the glue: extension inits, Lib "C" wrappers taking Variant arguments */
        buf_puts(&g, "/* generated by boing vm: the linked extensions and Lib \"C\" functions of this interpreter */\n#include \"boing_ext.h\"\n#include <stdint.h>\n");
        for (k = 0; k < nn; k++) buf_printf(&g, "void bb_ext_init_%s(void);\n", names[k]);
        for (k = 0; p && k < p->nprocs; k++) {
            Proc *pr = p->procs[k];
            int j;
            if (pr->kind != PK_DECLARE || !pr->clib) continue;
            buf_printf(&g, "%s %s(", pr->ret ? glue_ctype(pr->ret) : "void", pr->alias);
            for (j = 0; j < pr->nparams; j++) buf_printf(&g, "%s%s", j ? ", " : "", glue_ctype(pr->params[j].ty));
            buf_printf(&g, "%s);\nstatic bb_value bbg_%d(int argc, bb_value *a)\n{\n    (void)argc; (void)a;\n    ", pr->nparams ? "" : "void", k);
            {
                Buf call = {0, 0, 0};
                buf_printf(&call, "%s(", pr->alias);
                for (j = 0; j < pr->nparams; j++) {
                    int tk = pr->params[j].ty->kind;
                    const char *sep = j ? ", " : "";
                    if (tk == T_STRING) buf_printf(&call, "%sbb_str_ptr(a[%d].type == BB_STRING ? a[%d].u.s : NULL)", sep, j, j);
                    else if (tk == T_SINGLE || tk == T_DOUBLE) buf_printf(&call, "%s(%s)bb_v_to_double(&a[%d])", sep, glue_ctype(pr->params[j].ty), j);
                    else if (tk == T_BOOLEAN) buf_printf(&call, "%s(int)bb_v_to_bool(&a[%d])", sep, j);
                    else buf_printf(&call, "%s(%s)bb_v_to_long(&a[%d])", sep, glue_ctype(pr->params[j].ty), j);
                }
                buf_puts(&call, ")");
                if (!pr->ret) buf_printf(&g, "%s;\n    return bb_v_empty();\n}\n", call.p);
                else switch (pr->ret->kind) {
                case T_STRING: buf_printf(&g, "return bb_v_str(bb_str_from_c(%s));\n}\n", call.p); break;
                case T_DOUBLE: buf_printf(&g, "return bb_v_double(%s);\n}\n", call.p); break;
                case T_SINGLE: buf_printf(&g, "return bb_v_single(%s);\n}\n", call.p); break;
                case T_INTEGER: buf_printf(&g, "return bb_v_int(%s);\n}\n", call.p); break;
                case T_BYTE: buf_printf(&g, "return bb_v_byte(%s);\n}\n", call.p); break;
                case T_BOOLEAN: buf_printf(&g, "return bb_v_bool(%s);\n}\n", call.p); break;
                default: buf_printf(&g, "return bb_v_long(%s);\n}\n", call.p); break;
                }
            }
        }
        buf_puts(&g, "void bb_vm_ext_init(void)\n{\n");
        for (k = 0; k < nn; k++) buf_printf(&g, "    bb_ext_init_%s();\n", names[k]);
        for (k = 0; p && k < p->nprocs; k++) {
            Proc *pr = p->procs[k];
            if (pr->kind == PK_DECLARE && pr->clib) buf_printf(&g, "    bb_register_function(\"%s\", bbg_%d);\n", pr->name, k);
        }
        buf_puts(&g, "}\n");
        gpath = xsprintf("%s.glue.c", out);
        f = fopen(gpath, "wb");
        if (!f) { fprintf(stderr, "boing vm: cannot write %s\n", gpath); return 1; }
        fwrite(g.p, 1, g.n, f);
        fclose(f);
        dir = exe_dir(argv0);
        if (target && !strcmp(target, "os4")) {
            /* cross build: tools/boing-vm-os4.sh compiles the glue and sources in Docker */
            Buf c2 = {0, 0, 0};
            char *script = xsprintf("%s/../tools/boing-vm-os4.sh", dir);
            int rc;
            if (!file_exists(script)) { fprintf(stderr, "boing vm: %s not found\n", script); return 10; }
            buf_printf(&c2, "sh \"%s\" \"%s\" \"%s\"%s", script, out, gpath, links_os4);    /* -lX: link libraries */
            for (k = 0; k < ns; k++) buf_printf(&c2, " \"%s\"", src[k]);
            rc = system(c2.p);
            remove(gpath);
            return rc == 0 ? 0 : 1;
        }
        if (target && strcmp(target, "host")) { fprintf(stderr, "boing vm: unknown target %s (host, os4)\n", target); return 5; }
        /* compile and link: main.o, the compiler and the VM come from libboingvm.a */
        {
            size_t dl = strlen(dir);
            const char *sep = dl && (dir[dl - 1] == ':' || dir[dl - 1] == '/') ? "" : "/";
            inc = xsprintf("%s%sinclude", dir, sep);
            lib = file_exists(xsprintf("%s%slib/libboing.a", dir, sep)) ? xsprintf("%s%slib", dir, sep) : xsprintf("%s", dir);
        }
#ifdef __amigaos4__
        if (!cc || !*cc) cc = bb_sys_probe("SDK:gcc/bin/gcc") ? "SDK:gcc/bin/gcc" : "gcc";
        if (!cxxc || !*cxxc) cxxc = bb_sys_probe("SDK:gcc/bin/g++") ? "SDK:gcc/bin/g++" : "g++";
        const char *fl = "-mcrt=newlib -mcpu=powerpc -O2 -D__USE_OLD_TIMEVAL__";
#else
        if (!cc || !*cc) cc = "cc";
        if (!cxxc || !*cxxc) cxxc = "c++";
        const char *fl = "-O2";
#endif
        buf_puts(&objs, "");
        for (k = -1; k < ns; k++) {
            const char *fsrc = k < 0 ? gpath : src[k];
            size_t n2 = strlen(fsrc);
            int isx = (n2 > 4 && !strcasecmp(fsrc + n2 - 4, ".cpp")) || (n2 > 3 && !strcasecmp(fsrc + n2 - 3, ".cc"));
            char *o = xsprintf("%s.x%d.o", out, k + 1);
            char *c1 = xsprintf("%s %s%s \"-I%s\" -c \"%s\" -o \"%s\"", isx ? cxxc : cc, fl, isx ? CXX_THREADS : "", inc, fsrc, o);
            if (system(c1) != 0) { fprintf(stderr, "boing vm: compiler failed: %s\n", c1); return 1; }
            buf_printf(&objs, " \"%s\"", o);
            if (isx) cxx = 1;
        }
#ifdef __amigaos4__
        cmd = xsprintf("%s -mcrt=newlib -mcpu=powerpc%s%s -o \"%s\" \"-L%s\" -lboingvm -lboing%s -lauto -lm", cxx ? cxxc : cc, cxx ? CXX_THREADS : "", objs.p, out, lib, links_os4);
#else
        cmd = xsprintf("%s%s -o \"%s\" -L\"%s\" -lboingvm -lboing%s -lm", cxx ? cxxc : cc, objs.p, out, lib, links_host);
#endif
        if (system(cmd) != 0) { fprintf(stderr, "boing vm: link failed: %s\n", cmd); return 1; }
        if (!getenv("BOING_KEEP_GLUE")) {
            remove(gpath);
            for (k = -1; k < ns; k++) remove(xsprintf("%s.x%d.o", out, k + 1));
        }
        (void)names;
    }
    return 0;
}

int main(int argc, char **argv)
{
    const char *cmd;
    g_argv0 = argv[0];
    bbc_home = home_dir;
#ifdef __amigaos4__
    bb_wb_start(&argc, &argv);
#endif
    bb_vm_ext_init();
    if (argc < 2) usage();
    cmd = argv[1];
    if (!strcmp(cmd, "--version") || !strcmp(cmd, "version")) { printf("Boing BASIC " BOING_VERSION "\n"); return 0; }
    if (!strcmp(cmd, "extensions")) {
        /* the extensions linked into this interpreter (STD_EXTS, or a `boing vm` one's), one per
           line: an IDE runs a project whose Extension= lines are all here with this boing,
           without building an interpreter for it */
        int i;
        for (i = 0; i < bb_ext_linked_count(); i++) printf("%s\n", bb_ext_linked_name(i));
        return 0;
    }
    if (argc < 3 && strcmp(cmd, "members") && strcmp(cmd, "vm")) usage();
    if (!strcmp(cmd, "vm")) return cmd_vm(argv[0], argc, argv);
    if (!strcmp(cmd, "sources")) {
        /* boing sources PROG.bbp: the C/C++ files a native build compiles besides the program
           (Extension= and CSource=), one per line (tools/boing-build-os4.sh) */
        Program *p = load(argv[2]);
        int k;
        if (p->nerrors) return 1;
        for (k = 0; k < p->nexts; k++) printf("%s\n", p->exts[k].src);
        for (k = 0; k < p->ncsources; k++) printf("%s\n", p->csources[k]);
        return 0;
    }
    if (!strcmp(cmd, "links")) {
        /* boing links PROG.bbp [os4|host]: the extensions' link flags (-lsqlite3 ...) for a target */
        Program *p = load(argv[2]);
        if (p->nerrors) return 1;
        printf("%s\n", bbx_link_flags(p, argc > 3 && !strcmp(argv[3], "os4")) + (p->nlinks ? 1 : 0));
        return 0;
    }
    if (!strcmp(cmd, "members")) {
        /* boing members [Class]: the members of the runtime classes (Engine3D, Canvas, Audio), one per
           line "Class<TAB>Name<TAB>method|property", for AmiForge's completion; each name is checked
           against the class's own find() (exit 1 if one does not resolve) */
        size_t i;
        int bad = 0, ai = 2;
        const char *want = NULL;
        Program *xp = NULL;
        if (argc > 3 && !strcmp(argv[2], "--project")) {
            /* the project's extension classes too (their .bbx: signature and type in fields 4, 5) */
            xp = prog_new();
            xp->diag_out = stderr;
            prog_load_file(xp, argv[3]);
            ai = 4;
        }
        want = argc > ai ? argv[ai] : NULL;
        if (want && !strncasecmp(want, "Boing.", 6)) want += 6;
        if (xp) {
            int k, j;
            for (k = 0; k < xp->nxclasses; k++) {
                ExtClass *xc = xp->xclasses[k];
                if (want && strcasecmp(want, xc->name)) continue;
                for (j = 0; j < xc->nm; j++)
                    printf("%s\t%s\t%s\t%s\t%s\n", xc->name, xc->m[j].name, xc->m[j].kind == 0 ? "method" : xc->m[j].kind == 1 ? "property" : "property-ro",
                           xc->m[j].sig, xc->m[j].type);
            }
            /* the extensions' functions and subs: an empty class field */
            for (k = 0; !want && k < xp->nxfuncs; k++) {
                ExtFunc *xf = xp->xfuncs[k];
                printf("\t%s\t%s\t%s\t%s\n", xf->name, xf->ret ? "function" : "sub", xf->sig, xf->ret ? xf->ret : "");
            }
            /* and their constants: kind "const", the value in the signature field */
            for (k = 0; !want && k < xp->nxconsts; k++) {
                ExtConst *xk = xp->xconsts[k];
                if (xk->isdbl) printf("\t%s\tconst\t%.17g\tDouble\n", xk->name, xk->d);
                else printf("\t%s\tconst\t%lld\tLong\n", xk->name, (long long)xk->i);
            }
        }
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
