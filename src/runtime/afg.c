/* .afg parser (see afg.h). Mirrors AmiForge's GuiModel::parse, including its defaults. */
#include "afg.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct kind_def {
    const char *name;
    int container, gadget;
    const char *defaults;      /* "key=value\n..." */
};

#define COMMON_GADGET "disabled=0\n"
static const struct kind_def kinds[AFG_NUM_KINDS] = {
    [AFG_WINDOW] = { "window", 1, 0, "name=main\ntitle=Untitled\nwidth=0\nheight=0\nresizable=1\n" },
    [AFG_VLAYOUT] = { "vlayout", 1, 0, "frame=none\neven=0\n" },
    [AFG_HLAYOUT] = { "hlayout", 1, 0, "frame=none\neven=0\n" },
    [AFG_BUTTON] = { "button", 0, 1, "text=Button\n" COMMON_GADGET },
    [AFG_STRING] = { "string", 0, 1, "maxchars=128\n" COMMON_GADGET },
    [AFG_INTEGER] = { "integer", 0, 1, "value=0\nmin=0\nmax=100\n" COMMON_GADGET },
    [AFG_CHECKBOX] = { "checkbox", 0, 1, "text=Check box\nchecked=0\n" COMMON_GADGET },
    [AFG_CHOOSER] = { "chooser", 0, 1, "items=One|Two|Three\nselected=0\n" COMMON_GADGET },
    [AFG_RADIO] = { "radio", 0, 1, "items=One|Two\nselected=0\n" COMMON_GADGET },
    [AFG_SLIDER] = { "slider", 0, 1, "min=0\nmax=100\nlevel=0\nvertical=0\n" COMMON_GADGET },
    [AFG_SCROLLER] = { "scroller", 0, 1, "total=100\nvisible=10\ntop=0\nvertical=0\n" COMMON_GADGET },
    [AFG_LISTBROWSER] = { "listbrowser", 0, 1, COMMON_GADGET },
    [AFG_LABEL] = { "label", 0, 0, "text=Text\n" },
    [AFG_SPACE] = { "space", 0, 0, "" },
    [AFG_FUELGAUGE] = { "fuelgauge", 0, 0, "min=0\nmax=100\nlevel=50\n" },
    [AFG_GETFILE] = { "getfile", 0, 1, "title=Choose a file\nsave=0\n" COMMON_GADGET },
    [AFG_TEXTEDITOR] = { "texteditor", 0, 1, COMMON_GADGET },
    [AFG_TIMER] = { "timer", 0, 0, "interval=0\nenabled=1\n" },
    [AFG_CANVAS] = { "canvas", 0, 0, "width=320\nheight=200\n" },     /* canvas */
};

const char *afg_kind_name(afg_kind k) { return k < AFG_NUM_KINDS ? kinds[k].name : "?"; }
int afg_is_container(afg_kind k) { return k < AFG_NUM_KINDS && kinds[k].container; }
int afg_is_gadget(afg_kind k) { return k < AFG_NUM_KINDS && kinds[k].gadget; }

int afg_kind_by_name(const char *name)
{
    for (int i = 0; i < AFG_NUM_KINDS; i++)
        if (!strcmp(name, kinds[i].name)) return i;
    return -1;
}

static char *dupn(const char *s, size_t n)
{
    char *o = malloc(n + 1);
    if (!o) return NULL;
    memcpy(o, s, n);
    o[n] = 0;
    return o;
}

static const char *find_default(afg_kind k, const char *key)
{
    static char buf[256];
    const char *d = kinds[k].defaults;
    size_t kl = strlen(key);
    while (*d) {
        const char *nl = strchr(d, '\n');
        if (!nl) nl = d + strlen(d);
        if ((size_t)(nl - d) > kl && !strncmp(d, key, kl) && d[kl] == '=') {
            size_t vl = nl - d - kl - 1;
            if (vl >= sizeof buf) vl = sizeof buf - 1;
            memcpy(buf, d + kl + 1, vl);
            buf[vl] = 0;
            return buf;
        }
        d = *nl ? nl + 1 : nl;
    }
    return NULL;
}

const char *afg_get(const afg_node *n, const char *key)
{
    for (int i = 0; i < n->nprops; i++)
        if (!strcmp(n->props[i].key, key)) return n->props[i].value;
    const char *d = find_default(n->kind, key);
    return d ? d : "";
}

int afg_get_int(const afg_node *n, const char *key) { return atoi(afg_get(n, key)); }

int afg_get_bool(const afg_node *n, const char *key)
{
    const char *v = afg_get(n, key);
    return *v && strcmp(v, "0") && strcmp(v, "no") && strcmp(v, "false");
}

int afg_has(const afg_node *n, const char *key)
{
    for (int i = 0; i < n->nprops; i++)
        if (!strcmp(n->props[i].key, key)) return n->props[i].value[0] != 0;
    return 0;
}

static void add_prop(afg_node *n, char *key, char *value)
{
    for (int i = 0; i < n->nprops; i++)
        if (!strcmp(n->props[i].key, key)) {
            free(n->props[i].value);
            free(key);
            n->props[i].value = value;
            return;
        }
    n->props = realloc(n->props, (n->nprops + 1) * sizeof *n->props);
    n->props[n->nprops].key = key;
    n->props[n->nprops].value = value;
    n->nprops++;
}

static void add_child(afg_node *p, afg_node *c)
{
    p->children = realloc(p->children, (p->nchildren + 1) * sizeof *p->children);
    p->children[p->nchildren++] = c;
    c->parent = p;
}

