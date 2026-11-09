/* engine3d.c - Boing.Engine3D: the amiga3d engine's 3D in C, drawing into a Canvas
 *
 * See docs/engine3d.md. The maths, camera and clipping are amiga3d's own (a3d/, vendored);
 * the draw list, models and drawing follow amiga3d's a3d_draw.c with the same rules (depth
 * buckets far to near, models' visible faces sorted, the fixed sun's lit/shade pens), but
 * draw into the Canvas's 32-bit 0xAARRGGBB target, at Sub (1..4) pixels a 3D-area unit.
 */
#include "canvas.h"
#include "a3d/a3d.h"
#include "a3d/a3d_fix.h"
#include "a3d/a3d_font16.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

#define ARGB(vb) (0xFF000000u | (((uint32_t)(vb) & 0xFFu) << 16) | ((uint32_t)(vb) & 0xFF00u) | \
                  (((uint32_t)(vb) >> 16) & 0xFFu))
#define VBCOL(argb) ((int32_t)((((argb) >> 16) & 0xFFu) | ((argb) & 0xFF00u) | (((argb) & 0xFFu) << 16)))

#define E3_MAXV      256
#define E3_MAXF      192
#define E3_MAXPOLY   8000
#define E3_NBUCKET   512
#define E3_NCAM      8
#define E3_COL_BODY  200
#define E3_COL_FLASH 210

enum { K_POLY = 0, K_LINE = 1, K_POINT = 2 };

typedef struct {
    int32_t next;
    uint8_t n, kind, grad, size;
    uint32_t col;
    int16_t x[MAX_PV], y[MAX_PV];
} DPoly;

typedef struct { int32_t n, col, lit; uint16_t idx[4]; } E3Face;

typedef struct {
    int used;
    int32_t nv, nf, radius;
    int16_t v[E3_MAXV][3];
    E3Face f[E3_MAXF];
} E3Model;

typedef struct {
    int used;
    int32_t w, h, cell, x0, z0;
    int32_t *hgt;               /* w * h, whole units */
    int32_t *pen;               /* (w-1) * (h-1), NULL: by height or pen 2 */
    V3 *xf;                     /* camera-space cache, w * h */
    int32_t water, wpen, lpen, hpen, snow, spen, bypen;   /* GridColours */
    int shade;
} E3Grid;

typedef struct { Cam c; int32_t roll, cr, sr, rolled; } E3Cam;

typedef struct bb_e3d {
    bb_obj hdr;
    bb_obj *canvas;
    E3Cam cam, saved[E3_NCAM];
    int32_t sub, ox, oy;
    uint32_t pal[256];
    int32_t sky_pen, sky_rows;
    uint32_t sky[1024];
    int32_t shading, amb;
    int32_t margin, quad_bias;            /* ModelMargin (800), QuadBias (0) */
    int32_t lix, liy, liz;               /* the light direction, 16.16 unit vector */
    int32_t fog_on;
    uint32_t fog_col;
    int32_t fog_near, fog_far;
    /* the draw list */
    DPoly *pool;
    int32_t npolys, dropped, far_z;
    int32_t bhead[E3_NBUCKET], btail[E3_NBUCKET];
    /* models, grids (numbered from 1) */
    E3Model **models;
    int32_t nmodels;
    E3Grid *grids;
    int32_t ngrids;
    /* scratch */
    V3 mv[E3_MAXV];
    int32_t wv[E3_MAXV][3];
    int32_t vis_depth[E3_MAXF];
    int32_t vis_face[E3_MAXF];
    /* the target while drawing */
    uint32_t *tp;
    int32_t tw, th;
} bb_e3d;

/* ---------------------------------------------------------------- arguments */

static int missing(int argc, const bb_value *argv, int i)
{
    if (i >= argc) return 1;
    return argv[i].type == BB_ERROR && (argv[i].flags & BB_VF_MISSING);
}

static int32_t to_l(const bb_value *v)
{
    bb_value t;
    switch (v->type) {
    case BB_LONG: return v->u.l;
    case BB_INTEGER: return v->u.i;
    case BB_BOOLEAN: return v->u.b;
    case BB_BYTE: return v->u.by;
    case BB_REF | BB_LONG: return *(bb_long *)v->u.p;
    case BB_REF | BB_INTEGER: return *(bb_int *)v->u.p;
    default:
        if (v->type & BB_REF) v = bb_v_deref(v, &t);
        return bb_v_to_long(v);
    }
}

static int32_t argl(int argc, const bb_value *argv, int i)
{
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    return to_l(&argv[i]);
}

static int32_t argl_opt(int argc, const bb_value *argv, int i, int32_t def)
{
    return missing(argc, argv, i) ? def : to_l(&argv[i]);
}

/* the array an argument holds, NULL if it holds none */
static bb_array *try_array(int argc, const bb_value *argv, int i)
{
    const bb_value *v;
    if (missing(argc, argv, i)) return NULL;
    v = &argv[i];
    if ((v->type & BB_REF) && (v->type & BB_ARRAY)) return *(bb_array **)v->u.p;
    if (v->type & BB_REF) {
        if ((v->type & ~BB_REF) == BB_VARIANT) {
            const bb_value *pv = (const bb_value *)v->u.p;
            if (pv->type & BB_ARRAY) return pv->u.a;
        }
        return NULL;
    }
    if (v->type & BB_ARRAY) return v->u.a;
    return NULL;
}

static bb_array *arg_array(int argc, const bb_value *argv, int i)
{
    bb_array *a;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    a = try_array(argc, argv, i);
    if (!a) bb_raise(13, NULL);
    return a;
}

static int32_t elem_l(const bb_array *a, int32_t k)
{
    const char *p = (const char *)a->data + (size_t)k * (size_t)a->esize;
    switch (a->etype) {
    case BB_LONG: return *(const bb_long *)p;
    case BB_INTEGER: return *(const bb_int *)p;
    case BB_BYTE: return *(const bb_byte *)p;
    case BB_BOOLEAN: return *(const bb_bool *)p;
    case BB_SINGLE: return bb_v_to_long(&(bb_value){ .type = BB_SINGLE, .u.f = *(const bb_single *)p });
    case BB_DOUBLE: return bb_v_to_long(&(bb_value){ .type = BB_DOUBLE, .u.d = *(const bb_double *)p });
    case BB_VARIANT: return to_l((const bb_value *)p);
    default: bb_raise(13, NULL);
    }
    return 0;
}

/* the first n elements of a numeric array (n checked against its size) into out */
static void read_arr(const bb_array *a, int32_t n, int32_t *out)
{
    int32_t i;
    if (!a || n < 0 || n > a->count) bb_raise(9, NULL);
    if (a->etype == BB_LONG) { memcpy(out, a->data, (size_t)n * 4); return; }
    for (i = 0; i < n; i++) out[i] = elem_l(a, i);
}

static bb_long *out_arr(int argc, const bb_value *argv, int i, int32_t n)
{
    bb_array *a = arg_array(argc, argv, i);
    if (a->etype != BB_LONG) bb_raise(13, NULL);
    if (n > a->count) bb_raise(9, NULL);
    return (bb_long *)a->data;
}

static void store_l(const bb_value *ref, int32_t x)
{
    bb_value v = bb_v_long(x);
    if (!(ref->type & BB_REF)) return;      /* passed by value: nowhere to write */
    bb_v_store_ref(ref, &v);
}

/* "an array or one value": element k of it */
typedef struct { const bb_array *a; int32_t one; } many;
static many arg_many(int argc, const bb_value *argv, int i, int32_t def)
{
    many m;
    m.a = try_array(argc, argv, i);
    m.one = m.a ? 0 : argl_opt(argc, argv, i, def);
    return m;
}
static int32_t many_at(const many *m, int32_t k)
{
    if (!m->a) return m->one;
    if (k >= m->a->count) bb_raise(9, NULL);
    return elem_l(m->a, k);
}

static const char *arg_str(int argc, const bb_value *argv, int i, bb_str **hold)
{
    bb_value t;
    const bb_value *v;
    *hold = NULL;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_STRING) return bb_str_ptr(v->u.s);
    *hold = bb_v_to_str(v);
    return bb_str_ptr(*hold);
}

static bb_obj *arg_obj(int argc, const bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_OBJECT) return v->u.o;
    if (v->type == BB_VARIANT) {
        const bb_value *in = (const bb_value *)v->u.p;
        if (in && in->type == BB_OBJECT) return in->u.o;
    }
    bb_raise(13, NULL);
    return NULL;
}

/* ---------------------------------------------------------------- the camera */

static void cam_trig(E3Cam *k)
{
    cam_setup(&k->c);
    k->cr = a3_cos(k->roll) >> 4;
    k->sr = a3_sin(k->roll) >> 4;
    k->rolled = (k->roll & 0xFFFF) != 0;
}

static inline void xform(const E3Cam *k, const Cam *c, int32_t wx, int32_t wy, int32_t wz, V3 *o)
{
    cam_xform(c, wx, wy, wz, o);
    if (k->rolled) {
        int64_t x = o->x, y = o->y;
        o->x = (int32_t)((x * k->cr + y * k->sr) >> 12);
        o->y = (int32_t)((y * k->cr - x * k->sr) >> 12);
    }
}

/* ---------------------------------------------------------------- colours */

static uint32_t pen_argb(const bb_e3d *e, int32_t pen, int *grad)
{
    if (pen < 0) return ARGB(-1 - pen);
    pen &= 255;
    if (grad && pen == e->sky_pen && e->sky_rows > 0) *grad = 1;
    return e->pal[pen];
}

static uint32_t scale_col(uint32_t c, int32_t k)       /* k 0..256 */
{
    uint32_t r = ((c >> 16) & 255) * (uint32_t)k >> 8, g = ((c >> 8) & 255) * (uint32_t)k >> 8, b = (c & 255) * (uint32_t)k >> 8;
    return 0xFF000000u | r << 16 | g << 8 | b;
}

static uint32_t mix_col(uint32_t a, uint32_t b, int32_t t)   /* t 0..256 towards b */
{
    int32_t u = 256 - t;
    uint32_t r = (((a >> 16) & 255) * u + ((b >> 16) & 255) * t) >> 8;
    uint32_t g = (((a >> 8) & 255) * u + ((b >> 8) & 255) * t) >> 8;
    uint32_t bl = ((a & 255) * u + (b & 255) * t) >> 8;
    return 0xFF000000u | r << 16 | g << 8 | bl;
}

/* Lambert: 0..256 for a face normal (world space, any length). Integer only, so every
 * platform shades alike (GCC fuses floating multiply-adds on PPC). */
static int32_t lambert(const bb_e3d *e, double fx, double fy, double fz)
{
    int64_t nx = (int64_t)fx, ny = (int64_t)fy, nz = (int64_t)fz, d;
    uint32_t len;
    int32_t k;
    while (nx > 16383 || nx < -16383 || ny > 16383 || ny < -16383 || nz > 16383 || nz < -16383) {
        nx /= 2; ny /= 2; nz /= 2;
    }
    len = a3_isqrt((uint32_t)(nx * nx + ny * ny + nz * nz));
    if (!len) return 256;
    d = nx * e->lix + ny * e->liy + nz * e->liz;        /* light: 16.16 unit vector */
    if (d < 0) d = 0;
    d /= len;                                           /* cos, 16.16 */
    k = e->amb + (int32_t)(((int64_t)(256 - e->amb) * d) >> 16);
    return k < 0 ? 0 : k > 256 ? 256 : k;
}

/* the colour a polygon is drawn in: pen, shading by a world normal, fog by depth */
static uint32_t face_col(const bb_e3d *e, const Cam *c, int32_t pen, int has_n, double nx, double ny, double nz,
                         int32_t depth, int *grad)
{
    uint32_t col = pen_argb(e, pen, grad);
    if (e->shading && has_n) {
        col = scale_col(col, lambert(e, nx, ny, nz));
        *grad = 0;
    }
    if (e->fog_on) {
        int32_t z = depth / CAM_U(c), t;
        if (z > e->fog_near) {
            t = z >= e->fog_far ? 256 : (int32_t)(((int64_t)(z - e->fog_near) * 256) / (e->fog_far - e->fog_near));
            col = mix_col(col, e->fog_col, t);
            *grad = 0;
        }
    }
    return col;
}

/* ---------------------------------------------------------------- the draw list */

static void e_begin(bb_e3d *e, int32_t fz)
{
    int i;
    e->npolys = 0;
    e->dropped = 0;
    e->far_z = fz > 0 ? fz : 1;
    for (i = 0; i < E3_NBUCKET; i++) e->bhead[i] = e->btail[i] = -1;
}

