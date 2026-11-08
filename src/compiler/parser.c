/* parser.c - recursive-descent parser for Boing BASIC (VB6 dialect) */
#include "bbc.h"
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

typedef struct P {
    Program *prog;
    Module *mod;
    Token *t;
    int n, i;
    int file;
    int pending_next;       /* "Next i, j": loops still to close */
    int in_proc;
    int single_line;        /* inside a single-line If */
    jmp_buf jb;             /* error recovery */
} P;

static Token *tk(P *p) { return &p->t[p->i]; }
static Token *tkn(P *p, int k) { int j = p->i + k; return &p->t[j < p->n ? j : p->n - 1]; }
static Token *adv(P *p) { Token *t = &p->t[p->i]; if (p->i < p->n - 1) p->i++; return t; }
static int is(P *p, int kind) { return tk(p)->kind == kind; }
static int iskw(P *p, int kw) { return tk(p)->kind == TK_KW && tk(p)->kw == kw; }
static int isid(P *p, const char *s) { return tk(p)->kind == TK_ID && name_eq(tk(p)->text, s); }
static int tok_isid(Token *t, const char *s) { return t->kind == TK_ID && name_eq(t->text, s); }

static const char *tok_desc(Token *t)
{
    static char b[96];
    switch (t->kind) {
    case TK_EOF: return "end of file";
    case TK_NL: return "end of line";
    case TK_ID: snprintf(b, sizeof b, "'%s'", t->text); return b;
    case TK_KW: snprintf(b, sizeof b, "'%s'", kw_name(t->kw)); return b;
    case TK_INT: case TK_FLT: return "number";
    case TK_STR: return "string";
    case TK_DATE: return "date literal";
    case TK_COLON: return "':'";
    case TK_LP: return "'('";
    case TK_RP: return "')'";
    case TK_COMMA: return "','";
    case TK_EQ: return "'='";
    default: return "operator";
    }
}

static void perr(P *p, Token *t, const char *fmt, const char *arg)
{
    char m[256];
    snprintf(m, sizeof m, fmt, arg ? arg : tok_desc(t));
    diag(p->prog, p->file, t->line, t->col, "%s", m);
    longjmp(p->jb, 1);
}

static void expect(P *p, int kind, const char *what)
{
    if (!is(p, kind)) {
        char m[128];
        snprintf(m, sizeof m, "expected %s, found %%s", what);
        perr(p, tk(p), m, NULL);
    }
    adv(p);
}

static void expect_kw(P *p, int kw)
{
    if (!iskw(p, kw)) {
        char m[128];
        snprintf(m, sizeof m, "expected '%s', found %%s", kw_name(kw));
        perr(p, tk(p), m, NULL);
    }
    adv(p);
}

static int accept(P *p, int kind) { if (is(p, kind)) { adv(p); return 1; } return 0; }
static int accept_kw(P *p, int kw) { if (iskw(p, kw)) { adv(p); return 1; } return 0; }

static Node *mk(P *p, int kind, Token *t) { return node_new(kind, p->file, t->line, t->col); }

static int at_eos(P *p)
{
    return is(p, TK_NL) || is(p, TK_COLON) || is(p, TK_EOF) || (p->single_line && iskw(p, KW_ELSE));
}

static void end_stmt(P *p)
{
    if (p->single_line && is(p, TK_NL)) return;
    if (is(p, TK_NL) || is(p, TK_COLON)) { adv(p); return; }
    if (is(p, TK_EOF)) return;
    if (p->single_line && iskw(p, KW_ELSE)) return;
    perr(p, tk(p), "expected end of statement, found %s", NULL);
}

/* identifier text, also accepting keywords where a name is allowed (after '.') */
static char *ident(P *p, char *suffix)
{
    Token *t = tk(p);
    if (t->kind == TK_ID) { adv(p); if (suffix) *suffix = t->suffix; return t->text; }
    perr(p, t, "expected identifier, found %s", NULL);
    return NULL;
}

static char *member_name(P *p)
{
    Token *t = tk(p);
    if (t->kind == TK_ID || t->kind == TK_KW) { adv(p); return t->text ? t->text : xstrdup(kw_name(t->kw)); }
    perr(p, t, "expected member name, found %s", NULL);
    return NULL;
}

/* ---------- expressions ---------- */

static Node *expr(P *p);
static Node *parse_postfix(P *p, int stmt_start);

static void parse_args(P *p, NodeList *args, int closer)
{
    if (is(p, closer)) return;
    for (;;) {
        Token *t = tk(p);
        if (is(p, TK_COMMA)) { nl_push(args, mk(p, E_MISSING, t)); adv(p); continue; }
        if (closer == TK_RP && is(p, TK_RP)) { nl_push(args, mk(p, E_MISSING, t)); break; }
        if (closer != TK_RP && at_eos(p)) { nl_push(args, mk(p, E_MISSING, t)); break; }
        if (t->kind == TK_ID && tkn(p, 1)->kind == TK_ASSIGN) {
            Node *na = mk(p, E_NAMEDARG, t);
            na->name = t->text;
            adv(p); adv(p);
            na->a = expr(p);
            nl_push(args, na);
        } else {
            if (is(p, TK_HASH)) adv(p);       /* Input$(n, #1), EOF(#1) leniency */
            if (iskw(p, KW_BYVAL)) adv(p);
            nl_push(args, expr(p));
        }
        if (!accept(p, TK_COMMA)) break;
        if ((closer == TK_RP && is(p, TK_RP)) || (closer != TK_RP && at_eos(p))) {
            nl_push(args, mk(p, E_MISSING, tk(p)));
            break;
        }
    }
}

static Node *primary(P *p)
{
    Token *t = tk(p);
    Node *n;
    switch (t->kind) {
    case TK_INT:
        adv(p);
        n = mk(p, E_INT, t);
        n->ival = t->ival;
        n->ty = type_prim(t->ity);
        return n;
    case TK_FLT:
        adv(p);
        n = mk(p, E_FLT, t);
        n->fval = t->fval;
        n->ty = type_prim(t->ity);
        return n;
    case TK_STR:
        adv(p);
        n = mk(p, E_STR, t);
        n->name = t->text;
        n->slen = t->len;
        return n;
    case TK_DATE:
        adv(p);
        n = mk(p, E_DATE, t);
        n->name = t->text;
        return n;
    case TK_LP:
        adv(p);
        n = mk(p, E_PAREN, t);
        n->a = expr(p);
        expect(p, TK_RP, "')'");
        return n;
    case TK_DOT:
        /* With member */
        return parse_postfix(p, 0);
    case TK_ID:
        return parse_postfix(p, 0);
    case TK_KW:
        switch (t->kw) {
        case KW_TRUE: case KW_FALSE:
            adv(p);
            n = mk(p, E_BOOL, t);
            n->ival = t->kw == KW_TRUE ? -1 : 0;
            return n;
        case KW_NOTHING: adv(p); return mk(p, E_NOTHING, t);
        case KW_EMPTY: adv(p); return mk(p, E_EMPTY, t);
        case KW_NULL: adv(p); return mk(p, E_NULL, t);
        case KW_ME: return parse_postfix(p, 0);
        case KW_NEW:
            adv(p);
            n = mk(p, E_NEW, t);
            n->name = ident(p, NULL);
            return n;
        case KW_TYPEOF:
            adv(p);
            n = mk(p, E_TYPEOF, t);
            n->a = parse_postfix(p, 0);
            expect_kw(p, KW_IS);
            n->name = ident(p, NULL);
            return n;
        case KW_ADDRESSOF:
            adv(p);
            n = mk(p, E_ADDROF, t);
            n->name = ident(p, NULL);
            return n;
        case KW_NOT:
            adv(p);
            n = mk(p, E_UN, t);
            n->op = OP_NOT;
            n->a = expr(p);
            return n;
        case KW_INPUT: case KW_ERROR:
            /* Input$(n, #f) / Error$(n) used as functions */
            return parse_postfix(p, 0);
        default: break;
        }
        /* fallthrough */
    default:
        perr(p, t, "expected expression, found %s", NULL);
    }
    return NULL;
}

