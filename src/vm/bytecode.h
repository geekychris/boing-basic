/* bytecode.h - Boing BASIC VM image and instruction set */
#ifndef BB_BYTECODE_H
#define BB_BYTECODE_H

#include <stdio.h>
#include "../runtime/boing.h"

#define BBC_MAGIC "BBC1"
#define BBC_VERSION 3

/* OP(name, number of operand words) */
#define BB_OPCODES(OP) \
    OP(NOP, 0) OP(PUSHI, 1) OP(PUSHL, 1) OP(PUSHB, 1) OP(PUSHK, 1) OP(PUSHEMPTY, 0) \
    OP(PUSHNULL, 0) OP(PUSHNOTHING, 0) OP(PUSHMISSING, 0) OP(POP, 0) OP(DUP, 0) \
    OP(LDL, 1) OP(LDLS, 1) OP(LDLV, 1) OP(STL, 1) OP(STLS, 1) OP(STLV, 1) \
    OP(LDG, 1) OP(LDGS, 1) OP(LDGV, 1) OP(STG, 1) OP(STGS, 1) OP(STGV, 1) \
    OP(LDF, 1) OP(LDFV, 1) OP(STF, 1) OP(STFV, 1) \
    OP(LADDR, 2) OP(GADDR, 2) OP(FADDR, 2) OP(LDR, 2) OP(STR, 2) \
    OP(LDIND, 1) OP(STIND, 1) OP(ELEM, 1) OP(UFIELD, 2) OP(MFIELD, 3) OP(UDTNEW, 1) \
    OP(ADD_B, 0) OP(SUB_B, 0) OP(MUL_B, 0) \
    OP(ADD_I, 0) OP(SUB_I, 0) OP(MUL_I, 0) OP(NEG_I, 0) OP(IDIV_I, 0) OP(MOD_I, 0) \
    OP(ADD_L, 0) OP(SUB_L, 0) OP(MUL_L, 0) OP(NEG_L, 0) OP(IDIV_L, 0) OP(MOD_L, 0) \
    OP(ADD_F, 0) OP(SUB_F, 0) OP(MUL_F, 0) OP(DIV_F, 0) OP(NEG_F, 0) \
    OP(ADD_D, 0) OP(SUB_D, 0) OP(MUL_D, 0) OP(DIV_D, 0) OP(NEG_D, 0) OP(POW_D, 0) \
    OP(ADD_C, 0) OP(SUB_C, 0) OP(MUL_C, 0) OP(NEG_C, 0) \
    OP(ADD_DT, 0) OP(SUB_DT, 0) \
    OP(CAT, 0) OP(LIKE, 1) \
    OP(CMP_I, 1) OP(CMP_L, 1) OP(CMP_D, 1) OP(CMP_C, 1) OP(CMP_S, 2) \
    OP(LOGIC, 2) OP(NOT, 1) \
    OP(VARITH, 1) OP(VCMP, 2) OP(VNEG, 0) OP(VNOT, 0) OP(VCAT, 0) \
    OP(IS, 0) OP(TYPEOF, 1) OP(CVT, 1) OP(CVTFIX, 1) OP(CHKCLS, 1) OP(CVTARR, 1) \
    OP(JMP, 1) OP(JF, 1) OP(JT, 1) \
    OP(FORCHK_I, 4) OP(FORINC_I, 4) OP(FORCHK_L, 4) OP(FORINC_L, 4) OP(FORCHK_D, 4) OP(FORINC_D, 4) \
    OP(FORCHKV, 1) \
    OP(CALL, 1) OP(CALLM, 3) OP(CALLB, 3) OP(CALLD, 2) OP(INVOKE, 3) OP(VSTOREIDX, 1) OP(VINDEX, 1) \
    OP(NEW, 1) OP(NEWCOLL, 0) OP(RET, 0) OP(END, 0) OP(STOP, 0) \
    OP(ONERR, 2) OP(RESUME, 2) OP(ERRRAISE, 0) OP(ERROP, 1) \
    OP(GOSUB, 1) OP(RETSUB, 0) OP(ONGOTO, 1) \
    OP(SETFN, 0) OP(PRT, 0) OP(PRTCOMMA, 0) OP(PRTNL, 0) OP(PRTSPC, 0) OP(PRTTAB, 0) OP(WRT, 1) \
    OP(INFIELD, 1) OP(INEND, 0) OP(LINEIN, 0) OP(PROMPT, 1) \
    OP(OPEN, 1) OP(CLOSE, 0) OP(CLOSEALL, 0) OP(GETREC, 2) OP(PUTREC, 2) OP(SEEK, 0) OP(NAMEF, 0) \
    OP(REDIM, 4) OP(ERASE, 0) OP(MIDSET, 0) \
    OP(FEBEGIN, 1) OP(FENEXT, 2) OP(FEEND, 1) \
    OP(RAISEEV, 3) OP(WEVCONN, 3) OP(ARRLIT, 1) OP(SWAP, 0) OP(LINE, 1) OP(UNKEEP, 0) OP(LDE1, 1) \
    /* register forms (operands are frame slots, I immediates, K constants): must stay last */ \
    OP(R_MOV, 2) OP(R_MOVI_I, 2) OP(R_MOVI_L, 2) OP(R_MOVK, 2) \
    OP(R_ADD_LRR, 3) OP(R_ADD_LRI, 3) OP(R_SUB_LRR, 3) OP(R_SUB_LRI, 3) OP(R_SUB_LIR, 3) \
    OP(R_MUL_LRR, 3) OP(R_MUL_LRI, 3) OP(R_IDIV_LRR, 3) OP(R_IDIV_LRI, 3) OP(R_MOD_LRR, 3) OP(R_MOD_LRI, 3) \
    OP(R_AND_LRR, 3) OP(R_AND_LRI, 3) OP(R_OR_LRR, 3) OP(R_OR_LRI, 3) OP(R_XOR_LRR, 3) OP(R_XOR_LRI, 3) OP(R_NEG_L, 2) \
    OP(R_ADD_IRR, 3) OP(R_ADD_IRI, 3) OP(R_SUB_IRR, 3) OP(R_SUB_IRI, 3) OP(R_SUB_IIR, 3) \
    OP(R_MUL_IRR, 3) OP(R_MUL_IRI, 3) OP(R_IDIV_IRR, 3) OP(R_IDIV_IRI, 3) OP(R_MOD_IRR, 3) OP(R_MOD_IRI, 3) \
    OP(R_AND_IRR, 3) OP(R_AND_IRI, 3) OP(R_OR_IRR, 3) OP(R_OR_IRI, 3) OP(R_XOR_IRR, 3) OP(R_XOR_IRI, 3) OP(R_NEG_I, 2) \
    OP(R_ADD_DRR, 3) OP(R_ADD_DRK, 3) OP(R_SUB_DRR, 3) OP(R_SUB_DRK, 3) OP(R_SUB_DKR, 3) \
    OP(R_MUL_DRR, 3) OP(R_MUL_DRK, 3) OP(R_DIV_DRR, 3) OP(R_DIV_DRK, 3) OP(R_DIV_DKR, 3) OP(R_NEG_D, 2) \
    OP(R_CVT_LD, 2) OP(R_CVT_ID, 2) OP(R_CVT_IL, 2) \
    OP(R_JCMP_LRR, 4) OP(R_JCMP_LRI, 4) OP(R_JCMP_IRR, 4) OP(R_JCMP_IRI, 4) OP(R_JCMP_DRR, 4) OP(R_JCMP_DRK, 4) \
    OP(R_LDE1, 4) OP(R_STE1, 4) OP(R_LDE2, 5) OP(R_STE2, 5) OP(R_LDEF1, 5) OP(R_STEF1, 5) OP(R_LDF, 4) OP(R_STF, 4) \
    OP(R_JNZ, 2) OP(R_JZ, 2)

