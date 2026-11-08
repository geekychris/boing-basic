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

static char *read_file(const char *path, long *len)
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

Module *prog_add_source(Program *p, const char *path, const char *src, int is_class)
{
    Module *m = (Module *)xcalloc(1, sizeof(Module));
    Token *toks;
    int ntoks;
    m->path = xstrdup(path);
    m->name = base_name(path);
    m->is_class = is_class;
    m->file = add_file(p, path, (char *)src);
    p->mods = (Module **)xrealloc(p->mods, sizeof(Module *) * (size_t)(p->nmods + 1));
    p->mods[p->nmods++] = m;
    lex_file(p, m->file, src, &toks, &ntoks);
    parse_module(p, m, toks, ntoks);
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
    char *startup = NULL;
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
            read_afg(p, m, afg);
        } else if (name_eq(key, "Startup")) startup = xstrdup(val);
        else if (name_eq(key, "Stack")) p->stack = atoi(val);
        else if (name_eq(key, "Icon") || name_eq(key, "Uses") || name_eq(key, "Version") || name_eq(key, "Title")) {
            /* used by the platform build */
        } else diag_warn(p, 0, lineno, 1, "unknown project key '%s'", key);
    }
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
