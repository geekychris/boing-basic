/* lexer.c - tokens for Boing BASIC (VB6 lexical rules) */
#include "bbc.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

static const char *kwnames[KW_COUNT] = {
    "", "And", "As", "ByRef", "ByVal", "Call", "Case", "Close", "Const",
    "Declare", "Dim", "Do", "Each", "Else", "ElseIf", "Empty", "End", "Enum",
    "Eqv", "Erase", "Error", "Event", "Exit", "False", "For", "Friend", "Function",
    "Get", "Global", "GoSub", "GoTo", "If", "Imp", "Implements", "In", "Input",
    "Is", "Let", "Like", "Loop", "Me", "Mod", "New", "Next", "Not", "Nothing",
    "Null", "On", "Open", "Option", "Optional", "Or", "ParamArray", "Preserve",
    "Print", "Private", "Property", "Public", "RaiseEvent", "ReDim", "Resume",
    "Return", "Select", "Set", "Static", "Step", "Stop", "Sub", "Then", "To",
    "True", "Type", "TypeOf", "Until", "Wend", "While", "With", "WithEvents",
    "Write", "Xor", "AddressOf", "LSet", "RSet", "#"
};

const char *kw_name(int kw) { return kw > 0 && kw < KW_COUNT ? kwnames[kw] : "?"; }

static int kw_lookup(const char *s, size_t n)
{
    int i;
    for (i = 1; i < KW_COUNT - 1; i++)
        if (strlen(kwnames[i]) == n && strncasecmp(kwnames[i], s, n) == 0) return i;
    return 0;
}

static Token *push(Lexer *L, int kind, const char *at)
{
    Token *t;
    if (L->ntoks == L->cap) {
        L->cap = L->cap ? L->cap * 2 : 256;
        L->toks = (Token *)xrealloc(L->toks, sizeof(Token) * (size_t)L->cap);
    }
    t = &L->toks[L->ntoks++];
    memset(t, 0, sizeof *t);
    t->kind = kind;
    t->line = L->line;
    t->col = (int)(at - L->line_begin) + 1;
    t->space_before = at > L->src && (at[-1] == ' ' || at[-1] == '\t');
    t->line_start = L->ntoks == 1 || L->toks[L->ntoks - 2].kind == TK_NL;
    return t;
}

static int is_idc(int c) { return isalnum(c) || c == '_' || (c & 0x80); }

static void lex_error(Lexer *L, const char *at, const char *msg)
{
    diag(L->prog, L->file, L->line, (int)(at - L->line_begin) + 1, "%s", msg);
}

static int looks_like_date(const char *p)
{
    /* p points after '#': date literal if a closing # follows on this line and the
     * contents look like a date or time */
    const char *q = p;
    int slash = 0, colon = 0, digit = 0;
    while (*q && *q != '#' && *q != '\n' && *q != '\r') {
        if (*q == '/' || *q == '-') slash = 1;
        else if (*q == ':') colon = 1;
        else if (isdigit((unsigned char)*q)) digit = 1;
        else if (*q == ',' || *q == '"' || *q == '(' || *q == '=') return 0;
        q++;
    }
    return *q == '#' && digit && (slash || colon);
}