static void e_link(bb_e3d *e, const Cam *c, int32_t depth)
{
    int32_t b, k = e->npolys;
    if (c->precise) depth /= 16;
    b = depth < 0 ? 0 : (depth >= e->far_z ? E3_NBUCKET - 1 : (int32_t)(((int64_t)depth * E3_NBUCKET) / e->far_z));
    if (b < 0) b = 0;
    if (b >= E3_NBUCKET) b = E3_NBUCKET - 1;
    if (e->btail[b] >= 0) e->pool[e->btail[b]].next = k; else e->bhead[b] = k;
    e->btail[b] = k;
    e->npolys++;
}

static DPoly *e_new(bb_e3d *e)
{
    DPoly *p;
    if (e->npolys >= E3_MAXPOLY) { e->dropped++; return NULL; }
    p = &e->pool[e->npolys];
    p->next = -1;
    p->grad = 0;
    p->size = 0;
    return p;
}

static inline void project(const bb_e3d *e, const Cam *c, const V3 *p, int32_t *sx, int32_t *sy)
{
    int32_t S = e->sub, qx = p->x * c->fov, qy = p->y * c->fov, z = p->z;
    if (S == 1) {
        *sx = c->cx + qx / z;
        *sy = c->cyc - qy / z;
    } else {
        *sx = c->cx * S + (qx / z) * S + ((qx % z) * S) / z;
        *sy = c->cyc * S - ((qy / z) * S + ((qy % z) * S) / z);
    }
}

/* amiga3d's a3_poly: camera space polygon, near clip, project, screen clip, into the list */
static void e_poly(bb_e3d *e, const Cam *c, int32_t depth, uint32_t col, int grad, V3 *cv, int n)
{
    V3 cl[MAX_PV];
    int32_t xs[MAX_PV], ys[MAX_PV];
    DPoly *p;
    int i;

    n = clip_near_at(cv, n, cl, CAM_NEAR(c));
    if (n < 3) return;
    for (i = 0; i < n; i++) project(e, c, &cl[i], &xs[i], &ys[i]);
    n = clip_rect(xs, ys, n, 0, 0, c->vw * e->sub - 1, c->vh * e->sub - 1);
    if (n < 3) return;
    if (!(p = e_new(e))) return;
    p->n = (uint8_t)n;
    p->kind = K_POLY;
    p->col = col;
    p->grad = (uint8_t)grad;
    for (i = 0; i < n; i++) { p->x[i] = (int16_t)xs[i]; p->y[i] = (int16_t)ys[i]; }
    e_link(e, c, depth);
}

/* a3_quad's trivial rejects, then e_poly */
static void e_quad(bb_e3d *e, const Cam *c, int32_t depth, uint32_t col, int grad, V3 *q)
{
    int32_t nz = CAM_NEAR(c);
    if (q[0].z < nz && q[1].z < nz && q[2].z < nz && q[3].z < nz) return;
    if (q[0].x > q[0].z && q[1].x > q[1].z && q[2].x > q[2].z && q[3].x > q[3].z) return;
    if (q[0].x < -q[0].z && q[1].x < -q[1].z && q[2].x < -q[2].z && q[3].x < -q[3].z) return;
    e_poly(e, c, depth, col, grad, q, 4);
}

static int32_t pick_depth(const bb_e3d *e, int32_t mode, const V3 *q, int n)
{
    int32_t d, i;
    if (mode >= 0) return mode;
    switch (mode) {
    case -2: d = 0; for (i = 0; i < n; i++) d += q[i].z; return d / n;
    case -3: d = q[0].z; for (i = 1; i < n; i++) if (q[i].z < d) d = q[i].z; return d;
    case -4: d = q[0].z; for (i = 1; i < n; i++) if (q[i].z > d) d = q[i].z; return d;
    case -5: d = 0; for (i = 0; i < n; i++) d += q[i].z; return d / n + e->quad_bias;
    default: return (q[0].z + q[n > 2 ? 2 : n - 1].z) / 2 + e->quad_bias;
    }
}

/* a polygon of world points: xform, depth, shading by its normal */
static void e_poly_world(bb_e3d *e, int32_t depth, int32_t pen, const int32_t *w, int n, int quad)
{
    V3 q[MAX_PV];
    int i, grad = 0;
    double nx = 0, ny = 0, nz = 0;
    uint32_t col;
    for (i = 0; i < n; i++) xform(&e->cam, &e->cam.c, w[i * 3], w[i * 3 + 1], w[i * 3 + 2], &q[i]);
    depth = pick_depth(e, depth, q, n);
    if (e->shading) {
        double ux = w[3] - w[0], uy = w[4] - w[1], uz = w[5] - w[2];
        double vx = w[6] - w[0], vy = w[7] - w[1], vz = w[8] - w[2];
        nx = uy * vz - uz * vy; ny = uz * vx - ux * vz; nz = ux * vy - uy * vx;
        /* either side may face the camera: light the side that does */
        {
            double ex = e->cam.c.x - w[0], ey = e->cam.c.y - w[1], ez = e->cam.c.z - w[2];
            if (nx * ex + ny * ey + nz * ez < 0) { nx = -nx; ny = -ny; nz = -nz; }
        }
    }
    col = face_col(e, &e->cam.c, pen, e->shading, nx, ny, nz, depth, &grad);
    if (quad && n == 4) e_quad(e, &e->cam.c, depth, col, grad, q);
    else e_poly(e, &e->cam.c, depth, col, grad, q, n);
}

/* a camera-space line: cut at the near plane, projected; 0 when nothing is left to draw */
static int clip_line(bb_e3d *e, const V3 *a0, const V3 *b0, int32_t *o)
{
    const Cam *c = &e->cam.c;
    V3 a = *a0, b = *b0;
    int32_t nz = CAM_NEAR(c), x0, y0, x1, y1, W = c->vw * e->sub, H = c->vh * e->sub;
    if (a.z < nz && b.z < nz) return 0;
    if (a.z < nz || b.z < nz) {
        V3 *in = a.z >= nz ? &a : &b, *out = a.z >= nz ? &b : &a;
        int32_t t = nz - in->z, dz = out->z - in->z;
        out->x = in->x + (int32_t)(((int64_t)(out->x - in->x) * t) / dz);
        out->y = in->y + (int32_t)(((int64_t)(out->y - in->y) * t) / dz);
        out->z = nz;
    }
    project(e, c, &a, &x0, &y0);
    project(e, c, &b, &x1, &y1);
    if ((x0 < 0 && x1 < 0) || (y0 < 0 && y1 < 0) || (x0 >= W && x1 >= W) || (y0 >= H && y1 >= H)) return 0;
    /* keep the ends within int16 (and the stepping short): pull a far end in along the line */
    while (x0 < -16000 || x0 > 16000 || y0 < -16000 || y0 > 16000) { x0 = (x0 + x1) / 2; y0 = (y0 + y1) / 2; }
    while (x1 < -16000 || x1 > 16000 || y1 < -16000 || y1 > 16000) { x1 = (x0 + x1) / 2; y1 = (y0 + y1) / 2; }
    o[0] = x0; o[1] = y0; o[2] = x1; o[3] = y1;
    return 1;
}

static void e_line(bb_e3d *e, const V3 *a, const V3 *b, int32_t depth, uint32_t col)
{
    int32_t o[4];
    DPoly *p;
    if (!clip_line(e, a, b, o) || !(p = e_new(e))) return;
    p->n = 2;
    p->kind = K_LINE;
    p->col = col;
    p->x[0] = (int16_t)o[0]; p->y[0] = (int16_t)o[1]; p->x[1] = (int16_t)o[2]; p->y[1] = (int16_t)o[3];
    e_link(e, &e->cam.c, depth);
}

static void e_point(bb_e3d *e, int32_t wx, int32_t wy, int32_t wz, int32_t pen, int32_t size, int32_t bias)
{
    const Cam *c = &e->cam.c;
    V3 q;
    int32_t sx, sy, s, grad = 0;
    DPoly *p;
    xform(&e->cam, c, wx, wy, wz, &q);
    if (q.z < CAM_NEAR(c)) return;
    project(e, c, &q, &sx, &sy);
    if (size < 0) {
        /* -size pixels at a depth of 256 units, smaller further away */
        s = (int32_t)(((int64_t)(-size) * 256 * CAM_U(c) * e->sub) / q.z);
        if (s < 1) s = 1;
    } else s = (size < 1 ? 1 : size) * e->sub;
    if (s > 255) s = 255;
    if (sx + s < 0 || sy + s < 0 || sx - s >= c->vw * e->sub || sy - s >= c->vh * e->sub) return;
    if (!(p = e_new(e))) return;
    p->n = 1;
    p->kind = K_POINT;
    p->size = (uint8_t)s;
    p->col = face_col(e, c, pen, 0, 0, 0, 0, q.z, &grad);
    p->x[0] = (int16_t)sx; p->y[0] = (int16_t)sy;
    e_link(e, c, q.z - bias * CAM_U(c));
}

/* ---------------------------------------------------------------- rasterising */

static int16_t span_l[SPAN_MAX], span_r[SPAN_MAX];

static int need_target(bb_e3d *e)
{
    if (!e->canvas) bb_raise(91, NULL);
    e->tp = bb_canvas_pixels(e->canvas, &e->tw, &e->th);
    return e->tp != NULL;
}

static inline void fill_row(uint32_t *d, int32_t n, uint32_t c)
{
    while (n >= 4) { d[0] = c; d[1] = c; d[2] = c; d[3] = c; d += 4; n -= 4; }
    while (n-- > 0) *d++ = c;
}

/* a span in the drawing's pixels relative to the 3D area's origin, clipped to the target */
static void tspan(bb_e3d *e, int32_t y, int32_t xl, int32_t xr, uint32_t c)
{
    int32_t S = e->sub;
    y += e->oy * S;
    xl += e->ox * S;
    xr += e->ox * S;
    if ((uint32_t)y >= (uint32_t)e->th) return;
    if (xl < 0) xl = 0;
    if (xr >= e->tw) xr = e->tw - 1;
    if (xl > xr) return;
    fill_row(e->tp + y * e->tw + xl, xr - xl + 1, c);
}

static uint32_t sky_at(const bb_e3d *e, int32_t y, uint32_t c)
{
    if (y >= 0 && y < e->sky_rows * e->sub) return e->sky[y < 1024 ? y : 1023];
    return c;
}

/* fill a polygon (the drawing's pixels); widen stretches spans and the last row */
static void raster(bb_e3d *e, const int16_t *xs, const int16_t *ys, int n, uint32_t c, int grad, int widen)
{
    int ymin, i, rows = poly_spans(xs, ys, n, span_l, span_r, &ymin);
    int32_t S = e->sub, bx = e->ox * S, by = e->oy * S;
    for (i = 0; i < rows + widen; i++) {
        int k = i < rows ? i : rows - 1;
        int32_t xl = span_l[k] + bx, xr = span_r[k] + widen + bx, y = ymin + i + by;
        if (xl > xr || (uint32_t)y >= (uint32_t)e->th) continue;
        if (xl < 0) xl = 0;
        if (xr >= e->tw) xr = e->tw - 1;
        if (xl > xr) continue;
        fill_row(e->tp + y * e->tw + xl, xr - xl + 1, grad ? sky_at(e, ymin + i, c) : c);
    }
}

static void raster_line(bb_e3d *e, int32_t x1, int32_t y1, int32_t x2, int32_t y2, uint32_t col)
{
    int32_t S = e->sub, W = e->cam.c.vw * S, H = e->cam.c.vh * S;
    int32_t dx = x2 > x1 ? x2 - x1 : x1 - x2, dy = y2 > y1 ? y1 - y2 : y2 - y1;
    int32_t sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1, er = dx + dy, e2;
    int32_t bx = e->ox * S, by = e->oy * S;
    for (;;) {
        if ((uint32_t)x1 < (uint32_t)W && (uint32_t)y1 < (uint32_t)H) {
            int32_t px = x1 + bx, py = y1 + by;
            if ((uint32_t)px < (uint32_t)e->tw && (uint32_t)py < (uint32_t)e->th) e->tp[py * e->tw + px] = col;
        }
        if (x1 == x2 && y1 == y2) break;
        e2 = 2 * er;
        if (e2 >= dy) { er += dy; x1 += sx; }
        if (e2 <= dx) { er += dx; y1 += sy; }
    }
}

static void raster_point(bb_e3d *e, int32_t x, int32_t y, int32_t s, uint32_t col)
{
    int32_t W = e->cam.c.vw * e->sub - 1, H = e->cam.c.vh * e->sub - 1;
    int32_t x0 = x - s / 2, y0 = y - s / 2, x1 = x0 + s - 1, y1 = y0 + s - 1, yy;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > W) x1 = W;
    if (y1 > H) y1 = H;
    for (yy = y0; yy <= y1; yy++) tspan(e, yy, x0, x1, col);
}

