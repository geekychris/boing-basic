/* value.c - Variants: lifetime, conversion, arithmetic, comparison */
#include "boing.h"
#include <string.h>
#include <math.h>

void bb_v_release(bb_value *v)
{
    uint16_t t = v->type;
    if (t == BB_STRING) bb_str_release(v->u.s);
    else if (t == BB_OBJECT) bb_obj_release(v->u.o);
    else if (t & BB_ARRAY && !(t & BB_REF)) bb_arr_free(v->u.a);
    else if (t == BB_UDT && v->u.p) {
        bb_udtbox *b = (bb_udtbox *)v->u.p;
        bb_udt_clear(b->desc, b->data);
        bb_free(b);
    }
    v->type = BB_EMPTY;
    v->flags = 0;
    v->u.c = 0;
}

void bb_v_copy(bb_value *dst, const bb_value *src)
{
    *dst = *src;
    if (src->type == BB_STRING) bb_str_retain(src->u.s);
    else if (src->type == BB_OBJECT) bb_obj_retain(src->u.o);
    else if (src->type & BB_REF) {
        bb_value tmp;
        const bb_value *v = bb_v_deref(src, &tmp);
        bb_v_copy(dst, v);
    }
    else if (src->type & BB_ARRAY) dst->u.a = src->u.a ? bb_arr_copy(src->u.a) : NULL;
    else if (src->type == BB_UDT && src->u.p) {
        const bb_udtbox *sb = (const bb_udtbox *)src->u.p;
        bb_value n = bb_v_udt_new(sb->desc);
        bb_udt_copy(sb->desc, bb_v_udt_data(&n), sb->data);
        *dst = n;
    }
}

void bb_v_assign(bb_value *dst, const bb_value *src)
{
    bb_value n;
    if (dst == src) return;
    bb_v_copy(&n, src);
    bb_v_set(dst, n);
}

bb_value bb_v_dup(const bb_value *src)
{
    bb_value n;
    bb_v_copy(&n, src);
    return n;
}

const bb_value *bb_v_deref(const bb_value *v, bb_value *tmp)
{
    uint16_t t;
    void *p;
    if (!(v->type & BB_REF)) return v;
    t = BB_BASETYPE(v->type);
    p = v->u.p;
    if (v->type & BB_ARRAY) {
        *tmp = bb_v_make((uint16_t)(BB_ARRAY | t));
        tmp->u.a = *(bb_array **)p;
        return tmp;
    }
    if (t == BB_VARIANT) return bb_v_deref((const bb_value *)p, tmp);
    if (t == BB_UDT) bb_raise(13, NULL);
    *tmp = bb_v_make(t);
    switch (t) {
    case BB_INTEGER: case BB_BOOLEAN: tmp->u.i = *(bb_int *)p; break;
    case BB_LONG: tmp->u.l = *(bb_long *)p; break;
    case BB_SINGLE: tmp->u.f = *(bb_single *)p; break;
    case BB_DOUBLE: case BB_DATE: tmp->u.d = *(bb_double *)p; break;
    case BB_CURRENCY: tmp->u.c = *(bb_cur *)p; break;
    case BB_BYTE: tmp->u.by = *(bb_byte *)p; break;
    case BB_STRING: tmp->u.s = *(bb_str **)p; break;
    case BB_OBJECT: tmp->u.o = *(bb_obj **)p; break;
    default: bb_raise(13, NULL);
    }
    return tmp;
}

