/* bbc.h - Boing BASIC compiler: shared declarations */
#ifndef BBC_H
#define BBC_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

typedef struct Node Node;
typedef struct Type Type;
typedef struct Sym Sym;
typedef struct Proc Proc;
typedef struct Module Module;
typedef struct ClassInfo ClassInfo;
typedef struct Udt Udt;
typedef struct Scope Scope;
typedef struct Program Program;

/* ---------- utilities ---------- */
void *xmalloc(size_t n);
void *xcalloc(size_t n, size_t m);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);
char *xstrndup(const char *s, size_t n);
char *xsprintf(const char *fmt, ...);
int name_eq(const char *a, const char *b);      /* case-insensitive */
char *str_lower(const char *s);

typedef struct NodeList { Node **v; int n, cap; } NodeList;
void nl_push(NodeList *l, Node *n);

typedef struct Buf { char *p; size_t n, cap; } Buf;
void buf_put(Buf *b, const char *s, size_t n);
void buf_puts(Buf *b, const char *s);
void buf_printf(Buf *b, const char *fmt, ...);
void buf_free(Buf *b);

/* ---------- diagnostics ---------- */
void diag(Program *p, int file, int line, int col, const char *fmt, ...);
void diag_warn(Program *p, int file, int line, int col, const char *fmt, ...);
const char *file_name(Program *p, int file);

/* ---------- lexer ---------- */
enum {
    TK_EOF, TK_NL, TK_COLON, TK_ID, TK_INT, TK_FLT, TK_STR, TK_DATE, TK_KW,
    TK_PLUS, TK_MINUS, TK_STAR, TK_SLASH, TK_BSLASH, TK_CARET, TK_AMP,
    TK_EQ, TK_NE, TK_LT, TK_GT, TK_LE, TK_GE, TK_LP, TK_RP, TK_COMMA, TK_SEMI,
    TK_DOT, TK_HASH, TK_BANG, TK_ASSIGN /* := */
};

/* reserved words */
enum {
    KW_NONE, KW_AND, KW_AS, KW_BYREF, KW_BYVAL, KW_CALL, KW_CASE, KW_CLOSE, KW_CONST,
    KW_DECLARE, KW_DIM, KW_DO, KW_EACH, KW_ELSE, KW_ELSEIF, KW_EMPTY, KW_END, KW_ENUM,
    KW_EQV, KW_ERASE, KW_ERROR, KW_EVENT, KW_EXIT, KW_FALSE, KW_FOR, KW_FRIEND, KW_FUNCTION,
    KW_GET, KW_GLOBAL, KW_GOSUB, KW_GOTO, KW_IF, KW_IMP, KW_IMPLEMENTS, KW_IN, KW_INPUT,
    KW_IS, KW_LET, KW_LIKE, KW_LOOP, KW_ME, KW_MOD, KW_NEW, KW_NEXT, KW_NOT, KW_NOTHING,
    KW_NULL, KW_ON, KW_OPEN, KW_OPTION, KW_OPTIONAL, KW_OR, KW_PARAMARRAY, KW_PRESERVE,
    KW_PRINT, KW_PRIVATE, KW_PROPERTY, KW_PUBLIC, KW_RAISEEVENT, KW_REDIM, KW_RESUME,
    KW_RETURN, KW_SELECT, KW_SET, KW_STATIC, KW_STEP, KW_STOP, KW_SUB, KW_THEN, KW_TO,
    KW_TRUE, KW_TYPE, KW_TYPEOF, KW_UNTIL, KW_WEND, KW_WHILE, KW_WITH, KW_WITHEVENTS,
    KW_WRITE, KW_XOR, KW_ADDRESSOF, KW_LSET, KW_RSET, KW_DEBUG_UNUSED,
    KW_COUNT
};

typedef struct Token {
    int kind;
    int kw;                 /* TK_KW */
    int line, col;
    char *text;             /* TK_ID name (without suffix), TK_STR contents */
    int len;                /* TK_STR length */
    char suffix;            /* TK_ID / number type suffix: % & ! # @ $ or 0 */
    int64_t ival;
    double fval;
    int ity;                /* TK_INT: T_INTEGER / T_LONG; TK_FLT: T_SINGLE/T_DOUBLE/T_CURRENCY */
    int space_before;
    int line_start;         /* first token of a line */
} Token;