/* one line: kind key=value ...; 0 with err on a syntax error */
static int parse_line(const char *line, size_t n, afg_node *node, char *kind, size_t kindlen, char *err, int errlen)
{
    size_t i = 0;
    while (i < n && isspace((unsigned char)line[i])) i++;
    size_t a = i;
    while (i < n && !isspace((unsigned char)line[i])) i++;
    size_t kl = i - a < kindlen - 1 ? i - a : kindlen - 1;
    memcpy(kind, line + a, kl);
    kind[kl] = 0;
    for (;;) {
        while (i < n && isspace((unsigned char)line[i])) i++;
        if (i >= n || line[i] == '#') break;
        size_t k = i;
        while (i < n && line[i] != '=' && !isspace((unsigned char)line[i])) i++;
        if (i >= n || line[i] != '=') {
            snprintf(err, errlen, "expected key=value after \"%.*s\"", (int)(i - k), line + k);
            return 0;
        }
        char *key = dupn(line + k, i - k);
        i++;
        char *val;
        if (i < n && line[i] == '"') {
            i++;
            val = malloc(n - i + 1);
            size_t vl = 0;
            int closed = 0;
            while (i < n) {
                char c = line[i++];
                if (c == '\\' && i < n) {
                    char e = line[i++];
                    val[vl++] = e == 'n' ? '\n' : e;
                } else if (c == '"') {
                    closed = 1;
                    break;
                } else
                    val[vl++] = c;
            }
            val[vl] = 0;
            if (!closed) {
                free(key);
                free(val);
                snprintf(err, errlen, "missing closing quote");
                return 0;
            }
        } else {
            size_t v = i;
            while (i < n && !isspace((unsigned char)line[i])) i++;
            val = dupn(line + v, i - v);
        }
        add_prop(node, key, val);
    }
    return 1;
}

afg_node *afg_parse(const char *text, char *err, int errlen)
{
    afg_node *win = calloc(1, sizeof *win);
    win->kind = AFG_WINDOW;
    afg_node *stack[64];
    int indents[64], depth = 0, have_window = 0, lineno = 0;
    const char *p = text;
    char e[200];
    while (*p) {
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - p) : strlen(p);
        const char *line = p;
        p = nl ? nl + 1 : p + len;
        lineno++;
        if (len && line[len - 1] == '\r') len--;
        size_t ind = 0;
        while (ind < len && (line[ind] == ' ' || line[ind] == '\t')) ind++;
        if (ind == len || line[ind] == '#') continue;
        afg_node *n = calloc(1, sizeof *n);
        n->line = lineno;
        char kind[32];
        if (!parse_line(line, len, n, kind, sizeof kind, e, sizeof e)) {
            snprintf(err, errlen, "line %d: %s", lineno, e);
            afg_free(n);
            afg_free(win);
            return NULL;
        }
        int k = afg_kind_by_name(kind);
        if (k < 0) {
            snprintf(err, errlen, "line %d: unknown object \"%s\"", lineno, kind);
            afg_free(n);
            afg_free(win);
            return NULL;
        }
        n->kind = (afg_kind)k;
        if (k == AFG_WINDOW) {
            if (have_window) {
                snprintf(err, errlen, "line %d: a second window", lineno);
                afg_free(n);
                afg_free(win);
                return NULL;
            }
            win->props = n->props;
            win->nprops = n->nprops;
            win->line = lineno;
            n->props = NULL;
            n->nprops = 0;
            afg_free(n);
            have_window = 1;
            continue;
        }
        while (depth > 0 && indents[depth - 1] >= (int)ind) depth--;
        afg_node *parent = depth ? stack[depth - 1] : win;
        const char *msg = NULL;
        if (parent == win && win->nchildren) msg = "only one root layout is allowed";
        else if (parent == win && !afg_is_container(n->kind)) msg = "the root must be a vlayout or hlayout";
        else if (!afg_is_container(parent->kind)) msg = "this object can't contain objects";
        else if (depth >= 64) msg = "nested too deeply";
        if (msg) {
            snprintf(err, errlen, "line %d: %s", lineno, msg);
            afg_free(n);
            afg_free(win);
            return NULL;
        }
        add_child(parent, n);
        stack[depth] = n;
        indents[depth] = (int)ind;
        depth++;
    }
    if (!win->nchildren) {
        afg_node *r = calloc(1, sizeof *r);
        r->kind = AFG_VLAYOUT;
        add_prop(r, dupn("id", 2), dupn("root", 4));
        add_child(win, r);
    }
    return win;
}

void afg_free(afg_node *n)
{
    if (!n) return;
    for (int i = 0; i < n->nprops; i++) {
        free(n->props[i].key);
        free(n->props[i].value);
    }
    free(n->props);
    for (int i = 0; i < n->nchildren; i++) afg_free(n->children[i]);
    free(n->children);
    free(n);
}

void afg_walk(afg_node *n, void (*fn)(afg_node *, void *), void *ud)
{
    fn(n, ud);
    for (int i = 0; i < n->nchildren; i++) afg_walk(n->children[i], fn, ud);
}

int afg_split_items(const char *s, char ***items)
{
    *items = NULL;
    if (!*s) return 0;
    int n = 1;
    for (const char *p = s; *p; p++) n += *p == '|';
    char **v = malloc(n * sizeof *v);
    int i = 0;
    for (const char *a = s;; i++) {
        const char *b = strchr(a, '|');
        v[i] = dupn(a, b ? (size_t)(b - a) : strlen(a));
        if (!b) break;
        a = b + 1;
    }
    *items = v;
    return n;
}

void afg_free_items(char **items, int n)
{
    for (int i = 0; i < n; i++) free(items[i]);
    free(items);
}
