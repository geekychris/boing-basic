/* canvas.c - the Canvas control: portable drawing on a chunky 0xAARRGGBB buffer
 *
 * See canvas.h and docs/graphics.md. Colours from BASIC are VB colours (&HBBGGRR, what RGB()
 * returns). All drawing goes to the back buffer (or to an image chosen with SetTarget);
 * Refresh (= Flip = EndDraw) hands the back buffer to the platform layer, which blits it into
 * the control's window. Members are found once per call site (ids below), and invoke() reads
 * the arguments straight from the Variants, so a drawing call costs little more than the
 * call itself.
 */
#include "canvas.h"
#include <math.h>
#include "audio.h"
#include "canvas_font.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct cv_image {
    int32_t w, h;
    uint32_t *px;
} cv_image;

struct bb_canvas {
    bb_obj hdr;
    bb_ctl *ctl;                 /* form control, NULL = off-screen */
    bb_canvas *next;             /* list of canvases with a control */
    int32_t w, h;
    uint32_t *back;              /* w * h */
    cv_image *imgs;              /* images 1..nimgs (imgs[i-1]) */
    int32_t nimgs;
    int32_t target;              /* 0 = the back buffer, else an image */
    /* the current target */
    uint32_t *tp;
    int32_t tw, th;
    int32_t fore, fill, backc;   /* VB colours */
    int32_t curx, cury;
    int32_t frames;
    int32_t scale;               /* shown scale x scale times bigger */
    uint32_t *sbuf;              /* the scaled picture */
};

static bb_canvas *ctl_canvases;
int bb_is_canvas(const bb_obj *o);
static unsigned char keys[512];

#define ARGB(vb) (0xFF000000u | (((uint32_t)(vb) & 0xFFu) << 16) | ((uint32_t)(vb) & 0xFF00u) | \
                  (((uint32_t)(vb) >> 16) & 0xFFu))
#define VBCOL(argb) ((int32_t)((((argb) >> 16) & 0xFFu) | ((argb) & 0xFF00u) | (((argb) & 0xFFu) << 16)))

/* ---------------------------------------------------------------- arguments */

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

static int missing(int argc, const bb_value *argv, int i)
{
    if (i >= argc) return 1;
    return argv[i].type == BB_ERROR && (argv[i].flags & BB_VF_MISSING);
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

/* a string argument; *hold gets an owned string to release when it had to be converted */
static const char *args_(int argc, const bb_value *argv, int i, bb_str **hold, int32_t *len)
{
    bb_value t;
    const bb_value *v;
    *hold = NULL;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_STRING) {
        *len = bb_str_len(v->u.s);
        return bb_str_ptr(v->u.s);
    }
    *hold = bb_v_to_str(v);
    *len = bb_str_len(*hold);
    return bb_str_ptr(*hold);
}

static bb_array *arg_array(int argc, const bb_value *argv, int i)
{
    const bb_value *v;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = &argv[i];
    if ((v->type & BB_REF) && (v->type & BB_ARRAY)) return *(bb_array **)v->u.p;
    if (v->type & BB_REF) {
        const bb_value *pv = (const bb_value *)v->u.p;
        if (pv->type & BB_ARRAY) return pv->u.a;
    } else if (v->type & BB_ARRAY) return v->u.a;
    bb_raise(13, NULL);
    return NULL;
}

/* element k (in storage order) of a numeric array, as a Long */
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

static void need_count(const bb_array *a, int32_t n)
{
    if (!a || n < 0 || n > a->count) bb_raise(9, NULL);
}

/* ---------------------------------------------------------------- drawing */

static inline void plot(bb_canvas *c, int32_t x, int32_t y, uint32_t col)
{
    if ((uint32_t)x < (uint32_t)c->tw && (uint32_t)y < (uint32_t)c->th) c->tp[y * c->tw + x] = col;
}

static void hspan(bb_canvas *c, int32_t x1, int32_t x2, int32_t y, uint32_t col)
{
    uint32_t *p;
    int32_t i;
    if ((uint32_t)y >= (uint32_t)c->th) return;
    if (x1 > x2) { int32_t t = x1; x1 = x2; x2 = t; }
    if (x1 < 0) x1 = 0;
    if (x2 >= c->tw) x2 = c->tw - 1;
    if (x1 > x2) return;
    p = c->tp + y * c->tw;
    for (i = x1; i <= x2; i++) p[i] = col;
}

static void fill_rect(bb_canvas *c, int32_t x1, int32_t y1, int32_t x2, int32_t y2, uint32_t col)
{
    int32_t y;
    if (y1 > y2) { int32_t t = y1; y1 = y2; y2 = t; }
    if (y1 < 0) y1 = 0;
    if (y2 >= c->th) y2 = c->th - 1;
    for (y = y1; y <= y2; y++) hspan(c, x1, x2, y, col);
}