static void e_flush(bb_e3d *e)
{
    int32_t b, k;
    if (!need_target(e)) return;
    for (b = E3_NBUCKET - 1; b >= 0; b--)
        for (k = e->bhead[b]; k >= 0; k = e->pool[k].next) {
            DPoly *p = &e->pool[k];
            switch (p->kind) {
            case K_POLY: raster(e, p->x, p->y, p->n, p->col, p->grad, 0); break;
            case K_LINE: raster_line(e, p->x[0], p->y[0], p->x[1], p->y[1], p->col); break;
            default: raster_point(e, p->x[0], p->y[0], p->size, p->col); break;
            }
        }
}

/* ---------------------------------------------------------------- models */

static E3Model *get_model(bb_e3d *e, int32_t m)
{
    if (m < 1 || m > e->nmodels || !e->models[m - 1] || !e->models[m - 1]->used) bb_raise(380, NULL);
    return e->models[m - 1];
}

static int32_t model_new(bb_e3d *e)
{
    int32_t i;
    for (i = 0; i < e->nmodels; i++)
        if (!e->models[i]->used) break;
    if (i == e->nmodels) {
        E3Model **nm = (E3Model **)realloc(e->models, sizeof(E3Model *) * (size_t)(e->nmodels + 1));
        if (!nm) bb_raise(7, NULL);
        e->models = nm;
        nm[i] = (E3Model *)calloc(1, sizeof(E3Model));
        if (!nm[i]) bb_raise(7, NULL);
        e->nmodels++;
    }
    memset(e->models[i], 0, sizeof(E3Model));
    e->models[i]->used = 1;
    e->models[i]->radius = -1;
    return i + 1;
}

static int mdl_vtx3(E3Model *m, int x, int y, int z)
{
    int i = m->nv;
    if (i >= E3_MAXV) return E3_MAXV - 1;
    m->nv++;
    m->v[i][0] = (int16_t)x;
    m->v[i][1] = (int16_t)y;
    m->v[i][2] = (int16_t)z;
    m->radius = -1;
    return i;
}

/* amiga3d's mdl_face: flipped to face away from (ix, iy, iz), lit or shade by the fixed sun */
static void mdl_face3(E3Model *m, int32_t lit, int32_t shade, int n, int a, int b, int c, int d, int ix, int iy, int iz)
{
    E3Face *f;
    int16_t *A, *B, *C;
    int32_t ux, uy, uz, vx, vy, vz, nx, ny, nz, light, mag;
    if (m->nf >= E3_MAXF) return;
    if (a < 0 || a >= m->nv || b < 0 || b >= m->nv || c < 0 || c >= m->nv || (n == 4 && (d < 0 || d >= m->nv)))
        bb_raise(9, NULL);
    A = m->v[a]; B = m->v[b]; C = m->v[c];
    ux = B[0] - A[0]; uy = B[1] - A[1]; uz = B[2] - A[2];
    vx = C[0] - A[0]; vy = C[1] - A[1]; vz = C[2] - A[2];
    nx = uy * vz - uz * vy; ny = uz * vx - ux * vz; nz = ux * vy - uy * vx;
    f = &m->f[m->nf++];
    f->n = n;
    if (nx * (A[0] - ix) + ny * (A[1] - iy) + nz * (A[2] - iz) >= 0) {
        f->idx[0] = (uint16_t)a; f->idx[1] = (uint16_t)b; f->idx[2] = (uint16_t)c; f->idx[3] = (uint16_t)d;
    } else {
        if (n == 4) { f->idx[0] = (uint16_t)d; f->idx[1] = (uint16_t)c; f->idx[2] = (uint16_t)b; f->idx[3] = (uint16_t)a; }
        else        { f->idx[0] = (uint16_t)c; f->idx[1] = (uint16_t)b; f->idx[2] = (uint16_t)a; f->idx[3] = 0; }
        nx = -nx; ny = -ny; nz = -nz;
    }
    light = -nx + 2 * ny + nz;
    mag = (nx < 0 ? -nx : nx) + (ny < 0 ? -ny : ny) + (nz < 0 ? -nz : nz);
    f->col = (mag && light * 4 > mag * 3) ? lit : shade;
    f->lit = lit;
}

/* a face exactly as given (clockwise from outside) */
static void mdl_face_raw(E3Model *m, int32_t pen, int n, const int32_t *idx)
{
    E3Face *f;
    int i;
    if (n != 3 && n != 4) bb_raise(5, NULL);
    if (m->nf >= E3_MAXF) return;
    for (i = 0; i < n; i++) if (idx[i] < 0 || idx[i] >= m->nv) bb_raise(9, NULL);
    f = &m->f[m->nf++];
    f->n = n;
    for (i = 0; i < 4; i++) f->idx[i] = (uint16_t)(i < n ? idx[i] : 0);
    f->col = f->lit = pen;
}

static void mdl_box3(E3Model *m, int32_t lit, int32_t shade, int x0, int x1, int y0, int y1, int z0, int z1)
{
    int b = m->nv, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, cz = (z0 + z1) / 2;
    if (m->nv + 8 > E3_MAXV) bb_raise(5, NULL);
    mdl_vtx3(m, x0, y0, z0); mdl_vtx3(m, x1, y0, z0); mdl_vtx3(m, x1, y1, z0); mdl_vtx3(m, x0, y1, z0);
    mdl_vtx3(m, x0, y0, z1); mdl_vtx3(m, x1, y0, z1); mdl_vtx3(m, x1, y1, z1); mdl_vtx3(m, x0, y1, z1);
    mdl_face3(m, lit, shade, 4, b + 0, b + 3, b + 2, b + 1, cx, cy, cz);
    mdl_face3(m, lit, shade, 4, b + 5, b + 6, b + 7, b + 4, cx, cy, cz);
    mdl_face3(m, lit, shade, 4, b + 4, b + 7, b + 3, b + 0, cx, cy, cz);
    mdl_face3(m, lit, shade, 4, b + 1, b + 2, b + 6, b + 5, cx, cy, cz);
    mdl_face3(m, lit, shade, 4, b + 3, b + 7, b + 6, b + 2, cx, cy, cz);
    mdl_face3(m, lit, shade, 4, b + 0, b + 1, b + 5, b + 4, cx, cy, cz);
}

static void mdl_pyramid3(E3Model *m, int32_t lit, int32_t shade, int x0, int x1, int y0, int z0, int z1, int apex)
{
    int b = m->nv, t, cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, cy = y0 + (apex - y0) / 4;
    if (m->nv + 5 > E3_MAXV) bb_raise(5, NULL);
    mdl_vtx3(m, x0, y0, z0); mdl_vtx3(m, x1, y0, z0); mdl_vtx3(m, x1, y0, z1); mdl_vtx3(m, x0, y0, z1);
    t = mdl_vtx3(m, cx, apex, cz);
    mdl_face3(m, lit, shade, 3, b + 0, b + 1, t, 0, cx, cy, cz);
    mdl_face3(m, lit, shade, 3, b + 1, b + 2, t, 0, cx, cy, cz);
    mdl_face3(m, lit, shade, 3, b + 2, b + 3, t, 0, cx, cy, cz);
    mdl_face3(m, lit, shade, 3, b + 3, b + 0, t, 0, cx, cy, cz);
}

static void mdl_prism3(E3Model *m, int32_t lit, int32_t shade, int sides, int r, int y0, int y1, int top)
{
    int b = m->nv, k, cy = (y0 + y1) / 2, c;
    if (sides < 3 || sides > 64 || m->nv + 2 * sides + 1 > E3_MAXV) bb_raise(5, NULL);
    for (k = 0; k < sides; k++) {
        int a = (k * 65536) / sides;
        int x = (int)((a3_sin(a) * r) >> 16), z = (int)((a3_cos(a) * r) >> 16);
        mdl_vtx3(m, x, y0, z);
        mdl_vtx3(m, x, y1, z);
    }
    for (k = 0; k < sides; k++) {
        int j = (k + 1) % sides;
        mdl_face3(m, lit, shade, 4, b + 2 * k, b + 2 * k + 1, b + 2 * j + 1, b + 2 * j, 0, cy, 0);
    }
    if (!top) return;
    c = mdl_vtx3(m, 0, y1, 0);
    for (k = 0; k < sides; k++) {
        int j = (k + 1) % sides;
        mdl_face3(m, lit, lit, 3, b + 2 * k + 1, b + 2 * j + 1, c, 0, 0, y0, 0);
    }
}

static void mdl_shadow3(E3Model *m, int32_t col, int x0, int x1, int z0, int z1)
{
    int b = m->nv;
    if (m->nv + 4 > E3_MAXV) bb_raise(5, NULL);
    mdl_vtx3(m, x0, 1, z0); mdl_vtx3(m, x1, 1, z0); mdl_vtx3(m, x1, 1, z1); mdl_vtx3(m, x0, 1, z1);
    mdl_face3(m, col, col, 4, b + 0, b + 1, b + 2, b + 3, 0, -10, 0);
}

static int32_t model_radius(E3Model *m)
{
    int32_t i;
    uint32_t best = 0;
    if (m->radius >= 0) return m->radius;
    for (i = 0; i < m->nv; i++) {
        uint32_t d = (uint32_t)(m->v[i][0] * m->v[i][0]) + (uint32_t)(m->v[i][1] * m->v[i][1]) + (uint32_t)(m->v[i][2] * m->v[i][2]);
        if (d > best) best = d;
    }
    m->radius = (int32_t)a3_isqrt(best) + 1;
    return m->radius;
}

/* rotation matrices, 16.16 (amiga3d's a3_rot_yaw / a3_rot_ypr) */
static void rot_yaw(int32_t m[9], int yaw)
{
    int32_t c = a3_cos(yaw), s = a3_sin(yaw);
    m[0] = c;  m[1] = 0;     m[2] = s;
    m[3] = 0;  m[4] = 65536; m[5] = 0;
    m[6] = -s; m[7] = 0;     m[8] = c;
}

static void rot_ypr(int32_t m[9], int yaw, int pitch, int roll)
{
    int32_t cy = a3_cos(yaw) >> 4, sy = a3_sin(yaw) >> 4, cp = a3_cos(pitch) >> 4, sp = a3_sin(pitch) >> 4;
    int32_t cr = a3_cos(roll) >> 4, sr = a3_sin(roll) >> 4;
    int32_t a00 = cr, a01 = -sr, a10 = (cp * sr) >> 12, a11 = (cp * cr) >> 12, a12 = -sp;
    int32_t a20 = (sp * sr) >> 12, a21 = (sp * cr) >> 12, a22 = cp;
    m[0] = (cy * a00 + sy * a20) >> 8;  m[1] = (cy * a01 + sy * a21) >> 8;  m[2] = (sy * a22) >> 8;
    m[3] = a10 << 4;                     m[4] = a11 << 4;                     m[5] = a12 << 4;
    m[6] = (-sy * a00 + cy * a20) >> 8; m[7] = (-sy * a01 + cy * a21) >> 8; m[8] = (cy * a22) >> 8;
}

