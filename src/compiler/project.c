/* project.c - programs, source files and .bbp projects */
#include "bbc.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

Program *prog_new(void)
{
    Program *p = (Program *)xcalloc(1, sizeof(Program));
    p->global = scope_new(NULL);
    p->max_errors = 50;
    p->stack = 262144;
    return p;
}

char *read_file(const char *path, long *len)
{
    FILE *f = fopen(path, "rb");
    char *b;
    long n;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b = (char *)xmalloc((size_t)n + 1);
    if (n > 0 && fread(b, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(b); return NULL; }
    b[n] = 0;
    fclose(f);
    if (len) *len = n;
    return b;
}

static char *base_name(const char *path)
{
    const char *s = strrchr(path, '/'), *c = strrchr(path, ':'), *d;
    if (c && (!s || c > s)) s = c;
    s = s ? s + 1 : path;
    d = strrchr(s, '.');
    return d ? xstrndup(s, (size_t)(d - s)) : xstrdup(s);
}

static const char *ext_of(const char *path)
{
    const char *d = strrchr(path, '.'), *s = strrchr(path, '/');
    if (!d || (s && d < s)) return "";
    return d;
}

static int add_file(Program *p, const char *path, char *src)
{
    p->files = (char **)xrealloc(p->files, sizeof(char *) * (size_t)(p->nfiles + 1));
    p->srcs = (char **)xrealloc(p->srcs, sizeof(char *) * (size_t)(p->nfiles + 1));
    p->files[p->nfiles] = xstrdup(path);
    p->srcs[p->nfiles] = src;
    return p->nfiles++;
}

/* the boing installation's directory (main.c sets it: the executable's, or BOING_HOME) */
char *(*bbc_home)(void);

static char *dir_of(const char *path)
{
    const char *s = strrchr(path, '/'), *c = strrchr(path, ':');
    if (c && (!s || c > s)) s = c;
    return s ? xstrndup(path, (size_t)(s - path) + 1) : xstrdup("");
}

static int readable(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fclose(f);
    return 1;
}

static char *join_dir(const char *dir, const char *rel);

/* an #Include or Uses= file: beside the including file, then $BOING_BINDINGS, then the
   installation's bindings/ (and, on hosts, the repo's: build/boing -> bindings/) */
static char *find_include(Program *p, const char *from_dir, const char *name)
{
    const char *env = getenv("BOING_BINDINGS");
    char *home = bbc_home ? bbc_home() : NULL, *c;
    (void)p;
    if (strchr(name, ':') || name[0] == '/') return readable(name) ? xstrdup(name) : NULL;
    c = join_dir(from_dir, name);
    if (readable(c)) return c;
    if (env && *env) {
        size_t n = strlen(env);
        c = xsprintf("%s%s%s", env, env[n - 1] == '/' || env[n - 1] == ':' ? "" : "/", name);
        if (readable(c)) return c;
    }
    if (home && *home) {
        size_t n = strlen(home);
        const char *sep = home[n - 1] == '/' || home[n - 1] == ':' ? "" : "/";
        c = xsprintf("%s%sbindings/%s", home, sep, name);
        if (readable(c)) return c;
#ifndef __amigaos4__
        c = xsprintf("%s%s../bindings/%s", home, sep, name);
        if (readable(c)) return c;
#endif
    }
    return NULL;
}

/* Extension=NAME: dir/NAME, else a standard extension NAME/NAME in $BOING_EXT, the
   installation's ext/ (and, on hosts, the repo's: build/boing -> ext/) */
static char *ext_base(Program *p, const char *dir, const char *val, int lineno)
{
    char *b = join_dir(dir, val), *c;
    const char *env = getenv("BOING_EXT");
    char *home;
    if (strchr(val, '/') || strchr(val, ':') || readable(c = xsprintf("%s.bbx", b))) return b;
    if (env && *env) {
        size_t n = strlen(env);
        c = xsprintf("%s%s%s/%s", env, env[n - 1] == '/' || env[n - 1] == ':' ? "" : "/", val, val);
        if (readable(xsprintf("%s.bbx", c))) return c;
    }
    home = bbc_home ? bbc_home() : NULL;
    if (home && *home) {
        size_t n = strlen(home);
        const char *sep = home[n - 1] == '/' || home[n - 1] == ':' ? "" : "/";
        c = xsprintf("%s%sext/%s/%s", home, sep, val, val);
        if (readable(xsprintf("%s.bbx", c))) return c;
#ifndef __amigaos4__
        c = xsprintf("%s%s../ext/%s/%s", home, sep, val, val);
        if (readable(xsprintf("%s.bbx", c))) return c;
#endif
    }
    diag(p, 0, lineno, 1, "extension '%s' not found: no %s.bbx beside the project, in $BOING_EXT or in the ext directory of the installation", val, val);
    return b;
}

/* add an included file to the program as its own module, once per program */
static void include_file(Program *p, Module *from, int line, int col, const char *dir, const char *name)
{
    char *path = find_include(p, dir, name), *src;
    long n;
    int i;
    if (!path) {
        diag(p, from ? from->file : 0, line, col, "cannot find include file '%s' (looked beside the program, in $BOING_BINDINGS and in the bindings directory)", name);
        return;
    }
    for (i = 0; i < p->nincludes; i++)
        if (!strcmp(p->includes[i], path)) return;
    p->includes = (char **)xrealloc(p->includes, sizeof(char *) * (size_t)(p->nincludes + 1));
    p->includes[p->nincludes++] = path;
    src = read_file(path, &n);
    if (!src) { diag(p, from ? from->file : 0, line, col, "cannot read include file '%s'", path); return; }
    prog_add_source(p, path, src, 0);
}

Module *prog_add_source(Program *p, const char *path, const char *src, int is_class)
{
    Module *m = (Module *)xcalloc(1, sizeof(Module));
    Token *toks;
    int ntoks, i, o, ninc = 0;
    struct { char *name; int line, col; } *inc = NULL;
    m->path = xstrdup(path);
    m->name = base_name(path);
    m->is_class = is_class;
    m->file = add_file(p, path, (char *)src);
    p->mods = (Module **)xrealloc(p->mods, sizeof(Module *) * (size_t)(p->nmods + 1));
    p->mods[p->nmods++] = m;
    lex_file(p, m->file, src, &toks, &ntoks);
    /* #Include "file" lines: taken out here, the files added as modules after this one */
    for (i = o = 0; i < ntoks; i++) {
        Token *t = &toks[i];
        if (t->kind == TK_HASH && t->line_start && i + 2 < ntoks && toks[i + 1].kind == TK_ID &&
            name_eq(toks[i + 1].text, "Include") && toks[i + 2].kind == TK_STR && toks[i + 2].line == t->line) {
            inc = xrealloc(inc, sizeof *inc * (size_t)(ninc + 1));
            inc[ninc].name = toks[i + 2].text; inc[ninc].line = t->line; inc[ninc].col = t->col;
            ninc++;
            i += 2;
            continue;
        }
        toks[o++] = *t;
    }
    ntoks = o;
    parse_module(p, m, toks, ntoks);
    if (ninc) {
        char *dir = dir_of(path);
        if (is_class) diag(p, m->file, inc[0].line, inc[0].col, "#Include is not allowed in a class module: put it in a standard module");
        else for (i = 0; i < ninc; i++) include_file(p, m, inc[i].line, inc[i].col, dir, inc[i].name);
    }
    return m;
}

/* the ids of an AmiForge .afg form: "kind key=value ..." per line */
static void read_afg(Program *p, Module *m, const char *afgpath)
{
    long n;
    char *src = read_file(afgpath, &n), *line, *save = NULL;
    if (!src) {
        diag(p, m->file, 1, 1, "cannot read form file '%s'", afgpath);
        return;
    }
    for (line = strtok_r(src, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        char *q = line, kind[64];
        int k = 0;
        while (*q == ' ' || *q == '\t') q++;
        if (*q == '#' || !*q) continue;
        while (*q && !isspace((unsigned char)*q) && k < 63) kind[k++] = *q++;
        kind[k] = 0;
        for (;;) {
            char key[64], val[256];
            int kk = 0, vv = 0;
            while (*q == ' ' || *q == '\t') q++;
            if (!*q) break;
            while (*q && *q != '=' && !isspace((unsigned char)*q) && kk < 63) key[kk++] = *q++;
            key[kk] = 0;
            if (*q != '=') { while (*q && !isspace((unsigned char)*q)) q++; continue; }
            q++;
            if (*q == '"') { q++; while (*q && *q != '"' && vv < 255) val[vv++] = *q++; if (*q) q++; }
            else while (*q && !isspace((unsigned char)*q) && vv < 255) val[vv++] = *q++;
            val[vv] = 0;
            if ((strcmp(key, "id") == 0) || (strcmp(kind, "window") == 0 && strcmp(key, "name") == 0)) {
                m->form_controls = (char **)xrealloc(m->form_controls, sizeof(char *) * (size_t)(m->ncontrols + 1));
                m->form_controls[m->ncontrols++] = xstrdup(val);
                if (strcmp(kind, "window") == 0 && strcmp(key, "name") == 0) m->form_name = xstrdup(val);
            }
        }
    }
    free(src);
}

static char *join_dir(const char *dir, const char *rel)
{
#ifdef __amigaos4__
    /* .bbp files are written with Unix-style relative paths; AmigaDOS has no "." or "..":
       "../x" is "/x" (the parent), "./x" is "x" */
    if (!strchr(rel, ':') && (rel[0] == '.' )) {
        char buf[1024];
        size_t o = 0;
        while (rel[0] == '.') {
            if (rel[1] == '/') rel += 2;
            else if (rel[1] == '.' && rel[2] == '/') { if (o < sizeof buf - 1) buf[o++] = '/'; rel += 3; }
            else break;
        }
        snprintf(buf + o, sizeof buf - o, "%s", rel);
        return xsprintf("%s%s", dir, buf);
    }
#endif
    if (!dir[0] || rel[0] == '/' || strchr(rel, ':')) return xstrdup(rel);
    return xsprintf("%s%s", dir, rel);
}

static int load_source(Program *p, const char *path, int is_class)
{
    long n;
    char *src = read_file(path, &n);
    if (!src) {
        fprintf(p->diag_out ? p->diag_out : stderr, "%s: error: cannot read file\n", path);
        p->nerrors++;
        return 0;
    }
    prog_add_source(p, path, src, is_class);
    return 1;
}

static int load_project(Program *p, const char *path)
{
    long n;
    char *src = read_file(path, &n), *line, *save = NULL, dir[1024];
    const char *slash = strrchr(path, '/');
    int lineno = 0;
    char *startup = NULL, **uses = NULL;
    int nuses = 0, *uses_line = NULL, ui;
    if (!src) {
        fprintf(p->diag_out ? p->diag_out : stderr, "%s: error: cannot read project file\n", path);
        p->nerrors++;
        return 0;
    }
    if (slash) { size_t k = (size_t)(slash - path) + 1; memcpy(dir, path, k); dir[k] = 0; }
    else dir[0] = 0;
    add_file(p, path, src);
    for (line = strtok_r(xstrdup(src), "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        char *eq, *key, *val, *e;
        lineno++;
        while (*line == ' ' || *line == '\t') line++;
        if (*line == '#' || *line == '\'' || !*line || *line == '\r') continue;
        eq = strchr(line, '=');
        if (!eq) { diag(p, 0, lineno, 1, "expected key=value"); continue; }
        *eq = 0;
        key = line;
        val = eq + 1;
        for (e = eq - 1; e >= key && (*e == ' ' || *e == '\t'); e--) *e = 0;
        while (*val == ' ' || *val == '\t') val++;
        /* strip trailing comment and spaces */
        if ((e = strstr(val, " '")) != NULL) *e = 0;
        if ((e = strstr(val, "\t'")) != NULL) *e = 0;
        for (e = val + strlen(val) - 1; e >= val && (*e == ' ' || *e == '\t' || *e == '\r'); e--) *e = 0;
        if (name_eq(key, "Name")) p->name = xstrdup(val);
        else if (name_eq(key, "Module")) load_source(p, join_dir(dir, val), 0);
        else if (name_eq(key, "Class")) load_source(p, join_dir(dir, val), 1);
        else if (name_eq(key, "Form")) {
            char *afg = join_dir(dir, val), *bas;
            const char *x = strrchr(afg, '.');
            Module *m;
            bas = x ? xsprintf("%.*s.bas", (int)(x - afg), afg) : xsprintf("%s.bas", afg);
            if (!load_source(p, bas, 0)) continue;
            m = p->mods[p->nmods - 1];
            m->is_form = 1;
            m->afg_path = xstrdup(afg);
            read_afg(p, m, afg);
            if (!m->form_name) m->form_name = xstrdup(m->name);
        } else if (name_eq(key, "Startup")) startup = xstrdup(val);
        else if (name_eq(key, "Stack")) p->stack = atoi(val);
        else if (name_eq(key, "Title")) p->title = xstrdup(val);
        else if (name_eq(key, "Version")) {
            /* "1.2.3" (or 1.2, 1): App.Major/Minor/Revision and the $VER string */
            p->version = xstrdup(val);
            p->ver_major = atoi(val);
            p->ver_minor = strchr(val, '.') ? atoi(strchr(val, '.') + 1) : 0;
            p->ver_rev = strchr(val, '.') && strchr(strchr(val, '.') + 1, '.') ? atoi(strchr(strchr(val, '.') + 1, '.') + 1) : 0;
        }
        else if (name_eq(key, "Extension")) {
            /* Extension=dir/name: dir/name.c (or .cpp) and its descriptor dir/name.bbx */
            char *base = ext_base(p, dir, val, lineno), *slash = strrchr(base, '/'), *colon = strrchr(base, ':');
            const char *nm = slash ? slash + 1 : colon ? colon + 1 : base;
            ExtInfo *x;
            long n2;
            char *probe;
            p->exts = (ExtInfo *)xrealloc(p->exts, sizeof(ExtInfo) * (size_t)(p->nexts + 1));
            x = &p->exts[p->nexts++];
            x->name = xstrdup(nm);
            x->dir = xstrndup(base, (size_t)(nm - base));
            x->bbx = xsprintf("%s.bbx", base);
            x->src = xsprintf("%s.c", base);
            probe = read_file(x->src, &n2);
            if (!probe) { free(x->src); x->src = xsprintf("%s.cpp", base); probe = read_file(x->src, &n2); }
            free(probe);
            if (strchr(val, '/') || strchr(val, ':') || readable(x->bbx)) bbx_load(p, x->bbx, x->name);
        } else if (name_eq(key, "CSource")) {
            p->csources = (char **)xrealloc(p->csources, sizeof(char *) * (size_t)(p->ncsources + 1));
            p->csources[p->ncsources++] = join_dir(dir, val);
        } else if (name_eq(key, "Uses")) {
            /* Uses=exec,dos: the bindings exec.bi and dos.bi, as #Include does */
            char *list = xstrdup(val), *nm, *sv = NULL;
            for (nm = strtok_r(list, ", ", &sv); nm; nm = strtok_r(NULL, ", ", &sv)) {
                char *file = strchr(nm, '.') ? xstrdup(nm) : xsprintf("%s.bi", nm);
                uses = (char **)xrealloc(uses, sizeof(char *) * (size_t)(nuses + 1));
                uses_line = (int *)xrealloc(uses_line, sizeof(int) * (size_t)(nuses + 1));
                uses_line[nuses] = lineno;
                uses[nuses++] = file;
            }
        } else if (name_eq(key, "Icon")) {
            /* used by the platform build */
        } else diag_warn(p, 0, lineno, 1, "unknown project key '%s'", key);
    }
    /* Uses= bindings after the project's own modules (the first module stays the default startup) */
    for (ui = 0; ui < nuses; ui++) include_file(p, NULL, uses_line[ui], 1, dir, uses[ui]);
    if (startup) {
        int i;
        if (strncasecmp(startup, "Sub ", 4) == 0) {
            /* Sub Main: the module defining it is found by sema */
            p->startup = NULL;
        } else if (strncasecmp(startup, "Form ", 5) == 0) {
            const char *fn = startup + 5;
            for (i = 0; i < p->nmods; i++)
                if (p->mods[i]->is_form && name_eq(p->mods[i]->name, fn)) p->startup = p->mods[i];
            if (!p->startup) diag(p, 0, 1, 1, "startup form '%s' is not in the project", fn);
        }
    }
    return 1;
}

int prog_load_file(Program *p, const char *path)
{
    const char *e = ext_of(path);
    if (name_eq(e, ".bbp")) return load_project(p, path);
    if (name_eq(e, ".cls")) return load_source(p, path, 1);
    return load_source(p, path, 0);
}

int prog_compile(Program *p)
{
    if (p->nerrors) return 0;
    if (!sema_program(p)) return 0;
    if (!p->startup_proc && p->nmods && !(p->startup && p->startup->is_form)) {
        diag(p, p->mods[0]->file, 1, 1, "no startup code: add statements at module level or a Sub Main");
        return 0;
    }
    return 1;
}