/* Liang-Barsky: clip the segment to [lo, hi] boxes; returns 0 if nothing is left */
static int clip_seg(double *x1, double *y1, double *x2, double *y2, double xlo, double ylo, double xhi, double yhi)
{
    double t0 = 0, t1 = 1, dx = *x2 - *x1, dy = *y2 - *y1;
    double p[4], q[4];
    int i;
    p[0] = -dx; q[0] = *x1 - xlo;
    p[1] = dx;  q[1] = xhi - *x1;
    p[2] = -dy; q[2] = *y1 - ylo;
    p[3] = dy;  q[3] = yhi - *y1;
    for (i = 0; i < 4; i++) {
        if (p[i] == 0) { if (q[i] < 0) return 0; continue; }
        {
            double r = q[i] / p[i];
            if (p[i] < 0) { if (r > t1) return 0; if (r > t0) t0 = r; }
            else { if (r < t0) return 0; if (r < t1) t1 = r; }
        }
    }
    {
        double ax = *x1, ay = *y1;
        *x1 = ax + t0 * dx; *y1 = ay + t0 * dy;
        *x2 = ax + t1 * dx; *y2 = ay + t1 * dy;
    }
    return 1;
}

#define LINE_GUARD 1024     /* lines within this far of the target are drawn unclipped (exact pixels) */

static void line(bb_canvas *c, int32_t x1, int32_t y1, int32_t x2, int32_t y2, uint32_t col)
{
    int32_t dx, dy, sx, sy, e, e2;
    /* both ends off the same side: nothing to draw */
    if ((x1 < 0 && x2 < 0) || (y1 < 0 && y2 < 0) || (x1 >= c->tw && x2 >= c->tw) || (y1 >= c->th && y2 >= c->th))
        return;
    if (x1 < -LINE_GUARD || x2 < -LINE_GUARD || y1 < -LINE_GUARD || y2 < -LINE_GUARD ||
        x1 > c->tw + LINE_GUARD || x2 > c->tw + LINE_GUARD || y1 > c->th + LINE_GUARD || y2 > c->th + LINE_GUARD) {
        /* a very long line (e.g. a projected 3D edge ending near the camera): clip it to the
           target plus the guard band first, so the work is bounded by the target's size */
        double fx1 = x1, fy1 = y1, fx2 = x2, fy2 = y2;
        if (!clip_seg(&fx1, &fy1, &fx2, &fy2, -LINE_GUARD, -LINE_GUARD, c->tw + LINE_GUARD, c->th + LINE_GUARD)) return;
        x1 = (int32_t)floor(fx1 + 0.5); y1 = (int32_t)floor(fy1 + 0.5);
        x2 = (int32_t)floor(fx2 + 0.5); y2 = (int32_t)floor(fy2 + 0.5);
        if ((x1 < 0 && x2 < 0) || (y1 < 0 && y2 < 0) || (x1 >= c->tw && x2 >= c->tw) || (y1 >= c->th && y2 >= c->th))
            return;
    }
    dx = x2 > x1 ? x2 - x1 : x1 - x2;
    dy = y2 > y1 ? y1 - y2 : y2 - y1;
    sx = x1 < x2 ? 1 : -1;
    sy = y1 < y2 ? 1 : -1;
    e = dx + dy;
    if (y1 == y2) { hspan(c, x1, x2, y1, col); return; }
    for (;;) {
        plot(c, x1, y1, col);
        if (x1 == x2 && y1 == y2) break;
        e2 = 2 * e;
        if (e2 >= dy) { e += dy; x1 += sx; }
        if (e2 <= dx) { e += dx; y1 += sy; }
    }
}

static void circle(bb_canvas *c, int32_t cx, int32_t cy, int32_t r, uint32_t col, int filled)
{
    int32_t x = r, y = 0, e = 1 - r;
    if (r < 0) return;
    while (x >= y) {
        if (filled) {
            hspan(c, cx - x, cx + x, cy + y, col);
            hspan(c, cx - x, cx + x, cy - y, col);
            hspan(c, cx - y, cx + y, cy + x, col);
            hspan(c, cx - y, cx + y, cy - x, col);
        } else {
            plot(c, cx + x, cy + y, col); plot(c, cx + y, cy + x, col);
            plot(c, cx - y, cy + x, col); plot(c, cx - x, cy + y, col);
            plot(c, cx - x, cy - y, col); plot(c, cx - y, cy - x, col);
            plot(c, cx + y, cy - x, col); plot(c, cx + x, cy - y, col);
        }
        y++;
        if (e < 0) e += 2 * y + 1;
        else { x--; e += 2 * (y - x) + 1; }
    }
}