static Node *parse_postfix(P *p, int stmt_start)
{
    Token *t = tk(p);
    Node *n;
    if (t->kind == TK_DOT) {
        adv(p);
        n = mk(p, E_DOT, t);
        n->a = NULL;
        n->name = member_name(p);
    } else if (t->kind == TK_KW && t->kw == KW_ME) {
        adv(p);
        n = mk(p, E_ME, t);
    } else if (t->kind == TK_KW && (t->kw == KW_INPUT || t->kw == KW_ERROR)) {
        adv(p);
        n = mk(p, E_NAME, t);
        n->name = xstrdup(t->kw == KW_INPUT ? "Input" : "Error");
    } else {
        char suf = 0;
        n = mk(p, E_NAME, t);
        n->name = ident(p, &suf);
        n->suffix = suf;
    }
    for (;;) {
        Token *u = tk(p);
        if (u->kind == TK_DOT && !u->space_before) {
            Node *m = mk(p, E_DOT, u);
            adv(p);
            m->line = tk(p)->line;
            m->col = tk(p)->col;
            m->a = n;
            m->name = member_name(p);
            n = m;
        } else if (u->kind == TK_DOT && u->space_before && n->kind != E_NAME) {
            break;
        } else if (u->kind == TK_LP && !(stmt_start && u->space_before && n->kind != E_APPLY)) {
            Node *m = mk(p, E_APPLY, u);
            adv(p);
            m->a = n;
            parse_args(p, &m->list, TK_RP);
            expect(p, TK_RP, "')'");
            n = m;
        } else if (u->kind == TK_BANG) {
            Node *m = mk(p, E_APPLY, u), *k;
            adv(p);
            m->a = n;
            k = mk(p, E_STR, tk(p));
            k->name = member_name(p);
            k->slen = (int)strlen(k->name);
            nl_push(&m->list, k);
            m->flags |= NF_ISDEFAULT;
            n = m;
        } else break;
    }
    return n;
}

static Node *binop(P *p, Token *t, int op, Node *a, Node *b)
{
    Node *n = mk(p, E_BIN, t);
    n->op = op;
    n->a = a;
    n->b = b;
    return n;
}

static Node *unary_operand(P *p);

static Node *parse_pow(P *p)
{
    Node *a = primary(p);
    while (is(p, TK_CARET)) {
        Token *t = adv(p);
        a = binop(p, t, OP_POW, a, unary_operand(p));
    }
    return a;
}

/* operand of ^ may itself be negated: 2 ^ -1 */
static Node *unary_operand(P *p)
{
    Token *t = tk(p);
    if (is(p, TK_MINUS) || is(p, TK_PLUS)) {
        Node *n = mk(p, E_UN, t);
        adv(p);
        n->op = t->kind == TK_MINUS ? OP_NEG : OP_PLUS;
        n->a = unary_operand(p);
        return n;
    }
    return primary(p);
}

static Node *parse_neg(P *p)
{
    Token *t = tk(p);
    if (is(p, TK_MINUS) || is(p, TK_PLUS)) {
        Node *n = mk(p, E_UN, t);
        adv(p);
        n->op = t->kind == TK_MINUS ? OP_NEG : OP_PLUS;
        n->a = parse_neg(p);
        return n;
    }
    return parse_pow(p);
}

static Node *parse_mul(P *p)
{
    Node *a = parse_neg(p);
    while (is(p, TK_STAR) || is(p, TK_SLASH)) {
        Token *t = adv(p);
        a = binop(p, t, t->kind == TK_STAR ? OP_MUL : OP_DIV, a, parse_neg(p));
    }
    return a;
}

static Node *parse_idiv(P *p)
{
    Node *a = parse_mul(p);
    while (is(p, TK_BSLASH)) {
        Token *t = adv(p);
        a = binop(p, t, OP_IDIV, a, parse_mul(p));
    }
    return a;
}

static Node *parse_mod(P *p)
{
    Node *a = parse_idiv(p);
    while (iskw(p, KW_MOD)) {
        Token *t = adv(p);
        a = binop(p, t, OP_MOD, a, parse_idiv(p));
    }
    return a;
}

static Node *parse_add(P *p)
{
    Node *a = parse_mod(p);
    while (is(p, TK_PLUS) || is(p, TK_MINUS)) {
        Token *t = adv(p);
        a = binop(p, t, t->kind == TK_PLUS ? OP_ADD : OP_SUB, a, parse_mod(p));
    }
    return a;
}

static Node *parse_cat(P *p)
{
    Node *a = parse_add(p);
    while (is(p, TK_AMP)) {
        Token *t = adv(p);
        a = binop(p, t, OP_CAT, a, parse_add(p));
    }
    return a;
}

static int cmp_op(P *p)
{
    switch (tk(p)->kind) {
    case TK_EQ: return OP_EQ;
    case TK_NE: return OP_NE;
    case TK_LT: return OP_LT;
    case TK_GT: return OP_GT;
    case TK_LE: return OP_LE;
    case TK_GE: return OP_GE;
    case TK_KW:
        if (tk(p)->kw == KW_LIKE) return OP_LIKE;
        if (tk(p)->kw == KW_IS) return OP_IS;
        return 0;
    default: return 0;
    }
}

static Node *parse_cmp(P *p)
{
    Node *a = parse_cat(p);
    int op;
    while ((op = cmp_op(p)) != 0) {
        Token *t = adv(p);
        a = binop(p, t, op, a, parse_cat(p));
    }
    return a;
}

static Node *parse_not(P *p)
{
    Token *t = tk(p);
    if (iskw(p, KW_NOT)) {
        Node *n = mk(p, E_UN, t);
        adv(p);
        n->op = OP_NOT;
        n->a = parse_not(p);
        return n;
    }
    return parse_cmp(p);
}