enum {
#define OP_ENUM(n, k) I_##n,
    BB_OPCODES(OP_ENUM)
#undef OP_ENUM
    I__COUNT
};
#define I_R_FIRST I_R_MOV

/* ERROP sub-operations */
enum { EO_NUMBER, EO_DESC, EO_SOURCE, EO_SETNUMBER, EO_SETDESC, EO_SETSOURCE, EO_CLEAR, EO_RAISE, EO_ERROR };
/* ONERR modes */
enum { OE_NONE, OE_GOTO, OE_RESUMENEXT };
/* RESUME modes */
enum { RS_PLAIN, RS_NEXT, RS_LABEL };
/* VARITH ops */
enum { VA_ADD, VA_SUB, VA_MUL, VA_DIV, VA_IDIV, VA_MOD, VA_POW, VA_AND, VA_OR, VA_XOR, VA_EQV, VA_IMP };
/* LOGIC ops */
enum { LG_AND, LG_OR, LG_XOR, LG_EQV, LG_IMP };

/* storage descriptor of a local, global or field: how it is initialised */
typedef struct VMSlot {
    uint16_t vt;            /* BB_xxx; BB_ARRAY|elem; BB_UDT */
    int16_t udt;            /* UDT index (BB_UDT or array of UDT) */
    int16_t fixlen;         /* String * n */
    int16_t ndims;          /* fixed array: dims (0 = dynamic) */
    int16_t isref;          /* holds a BB_REF (ByRef param, With record) */
    int16_t newcls;         /* As New (class index + 1, -1 = Collection) */
    int32_t lb[BB_MAXDIMS], ub[BB_MAXDIMS];
    char *name;
} VMSlot;

