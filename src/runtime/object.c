/* object.c - objects, late-bound dispatch, events, For Each, Collection */
#include "boing.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>

bb_obj *bb_obj_new(const bb_class *cls)
{
    bb_obj *o = (bb_obj *)bb_alloc(cls->size < sizeof(bb_obj) ? sizeof(bb_obj) : cls->size);
    o->cls = cls;
    o->ref = 1;
    return o;
}

void bb_obj_free_(bb_obj *o)
{
    bb_sink *s, *n;
    o->ref = 1;     /* keep alive while terminating */
    if (o->cls->terminate) o->cls->terminate(o);
    for (s = o->sinks; s; s = n) { n = s->next; free(s); }
    free(o);
}

int32_t bb_class_find_default(const bb_class *cls, const char *name)
{
    int32_t i;
    if (!name || !*name) return cls->nmembers ? BB_MEMBER_DEFAULT : BB_NOMEMBER;
    for (i = 0; i < cls->nmembers; i++)
        if (strcasecmp(cls->members[i].name, name) == 0) return cls->members[i].id;
    return BB_NOMEMBER;
}

int32_t bb_member_id(bb_obj *o, const char *name)
{
    int32_t id;
    bb_obj_check(o);
    id = o->cls->find ? o->cls->find(o->cls, name) : BB_NOMEMBER;
    if (id == BB_NOMEMBER) bb_raise(438, NULL);
    return id;
}

typedef struct { bb_cleanup c; bb_obj *o; bb_value *r; } invoke_guard;

static void invoke_unwind(void *ctx)
{
    invoke_guard *g = (invoke_guard *)ctx;
    bb_v_release(g->r);
    bb_obj_release(g->o);
}

bb_value bb_invoke_id(bb_obj *o, int32_t id, int kind, int argc, bb_value *argv)
{
    bb_value r = bb_v_empty();
    invoke_guard g;
    bb_obj_check(o);
    if (!o->cls->invoke) bb_raise(438, NULL);
    /* keep the object alive during the call; an error unwinding through here runs
       invoke_unwind (a cleanup entry costs far less than a setjmp frame) */
    bb_obj_retain(o);
    g.o = o;
    g.r = &r;
    g.c.fn = invoke_unwind;
    g.c.ctx = &g;
    g.c.prev = bb_cleanups;
    bb_cleanups = &g.c;
    o->cls->invoke(o, id, kind, argc, argv, &r);
    bb_cleanups = g.c.prev;
    bb_obj_release(o);
    return r;
}

bb_value bb_invoke_site(bb_obj *o, bb_site *s, const char *name, int kind, int argc, bb_value *argv)
{
    bb_obj_check(o);
    if (s->cls != o->cls) {
        s->id = bb_member_id(o, name);
        s->cls = o->cls;
    }
    return bb_invoke_id(o, s->id, kind, argc, argv);
}

/* a member of a variable declared As one of the built-in classes (Engine3D, Canvas, Audio), its
   id resolved by the compiler: called directly (no site lookup, no retain or cleanup entry: these
   classes never run BASIC code from a call); another class's object: by name, as late binding */
bb_value bb_invoke_rt(bb_obj *o, const bb_class *cls, int32_t id, const char *name, int kind, int argc, bb_value *argv)
{
    bb_obj_check(o);
    if (BB_LIKELY(o->cls == cls)) {
        bb_value r = bb_v_empty();
        cls->invoke(o, id, kind, argc, argv, &r);
        return r;
    }
    return bb_invoke(o, name, kind, argc, argv);
}

bb_value bb_v_invoke_site(const bb_value *v, bb_site *s, const char *name, int kind, int argc, bb_value *argv)
{
    bb_value t;
    v = bb_v_deref(v, &t);
    if (v->type != BB_OBJECT) bb_raise(424, NULL);
    return bb_invoke_site(v->u.o, s, name, kind, argc, argv);
}

bb_obj *bb_create_object(const bb_str *progid);    /* object_registry / canvas */
bb_value bb_createobject(bb_str *progid, bb_str *server)
{
    (void)server;
    return bb_v_obj(bb_create_object(progid));
}

bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv)
{
    return bb_invoke_id(o, bb_member_id(o, name), kind, argc, argv);
}

bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv)
{
    bb_value t;
    v = bb_v_deref(v, &t);
    if (v->type != BB_OBJECT) bb_raise(424, NULL);
    return bb_invoke(v->u.o, name, kind, argc, argv);
}

bb_value bb_get_prop(bb_obj *o, const char *name)
{
    return bb_invoke(o, name, BB_INV_GET, 0, NULL);
}