/* amiga3d's a3_model, with the engine's camera c (a cam_for copy or the camera itself) */
static void e_model(bb_e3d *e, const Cam *c, E3Model *m, int32_t wx, int32_t wy, int32_t wz, const int32_t *rot,
                    int32_t blit, int32_t bshade, int has_body, int32_t flash, int32_t depth_bias)
{
    V3 ctr, *cv = e->mv;
    int32_t depth, i, k, nvis = 0;

    xform(&e->cam, c, wx, wy, wz, &ctr);
    {
        int32_t mg = e->margin * CAM_U(c);
        if (ctr.z < -mg || ctr.x > ctr.z + mg || ctr.x < -ctr.z - mg) return;
    }
    for (i = 0; i < m->nv; i++) {
        int32_t x = m->v[i][0], y = m->v[i][1], z = m->v[i][2];
        if (rot) {
            int32_t rx = (x * rot[0] + y * rot[1] + z * rot[2]) >> 16;
            int32_t ry = (x * rot[3] + y * rot[4] + z * rot[5]) >> 16;
            int32_t rz = (x * rot[6] + y * rot[7] + z * rot[8]) >> 16;
            x = rx; y = ry; z = rz;
        }
        e->wv[i][0] = x; e->wv[i][1] = y; e->wv[i][2] = z;
        xform(&e->cam, c, wx + x, wy + y, wz + z, &cv[i]);
    }
    for (k = 0; k < m->nf; k++) {
        const E3Face *f = &m->f[k];
        const V3 *a = &cv[f->idx[0]], *b = &cv[f->idx[1]], *d = &cv[f->idx[2]];
        int32_t ux = b->x - a->x, uy = b->y - a->y, uz = b->z - a->z;
        int32_t vx = d->x - a->x, vy = d->y - a->y, vz = d->z - a->z;
        int64_t nx = (int64_t)uy * vz - (int64_t)uz * vy, ny = (int64_t)uz * vx - (int64_t)ux * vz, nz = (int64_t)ux * vy - (int64_t)uy * vx;
        if (nx * a->x + ny * a->y + nz * a->z >= 0) continue;
        depth = a->z + b->z + d->z + (f->n == 4 ? cv[f->idx[3]].z : d->z);
        if (m->v[f->idx[0]][1] == 1 && m->v[f->idx[1]][1] == 1 && m->v[f->idx[2]][1] == 1)
            depth = 0x7FFFFFFF;
        for (i = nvis; i > 0 && e->vis_depth[i - 1] < depth; i--) {
            e->vis_face[i] = e->vis_face[i - 1];
            e->vis_depth[i] = e->vis_depth[i - 1];
        }
        e->vis_face[i] = k;
        e->vis_depth[i] = depth;
        nvis++;
    }
    depth = ctr.z - depth_bias * CAM_U(c);
    for (i = 0; i < nvis; i++) {
        const E3Face *f = &m->f[e->vis_face[i]];
        V3 q[4];
        int32_t col = e->shading ? f->lit : f->col;
        int grad = 0;
        double nx = 0, ny = 0, nz = 0;
        q[0] = cv[f->idx[0]]; q[1] = cv[f->idx[1]]; q[2] = cv[f->idx[2]];
        if (f->n == 4) q[3] = cv[f->idx[3]];
        if (col >= E3_COL_FLASH && col < E3_COL_FLASH + 10) col = flash;
        else if (col >= E3_COL_BODY && col < E3_COL_BODY + 2) col = has_body ? (col == E3_COL_BODY ? blit : bshade) : 3;
        if (e->shading) {
            const int32_t *A = e->wv[f->idx[0]], *B = e->wv[f->idx[1]], *C = e->wv[f->idx[2]];
            double ux = B[0] - A[0], uy = B[1] - A[1], uz = B[2] - A[2];
            double vx = C[0] - A[0], vy = C[1] - A[1], vz = C[2] - A[2];
            nx = uy * vz - uz * vy; ny = uz * vx - ux * vz; nz = ux * vy - uy * vx;
        }
        e_poly(e, c, depth, face_col(e, c, col, e->shading, nx, ny, nz, depth, &grad), grad, q, f->n);
    }
}

/* draw model m at a whole-unit (f16 0) or 16.16 (f16 1) position, rotated by the angles */
static void draw_model(bb_e3d *e, int32_t mid, int32_t x, int32_t y, int32_t z, int f16, int32_t yaw, int32_t pitch,
                       int32_t roll, const int32_t *mat, int32_t blit, int32_t bshade, int has_body, int32_t flash, int32_t bias)
{
    E3Model *m = get_model(e, mid);
    int32_t rot[9];
    const int32_t *r = mat;
    Cam tc;
    const Cam *c = &e->cam.c;
    if (!r && ((yaw | pitch | roll) & 0xFFFF)) {
        if ((pitch | roll) & 0xFFFF) rot_ypr(rot, yaw, pitch, roll); else rot_yaw(rot, yaw);
        r = rot;
    }
    if (f16) {
        cam_for(c, x, y, z, &tc);
        c = &tc;
        x >>= 16; y >>= 16; z >>= 16;
    }
    e_model(e, c, m, x, y, z, r, blit, bshade, has_body, flash, bias);
}

/* model files: v / f / box / pyramid / prism / shadow / face lines */
static int32_t pen_word(const char *w)
{
    if (!strcasecmp(w, "body") || !strcasecmp(w, "lit")) return E3_COL_BODY;
    if (!strcasecmp(w, "shade")) return E3_COL_BODY + 1;
    if (!strcasecmp(w, "flash")) return E3_COL_FLASH;
    return (int32_t)strtol(w, NULL, 0);
}

static int32_t model_load(bb_e3d *e, const char *path)
{
    FILE *f = fopen(path, "r");
    char line[512];
    int32_t id;
    E3Model *m;
    if (!f) bb_raise(53, NULL);
    id = model_new(e);
    m = e->models[id - 1];
    while (fgets(line, sizeof line, f)) {
        char *w[16], *p = line, *h = strchr(line, '#');
        int n = 0;
        int32_t a[16];
        int i;
        if (h) *h = 0;
        while (n < 16) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            w[n++] = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) *p++ = 0;
        }
        if (!n) continue;
        for (i = 1; i < n; i++) a[i] = pen_word(w[i]);
        if (!strcasecmp(w[0], "v") && n >= 4) mdl_vtx3(m, a[1], a[2], a[3]);
        else if (!strcasecmp(w[0], "f") && (n == 5 || n == 6)) mdl_face_raw(m, a[1], n - 2, &a[2]);
        else if (!strcasecmp(w[0], "box") && n >= 9) mdl_box3(m, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]);
        else if (!strcasecmp(w[0], "pyramid") && n >= 9) mdl_pyramid3(m, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]);
        else if (!strcasecmp(w[0], "prism") && n >= 7) mdl_prism3(m, a[1], a[2], a[3], a[4], a[5], a[6], n >= 8 ? !a[7] : 1);
        else if (!strcasecmp(w[0], "shadow") && n >= 6) mdl_shadow3(m, a[1], a[2], a[3], a[4], a[5]);
        else if (!strcasecmp(w[0], "face") && n >= 11) mdl_face3(m, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10]);
        else { fclose(f); m->used = 0; bb_raise(5, NULL); }
    }
    fclose(f);
    return id;
}

/* ---------------------------------------------------------------- grids */

static E3Grid *get_grid(bb_e3d *e, int32_t g)
{
    if (g < 1 || g > e->ngrids || !e->grids[g - 1].used) bb_raise(380, NULL);
    return &e->grids[g - 1];
}

static int32_t grid_new(bb_e3d *e, int32_t w, int32_t h, int32_t cell, int32_t x0, int32_t z0)
{
    E3Grid *g;
    int32_t i;
    if (w < 2 || h < 2 || w > 1025 || h > 1025 || cell < 1) bb_raise(5, NULL);
    for (i = 0; i < e->ngrids; i++) if (!e->grids[i].used) break;
    if (i == e->ngrids) {
        E3Grid *ng = (E3Grid *)realloc(e->grids, sizeof(E3Grid) * (size_t)(e->ngrids + 1));
        if (!ng) bb_raise(7, NULL);
        e->grids = ng;
        e->ngrids++;
    }
    g = &e->grids[i];
    memset(g, 0, sizeof *g);
    g->hgt = (int32_t *)calloc((size_t)w * (size_t)h, 4);
    g->xf = (V3 *)malloc(sizeof(V3) * (size_t)w * (size_t)h);
    if (!g->hgt || !g->xf) { free(g->hgt); free(g->xf); bb_raise(7, NULL); }
    g->used = 1;
    g->w = w; g->h = h; g->cell = cell; g->x0 = x0; g->z0 = z0;
    g->shade = 1;
    return i + 1;
}

static void grid_free(E3Grid *g)
{
    free(g->hgt); free(g->pen); free(g->xf);
    memset(g, 0, sizeof *g);
}

/* height at a 16.16 world point, 16.16, bilinear between the four corners */
static int32_t grid_height16(const E3Grid *g, int32_t x, int32_t z)
{
    int64_t gx = ((int64_t)x - ((int64_t)g->x0 << 16)) / g->cell, gz = ((int64_t)z - ((int64_t)g->z0 << 16)) / g->cell;
    int32_t i, j, fx, fz, h00, h10, h01, h11;
    int64_t top, bot;
    if (gx < 0) gx = 0;
    if (gz < 0) gz = 0;
    if (gx > ((int64_t)(g->w - 1) << 16)) gx = (int64_t)(g->w - 1) << 16;
    if (gz > ((int64_t)(g->h - 1) << 16)) gz = (int64_t)(g->h - 1) << 16;
    i = (int32_t)(gx >> 16); j = (int32_t)(gz >> 16);
    fx = (int32_t)(gx & 0xFFFF); fz = (int32_t)(gz & 0xFFFF);
    if (i >= g->w - 1) { i = g->w - 2; fx = 65536; }
    if (j >= g->h - 1) { j = g->h - 2; fz = 65536; }
    h00 = g->hgt[j * g->w + i]; h10 = g->hgt[j * g->w + i + 1];
    h01 = g->hgt[(j + 1) * g->w + i]; h11 = g->hgt[(j + 1) * g->w + i + 1];
    top = ((int64_t)h00 << 16) + (int64_t)(h10 - h00) * fx;
    bot = ((int64_t)h01 << 16) + (int64_t)(h11 - h01) * fx;
    return (int32_t)(top + (((bot - top) * fz) >> 16));
}

/* diamond-square on a (2^k + 1) square, sampled into the grid */
static void grid_generate(E3Grid *g, uint32_t seed, int32_t rough, int32_t height)
{
    int32_t n = 2, N, step, x, y, amp;
    int32_t *t;
    while (n + 1 < g->w || n + 1 < g->h) n *= 2;
    N = n + 1;
    t = (int32_t *)calloc((size_t)N * (size_t)N, 4);
    if (!t) bb_raise(7, NULL);
#define T(xx, yy) t[(yy) * N + (xx)]
#define RND(xx, yy) ((int32_t)(a3_hash(seed * 2654435761u + (uint32_t)((yy) * N + (xx))) & 0xFFFF) - 32768)
    amp = height;
    T(0, 0) = (int32_t)(((int64_t)RND(0, 0) * amp) >> 16);
    T(n, 0) = (int32_t)(((int64_t)RND(n, 0) * amp) >> 16);
    T(0, n) = (int32_t)(((int64_t)RND(0, n) * amp) >> 16);
    T(n, n) = (int32_t)(((int64_t)RND(n, n) * amp) >> 16);
    for (step = n; step > 1; step /= 2) {
        int32_t hs = step / 2;
        amp = (int32_t)(((int64_t)amp * rough) >> 8);
        for (y = hs; y < N; y += step)
            for (x = hs; x < N; x += step) {
                int32_t avg = (T(x - hs, y - hs) + T(x + hs, y - hs) + T(x - hs, y + hs) + T(x + hs, y + hs)) / 4;
                T(x, y) = avg + (int32_t)(((int64_t)RND(x, y) * amp) >> 15);
            }
        for (y = 0; y < N; y += hs)
            for (x = (y / hs) % 2 ? 0 : hs; x < N; x += step) {
                int32_t s = 0, c = 0;
                if (x >= hs) { s += T(x - hs, y); c++; }
                if (x + hs < N) { s += T(x + hs, y); c++; }
                if (y >= hs) { s += T(x, y - hs); c++; }
                if (y + hs < N) { s += T(x, y + hs); c++; }
                T(x, y) = s / c + (int32_t)(((int64_t)RND(x, y) * amp) >> 15);
            }
    }
    for (y = 0; y < g->h; y++)
        for (x = 0; x < g->w; x++) g->hgt[y * g->w + x] = T(x, y);
#undef T
#undef RND
    free(t);
}

static int32_t grid_cell_pen(const E3Grid *g, int32_t i, int32_t j, int32_t avg)
{
    if (g->pen) return g->pen[j * (g->w - 1) + i];
    if (g->bypen) {
        if (avg <= g->water) return g->wpen;
        if (avg >= g->snow) return g->spen;
        return avg < (g->water + g->snow) / 2 ? g->lpen : g->hpen;
    }
    return 2;
}