typedef struct VMLine { int32_t pc, line; } VMLine;

typedef struct VMProc {
    char *name;
    int32_t module;
    int32_t file;
    int32_t kind;           /* PK_xxx */
    int32_t cls;            /* class index or -1 */
    int32_t nparams;        /* including Me for methods */
    int32_t nlocals;        /* slots incl. params */
    int32_t ret_slot;       /* -1 for subs */
    int32_t code;           /* start offset */
    int32_t has_onerror;
    VMSlot *slots;
    int32_t *param_def;     /* per user param: const index, -1 = required, -2 = Missing */
    uint8_t *param_byref;
    int32_t nlines;
    VMLine *lines;          /* statement starts: pc -> line */
    int32_t is_public;
    int32_t hidden;         /* first hidden slot (by-reference temporaries) */
} VMProc;

typedef struct VMMember {
    char *name;
    int32_t field;          /* field index or -1 */
    int32_t method, pget, plet, pset;   /* proc indices or -1 */
} VMMember;

typedef struct VMClass {
    char *name;
    int32_t nfields;
    VMSlot *fields;
    int32_t init_proc, term_proc;
    int32_t nvtbl;
    int32_t *vtbl;          /* own public members: proc indices */
    int32_t nifaces;
    int32_t *iface_cls;     /* implemented class indices */
    int32_t **iface_vtbl;   /* per iface: proc index per iface slot */
    int32_t nmembers;
    VMMember *members;
    int32_t nevents;
    char **events;
    bb_class rt;            /* runtime class (built at load) */
    bb_iface *rt_ifaces;
} VMClass;

typedef struct VMWev {          /* a WithEvents variable's handlers */
    int32_t cls;                /* source class */
    int32_t *handler;           /* per event index: proc index or -1 */
    int32_t in_class;           /* receiver: class index, or -1 for a module */
    int32_t hidden;             /* hidden global/field holding the connection */
} VMWev;

typedef struct VMUdt {
    char *name;
    int32_t nfields;
    VMSlot *fields;
    bb_udt_desc desc;           /* built at load */
    bb_field *rtfields;
} VMUdt;

typedef struct VMImage {
    int32_t *code;
    int32_t ncode, capcode;
    bb_value *consts;
    int32_t nconsts, capconsts;
    VMProc *procs;
    int32_t nprocs;
    VMSlot *globals;
    int32_t nglobals;
    int32_t *global_mod;
    VMClass *classes;
    int32_t nclasses;
    VMUdt *udts;
    int32_t nudts;
    VMWev *wevs;
    int32_t nwevs;
    bb_declare *decls;
    int32_t ndecls;
    char **files;
    int32_t nfiles;
    char **modules;
    int32_t nmodules;
    int32_t startup;            /* proc index */
    int32_t stack;
    int32_t nforms;             /* forms: module index, window name, .afg text and path */
    int32_t *form_mod;
    char **form_name, **form_afg, **form_path;
    int32_t startup_form;       /* index into forms, -1 = none */
} VMImage;

extern const char *const bb_opnames[];
extern const int bb_opwords[];

/* vm.c */
int vm_run(VMImage *img, int argc, char **argv);    /* exit code */
void vm_disasm(VMImage *img, FILE *out);
int vm_save(VMImage *img, const char *path);
VMImage *vm_load(const char *path);

#endif