typedef struct Lexer {
    Program *prog;
    int file;
    const char *src, *p;
    int line;
    const char *line_begin;
    Token *toks;
    int ntoks, cap;
} Lexer;

int lex_file(Program *prog, int file, const char *src, Token **out, int *ntoks);
const char *kw_name(int kw);

/* ---------- types ---------- */
enum {
    T_VOID, T_BOOLEAN, T_BYTE, T_INTEGER, T_LONG, T_SINGLE, T_DOUBLE, T_CURRENCY,
    T_DATE, T_STRING, T_VARIANT, T_OBJECT, T_UDT, T_ARRAY, T_ANY /* builtin param */
};

struct Type {
    int kind;
    ClassInfo *cls;         /* T_OBJECT: NULL = Object */
    Udt *udt;               /* T_UDT */
    Type *elem;             /* T_ARRAY */
    int ndims;              /* T_ARRAY: 0 = unknown (dynamic) */
    int fixlen;             /* T_STRING: String * n */
};

extern Type ty_void, ty_boolean, ty_byte, ty_integer, ty_long, ty_single, ty_double,
    ty_currency, ty_date, ty_string, ty_variant, ty_object;
Type *type_prim(int kind);
Type *type_array(Type *elem, int ndims);
Type *type_object(ClassInfo *cls);
Type *type_udt(Udt *u);
int type_is_numeric(const Type *t);
int type_is_integral(const Type *t);
int type_eq(const Type *a, const Type *b);
const char *type_name(const Type *t);
int type_vartype(const Type *t);        /* BB_xxx code */
int type_rank(const Type *t);

/* ---------- constant values ---------- */
typedef struct CVal {
    int type;               /* T_xxx; T_VOID = not constant; T_VARIANT+isnull/isempty */
    int64_t i;
    double d;
    char *s;
    int slen;
    int is_null, is_empty, is_nothing;
} CVal;

/* ---------- AST ---------- */
enum {
    /* expressions (parser) */
    E_INT = 1, E_FLT, E_STR, E_BOOL, E_DATE, E_NOTHING, E_EMPTY, E_NULL, E_MISSING,
    E_NAME, E_DOT, E_APPLY, E_UN, E_BIN, E_PAREN, E_NEW, E_TYPEOF, E_NAMEDARG, E_ME, E_ADDROF,
    /* expressions (after sema) */
    E_VAR, E_CONST, E_FIELD, E_INDEX, E_CALL, E_BUILTIN, E_LATE, E_MCALL, E_MFIELD,
    E_CONV, E_WITHVAR, E_ERRPROP, E_CASEIS, E_CASERANGE, E_ARRAYLIT, E_DEFPROP,
    E_EXTCALL,              /* a linked extension's function (name; list = Variant arguments) */
    E_WBARG,    /* a typed variable passed ByRef to a Variant parameter: a = the variable, b = a hidden
                   Variant local (passed), c = the variable as a Variant; copied back after the call */

    /* statements */
    S_EXPR = 100, S_LET, S_SET, S_DIM, S_IF, S_ELSEIF, S_SELECT, S_CASE, S_FOR, S_FOREACH,
    S_DO, S_EXIT, S_GOTO, S_GOSUB, S_RETURN, S_LABEL, S_ONERROR, S_RESUME, S_PRINT,
    S_PRINTITEM, S_WRITE, S_INPUT, S_LINEINPUT, S_OPEN, S_CLOSE, S_GET, S_PUT, S_SEEK,
    S_REDIM, S_ERASE, S_END, S_STOP, S_WITH, S_RAISEEVENT, S_ERROR, S_MIDASSIGN, S_LSET,
    S_RSET, S_CONST, S_NAME, S_ONGOTO, S_BLOCK, S_NOP, S_STATIC,

    /* declarations */
    D_PROC = 200, D_TYPE, D_ENUM, D_DIM, D_CONST, D_DECLARE, D_EVENT, D_IMPLEMENTS, D_OPTION,
    D_VARDECL /* one declarator */
};