static void draw_grid(bb_e3d *e, E3Grid *g, int32_t range, int32_t bias)
{
    const Cam *c = &e->cam.c;
    int32_t i0 = 0, j0 = 0, i1 = g->w - 1, j1 = g->h - 1, i, j;
    int32_t camx = c->x, camz = c->z, cu = CAM_U(c);
    if (range > 0) {
        i0 = (camx - range - g->x0) / g->cell; i1 = (camx + range - g->x0) / g->cell + 1;
        j0 = (camz - range - g->z0) / g->cell; j1 = (camz + range - g->z0) / g->cell + 1;
        if (i0 < 0) i0 = 0;
        if (j0 < 0) j0 = 0;
        if (i1 > g->w - 1) i1 = g->w - 1;
        if (j1 > g->h - 1) j1 = g->h - 1;
        if (i0 >= i1 || j0 >= j1) return;
    }
    for (j = j0; j <= j1; j++)
        for (i = i0; i <= i1; i++) {
            int32_t y = g->hgt[j * g->w + i];
            if (g->bypen && y < g->water) y = g->water;
            xform(&e->cam, c, g->x0 + i * g->cell, y, g->z0 + j * g->cell, &g->xf[j * g->w + i]);
        }
    for (j = j0; j < j1; j++)
        for (i = i0; i < i1; i++) {
            V3 q[4], t[3];
            int32_t ha = g->hgt[j * g->w + i], hb = g->hgt[j * g->w + i + 1];
            int32_t hc = g->hgt[(j + 1) * g->w + i + 1], hd = g->hgt[(j + 1) * g->w + i];
            int32_t pen, depth, nz = CAM_NEAR(c);
            int grad = 0;
            uint32_t col;
            q[0] = g->xf[j * g->w + i]; q[1] = g->xf[(j + 1) * g->w + i];
            q[2] = g->xf[(j + 1) * g->w + i + 1]; q[3] = g->xf[j * g->w + i + 1];
            if (q[0].z < nz && q[1].z < nz && q[2].z < nz && q[3].z < nz) continue;
            if (q[0].x > q[0].z && q[1].x > q[1].z && q[2].x > q[2].z && q[3].x > q[3].z) continue;
            if (q[0].x < -q[0].z && q[1].x < -q[1].z && q[2].x < -q[2].z && q[3].x < -q[3].z) continue;
            if (g->bypen) {
                if (ha < g->water) ha = g->water;
                if (hb < g->water) hb = g->water;
                if (hc < g->water) hc = g->water;
                if (hd < g->water) hd = g->water;
            }
            pen = grid_cell_pen(g, i, j, (ha + hb + hc + hd) / 4);
            depth = (q[0].z + q[1].z + q[2].z + q[3].z) / 4 - bias * cu;
            if (ha + hc == hb + hd || !g->shade) {
                /* planar: one quad; normal of (dx, dy, dz) slopes */
                double s = g->cell;
                int save = e->shading;
                e->shading = g->shade;
                col = face_col(e, c, pen, g->shade, -(double)(hb - ha + hc - hd) * s * 0.5, s * s,
                               -(double)(hd - ha + hc - hb) * s * 0.5, depth, &grad);
                e->shading = save;
                e_poly(e, c, depth, col, grad, q, 4);
            } else {
                /* two triangles a-d-c and a-c-b (corners: a (i,j), b (i+1,j), c (i+1,j+1), d (i,j+1)) */
                double s = g->cell;
                int save = e->shading;
                e->shading = 1;
                t[0] = q[0]; t[1] = q[1]; t[2] = q[2];
                grad = 0;
                col = face_col(e, c, pen, 1, -(double)(hc - hd) * s, s * s, -(double)(hd - ha) * s, depth, &grad);
                e_poly(e, c, depth, col, grad, t, 3);
                t[0] = q[0]; t[1] = q[2]; t[2] = q[3];
                grad = 0;
                col = face_col(e, c, pen, 1, -(double)(hb - ha) * s, s * s, -(double)(hc - hb) * s, depth, &grad);
                e_poly(e, c, depth, col, grad, t, 3);
                e->shading = save;
            }
        }
}

/* ---------------------------------------------------------------- text and 2D */

static void text16(bb_e3d *e, int32_t x, int32_t y, const char *s, uint32_t col, int32_t scale)
{
    int32_t S = e->sub, cell = 8 * scale * S;          /* the cell in the drawing's pixels */
    int32_t px = x * S, py = y * S;
    for (; *s; s++, px += cell) {
        int ch = (unsigned char)*s, r, b;
        const uint16_t *gl;
        if (ch < 32 || ch > 126) ch = '?';
        gl = a3_font16[ch - 32];
        if (cell >= 16 && cell % 16 == 0) {
            int32_t k = cell / 16;
            for (r = 0; r < 16; r++) {
                uint16_t bits = gl[r];
                int32_t rr;
                if (!bits) continue;
                for (b = 0; b < 16; b++)
                    if (bits & (0x8000 >> b)) {
                        int e2 = b;
                        while (e2 < 15 && (bits & (0x8000 >> (e2 + 1)))) e2++;
                        for (rr = 0; rr < k; rr++) tspan(e, py + r * k + rr, px + b * k, px + e2 * k + k - 1, col);
                        b = e2;
                    }
            }
        } else {
            /* other sizes: each target pixel from the font pixels it covers (set when at
             * least half of them are) */
            int32_t ty, tx;
            for (ty = 0; ty < cell; ty++) {
                int32_t r0 = ty * 16 / cell, r1 = ((ty + 1) * 16 - 1) / cell;
                for (tx = 0; tx < cell; tx++) {
                    int32_t c0 = tx * 16 / cell, c1 = ((tx + 1) * 16 - 1) / cell, on = 0, tot = 0, rr, cc;
                    for (rr = r0; rr <= r1; rr++)
                        for (cc = c0; cc <= c1; cc++) { tot++; if (gl[rr] & (0x8000 >> cc)) on++; }
                    if (on * 2 >= tot && on) tspan(e, py + ty, px + tx, px + tx, col);
                }
            }
        }
    }
}

static void fill_rect_e(bb_e3d *e, int32_t x0, int32_t y0, int32_t x1, int32_t y1, uint32_t col, int grad)
{
    int32_t S = e->sub, y;
    if (x0 > x1) { int32_t t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { int32_t t = y0; y0 = y1; y1 = t; }
    for (y = y0 * S; y <= y1 * S + S - 1; y++) tspan(e, y, x0 * S, x1 * S + S - 1, grad ? sky_at(e, y, col) : col);
}

/* ---------------------------------------------------------------- the object */

enum {
    M_ATTACH = 1, M_VIEW, M_VIEWORIGIN, P_SUB, M_PALETTE, M_PALETTE12, P_PEN, M_PENCOLOR, M_SKYGRADIENT, M_CLEAR, P_FAR,
    M_CAMPOS, M_CAMPLACE, M_CAMANGLES, M_CAMLOOKAT, P_CAMX, P_CAMY, P_CAMZ, P_CAMYAW, P_CAMPITCH, P_CAMROLL,
    P_CAMU, P_CAMNEAR, P_HORIZON, M_CAMSAVE, M_CAMLOAD, M_XFORM, M_XFORMMANY, M_PROJECT, M_PROJECTCAM, M_VISIBLE,
    M_BEGIN, M_POLY, M_QUAD, M_POLYW, M_QUADW, M_QUADSW, M_SPOT, M_STAR, M_LINE3D, M_LINES3D, M_POINTS, M_FLUSH,
    P_NPOLYS, P_DROPPED,
    M_MODELNEW, M_MDLVTX, M_MDLFACE, M_MDLBOX, M_MDLPYRAMID, M_MDLPRISM, M_MDLSHADOW, M_MODELFROMARRAYS, M_MODELLOAD,
    M_MODELFREE, M_MODELCLEAR, M_MODELVERTS, M_MODELFACES, M_MODELRADIUS, M_DRAWMODEL, M_DRAWMODELF, M_DRAWMODELM,
    M_DRAWMODELS,
    M_GRIDNEW, M_GRIDSET, M_GRIDHEIGHTSET, M_GRIDPENSET, M_GRIDHEIGHT, M_GRIDHEIGHTF, M_GRIDGENERATE, M_GRIDCOLOURS,
    M_DRAWGRID, M_GRIDFREE, M_GRIDSHADE,
    P_SHADING, M_LIGHT, M_FOG,
    M_TEXT, M_TEXTSHADOW, M_TEXTCENTRE, M_TEXTWIDTH, M_SPAN, M_FILLRECT, M_POLYFILL, M_BLEND,
    M_SIN, M_COS, M_ATAN2, M_ISQRT, M_HYPOT, M_HASH, M_RAND, M_FMUL, M_FDIV, M_FSQRT, M_ROTYPR, M_ROTYAW, M_MATMUL,
    M_MATAPPLY, M_SINTABLE, M_COSTABLE, M_CAMSET, P_MODELMARGIN, P_QUADBIAS, M_DRAWLINE3D, M_FILLGRADIENT, M_DRAWMODELMF, M_CAMBANK
};

static const struct { const char *name; int32_t id; } members[] = {
    {"Attach", M_ATTACH}, {"View", M_VIEW}, {"ViewOrigin", M_VIEWORIGIN}, {"Sub", P_SUB}, {"Palette", M_PALETTE},
    {"Palette12", M_PALETTE12}, {"Pen", P_PEN}, {"PenColor", M_PENCOLOR}, {"PenColour", M_PENCOLOR},
    {"SkyGradient", M_SKYGRADIENT}, {"Clear", M_CLEAR}, {"Far", P_FAR},
    {"CamPos", M_CAMPOS}, {"CamPlace", M_CAMPLACE}, {"CamAngles", M_CAMANGLES}, {"CamLookAt", M_CAMLOOKAT},
    {"CamX", P_CAMX}, {"CamY", P_CAMY}, {"CamZ", P_CAMZ}, {"CamYaw", P_CAMYAW}, {"CamPitch", P_CAMPITCH},
    {"CamRoll", P_CAMROLL}, {"CamU", P_CAMU}, {"CamNear", P_CAMNEAR}, {"Horizon", P_HORIZON},
    {"CamSave", M_CAMSAVE}, {"CamLoad", M_CAMLOAD}, {"Xform", M_XFORM}, {"XformMany", M_XFORMMANY},
    {"Project", M_PROJECT}, {"ProjectCam", M_PROJECTCAM}, {"Visible", M_VISIBLE},
    {"Begin", M_BEGIN}, {"Poly", M_POLY}, {"Quad", M_QUAD}, {"PolyW", M_POLYW}, {"QuadW", M_QUADW},
    {"QuadsW", M_QUADSW}, {"Spot", M_SPOT}, {"Star", M_STAR}, {"Line3D", M_LINE3D}, {"Lines3D", M_LINES3D},
    {"Points", M_POINTS}, {"Flush", M_FLUSH}, {"NPolys", P_NPOLYS}, {"Dropped", P_DROPPED},
    {"ModelNew", M_MODELNEW}, {"MdlVtx", M_MDLVTX}, {"MdlFace", M_MDLFACE}, {"MdlBox", M_MDLBOX},
    {"MdlPyramid", M_MDLPYRAMID}, {"MdlPrism", M_MDLPRISM}, {"MdlShadow", M_MDLSHADOW},
    {"ModelFromArrays", M_MODELFROMARRAYS}, {"ModelLoad", M_MODELLOAD}, {"ModelFree", M_MODELFREE},
    {"ModelClear", M_MODELCLEAR}, {"ModelVerts", M_MODELVERTS}, {"ModelFaces", M_MODELFACES},
    {"ModelRadius", M_MODELRADIUS}, {"DrawModel", M_DRAWMODEL}, {"DrawModelF", M_DRAWMODELF},
    {"DrawModelM", M_DRAWMODELM}, {"DrawModels", M_DRAWMODELS},
    {"GridNew", M_GRIDNEW}, {"GridSet", M_GRIDSET}, {"GridHeightSet", M_GRIDHEIGHTSET}, {"GridPenSet", M_GRIDPENSET},
    {"GridHeight", M_GRIDHEIGHT}, {"GridHeightF", M_GRIDHEIGHTF}, {"GridGenerate", M_GRIDGENERATE},
    {"GridColours", M_GRIDCOLOURS}, {"GridColors", M_GRIDCOLOURS}, {"DrawGrid", M_DRAWGRID}, {"GridFree", M_GRIDFREE},
    {"GridShade", M_GRIDSHADE},
    {"Shading", P_SHADING}, {"Light", M_LIGHT}, {"Fog", M_FOG},
    {"Text", M_TEXT}, {"TextShadow", M_TEXTSHADOW}, {"TextCentre", M_TEXTCENTRE}, {"TextCenter", M_TEXTCENTRE},
    {"TextWidth", M_TEXTWIDTH}, {"Span", M_SPAN}, {"FillRect", M_FILLRECT}, {"PolyFill", M_POLYFILL}, {"Blend", M_BLEND},
    {"Sin", M_SIN}, {"Cos", M_COS}, {"Atan2", M_ATAN2}, {"ISqrt", M_ISQRT}, {"Hypot", M_HYPOT}, {"Hash", M_HASH},
    {"Rand", M_RAND}, {"FMul", M_FMUL}, {"FDiv", M_FDIV}, {"FSqrt", M_FSQRT}, {"RotYPR", M_ROTYPR},
    {"RotYaw", M_ROTYAW}, {"MatMul", M_MATMUL}, {"MatApply", M_MATAPPLY}, {"SinTable", M_SINTABLE},
    {"CosTable", M_COSTABLE}, {"CamSet", M_CAMSET}, {"ModelMargin", P_MODELMARGIN}, {"QuadBias", P_QUADBIAS},
    {"DrawLine3D", M_DRAWLINE3D}, {"FillGradient", M_FILLGRADIENT}, {"DrawModelMF", M_DRAWMODELMF},
    {"CamBank", M_CAMBANK},
};

static int32_t e3_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (strcasecmp(members[i].name, name) == 0) return members[i].id;
    return BB_NOMEMBER;
}

