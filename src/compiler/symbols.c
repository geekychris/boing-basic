/* symbols.c - `boing symbols`: one declaration per line for IDE outlines and completion
 *
 * Format (tab separated): kind  name  line  signature  [scope]
 *   kind: sub function property-get property-let property-set variable const type
 *         field enum enummember declare event class label param local
 *   scope: empty for module level, otherwise the procedure (or type/enum) name
 * Works from the parse tree only, so it also works on files with semantic errors.
 */
#include "bbc.h"
#include <string.h>

static void type_text(Buf *b, Node *ty, Node *decl)
{
    if (!ty) {
        if (decl && decl->suffix) buf_printf(b, "%c", decl->suffix);
        return;
    }
    buf_puts(b, " As ");
    if (decl && (decl->flags & NF_NEW)) buf_puts(b, "New ");
    buf_puts(b, ty->name);
    if (ty->b && ty->b->kind == E_INT) buf_printf(b, " * %lld", (long long)ty->b->ival);
}

static void param_text(Buf *b, Node *pn)
{
    if (pn->ival & 1) buf_puts(b, "Optional ");
    if (pn->ival & 2) buf_puts(b, "ParamArray ");
    else if (pn->op == 0) buf_puts(b, "ByVal ");
    else if (pn->op == 1) buf_puts(b, "ByRef ");
    buf_puts(b, pn->name);
    if (pn->flags & NF_ARRAY) buf_puts(b, "()");
    type_text(b, pn->a, pn);
    if (pn->c) {
        Node *d = pn->c;
        if (d->kind == E_INT) buf_printf(b, " = %lld", (long long)d->ival);
        else if (d->kind == E_STR) buf_printf(b, " = \"%s\"", d->name);
        else if (d->kind == E_BOOL) buf_printf(b, " = %s", d->ival ? "True" : "False");
        else buf_puts(b, " = ...");
    }
}

static const char *proc_kind(int op)
{
    switch (op) {
    case PK_SUB: return "sub";
    case PK_FUNCTION: return "function";
    case PK_PGET: return "property-get";
    case PK_PLET: return "property-let";
    default: return "property-set";
    }
}

static const char *proc_kw(int op)
{
    switch (op) {
    case PK_SUB: return "Sub";
    case PK_FUNCTION: return "Function";
    case PK_PGET: return "Property Get";
    case PK_PLET: return "Property Let";
    default: return "Property Set";
    }
}

static void emit(FILE *out, const char *kind, const char *name, int line, const char *sig, const char *scope)
{
    fprintf(out, "%s\t%s\t%d\t%s", kind, name, line, sig ? sig : "");
    if (scope && *scope) fprintf(out, "\t%s", scope);
    fprintf(out, "\n");
}

static void vis(Buf *b, int flags)
{
    if (flags & NF_FRIEND) buf_puts(b, "Friend ");
    else if (flags & NF_PUBLIC) buf_puts(b, "Public ");
    else if (flags & NF_PRIVATE) buf_puts(b, "Private ");
}

static void locals_in(FILE *out, NodeList *body, const char *scope)
{
    int i, j;
    for (i = 0; i < body->n; i++) {
        Node *s = body->v[i];
        if (!s) continue;
        if (s->kind == S_DIM || s->kind == S_CONST) {
            for (j = 0; j < s->list.n; j++) {
                Node *d = s->list.v[j];
                Buf b = {0, 0, 0};
                buf_puts(&b, s->kind == S_CONST ? "Const " : (s->flags & NF_STATIC) ? "Static " : "Dim ");
                buf_puts(&b, d->name);
                if (d->flags & NF_ARRAY) buf_puts(&b, "()");
                type_text(&b, d->a, d);
                emit(out, s->kind == S_CONST ? "const" : "local", d->name, d->line, b.p, scope);
                buf_free(&b);
            }
        } else if (s->kind == S_LABEL) {
            emit(out, "label", s->name, s->line, "", scope);
        }
        locals_in(out, &s->list, scope);
        locals_in(out, &s->list2, scope);
        if (s->kind == S_IF || s->kind == S_SELECT)
            for (j = 0; j < s->list.n; j++) locals_in(out, &s->list.v[j]->list2, scope);
    }
}