void bb_v_store_ref(const bb_value *ref, const bb_value *val)
{
    uint16_t t = BB_BASETYPE(ref->type);
    void *p = ref->u.p;
    if (!(ref->type & BB_REF)) bb_raise(51, NULL);
    if (ref->type & BB_ARRAY) {
        bb_value tmp;
        const bb_value *v = bb_v_deref(val, &tmp);
        if (!(v->type & BB_ARRAY)) bb_raise(13, NULL);
        bb_arr_assign((bb_array **)p, v->u.a);
        return;
    }
    switch (t) {
    case BB_VARIANT: bb_v_assign((bb_value *)p, val); break;
    case BB_INTEGER: *(bb_int *)p = bb_v_to_int(val); break;
    case BB_BOOLEAN: *(bb_bool *)p = bb_v_to_bool(val); break;
    case BB_LONG: *(bb_long *)p = bb_v_to_long(val); break;
    case BB_SINGLE: *(bb_single *)p = bb_v_to_single(val); break;
    case BB_DOUBLE: *(bb_double *)p = bb_v_to_double(val); break;
    case BB_DATE: *(bb_date *)p = bb_v_to_date(val); break;
    case BB_CURRENCY: *(bb_cur *)p = bb_v_to_cur(val); break;
    case BB_BYTE: *(bb_byte *)p = bb_v_to_byte(val); break;
    case BB_STRING: bb_str_set((bb_str **)p, bb_v_to_str(val)); break;
    case BB_OBJECT: bb_obj_set((bb_obj **)p, bb_v_to_obj(val)); break;
    default: bb_raise(13, NULL);
    }
}

/* ---- conversions ---- */

#define DEREF(v) bb_value tmp_; v = bb_v_deref(v, &tmp_)

static double num_of(const bb_value *v)
{
    switch (v->type) {
    case BB_EMPTY: return 0;
    case BB_NULL: bb_raise(94, NULL);
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_LONG: return v->u.l;
    case BB_SINGLE: return v->u.f;
    case BB_DOUBLE: case BB_DATE: return v->u.d;
    case BB_CURRENCY: return (double)v->u.c / 10000.0;
    case BB_BYTE: return v->u.by;
    case BB_STRING: return bb_str_to_double(v->u.s);
    default: bb_raise(13, NULL);
    }
    return 0;
}

bb_int bb_v_to_int(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_BYTE: return v->u.by;
    case BB_LONG: if (v->u.l < -32768 || v->u.l > 32767) bb_overflow(); return (bb_int)v->u.l;
    case BB_STRING: if (bb_str_len(v->u.s) && (v->u.s->data[0] | 32) == 't') return bb_str_to_bool(v->u.s);
                    if (bb_str_len(v->u.s) && (v->u.s->data[0] | 32) == 'f') return bb_str_to_bool(v->u.s);
                    /* fallthrough */
    default: return bb_cint(num_of(v));
    }
}

bb_long bb_v_to_long(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_BYTE: return v->u.by;
    case BB_LONG: return v->u.l;
    case BB_STRING: if (bb_str_len(v->u.s) && ((v->u.s->data[0] | 32) == 't' || (v->u.s->data[0] | 32) == 'f'))
                        return bb_str_to_bool(v->u.s);
                    /* fallthrough */
    default: return bb_clng(num_of(v));
    }
}

bb_single bb_v_to_single(const bb_value *v)
{
    DEREF(v);
    if (v->type == BB_SINGLE) return v->u.f;
    return bb_csng(num_of(v));
}

bb_double bb_v_to_double(const bb_value *v)
{
    DEREF(v);
    if (v->type == BB_DOUBLE) return v->u.d;
    if (v->type == BB_STRING && bb_str_len(v->u.s) &&
        ((v->u.s->data[0] | 32) == 't' || (v->u.s->data[0] | 32) == 'f'))
        return bb_str_to_bool(v->u.s);
    return num_of(v);
}

bb_cur bb_v_to_cur(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_CURRENCY: return v->u.c;
    case BB_INTEGER: case BB_BOOLEAN: return (bb_cur)v->u.i * 10000;
    case BB_LONG: return (bb_cur)v->u.l * 10000;
    case BB_BYTE: return (bb_cur)v->u.by * 10000;
    default: return bb_ccur(num_of(v));
    }
}