static void set_view(bb_e3d *e, int32_t vw, int32_t vh, int32_t cx, int32_t cy, int32_t fov)
{
    if (vw < 1 || vh < 1 || vw * e->sub > 4096 || vh * e->sub > SPAN_MAX) bb_raise(5, NULL);
    cam_view(&e->cam.c, vw, vh, cx, cy, fov);
}

static void palette(bb_e3d *e, int argc, bb_value *argv, int twelve)
{
    bb_array *a = arg_array(argc, argv, 0);
    int32_t first = argl_opt(argc, argv, 1, 0), i;
    for (i = 0; i < a->count && first + i < 256; i++) {
        int32_t v = elem_l(a, i);
        if (first + i < 0) continue;
        if (twelve) {
            uint32_t r = (v >> 8) & 15, g = (v >> 4) & 15, b = v & 15;
            e->pal[first + i] = 0xFF000000u | (r * 17) << 16 | (g * 17) << 8 | (b * 17);
        } else e->pal[first + i] = ARGB(v);
    }
}

static void set_light(bb_e3d *e, int32_t x, int32_t y, int32_t z)
{
    uint32_t len;
    while (x > 16383 || x < -16383 || y > 16383 || y < -16383 || z > 16383 || z < -16383) { x /= 2; y /= 2; z /= 2; }
    len = a3_isqrt((uint32_t)(x * x + y * y + z * z));
    if (!len) bb_raise(5, NULL);
    e->lix = (int32_t)(((int64_t)x << 16) / len);
    e->liy = (int32_t)(((int64_t)y << 16) / len);
    e->liz = (int32_t)(((int64_t)z << 16) / len);
}