static Node *parse_and(P *p)
{
    Node *a = parse_not(p);
    while (iskw(p, KW_AND)) { Token *t = adv(p); a = binop(p, t, OP_AND, a, parse_not(p)); }
    return a;
}
static Node *parse_or(P *p)
{
    Node *a = parse_and(p);
    while (iskw(p, KW_OR)) { Token *t = adv(p); a = binop(p, t, OP_OR, a, parse_and(p)); }
    return a;
}
static Node *parse_xor(P *p)
{
    Node *a = parse_or(p);
    while (iskw(p, KW_XOR)) { Token *t = adv(p); a = binop(p, t, OP_XOR, a, parse_or(p)); }
    return a;
}
static Node *parse_eqv(P *p)
{
    Node *a = parse_xor(p);
    while (iskw(p, KW_EQV)) { Token *t = adv(p); a = binop(p, t, OP_EQV, a, parse_xor(p)); }
    return a;
}
static Node *expr(P *p)
{
    Node *a = parse_eqv(p);
    while (iskw(p, KW_IMP)) { Token *t = adv(p); a = binop(p, t, OP_IMP, a, parse_eqv(p)); }
    return a;
}

/* ---------- declarations ---------- */

/* As [New] Type [* n]  ->  type node (E_NAME, b = fixlen expr), sets NF_NEW on decl */
static Node *parse_as_type(P *p, Node *decl)
{
    Token *t;
    Node *ty;
    if (!accept_kw(p, KW_AS)) return NULL;
    if (accept_kw(p, KW_NEW)) decl->flags |= NF_NEW;
    t = tk(p);
    ty = mk(p, E_NAME, t);
    if (t->kind == TK_ID) { adv(p); ty->name = t->text; }
    else perr(p, t, "expected type name, found %s", NULL);
    /* qualified names (VBA.Collection): keep the last part */
    while (is(p, TK_DOT)) { adv(p); ty->name = member_name(p); }
    if (is(p, TK_STAR)) {
        adv(p);
        ty->b = primary(p);
    }
    return ty;
}

/* array bounds: ( [lb To] ub, ... ) ; empty () allowed */
static void parse_bounds(P *p, Node *d)
{
    expect(p, TK_LP, "'('");
    d->flags |= NF_ARRAY;
    if (!is(p, TK_RP)) {
        for (;;) {
            Node *b = mk(p, S_NOP, tk(p)), *e = expr(p);
            if (accept_kw(p, KW_TO)) { b->a = e; b->b = expr(p); }
            else { b->a = NULL; b->b = e; }
            nl_push(&d->list, b);
            if (!accept(p, TK_COMMA)) break;
        }
    }
    expect(p, TK_RP, "')'");
}

static Node *parse_declarator(P *p, int flags)
{
    Token *t = tk(p);
    Node *d = mk(p, D_VARDECL, t);
    char suf = 0;
    d->flags = flags;
    if (accept_kw(p, KW_WITHEVENTS)) d->flags |= NF_WITHEVENTS;
    d->name = ident(p, &suf);
    d->suffix = suf;
    if (is(p, TK_LP)) parse_bounds(p, d);
    d->a = parse_as_type(p, d);
    return d;
}

static void parse_dim_list(P *p, Node *n, int flags)
{
    for (;;) {
        nl_push(&n->list, parse_declarator(p, flags));
        if (!accept(p, TK_COMMA)) break;
    }
}

static Node *parse_const(P *p, Token *t, int flags)
{
    Node *n = mk(p, D_CONST, t);
    n->flags = flags;
    for (;;) {
        Token *u = tk(p);
        Node *d = mk(p, D_VARDECL, u);
        char suf = 0;
        d->name = ident(p, &suf);
        d->suffix = suf;
        d->a = parse_as_type(p, d);
        expect(p, TK_EQ, "'='");
        d->c = expr(p);
        d->flags = flags;
        nl_push(&n->list, d);
        if (!accept(p, TK_COMMA)) break;
    }
    return n;
}

static void parse_params(P *p, NodeList *out)
{
    if (!accept(p, TK_LP)) return;
    if (accept(p, TK_RP)) return;
    for (;;) {
        Token *t = tk(p);
        Node *d = mk(p, D_VARDECL, t);
        int byref = -1, opt = 0, pa = 0;
        char suf = 0;
        for (;;) {
            if (accept_kw(p, KW_OPTIONAL)) opt = 1;
            else if (accept_kw(p, KW_BYVAL)) byref = 0;
            else if (accept_kw(p, KW_BYREF)) byref = 1;
            else if (accept_kw(p, KW_PARAMARRAY)) pa = 1;
            else break;
        }
        d->name = ident(p, &suf);
        d->suffix = suf;
        if (is(p, TK_LP)) { adv(p); expect(p, TK_RP, "')'"); d->flags |= NF_ARRAY; }
        d->a = parse_as_type(p, d);
        if (accept(p, TK_EQ)) d->c = expr(p);
        d->op = byref;         /* -1 default (ByRef), 0 ByVal, 1 ByRef */
        d->ival = opt | (pa << 1);
        nl_push(out, d);
        if (!accept(p, TK_COMMA)) break;
    }
    expect(p, TK_RP, "')'");
}

static void parse_block(P *p, NodeList *body);

static int end_is(P *p, int kw)
{
    return iskw(p, KW_END) && tkn(p, 1)->kind == TK_KW && tkn(p, 1)->kw == kw;
}

static void expect_end(P *p, int kw)
{
    if (end_is(p, kw)) { adv(p); adv(p); return; }
    {
        char m[128];
        snprintf(m, sizeof m, "expected 'End %s', found %%s", kw_name(kw));
        perr(p, tk(p), m, NULL);
    }
}

static Node *parse_proc(P *p, Token *t, int flags)
{
    Node *n = mk(p, D_PROC, t);
    int kw = tk(p)->kw, endkw;
    adv(p);
    n->flags = flags;
    if (kw == KW_SUB) { n->op = PK_SUB; endkw = KW_SUB; }
    else if (kw == KW_FUNCTION) { n->op = PK_FUNCTION; endkw = KW_FUNCTION; }
    else {
        endkw = KW_PROPERTY;
        if (accept_kw(p, KW_GET)) n->op = PK_PGET;
        else if (accept_kw(p, KW_LET)) n->op = PK_PLET;
        else if (accept_kw(p, KW_SET)) n->op = PK_PSET;
        else perr(p, tk(p), "expected Get, Let or Set after Property, found %s", NULL);
    }
    {
        char suf = 0;
        Token *nt = tk(p);
        if (nt->kind == TK_KW && (nt->kw == KW_INPUT || nt->kw == KW_ERROR || nt->kw == KW_PRINT)) { adv(p); n->name = nt->text; }
        else n->name = ident(p, &suf);
        n->suffix = suf;
    }
    parse_params(p, &n->list);
    if (n->op != PK_SUB && n->op != PK_PLET && n->op != PK_PSET) n->a = parse_as_type(p, n);
    end_stmt(p);
    p->in_proc = 1;
    parse_block(p, &n->list2);
    p->in_proc = 0;
    if (!end_is(p, endkw)) {
        char m[128];
        snprintf(m, sizeof m, "expected 'End %s', found %%s", kw_name(endkw));
        perr(p, tk(p), m, NULL);
    }
    adv(p); adv(p);
    n->ival = tk(p)->line;   /* end line */
    return n;
}