bb_date bb_v_to_date(const bb_value *v)
{
    DEREF(v);
    if (v->type == BB_DATE) return v->u.dt;
    if (v->type == BB_STRING) return bb_str_to_date(v->u.s);
    return num_of(v);
}

bb_bool bb_v_to_bool(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_BOOLEAN: return v->u.b;
    case BB_EMPTY: return BB_FALSE;
    case BB_STRING: return bb_str_to_bool(v->u.s);
    case BB_INTEGER: return v->u.i ? BB_TRUE : BB_FALSE;
    case BB_LONG: return v->u.l ? BB_TRUE : BB_FALSE;
    case BB_CURRENCY: return v->u.c ? BB_TRUE : BB_FALSE;
    default: return num_of(v) != 0 ? BB_TRUE : BB_FALSE;
    }
}

bb_byte bb_v_to_byte(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_BYTE: return v->u.by;
    case BB_INTEGER: case BB_BOOLEAN: if (v->u.i < 0 || v->u.i > 255) bb_overflow(); return (bb_byte)v->u.i;
    case BB_LONG: if (v->u.l < 0 || v->u.l > 255) bb_overflow(); return (bb_byte)v->u.l;
    default: return bb_cbyte(num_of(v));
    }
}

bb_str *bb_v_to_str(const bb_value *v)
{
    DEREF(v);
    switch (v->type) {
    case BB_EMPTY: return NULL;
    case BB_NULL: bb_raise(94, NULL);
    case BB_STRING: return bb_str_retain(v->u.s);
    case BB_INTEGER: return bb_str_from_long(v->u.i);
    case BB_LONG: return bb_str_from_long(v->u.l);
    case BB_BYTE: return bb_str_from_long(v->u.by);
    case BB_BOOLEAN: return bb_str_from_bool(v->u.b);
    case BB_SINGLE: return bb_str_from_single(v->u.f);
    case BB_DOUBLE: return bb_str_from_double(v->u.d);
    case BB_CURRENCY: return bb_str_from_cur(v->u.c);
    case BB_DATE: return bb_str_from_date(v->u.dt);
    case BB_ERROR: {
        bb_str *n = bb_str_from_long(v->u.l), *p = bb_str_from_c("Error "), *r = bb_str_concat(p, n);
        bb_str_release(n); bb_str_release(p);
        return r;
    }
    case BB_OBJECT: {
        /* default member */
        bb_value r = bb_invoke(v->u.o, "", BB_INV_GET, 0, NULL);
        bb_str *s = bb_v_to_str(&r);
        bb_v_release(&r);
        return s;
    }
    default: bb_raise(13, NULL);
    }
    return NULL;
}

bb_obj *bb_v_to_obj(const bb_value *v)
{
    DEREF(v);
    if (v->type == BB_OBJECT) return bb_obj_retain(v->u.o);
    bb_raise(424, NULL);
    return NULL;
}

bb_value bb_v_convert(const bb_value *v, int t)
{
    switch (t) {
    case BB_INTEGER: return bb_v_int(bb_v_to_int(v));
    case BB_LONG: return bb_v_long(bb_v_to_long(v));
    case BB_SINGLE: return bb_v_single(bb_v_to_single(v));
    case BB_DOUBLE: return bb_v_double(bb_v_to_double(v));
    case BB_CURRENCY: return bb_v_cur(bb_v_to_cur(v));
    case BB_DATE: return bb_v_date(bb_v_to_date(v));
    case BB_BOOLEAN: return bb_v_bool(bb_v_to_bool(v));
    case BB_BYTE: return bb_v_byte(bb_v_to_byte(v));
    case BB_STRING: return bb_v_str(bb_v_to_str(v));
    case BB_OBJECT: return bb_v_obj(bb_v_to_obj(v));
    default: return bb_v_dup(v);
    }
}

int bb_v_truth(const bb_value *v)
{
    DEREF(v);
    if (v->type == BB_NULL) return 0;
    return bb_v_to_bool(v) != 0;
}