static void e3_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bb_e3d *e = (bb_e3d *)self;
    E3Cam *k = &e->cam;
    Cam *c = &k->c;
    int setting = (kind & (BB_INV_LET | BB_INV_SET)) != 0;
    bb_str *hold = NULL;
    int32_t w[3 * MAX_PV];

    switch (id) {
    /* ---- setup ---- */
    case M_ATTACH: {
        bb_obj *o = arg_obj(argc, argv, 0);
        if (!bb_is_canvas(o)) bb_raise(13, NULL);
        bb_obj_assign(&e->canvas, o);
        return;
    }
    case M_VIEW:
        set_view(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4));
        return;
    case M_VIEWORIGIN: e->ox = argl(argc, argv, 0); e->oy = argl(argc, argv, 1); return;
    case P_SUB:
        if (setting) {
            int32_t s = argl(argc, argv, argc - 1);
            if (s < 1 || s > 4 || c->vw * s > 4096 || c->vh * s > SPAN_MAX) bb_raise(380, NULL);
            e->sub = s;
        } else *ret = bb_v_long(e->sub);
        return;
    case M_PALETTE: palette(e, argc, argv, 0); return;
    case M_PALETTE12: palette(e, argc, argv, 1); return;
    case P_PEN: {
        int32_t i = argl(argc, argv, 0);
        if (i < 0 || i > 255) bb_raise(9, NULL);
        if (setting) e->pal[i] = ARGB(argl(argc, argv, argc - 1));
        else *ret = bb_v_long(VBCOL(e->pal[i]));
        return;
    }
    case M_PENCOLOR: {
        int32_t i = argl(argc, argv, 0);
        *ret = bb_v_long(i < 0 ? -1 - i : VBCOL(e->pal[i & 255]));
        return;
    }
    case M_SKYGRADIENT: {
        int32_t pen = argl(argc, argv, 0), rows = argl(argc, argv, 3), i, n;
        uint32_t top = ARGB(argl(argc, argv, 1)), bot = ARGB(argl(argc, argv, 2));
        e->sky_pen = pen;
        e->sky_rows = rows < 0 ? 0 : rows;
        n = e->sky_rows * e->sub;
        if (n > 1024) n = 1024;
        for (i = 0; i < 1024; i++) e->sky[i] = i < n ? mix_col(top, bot, n > 1 ? (i * 256) / (n - 1) : 0) : bot;
        if (e->sky_rows * e->sub > 1024) e->sky_rows = 1024 / e->sub;
        return;
    }
    case M_CLEAR: {
        int grad = 0;
        uint32_t col = pen_argb(e, argl(argc, argv, 0), &grad);
        if (!need_target(e)) return;
        fill_rect_e(e, 0, 0, c->vw - 1, c->vh - 1, col, grad);
        return;
    }
    case P_FAR: *ret = bb_v_long(e->far_z); return;

    /* ---- the camera ---- */
    case M_CAMPOS:
        c->x = argl(argc, argv, 0); c->y = argl(argc, argv, 1); c->z = argl(argc, argv, 2);
        c->qx = c->qy = c->qz = 0;
        c->precise = 0;
        return;
    case M_CAMPLACE: cam_place(c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2)); return;
    case M_CAMANGLES:
        c->yaw = argl(argc, argv, 0) & 0xFFFF;
        c->pitch = argl(argc, argv, 1) & 0xFFFF;
        k->roll = argl_opt(argc, argv, 2, 0) & 0xFFFF;
        cam_trig(k);
        return;
    case M_CAMLOOKAT: {
        int32_t dx = argl(argc, argv, 0) - c->x, dy = argl(argc, argv, 1) - c->y, dz = argl(argc, argv, 2) - c->z;
        c->yaw = a3_atan2(dx, dz);
        c->pitch = a3_atan2(-dy, a3_hypot(dx, dz)) & 0xFFFF;
        cam_trig(k);
        return;
    }
    case P_CAMX: case P_CAMY: case P_CAMZ: {
        int32_t *p = id == P_CAMX ? &c->x : id == P_CAMY ? &c->y : &c->z;
        if (setting) *p = argl(argc, argv, argc - 1); else *ret = bb_v_long(*p);
        return;
    }
    case P_CAMYAW: case P_CAMPITCH: case P_CAMROLL: {
        int32_t *p = id == P_CAMYAW ? (int32_t *)&c->yaw : id == P_CAMPITCH ? (int32_t *)&c->pitch : &k->roll;
        if (setting) { *p = argl(argc, argv, argc - 1) & 0xFFFF; cam_trig(k); }
        else *ret = bb_v_long(*p);
        return;
    }
    case M_CAMSET:
        /* the whole amiga3d camera at once: x, y, z, yaw, pitch [, qx, qy, qz (precise) [, roll]] */
        c->x = argl(argc, argv, 0); c->y = argl(argc, argv, 1); c->z = argl(argc, argv, 2);
        if (!missing(argc, argv, 5)) {
            c->qx = argl(argc, argv, 5); c->qy = argl_opt(argc, argv, 6, 0); c->qz = argl_opt(argc, argv, 7, 0);
            c->precise = 1;
        } else { c->qx = c->qy = c->qz = 0; c->precise = 0; }
        c->yaw = argl(argc, argv, 3) & 0xFFFF;
        c->pitch = argl(argc, argv, 4) & 0xFFFF;
        k->roll = argl_opt(argc, argv, 8, 0) & 0xFFFF;
        cam_trig(k);
        return;
    case M_CAMBANK: {
        /* the camera's bank from its 16.16 cosine and sine, turning camera space as
         * x' = x cos - y sin, y' = x sin + y cos (ace_pilot2's render.c xf); sin 0 = no bank */
        int32_t cs = argl(argc, argv, 0), sn = argl(argc, argv, 1);
        k->cr = cs >> 4;
        k->sr = -(sn >> 4);
        k->rolled = sn != 0;
        k->roll = 0;
        return;
    }
    case P_MODELMARGIN: case P_QUADBIAS: {
        int32_t *p = id == P_MODELMARGIN ? &e->margin : &e->quad_bias;
        if (setting) *p = argl(argc, argv, argc - 1); else *ret = bb_v_long(*p);
        return;
    }
    case M_DRAWLINE3D: {
        /* a world line drawn now (not in the list): near-plane cut, clipped to the 3D area */
        V3 a, b;
        int grad = 0;
        uint32_t col;
        int32_t i;
        for (i = 0; i < 6; i++) w[i] = argl(argc, argv, i);
        col = pen_argb(e, argl(argc, argv, 6), &grad);
        xform(k, c, w[0], w[1], w[2], &a);
        xform(k, c, w[3], w[4], w[5], &b);
        if (need_target(e)) {
            int32_t o[4];
            if (clip_line(e, &a, &b, o)) raster_line(e, o[0], o[1], o[2], o[3], col);
        }
        return;
    }
    case P_CAMU: *ret = bb_v_long(CAM_U(c)); return;
    case P_CAMNEAR: *ret = bb_v_long(CAM_NEAR(c)); return;
    case P_HORIZON:
        *ret = bb_v_long((c->cp >> 4) ? cam_horizon(c) : (c->sp > 0 ? -32768 : 32767));
        return;
    case M_CAMSAVE: case M_CAMLOAD: {
        int32_t n = argl(argc, argv, 0);
        if (n < 0 || n >= E3_NCAM) bb_raise(9, NULL);
        if (id == M_CAMSAVE) e->saved[n] = *k; else *k = e->saved[n];
        return;
    }
    case M_XFORM: {
        V3 o;
        xform(k, c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), &o);
        if (argc < 6) bb_raise(450, NULL);
        store_l(&argv[3], o.x); store_l(&argv[4], o.y); store_l(&argv[5], o.z);
        return;
    }
    case M_XFORMMANY: {
        int32_t n = argl(argc, argv, 0), i;
        bb_array *ax = arg_array(argc, argv, 1), *ay = arg_array(argc, argv, 2), *az = arg_array(argc, argv, 3);
        bb_long *ox, *oy, *oz;
        if (n < 0 || n > ax->count || n > ay->count || n > az->count) bb_raise(9, NULL);
        ox = out_arr(argc, argv, 4, n); oy = out_arr(argc, argv, 5, n); oz = out_arr(argc, argv, 6, n);
        for (i = 0; i < n; i++) {
            V3 o;
            xform(k, c, elem_l(ax, i), elem_l(ay, i), elem_l(az, i), &o);
            ox[i] = o.x; oy[i] = o.y; oz[i] = o.z;
        }
        return;
    }
    case M_PROJECT: case M_PROJECTCAM: {
        V3 o;
        int32_t sx, sy;
        if (argc < 5) bb_raise(450, NULL);
        if (id == M_PROJECT) xform(k, c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), &o);
        else { o.x = argl(argc, argv, 0); o.y = argl(argc, argv, 1); o.z = argl(argc, argv, 2); }
        if (o.z < CAM_NEAR(c)) { *ret = bb_v_bool(0); return; }
        cam_project(c, &o, &sx, &sy);
        store_l(&argv[3], sx); store_l(&argv[4], sy);
        *ret = bb_v_bool(1);
        return;
    }
    case M_VISIBLE: {
        V3 o;
        int64_t r, zr;
        xform(k, c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), &o);
        r = (int64_t)argl(argc, argv, 3) * CAM_U(c);
        zr = o.z + r;
        if (zr < CAM_NEAR(c)) { *ret = bb_v_bool(0); return; }
        if ((o.x - r) * c->fov > (int64_t)(c->vw - c->cx) * zr || (o.x + r) * c->fov < -(int64_t)c->cx * zr ||
            (o.y - r) * c->fov > (int64_t)c->cyc * zr || (o.y + r) * c->fov < -(int64_t)(c->vh - c->cyc) * zr) {
            *ret = bb_v_bool(0);
            return;
        }
        *ret = bb_v_bool(1);
        return;
    }

    /* ---- the draw list ---- */
    case M_BEGIN: e_begin(e, argl(argc, argv, 0)); return;
    case M_POLY: case M_POLYW: {
        int32_t depth = argl(argc, argv, 0), pen = argl(argc, argv, 1), n = argl(argc, argv, 5), i;
        int32_t xs[MAX_PV], ys[MAX_PV], zs[MAX_PV];
        if (n < 3 || n > MAX_PV) bb_raise(5, NULL);
        read_arr(arg_array(argc, argv, 2), n, xs);
        read_arr(arg_array(argc, argv, 3), n, ys);
        read_arr(arg_array(argc, argv, 4), n, zs);
        if (id == M_POLY) {
            V3 q[MAX_PV];
            int grad = 0;
            uint32_t col;
            for (i = 0; i < n; i++) { q[i].x = xs[i]; q[i].y = ys[i]; q[i].z = zs[i]; }
            col = face_col(e, c, pen, 0, 0, 0, 0, depth, &grad);
            e_poly(e, c, depth, col, grad, q, n);
        } else {
            for (i = 0; i < n; i++) { w[i * 3] = xs[i]; w[i * 3 + 1] = ys[i]; w[i * 3 + 2] = zs[i]; }
            e_poly_world(e, depth, pen, w, n, 0);
        }
        return;
    }
    case M_QUAD: {
        V3 q[4];
        int32_t depth = argl(argc, argv, 0), pen = argl(argc, argv, 1), i;
        int grad = 0;
        uint32_t col;
        for (i = 0; i < 4; i++) {
            q[i].x = argl(argc, argv, 2 + i * 3); q[i].y = argl(argc, argv, 3 + i * 3); q[i].z = argl(argc, argv, 4 + i * 3);
        }
        col = face_col(e, c, pen, 0, 0, 0, 0, depth, &grad);
        e_quad(e, c, depth, col, grad, q);
        return;
    }
    case M_QUADW: {
        int32_t depth = argl(argc, argv, 0), pen = argl(argc, argv, 1), i;
        for (i = 0; i < 12; i++) w[i] = argl(argc, argv, 2 + i);
        e_poly_world(e, depth, pen, w, 4, 1);
        return;
    }
    case M_QUADSW: {
        int32_t n = argl(argc, argv, 0), depth = argl(argc, argv, 1), i, j;
        many pens = arg_many(argc, argv, 2, 1);
        bb_array *co = arg_array(argc, argv, 3);
        int32_t first = argl_opt(argc, argv, 4, 0), q;
        if (n < 0 || first < 0 || (int64_t)(first + n) * 12 > co->count) bb_raise(9, NULL);
        for (i = 0; i < n; i++) {
            q = first + i;
            if (co->etype == BB_LONG) memcpy(w, (const bb_long *)co->data + q * 12, 48);
            else for (j = 0; j < 12; j++) w[j] = elem_l(co, q * 12 + j);
            e_poly_world(e, depth, many_at(&pens, q), w, 4, 1);
        }
        return;
    }
    case M_SPOT: case M_STAR: {
        V3 o, q[MAX_PV];
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), z = argl(argc, argv, 2);
        int32_t r = argl(argc, argv, 3) * CAM_U(c), pen = argl(argc, argv, 4), bias, i, n = 4;
        int grad = 0;
        xform(k, c, x, y, z, &o);
        if (o.z < CAM_NEAR(c) + r) return;
        if (id == M_SPOT) {
            bias = argl_opt(argc, argv, 5, 0);
            q[0].x = o.x - r; q[0].y = o.y - r;
            q[1].x = o.x + r; q[1].y = o.y - r;
            q[2].x = o.x + r; q[2].y = o.y + r;
            q[3].x = o.x - r; q[3].y = o.y + r;
        } else {
            int32_t pts = argl(argc, argv, 5), turn = argl(argc, argv, 6);
            bias = argl_opt(argc, argv, 7, 0);
            n = pts * 2;
            if (pts < 2 || n > MAX_PV) bb_raise(5, NULL);
            for (i = 0; i < n; i++) {
                int32_t a = i * (65536 / n) + turn, rr = (i & 1) ? r / 2 : r;
                q[i].x = o.x + (int32_t)(((int64_t)a3_sin(a) * rr) >> 16);
                q[i].y = o.y + (int32_t)(((int64_t)a3_cos(a) * rr) >> 16);
            }
        }
        for (i = 0; i < n; i++) q[i].z = o.z;
        e_poly(e, c, o.z + bias * CAM_U(c), face_col(e, c, pen, 0, 0, 0, 0, o.z, &grad), grad, q, n);
        return;
    }
    case M_LINE3D: case M_LINES3D: {
        int32_t n = 1, i, j;
        many pens;
        bb_array *co = NULL;
        int32_t bias = 0;
        if (id == M_LINES3D) {
            n = argl(argc, argv, 0);
            co = arg_array(argc, argv, 1);
            pens = arg_many(argc, argv, 2, 1);
            if (n < 0 || n * 6 > co->count) bb_raise(9, NULL);
        } else {
            for (j = 0; j < 6; j++) w[j] = argl(argc, argv, j);
            pens = arg_many(argc, argv, 6, 1);
            bias = argl_opt(argc, argv, 7, 0);
        }
        for (i = 0; i < n; i++) {
            V3 a, b;
            int grad = 0;
            if (co) for (j = 0; j < 6; j++) w[j] = elem_l(co, i * 6 + j);
            xform(k, c, w[0], w[1], w[2], &a);
            xform(k, c, w[3], w[4], w[5], &b);
            e_line(e, &a, &b, (a.z + b.z) / 2 - bias * CAM_U(c),
                   face_col(e, c, many_at(&pens, i), 0, 0, 0, 0, (a.z + b.z) / 2, &grad));
        }
        return;
    }
    case M_POINTS: {
        int32_t n = argl(argc, argv, 0), i, size = argl_opt(argc, argv, 5, 1), bias = argl_opt(argc, argv, 6, 0);
        bb_array *ax = arg_array(argc, argv, 1), *ay = arg_array(argc, argv, 2), *az = arg_array(argc, argv, 3);
        many pens = arg_many(argc, argv, 4, 1);
        if (n < 0 || n > ax->count || n > ay->count || n > az->count) bb_raise(9, NULL);
        for (i = 0; i < n; i++) e_point(e, elem_l(ax, i), elem_l(ay, i), elem_l(az, i), many_at(&pens, i), size, bias);
        return;
    }
    case M_FLUSH: e_flush(e); return;
    case P_NPOLYS: *ret = bb_v_long(e->npolys); return;
    case P_DROPPED: *ret = bb_v_long(e->dropped); return;

    /* ---- models ---- */
    case M_MODELNEW: *ret = bb_v_long(model_new(e)); return;
    case M_MDLVTX: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        if (m->nv >= E3_MAXV) bb_raise(5, NULL);
        *ret = bb_v_long(mdl_vtx3(m, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3)));
        return;
    }
    case M_MDLFACE: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        int32_t a[11], i;
        for (i = 1; i < 11; i++) a[i] = argl(argc, argv, i);
        if (a[3] != 3 && a[3] != 4) bb_raise(5, NULL);
        mdl_face3(m, a[1], a[2], a[3], a[4], a[5], a[6], a[3] == 4 ? a[7] : 0, a[8], a[9], a[10]);
        return;
    }
    case M_MDLBOX: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        mdl_box3(m, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4), argl(argc, argv, 5),
                 argl(argc, argv, 6), argl(argc, argv, 7), argl(argc, argv, 8));
        return;
    }
    case M_MDLPYRAMID: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        mdl_pyramid3(m, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4),
                     argl(argc, argv, 5), argl(argc, argv, 6), argl(argc, argv, 7), argl(argc, argv, 8));
        return;
    }
    case M_MDLPRISM: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        mdl_prism3(m, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4),
                   argl(argc, argv, 5), argl(argc, argv, 6), argl_opt(argc, argv, 7, 0) == 0);
        return;
    }
    case M_MDLSHADOW: {
        E3Model *m = get_model(e, argl(argc, argv, 0));
        mdl_shadow3(m, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4), argl(argc, argv, 5));
        return;
    }
    case M_MODELFROMARRAYS: {
        bb_array *vx = arg_array(argc, argv, 0), *vy = arg_array(argc, argv, 1), *vz = arg_array(argc, argv, 2);
        int32_t nv = argl(argc, argv, 3), nf = argl(argc, argv, 7), i, j, mid;
        bb_array *fn = arg_array(argc, argv, 4), *fi = arg_array(argc, argv, 5), *fc = arg_array(argc, argv, 6);
        E3Model *m;
        if (nv < 0 || nv > E3_MAXV || nf < 0 || nf > E3_MAXF || nv > vx->count || nv > vy->count || nv > vz->count ||
            nf > fn->count || nf * 4 > fi->count || nf > fc->count)
            bb_raise(9, NULL);
        mid = model_new(e);
        m = e->models[mid - 1];
        for (i = 0; i < nv; i++) mdl_vtx3(m, elem_l(vx, i), elem_l(vy, i), elem_l(vz, i));
        for (i = 0; i < nf; i++) {
            int32_t idx[4];
            for (j = 0; j < 4; j++) idx[j] = elem_l(fi, i * 4 + j);
            mdl_face_raw(m, elem_l(fc, i), elem_l(fn, i), idx);
        }
        *ret = bb_v_long(mid);
        return;
    }
    case M_MODELLOAD: {
        const char *p = arg_str(argc, argv, 0, &hold);
        int32_t mid;
        char path[1024];
        snprintf(path, sizeof path, "%s", p);
        bb_str_release(hold);
        mid = model_load(e, path);
        *ret = bb_v_long(mid);
        return;
    }
    case M_MODELFREE: get_model(e, argl(argc, argv, 0))->used = 0; return;
    case M_MODELCLEAR: { E3Model *m = get_model(e, argl(argc, argv, 0)); m->nv = m->nf = 0; m->radius = -1; return; }
    case M_MODELVERTS: *ret = bb_v_long(get_model(e, argl(argc, argv, 0))->nv); return;
    case M_MODELFACES: *ret = bb_v_long(get_model(e, argl(argc, argv, 0))->nf); return;
    case M_MODELRADIUS: *ret = bb_v_long(model_radius(get_model(e, argl(argc, argv, 0)))); return;
    case M_DRAWMODEL: case M_DRAWMODELF: {
        int has_body = !missing(argc, argv, 7);
        draw_model(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), id == M_DRAWMODELF,
                   argl_opt(argc, argv, 4, 0), argl_opt(argc, argv, 5, 0), argl_opt(argc, argv, 6, 0), NULL,
                   argl_opt(argc, argv, 7, 3), argl_opt(argc, argv, 8, argl_opt(argc, argv, 7, 3)), has_body,
                   argl_opt(argc, argv, 9, 1), argl_opt(argc, argv, 10, 0));
        return;
    }
    case M_DRAWMODELM: case M_DRAWMODELMF: {
        int32_t rot[9];
        int has_body = !missing(argc, argv, 5);
        read_arr(arg_array(argc, argv, 4), 9, rot);
        draw_model(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3),
                   id == M_DRAWMODELMF, 0, 0, 0, rot,
                   argl_opt(argc, argv, 5, 3), argl_opt(argc, argv, 6, argl_opt(argc, argv, 5, 3)), has_body,
                   argl_opt(argc, argv, 7, 1), argl_opt(argc, argv, 8, 0));
        return;
    }
    case M_DRAWMODELS: {
        int32_t n = argl(argc, argv, 0), i, f16 = argl_opt(argc, argv, 6, 0) != 0;
        many ids = arg_many(argc, argv, 1, 1), yaws = arg_many(argc, argv, 5, 0);
        many lits = arg_many(argc, argv, 7, 3), shades = arg_many(argc, argv, 8, -1), biases = arg_many(argc, argv, 9, 0);
        int has_body = !missing(argc, argv, 7);
        bb_array *ax = arg_array(argc, argv, 2), *ay = arg_array(argc, argv, 3), *az = arg_array(argc, argv, 4);
        if (n < 0 || n > ax->count || n > ay->count || n > az->count) bb_raise(9, NULL);
        for (i = 0; i < n; i++)
        {
            int32_t lit = many_at(&lits, i), sh = shades.a || !missing(argc, argv, 8) ? many_at(&shades, i) : lit;
            draw_model(e, many_at(&ids, i), elem_l(ax, i), elem_l(ay, i), elem_l(az, i), f16, many_at(&yaws, i), 0, 0, NULL,
                       lit, sh, has_body, 1, many_at(&biases, i));
        }
        return;
    }

    /* ---- grids ---- */
    case M_GRIDNEW:
        *ret = bb_v_long(grid_new(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl_opt(argc, argv, 3, 0),
                                  argl_opt(argc, argv, 4, 0)));
        return;
    case M_GRIDSET: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        read_arr(arg_array(argc, argv, 1), g->w * g->h, g->hgt);
        if (!missing(argc, argv, 2)) {
            if (!g->pen) g->pen = (int32_t *)calloc((size_t)(g->w - 1) * (size_t)(g->h - 1), 4);
            if (!g->pen) bb_raise(7, NULL);
            read_arr(arg_array(argc, argv, 2), (g->w - 1) * (g->h - 1), g->pen);
        }
        return;
    }
    case M_GRIDHEIGHTSET: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        int32_t i = argl(argc, argv, 1), j = argl(argc, argv, 2);
        if (i < 0 || j < 0 || i >= g->w || j >= g->h) bb_raise(9, NULL);
        g->hgt[j * g->w + i] = argl(argc, argv, 3);
        return;
    }
    case M_GRIDPENSET: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        int32_t i = argl(argc, argv, 1), j = argl(argc, argv, 2);
        if (i < 0 || j < 0 || i >= g->w - 1 || j >= g->h - 1) bb_raise(9, NULL);
        if (!g->pen) {
            int32_t q;
            g->pen = (int32_t *)malloc((size_t)(g->w - 1) * (size_t)(g->h - 1) * 4);
            if (!g->pen) bb_raise(7, NULL);
            for (q = 0; q < (g->w - 1) * (g->h - 1); q++) g->pen[q] = 2;
        }
        g->pen[j * (g->w - 1) + i] = argl(argc, argv, 3);
        return;
    }
    case M_GRIDHEIGHT: case M_GRIDHEIGHTF: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        int32_t h = grid_height16(g, argl(argc, argv, 1), argl(argc, argv, 2));
        *ret = bb_v_long(id == M_GRIDHEIGHT ? h >> 16 : h);
        return;
    }
    case M_GRIDGENERATE: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        grid_generate(g, (uint32_t)argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3));
        return;
    }
    case M_GRIDCOLOURS: {
        E3Grid *g = get_grid(e, argl(argc, argv, 0));
        g->water = argl(argc, argv, 1); g->wpen = argl(argc, argv, 2); g->lpen = argl(argc, argv, 3);
        g->hpen = argl(argc, argv, 4); g->snow = argl(argc, argv, 5); g->spen = argl(argc, argv, 6);
        g->bypen = 1;
        return;
    }
    case M_GRIDSHADE: get_grid(e, argl(argc, argv, 0))->shade = argl(argc, argv, 1) != 0; return;
    case M_DRAWGRID: draw_grid(e, get_grid(e, argl(argc, argv, 0)), argl_opt(argc, argv, 1, 0), argl_opt(argc, argv, 2, 0)); return;
    case M_GRIDFREE: grid_free(get_grid(e, argl(argc, argv, 0))); return;

    /* ---- shading, fog ---- */
    case P_SHADING:
        if (setting) e->shading = argl(argc, argv, argc - 1) != 0; else *ret = bb_v_long(e->shading);
        return;
    case M_LIGHT:
        set_light(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2));
        e->amb = argl_opt(argc, argv, 3, 64);
        return;
    case M_FOG: {
        int32_t col = argl(argc, argv, 0);
        if (col == -1) { e->fog_on = 0; return; }
        e->fog_col = ARGB(col);
        e->fog_near = argl(argc, argv, 1);
        e->fog_far = argl(argc, argv, 2);
        if (e->fog_far <= e->fog_near) bb_raise(5, NULL);
        e->fog_on = 1;
        return;
    }

    /* ---- text and 2D ---- */
    case M_TEXT: case M_TEXTSHADOW: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), sc = argl_opt(argc, argv, 4, 1);
        const char *s = arg_str(argc, argv, 2, &hold);
        uint32_t col = pen_argb(e, argl(argc, argv, 3), NULL);
        if (sc < 1) sc = 1;
        if (need_target(e)) {
            if (id == M_TEXTSHADOW) text16(e, x + 1, y + 1, s, e->pal[0], sc);
            text16(e, x, y, s, col, sc);
        }
        bb_str_release(hold);
        return;
    }
    case M_TEXTCENTRE: {
        int32_t y = argl(argc, argv, 0), sc = argl_opt(argc, argv, 3, 1), x;
        const char *s = arg_str(argc, argv, 1, &hold);
        uint32_t col = pen_argb(e, argl(argc, argv, 2), NULL);
        if (sc < 1) sc = 1;
        x = (c->vw - (int32_t)strlen(s) * 8 * sc) / 2;
        if (need_target(e)) {
            text16(e, x + 1, y + 1, s, e->pal[0], sc);
            text16(e, x, y, s, col, sc);
        }
        bb_str_release(hold);
        return;
    }
    case M_TEXTWIDTH: {
        const char *s = arg_str(argc, argv, 0, &hold);
        int32_t sc = argl_opt(argc, argv, 1, 1);
        *ret = bb_v_long((int32_t)strlen(s) * 8 * (sc < 1 ? 1 : sc));
        bb_str_release(hold);
        return;
    }
    case M_FILLGRADIENT: {
        /* rows y0..y1 of the 3D area (its coordinates) across its width, top colour to bottom */
        int32_t y0 = argl(argc, argv, 0), y1 = argl(argc, argv, 1), S = e->sub, y, n;
        uint32_t top = ARGB(argl(argc, argv, 2)), bot = ARGB(argl(argc, argv, 3));
        if (y1 < y0 || !need_target(e)) return;
        n = (y1 - y0 + 1) * S;
        for (y = 0; y < n; y++)
            tspan(e, y0 * S + y, 0, c->vw * S - 1, mix_col(top, bot, n > 1 ? (y * 256) / (n - 1) : 0));
        return;
    }
    case M_SPAN: {
        int grad = 0;
        int32_t y = argl(argc, argv, 0);
        uint32_t col = pen_argb(e, argl(argc, argv, 3), &grad);
        if (need_target(e)) tspan(e, y, argl(argc, argv, 1), argl(argc, argv, 2), grad ? sky_at(e, y, col) : col);
        return;
    }
    case M_FILLRECT: {
        int grad = 0;
        uint32_t col = pen_argb(e, argl(argc, argv, 4), &grad);
        if (need_target(e)) fill_rect_e(e, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), col, grad);
        return;
    }
    case M_POLYFILL: {
        int32_t n = argl(argc, argv, 2), xs[MAX_PV], ys[MAX_PV], i, S = e->sub;
        int16_t px[MAX_PV], py[MAX_PV];
        int grad = 0;
        uint32_t col = pen_argb(e, argl(argc, argv, 3), &grad);
        if (n < 3 || n > MAX_PV) bb_raise(5, NULL);
        read_arr(arg_array(argc, argv, 0), n, xs);
        read_arr(arg_array(argc, argv, 1), n, ys);
        for (i = 0; i < n; i++) { xs[i] *= S; ys[i] *= S; }
        n = clip_rect(xs, ys, n, 0, 0, c->vw * S - 1, c->vh * S - 1);
        if (n < 3 || !need_target(e)) return;
        for (i = 0; i < n; i++) { px[i] = (int16_t)xs[i]; py[i] = (int16_t)ys[i]; }
        raster(e, px, py, n, col, grad, S - 1);
        return;
    }
    case M_BLEND: {
        int32_t y = argl(argc, argv, 0), xl = argl(argc, argv, 1), xr = argl(argc, argv, 2), a = argl(argc, argv, 4), x, S = e->sub;
        uint32_t col = pen_argb(e, argl(argc, argv, 3), NULL);
        if (!need_target(e) || a <= 0) return;
        if (a > 256) a = 256;
        y += e->oy * S; xl += e->ox * S; xr += e->ox * S;
        if ((uint32_t)y >= (uint32_t)e->th) return;
        if (xl < 0) xl = 0;
        if (xr >= e->tw) xr = e->tw - 1;
        for (x = xl; x <= xr; x++) {
            uint32_t *p = e->tp + y * e->tw + x;
            *p = mix_col(*p, col, a);
        }
        return;
    }

    /* ---- maths ---- */
    case M_SIN: *ret = bb_v_long(a3_sin(argl(argc, argv, 0) & 0xFFFF)); return;
    case M_COS: *ret = bb_v_long(a3_cos(argl(argc, argv, 0) & 0xFFFF)); return;
    case M_ATAN2: *ret = bb_v_long(a3_atan2(argl(argc, argv, 0), argl(argc, argv, 1))); return;
    case M_ISQRT: *ret = bb_v_long((int32_t)a3_isqrt((uint32_t)argl(argc, argv, 0))); return;
    case M_HYPOT: *ret = bb_v_long(a3_hypot(argl(argc, argv, 0), argl(argc, argv, 1))); return;
    case M_HASH: *ret = bb_v_long((int32_t)a3_hash((uint32_t)argl(argc, argv, 0))); return;
    case M_RAND: {
        uint32_t st = (uint32_t)argl(argc, argv, 0);
        int32_t r = (int32_t)a3_rand(&st);
        store_l(&argv[0], (int32_t)st);
        *ret = bb_v_long(r);
        return;
    }
    case M_FMUL: *ret = bb_v_long(FMUL(argl(argc, argv, 0), argl(argc, argv, 1))); return;
    case M_FDIV: {
        int32_t b = argl(argc, argv, 1);
        if (!b) bb_raise(11, NULL);
        *ret = bb_v_long(FDIV(argl(argc, argv, 0), b));
        return;
    }
    case M_FSQRT: *ret = bb_v_long(fsqrt(argl(argc, argv, 0))); return;
    case M_ROTYPR: case M_ROTYAW: {
        bb_long *m = out_arr(argc, argv, 0, 9);
        int32_t r[9], i;
        if (id == M_ROTYPR) rot_ypr(r, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3));
        else rot_yaw(r, argl(argc, argv, 1));
        for (i = 0; i < 9; i++) m[i] = r[i];
        return;
    }
    case M_MATMUL: {
        bb_long *o = out_arr(argc, argv, 0, 9);
        int32_t a[9], b[9], r[9], i, j;
        read_arr(arg_array(argc, argv, 1), 9, a);
        read_arr(arg_array(argc, argv, 2), 9, b);
        for (i = 0; i < 3; i++)
            for (j = 0; j < 3; j++)
                r[i * 3 + j] = (int32_t)(((int64_t)a[i * 3] * b[j] + (int64_t)a[i * 3 + 1] * b[3 + j] + (int64_t)a[i * 3 + 2] * b[6 + j]) >> 16);
        for (i = 0; i < 9; i++) o[i] = r[i];
        return;
    }
    case M_MATAPPLY: {
        int32_t m[9], x, y, z;
        if (argc < 7) bb_raise(450, NULL);
        read_arr(arg_array(argc, argv, 0), 9, m);
        x = argl(argc, argv, 1); y = argl(argc, argv, 2); z = argl(argc, argv, 3);
        store_l(&argv[4], (int32_t)(((int64_t)x * m[0] + (int64_t)y * m[1] + (int64_t)z * m[2]) >> 16));
        store_l(&argv[5], (int32_t)(((int64_t)x * m[3] + (int64_t)y * m[4] + (int64_t)z * m[5]) >> 16));
        store_l(&argv[6], (int32_t)(((int64_t)x * m[6] + (int64_t)y * m[7] + (int64_t)z * m[8]) >> 16));
        return;
    }
    case M_SINTABLE: case M_COSTABLE: {
        bb_long *o = out_arr(argc, argv, 0, 256);
        int32_t i;
        for (i = 0; i < 256; i++) o[i] = id == M_SINTABLE ? a3_sin_tab[i] : a3_sin_tab[(i + 64) & 255];
        return;
    }
    }
    bb_raise(438, NULL);
}