/* ---------- statements ---------- */

static Node *parse_statement(P *p);

static int at_block_end(P *p)
{
    Token *t = tk(p);
    if (t->kind == TK_EOF) return 1;
    if (t->kind != TK_KW) return 0;
    switch (t->kw) {
    case KW_ELSE: case KW_ELSEIF: case KW_CASE: case KW_NEXT: case KW_LOOP: case KW_WEND:
        return 1;
    case KW_END: {
        Token *u = tkn(p, 1);
        if (u->kind == TK_KW) {
            switch (u->kw) {
            case KW_IF: case KW_SELECT: case KW_WITH: case KW_SUB: case KW_FUNCTION:
            case KW_PROPERTY: case KW_TYPE: case KW_ENUM:
                return 1;
            default: return 0;
            }
        }
        return 0;
    }
    default: return 0;
    }
}

static void skip_line(P *p)
{
    while (!is(p, TK_NL) && !is(p, TK_EOF)) adv(p);
    if (is(p, TK_NL)) adv(p);
}

static void parse_block(P *p, NodeList *body)
{
    for (;;) {
        while (is(p, TK_NL) || is(p, TK_COLON)) adv(p);
        if (p->pending_next) return;
        if (at_block_end(p)) return;
        if (!p->in_proc && p->mod && (iskw(p, KW_SUB) || iskw(p, KW_FUNCTION))) return;
        {
            int save = p->i;
            jmp_buf old;
            memcpy(old, p->jb, sizeof old);
            if (setjmp(p->jb) == 0) {
                Node *s = parse_statement(p);
                if (s) nl_push(body, s);
            } else {
                if (p->i == save) adv(p);
                skip_line(p);
            }
            memcpy(p->jb, old, sizeof old);
        }
    }
}

static Node *parse_if(P *p, Token *t)
{
    Node *n = mk(p, S_IF, t), *br;
    br = mk(p, S_ELSEIF, t);
    br->a = expr(p);
    expect_kw(p, KW_THEN);
    nl_push(&n->list, br);
    if (!is(p, TK_NL) && !is(p, TK_EOF)) {
        /* single-line If */
        int old = p->single_line;
        n->flags |= NF_SINGLELINE;
        p->single_line = 1;
        if (is(p, TK_INT)) {
            Node *g = mk(p, S_GOTO, tk(p));
            g->name = xsprintf("%lld", (long long)adv(p)->ival);
            nl_push(&br->list, g);
        } else {
            while (!is(p, TK_NL) && !is(p, TK_EOF) && !iskw(p, KW_ELSE)) {
                Node *s = parse_statement(p);
                if (s) nl_push(&br->list, s);
            }
        }
        if (accept_kw(p, KW_ELSE)) {
            if (is(p, TK_INT)) {
                Node *g = mk(p, S_GOTO, tk(p));
                g->name = xsprintf("%lld", (long long)adv(p)->ival);
                nl_push(&n->list2, g);
            }
            while (!is(p, TK_NL) && !is(p, TK_EOF)) {
                Node *s = parse_statement(p);
                if (s) nl_push(&n->list2, s);
            }
        }
        p->single_line = old;
        return n;
    }
    end_stmt(p);
    parse_block(p, &br->list);
    for (;;) {
        if (iskw(p, KW_ELSEIF)) {
            Token *u = adv(p);
            br = mk(p, S_ELSEIF, u);
            br->a = expr(p);
            expect_kw(p, KW_THEN);
            end_stmt(p);
            parse_block(p, &br->list);
            nl_push(&n->list, br);
        } else if (iskw(p, KW_ELSE) && tkn(p, 1)->kind == TK_KW && tkn(p, 1)->kw == KW_IF) {
            /* "Else If" on one line: treat as ElseIf */
            Token *u = adv(p);
            adv(p);
            br = mk(p, S_ELSEIF, u);
            br->a = expr(p);
            expect_kw(p, KW_THEN);
            end_stmt(p);
            parse_block(p, &br->list);
            nl_push(&n->list, br);
        } else if (iskw(p, KW_ELSE)) {
            adv(p);
            accept(p, TK_COLON);
            if (is(p, TK_NL)) adv(p);
            parse_block(p, &n->list2);
            break;
        } else break;
    }
    expect_end(p, KW_IF);
    return n;
}

static Node *parse_select(P *p, Token *t)
{
    Node *n = mk(p, S_SELECT, t);
    accept_kw(p, KW_CASE);
    n->a = expr(p);
    end_stmt(p);
    while (is(p, TK_NL) || is(p, TK_COLON)) adv(p);
    while (iskw(p, KW_CASE)) {
        Token *u = adv(p);
        Node *c = mk(p, S_CASE, u);
        if (accept_kw(p, KW_ELSE)) c->flags |= NF_CASEELSE;
        else {
            for (;;) {
                Token *v = tk(p);
                if (accept_kw(p, KW_IS)) {
                    Node *ci = mk(p, E_CASEIS, v);
                    ci->op = cmp_op(p);
                    if (!ci->op || ci->op == OP_LIKE || ci->op == OP_IS) perr(p, tk(p), "expected comparison operator after Is, found %s", NULL);
                    adv(p);
                    ci->a = parse_cat(p);
                    nl_push(&c->list, ci);
                } else if (cmp_op(p) && cmp_op(p) != OP_LIKE && cmp_op(p) != OP_IS) {
                    /* "Case > 5" (Is omitted) */
                    Node *ci = mk(p, E_CASEIS, v);
                    ci->op = cmp_op(p);
                    adv(p);
                    ci->a = parse_cat(p);
                    nl_push(&c->list, ci);
                } else {
                    Node *e = expr(p);
                    if (accept_kw(p, KW_TO)) {
                        Node *r = mk(p, E_CASERANGE, v);
                        r->a = e;
                        r->b = expr(p);
                        e = r;
                    }
                    nl_push(&c->list, e);
                }
                if (!accept(p, TK_COMMA)) break;
            }
        }
        if (is(p, TK_COLON)) adv(p); else end_stmt(p);
        parse_block(p, &c->list2);
        nl_push(&n->list, c);
        if (c->flags & NF_CASEELSE) break;
    }
    expect_end(p, KW_SELECT);
    return n;
}

