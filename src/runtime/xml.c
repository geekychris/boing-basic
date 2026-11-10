/* xml.c - Boing.XmlDocument and its XmlElement nodes: a small XML DOM (docs/xml.md):
 *
 *     Dim doc As XmlDocument
 *     Set doc = CreateObject("XmlDocument")
 *     doc.Load "feed.xml"
 *     For Each item In doc.Root.FindAll("item")
 *         Print item.Child("title").Text; " "; item.Attribute("id")
 *     Next
 *     Set e = doc.Root.AddElement("item")
 *     e.Attribute("id") = 7 : e.Text = "new"
 *     doc.Save "feed.xml"
 *
 * The document owns every node; an XmlElement object holds a node and a reference to its
 * document, so nodes stay valid as long as some object refers to them. Removed nodes stay in
 * the document until it is freed. Comments and processing instructions are skipped when
 * parsing; whitespace-only text between elements is dropped. Strings are bytes: character
 * references below 256 become that byte (Latin-1), others UTF-8. */
#include "boing.h"

#include <stdio.h>
#include "fpath.h"           /* "DH1:/name" -> "DH1:name" on AmigaOS */
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define E_XML_PARSE 31401

enum { N_ELEM, N_TEXT };

typedef struct xnode {
    int type;
    char *name;                 /* element name */
    char *text;                 /* N_TEXT: the text (bytes) */
    long textlen;
    char **attrs;               /* name, value pairs */
    int nattrs;
    struct xnode **kids;
    int nkids, capkids;
    struct xnode *parent;
    struct xnode *next_all;     /* every node of the document, for freeing */
} xnode;

typedef struct {
    bb_obj hdr;
    xnode *root;
    xnode *all;
    int indent;
    char *decl;                 /* the <?xml ...?> declaration seen, or NULL */
} xdoc;

typedef struct {
    bb_obj hdr;
    xdoc *doc;                  /* retained */
    xnode *n;
} xelem;

typedef struct {                /* a list of elements (Children, FindAll) */
    bb_obj hdr;
    int n;
    bb_obj **items;
} xlist;

static const bb_class doc_class, elem_class, list_class;

/* ---- nodes ---- */

static xnode *new_node(xdoc *d, int type)
{
    xnode *n = (xnode *)calloc(1, sizeof *n);
    n->type = type;
    n->next_all = d->all;
    d->all = n;
    return n;
}

static void free_nodes(xdoc *d)
{
    xnode *n = d->all, *nx;
    int i;
    for (; n; n = nx) {
        nx = n->next_all;
        free(n->name);
        free(n->text);
        for (i = 0; i < 2 * n->nattrs; i++) free(n->attrs[i]);
        free(n->attrs);
        free(n->kids);
        free(n);
    }
    d->all = NULL;
    d->root = NULL;
}

static void add_kid(xnode *p, xnode *k)
{
    if (p->nkids == p->capkids) {
        p->capkids = p->capkids ? p->capkids * 2 : 4;
        p->kids = (xnode **)realloc(p->kids, sizeof(xnode *) * (size_t)p->capkids);
    }
    p->kids[p->nkids++] = k;
    k->parent = p;
}

static void detach(xnode *k)
{
    xnode *p = k->parent;
    int i;
    if (!p) return;
    for (i = 0; i < p->nkids; i++)
        if (p->kids[i] == k) {
            memmove(&p->kids[i], &p->kids[i + 1], sizeof(xnode *) * (size_t)(p->nkids - i - 1));
            p->nkids--;
            break;
        }
    k->parent = NULL;
}

static char *dupn(const char *p, size_t n)
{
    char *o = malloc(n + 1);
    memcpy(o, p, n);
    o[n] = 0;
    return o;
}

static const char *get_attr(const xnode *n, const char *name)
{
    int i;
    for (i = 0; i < n->nattrs; i++) if (!strcmp(n->attrs[2 * i], name)) return n->attrs[2 * i + 1];
    return NULL;
}

static void set_attr(xnode *n, const char *name, const char *value)
{
    int i;
    for (i = 0; i < n->nattrs; i++)
        if (!strcmp(n->attrs[2 * i], name)) {
            free(n->attrs[2 * i + 1]);
            n->attrs[2 * i + 1] = dupn(value, strlen(value));
            return;
        }
    n->attrs = (char **)realloc(n->attrs, sizeof(char *) * (size_t)(2 * n->nattrs + 2));
    n->attrs[2 * n->nattrs] = dupn(name, strlen(name));
    n->attrs[2 * n->nattrs + 1] = dupn(value, strlen(value));
    n->nattrs++;
}

static int remove_attr(xnode *n, const char *name)
{
    int i;
    for (i = 0; i < n->nattrs; i++)
        if (!strcmp(n->attrs[2 * i], name)) {
            free(n->attrs[2 * i]);
            free(n->attrs[2 * i + 1]);
            memmove(&n->attrs[2 * i], &n->attrs[2 * i + 2], sizeof(char *) * (size_t)(2 * (n->nattrs - i - 1)));
            n->nattrs--;
            return 1;
        }
    return 0;
}

