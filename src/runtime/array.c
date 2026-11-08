/* array.c - arrays and user-defined types */
#include "boing.h"
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

int32_t bb_type_size(int t)
{
    switch (t) {
    case BB_BYTE: return 1;
    case BB_INTEGER: case BB_BOOLEAN: return 2;
    case BB_LONG: case BB_SINGLE: return 4;
    case BB_DOUBLE: case BB_DATE: case BB_CURRENCY: return 8;
    case BB_STRING: return (int32_t)sizeof(bb_str *);
    case BB_OBJECT: return (int32_t)sizeof(bb_obj *);
    case BB_VARIANT: return (int32_t)sizeof(bb_value);
    default:
        if (t & BB_ARRAY) return (int32_t)sizeof(bb_array *);
        return 0;
    }
}

static int32_t esize_of(int etype, const bb_udt_desc *udt)
{
    return etype == BB_UDT ? udt->size : bb_type_size(etype);
}

void bb_elem_init(int etype, const bb_udt_desc *udt, void *p)
{
    if (etype == BB_UDT) bb_udt_init(udt, p);
    else memset(p, 0, (size_t)bb_type_size(etype));
}

void bb_elem_release(int etype, const bb_udt_desc *udt, void *p)
{
    switch (etype) {
    case BB_STRING: bb_str_set((bb_str **)p, NULL); break;
    case BB_OBJECT: bb_obj_set((bb_obj **)p, NULL); break;
    case BB_VARIANT: bb_v_release((bb_value *)p); break;
    case BB_UDT: bb_udt_clear(udt, p); break;
    default:
        if (etype & BB_ARRAY) { bb_arr_free(*(bb_array **)p); *(bb_array **)p = NULL; }
    }
}

void bb_elem_copy(int etype, const bb_udt_desc *udt, void *dst, const void *src)
{
    switch (etype) {
    case BB_STRING: bb_str_assign((bb_str **)dst, *(bb_str *const *)src); break;
    case BB_OBJECT: bb_obj_assign((bb_obj **)dst, *(bb_obj *const *)src); break;
    case BB_VARIANT: bb_v_assign((bb_value *)dst, (const bb_value *)src); break;
    case BB_UDT: bb_udt_copy(udt, dst, src); break;
    default:
        if (etype & BB_ARRAY) bb_arr_assign((bb_array **)dst, *(bb_array *const *)src);
        else memcpy(dst, src, (size_t)bb_type_size(etype));
    }
}

bb_value bb_elem_load(int etype, const void *p)
{
    switch (etype) {
    case BB_BYTE: return bb_v_byte(*(const bb_byte *)p);
    case BB_INTEGER: return bb_v_int(*(const bb_int *)p);
    case BB_BOOLEAN: { bb_value v = bb_v_make(BB_BOOLEAN); v.u.b = *(const bb_bool *)p; return v; }
    case BB_LONG: return bb_v_long(*(const bb_long *)p);
    case BB_SINGLE: return bb_v_single(*(const bb_single *)p);
    case BB_DOUBLE: return bb_v_double(*(const bb_double *)p);
    case BB_DATE: return bb_v_date(*(const bb_date *)p);
    case BB_CURRENCY: return bb_v_cur(*(const bb_cur *)p);
    case BB_STRING: return bb_v_str(bb_str_retain(*(bb_str *const *)p));
    case BB_OBJECT: return bb_v_obj(bb_obj_retain(*(bb_obj *const *)p));
    case BB_VARIANT: return bb_v_dup((const bb_value *)p);
    default:
        if (etype & BB_ARRAY) {
            bb_array *a = *(bb_array *const *)p;
            bb_value v = bb_v_make((uint16_t)etype);
            v.u.a = a ? bb_arr_copy(a) : NULL;
            return v;
        }
    }
    bb_raise(13, NULL);
    return bb_v_empty();
}

void bb_elem_store(int etype, void *p, const bb_value *v)
{
    bb_value ref = bb_v_ref((uint16_t)etype, p);
    bb_v_store_ref(&ref, v);
}

static void init_range(bb_array *a, int32_t from, int32_t to)
{
    int32_t i;
    if (a->etype == BB_UDT) {
        for (i = from; i < to; i++) bb_udt_init(a->udt, (char *)a->data + (size_t)i * a->esize);
    } else {
        memset((char *)a->data + (size_t)from * a->esize, 0, (size_t)(to - from) * a->esize);
    }
}