/* filled polygon, even-odd rule, sampled at pixel centres */
static void fill_poly(bb_canvas *c, const int32_t *xs, const int32_t *ys, int32_t n, uint32_t col)
{
    int32_t ymin = ys[0], ymax = ys[0], i, j, y, k, nx;
    int32_t xb[64];
    for (i = 1; i < n; i++) {
        if (ys[i] < ymin) ymin = ys[i];
        if (ys[i] > ymax) ymax = ys[i];
    }
    if (ymin < 0) ymin = 0;
    if (ymax >= c->th) ymax = c->th - 1;
    for (y = ymin; y <= ymax; y++) {
        nx = 0;
        for (i = 0, j = n - 1; i < n; j = i++) {
            int32_t yi = ys[i], yj = ys[j];
            if ((yi <= y && yj > y) || (yj <= y && yi > y)) {
                /* x where the edge crosses y + 0.5, in 1/2 pixel units */
                int32_t num = (2 * y + 1 - 2 * yi) * (xs[j] - xs[i]), den = 2 * (yj - yi);
                int32_t x = xs[i] + (num >= 0 ? num / den : -((-num + den - 1) / den));
                if (nx < 64) xb[nx++] = x;
            }
        }
        for (i = 1; i < nx; i++)        /* insertion sort, nx is tiny */
            for (k = i; k > 0 && xb[k - 1] > xb[k]; k--) { int32_t t = xb[k]; xb[k] = xb[k - 1]; xb[k - 1] = t; }
        for (i = 0; i + 1 < nx; i += 2) hspan(c, xb[i], xb[i + 1] - 1, y, col);
    }
}

static int32_t text(bb_canvas *c, int32_t x, int32_t y, const char *s, int32_t len, uint32_t col)
{
    int32_t k, r, b;
    for (k = 0; k < len; k++, x += CV_FONT_W) {
        unsigned ch = (unsigned char)s[k];
        const unsigned char *g;
        if (ch == ' ') continue;
        if (ch < 32 || ch > 126) ch = '?';
        if (x >= c->tw || x + CV_FONT_W <= 0) continue;
        g = cv_font[ch - 32];
        for (r = 0; r < CV_FONT_H; r++) {
            unsigned bits = g[r];
            if (!bits || (uint32_t)(y + r) >= (uint32_t)c->th) continue;
            for (b = 0; bits; b++, bits = (bits << 1) & 0xFF)
                if (bits & 0x80) plot(c, x + b, y + r, col);
        }
    }
    return x;
}

static void set_target(bb_canvas *c, int32_t id)
{
    if (id == 0) {
        c->tp = c->back;
        c->tw = c->w;
        c->th = c->h;
    } else {
        if (id < 0 || id > c->nimgs || !c->imgs[id - 1].px) bb_raise(5, NULL);
        c->tp = c->imgs[id - 1].px;
        c->tw = c->imgs[id - 1].w;
        c->th = c->imgs[id - 1].h;
    }
    c->target = id;
}

static cv_image *image(bb_canvas *c, int32_t id)
{
    if (id < 1 || id > c->nimgs || !c->imgs[id - 1].px) bb_raise(5, NULL);
    return &c->imgs[id - 1];
}

static int32_t add_image(bb_canvas *c, int32_t w, int32_t h, uint32_t *px)
{
    c->imgs = (cv_image *)bb_realloc(c->imgs, sizeof(cv_image) * (size_t)(c->nimgs + 1));
    c->imgs[c->nimgs].w = w;
    c->imgs[c->nimgs].h = h;
    c->imgs[c->nimgs].px = px;
    c->nimgs++;
    if (c->target) set_target(c, c->target);   /* imgs may have moved */
    return c->nimgs;
}

/* copy an image's rectangle to (x, y), skipping pixels with alpha 0 */
static void blit(bb_canvas *c, const cv_image *im, int32_t sx, int32_t sy, int32_t sw, int32_t sh,
                 int32_t x, int32_t y, int opaque)
{
    int32_t i, j;
    if (sx < 0) { sw += sx; x -= sx; sx = 0; }
    if (sy < 0) { sh += sy; y -= sy; sy = 0; }
    if (sx + sw > im->w) sw = im->w - sx;
    if (sy + sh > im->h) sh = im->h - sy;
    if (x < 0) { sw += x; sx -= x; x = 0; }
    if (y < 0) { sh += y; sy -= y; y = 0; }
    if (x + sw > c->tw) sw = c->tw - x;
    if (y + sh > c->th) sh = c->th - y;
    if (sw <= 0 || sh <= 0 || im->px == c->tp) return;
    for (j = 0; j < sh; j++) {
        const uint32_t *s = im->px + (sy + j) * im->w + sx;
        uint32_t *d = c->tp + (y + j) * c->tw + x;
        if (opaque) for (i = 0; i < sw; i++) d[i] = s[i];
        else for (i = 0; i < sw; i++) if (s[i] >> 24) d[i] = s[i];
    }
}