void bb_set_prop(bb_obj *o, const char *name, bb_value owned)
{
    bb_value r = bb_invoke(o, name, owned.type == BB_OBJECT ? BB_INV_SET : BB_INV_LET, 1, &owned);
    bb_v_release(&r);
    bb_v_release(&owned);
}

const void *bb_vtbl(bb_obj *o, const bb_class *iface)
{
    int32_t i;
    bb_obj_check(o);
    if (o->cls == iface) return o->cls->vtbl;
    for (i = 0; i < o->cls->nifaces; i++)
        if (o->cls->ifaces[i].iface == iface) return o->cls->ifaces[i].vtbl;
    bb_raise(13, NULL);
    return NULL;
}

int bb_obj_is(bb_obj *o, const bb_class *cls)
{
    int32_t i;
    if (!o) return 0;
    if (o->cls == cls) return 1;
    for (i = 0; i < o->cls->nifaces; i++)
        if (o->cls->ifaces[i].iface == cls) return 1;
    return 0;
}

bb_str *bb_typename_obj(bb_obj *o)
{
    return bb_str_from_c(o ? o->cls->name : "Nothing");
}

/* ---- events ---- */

bb_sink *bb_event_connect(bb_obj *src, void (*fire)(bb_sink *, int32_t, const char *, int, bb_value *),
                          void *ctx, int32_t tag)
{
    bb_sink *s, **pp;
    if (!src) return NULL;
    s = (bb_sink *)bb_alloc(sizeof(bb_sink));
    s->fire = fire;
    s->ctx = ctx;
    s->tag = tag;
    for (pp = &src->sinks; *pp; pp = &(*pp)->next) ;
    *pp = s;
    return s;
}

void bb_event_disconnect(bb_obj *src, bb_sink *s)
{
    bb_sink **pp;
    if (!src || !s) return;
    for (pp = &src->sinks; *pp; pp = &(*pp)->next)
        if (*pp == s) { *pp = s->next; free(s); return; }
}

void bb_event_raise(bb_obj *src, int32_t event, const char *name, int argc, bb_value *argv)
{
    bb_sink *s, *n;
    bb_errframe f;
    if (!src) return;
    bb_obj_retain(src);
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        for (s = src->sinks; s; s = n) {
            n = s->next;
            s->fire(s, event, name, argc, argv);
        }
        bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        bb_obj_release(src);
        bb_rethrow();
    }
    bb_obj_release(src);
}

/* ---- For Each ---- */

void bb_foreach_begin(bb_foreach *fe, const bb_value *src)
{
    bb_value t;
    const bb_value *v = bb_v_deref(src, &t);
    fe->state = bb_v_empty();
    fe->index = 0;
    if (v->type & BB_ARRAY) {
        fe->src = bb_v_make(v->type);
        fe->src.u.a = v->u.a;           /* borrowed: arrays are locked, not copied */
        fe->src.flags = 1;
        if (!v->u.a) bb_raise(92, NULL);
        v->u.a->locked++;
        return;
    }
    if (v->type != BB_OBJECT) bb_raise(v->type == BB_EMPTY ? 92 : 13, NULL);
    bb_obj_check(v->u.o);
    if (!v->u.o->cls->iterate) bb_raise(438, NULL);
    fe->src = bb_v_obj(bb_obj_retain(v->u.o));
}

int bb_foreach_next(bb_foreach *fe, bb_value *out)
{
    if (fe->src.type & BB_ARRAY) {
        bb_array *a = fe->src.u.a;
        if (fe->index >= a->count) return 0;
        *out = bb_elem_load(a->etype, (char *)a->data + (size_t)fe->index * a->esize);
        fe->index++;
        return 1;
    }
    if (fe->src.type == BB_OBJECT)
        return fe->src.u.o->cls->iterate(fe->src.u.o, &fe->state, out);
    return 0;
}

void bb_foreach_end(bb_foreach *fe)
{
    if (fe->src.type & BB_ARRAY) {
        if (fe->src.u.a) fe->src.u.a->locked--;
        fe->src = bb_v_empty();
    } else bb_v_release(&fe->src);
    bb_v_release(&fe->state);
}

/* ---- Collection ---- */

typedef struct citem { bb_value v; bb_str *key; } citem;
typedef struct coll {
    bb_obj hdr;
    citem *items;
    int32_t n, cap;
} coll;

enum { C_ITEM = 0, C_ADD, C_COUNT, C_REMOVE };
static const bb_member coll_members[] = {
    {"Item", C_ITEM, BB_INV_METHOD | BB_INV_GET},
    {"Add", C_ADD, BB_INV_METHOD},
    {"Count", C_COUNT, BB_INV_METHOD | BB_INV_GET},
    {"Remove", C_REMOVE, BB_INV_METHOD},
};