int bb_v_is_numeric(const bb_value *v)
{
    double d;
    DEREF(v);
    switch (v->type) {
    case BB_EMPTY: case BB_INTEGER: case BB_LONG: case BB_SINGLE: case BB_DOUBLE:
    case BB_CURRENCY: case BB_BOOLEAN: case BB_BYTE: return 1;
    case BB_STRING: return bb_parse_number(bb_str_ptr(v->u.s), bb_str_len(v->u.s), &d);
    default: return 0;
    }
}

/* ---- arithmetic ---- */

/* numeric kinds, in widening order */
enum { K_BYTE, K_INT, K_LONG, K_SINGLE, K_DOUBLE, K_CUR, K_DATE, K_STR, K_NULL, K_EMPTY };

static int kind_of(const bb_value *v)
{
    switch (v->type) {
    case BB_EMPTY: return K_EMPTY;
    case BB_NULL: return K_NULL;
    case BB_BYTE: return K_BYTE;
    case BB_INTEGER: case BB_BOOLEAN: return K_INT;
    case BB_LONG: return K_LONG;
    case BB_SINGLE: return K_SINGLE;
    case BB_DOUBLE: return K_DOUBLE;
    case BB_CURRENCY: return K_CUR;
    case BB_DATE: return K_DATE;
    case BB_STRING: return K_STR;
    case BB_OBJECT: {
        return -1;
    }
    default: bb_raise(13, NULL);
    }
    return 0;
}

static int result_kind(int ka, int kb)
{
    if (ka == K_EMPTY) ka = K_INT;
    if (kb == K_EMPTY) kb = K_INT;
    if (ka == K_STR) ka = K_DOUBLE;
    if (kb == K_STR) kb = K_DOUBLE;
    if (ka == K_DATE || kb == K_DATE) return K_DATE;
    if (ka == K_CUR || kb == K_CUR) {
        int o = ka == K_CUR ? kb : ka;
        return (o == K_SINGLE || o == K_DOUBLE) ? K_DOUBLE : K_CUR;
    }
    if ((ka == K_SINGLE && kb == K_LONG) || (kb == K_SINGLE && ka == K_LONG)) return K_DOUBLE;
    return ka > kb ? ka : kb;
}

static bb_value make_int_kind(int64_t r, int k)
{
    if (k == K_BYTE && r >= 0 && r <= 255) return bb_v_byte((bb_byte)r);
    if (k <= K_INT && r >= -32768 && r <= 32767) return bb_v_int((bb_int)r);
    if (r >= INT32_MIN && r <= INT32_MAX) return bb_v_long((bb_long)r);
    return bb_v_double((double)r);
}

static int64_t ival(const bb_value *v)
{
    switch (v->type) {
    case BB_BYTE: return v->u.by;
    case BB_INTEGER: case BB_BOOLEAN: return v->u.i;
    case BB_LONG: return v->u.l;
    default: return 0;
    }
}

/* resolve an object operand to its default value */
static const bb_value *defval(const bb_value *v, bb_value *hold)
{
    if (v->type == BB_OBJECT) {
        *hold = bb_invoke(v->u.o, "", BB_INV_GET, 0, NULL);
        return hold;
    }
    return v;
}

enum { OP_ADD, OP_SUB, OP_MUL };