static int32_t hash(const uint32_t *p, int32_t n)
{
    uint32_t h = 2166136261u;
    int32_t i;
    for (i = 0; i < n; i++) {
        h = (h ^ (p[i] & 0xFFFFFFu)) * 16777619u;
    }
    return (int32_t)(h & 0x7FFFFFFFu);
}

/* ---------------------------------------------------------------- pictures */

static uint32_t *load_ppm(const char *path, int32_t *w, int32_t *h)
{
    FILE *f = fopen(path, "rb");
    int ww, hh, mx, ch, i;
    uint32_t *px;
    if (!f) return NULL;
    if (fscanf(f, "P6 %d %d %d", &ww, &hh, &mx) != 3 || ww <= 0 || hh <= 0 || ww > 8192 || hh > 8192 || mx != 255) {
        fclose(f);
        return NULL;
    }
    ch = fgetc(f);
    (void)ch;
    px = (uint32_t *)malloc((size_t)ww * (size_t)hh * 4);
    for (i = 0; px && i < ww * hh; i++) {
        int r = fgetc(f), g = fgetc(f), b = fgetc(f);
        if (b == EOF) break;
        px[i] = 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
    }
    fclose(f);
    if (px && i < ww * hh) { free(px); return NULL; }
    *w = ww;
    *h = hh;
    return px;
}

static int save_ppm(const char *path, const uint32_t *px, int32_t w, int32_t h)
{
    FILE *f = fopen(path, "wb");
    int32_t i;
    if (!f) return 0;
    fprintf(f, "P6\n%d %d\n255\n", (int)w, (int)h);
    for (i = 0; i < w * h; i++) {
        fputc((int)((px[i] >> 16) & 255), f);
        fputc((int)((px[i] >> 8) & 255), f);
        fputc((int)(px[i] & 255), f);
    }
    return fclose(f) == 0;
}

/* ---------------------------------------------------------------- the object */

enum {
    M_CLS = 1, M_PSET, M_LINE, M_BOX, M_RECT, M_CIRCLE, M_POLYGON, M_PRINT, M_DRAWTEXT, M_TEXTWIDTH,
    M_TEXTHEIGHT, M_REFRESH, M_BEGINDRAW, M_PSETMANY, M_POINT, M_HASH, M_CREATEIMAGE, M_LOADIMAGE,
    M_FREEIMAGE, M_SETTARGET, M_DRAWIMAGE, M_DRAWIMAGEPART, M_IMAGEWIDTH, M_IMAGEHEIGHT, M_KEYDOWN,
    M_SAVEIMAGE, M_INJECTKEY, M_RESIZE,
    P_WIDTH, P_HEIGHT, P_FORECOLOR, P_FILLCOLOR, P_BACKCOLOR, P_CURRENTX, P_CURRENTY, P_FRAMES,
    P_TARGET, P_NAME, P_BLITMODE, P_BLITINFO, P_SCALE
};

static const struct { const char *name; int32_t id; } members[] = {
    {"Cls", M_CLS}, {"PSet", M_PSET}, {"Line", M_LINE}, {"Box", M_BOX}, {"FillRect", M_BOX},
    {"Rect", M_RECT}, {"Circle", M_CIRCLE}, {"Polygon", M_POLYGON}, {"Print", M_PRINT},
    {"DrawText", M_DRAWTEXT}, {"TextWidth", M_TEXTWIDTH}, {"TextHeight", M_TEXTHEIGHT},
    {"Refresh", M_REFRESH}, {"Flip", M_REFRESH}, {"EndDraw", M_REFRESH}, {"BeginDraw", M_BEGINDRAW},
    {"PSetMany", M_PSETMANY}, {"Point", M_POINT}, {"Hash", M_HASH}, {"CreateImage", M_CREATEIMAGE},
    {"LoadImage", M_LOADIMAGE}, {"FreeImage", M_FREEIMAGE}, {"SetTarget", M_SETTARGET},
    {"DrawImage", M_DRAWIMAGE}, {"DrawImagePart", M_DRAWIMAGEPART}, {"ImageWidth", M_IMAGEWIDTH},
    {"ImageHeight", M_IMAGEHEIGHT}, {"KeyDown", M_KEYDOWN}, {"SaveImage", M_SAVEIMAGE},
    {"InjectKey", M_INJECTKEY}, {"Resize", M_RESIZE},
    {"Width", P_WIDTH}, {"ScaleWidth", P_WIDTH}, {"Height", P_HEIGHT}, {"ScaleHeight", P_HEIGHT},
    {"ForeColor", P_FORECOLOR}, {"FillColor", P_FILLCOLOR}, {"BackColor", P_BACKCOLOR},
    {"CurrentX", P_CURRENTX}, {"CurrentY", P_CURRENTY}, {"Frames", P_FRAMES}, {"Target", P_TARGET},
    {"Name", P_NAME}, {"BlitMode", P_BLITMODE}, {"BlitInfo", P_BLITINFO}, {"Scale", P_SCALE},
};