static int needs_release(int etype)
{
    return etype == BB_STRING || etype == BB_OBJECT || etype == BB_VARIANT || etype == BB_UDT || (etype & BB_ARRAY);
}

static void release_range(bb_array *a, int32_t from, int32_t to)
{
    int32_t i;
    if (!needs_release(a->etype)) return;
    for (i = from; i < to; i++) bb_elem_release(a->etype, a->udt, (char *)a->data + (size_t)i * a->esize);
}

bb_array *bb_arr_new(int etype, const bb_udt_desc *udt, int ndims, const int32_t *lb, const int32_t *ub)
{
    bb_array *a;
    int i;
    int64_t total = 1;
    if (ndims < 1 || ndims > BB_MAXDIMS) bb_raise(9, NULL);
    a = (bb_array *)bb_alloc(sizeof(bb_array));
    a->etype = (uint16_t)etype;
    a->udt = udt;
    a->esize = esize_of(etype, udt);
    a->ndims = (uint16_t)ndims;
    for (i = 0; i < ndims; i++) {
        int64_t c = (int64_t)ub[i] - lb[i] + 1;
        if (c < 0) { free(a); bb_raise(9, NULL); }
        a->dims[i].lbound = lb[i];
        a->dims[i].count = (int32_t)c;
        total *= c;
        if (total > 0x7fffffff) { free(a); bb_raise(7, NULL); }
    }
    a->count = (int32_t)total;
    a->data = total ? malloc((size_t)total * (size_t)a->esize) : NULL;
    if (total && !a->data) { free(a); bb_raise(7, NULL); }
    init_range(a, 0, a->count);
    return a;
}

bb_array *bb_arr_new1(int etype, int32_t lb, int32_t ub)
{
    return bb_arr_new(etype, NULL, 1, &lb, &ub);
}

void bb_arr_free(bb_array *a)
{
    if (!a) return;
    release_range(a, 0, a->count);
    free(a->data);
    free(a);
}

bb_array *bb_arr_copy(const bb_array *src)
{
    bb_array *a;
    int32_t i;
    if (!src) return NULL;
    a = (bb_array *)bb_alloc(sizeof(bb_array));
    *a = *src;
    a->fixed = 0;
    a->locked = 0;
    a->data = src->count ? malloc((size_t)src->count * (size_t)src->esize) : NULL;
    if (!needs_release(src->etype)) {
        if (src->count) memcpy(a->data, src->data, (size_t)src->count * (size_t)src->esize);
        return a;
    }
    init_range(a, 0, a->count);
    for (i = 0; i < a->count; i++)
        bb_elem_copy(a->etype, a->udt, (char *)a->data + (size_t)i * a->esize,
                     (const char *)src->data + (size_t)i * a->esize);
    return a;
}

void bb_arr_assign(bb_array **dst, const bb_array *src)
{
    bb_array *n;
    if (*dst == src) return;
    if (*dst && (*dst)->fixed) bb_raise(10, NULL);
    n = bb_arr_copy(src);
    bb_arr_free(*dst);
    *dst = n;
}

void bb_arr_redim(bb_array **pa, int etype, const bb_udt_desc *udt, int ndims,
                  const int32_t *lb, const int32_t *ub, int preserve)
{
    bb_array *old = *pa, *n;
    int i;
    if (old && (old->fixed || old->locked)) bb_raise(10, NULL);
    if (!preserve || !old) {
        n = bb_arr_new(etype, udt, ndims, lb, ub);
        *pa = n;
        bb_arr_free(old);
        return;
    }
    /* Preserve: only the last dimension may change */
    if (old->ndims != ndims) bb_raise(9, NULL);
    for (i = 0; i < ndims - 1; i++)
        if (old->dims[i].lbound != lb[i] || old->dims[i].count != ub[i] - lb[i] + 1) bb_raise(9, NULL);
    if (old->dims[ndims - 1].lbound != lb[ndims - 1]) bb_raise(9, NULL);
    {
        int64_t c = (int64_t)ub[ndims - 1] - lb[ndims - 1] + 1, total;
        int32_t oldcount = old->count;
        if (c < 0) bb_raise(9, NULL);
        total = (oldcount / (old->dims[ndims - 1].count ? old->dims[ndims - 1].count : 1)) * c;
        if (ndims > 1 && old->dims[ndims - 1].count == 0) {
            total = c;
            for (i = 0; i < ndims - 1; i++) total *= old->dims[i].count;
        }
        if (total < oldcount) release_range(old, (int32_t)total, oldcount);
        old->data = realloc(old->data, (size_t)(total ? total : 1) * (size_t)old->esize);
        if (!old->data) bb_raise(7, NULL);
        old->count = (int32_t)total;
        old->dims[ndims - 1].count = (int32_t)c;
        if (total > oldcount) init_range(old, oldcount, (int32_t)total);
    }
}