static int is_missing(const bb_value *v) { return v->type == BB_ERROR && (v->flags & BB_VF_MISSING); }

static int32_t coll_find_key(coll *c, bb_str *key)
{
    int32_t i;
    for (i = 0; i < c->n; i++)
        if (c->items[i].key && bb_str_cmp(c->items[i].key, key, 1) == 0) return i;
    return -1;
}

/* index argument (1-based number or key) -> 0-based position */
static int32_t coll_index(coll *c, const bb_value *arg)
{
    bb_value t;
    const bb_value *v = bb_v_deref(arg, &t);
    int32_t i;
    if (v->type == BB_STRING) {
        i = coll_find_key(c, v->u.s);
        if (i < 0) bb_raise(5, NULL);
        return i;
    }
    i = bb_v_to_long(v);
    if (i < 1 || i > c->n) bb_raise(9, NULL);
    return i - 1;
}

static void coll_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    coll *c = (coll *)self;
    (void)kind;
    switch (id) {
    case C_ITEM:
        if (argc != 1) bb_raise(450, NULL);
        bb_v_copy(ret, &c->items[coll_index(c, &argv[0])].v);
        break;
    case C_COUNT:
        if (argc != 0) bb_raise(450, NULL);
        *ret = bb_v_long(c->n);
        break;
    case C_ADD: {
        bb_str *key = NULL;
        int32_t pos = c->n;
        if (argc < 1 || argc > 4) bb_raise(450, NULL);
        if (argc > 1 && !is_missing(&argv[1])) {
            key = bb_v_to_str(&argv[1]);
            if (coll_find_key(c, key) >= 0) { bb_str_release(key); bb_raise(457, NULL); }
        }
        if (argc > 2 && !is_missing(&argv[2])) pos = coll_index(c, &argv[2]);
        else if (argc > 3 && !is_missing(&argv[3])) pos = coll_index(c, &argv[3]) + 1;
        if (c->n == c->cap) {
            c->cap = c->cap ? c->cap * 2 : 8;
            c->items = (citem *)bb_realloc(c->items, sizeof(citem) * (size_t)c->cap);
        }
        memmove(&c->items[pos + 1], &c->items[pos], sizeof(citem) * (size_t)(c->n - pos));
        {
            bb_value t;
            bb_v_copy(&c->items[pos].v, bb_v_deref(&argv[0], &t));
        }
        c->items[pos].key = key;
        c->n++;
        break;
    }
    case C_REMOVE: {
        int32_t i;
        if (argc != 1) bb_raise(450, NULL);
        i = coll_index(c, &argv[0]);
        bb_v_release(&c->items[i].v);
        bb_str_release(c->items[i].key);
        memmove(&c->items[i], &c->items[i + 1], sizeof(citem) * (size_t)(c->n - i - 1));
        c->n--;
        break;
    }
    default:
        bb_raise(438, NULL);
    }
}

static void coll_terminate(bb_obj *self)
{
    coll *c = (coll *)self;
    int32_t i;
    for (i = 0; i < c->n; i++) { bb_v_release(&c->items[i].v); bb_str_release(c->items[i].key); }
    free(c->items);
}

static int coll_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    coll *c = (coll *)self;
    int32_t i = state->type == BB_LONG ? state->u.l : 0;
    if (i >= c->n) return 0;
    bb_v_copy(out, &c->items[i].v);
    *state = bb_v_long(i + 1);
    return 1;
}

const bb_class bb_collection_class = {
    "Collection", sizeof(coll), bb_class_find_default, coll_invoke, coll_terminate, coll_iterate,
    coll_members, 4, NULL, 0, NULL, NULL
};

bb_obj *bb_collection_new(void) { return bb_obj_new(&bb_collection_class); }

/* ---- Variant indexing ---- */

static void *elem_of(bb_array *a, int argc, bb_value *argv)
{
    int32_t idx[BB_MAXDIMS];
    int i;
    if (argc > BB_MAXDIMS) bb_raise(9, NULL);
    for (i = 0; i < argc; i++) idx[i] = bb_v_to_long(&argv[i]);
    return bb_arr_elem(a, argc, idx);
}

bb_value bb_v_index(const bb_value *v0, int argc, bb_value *argv)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    if (v->type & BB_ARRAY) {
        if (!v->u.a) bb_raise(9, NULL);
        return bb_elem_load(v->u.a->etype, elem_of(v->u.a, argc, argv));
    }
    if (v->type == BB_OBJECT) return bb_invoke(v->u.o, "", BB_INV_GET | BB_INV_METHOD, argc, argv);
    bb_raise(13, NULL);
    return bb_v_empty();
}