#define CV_CTL_MEMBER 10000
static char *ctl_names[64];
static int n_ctl_names;

static int32_t cv_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (strcasecmp(members[i].name, name) == 0) return members[i].id;
    /* other names go to the form control the canvas shows in (ContextMenu, Visible,
       ToolTipText, Left/Top...; docs/ui.md), when it has one */
    for (i = 0; i < (size_t)n_ctl_names; i++)
        if (strcasecmp(ctl_names[i], name) == 0) return CV_CTL_MEMBER + (int32_t)i;
    if (n_ctl_names < 64) {
        ctl_names[n_ctl_names] = strdup(name);
        return CV_CTL_MEMBER + n_ctl_names++;
    }
    return BB_NOMEMBER;
}

static void resize(bb_canvas *c, int32_t w, int32_t h)
{
    if (w < 1 || h < 1 || w > 4096 || h > 4096) bb_raise(380, NULL);
    free(c->back);
    c->back = (uint32_t *)malloc((size_t)w * (size_t)h * 4);
    if (!c->back) bb_raise(7, NULL);
    c->w = w;
    c->h = h;
    free(c->sbuf);
    c->sbuf = NULL;
    {
        int32_t i;
        uint32_t bc = ARGB(c->backc);
        for (i = 0; i < w * h; i++) c->back[i] = bc;
    }
    set_target(c, 0);
}

/* hand the back buffer (scaled up if asked) to the platform layer */
static void present(bb_canvas *c)
{
    int32_t s = c->scale, sw, x, y, k;
    if (s <= 1) {
        canvas_plat_present(c->ctl, c->back, c->w, c->h, c->w);
        return;
    }
    sw = c->w * s;
    if (!c->sbuf) {
        c->sbuf = (uint32_t *)malloc((size_t)sw * (size_t)(c->h * s) * 4);
        if (!c->sbuf) bb_raise(7, NULL);
    }
    for (y = 0; y < c->h; y++) {
        const uint32_t *src = c->back + y * c->w;
        uint32_t *d = c->sbuf + (size_t)y * s * sw;
        for (x = 0; x < c->w; x++) {
            uint32_t p = src[x];
            for (k = 0; k < s; k++) d[x * s + k] = p;
        }
        for (k = 1; k < s; k++) {
            uint32_t *d2 = d + (size_t)k * sw;
            for (x = 0; x < sw; x++) d2[x] = d[x];
        }
    }
    canvas_plat_present(c->ctl, c->sbuf, sw, c->h * s, sw);
}