int lex_file(Program *prog, int file, const char *src, Token **out, int *ntoks)
{
    Lexer L;
    const char *p = src;
    memset(&L, 0, sizeof L);
    L.prog = prog;
    L.file = file;
    L.src = src;
    L.line = 1;
    L.line_begin = src;
    /* skip UTF-8 BOM */
    if ((unsigned char)p[0] == 0xEF && (unsigned char)p[1] == 0xBB && (unsigned char)p[2] == 0xBF) p += 3;
    while (*p) {
        int c = (unsigned char)*p;
        Token *t;
        if (c == ' ' || c == '\t' || c == '\f' || c == 0x1a) { p++; continue; }
        if (c == '\r' || c == '\n') {
            if (L.ntoks == 0 || L.toks[L.ntoks - 1].kind != TK_NL) push(&L, TK_NL, p);
            if (c == '\r' && p[1] == '\n') p++;
            p++;
            L.line++;
            L.line_begin = p;
            continue;
        }
        if (c == '\'') {
            while (*p && *p != '\n' && *p != '\r') p++;
            continue;
        }
        /* line continuation: " _" at end of line */
        if (c == '_' && (p == src || p[-1] == ' ' || p[-1] == '\t')) {
            const char *q = p + 1;
            while (*q == ' ' || *q == '\t') q++;
            if (*q == '\r' || *q == '\n' || *q == 0) {
                if (*q == '\r' && q[1] == '\n') q++;
                if (*q) q++;
                p = q;
                L.line++;
                L.line_begin = p;
                continue;
            }
        }
        if (isalpha(c) || (c & 0x80) || (c == '_' && is_idc((unsigned char)p[1]))) {
            const char *st = p;
            size_t n;
            int kw;
            while (is_idc((unsigned char)*p)) p++;
            n = (size_t)(p - st);
            /* Rem comment */
            if (n == 3 && strncasecmp(st, "rem", 3) == 0 &&
                (L.ntoks == 0 || L.toks[L.ntoks - 1].kind == TK_NL || L.toks[L.ntoks - 1].kind == TK_COLON)) {
                while (*p && *p != '\n' && *p != '\r') p++;
                continue;
            }
            kw = kw_lookup(st, n);
            /* a keyword directly after '.' is a member name */
            if (kw && L.ntoks && L.toks[L.ntoks - 1].kind == TK_DOT && !L.toks[L.ntoks - 1].space_before) kw = 0;
            if (kw && L.ntoks && L.toks[L.ntoks - 1].kind == TK_DOT) kw = 0;
            if (kw && !(kw == KW_INPUT || kw == KW_ERROR) ? 1 : 0) {
                /* keywords cannot carry type suffixes, except Input$ / Error$ handled below */
            }
            if (kw && (*p == '$') && (kw == KW_INPUT || kw == KW_ERROR)) kw = 0;
            if (kw) {
                t = push(&L, TK_KW, st);
                t->kw = kw;
                t->text = xstrndup(st, n);
                continue;
            }
            t = push(&L, TK_ID, st);
            t->text = xstrndup(st, n);
            if (*p == '%' || *p == '$' || *p == '#' || *p == '@' ||
                (*p == '!' && !is_idc((unsigned char)p[1]) && p[1] != '[') ||
                (*p == '&' && !is_idc((unsigned char)p[1]) && p[1] != '"' && p[1] != '(')) {
                t->suffix = *p++;
            }
            continue;
        }
        if (isdigit(c) || (c == '.' && isdigit((unsigned char)p[1]))) {
            const char *st = p;
            int isflt = 0;
            char buf[128];
            size_t n;
            while (isdigit((unsigned char)*p)) p++;
            if (*p == '.' && isdigit((unsigned char)p[1])) { isflt = 1; p++; while (isdigit((unsigned char)*p)) p++; }
            else if (*p == '.' && !isalpha((unsigned char)p[1])) { isflt = 1; p++; }
            if ((*p == 'e' || *p == 'E' || *p == 'd' || *p == 'D') &&
                (isdigit((unsigned char)p[1]) || ((p[1] == '+' || p[1] == '-') && isdigit((unsigned char)p[2])))) {
                isflt = 1;
                p += 2;
                while (isdigit((unsigned char)*p)) p++;
            }
            n = (size_t)(p - st);
            if (n >= sizeof buf) n = sizeof buf - 1;
            memcpy(buf, st, n);
            buf[n] = 0;
            { char *q; for (q = buf; *q; q++) if (*q == 'd' || *q == 'D') *q = 'e'; }
            if (isflt) {
                t = push(&L, TK_FLT, st);
                t->fval = strtod(buf, NULL);
                t->ity = T_DOUBLE;
            } else {
                double v = strtod(buf, NULL);
                if (v <= 2147483647.0) {
                    t = push(&L, TK_INT, st);
                    t->ival = (int64_t)v;
                    t->ity = v <= 32767 ? T_INTEGER : T_LONG;
                } else {
                    t = push(&L, TK_FLT, st);
                    t->fval = v;
                    t->ity = T_DOUBLE;
                }
            }
            /* suffix */
            if (*p == '%' || *p == '&' || *p == '!' || *p == '#' || *p == '@') {
                char s = *p;
                if (s == '&' && (p[1] == 'H' || p[1] == 'h' || p[1] == 'O' || p[1] == 'o') && 0) {}
                else if (s == '#' && looks_like_date(p + 1)) {}
                else {
                    p++;
                    t->suffix = s;
                    if (s == '%' || s == '&') {
                        double v = t->kind == TK_INT ? (double)t->ival : t->fval;
                        if (t->kind == TK_FLT && v != floor(v)) lex_error(&L, st, "invalid type suffix on a fractional number");
                        if ((s == '%' && (v > 32767 || v < -32768)) || (s == '&' && v > 2147483647.0)) lex_error(&L, st, "overflow in numeric literal");
                        t->kind = TK_INT;
                        t->ival = (int64_t)v;
                        t->ity = s == '%' ? T_INTEGER : T_LONG;
                    } else {
                        double v = t->kind == TK_INT ? (double)t->ival : t->fval;
                        t->kind = TK_FLT;
                        t->fval = v;
                        t->ity = s == '!' ? T_SINGLE : s == '#' ? T_DOUBLE : T_CURRENCY;
                    }
                }
            }
            if (t->kind == TK_FLT && t->ity == T_DOUBLE && !t->suffix) t->ity = T_DOUBLE;
            continue;
        }
        if (c == '&' && (p[1] == 'H' || p[1] == 'h' || p[1] == 'O' || p[1] == 'o') &&
            isxdigit((unsigned char)p[2])) {
            const char *st = p;
            int base = (p[1] == 'H' || p[1] == 'h') ? 16 : 8, digits = 0;
            uint64_t v = 0;
            p += 2;
            while (isxdigit((unsigned char)*p)) {
                int d = isdigit((unsigned char)*p) ? *p - '0' : (toupper((unsigned char)*p) - 'A' + 10);
                if (d >= base) break;
                v = v * (uint64_t)base + (uint64_t)d;
                digits++;
                p++;
            }
            t = push(&L, TK_INT, st);
            if (*p == '&') {
                p++;
                t->suffix = '&';
                t->ival = (int32_t)(uint32_t)v;
                t->ity = T_LONG;
            } else if (*p == '%') {
                p++;
                t->ival = (int16_t)(uint16_t)v;
                t->ity = T_INTEGER;
            } else if (v <= 0xFFFF) {
                t->ival = (int16_t)(uint16_t)v;
                t->ity = T_INTEGER;
            } else {
                t->ival = (int32_t)(uint32_t)v;
                t->ity = T_LONG;
            }
            if (v > 0xFFFFFFFFULL) lex_error(&L, st, "overflow in numeric literal");
            (void)digits;
            continue;
        }
        if (c == '"') {
            const char *st = p;
            Buf b = {0, 0, 0};
            p++;
            for (;;) {
                if (*p == 0 || *p == '\n' || *p == '\r') { lex_error(&L, st, "unterminated string"); break; }
                if (*p == '"') {
                    if (p[1] == '"') { buf_put(&b, "\"", 1); p += 2; continue; }
                    p++;
                    break;
                }
                buf_put(&b, p, 1);
                p++;
            }
            t = push(&L, TK_STR, st);
            t->text = b.p ? b.p : xstrdup("");
            t->len = (int)b.n;
            continue;
        }
        if (c == '#' && looks_like_date(p + 1)) {
            const char *st = p, *e;
            p++;
            e = strchr(p, '#');
            t = push(&L, TK_DATE, st);
            t->text = xstrndup(p, (size_t)(e - p));
            p = e + 1;
            continue;
        }
        {
            const char *st = p;
            int k = -1;
            switch (c) {
            case '+': k = TK_PLUS; break;
            case '-': k = TK_MINUS; break;
            case '*': k = TK_STAR; break;
            case '/': k = TK_SLASH; break;
            case '\\': k = TK_BSLASH; break;
            case '^': k = TK_CARET; break;
            case '&': k = TK_AMP; break;
            case '=': k = TK_EQ; break;
            case '(': k = TK_LP; break;
            case ')': k = TK_RP; break;
            case ',': k = TK_COMMA; break;
            case ';': k = TK_SEMI; break;
            case '.': k = TK_DOT; break;
            case '#': k = TK_HASH; break;
            case '!': k = TK_BANG; break;
            case '<':
                if (p[1] == '>') { k = TK_NE; p++; }
                else if (p[1] == '=') { k = TK_LE; p++; }
                else k = TK_LT;
                break;
            case '>':
                if (p[1] == '=') { k = TK_GE; p++; }
                else if (p[1] == '<') { k = TK_NE; p++; }
                else k = TK_GT;
                break;
            case ':':
                if (p[1] == '=') { k = TK_ASSIGN; p++; }
                else k = TK_COLON;
                break;
            }
            if (k < 0) {
                char m[64];
                snprintf(m, sizeof m, "unexpected character '%c'", c);
                lex_error(&L, st, m);
                p++;
                continue;
            }
            p++;
            push(&L, k, st);
        }
    }
    push(&L, TK_NL, p);
    push(&L, TK_EOF, p);
    *out = L.toks;
    *ntoks = L.ntoks;
    return 1;
}