void print_symbols(Program *p, Module *m, FILE *out)
{
    int i, j;
    (void)p;
    if (m->is_class) emit(out, "class", m->name, 1, xsprintf("Class %s", m->name), "");
    for (i = 0; i < m->decls.n; i++) {
        Node *d = m->decls.v[i];
        Buf b = {0, 0, 0};
        switch (d->kind) {
        case D_PROC: case D_DECLARE: case D_EVENT: {
            vis(&b, d->flags);
            if (d->kind == D_DECLARE) {
                buf_printf(&b, "Declare %s %s Lib \"%s\"", d->op == PK_SUB ? "Sub" : "Function", d->name, d->b ? d->b->name : "");
            } else if (d->kind == D_EVENT) buf_printf(&b, "Event %s", d->name);
            else {
                if (d->flags & NF_STATIC) buf_puts(&b, "Static ");
                buf_printf(&b, "%s %s", proc_kw(d->op), d->name);
            }
            buf_puts(&b, "(");
            for (j = 0; j < d->list.n; j++) {
                if (j) buf_puts(&b, ", ");
                param_text(&b, d->list.v[j]);
            }
            buf_puts(&b, ")");
            if (d->a) type_text(&b, d->a, NULL);
            else if (d->suffix && (d->op == PK_FUNCTION || d->op == PK_PGET)) buf_printf(&b, " As %c", d->suffix);
            emit(out, d->kind == D_DECLARE ? "declare" : d->kind == D_EVENT ? "event" : proc_kind(d->op), d->name, d->line, b.p, "");
            for (j = 0; j < d->list.n; j++) {
                Buf pb = {0, 0, 0};
                param_text(&pb, d->list.v[j]);
                emit(out, "param", d->list.v[j]->name, d->list.v[j]->line, pb.p, d->name);
                buf_free(&pb);
            }
            if (d->kind == D_PROC) locals_in(out, &d->list2, d->name);
            break;
        }
        case D_DIM:
            for (j = 0; j < d->list.n; j++) {
                Node *v = d->list.v[j];
                Buf vb = {0, 0, 0};
                vis(&vb, d->flags);
                if (!(d->flags & (NF_PUBLIC | NF_PRIVATE))) buf_puts(&vb, "Dim ");
                if (v->flags & NF_WITHEVENTS) buf_puts(&vb, "WithEvents ");
                buf_puts(&vb, v->name);
                if (v->flags & NF_ARRAY) buf_puts(&vb, "()");
                type_text(&vb, v->a, v);
                emit(out, "variable", v->name, v->line, vb.p, "");
                buf_free(&vb);
            }
            break;
        case D_CONST:
            for (j = 0; j < d->list.n; j++) {
                Node *v = d->list.v[j];
                Buf vb = {0, 0, 0};
                vis(&vb, d->flags);
                buf_printf(&vb, "Const %s", v->name);
                type_text(&vb, v->a, v);
                emit(out, "const", v->name, v->line, vb.p, "");
                buf_free(&vb);
            }
            break;
        case D_TYPE:
            vis(&b, d->flags);
            buf_printf(&b, "Type %s", d->name);
            emit(out, "type", d->name, d->line, b.p, "");
            for (j = 0; j < d->list.n; j++) {
                Node *f = d->list.v[j];
                Buf fb = {0, 0, 0};
                buf_puts(&fb, f->name);
                if (f->flags & NF_ARRAY) buf_puts(&fb, "()");
                type_text(&fb, f->a, f);
                emit(out, "field", f->name, f->line, fb.p, d->name);
                buf_free(&fb);
            }
            break;
        case D_ENUM:
            vis(&b, d->flags);
            buf_printf(&b, "Enum %s", d->name);
            emit(out, "enum", d->name, d->line, b.p, "");
            for (j = 0; j < d->list.n; j++)
                emit(out, "enummember", d->list.v[j]->name, d->list.v[j]->line, "", d->name);
            break;
        case D_IMPLEMENTS:
            emit(out, "implements", d->name, d->line, xsprintf("Implements %s", d->name), "");
            break;
        default:
            break;
        }
        buf_free(&b);
    }
    locals_in(out, &m->mainstmts, "");
}