void bb_arr_clear_elems(bb_array *a)
{
    if (!a) return;
    release_range(a, 0, a->count);
    init_range(a, 0, a->count);
}

void bb_arr_erase(bb_array **pa)
{
    bb_array *a = *pa;
    if (!a) return;
    if (a->locked) bb_raise(10, NULL);
    if (a->fixed) { bb_arr_clear_elems(a); return; }
    bb_arr_free(a);
    *pa = NULL;
}

void *bb_arr_elem(bb_array *a, int n, const int32_t *idx)
{
    int i;
    size_t off = 0, stride = 1;
    if (!a || a->ndims != n) bb_raise(9, NULL);
    for (i = 0; i < n; i++) {
        int32_t k = idx[i] - a->dims[i].lbound;
        if (k < 0 || k >= a->dims[i].count) bb_raise(9, NULL);
        off += (size_t)k * stride;
        stride *= (size_t)a->dims[i].count;
    }
    return (char *)a->data + off * (size_t)a->esize;
}

bb_long bb_arr_lbound(const bb_array *a, int dim)
{
    if (!a || dim < 1 || dim > a->ndims) bb_raise(9, NULL);
    return a->dims[dim - 1].lbound;
}

bb_long bb_arr_ubound(const bb_array *a, int dim)
{
    if (!a || dim < 1 || dim > a->ndims) bb_raise(9, NULL);
    return a->dims[dim - 1].lbound + a->dims[dim - 1].count - 1;
}

/* ---- UDTs ---- */

void bb_udt_init(const bb_udt_desc *d, void *p)
{
    int32_t i;
    memset(p, 0, (size_t)d->size);
    for (i = 0; i < d->nfields; i++) {
        const bb_field *f = &d->fields[i];
        char *q = (char *)p + f->offset;
        if (f->type == BB_UDT) bb_udt_init(f->udt, q);
        else if ((f->type & BB_ARRAY) && f->ndims > 0) {
            bb_array *a = bb_arr_new(BB_BASETYPE(f->type), f->udt, f->ndims, f->lb, f->ub);
            a->fixed = 1;
            *(bb_array **)q = a;
        } else if (f->type == BB_STRING && f->fixlen) {
            *(bb_str **)q = bb_str_fixlen(NULL, f->fixlen);
        }
    }
}

void bb_udt_clear(const bb_udt_desc *d, void *p)
{
    int32_t i;
    for (i = 0; i < d->nfields; i++) {
        const bb_field *f = &d->fields[i];
        char *q = (char *)p + f->offset;
        if (f->type & BB_ARRAY) { bb_arr_free(*(bb_array **)q); *(bb_array **)q = NULL; }
        else bb_elem_release(f->type, f->udt, q);
    }
}

void bb_udt_copy(const bb_udt_desc *d, void *dst, const void *src)
{
    int32_t i;
    if (dst == src) return;
    for (i = 0; i < d->nfields; i++) {
        const bb_field *f = &d->fields[i];
        char *q = (char *)dst + f->offset;
        const char *s = (const char *)src + f->offset;
        if (f->type & BB_ARRAY) {
            bb_array *n = bb_arr_copy(*(bb_array *const *)s);
            if (n && f->ndims > 0) n->fixed = 1;
            bb_arr_free(*(bb_array **)q);
            *(bb_array **)q = n;
        } else bb_elem_copy(f->type, f->udt, q, s);
    }
}

bb_value bb_v_udt_new(const bb_udt_desc *d)
{
    bb_value v = bb_v_make(BB_UDT);
    bb_udtbox *b = (bb_udtbox *)bb_alloc(offsetof(bb_udtbox, data) + (size_t)(d->size ? d->size : 1));
    b->desc = d;
    bb_udt_init(d, b->data);
    v.u.p = b;
    return v;
}

void bb_subscript_error(void) { bb_raise(9, NULL); }