/* binary/unary operators (Node.op) */
enum {
    OP_NONE, OP_POW, OP_NEG, OP_MUL, OP_DIV, OP_IDIV, OP_MOD, OP_ADD, OP_SUB, OP_CAT,
    OP_EQ, OP_NE, OP_LT, OP_GT, OP_LE, OP_GE, OP_LIKE, OP_IS, OP_NOT, OP_AND, OP_OR,
    OP_XOR, OP_EQV, OP_IMP, OP_PLUS
};

/* statement sub-ops */
enum { EXIT_SUB = 1, EXIT_FUNCTION, EXIT_PROPERTY, EXIT_FOR, EXIT_DO };
enum { DO_NONE, DO_PRE_WHILE, DO_PRE_UNTIL, DO_POST_WHILE, DO_POST_UNTIL };
enum { ONERR_GOTO = 1, ONERR_RESUMENEXT, ONERR_GOTO0, ONERR_GOTOM1 };
enum { RES_PLAIN = 1, RES_NEXT, RES_LABEL };
enum { PSEP_NONE, PSEP_SEMI, PSEP_COMMA };
enum { PI_EXPR, PI_SPC, PI_TAB };

struct Node {
    int kind;
    int op;
    int line, col, file;
    Type *ty;               /* expression type (sema) */
    Node *a, *b, *c, *d;
    NodeList list, list2;
    char *name;
    char suffix;            /* E_NAME type suffix */
    int slen;               /* E_STR length */
    int64_t ival;
    double fval;
    Sym *sym;               /* resolved symbol (E_VAR, E_CONST) */
    Proc *proc;             /* E_CALL / E_MCALL target, D_PROC */
    int bi;                 /* E_BUILTIN index */
    int flags;
    int id;                 /* emitter scratch */
    CVal cv;                /* E_CONST */
    ClassInfo *cls;
    Udt *udt;
    int field;              /* E_FIELD / E_MFIELD index */
    int argc_kind;          /* E_LATE invoke kind */
    int rtid;               /* E_LATE on a built-in runtime class: member id + 1 (0 = by name) */
    int text;               /* string comparisons: Option Compare Text */
};

/* Node.flags */
#define NF_BYREF      0x0001  /* argument passed by reference (lvalue) */
#define NF_PUBLIC     0x0002
#define NF_PRIVATE    0x0004
#define NF_STATIC     0x0008
#define NF_NEW        0x0010  /* As New */
Node *late_byref_var(Node *x);
int decl_nullstr(Node *a);       /* Declare argument: the vbNullString constant (passed as 0) */
int decl_strvar(Node *a);        /* Declare argument: a String variable passed ByVal (buffer, copied back) */   /* a late-bound call's argument that is passed by reference */
#define NF_WITHEVENTS 0x0020
#define NF_PRESERVE   0x0040
#define NF_DEBUG      0x0080  /* Debug.Print */
#define NF_QUESTION   0x0100  /* Input "x"; vs "x", */
#define NF_SINGLELINE 0x0200
#define NF_CASEELSE   0x0400
#define NF_ARRAY      0x0800  /* declarator has () */
#define NF_ISDEFAULT  0x1000
#define NF_VOIDCALL   0x2000  /* call used as statement: discard result */
#define NF_PARENARG   0x4000  /* (x): forced ByVal */
#define NF_FRIEND     0x8000

Node *node_new(int kind, int file, int line, int col);

/* ---------- symbols ---------- */
enum { SK_VAR = 1, SK_CONST, SK_PROC, SK_UDT, SK_ENUM, SK_CLASS, SK_MODULE, SK_LABEL, SK_PROPGROUP };
enum { ST_GLOBAL = 1, ST_LOCAL, ST_PARAM, ST_STATIC, ST_FIELD };