static void cv_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bb_canvas *c = (bb_canvas *)self;
    bb_str *hold = NULL;
    int32_t len;
    const char *s;
    int setting = (kind & (BB_INV_LET | BB_INV_SET)) != 0;

    if (id >= CV_CTL_MEMBER) {
        if (!c->ctl) bb_raise(438, NULL);
        bb_ctl_invoke_named(c->ctl, ctl_names[id - CV_CTL_MEMBER], kind, argc, argv, ret);
        return;
    }
    switch (id) {
    case M_CLS: {
        int32_t i, n = c->tw * c->th;
        uint32_t col = missing(argc, argv, 0) ? (c->target ? 0u : ARGB(c->backc)) : ARGB(to_l(&argv[0]));
        uint32_t *p = c->tp;
        for (i = 0; i < n; i++) p[i] = col;
        c->curx = c->cury = 0;
        return;
    }
    case M_PSET: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1);
        plot(c, x, y, ARGB(argl_opt(argc, argv, 2, c->fore)));
        c->curx = x;
        c->cury = y;
        return;
    }
    case M_LINE: {
        int32_t x1 = argl(argc, argv, 0), y1 = argl(argc, argv, 1), x2 = argl(argc, argv, 2), y2 = argl(argc, argv, 3);
        uint32_t col = ARGB(argl_opt(argc, argv, 4, c->fore));
        int box = 0;                /* VB's Line ... , B / BF */
        if (!missing(argc, argv, 5)) {
            bb_value t;
            const bb_value *v = bb_v_deref(&argv[5], &t);
            if (v->type == BB_STRING) {
                const char *f = bb_str_ptr(v->u.s);
                box = !strcasecmp(f, "BF") ? 2 : !strcasecmp(f, "B") ? 1 : 0;
            } else box = to_l(v);
        }
        if (box == 2) fill_rect(c, x1, y1, x2, y2, col);
        else if (box == 1) {
            line(c, x1, y1, x2, y1, col); line(c, x1, y2, x2, y2, col);
            line(c, x1, y1, x1, y2, col); line(c, x2, y1, x2, y2, col);
        } else line(c, x1, y1, x2, y2, col);
        c->curx = x2;
        c->cury = y2;
        return;
    }
    case M_BOX: case M_RECT: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3);
        uint32_t col = ARGB(argl_opt(argc, argv, 4, id == M_BOX ? c->fill : c->fore));
        if (w <= 0 || h <= 0) return;
        if (id == M_BOX) fill_rect(c, x, y, x + w - 1, y + h - 1, col);
        else {
            line(c, x, y, x + w - 1, y, col); line(c, x, y + h - 1, x + w - 1, y + h - 1, col);
            line(c, x, y, x, y + h - 1, col); line(c, x + w - 1, y, x + w - 1, y + h - 1, col);
        }
        return;
    }
    case M_CIRCLE: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), r = argl(argc, argv, 2);
        uint32_t col = ARGB(argl_opt(argc, argv, 3, c->fore));
        circle(c, x, y, r, col, argl_opt(argc, argv, 4, 0) != 0);
        return;
    }
    case M_POLYGON: {
        bb_array *ax = arg_array(argc, argv, 0), *ay = arg_array(argc, argv, 1);
        int32_t n = argl(argc, argv, 2), i;
        int32_t xs[64], ys[64];
        uint32_t col = ARGB(argl_opt(argc, argv, 3, c->fore));
        int filled = argl_opt(argc, argv, 4, 0) != 0;
        need_count(ax, n);
        need_count(ay, n);
        if (n > 64) bb_raise(5, NULL);
        if (n < 2) return;
        for (i = 0; i < n; i++) { xs[i] = elem_l(ax, i); ys[i] = elem_l(ay, i); }
        if (filled && n >= 3) fill_poly(c, xs, ys, n, col);
        else for (i = 0; i < n; i++) line(c, xs[i], ys[i], xs[(i + 1) % n], ys[(i + 1) % n], col);
        return;
    }
    case M_PRINT:
        s = argc ? args_(argc, argv, 0, &hold, &len) : "";
        if (!argc) len = 0;
        text(c, c->curx, c->cury, s, len, ARGB(c->fore));
        bb_str_release(hold);
        c->curx = 0;
        c->cury += CV_FONT_H + 1;
        return;
    case M_DRAWTEXT: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1);
        s = args_(argc, argv, 2, &hold, &len);
        c->curx = text(c, x, y, s, len, ARGB(argl_opt(argc, argv, 3, c->fore)));
        c->cury = y;
        bb_str_release(hold);
        return;
    }
    case M_TEXTWIDTH:
        s = args_(argc, argv, 0, &hold, &len);
        bb_str_release(hold);
        *ret = bb_v_long(len * CV_FONT_W);
        return;
    case M_TEXTHEIGHT:
        *ret = bb_v_long(CV_FONT_H + 1);
        return;
    case M_REFRESH:
        if (c->ctl) present(c);
        c->frames++;
        return;
    case M_BEGINDRAW:
        set_target(c, 0);
        return;
    case M_PSETMANY: {
        /* PSetMany xs(), ys(), colours() | colour, n [, size] */
        bb_array *ax = arg_array(argc, argv, 0), *ay = arg_array(argc, argv, 1), *ac = NULL;
        int32_t n = argl(argc, argv, 3), i, one = 0, sz = argl_opt(argc, argv, 4, 1);
        bb_value t;
        const bb_value *cv = missing(argc, argv, 2) ? NULL : bb_v_deref(&argv[2], &t);
        if (!cv) one = c->fore;
        else if (cv->type & BB_ARRAY) ac = arg_array(argc, argv, 2);
        else one = to_l(cv);
        need_count(ax, n);
        need_count(ay, n);
        if (ac) need_count(ac, n);
        if (sz > 1) {
            for (i = 0; i < n; i++) {
                int32_t x = elem_l(ax, i), y = elem_l(ay, i);
                fill_rect(c, x, y, x + sz - 1, y + sz - 1, ARGB(ac ? elem_l(ac, i) : one));
            }
        } else if (ax->etype == BB_LONG && ay->etype == BB_LONG && (!ac || ac->etype == BB_LONG)) {
            const int32_t *xs = (const int32_t *)ax->data, *ys = (const int32_t *)ay->data;
            const int32_t *cs = ac ? (const int32_t *)ac->data : NULL;
            uint32_t col1 = ARGB(one);
            for (i = 0; i < n; i++) plot(c, xs[i], ys[i], cs ? ARGB(cs[i]) : col1);
        } else {
            for (i = 0; i < n; i++) plot(c, elem_l(ax, i), elem_l(ay, i), ARGB(ac ? elem_l(ac, i) : one));
        }
        return;
    }
    case M_POINT: {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1);
        if ((uint32_t)x >= (uint32_t)c->tw || (uint32_t)y >= (uint32_t)c->th) *ret = bb_v_long(-1);
        else *ret = bb_v_long(VBCOL(c->tp[y * c->tw + x]));
        return;
    }
    case M_HASH:
        *ret = bb_v_long(hash(c->tp, c->tw * c->th));
        return;
    case M_CREATEIMAGE: {
        int32_t w = argl(argc, argv, 0), h = argl(argc, argv, 1);
        uint32_t *px;
        if (w < 1 || h < 1 || w > 4096 || h > 4096) bb_raise(380, NULL);
        px = (uint32_t *)calloc((size_t)w * (size_t)h, 4);     /* transparent */
        if (!px) bb_raise(7, NULL);
        *ret = bb_v_long(add_image(c, w, h, px));
        return;
    }
    case M_LOADIMAGE: {
        int32_t w = 0, h = 0;
        uint32_t *px;
        s = args_(argc, argv, 0, &hold, &len);
        px = canvas_plat_load_picture(s, &w, &h);
        if (!px) px = load_ppm(s, &w, &h);
        if (!px) {
            FILE *f = fopen(s, "rb");
            bb_str_release(hold);
            if (!f) bb_raise(53, NULL);
            fclose(f);
            bb_raise(481, "Invalid picture");
        }
        bb_str_release(hold);
        *ret = bb_v_long(add_image(c, w, h, px));
        return;
    }
    case M_FREEIMAGE: {
        cv_image *im = image(c, argl(argc, argv, 0));
        if (c->target && &c->imgs[c->target - 1] == im) set_target(c, 0);
        free(im->px);
        im->px = NULL;
        return;
    }
    case M_SETTARGET:
        set_target(c, argl_opt(argc, argv, 0, 0));
        return;
    case M_DRAWIMAGE: {
        cv_image *im = image(c, argl(argc, argv, 0));
        blit(c, im, 0, 0, im->w, im->h, argl(argc, argv, 1), argl(argc, argv, 2), argl_opt(argc, argv, 3, 0) != 0);
        return;
    }
    case M_DRAWIMAGEPART: {
        cv_image *im = image(c, argl(argc, argv, 0));
        blit(c, im, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4),
             argl(argc, argv, 5), argl(argc, argv, 6), argl_opt(argc, argv, 7, 0) != 0);
        return;
    }
    case M_IMAGEWIDTH: *ret = bb_v_long(image(c, argl(argc, argv, 0))->w); return;
    case M_IMAGEHEIGHT: *ret = bb_v_long(image(c, argl(argc, argv, 0))->h); return;
    case M_KEYDOWN: {
        int32_t k = argl(argc, argv, 0);
        *ret = bb_v_bool(k >= 0 && k < 512 && keys[k]);
        return;
    }
    case M_INJECTKEY:
        bb_canvas_key_event(argl(argc, argv, 0), argl_opt(argc, argv, 1, 1) != 0);
        return;
    case M_SAVEIMAGE: {
        int32_t im = argl_opt(argc, argv, 1, 0);
        const uint32_t *px = im ? image(c, im)->px : c->back;
        int32_t w = im ? image(c, im)->w : c->w, h = im ? image(c, im)->h : c->h;
        int ok;
        s = args_(argc, argv, 0, &hold, &len);
        ok = save_ppm(s, px, w, h);
        bb_str_release(hold);
        if (!ok) bb_raise(75, NULL);
        return;
    }
    case M_RESIZE:
        resize(c, argl(argc, argv, 0), argl(argc, argv, 1));
        return;
    case P_WIDTH: case P_HEIGHT:
        if (setting) {
            if (c->ctl) bb_raise(383, NULL);
            if (id == P_WIDTH) resize(c, to_l(&argv[argc - 1]), c->h);
            else resize(c, c->w, to_l(&argv[argc - 1]));
            return;
        }
        *ret = bb_v_long(id == P_WIDTH ? c->w : c->h);
        return;
    case P_FORECOLOR: case P_FILLCOLOR: case P_BACKCOLOR: case P_CURRENTX: case P_CURRENTY: {
        int32_t *f = id == P_FORECOLOR ? &c->fore : id == P_FILLCOLOR ? &c->fill : id == P_BACKCOLOR ? &c->backc
                   : id == P_CURRENTX ? &c->curx : &c->cury;
        if (setting) *f = to_l(&argv[argc - 1]);
        else *ret = bb_v_long(*f);
        return;
    }
    case P_FRAMES:
        if (setting) bb_raise(383, NULL);
        *ret = bb_v_long(c->frames);
        return;
    case P_TARGET:
        if (setting) set_target(c, to_l(&argv[argc - 1]));
        else *ret = bb_v_long(c->target);
        return;
    case P_NAME:
        if (setting) bb_raise(383, NULL);
        *ret = bb_v_str(bb_str_from_c("Canvas"));
        return;
    case P_BLITMODE:
        if (setting) {
            int32_t m = to_l(&argv[argc - 1]);
            if (m < 0 || m > 3) bb_raise(380, NULL);
            canvas_blit_mode = m;
        } else *ret = bb_v_long(canvas_blit_mode);
        return;
    case P_SCALE:
        if (setting) bb_raise(383, NULL);
        *ret = bb_v_long(c->scale);
        return;
    case P_BLITINFO:
        if (setting) bb_raise(383, NULL);
        *ret = bb_v_str(bb_str_from_c(canvas_plat_blit_info()));
        return;
    }
    bb_raise(438, NULL);
}