static bb_value arith(int op, const bb_value *a, const bb_value *b)
{
    bb_value ta, tb, ha = bb_v_empty(), hb = bb_v_empty(), r;
    int ka, kb, k;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    a = defval(a, &ha); b = defval(b, &hb);
    ka = kind_of(a); kb = kind_of(b);
    if (ka == K_NULL || kb == K_NULL) { r = bb_v_null(); goto out; }
    if (op == OP_ADD && ka == K_STR && (kb == K_STR || kb == K_EMPTY)) { r = bb_v_str(bb_str_concat(a->u.s, NULL)); if (kb == K_STR) { bb_str_release(r.u.s); r.u.s = bb_str_concat(a->u.s, b->u.s); } goto out; }
    if (op == OP_ADD && kb == K_STR && ka == K_EMPTY) { r = bb_v_str(bb_str_retain(b->u.s)); goto out; }
    k = result_kind(ka, kb);
    if (op == OP_SUB && ka == K_DATE && kb == K_DATE) k = K_DOUBLE;
    if (op == OP_MUL && k == K_DATE) k = K_DOUBLE;
    switch (k) {
    case K_BYTE: case K_INT: case K_LONG: {
        int64_t x = ival(a), y = ival(b), z = op == OP_ADD ? x + y : op == OP_SUB ? x - y : x * y;
        r = make_int_kind(z, k);
        if (k == K_BYTE && r.type != BB_BYTE && z >= -32768 && z <= 32767) r = bb_v_int((bb_int)z);
        break;
    }
    case K_SINGLE: {
        double x = num_of(a), y = num_of(b), z = op == OP_ADD ? x + y : op == OP_SUB ? x - y : x * y;
        if (fabs(z) > 3.402823466e38) r = bb_v_double(bb_chk_double(z));
        else r = bb_v_single((bb_single)z);
        break;
    }
    case K_CUR: {
        bb_cur x = bb_v_to_cur(a), y = bb_v_to_cur(b);
        r = bb_v_cur(op == OP_ADD ? bb_cur_add(x, y) : op == OP_SUB ? bb_cur_sub(x, y) : bb_cur_mul(x, y));
        break;
    }
    case K_DATE: {
        double x = num_of(a), y = num_of(b);
        r = bb_v_date(bb_chk_double(op == OP_ADD ? x + y : x - y));
        break;
    }
    default: {
        double x = num_of(a), y = num_of(b);
        r = bb_v_double(bb_chk_double(op == OP_ADD ? x + y : op == OP_SUB ? x - y : x * y));
    }
    }
out:
    bb_v_release(&ha); bb_v_release(&hb);
    return r;
}

bb_value bb_v_add(const bb_value *a, const bb_value *b) { return arith(OP_ADD, a, b); }
bb_value bb_v_sub(const bb_value *a, const bb_value *b) { return arith(OP_SUB, a, b); }
bb_value bb_v_mul(const bb_value *a, const bb_value *b) { return arith(OP_MUL, a, b); }

static int is_null(const bb_value *v)
{
    bb_value t;
    return bb_v_deref(v, &t)->type == BB_NULL;
}

bb_value bb_v_div(const bb_value *a, const bb_value *b)
{
    bb_value ta, tb;
    int ka, kb;
    double r;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    if (a->type == BB_NULL || b->type == BB_NULL) return bb_v_null();
    ka = kind_of(a); kb = kind_of(b);
    r = bb_fdiv(bb_v_to_double(a), bb_v_to_double(b));
    if ((ka == K_SINGLE && (kb == K_SINGLE || kb <= K_INT)) || (kb == K_SINGLE && ka <= K_INT))
        return bb_v_single(bb_csng(r));
    return bb_v_double(r);
}

static int small_int(int k) { return k == K_BYTE || k == K_INT || k == K_EMPTY; }

bb_value bb_v_idiv(const bb_value *a, const bb_value *b)
{
    bb_value ta, tb;
    bb_long x, y, r;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    if (a->type == BB_NULL || b->type == BB_NULL) return bb_v_null();
    x = bb_v_to_long(a); y = bb_v_to_long(b);
    r = bb_idiv_l(x, y);
    if (a->type == BB_BYTE && b->type == BB_BYTE) return bb_v_byte((bb_byte)r);
    if (small_int(kind_of(a)) && small_int(kind_of(b))) return make_int_kind(r, K_INT);
    return bb_v_long(r);
}