struct Sym {
    int kind;
    char *name;
    Type *ty;
    int storage;
    int index;              /* global index, local slot, field index */
    int byref;              /* ByRef parameter */
    int is_public;
    int fixed_array;        /* Dim a(10): fixed bounds, allocated at entry */
    NodeList bounds;        /* fixed array bounds: pairs (lb, ub) */
    int ndims;
    Module *mod;
    Proc *proc;             /* SK_PROC target; owner of locals */
    ClassInfo *cls;         /* SK_CLASS / field owner */
    Udt *udt;
    CVal cv;                /* SK_CONST */
    int line, col, file;
    int is_new;             /* As New: auto-instantiate */
    int withevents;
    int implicit;
    int is_param_array;
    int used, assigned;
    int is_retvar;
    int optional;
    char *cname;
    Proc *pget, *plet, *pset;   /* SK_PROPGROUP */
    Sym *next;              /* scope chain */
    int label_id;
    Proc *user;             /* globals: the one procedure using it, if only one */
    int shared;             /* globals: used by several procedures (or from outside) */
    Module *ambig;          /* a Public procedure: another module with a Public one of this name */
};

typedef struct ScopeEnt { Sym *sym; struct ScopeEnt *next; } ScopeEnt;
struct Scope {
    Scope *parent;
    ScopeEnt **tab;
    int cap, n;
};
Scope *scope_new(Scope *parent);
Sym *scope_find_local(Scope *s, const char *name);
Sym *scope_find(Scope *s, const char *name);
void scope_add(Scope *s, Sym *sym);

typedef struct Param {
    char *name;
    Type *ty;
    int byref, optional, paramarray;
    Node *defexpr;
    CVal def;
    int has_def;
    Sym *sym;
    int line, col;
} Param;

enum { PK_SUB = 1, PK_FUNCTION, PK_PGET, PK_PLET, PK_PSET, PK_DECLARE, PK_EVENT, PK_MAIN };

struct Proc {
    char *name;
    int kind;
    Type *ret;              /* NULL for subs */
    Param *params;
    int nparams;
    int min_args;
    Module *mod;
    ClassInfo *cls;
    int is_public;
    int all_static;
    Node *decl;
    NodeList body;
    Scope *scope;
    Sym **locals;           /* params first, then locals, then statics/ret */
    int nlocals, caplocals;
    Sym *retvar;
    int has_onerror, has_resume, has_gosub, has_labels;
    int index;              /* program-wide proc index */
    int vslot;              /* vtable slot within the class (-1 = private) */
    char *lib, *alias, *iface;  /* Declare */
    int version;
    int is_func_declare;
    int clib;               /* Declare ... Lib "C": a C function of a CSource= file (docs/extensions.md) */
    int line, file;
    char *cname;
    int is_handler;
    Proc *impl_of;          /* Implements: interface proc this implements */
    ClassInfo *impl_iface;
    int defined;            /* body present */
    Sym **labels; int nlabels;
    int event_index;        /* PK_EVENT */
};

struct ClassInfo {
    char *name;
    Module *mod;
    int builtin;            /* runtime class (Collection) */
    const char *rt_new;     /* builtin: C constructor */
    struct ExtClass *xcls;  /* a linked extension's class (its .bbx): members checked, called by name */
    const void *rtcls;      /* a built-in runtime class (Engine3D, Canvas, Audio: its bb_class): members resolved at compile time */
    Sym **fields; int nfields;
    Proc **methods; int nmethods;
    Proc **vtbl; int nvtbl;           /* public members in slot order */
    Proc **events; int nevents;
    ClassInfo **impls; int nimpls;    /* Implements */
    int is_interface;
    Proc *init, *term;
    int index;
    char *cname;
    Sym **wevars; int nwevars;        /* WithEvents fields declared in this class */
};

typedef struct UField {
    char *name;
    Type *ty;
    int fixlen;
    int ndims;
    int lb[8], ub[8];
    int line;
} UField;

struct Udt {
    char *name;
    UField *fields;
    int nfields;
    Module *mod;
    int is_public;
    int index;
    char *cname;
    int line, file;
};

struct Module {
    char *name;
    char *path;
    int file;
    int is_class;
    int is_form;
    ClassInfo *cls;
    NodeList decls;
    NodeList mainstmts;
    Proc *mainproc;
    Scope *scope;
    int opt_explicit, opt_base, opt_text;
    unsigned char deftype[26];  /* DefInt etc.: default type kind by first letter (0 = Variant) */
    Proc **procs; int nprocs;
    char **form_controls; int ncontrols;   /* .afg ids */
    char *form_name;
    Sym *form_var;          /* a form named like its module (window name=X in X.bas): the form object */
    char *afg_path;
    int index;
};

