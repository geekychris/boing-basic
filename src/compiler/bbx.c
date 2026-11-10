/* bbx.c - extension descriptors (name.bbx): the classes, members and functions a linked extension
 * registers, for compile-time checks and `boing members` (docs/extensions.md).
 *
 *   # comment
 *   class Counter
 *     method Add(ByVal n As Long) As Long
 *     method Reset()
 *     property Value As Long
 *     property Count As Long ReadOnly
 *   function Clamp(ByVal x As Long, ByVal lo As Long, ByVal hi As Long) As Long
 *   sub Beep2(ByVal hz As Long)
 */
#include "bbc.h"
#include <ctype.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>

static char *trim(char *s)
{
    char *e;
    while (*s == ' ' || *s == '\t') s++;
    e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n')) *--e = 0;
    return s;
}

/* "Name(ByVal a As Long, b As String) As Long": name, the text in parentheses, the type after */
static int split_sig(char *s, char **name, char **args, char **type)
{
    char *lp = strchr(s, '('), *rp, *as;
    *args = NULL;
    *type = NULL;
    if (lp) {
        rp = strrchr(s, ')');
        if (!rp || rp < lp) return 0;
        *lp = 0;
        *rp = 0;
        *args = trim(lp + 1);
        as = rp + 1;
    } else as = s;
    {
        char *k = as;
        while (*k) {
            if ((k == as || k[-1] == ' ' || k[-1] == '\t') && !strncasecmp(k, "As ", 3)) { *k = 0; *type = trim(k + 3); break; }
            k++;
        }
    }
    *name = trim(s);
    return **name != 0;
}