static void cv_terminate(bb_obj *self)
{
    bb_canvas *c = (bb_canvas *)self, **pp;
    int32_t i;
    for (pp = &ctl_canvases; *pp; pp = &(*pp)->next)
        if (*pp == c) { *pp = c->next; break; }
    for (i = 0; i < c->nimgs; i++) free(c->imgs[i].px);
    free(c->imgs);
    free(c->back);
    free(c->sbuf);
}

static const bb_class canvas_class = {
    "Canvas", sizeof(bb_canvas), cv_find, cv_invoke, cv_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

int bb_is_canvas(const bb_obj *o) { return o && o->cls == &canvas_class; }

uint32_t *bb_canvas_pixels(bb_obj *o, int32_t *w, int32_t *h)
{
    bb_canvas *c;
    if (!bb_is_canvas(o)) return NULL;
    c = (bb_canvas *)o;
    *w = c->tw;
    *h = c->th;
    return c->tp;
}

bb_obj *bb_canvas_new(int32_t w, int32_t h, bb_ctl *ctl)
{
    bb_canvas *c = (bb_canvas *)bb_obj_new(&canvas_class);
    c->fore = 0xFFFFFF;
    c->fill = 0xFFFFFF;
    c->backc = 0;
    resize(c, w > 0 ? w : 320, h > 0 ? h : 200);
    c->ctl = ctl;
    c->scale = 1;
    if (ctl) {
        c->next = ctl_canvases;
        ctl_canvases = c;
    }
    return &c->hdr;
}

void bb_canvas_ctl_refresh(bb_ctl *ctl)
{
    bb_canvas *c;
    for (c = ctl_canvases; c; c = c->next)
        if (c->ctl == ctl) present(c);
}

void bb_canvas_set_scale(bb_obj *o, int s)
{
    if (!bb_is_canvas(o)) return;
    ((bb_canvas *)o)->scale = s < 1 ? 1 : s > 4 ? 4 : s;
}

void bb_canvas_ctl_gone(bb_ctl *ctl)
{
    bb_canvas *c;
    for (c = ctl_canvases; c; c = c->next)
        if (c->ctl == ctl) c->ctl = NULL;
}

/* the picture size and scale of a control's canvas, for the forms layer's mouse coordinates */
int bb_canvas_ctl_geometry(bb_ctl *ctl, int *w, int *h, int *scale)
{
    bb_canvas *c;
    for (c = ctl_canvases; c; c = c->next)
        if (c->ctl == ctl) {
            *w = c->w;
            *h = c->h;
            *scale = c->scale > 1 ? c->scale : 1;
            return 1;
        }
    return 0;
}

/* Clipboard.GetPicture (docs/ui.md): a picture copied into the back buffer (resized to w x h) */
int bb_canvas_put_picture(bb_obj *o, const uint32_t *px, int32_t w, int32_t h)
{
    bb_canvas *c = (bb_canvas *)o;
    int32_t i, n = w * h;
    if (!bb_is_canvas(o) || w <= 0 || h <= 0) return 0;
    if (w != c->w || h != c->h) resize(c, w, h);
    for (i = 0; i < n; i++) c->back[i] = px[i] | 0xFF000000u;     /* a loop: the guest's big-memcpy bug */
    return 1;
}

void bb_canvas_key_event(int key, int down)
{
    if (key >= 0 && key < 512) keys[key] = down ? 1 : 0;
}

/* ---------------------------------------------------------------- CreateObject */

bb_obj *bb_create_object(const bb_str *progid)
{
    const char *p = bb_str_ptr(progid);
    if (!strcasecmp(p, "Boing.Canvas") || !strcasecmp(p, "Canvas")) return bb_canvas_new(320, 200, NULL);
    if (!strcasecmp(p, "Boing.Engine3D") || !strcasecmp(p, "Engine3D")) return bb_engine3d_new();
    if (!strcasecmp(p, "Boing.Audio") || !strcasecmp(p, "Audio")) return bb_audio_new();
    {
        bb_obj *o = bb_forms_create_object(p);       /* Boing.CommonDialog (forms_rt.c) */
        if (o) return o;
    }
    bb_raise(429, NULL);
    return NULL;
}