static Node *parse_for(P *p, Token *t)
{
    Node *n;
    if (accept_kw(p, KW_EACH)) {
        n = mk(p, S_FOREACH, t);
        n->a = parse_postfix(p, 0);
        expect_kw(p, KW_IN);
        n->b = expr(p);
    } else {
        n = mk(p, S_FOR, t);
        n->a = parse_postfix(p, 0);
        expect(p, TK_EQ, "'='");
        n->b = expr(p);
        expect_kw(p, KW_TO);
        n->c = expr(p);
        if (accept_kw(p, KW_STEP)) n->d = expr(p);
    }
    end_stmt(p);
    parse_block(p, &n->list);
    if (p->pending_next) {
        p->pending_next--;
        return n;
    }
    if (!iskw(p, KW_NEXT)) perr(p, tk(p), "expected 'Next', found %s", NULL);
    adv(p);
    if (!at_eos(p)) {
        /* Next i [, j ...] */
        int count = 0;
        for (;;) {
            Node *v = parse_postfix(p, 0);
            if (count == 0 && n->a->kind == E_NAME && v->kind == E_NAME && !name_eq(v->name, n->a->name))
                diag(p->prog, p->file, v->line, v->col, "'Next %s' does not match 'For %s'", v->name, n->a->name);
            count++;
            if (!accept(p, TK_COMMA)) break;
        }
        p->pending_next = count - 1;
    }
    end_stmt(p);
    return n;
}

static Node *parse_do(P *p, Token *t)
{
    Node *n = mk(p, S_DO, t);
    if (accept_kw(p, KW_WHILE)) { n->op = DO_PRE_WHILE; n->a = expr(p); }
    else if (accept_kw(p, KW_UNTIL)) { n->op = DO_PRE_UNTIL; n->a = expr(p); }
    end_stmt(p);
    parse_block(p, &n->list);
    expect_kw(p, KW_LOOP);
    if (n->op == DO_NONE) {
        if (accept_kw(p, KW_WHILE)) { n->op = DO_POST_WHILE; n->a = expr(p); }
        else if (accept_kw(p, KW_UNTIL)) { n->op = DO_POST_UNTIL; n->a = expr(p); }
    }
    end_stmt(p);
    return n;
}

static Node *file_number(P *p)
{
    accept(p, TK_HASH);
    return expr(p);
}

static Node *parse_print(P *p, Token *t, int debug)
{
    Node *n = mk(p, S_PRINT, t);
    if (debug) n->flags |= NF_DEBUG;
    if (is(p, TK_HASH)) {
        adv(p);
        n->a = expr(p);
        if (!at_eos(p)) expect(p, TK_COMMA, "','");
    }
    while (!at_eos(p)) {
        Token *u = tk(p);
        Node *it = mk(p, S_PRINTITEM, u);
        if (is(p, TK_SEMI)) { adv(p); it->op = PSEP_SEMI; nl_push(&n->list, it); continue; }
        if (is(p, TK_COMMA)) { adv(p); it->op = PSEP_COMMA; nl_push(&n->list, it); continue; }
        if ((tok_isid(u, "Spc") || tok_isid(u, "Tab")) && tkn(p, 1)->kind == TK_LP) {
            it->ival = tok_isid(u, "Spc") ? PI_SPC : PI_TAB;
            adv(p); adv(p);
            if (!is(p, TK_RP)) it->a = expr(p);
            expect(p, TK_RP, "')'");
        } else if (tok_isid(u, "Tab") && tkn(p, 1)->kind != TK_LP) {
            adv(p);
            it->ival = PI_TAB;
        } else {
            it->ival = PI_EXPR;
            it->a = expr(p);
        }
        if (is(p, TK_SEMI)) { adv(p); it->op = PSEP_SEMI; }
        else if (is(p, TK_COMMA)) { adv(p); it->op = PSEP_COMMA; }
        nl_push(&n->list, it);
    }
    return n;
}

static Node *parse_open(P *p, Token *t)
{
    Node *n = mk(p, S_OPEN, t);
    n->a = expr(p);
    n->op = 1 /* Random default */;
    n->op = 4;
    if (accept_kw(p, KW_FOR)) {
        Token *m = tk(p);
        if (iskw(p, KW_INPUT)) n->op = 1;
        else if (tok_isid(m, "Output")) n->op = 2;
        else if (tok_isid(m, "Append")) n->op = 8;
        else if (tok_isid(m, "Binary")) n->op = 32;
        else if (tok_isid(m, "Random")) n->op = 4;
        else perr(p, m, "expected Input, Output, Append, Binary or Random, found %s", NULL);
        adv(p);
    }
    if (isid(p, "Access")) {
        adv(p);
        while (iskw(p, KW_WRITE) || isid(p, "Read")) adv(p);
    }
    while (isid(p, "Shared") || isid(p, "Lock") || isid(p, "Read") || iskw(p, KW_WRITE)) adv(p);
    expect_kw(p, KW_AS);
    n->b = file_number(p);
    if (isid(p, "Len")) {
        adv(p);
        expect(p, TK_EQ, "'='");
        n->c = expr(p);
    }
    return n;
}

static Node *parse_onerror_or_goto(P *p, Token *t)
{
    Node *n;
    if (accept_kw(p, KW_ERROR)) {
        n = mk(p, S_ONERROR, t);
        if (accept_kw(p, KW_RESUME)) {
            if (!isid(p, "Next") && !iskw(p, KW_NEXT)) perr(p, tk(p), "expected 'Next', found %s", NULL);
            adv(p);
            n->op = ONERR_RESUMENEXT;
        } else {
            expect_kw(p, KW_GOTO);
            if (is(p, TK_INT) && tk(p)->ival == 0) { adv(p); n->op = ONERR_GOTO0; }
            else if (is(p, TK_MINUS) && tkn(p, 1)->kind == TK_INT && tkn(p, 1)->ival == 1) { adv(p); adv(p); n->op = ONERR_GOTOM1; }
            else if (is(p, TK_INT)) { n->op = ONERR_GOTO; n->name = xsprintf("%lld", (long long)adv(p)->ival); }
            else { n->op = ONERR_GOTO; n->name = ident(p, NULL); }
        }
        return n;
    }
    n = mk(p, S_ONGOTO, t);
    n->a = expr(p);
    if (accept_kw(p, KW_GOTO)) n->op = 0;
    else if (accept_kw(p, KW_GOSUB)) n->op = 1;
    else perr(p, tk(p), "expected GoTo or GoSub, found %s", NULL);
    for (;;) {
        Node *l = mk(p, S_GOTO, tk(p));
        if (is(p, TK_INT)) l->name = xsprintf("%lld", (long long)adv(p)->ival);
        else l->name = ident(p, NULL);
        nl_push(&n->list, l);
        if (!accept(p, TK_COMMA)) break;
    }
    return n;
}

static Node *label_target(P *p, Node *n)
{
    if (is(p, TK_INT)) n->name = xsprintf("%lld", (long long)adv(p)->ival);
    else n->name = ident(p, NULL);
    return n;
}