/* "ByVal a As Long, b As String" -> params (ByVal assumed; ByRef is not supported) */
static int parse_params(char *args, ExtParam **out, int *n)
{
    char *save = NULL, *tok;
    *out = NULL;
    *n = 0;
    if (!args || !*args) return 1;
    for (tok = strtok_r(args, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
        char *t = trim(tok), *as;
        if (!strncasecmp(t, "ByVal ", 6)) t = trim(t + 6);
        else if (!strncasecmp(t, "ByRef ", 6)) return 0;
        as = strstr(t, " As ");
        if (!as) as = strstr(t, " as ");
        *out = (ExtParam *)xrealloc(*out, sizeof(ExtParam) * (size_t)(*n + 1));
        if (as) { *as = 0; (*out)[*n].type = xstrdup(trim(as + 4)); }
        else (*out)[*n].type = xstrdup("Variant");
        (*out)[*n].name = xstrdup(trim(t));
        (*n)++;
    }
    return 1;
}

int bbx_load(Program *p, const char *path, const char *ext)
{
    long len;
    char *src = read_file(path, &len), *line, *save = NULL;
    ExtClass *cur = NULL;
    int lineno = 0, ok = 1;
    if (!src) {
        fprintf(p->diag_out ? p->diag_out : stderr, "%s: error: cannot read extension descriptor\n", path);
        p->nerrors++;
        return 0;
    }
    for (line = strtok_r(src, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        char *s = trim(line), *rest, *name, *args, *type;
        lineno++;
        if (!*s || *s == '#' || *s == '\'') continue;
        rest = s;
        while (*rest && !isspace((unsigned char)*rest)) rest++;
        if (*rest) *rest++ = 0;
        rest = trim(rest);
        if (!strcasecmp(s, "link")) {
            /* link LIB | link os4 LIB | link host LIB: -lLIB for native builds and `boing vm` */
            char *w2 = rest, *lib, *e2;
            const char *only = NULL;
            while (*w2 && !isspace((unsigned char)*w2)) w2++;
            if (*w2) { *w2++ = 0; w2 = trim(w2); }
            if (*w2 && (!strcasecmp(rest, "os4") || !strcasecmp(rest, "host"))) { only = !strcasecmp(rest, "os4") ? "os4" : "host"; lib = w2; }
            else if (!*w2) lib = rest;
            else goto bad;
            for (e2 = lib; *e2; e2++) if (!isalnum((unsigned char)*e2) && *e2 != '_' && *e2 != '-' && *e2 != '+' && *e2 != '.') goto bad;
            if (!*lib) goto bad;
            {
                char *ent = only ? xsprintf("%s:%s", only, lib) : xstrdup(lib);
                int k, dup = 0;
                for (k = 0; k < p->nlinks; k++) if (!strcmp(p->links[k], ent)) dup = 1;
                if (!dup) {
                    p->links = (char **)xrealloc(p->links, sizeof(char *) * (size_t)(p->nlinks + 1));
                    p->links[p->nlinks++] = ent;
                }
            }
            continue;
        }
        if (!strcasecmp(s, "class")) {
            if (!*rest) goto bad;
            cur = (ExtClass *)xcalloc(1, sizeof(ExtClass));
            cur->name = xstrdup(rest);
            cur->ext = xstrdup(ext);
            p->xclasses = (ExtClass **)xrealloc(p->xclasses, sizeof(ExtClass *) * (size_t)(p->nxclasses + 1));
            p->xclasses[p->nxclasses++] = cur;
        } else if (!strcasecmp(s, "property-ro")) {
            fprintf(p->diag_out ? p->diag_out : stderr, "%s:%d: error: write a read-only property as 'property Name As Type ReadOnly'\n", path, lineno);
            p->nerrors++;
            ok = 0;
            continue;
        } else if (!strcasecmp(s, "method") || !strcasecmp(s, "property")) {
            char *full = xstrdup(rest);
            ExtMember *m;
            if (!cur || !split_sig(rest, &name, &args, &type)) goto bad;
            cur->m = (ExtMember *)xrealloc(cur->m, sizeof(ExtMember) * (size_t)(cur->nm + 1));
            m = &cur->m[cur->nm++];
            m->name = xstrdup(name);
            m->kind = !strcasecmp(s, "method") ? 0 : 1;
            /* "property Count As Long ReadOnly" */
            if (type) {
                size_t tl = strlen(type);
                if (tl > 8 && !strcasecmp(type + tl - 8, "ReadOnly") && (type[tl - 9] == ' ' || type[tl - 9] == '\t')) {
                    type[tl - 9] = 0;
                    type = trim(type);
                    if (m->kind == 1) m->kind = 2;
                }
            }
            m->sig = xstrdup(args ? args : "");
            m->type = xstrdup(type ? type : "");
            free(full);
        } else if (!strcasecmp(s, "function") || !strcasecmp(s, "sub")) {
            ExtFunc *f = (ExtFunc *)xcalloc(1, sizeof(ExtFunc));
            if (!split_sig(rest, &name, &args, &type)) goto bad;
            f->name = xstrdup(name);
            f->ext = xstrdup(ext);
            f->sig = xstrdup(args ? args : "");
            f->ret = !strcasecmp(s, "sub") ? NULL : xstrdup(type ? type : "Variant");
            if (!parse_params(args ? xstrdup(args) : NULL, &f->p, &f->np)) goto bad;
            cur = NULL;
            p->xfuncs = (ExtFunc **)xrealloc(p->xfuncs, sizeof(ExtFunc *) * (size_t)(p->nxfuncs + 1));
            p->xfuncs[p->nxfuncs++] = f;
        } else goto bad;
        continue;
    bad:
        fprintf(p->diag_out ? p->diag_out : stderr, "%s:%d: error: expected 'class', 'method', 'property', 'function', 'sub' or 'link'\n", path, lineno);
        p->nerrors++;
        ok = 0;
    }
    free(src);
    return ok;
}

char *bbx_link_flags(Program *p, int os4)
{
    Buf b = {0, 0, 0};
    int k;
    buf_puts(&b, "");
    for (k = 0; k < p->nlinks; k++) {
        const char *l = p->links[k];
        if (!strncmp(l, "os4:", 4)) { if (!os4) continue; l += 4; }
        else if (!strncmp(l, "host:", 5)) { if (os4) continue; l += 5; }
        if (!strcmp(l, "m") || (os4 && !strcmp(l, "auto"))) continue;     /* always linked */
        buf_printf(&b, " -l%s", l);
    }
    return b.p;
}

ExtClass *ext_class_find(Program *p, const char *name)
{
    int i;
    if (!strncasecmp(name, "Boing.", 6)) name += 6;
    for (i = 0; i < p->nxclasses; i++) if (name_eq(p->xclasses[i]->name, name)) return p->xclasses[i];
    return NULL;
}

ExtMember *ext_member_find(ExtClass *c, const char *name)
{
    int i;
    for (i = 0; i < c->nm; i++) if (name_eq(c->m[i].name, name)) return &c->m[i];
    return NULL;
}

ExtFunc *ext_func_find(Program *p, const char *name)
{
    int i;
    for (i = 0; i < p->nxfuncs; i++) if (name_eq(p->xfuncs[i]->name, name)) return p->xfuncs[i];
    return NULL;
}