static void e3_terminate(bb_obj *self)
{
    bb_e3d *e = (bb_e3d *)self;
    int32_t i;
    bb_obj_release(e->canvas);
    for (i = 0; i < e->nmodels; i++) free(e->models[i]);
    free(e->models);
    for (i = 0; i < e->ngrids; i++) if (e->grids[i].used) grid_free(&e->grids[i]);
    free(e->grids);
    free(e->pool);
}

static const bb_class e3d_class = {
    "Engine3D", sizeof(bb_e3d), e3_find, e3_invoke, e3_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

/* the default pens: amiga3d-style basics, then a grey ramp */
static const uint16_t def_pal12[16] = {
    0x000, 0xFFF, 0x888, 0xAAA, 0x58A, 0x353, 0x575, 0x887, 0xC33, 0x3C3, 0x33C, 0xCC3, 0xC3C, 0x3CC, 0xF80, 0x555
};

bb_obj *bb_engine3d_new(void)
{
    bb_e3d *e = (bb_e3d *)bb_obj_new(&e3d_class);
    int32_t i;
    e->pool = (DPoly *)malloc(sizeof(DPoly) * E3_MAXPOLY);
    if (!e->pool) { bb_obj_release(&e->hdr); bb_raise(7, NULL); }
    for (i = 0; i < 256; i++) {
        if (i < 16) {
            uint32_t v = def_pal12[i];
            e->pal[i] = 0xFF000000u | (((v >> 8) & 15) * 17) << 16 | (((v >> 4) & 15) * 17) << 8 | ((v & 15) * 17);
        } else {
            uint32_t g = (uint32_t)i;
            e->pal[i] = 0xFF000000u | g << 16 | g << 8 | g;
        }
    }
    e->sub = 1;
    e->sky_pen = -1;
    e->amb = 64;
    e->margin = 800;
    set_light(e, -1, 2, 1);
    cam_view(&e->cam.c, 320, 256, 160, 128, 256);
    cam_trig(&e->cam);
    e_begin(e, 4096);
    return &e->hdr;
}