/* ---- growable buffer ---- */

typedef struct { char *p; long n, cap; } sbuf;

static void sb_add(sbuf *b, const char *p, long n)
{
    if (n <= 0) return;
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2 + 64;
        b->p = (char *)realloc(b->p, (size_t)b->cap);
    }
    memcpy(b->p + b->n, p, (size_t)n);
    b->n += n;
    b->p[b->n] = 0;
}

static void sb_puts(sbuf *b, const char *s) { sb_add(b, s, (long)strlen(s)); }

/* ---- parser ---- */

typedef struct {
    const char *s, *p, *end;
    xdoc *d;
    char err[200];
    int failed;
    int depth;
} xparser;

static void perr(xparser *x, const char *msg)
{
    if (!x->failed) {
        int line = 1;
        const char *q;
        for (q = x->s; q < x->p && q < x->end; q++) if (*q == '\n') line++;
        snprintf(x->err, sizeof x->err, "%s (line %d)", msg, line);
    }
    x->failed = 1;
}

static int is_name_start(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':' || c >= 128; }
static int is_name(int c) { return is_name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'; }
static int is_space(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

static void skip_space(xparser *x) { while (x->p < x->end && is_space((unsigned char)*x->p)) x->p++; }

static char *parse_name(xparser *x)
{
    const char *st = x->p;
    if (x->p >= x->end || !is_name_start((unsigned char)*x->p)) {
        perr(x, "a name was expected");
        return NULL;
    }
    while (x->p < x->end && is_name((unsigned char)*x->p)) x->p++;
    return dupn(st, (size_t)(x->p - st));
}

static void put_code(sbuf *b, unsigned long c)
{
    char u[4];
    if (c < 256) {
        u[0] = (char)c;
        sb_add(b, u, 1);
    } else if (c < 0x800) {
        u[0] = (char)(0xC0 | (c >> 6)); u[1] = (char)(0x80 | (c & 63));
        sb_add(b, u, 2);
    } else if (c < 0x10000) {
        u[0] = (char)(0xE0 | (c >> 12)); u[1] = (char)(0x80 | ((c >> 6) & 63)); u[2] = (char)(0x80 | (c & 63));
        sb_add(b, u, 3);
    } else {
        u[0] = (char)(0xF0 | (c >> 18)); u[1] = (char)(0x80 | ((c >> 12) & 63));
        u[2] = (char)(0x80 | ((c >> 6) & 63)); u[3] = (char)(0x80 | (c & 63));
        sb_add(b, u, 4);
    }
}

/* text with entity references decoded, up to (not including) stop */
static void decode(xparser *x, sbuf *b, const char *from, const char *to)
{
    const char *p = from;
    while (p < to) {
        const char *amp = memchr(p, '&', (size_t)(to - p)), *semi;
        if (!amp) {
            sb_add(b, p, to - p);
            break;
        }
        sb_add(b, p, amp - p);
        semi = memchr(amp, ';', (size_t)(to - amp));
        if (!semi || semi - amp > 12) {
            sb_add(b, "&", 1);          /* a lone & (lenient) */
            p = amp + 1;
            continue;
        }
        if (amp[1] == '#') {
            unsigned long c = strtoul(amp[2] == 'x' || amp[2] == 'X' ? amp + 3 : amp + 2, NULL,
                                      amp[2] == 'x' || amp[2] == 'X' ? 16 : 10);
            put_code(b, c);
        } else {
            size_t n = (size_t)(semi - amp - 1);
            if (n == 2 && !strncmp(amp + 1, "lt", 2)) sb_add(b, "<", 1);
            else if (n == 2 && !strncmp(amp + 1, "gt", 2)) sb_add(b, ">", 1);
            else if (n == 3 && !strncmp(amp + 1, "amp", 3)) sb_add(b, "&", 1);
            else if (n == 4 && !strncmp(amp + 1, "quot", 4)) sb_add(b, "\"", 1);
            else if (n == 4 && !strncmp(amp + 1, "apos", 4)) sb_add(b, "'", 1);
            else if (n == 4 && !strncmp(amp + 1, "nbsp", 4)) sb_add(b, "\xA0", 1);
            else sb_add(b, amp, semi - amp + 1);    /* unknown entity: kept as it is */
        }
        p = semi + 1;
    }
    (void)x;
}

static int starts(xparser *x, const char *s)
{
    size_t n = strlen(s);
    return (size_t)(x->end - x->p) >= n && !memcmp(x->p, s, n);
}

/* skip <!-- -->, <? ?>, <!DOCTYPE ...> ; 1 if one was skipped */
static int skip_misc(xparser *x)
{
    if (starts(x, "<!--")) {
        const char *e = x->p + 4;
        for (; e + 2 < x->end; e++) if (e[0] == '-' && e[1] == '-' && e[2] == '>') break;
        if (e + 2 >= x->end) {
            perr(x, "a comment isn't closed");
            return 0;
        }
        x->p = e + 3;
        return 1;
    }
    if (starts(x, "<?")) {
        const char *e = x->p + 2;
        for (; e + 1 < x->end; e++) if (e[0] == '?' && e[1] == '>') break;
        if (e + 1 >= x->end) {
            perr(x, "<? isn't closed");
            return 0;
        }
        if (starts(x, "<?xml ") && !x->d->decl) x->d->decl = dupn(x->p, (size_t)(e + 2 - x->p));
        x->p = e + 2;
        return 1;
    }
    if (starts(x, "<!DOCTYPE") || starts(x, "<!doctype")) {
        int depth = 0;
        const char *e = x->p + 9;
        for (; e < x->end; e++) {
            if (*e == '[') depth++;
            else if (*e == ']') depth--;
            else if (*e == '>' && depth <= 0) break;
        }
        if (e >= x->end) {
            perr(x, "<!DOCTYPE isn't closed");
            return 0;
        }
        x->p = e + 1;
        return 1;
    }
    return 0;
}

static void add_text(xparser *x, xnode *parent, const char *a, const char *b, int raw)
{
    sbuf t = {NULL, 0, 0};
    xnode *tn;
    if (raw) sb_add(&t, a, b - a);
    else decode(x, &t, a, b);
    /* adjacent text (text + CDATA) joins */
    if (parent->nkids && parent->kids[parent->nkids - 1]->type == N_TEXT) {
        xnode *prev = parent->kids[parent->nkids - 1];
        prev->text = realloc(prev->text, (size_t)(prev->textlen + t.n + 1));
        memcpy(prev->text + prev->textlen, t.p ? t.p : "", (size_t)t.n);
        prev->textlen += t.n;
        prev->text[prev->textlen] = 0;
        free(t.p);
        return;
    }
    tn = new_node(x->d, N_TEXT);
    tn->text = t.p ? t.p : dupn("", 0);
    tn->textlen = t.n;
    add_kid(parent, tn);
}

static xnode *parse_element(xparser *x);

static void parse_content(xparser *x, xnode *e)
{
    for (;;) {
        const char *st = x->p;
        while (x->p < x->end && *x->p != '<') x->p++;
        if (x->p > st) {
            const char *q;
            int blank = 1;
            for (q = st; q < x->p; q++) if (!is_space((unsigned char)*q)) blank = 0;
            if (!blank) add_text(x, e, st, x->p, 0);
        }
        if (x->p >= x->end) {
            perr(x, "an element isn't closed");
            return;
        }
        if (starts(x, "</")) {
            char *nm;
            x->p += 2;
            nm = parse_name(x);
            if (x->failed) return;
            if (strcmp(nm, e->name)) {
                char m[200];
                snprintf(m, sizeof m, "</%.60s> doesn't close <%.60s>", nm, e->name);
                free(nm);
                perr(x, m);
                return;
            }
            free(nm);
            skip_space(x);
            if (x->p >= x->end || *x->p != '>') {
                perr(x, "> expected");
                return;
            }
            x->p++;
            return;
        }
        if (starts(x, "<![CDATA[")) {
            const char *a = x->p + 9, *q = a;
            for (; q + 2 < x->end; q++) if (q[0] == ']' && q[1] == ']' && q[2] == '>') break;
            if (q + 2 >= x->end) {
                perr(x, "CDATA isn't closed");
                return;
            }
            add_text(x, e, a, q, 1);
            x->p = q + 3;
            continue;
        }
        if (skip_misc(x)) continue;
        if (x->failed) return;
        {
            xnode *k = parse_element(x);
            if (x->failed) return;
            add_kid(e, k);
        }
    }
}

static xnode *parse_element(xparser *x)
{
    xnode *e;
    if (++x->depth > 500) {
        perr(x, "elements nested too deeply");
        return NULL;
    }
    x->p++;                     /* '<' */
    e = new_node(x->d, N_ELEM);
    e->name = parse_name(x);
    if (x->failed) return NULL;
    for (;;) {
        char *an;
        char q;
        const char *vs;
        sbuf v = {NULL, 0, 0};
        skip_space(x);
        if (x->p >= x->end) {
            perr(x, "a tag isn't closed");
            return NULL;
        }
        if (*x->p == '>') {
            x->p++;
            parse_content(x, e);
            break;
        }
        if (*x->p == '/' && x->p + 1 < x->end && x->p[1] == '>') {
            x->p += 2;
            break;
        }
        an = parse_name(x);
        if (x->failed) return NULL;
        skip_space(x);
        if (x->p >= x->end || *x->p != '=') {
            free(an);
            perr(x, "= expected after an attribute name");
            return NULL;
        }
        x->p++;
        skip_space(x);
        if (x->p >= x->end || (*x->p != '"' && *x->p != '\'')) {
            free(an);
            perr(x, "an attribute value must be in quotes");
            return NULL;
        }
        q = *x->p++;
        vs = x->p;
        while (x->p < x->end && *x->p != q) x->p++;
        if (x->p >= x->end) {
            free(an);
            perr(x, "an attribute value isn't closed");
            return NULL;
        }
        decode(x, &v, vs, x->p);
        x->p++;
        set_attr(e, an, v.p ? v.p : "");
        free(an);
        free(v.p);
    }
    x->depth--;
    return e;
}

static int parse_doc(xdoc *d, const char *s, long len, char *err, int errlen)
{
    xparser x;
    memset(&x, 0, sizeof x);
    x.s = x.p = s;
    x.end = s + len;
    x.d = d;
    free_nodes(d);
    free(d->decl);
    d->decl = NULL;
    if (len >= 3 && (unsigned char)s[0] == 0xEF && (unsigned char)s[1] == 0xBB && (unsigned char)s[2] == 0xBF) x.p += 3;
    for (;;) {
        skip_space(&x);
        if (x.p >= x.end) break;
        if (skip_misc(&x)) continue;
        if (x.failed) break;
        if (*x.p != '<') {
            perr(&x, "text outside the root element");
            break;
        }
        if (d->root) {
            perr(&x, "more than one root element");
            break;
        }
        d->root = parse_element(&x);
        if (x.failed) break;
    }
    if (!x.failed && !d->root) perr(&x, "no root element");
    if (x.failed) {
        snprintf(err, (size_t)errlen, "%s", x.err);
        free_nodes(d);
        return 0;
    }
    return 1;
}

/* ---- writer ---- */

static void escape(sbuf *b, const char *s, long n, int attr)
{
    long i, st = 0;
    for (i = 0; i < n; i++) {
        const char *rep = NULL;
        switch (s[i]) {
        case '<': rep = "&lt;"; break;
        case '>': rep = "&gt;"; break;
        case '&': rep = "&amp;"; break;
        case '"': if (attr) rep = "&quot;"; break;
        case '\n': if (attr) rep = "&#10;"; break;
        case '\t': if (attr) rep = "&#9;"; break;
        case '\r': rep = "&#13;"; break;
        }
        if (rep) {
            sb_add(b, s + st, i - st);
            sb_puts(b, rep);
            st = i + 1;
        }
    }
    sb_add(b, s + st, n - st);
}

static void write_node(sbuf *b, const xnode *n, int indent, int level)
{
    int i, only_text = 1;
    if (n->type == N_TEXT) {
        escape(b, n->text, n->textlen, 0);
        return;
    }
    for (i = 0; i < n->nkids; i++) if (n->kids[i]->type != N_TEXT) only_text = 0;
    if (indent) for (i = 0; i < level; i++) sb_puts(b, "  ");
    sb_puts(b, "<");
    sb_puts(b, n->name);
    for (i = 0; i < n->nattrs; i++) {
        sb_puts(b, " ");
        sb_puts(b, n->attrs[2 * i]);
        sb_puts(b, "=\"");
        escape(b, n->attrs[2 * i + 1], (long)strlen(n->attrs[2 * i + 1]), 1);
        sb_puts(b, "\"");
    }
    if (!n->nkids) {
        sb_puts(b, "/>");
        if (indent) sb_puts(b, "\n");
        return;
    }
    sb_puts(b, ">");
    /* elements with text in them (mixed content) are written as they are, without indenting */
    if (only_text || !indent) {
        int mixed = !only_text;
        for (i = 0; i < n->nkids; i++) write_node(b, n->kids[i], 0, 0);
        (void)mixed;
    } else {
        int has_text = 0;
        for (i = 0; i < n->nkids; i++) if (n->kids[i]->type == N_TEXT) has_text = 1;
        if (has_text)
            for (i = 0; i < n->nkids; i++) write_node(b, n->kids[i], 0, 0);
        else {
            sb_puts(b, "\n");
            for (i = 0; i < n->nkids; i++) write_node(b, n->kids[i], 1, level + 1);
            for (i = 0; i < level; i++) sb_puts(b, "  ");
        }
    }
    sb_puts(b, "</");
    sb_puts(b, n->name);
    sb_puts(b, ">");
    if (indent) sb_puts(b, "\n");
}

static bb_str *to_xml(const xnode *n, int indent)
{
    sbuf b = {NULL, 0, 0};
    bb_str *r;
    write_node(&b, n, indent, 0);
    if (indent && b.n && b.p[b.n - 1] == '\n') b.n--;
    r = bb_str_new(b.p ? b.p : "", (int32_t)b.n);
    free(b.p);
    return r;
}

static void inner_text(sbuf *b, const xnode *n)
{
    int i;
    if (n->type == N_TEXT) {
        sb_add(b, n->text, n->textlen);
        return;
    }
    for (i = 0; i < n->nkids; i++) inner_text(b, n->kids[i]);
}

/* ---- arguments ---- */

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static char *arg_c(int argc, bb_value *argv, int i)
{
    bb_str *s = arg_str(argc, argv, i);
    char *c = dupn(bb_str_ptr(s), (size_t)bb_str_len(s));
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

static int valid_name(const char *s)
{
    if (!*s || !is_name_start((unsigned char)*s)) return 0;
    for (; *s; s++) if (!is_name((unsigned char)*s)) return 0;
    return 1;
}

static bb_obj *wrap(xdoc *d, xnode *n)
{
    xelem *e;
    if (!n) return NULL;
    e = (xelem *)bb_obj_new(&elem_class);
    e->doc = (xdoc *)bb_obj_retain(&d->hdr);
    e->n = n;
    return &e->hdr;
}

static xnode *elem_arg(xdoc *d, int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) bb_raise(450, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type != BB_OBJECT || !v->u.o || v->u.o->cls != &elem_class) bb_raise(13, "an XmlElement was expected");
    if (((xelem *)v->u.o)->doc != d) bb_raise(5, "the element belongs to another XmlDocument");
    return ((xelem *)v->u.o)->n;
}

static bb_obj *new_list(xdoc *d, xnode **nodes, int n)
{
    xlist *l = (xlist *)bb_obj_new(&list_class);
    int i;
    l->items = (bb_obj **)malloc(sizeof(bb_obj *) * (size_t)(n ? n : 1));
    for (i = 0; i < n; i++) l->items[i] = wrap(d, nodes[i]);
    l->n = n;
    return &l->hdr;
}

typedef struct { xnode **v; int n, cap; } nvec;
static void nv_add(nvec *v, xnode *x)
{
    if (v->n == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 16;
        v->v = (xnode **)realloc(v->v, sizeof(xnode *) * (size_t)v->cap);
    }
    v->v[v->n++] = x;
}

/* descendants named name ("*" any), in document order */
static void find_all(const xnode *n, const char *name, nvec *out, int first_only)
{
    int i;
    for (i = 0; i < n->nkids; i++) {
        xnode *k = n->kids[i];
        if (k->type != N_ELEM) continue;
        if (!strcmp(name, "*") || !strcmp(k->name, name)) {
            nv_add(out, k);
            if (first_only) return;
        }
        find_all(k, name, out, first_only);
        if (first_only && out->n) return;
    }
}

/* a path of child names: "channel/item/title" (each step all matching children) */
static void select_path(xnode *n, const char *path, nvec *out)
{
    const char *slash = strchr(path, '/');
    size_t len = slash ? (size_t)(slash - path) : strlen(path);
    int i;
    for (i = 0; i < n->nkids; i++) {
        xnode *k = n->kids[i];
        if (k->type != N_ELEM) continue;
        if ((len == 1 && path[0] == '*') || (strlen(k->name) == len && !strncmp(k->name, path, len))) {
            if (slash) select_path(k, slash + 1, out);
            else nv_add(out, k);
        }
    }
}

/* ---- XmlDocument ---- */

enum { D_LOAD = 1, D_LOADXML, D_SAVE, D_ROOT, D_XML, D_INDENT, D_CREATEELEMENT, D_CREATEROOT, D_FINDALL, D_FIND,
       D_SELECT };
static const struct { const char *name; int id; } members[] = {
    {"Load", D_LOAD}, {"LoadXml", D_LOADXML}, {"Save", D_SAVE}, {"Root", D_ROOT}, {"Xml", D_XML},
    {"Indent", D_INDENT}, {"CreateElement", D_CREATEELEMENT}, {"CreateRoot", D_CREATEROOT},
    {"FindAll", D_FINDALL}, {"Find", D_FIND}, {"SelectNodes", D_SELECT},
};

static void load_text(xdoc *d, const char *s, long n)
{
    char err[260];
    if (!parse_doc(d, s, n, err, sizeof err)) {
        char m[300];
        snprintf(m, sizeof m, "bad XML: %s", err);
        bb_raise(E_XML_PARSE, m);
    }
}

static bb_str *doc_xml(xdoc *d)
{
    sbuf b = {NULL, 0, 0};
    bb_str *x, *r;
    sb_puts(&b, d->decl ? d->decl : "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>");
    sb_puts(&b, "\n");
    if (d->root) {
        x = to_xml(d->root, d->indent);
        sb_add(&b, bb_str_ptr(x), bb_str_len(x));
        bb_str_release(x);
    }
    sb_puts(&b, "\n");
    r = bb_str_new(b.p, (int32_t)b.n);
    free(b.p);
    return r;
}

static void d_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    xdoc *d = (xdoc *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char *a;
    switch (id) {
    case D_LOAD: {
        FILE *f;
        long n;
        char *buf;
        a = arg_c(argc, argv, 0);
        f = fopen(a, "rb");
        free(a);
        if (!f) bb_raise(53, NULL);
        fseek(f, 0, SEEK_END);
        n = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)n + 1);
        if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) n = 0;
        fclose(f);
        buf[n] = 0;
        {
            bb_cleanup cl;
            cl.prev = bb_cleanups;
            cl.fn = free;
            cl.ctx = buf;
            bb_cleanups = &cl;
            load_text(d, buf, n);
            bb_cleanups = cl.prev;
        }
        free(buf);
        return;
    }
    case D_LOADXML: {
        bb_str *s = arg_str(argc, argv, 0);
        bb_cleanup cl;
        cl.prev = bb_cleanups;
        cl.fn = (void (*)(void *))bb_str_release;
        cl.ctx = s;
        bb_cleanups = &cl;
        load_text(d, bb_str_ptr(s), bb_str_len(s));
        bb_cleanups = cl.prev;
        bb_str_release(s);
        return;
    }
    case D_SAVE: {
        FILE *f;
        bb_str *x;
        a = arg_c(argc, argv, 0);
        f = fopen(a, "wb");
        free(a);
        if (!f) bb_raise(75, NULL);
        x = doc_xml(d);
        if (fwrite(bb_str_ptr(x), 1, (size_t)bb_str_len(x), f) != (size_t)bb_str_len(x)) {
            fclose(f);
            bb_str_release(x);
            bb_raise(61, NULL);
        }
        bb_str_release(x);
        if (fclose(f)) bb_raise(61, NULL);
        return;
    }
    case D_ROOT:
        if (set) {
            xnode *n = elem_arg(d, argc, argv, argc - 1);
            detach(n);
            d->root = n;
            return;
        }
        *ret = bb_v_obj(wrap(d, d->root));
        return;
    case D_XML:
        if (set) {
            bb_str *s = arg_str(argc, argv, argc - 1);
            load_text(d, bb_str_ptr(s), bb_str_len(s));
            bb_str_release(s);
        } else
            *ret = bb_v_str(doc_xml(d));
        return;
    case D_INDENT:
        if (set) {
            bb_value t;
            d->indent = bb_v_to_bool(bb_v_deref(&argv[argc - 1], &t)) != 0;
        } else
            *ret = bb_v_bool(d->indent);
        return;
    case D_CREATEELEMENT:
    case D_CREATEROOT: {
        xnode *n;
        a = arg_c(argc, argv, 0);
        if (!valid_name(a)) {
            free(a);
            bb_raise(5, "not a valid element name");
        }
        n = new_node(d, N_ELEM);
        n->name = a;
        if (id == D_CREATEROOT) d->root = n;
        *ret = bb_v_obj(wrap(d, n));
        return;
    }
    case D_SELECT: {            /* SelectNodes("rss/channel/item"): the path starts at the root element */
        nvec v = {NULL, 0, 0};
        a = arg_c(argc, argv, 0);
        if (d->root) {
            xnode top;
            xnode *kids[1];
            memset(&top, 0, sizeof top);
            kids[0] = d->root;
            top.kids = kids;
            top.nkids = 1;
            select_path(&top, a, &v);
        }
        free(a);
        *ret = bb_v_obj(new_list(d, v.v, v.n));
        free(v.v);
        return;
    }
    case D_FINDALL:
    case D_FIND: {
        nvec v = {NULL, 0, 0};
        a = arg_c(argc, argv, 0);
        if (d->root) {
            if (!strcmp(a, "*") || !strcmp(d->root->name, a)) nv_add(&v, d->root);
            if (!(id == D_FIND && v.n)) find_all(d->root, a, &v, id == D_FIND);
        }
        free(a);
        if (id == D_FIND) *ret = bb_v_obj(v.n ? wrap(d, v.v[0]) : NULL);
        else *ret = bb_v_obj(new_list(d, v.v, v.n));
        free(v.v);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t tab_find(const void *tab, size_t n, size_t stride, const char *name)
{
    size_t i;
    for (i = 0; i < n; i++) {
        const struct { const char *name; int id; } *e = (const void *)((const char *)tab + i * stride);
        if (!strcasecmp(e->name, name)) return e->id;
    }
    return BB_NOMEMBER;
}

static int32_t d_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return D_XML;
    return tab_find(members, sizeof members / sizeof members[0], sizeof members[0], name);
}

static void d_terminate(bb_obj *self)
{
    xdoc *d = (xdoc *)self;
    free_nodes(d);
    free(d->decl);
}

static const bb_class doc_class = {
    "XmlDocument", sizeof(xdoc), d_find, d_invoke, d_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_xmldoc_class(void) { return &doc_class; }
bb_obj *bb_xmldoc_new(void)
{
    xdoc *d = (xdoc *)bb_obj_new(&doc_class);
    d->indent = 1;
    return &d->hdr;
}

/* ---- XmlElement ---- */

enum { E_NAME = 1, E_TEXT, E_ATTRIBUTE, E_HASATTRIBUTE, E_REMOVEATTRIBUTE, E_ATTRIBUTENAMES, E_CHILDREN, E_CHILD,
       E_FIND, E_FINDALL, E_SELECT, E_PARENT, E_APPENDCHILD, E_ADDELEMENT, E_REMOVECHILD, E_REMOVE, E_XML,
       E_INNERXML, E_CHILDCOUNT, E_CHILDTEXT, E_DOCUMENT, E_INSERTBEFORE };
static const struct { const char *name; int id; } elem_tab[] = {
    {"Name", E_NAME}, {"Text", E_TEXT}, {"Attribute", E_ATTRIBUTE}, {"HasAttribute", E_HASATTRIBUTE},
    {"RemoveAttribute", E_REMOVEATTRIBUTE}, {"AttributeNames", E_ATTRIBUTENAMES}, {"Children", E_CHILDREN},
    {"Child", E_CHILD}, {"Find", E_FIND}, {"FindAll", E_FINDALL}, {"SelectNodes", E_SELECT}, {"Parent", E_PARENT},
    {"AppendChild", E_APPENDCHILD}, {"AddElement", E_ADDELEMENT}, {"RemoveChild", E_REMOVECHILD},
    {"Remove", E_REMOVE}, {"Xml", E_XML}, {"InnerXml", E_INNERXML}, {"ChildCount", E_CHILDCOUNT},
    {"ChildText", E_CHILDTEXT}, {"Document", E_DOCUMENT}, {"InsertBefore", E_INSERTBEFORE},
};

static int is_ancestor(const xnode *a, const xnode *n)
{
    for (; n; n = n->parent) if (n == a) return 1;
    return 0;
}

static void set_text(xdoc *d, xnode *n, const bb_str *s)
{
    xnode *t;
    while (n->nkids) detach(n->kids[n->nkids - 1]);
    if (!bb_str_len(s)) return;
    t = new_node(d, N_TEXT);
    t->text = dupn(bb_str_ptr(s), (size_t)bb_str_len(s));
    t->textlen = bb_str_len(s);
    add_kid(n, t);
}

static xnode *first_child(xnode *n, const char *name)
{
    int i;
    for (i = 0; i < n->nkids; i++)
        if (n->kids[i]->type == N_ELEM && (!strcmp(name, "*") || !strcmp(n->kids[i]->name, name))) return n->kids[i];
    return NULL;
}

static void e_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    xelem *e = (xelem *)self;
    xdoc *d = e->doc;
    xnode *n = e->n;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char *a;
    switch (id) {
    case E_NAME:
        if (set) {
            a = arg_c(argc, argv, argc - 1);
            if (!valid_name(a)) {
                free(a);
                bb_raise(5, "not a valid element name");
            }
            free(n->name);
            n->name = a;
        } else
            *ret = bb_v_str(bb_str_from_c(n->name));
        return;
    case E_TEXT:
        if (set) {
            bb_str *s = arg_str(argc, argv, argc - 1);
            set_text(d, n, s);
            bb_str_release(s);
        } else {
            sbuf b = {NULL, 0, 0};
            inner_text(&b, n);
            *ret = bb_v_str(bb_str_new(b.p ? b.p : "", (int32_t)b.n));
            free(b.p);
        }
        return;
    case E_ATTRIBUTE:
        if (set) {
            char *v;
            if (argc != 2) bb_raise(450, NULL);
            a = arg_c(argc, argv, 0);
            if (!valid_name(a)) {
                free(a);
                bb_raise(5, "not a valid attribute name");
            }
            v = arg_c(argc, argv, 1);
            set_attr(n, a, v);
            free(a);
            free(v);
        } else {
            const char *v;
            a = arg_c(argc, argv, 0);
            v = get_attr(n, a);
            free(a);
            if (v) *ret = bb_v_str(bb_str_from_c(v));
            else if (present(argc, argv, 1)) *ret = bb_v_str(arg_str(argc, argv, 1));
            else *ret = bb_v_str(bb_str_from_c(""));
        }
        return;
    case E_HASATTRIBUTE:
        a = arg_c(argc, argv, 0);
        *ret = bb_v_bool(get_attr(n, a) != NULL);
        free(a);
        return;
    case E_REMOVEATTRIBUTE:
        a = arg_c(argc, argv, 0);
        *ret = bb_v_bool(remove_attr(n, a));
        free(a);
        return;
    case E_ATTRIBUTENAMES: {
        bb_array *arr = bb_arr_new1(BB_STRING, 0, n->nattrs - 1);
        int i;
        for (i = 0; i < n->nattrs; i++) *(bb_str **)bb_arr_elem1(arr, i) = bb_str_from_c(n->attrs[2 * i]);
        *ret = bb_v_arr(arr);
        return;
    }
    case E_CHILDREN: {
        nvec v = {NULL, 0, 0};
        int i;
        for (i = 0; i < n->nkids; i++) if (n->kids[i]->type == N_ELEM) nv_add(&v, n->kids[i]);
        if (argc > 0) {             /* Children(i): one of them, from 0 */
            bb_value t;
            int32_t k = (int32_t)bb_v_to_long(bb_v_deref(&argv[0], &t));
            if (k < 0 || k >= v.n) {
                free(v.v);
                bb_raise(9, NULL);
            }
            *ret = bb_v_obj(wrap(d, v.v[k]));
        } else
            *ret = bb_v_obj(new_list(d, v.v, v.n));
        free(v.v);
        return;
    }
    case E_CHILDCOUNT: {
        int i, c = 0;
        for (i = 0; i < n->nkids; i++) if (n->kids[i]->type == N_ELEM) c++;
        *ret = bb_v_long(c);
        return;
    }
    case E_CHILD:
        a = arg_c(argc, argv, 0);
        *ret = bb_v_obj(wrap(d, first_child(n, a)));
        free(a);
        return;
    case E_CHILDTEXT: {         /* ChildText(name [, default]): a child's text, default if there is none */
        xnode *k;
        a = arg_c(argc, argv, 0);
        k = first_child(n, a);
        free(a);
        if (k) {
            sbuf b = {NULL, 0, 0};
            inner_text(&b, k);
            *ret = bb_v_str(bb_str_new(b.p ? b.p : "", (int32_t)b.n));
            free(b.p);
        } else
            *ret = present(argc, argv, 1) ? bb_v_str(arg_str(argc, argv, 1)) : bb_v_str(bb_str_from_c(""));
        return;
    }
    case E_FIND:
    case E_FINDALL:
    case E_SELECT: {
        nvec v = {NULL, 0, 0};
        a = arg_c(argc, argv, 0);
        if (id == E_SELECT) select_path(n, a, &v);
        else find_all(n, a, &v, id == E_FIND);
        free(a);
        if (id == E_FIND) *ret = bb_v_obj(v.n ? wrap(d, v.v[0]) : NULL);
        else *ret = bb_v_obj(new_list(d, v.v, v.n));
        free(v.v);
        return;
    }
    case E_PARENT:
        *ret = bb_v_obj(wrap(d, n->parent));
        return;
    case E_DOCUMENT:
        *ret = bb_v_obj(bb_obj_retain(&d->hdr));
        return;
    case E_APPENDCHILD:
    case E_INSERTBEFORE: {
        xnode *k = elem_arg(d, argc, argv, 0);
        if (is_ancestor(k, n)) bb_raise(5, "an element can't be put inside itself");
        if (k == d->root) d->root = NULL;
        detach(k);
        add_kid(n, k);
        if (id == E_INSERTBEFORE) {
            xnode *ref = elem_arg(d, argc, argv, 1);
            int i, at = -1;
            for (i = 0; i < n->nkids; i++) if (n->kids[i] == ref) at = i;
            if (at < 0 || ref->parent != n) bb_raise(5, "InsertBefore: the second element isn't a child of this one");
            memmove(&n->kids[at + 1], &n->kids[at], sizeof(xnode *) * (size_t)(n->nkids - 1 - at));
            n->kids[at] = k;
        }
        *ret = bb_v_obj(wrap(d, k));
        return;
    }
    case E_ADDELEMENT: {        /* AddElement(name [, text]): a new child element, returned */
        xnode *k;
        a = arg_c(argc, argv, 0);
        if (!valid_name(a)) {
            free(a);
            bb_raise(5, "not a valid element name");
        }
        k = new_node(d, N_ELEM);
        k->name = a;
        add_kid(n, k);
        if (present(argc, argv, 1)) {
            bb_str *s = arg_str(argc, argv, 1);
            set_text(d, k, s);
            bb_str_release(s);
        }
        *ret = bb_v_obj(wrap(d, k));
        return;
    }
    case E_REMOVECHILD: {
        xnode *k = elem_arg(d, argc, argv, 0);
        if (k->parent != n) bb_raise(5, "RemoveChild: not a child of this element");
        detach(k);
        return;
    }
    case E_REMOVE:
        if (n == d->root) d->root = NULL;
        detach(n);
        return;
    case E_XML:
        *ret = bb_v_str(to_xml(n, d->indent));
        return;
    case E_INNERXML: {
        sbuf b = {NULL, 0, 0};
        int i;
        for (i = 0; i < n->nkids; i++) write_node(&b, n->kids[i], 0, 0);
        *ret = bb_v_str(bb_str_new(b.p ? b.p : "", (int32_t)b.n));
        free(b.p);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t e_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return E_TEXT;
    return tab_find(elem_tab, sizeof elem_tab / sizeof elem_tab[0], sizeof elem_tab[0], name);
}

static void e_terminate(bb_obj *self) { bb_obj_release(&((xelem *)self)->doc->hdr); }

static const bb_class elem_class = {
    "XmlElement", sizeof(xelem), e_find, e_invoke, e_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_xmlelem_class(void) { return &elem_class; }

/* ---- element lists ---- */

enum { L_COUNT = 1, L_ITEM };
static const struct { const char *name; int id; } list_tab[] = { {"Count", L_COUNT}, {"Item", L_ITEM} };

static void l_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    xlist *l = (xlist *)self;
    bb_value t;
    if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);
    if (id == L_COUNT) {
        *ret = bb_v_long(l->n);
        return;
    }
    if (id == L_ITEM) {
        int32_t i;
        if (argc < 1) bb_raise(450, NULL);
        i = (int32_t)bb_v_to_long(bb_v_deref(&argv[0], &t));
        if (i < 0 || i >= l->n) bb_raise(9, NULL);
        *ret = bb_v_obj(bb_obj_retain(l->items[i]));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t l_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return L_ITEM;
    return tab_find(list_tab, 2, sizeof list_tab[0], name);
}

static void l_terminate(bb_obj *self)
{
    xlist *l = (xlist *)self;
    int i;
    for (i = 0; i < l->n; i++) bb_obj_release(l->items[i]);
    free(l->items);
}

static int l_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    xlist *l = (xlist *)self;
    int32_t i = state->type == BB_LONG ? state->u.l : 0;
    if (i >= l->n) return 0;
    *out = bb_v_obj(bb_obj_retain(l->items[i]));
    *state = bb_v_long(i + 1);
    return 1;
}

static const bb_class list_class = {
    "XmlElements", sizeof(xlist), l_find, l_invoke, l_terminate, l_iterate, NULL, 0, NULL, 0, NULL, NULL
};