bb_value bb_v_mod(const bb_value *a, const bb_value *b)
{
    bb_value ta, tb;
    bb_long x, y, r;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    if (a->type == BB_NULL || b->type == BB_NULL) return bb_v_null();
    x = bb_v_to_long(a); y = bb_v_to_long(b);
    r = bb_mod_l(x, y);
    if (a->type == BB_BYTE && b->type == BB_BYTE) return bb_v_byte((bb_byte)r);
    if (small_int(kind_of(a)) && small_int(kind_of(b))) return bb_v_int((bb_int)r);
    return bb_v_long(r);
}

bb_value bb_v_pow(const bb_value *a, const bb_value *b)
{
    if (is_null(a) || is_null(b)) return bb_v_null();
    return bb_v_double(bb_pow(bb_v_to_double(a), bb_v_to_double(b)));
}

bb_value bb_v_neg(const bb_value *a)
{
    bb_value ta;
    a = bb_v_deref(a, &ta);
    switch (a->type) {
    case BB_NULL: return bb_v_null();
    case BB_EMPTY: return bb_v_int(0);
    case BB_BYTE: return bb_v_int((bb_int)-a->u.by);
    case BB_INTEGER: case BB_BOOLEAN: return a->u.i == -32768 ? bb_v_long(32768) : bb_v_int((bb_int)-a->u.i);
    case BB_LONG: return a->u.l == INT32_MIN ? bb_v_double(2147483648.0) : bb_v_long(-a->u.l);
    case BB_SINGLE: return bb_v_single(-a->u.f);
    case BB_CURRENCY: return bb_v_cur(bb_cur_sub(0, a->u.c));
    case BB_DATE: return bb_v_date(-a->u.dt);
    default: return bb_v_double(-bb_v_to_double(a));
    }
}

bb_value bb_v_cat(const bb_value *a, const bb_value *b)
{
    bb_value ta, tb;
    bb_str *x, *y, *r;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    if (a->type == BB_NULL && b->type == BB_NULL) return bb_v_null();
    x = a->type == BB_NULL ? NULL : bb_v_to_str(a);
    y = b->type == BB_NULL ? NULL : bb_v_to_str(b);
    r = bb_str_concat(x, y);
    bb_str_release(x); bb_str_release(y);
    return bb_v_str(r);
}

/* ---- logical ---- */

static int64_t logic_int(const bb_value *v) { return bb_v_to_long(v); }

static bb_value logic_result(int64_t r, const bb_value *a, const bb_value *b)
{
    int ka = kind_of(a), kb = b ? kind_of(b) : ka;
    if (a->type == BB_BOOLEAN && (!b || b->type == BB_BOOLEAN)) return bb_v_bool(r != 0);
    if (a->type == BB_BYTE && (!b || b->type == BB_BYTE)) return bb_v_byte((bb_byte)r);
    if ((small_int(ka) || a->type == BB_BOOLEAN) && (small_int(kb) || (b && b->type == BB_BOOLEAN)))
        return bb_v_int((bb_int)r);
    return bb_v_long((bb_long)r);
}

bb_value bb_v_not(const bb_value *a)
{
    bb_value ta;
    a = bb_v_deref(a, &ta);
    if (a->type == BB_NULL) return bb_v_null();
    if (a->type == BB_BYTE) return bb_v_byte((bb_byte)~a->u.by);
    return logic_result(~logic_int(a), a, NULL);
}

enum { L_AND, L_OR, L_XOR, L_EQV, L_IMP };