/* assignment or call statement starting at the current token */
static Node *parse_simple(P *p, Token *t)
{
    int save = p->i;
    Node *target = parse_postfix(p, 1);
    Node *n;
    if (is(p, TK_EQ)) {
        adv(p);
        n = mk(p, S_LET, t);
        n->a = target;
        n->b = expr(p);
        return n;
    }
    /* "a (1) = 5": the statement-start rule kept the "(1)" out of the target */
    if (is(p, TK_LP)) {
        int save2 = p->i;
        Node *again;
        p->i = save;
        again = parse_postfix(p, 0);
        if (is(p, TK_EQ)) {
            adv(p);
            n = mk(p, S_LET, t);
            n->a = again;
            n->b = expr(p);
            return n;
        }
        p->i = save2;
    }
    n = mk(p, S_EXPR, t);
    if (!at_eos(p)) {
        /* call with arguments without parentheses */
        Node *call = mk(p, E_APPLY, t);
        call->a = target;
        call->flags |= NF_VOIDCALL;
        parse_args(p, &call->list, -1);
        n->a = call;
    } else {
        n->a = target;
        target->flags |= NF_VOIDCALL;
    }
    return n;
}

static Node *parse_statement(P *p)
{
    Token *t = tk(p);
    Node *n = NULL;

    /* labels */
    if (t->line_start && t->kind == TK_INT && !p->single_line) {
        n = mk(p, S_LABEL, t);
        n->name = xsprintf("%lld", (long long)t->ival);
        adv(p);
        return n;
    }
    if (t->kind == TK_ID && t->line_start && tkn(p, 1)->kind == TK_COLON && !p->single_line) {
        n = mk(p, S_LABEL, t);
        n->name = t->text;
        adv(p); adv(p);
        return n;
    }

    if (t->kind == TK_KW) {
        switch (t->kw) {
        case KW_DIM: case KW_STATIC: {
            adv(p);
            if (t->kw == KW_STATIC && (iskw(p, KW_SUB) || iskw(p, KW_FUNCTION) || iskw(p, KW_PROPERTY))) {
                Node *pr = parse_proc(p, t, NF_STATIC);
                return pr;
            }
            n = mk(p, S_DIM, t);
            if (t->kw == KW_STATIC) n->flags |= NF_STATIC;
            parse_dim_list(p, n, t->kw == KW_STATIC ? NF_STATIC : 0);
            break;
        }
        case KW_CONST:
            adv(p);
            n = parse_const(p, t, 0);
            n->kind = S_CONST;
            break;
        case KW_REDIM:
            adv(p);
            n = mk(p, S_REDIM, t);
            if (accept_kw(p, KW_PRESERVE)) n->flags |= NF_PRESERVE;
            for (;;) {
                Token *u = tk(p);
                Node *d = mk(p, D_VARDECL, u);
                Node *target = mk(p, E_NAME, u);
                char suf = 0;
                target->name = ident(p, &suf);
                target->suffix = suf;
                while (is(p, TK_DOT)) {
                    Node *m = mk(p, E_DOT, tk(p));
                    adv(p);
                    m->a = target;
                    m->name = member_name(p);
                    target = m;
                }
                d->b = target;
                parse_bounds(p, d);
                d->a = parse_as_type(p, d);
                nl_push(&n->list, d);
                if (!accept(p, TK_COMMA)) break;
            }
            break;
        case KW_ERASE:
            adv(p);
            n = mk(p, S_ERASE, t);
            for (;;) {
                nl_push(&n->list, parse_postfix(p, 0));
                if (!accept(p, TK_COMMA)) break;
            }
            break;
        case KW_IF:
            adv(p);
            return parse_if(p, t);
        case KW_SELECT:
            adv(p);
            return parse_select(p, t);
        case KW_FOR:
            adv(p);
            return parse_for(p, t);
        case KW_DO:
            adv(p);
            return parse_do(p, t);
        case KW_WHILE:
            adv(p);
            n = mk(p, S_DO, t);
            n->op = DO_PRE_WHILE;
            n->a = expr(p);
            end_stmt(p);
            parse_block(p, &n->list);
            expect_kw(p, KW_WEND);
            break;
        case KW_WITH:
            adv(p);
            n = mk(p, S_WITH, t);
            n->a = expr(p);
            end_stmt(p);
            parse_block(p, &n->list);
            expect_end(p, KW_WITH);
            break;
        case KW_EXIT:
            adv(p);
            n = mk(p, S_EXIT, t);
            if (accept_kw(p, KW_SUB)) n->op = EXIT_SUB;
            else if (accept_kw(p, KW_FUNCTION)) n->op = EXIT_FUNCTION;
            else if (accept_kw(p, KW_PROPERTY)) n->op = EXIT_PROPERTY;
            else if (accept_kw(p, KW_FOR)) n->op = EXIT_FOR;
            else if (accept_kw(p, KW_DO)) n->op = EXIT_DO;
            else perr(p, tk(p), "expected Sub, Function, Property, For or Do after Exit, found %s", NULL);
            break;
        case KW_GOTO:
            adv(p);
            n = label_target(p, mk(p, S_GOTO, t));
            break;
        case KW_GOSUB:
            adv(p);
            n = label_target(p, mk(p, S_GOSUB, t));
            break;
        case KW_RETURN:
            adv(p);
            n = mk(p, S_RETURN, t);
            break;
        case KW_ON:
            adv(p);
            n = parse_onerror_or_goto(p, t);
            break;
        case KW_RESUME:
            adv(p);
            n = mk(p, S_RESUME, t);
            n->op = RES_PLAIN;
            if (accept_kw(p, KW_NEXT)) n->op = RES_NEXT;
            else if (is(p, TK_INT) && tk(p)->ival == 0) adv(p);
            else if (!at_eos(p)) { n->op = RES_LABEL; label_target(p, n); }
            break;
        case KW_PRINT:
            adv(p);
            n = parse_print(p, t, 0);
            break;
        case KW_WRITE:
            adv(p);
            n = mk(p, S_WRITE, t);
            expect(p, TK_HASH, "'#'");
            n->a = expr(p);
            if (accept(p, TK_COMMA)) {
                while (!at_eos(p)) {
                    nl_push(&n->list, expr(p));
                    if (!accept(p, TK_COMMA) && !accept(p, TK_SEMI)) break;
                }
            }
            break;
        case KW_INPUT:
            adv(p);
            n = mk(p, S_INPUT, t);
            if (is(p, TK_HASH)) {
                adv(p);
                n->a = expr(p);
                expect(p, TK_COMMA, "','");
            } else if (is(p, TK_STR)) {
                Token *s = adv(p);
                Node *pr = mk(p, E_STR, s);
                pr->name = s->text;
                pr->slen = s->len;
                n->b = pr;
                if (accept(p, TK_SEMI)) n->flags |= NF_QUESTION;
                else expect(p, TK_COMMA, "';' or ','");
            } else n->flags |= NF_QUESTION;
            for (;;) {
                nl_push(&n->list, parse_postfix(p, 0));
                if (!accept(p, TK_COMMA)) break;
            }
            break;
        case KW_OPEN:
            adv(p);
            n = parse_open(p, t);
            break;
        case KW_CLOSE:
            adv(p);
            n = mk(p, S_CLOSE, t);
            while (!at_eos(p)) {
                nl_push(&n->list, file_number(p));
                if (!accept(p, TK_COMMA)) break;
            }
            break;
        case KW_GET:
            adv(p);
            n = mk(p, S_GET, t);
            n->a = file_number(p);
            expect(p, TK_COMMA, "','");
            if (!is(p, TK_COMMA)) n->b = expr(p);
            expect(p, TK_COMMA, "','");
            n->c = parse_postfix(p, 0);
            break;
        case KW_END:
            adv(p);
            n = mk(p, S_END, t);
            break;
        case KW_STOP:
            adv(p);
            n = mk(p, S_STOP, t);
            break;
        case KW_RAISEEVENT:
            adv(p);
            n = mk(p, S_RAISEEVENT, t);
            n->name = ident(p, NULL);
            if (accept(p, TK_LP)) {
                parse_args(p, &n->list, TK_RP);
                expect(p, TK_RP, "')'");
            }
            break;
        case KW_ERROR:
            adv(p);
            n = mk(p, S_ERROR, t);
            n->a = expr(p);
            break;
        case KW_LSET: case KW_RSET:
            adv(p);
            n = mk(p, t->kw == KW_LSET ? S_LSET : S_RSET, t);
            n->a = parse_postfix(p, 0);
            expect(p, TK_EQ, "'='");
            n->b = expr(p);
            break;
        case KW_SET:
            adv(p);
            n = mk(p, S_SET, t);
            n->a = parse_postfix(p, 0);
            expect(p, TK_EQ, "'='");
            n->b = expr(p);
            break;
        case KW_LET:
            adv(p);
            n = mk(p, S_LET, t);
            n->a = parse_postfix(p, 0);
            expect(p, TK_EQ, "'='");
            n->b = expr(p);
            break;
        case KW_CALL: {
            Node *target;
            adv(p);
            n = mk(p, S_EXPR, t);
            target = parse_postfix(p, 0);
            if (target->kind != E_APPLY) {
                Node *c = mk(p, E_APPLY, t);
                c->a = target;
                target = c;
            }
            target->flags |= NF_VOIDCALL;
            n->a = target;
            break;
        }
        case KW_ME:
            n = parse_simple(p, t);
            break;
        case KW_PUBLIC: case KW_PRIVATE: case KW_GLOBAL: case KW_FRIEND: case KW_SUB:
        case KW_FUNCTION: case KW_PROPERTY: case KW_TYPE: case KW_ENUM: case KW_DECLARE:
        case KW_EVENT: case KW_IMPLEMENTS: case KW_OPTION:
            perr(p, t, "%s is not allowed inside a procedure", NULL);
            break;
        default:
            perr(p, t, "unexpected %s", NULL);
        }
        end_stmt(p);
        return n;
    }

    if (t->kind == TK_ID) {
        /* contextual statements */
        if (name_eq(t->text, "Line") && tkn(p, 1)->kind == TK_KW && tkn(p, 1)->kw == KW_INPUT) {
            adv(p); adv(p);
            n = mk(p, S_LINEINPUT, t);
            if (is(p, TK_HASH)) {
                adv(p);
                n->a = expr(p);
                expect(p, TK_COMMA, "','");
            } else if (is(p, TK_STR)) {
                Token *s = adv(p);
                Node *pr = mk(p, E_STR, s);
                pr->name = s->text;
                pr->slen = s->len;
                n->b = pr;
                if (!accept(p, TK_SEMI)) expect(p, TK_COMMA, "';' or ','");
            }
            n->c = parse_postfix(p, 0);
            end_stmt(p);
            return n;
        }
        if (name_eq(t->text, "Debug") && tkn(p, 1)->kind == TK_DOT && tok_isid(tkn(p, 2), "Print")) {
            adv(p); adv(p); adv(p);
            n = parse_print(p, t, 1);
            end_stmt(p);
            return n;
        }
        if (name_eq(t->text, "Put") && tkn(p, 1)->kind == TK_HASH) {
            adv(p);
            n = mk(p, S_PUT, t);
            n->a = file_number(p);
            expect(p, TK_COMMA, "','");
            if (!is(p, TK_COMMA)) n->b = expr(p);
            expect(p, TK_COMMA, "','");
            n->c = expr(p);
            end_stmt(p);
            return n;
        }
        if (name_eq(t->text, "Seek") && tkn(p, 1)->kind == TK_HASH) {
            adv(p);
            n = mk(p, S_SEEK, t);
            n->a = file_number(p);
            expect(p, TK_COMMA, "','");
            n->b = expr(p);
            end_stmt(p);
            return n;
        }
        if (name_eq(t->text, "Name") && !t->suffix && tkn(p, 1)->kind != TK_EQ && tkn(p, 1)->kind != TK_DOT &&
            tkn(p, 1)->kind != TK_LP && tkn(p, 1)->kind != TK_NL && tkn(p, 1)->kind != TK_COLON) {
            adv(p);
            n = mk(p, S_NAME, t);
            n->a = expr(p);
            expect_kw(p, KW_AS);
            n->b = expr(p);
            end_stmt(p);
            return n;
        }
        n = parse_simple(p, t);
        end_stmt(p);
        return n;
    }
    if (t->kind == TK_DOT) {
        n = parse_simple(p, t);
        end_stmt(p);
        return n;
    }
    perr(p, t, "unexpected %s", NULL);
    return NULL;
}