/* linked extensions (docs/extensions.md): what a descriptor name.bbx declares */
typedef struct ExtParam { char *name; char *type; } ExtParam;
typedef struct ExtMember { char *name; int kind; char *sig; char *type; } ExtMember;  /* kind: 0 method, 1 property, 2 property-ro */
typedef struct ExtClass { char *name; char *ext; ExtMember *m; int nm; } ExtClass;
typedef struct ExtFunc { char *name; char *ext; ExtParam *p; int np; char *ret; char *sig; int line, file; } ExtFunc;
typedef struct ExtInfo { char *name; char *dir; char *src; char *bbx; } ExtInfo;   /* Extension=dir/name */

struct Program {
    Module **mods; int nmods;
    Scope *global;
    Proc **procs; int nprocs;
    Sym **globals; int nglobals;
    Udt **udts; int nudts;
    ClassInfo **classes; int nclasses;
    char **files; int nfiles;           /* source file paths */
    char **srcs;
    int nerrors, nwarnings;
    int max_errors;
    Module *startup;
    Proc *startup_proc;
    char *name;
    char *title;                        /* Title= (App.Title; else Name=) */
    char *version;                      /* Version= as written ("1.2.3"), NULL = none */
    int ver_major, ver_minor, ver_rev;  /* App.Major / Minor / Revision */
    int stack;
    char *c_name;                       /* the generated C file's name (#line back to it) */
    FILE *diag_out;
    /* compile for: */
    int target_vm;
    Buf *diag_buf;
    /* Extension= / CSource= (docs/extensions.md) */
    ExtInfo *exts; int nexts;
    ExtClass **xclasses; int nxclasses;
    ExtFunc **xfuncs; int nxfuncs;
    char **csources; int ncsources;
};
#define IS_REGCLS(c) ((c)->rtcls || (c)->xcls)   /* a registered (runtime or extension) class */
int bbx_load(Program *p, const char *path, const char *ext);   /* parse name.bbx into p; 0 on error */
ExtClass *ext_class_find(Program *p, const char *name);
ExtMember *ext_member_find(ExtClass *c, const char *name);
ExtFunc *ext_func_find(Program *p, const char *name);

Program *prog_new(void);
char *read_file(const char *path, long *len);   /* malloc'ed, NUL terminated; NULL if unreadable */
Module *prog_add_source(Program *p, const char *path, const char *src, int is_class);
int prog_load_file(Program *p, const char *path);      /* .bas/.cls/.bbp */
int prog_compile(Program *p);                           /* parse + sema; 0 = errors */

/* parser */
void parse_module(Program *p, Module *m, Token *toks, int ntoks);

/* sema */
int sema_program(Program *p);
int const_eval(Program *p, Node *e, CVal *out);
int proc_local_add(Proc *pr, Sym *s);

/* builtins */
enum { BIF_TEXT = 1, BIF_SPECIAL = 2, BIF_SUB = 4, BIF_VARARGS = 8, BIF_STRSUFFIX = 16, BIF_NOARGS_OK = 32 };
typedef struct Builtin {
    const char *name;
    int ret;                /* T_xxx or T_VOID */
    int minargs, maxargs;
    const char *params;     /* one char per param: s l i d f D b v V(any by value) a(array) y(byte) c(cur) */
    const char *defaults;   /* comma separated literal defaults, "" = none, "M" missing */
    const char *cfn;
    int flags;
} Builtin;
extern const Builtin builtins[];
extern const int nbuiltins;
int builtin_find(const char *name);
enum {   /* indices of builtins referenced directly by the compiler */
    BI__FIRST_SPECIAL = 0
};

/* symbols listing (boing symbols) */
void print_symbols(Program *p, Module *m, FILE *out);

/* back ends */
int emit_c(Program *p, Buf *out, int debug);
struct VMImage;
struct VMImage *emit_bytecode(Program *p);

#endif