void bb_v_index_store(bb_value *v0, int argc, bb_value *argv, const bb_value *val)
{
    bb_value *v = v0;
    if (v->type & BB_REF) {
        if (BB_BASETYPE(v->type) != BB_VARIANT) bb_raise(13, NULL);
        v = (bb_value *)v->u.p;
    }
    if (v->type & BB_ARRAY) {
        if (!v->u.a) bb_raise(9, NULL);
        bb_elem_store(v->u.a->etype, elem_of(v->u.a, argc, argv), val);
        return;
    }
    if (v->type == BB_OBJECT) {
        bb_value args[BB_MAXDIMS + 1], r;
        int i;
        if (argc > BB_MAXDIMS) bb_raise(450, NULL);
        for (i = 0; i < argc; i++) args[i] = argv[i];
        args[argc] = *val;
        r = bb_invoke(v->u.o, "", val->type == BB_OBJECT ? BB_INV_SET : BB_INV_LET, argc + 1, args);
        bb_v_release(&r);
        return;
    }
    bb_raise(13, NULL);
}

bb_array *bb_v_array(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    if (!(v->type & BB_ARRAY)) bb_raise(13, NULL);
    return v->u.a;
}

bb_array *bb_v_to_array(const bb_value *v0, int etype)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    if (!(v->type & BB_ARRAY)) bb_raise(13, NULL);
    if (!v->u.a) return NULL;
    if (etype != BB_VARIANT && v->u.a->etype != etype) bb_raise(13, NULL);
    return bb_arr_copy(v->u.a);
}

void bb_arr_set(bb_array **dst, bb_array *owned)
{
    if (*dst && (*dst)->fixed) { bb_arr_free(owned); bb_raise(10, NULL); }
    bb_arr_free(*dst);
    *dst = owned;
}

void bb_v_redim(bb_value *v, int etype, const bb_udt_desc *udt, int ndims, const int32_t *lb, const int32_t *ub, int preserve)
{
    if (v->type & BB_ARRAY) {
        bb_arr_redim(&v->u.a, v->u.a ? v->u.a->etype : etype, v->u.a ? v->u.a->udt : udt, ndims, lb, ub, preserve);
        if (v->u.a) v->type = (uint16_t)(BB_ARRAY | v->u.a->etype);
    } else {
        bb_array *a = NULL;
        bb_arr_redim(&a, etype, udt, ndims, lb, ub, 0);
        bb_v_set(v, bb_v_arr(a));
    }
}

void bb_v_erase(bb_value *v)
{
    if (v->type & BB_ARRAY) bb_arr_erase(&v->u.a);
    else bb_raise(13, NULL);
}

void bb_v_mid_assign(bb_value *v, bb_long start, bb_long len, bb_str *repl)
{
    if (v->type != BB_STRING) bb_raise(13, NULL);
    bb_mid_assign(&v->u.s, start, len, repl);
}

int bb_for_done_v(const bb_value *ctr, const bb_value *lim, const bb_value *step)
{
    bb_value zero = bb_v_int(0);
    int sg = bb_v_compare(step, &zero, 0), c = bb_v_compare(ctr, lim, 0);
    return sg >= 0 ? c == 1 : c == -1;
}

bb_bool bb_v_is(const bb_value *a0, const bb_value *b0)
{
    bb_value ta, tb;
    const bb_value *a = bb_v_deref(a0, &ta), *b = bb_v_deref(b0, &tb);
    if ((a->type != BB_OBJECT && a->type != BB_EMPTY) || (b->type != BB_OBJECT && b->type != BB_EMPTY)) bb_raise(424, NULL);
    return (a->type == BB_OBJECT ? a->u.o : NULL) == (b->type == BB_OBJECT ? b->u.o : NULL) ? BB_TRUE : BB_FALSE;
}

bb_obj *bb_chkcls(bb_obj *o, const bb_class *cls)
{
    if (o && !bb_obj_is(o, cls)) bb_raise(13, NULL);
    return o;
}

void bb_wev_disconnect(bb_wevconn *c)
{
    if (c->src) {
        bb_event_disconnect(c->src, c->sink);
        bb_obj_release(c->src);
    }
    c->src = NULL;
    c->sink = NULL;
}

void bb_wev_connect(bb_wevconn *c, bb_obj *src, void (*fire)(bb_sink *, int32_t, const char *, int, bb_value *),
                    void *ctx, int32_t tag)
{
    bb_wev_disconnect(c);
    if (!src) return;
    c->src = bb_obj_retain(src);
    c->sink = bb_event_connect(src, fire, ctx, tag);
}