/* ---------- module level ---------- */

static Node *parse_type(P *p, Token *t, int flags)
{
    Node *n = mk(p, D_TYPE, t);
    n->flags = flags;
    n->name = ident(p, NULL);
    end_stmt(p);
    for (;;) {
        while (is(p, TK_NL) || is(p, TK_COLON)) adv(p);
        if (end_is(p, KW_TYPE) || is(p, TK_EOF)) break;
        {
            Node *d = parse_declarator(p, 0);
            if (!d->a) diag(p->prog, p->file, d->line, d->col, "field '%s' needs a type (As ...)", d->name);
            nl_push(&n->list, d);
            end_stmt(p);
        }
    }
    expect_end(p, KW_TYPE);
    return n;
}

static Node *parse_enum(P *p, Token *t, int flags)
{
    Node *n = mk(p, D_ENUM, t);
    n->flags = flags;
    n->name = ident(p, NULL);
    end_stmt(p);
    for (;;) {
        Token *u;
        Node *m;
        while (is(p, TK_NL) || is(p, TK_COLON)) adv(p);
        if (end_is(p, KW_ENUM) || is(p, TK_EOF)) break;
        u = tk(p);
        m = mk(p, D_VARDECL, u);
        m->name = ident(p, NULL);
        if (accept(p, TK_EQ)) m->c = expr(p);
        nl_push(&n->list, m);
        end_stmt(p);
    }
    expect_end(p, KW_ENUM);
    return n;
}

