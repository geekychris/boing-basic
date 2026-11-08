/* sema.h - internal interface of the semantic analyser */
#ifndef SEMA_H
#define SEMA_H
#include "bbc.h"

enum { M_VALUE = 1, M_STMT, M_LVAL, M_SETLVAL, M_ARG };

typedef struct Ctx {
    Program *prog;
    Module *mod;
    Proc *proc;
    ClassInfo *cls;
    Scope *scope;
    NodeList withs;         /* E_VAR nodes of the active With temps */
    int ntemps;
    int in_loop_for, in_loop_do;
    int const_ctx;
} Ctx;

#define ERR(c, n, ...) diag((c)->prog, (n)->file, (n)->line, (n)->col, __VA_ARGS__)

Node *check_expr(Ctx *c, Node *e, int mode);
Node *check_value(Ctx *c, Node *e);           /* rvalue with a value */
Node *coerce(Ctx *c, Node *e, Type *to);
Node *coerce_explicit(Ctx *c, Node *e, Type *to);
Node *mk_const_node(Node *at, CVal *v);
Type *cval_type(CVal *v);
Type *resolve_type(Ctx *c, Node *tynode, char suffix, int *fixlen);
Type *suffix_type(char s);
Sym *new_temp(Ctx *c, Type *t, Node *at);
Sym *declare_implicit(Ctx *c, Node *e);
int is_lvalue(Node *e);
void check_block(Ctx *c, NodeList *body);
Node *mk_var(Node *at, Sym *s);
Node *make_call(Ctx *c, Node *at, Proc *pr, NodeList *args, Node *self, int mode);
ClassInfo *find_class(Ctx *c, const char *name);
int fold_const(Ctx *c, Node *e, CVal *out);
void cval_from_node(Node *e, CVal *v);
Node *conv_to_bool_cond(Ctx *c, Node *e);

#endif