static bb_value logic2(int op, const bb_value *a, const bb_value *b)
{
    bb_value ta, tb;
    int64_t x, y, r = 0;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    if (a->type == BB_NULL || b->type == BB_NULL) {
        const bb_value *o = a->type == BB_NULL ? b : a;
        int onull = o->type == BB_NULL;
        int64_t ov = onull ? 0 : logic_int(o);
        if (op == L_AND && !onull && ov == 0) return logic_result(0, o, o);
        if (op == L_OR && !onull && ov == -1) return logic_result(-1, o, o);
        if (op == L_IMP && a->type == BB_NULL && !onull && ov == -1) return logic_result(-1, o, o);
        if (op == L_IMP && b->type == BB_NULL && !onull && ov == 0) return logic_result(-1, o, o);
        return bb_v_null();
    }
    x = logic_int(a); y = logic_int(b);
    switch (op) {
    case L_AND: r = x & y; break;
    case L_OR: r = x | y; break;
    case L_XOR: r = x ^ y; break;
    case L_EQV: r = ~(x ^ y); break;
    case L_IMP: r = (~x) | y; break;
    }
    return logic_result(r, a, b);
}

bb_value bb_v_and(const bb_value *a, const bb_value *b) { return logic2(L_AND, a, b); }
bb_value bb_v_or(const bb_value *a, const bb_value *b) { return logic2(L_OR, a, b); }
bb_value bb_v_xor(const bb_value *a, const bb_value *b) { return logic2(L_XOR, a, b); }
bb_value bb_v_eqv(const bb_value *a, const bb_value *b) { return logic2(L_EQV, a, b); }
bb_value bb_v_imp(const bb_value *a, const bb_value *b) { return logic2(L_IMP, a, b); }

/* ---- comparison ---- */

static int is_num_kind(int k) { return k <= K_DATE || k == K_EMPTY; }

int bb_v_compare(const bb_value *a, const bb_value *b, int text)
{
    bb_value ta, tb, ha = bb_v_empty(), hb = bb_v_empty();
    int ka, kb, r;
    a = bb_v_deref(a, &ta); b = bb_v_deref(b, &tb);
    a = defval(a, &ha); b = defval(b, &hb);
    ka = kind_of(a); kb = kind_of(b);
    if (ka == K_NULL || kb == K_NULL) r = 2;
    else if (ka == K_STR && kb == K_STR) r = bb_str_cmp(a->u.s, b->u.s, text);
    else if (ka == K_STR && kb == K_EMPTY) r = bb_str_cmp(a->u.s, NULL, text);
    else if (kb == K_STR && ka == K_EMPTY) r = bb_str_cmp(NULL, b->u.s, text);
    else if (ka == K_STR) r = 1;        /* numbers sort before strings */
    else if (kb == K_STR) r = -1;
    else if (is_num_kind(ka) && is_num_kind(kb)) {
        if (ka <= K_LONG || ka == K_EMPTY) {
            if (kb <= K_LONG || kb == K_EMPTY) {
                int64_t x = ka == K_EMPTY ? 0 : ival(a), y = kb == K_EMPTY ? 0 : ival(b);
                r = x < y ? -1 : x > y;
                goto out;
            }
        }
        if (ka == K_CUR && kb == K_CUR) { r = a->u.c < b->u.c ? -1 : a->u.c > b->u.c; goto out; }
        {
            double x = num_of(a), y = num_of(b);
            /* compare Single with Single precision */
            if (ka == K_SINGLE && kb != K_SINGLE && kb != K_DOUBLE) y = (float)y;
            r = x < y ? -1 : x > y;
        }
    } else { bb_v_release(&ha); bb_v_release(&hb); bb_raise(13, NULL); }
out:
    bb_v_release(&ha); bb_v_release(&hb);
    if (r < -1) r = -1;
    if (r > 1 && r != 2) r = 1;
    return r;
}

bb_value bb_v_cmp(int op, const bb_value *a, const bb_value *b, int text)
{
    int c = bb_v_compare(a, b, text), r = 0;
    if (c == 2) return bb_v_null();
    switch (op) {
    case BB_CMP_EQ: r = c == 0; break;
    case BB_CMP_NE: r = c != 0; break;
    case BB_CMP_LT: r = c < 0; break;
    case BB_CMP_GT: r = c > 0; break;
    case BB_CMP_LE: r = c <= 0; break;
    case BB_CMP_GE: r = c >= 0; break;
    }
    return bb_v_bool(r);
}