static Node *parse_declare(P *p, Token *t, int flags)
{
    Node *n = mk(p, D_DECLARE, t);
    n->flags = flags;
    if (accept_kw(p, KW_SUB)) n->op = PK_SUB;
    else if (accept_kw(p, KW_FUNCTION)) n->op = PK_FUNCTION;
    else perr(p, tk(p), "expected Sub or Function after Declare, found %s", NULL);
    {
        char suf = 0;
        n->name = ident(p, &suf);
        n->suffix = suf;
    }
    if (!isid(p, "Lib")) perr(p, tk(p), "expected 'Lib', found %s", NULL);
    adv(p);
    if (!is(p, TK_STR)) perr(p, tk(p), "expected library name string, found %s", NULL);
    n->b = primary(p);
    for (;;) {
        if (isid(p, "Alias")) { adv(p); if (!is(p, TK_STR)) perr(p, tk(p), "expected alias string, found %s", NULL); n->c = primary(p); }
        else if (isid(p, "Interface")) { adv(p); if (!is(p, TK_STR)) perr(p, tk(p), "expected interface name string, found %s", NULL); n->d = primary(p); }
        else if (isid(p, "Version")) { adv(p); if (!is(p, TK_INT)) perr(p, tk(p), "expected version number, found %s", NULL); n->ival = adv(p)->ival; }
        else break;
    }
    parse_params(p, &n->list);
    if (n->op == PK_FUNCTION) n->a = parse_as_type(p, n);
    return n;
}

static void parse_toplevel(P *p)
{
    Token *t = tk(p);
    Module *m = p->mod;
    int flags = 0;
    Node *n = NULL;

    /* VB class/form file headers */
    if (t->kind == TK_ID && (name_eq(t->text, "Attribute") || name_eq(t->text, "VERSION")) && t->line_start) {
        skip_line(p);
        return;
    }
    if (t->kind == TK_ID && name_eq(t->text, "BEGIN") && t->line_start && tkn(p, 1)->kind == TK_NL) {
        while (!is(p, TK_EOF) && !(iskw(p, KW_END) && tkn(p, 1)->kind == TK_NL)) skip_line(p);
        skip_line(p);
        return;
    }
    if (iskw(p, KW_OPTION)) {
        adv(p);
        if (isid(p, "Explicit")) { adv(p); m->opt_explicit = 1; }
        else if (isid(p, "Base")) {
            adv(p);
            if (!is(p, TK_INT) || (tk(p)->ival != 0 && tk(p)->ival != 1)) perr(p, tk(p), "Option Base must be 0 or 1", "");
            m->opt_base = (int)adv(p)->ival;
        } else if (isid(p, "Compare")) {
            adv(p);
            if (isid(p, "Text")) m->opt_text = 1;
            else if (isid(p, "Binary")) m->opt_text = 0;
            else perr(p, tk(p), "expected Text or Binary, found %s", NULL);
            adv(p);
        } else if (isid(p, "Private")) { adv(p); if (isid(p, "Module")) adv(p); }
        else perr(p, tk(p), "expected Explicit, Base or Compare, found %s", NULL);
        end_stmt(p);
        return;
    }
    for (;;) {
        if (accept_kw(p, KW_PUBLIC) || accept_kw(p, KW_GLOBAL)) flags |= NF_PUBLIC;
        else if (accept_kw(p, KW_PRIVATE)) flags |= NF_PRIVATE;
        else if (accept_kw(p, KW_FRIEND)) flags |= NF_PUBLIC | NF_FRIEND;
        else if (iskw(p, KW_STATIC) && tkn(p, 1)->kind == TK_KW &&
                 (tkn(p, 1)->kw == KW_SUB || tkn(p, 1)->kw == KW_FUNCTION || tkn(p, 1)->kw == KW_PROPERTY)) {
            adv(p);
            flags |= NF_STATIC;
        } else break;
    }
    if (iskw(p, KW_SUB) || iskw(p, KW_FUNCTION) || iskw(p, KW_PROPERTY)) {
        n = parse_proc(p, t, flags);
        nl_push(&m->decls, n);
        end_stmt(p);
        return;
    }
    if (accept_kw(p, KW_TYPE)) { n = parse_type(p, t, flags); nl_push(&m->decls, n); end_stmt(p); return; }
    if (accept_kw(p, KW_ENUM)) { n = parse_enum(p, t, flags); nl_push(&m->decls, n); end_stmt(p); return; }
    if (accept_kw(p, KW_DECLARE)) { n = parse_declare(p, t, flags); nl_push(&m->decls, n); end_stmt(p); return; }
    if (accept_kw(p, KW_EVENT)) {
        n = mk(p, D_EVENT, t);
        n->flags = flags;
        n->name = ident(p, NULL);
        parse_params(p, &n->list);
        nl_push(&m->decls, n);
        end_stmt(p);
        return;
    }
    if (accept_kw(p, KW_IMPLEMENTS)) {
        n = mk(p, D_IMPLEMENTS, t);
        n->name = ident(p, NULL);
        nl_push(&m->decls, n);
        end_stmt(p);
        return;
    }
    if (accept_kw(p, KW_CONST)) { n = parse_const(p, t, flags); nl_push(&m->decls, n); end_stmt(p); return; }
    if (flags || iskw(p, KW_DIM)) {
        accept_kw(p, KW_DIM);
        n = mk(p, D_DIM, t);
        n->flags = flags;
        parse_dim_list(p, n, flags);
        nl_push(&m->decls, n);
        end_stmt(p);
        return;
    }
    /* module-level executable statement */
    {
        NodeList tmp = {0, 0, 0};
        int i;
        int old = p->in_proc;
        p->in_proc = 0;
        n = parse_statement(p);
        p->in_proc = old;
        (void)tmp;
        if (n) {
            if (n->kind == S_DIM) {
                /* a Dim at module level is a module variable, even between statements */
                n->kind = D_DIM;
                nl_push(&m->decls, n);
            } else if (n->kind == S_CONST) {
                n->kind = D_CONST;
                nl_push(&m->decls, n);
            } else if (n->kind == D_PROC) {
                nl_push(&m->decls, n);
            } else {
                nl_push(&m->mainstmts, n);
            }
        }
        (void)i;
    }
}

void parse_module(Program *prog, Module *m, Token *toks, int ntoks)
{
    P p;
    memset(&p, 0, sizeof p);
    p.prog = prog;
    p.mod = m;
    p.t = toks;
    p.n = ntoks;
    p.file = m->file;
    while (!is(&p, TK_EOF)) {
        while (is(&p, TK_NL) || is(&p, TK_COLON)) adv(&p);
        if (is(&p, TK_EOF)) break;
        if (setjmp(p.jb) == 0) {
            int before = p.i;
            parse_toplevel(&p);
            if (p.i == before) { diag(prog, p.file, tk(&p)->line, tk(&p)->col, "unexpected %s", tok_desc(tk(&p))); adv(&p); }
            if (p.pending_next) {
                diag(prog, p.file, tk(&p)->line, tk(&p)->col, "'Next' without 'For'");
                p.pending_next = 0;
            }
        } else {
            skip_line(&p);
        }
        /* stray block terminators at module level */
        if (at_block_end(&p) && !is(&p, TK_EOF)) {
            Token *t = tk(&p);
            diag(prog, p.file, t->line, t->col, "%s without a matching block start",
                 t->kw == KW_END ? xsprintf("'End %s'", kw_name(tkn(&p, 1)->kw)) : tok_desc(t));
            skip_line(&p);
        }
    }
}
