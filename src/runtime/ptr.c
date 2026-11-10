/* ptr.c - pointer-level builtins for OS calls through Declare: Peek/Poke, VarPtr/StrPtr/ObjPtr,
 * PeekS, TagList, AllocMem/FreeMem. Addresses are Longs (32 bits, as on AmigaOS 4). On a 64-bit
 * host a pointer that does not fit in 32 bits raises error 5 instead of being truncated.
 */
#include "boing.h"
#include <stdlib.h>
#include <string.h>

bb_long bb_ptr32(const void *p)
{
    uintptr_t u = (uintptr_t)p;
    if (u > 0xffffffffu) bb_raise(5, NULL);     /* not representable as a Long here */
    return (bb_long)(uint32_t)u;
}

static unsigned char *addr_of(bb_long a)
{
    if (a == 0) bb_raise(5, NULL);
    return (unsigned char *)(uintptr_t)(uint32_t)a;
}

/* native byte order (big-endian on the Amiga) */
bb_long bb_peekb(bb_long a) { return *addr_of(a); }
bb_long bb_peekw(bb_long a) { uint16_t v; memcpy(&v, addr_of(a), 2); return v; }
bb_long bb_peekl(bb_long a) { int32_t v; memcpy(&v, addr_of(a), 4); return v; }
void bb_pokeb(bb_long a, bb_long v) { *addr_of(a) = (unsigned char)v; }
void bb_pokew(bb_long a, bb_long v) { uint16_t x = (uint16_t)v; memcpy(addr_of(a), &x, 2); }
void bb_pokel(bb_long a, bb_long v) { int32_t x = v; memcpy(addr_of(a), &x, 4); }

bb_str *bb_peeks(bb_long a, bb_long maxlen)
{
    const char *p;
    size_t n = 0;
    if (a == 0) return NULL;
    p = (const char *)addr_of(a);
    while ((maxlen < 0 || (bb_long)n < maxlen) && p[n]) n++;
    return bb_str_new(p, (int32_t)n);
}

bb_long bb_strptr(bb_str *s) { return s && s->len ? bb_ptr32(s->data) : 0; }

bb_long bb_objptr(const bb_value *v)
{
    bb_value t;
    v = bb_v_deref(v, &t);
    if (v->type == BB_OBJECT) return v->u.o ? bb_ptr32(v->u.o) : 0;
    if (v->type == BB_EMPTY) return 0;
    bb_raise(13, NULL);
    return 0;
}

/* memory the program asked for: freed at exit unless freed earlier */
typedef struct blk { struct blk *next; } blk;
static blk *blocks;

static void *alloc_tracked(size_t n, int clear)
{
    blk *b = (blk *)malloc(sizeof(blk) + 8 + n);      /* the user part stays 8-byte aligned */
    void *p;
    if (!b) bb_raise(7, NULL);
    b->next = blocks;
    blocks = b;
    p = (char *)b + ((sizeof(blk) + 7) & ~(size_t)7);
    if (clear) memset(p, 0, n);
    return p;
}

static void free_tracked(void *p)
{
    blk **pp;
    for (pp = &blocks; *pp; pp = &(*pp)->next)
        if ((char *)*pp + ((sizeof(blk) + 7) & ~(size_t)7) == (char *)p) {
            blk *b = *pp;
            *pp = b->next;
            free(b);
            return;
        }
    bb_raise(5, NULL);      /* not from AllocMem / TagList */
}

void bb_ptr_cleanup(void)
{
    while (blocks) { blk *b = blocks; blocks = b->next; free(b); }
}

bb_long bb_allocmem(bb_long size, bb_bool clear)
{
    if (size < 0) bb_raise(5, NULL);
    return bb_ptr32(alloc_tracked((size_t)size, clear != 0));
}

void bb_freemem(bb_long p) { if (p) free_tracked(addr_of(p)); }

/* TagList(tag1, val1, ...): struct TagItem { ULONG ti_Tag; ULONG ti_Data; } array + TAG_DONE (0) */
bb_long bb_taglist(int argc, const bb_value *argv)
{
    uint32_t *t;
    char *sp;
    size_t sbytes = 0, tbytes;
    int i, n = argc / 2;
    if (argc % 2) bb_raise(450, NULL);
    /* strings are copied into the tag list's own block (after the tags), so a temporary
       ("Title " & n) stays valid until FreeTagList */
    for (i = 0; i < n; i++) {
        bb_value tmp;
        const bb_value *v = bb_v_deref(&argv[2 * i + 1], &tmp);
        if (v->type == BB_STRING) sbytes += (size_t)bb_str_len(v->u.s) + 1;
    }
    tbytes = sizeof(uint32_t) * 2 * (size_t)(n + 1);
    t = (uint32_t *)alloc_tracked(tbytes + sbytes, 1);
    sp = (char *)t + tbytes;
    for (i = 0; i < n; i++) {
        bb_value tmp;
        const bb_value *v = bb_v_deref(&argv[2 * i + 1], &tmp);
        t[2 * i] = (uint32_t)bb_v_to_long(&argv[2 * i]);
        if (v->type == BB_STRING) {
            size_t l = (size_t)bb_str_len(v->u.s);
            memcpy(sp, bb_str_ptr(v->u.s), l);
            sp[l] = 0;
            t[2 * i + 1] = (uint32_t)bb_ptr32(sp);
            sp += l + 1;
        }
        else if (v->type == BB_OBJECT) t[2 * i + 1] = (uint32_t)bb_objptr(v);
        else t[2 * i + 1] = (uint32_t)bb_v_to_long(v);
    }
    return bb_ptr32(t);
}
