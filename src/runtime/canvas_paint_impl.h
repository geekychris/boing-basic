/* canvas_paint_impl.h - paint-program helpers of the Canvas (docs/graphics.md, "Paint helpers")
 *
 * Not a normal header: canvas.c includes it once, after its own drawing helpers, so this code
 * shares the canvas's private structures (bb_canvas, cv_image) and helpers (argl, image,
 * add_image, plot, hspan, ...). Everything here is portable C, so the paint operations, the
 * PNG and IFF ILBM codecs included, work and are tested off-screen on the host.
 *
 * Colours are VB colours as everywhere in the Canvas; in these members -1 means "transparent"
 * (an eraser on an image).
 */

enum {
    MP_FLOODFILL = 1000, MP_ELLIPSE, MP_BRUSHLINE, MP_STAMPLINE, MP_DRAWIMAGESCALED, MP_DRAWIMAGEBLEND,
    MP_COPYIMAGE, MP_FLIPIMAGE, MP_ROTATEIMAGE, MP_SCALEIMAGE, MP_REPLACECOLOR, MP_SPRAY,
    MP_SAVEPNG, MP_SAVEILBM, MP_LASTPALETTE, MP_GETPALETTE, MP_QUANTIZE, MP_REMAPIMAGE, MP_DASHRECT,
    MP_IMAGEHASH, MP_DRAWTEXTSCALED, MP_IMAGEPOINT, MP_CLEARRECT, MP_IMAGEBOUNDS, MP_CHECKER, MP_FILLBOUNDS, MP_GRADIENT, MP_LINEARGRADIENT
};

static const struct { const char *name; int32_t id; } paint_members[] = {
    {"FloodFill", MP_FLOODFILL}, {"Ellipse", MP_ELLIPSE}, {"BrushLine", MP_BRUSHLINE},
    {"StampLine", MP_STAMPLINE}, {"DrawImageScaled", MP_DRAWIMAGESCALED},
    {"DrawImageBlend", MP_DRAWIMAGEBLEND}, {"CopyImage", MP_COPYIMAGE}, {"FlipImage", MP_FLIPIMAGE},
    {"RotateImage", MP_ROTATEIMAGE}, {"ScaleImage", MP_SCALEIMAGE}, {"ReplaceColor", MP_REPLACECOLOR},
    {"Spray", MP_SPRAY}, {"SavePNG", MP_SAVEPNG}, {"SaveILBM", MP_SAVEILBM},
    {"LastPalette", MP_LASTPALETTE}, {"GetPalette", MP_GETPALETTE}, {"Quantize", MP_QUANTIZE},
    {"RemapImage", MP_REMAPIMAGE}, {"DashRect", MP_DASHRECT}, {"ImageHash", MP_IMAGEHASH},
    {"DrawTextScaled", MP_DRAWTEXTSCALED}, {"ImagePoint", MP_IMAGEPOINT}, {"ClearRect", MP_CLEARRECT},
    {"ImageBounds", MP_IMAGEBOUNDS}, {"Checker", MP_CHECKER}, {"FillBounds", MP_FILLBOUNDS}, {"Gradient", MP_GRADIENT}, {"LinearGradient", MP_LINEARGRADIENT},
};

static int32_t paint_find(const char *name)
{
    size_t i;
    for (i = 0; i < sizeof paint_members / sizeof paint_members[0]; i++)
        if (strcasecmp(paint_members[i].name, name) == 0) return paint_members[i].id;
    return BB_NOMEMBER;
}

/* VB colour -> pixel; -1 = transparent */
static uint32_t pcol(int32_t vb) { return vb == -1 ? 0u : ARGB(vb); }

/* image id, 0 = the back buffer */
static cv_image img0(bb_canvas *c, int32_t id)
{
    cv_image r;
    if (id == 0) { r.w = c->w; r.h = c->h; r.px = c->back; return r; }
    return *image(c, id);
}

static uint32_t *px_alloc(int32_t w, int32_t h)
{
    uint32_t *p;
    if (w < 1 || h < 1 || w > 4096 || h > 4096) bb_raise(380, NULL);
    p = (uint32_t *)calloc((size_t)w * (size_t)h, 4);
    if (!p) bb_raise(7, NULL);
    return p;
}

/* a Long array (0 To n-1) of vals, as a call's result; Empty when n < 1 */
static bb_value long_array(const int32_t *vals, int32_t n)
{
    bb_array *a;
    if (n < 1) return bb_v_make(BB_EMPTY);
    a = bb_arr_new1(BB_LONG, 0, n - 1);
    memcpy(a->data, vals, sizeof(int32_t) * (size_t)n);
    return bb_v_arr(a);
}

/* ---------------------------------------------------------------- flood fill */

static int col_near(uint32_t a, uint32_t b, int32_t tol)
{
    int32_t d;
    if (a == b) return 1;
    if (tol <= 0) return 0;
    if ((a >> 24) != (b >> 24)) return 0;
    d = (int32_t)((a >> 16) & 255) - (int32_t)((b >> 16) & 255); if (d < 0) d = -d; if (d > tol) return 0;
    d = (int32_t)((a >> 8) & 255) - (int32_t)((b >> 8) & 255); if (d < 0) d = -d; if (d > tol) return 0;
    d = (int32_t)(a & 255) - (int32_t)(b & 255); if (d < 0) d = -d; if (d > tol) return 0;
    return 1;
}

static int32_t fill_bounds[4];   /* x, y, w, h of the last FloodFill */

/* scanline fill, 4-connected; returns the number of pixels filled */
static int32_t flood(bb_canvas *c, int32_t x, int32_t y, uint32_t col, int32_t tol)
{
    int32_t w = c->tw, h = c->th, n = 0, sp = 0, cap = 1024;
    uint32_t *p = c->tp, old;
    int32_t *st;
    unsigned char *done = NULL;
    int32_t bx1 = w, by1 = h, bx2 = -1, by2 = -1;
    fill_bounds[0] = fill_bounds[1] = fill_bounds[2] = fill_bounds[3] = 0;
    if ((uint32_t)x >= (uint32_t)w || (uint32_t)y >= (uint32_t)h) return 0;
    old = p[y * w + x];
    if (old == col && tol <= 0) return 0;
    if (tol > 0) {               /* with a tolerance the new colour can match too: remember */
        done = (unsigned char *)calloc((size_t)w * (size_t)h, 1);
        if (!done) bb_raise(7, NULL);
    }
    st = (int32_t *)malloc(sizeof(int32_t) * 2 * (size_t)cap);
    if (!st) { free(done); bb_raise(7, NULL); }
#define FILLABLE(xx, yy) (done ? (!done[(yy) * w + (xx)] && col_near(p[(yy) * w + (xx)], old, tol)) \
                               : p[(yy) * w + (xx)] == old)
#define PUSH(xx, yy) do { if (sp == cap) { cap *= 2; st = (int32_t *)bb_realloc(st, sizeof(int32_t) * 2 * (size_t)cap); } \
                          st[2 * sp] = (xx); st[2 * sp + 1] = (yy); sp++; } while (0)
    PUSH(x, y);
    while (sp > 0) {
        int32_t lx, rx, i, yy;
        sp--;
        x = st[2 * sp];
        y = st[2 * sp + 1];
        if (!FILLABLE(x, y)) continue;
        lx = x;
        while (lx > 0 && FILLABLE(lx - 1, y)) lx--;
        rx = x;
        while (rx < w - 1 && FILLABLE(rx + 1, y)) rx++;
        for (i = lx; i <= rx; i++) {
            p[y * w + i] = col;
            if (done) done[y * w + i] = 1;
        }
        n += rx - lx + 1;
        if (lx < bx1) bx1 = lx;
        if (rx > bx2) bx2 = rx;
        if (y < by1) by1 = y;
        if (y > by2) by2 = y;
        for (yy = y - 1; yy <= y + 1; yy += 2) {
            int in = 0;
            if (yy < 0 || yy >= h) continue;
            for (i = lx; i <= rx; i++) {
                if (FILLABLE(i, yy)) {
                    if (!in) { PUSH(i, yy); in = 1; }
                } else in = 0;
            }
        }
    }
#undef FILLABLE
#undef PUSH
    free(st);
    free(done);
    if (bx2 >= 0) { fill_bounds[0] = bx1; fill_bounds[1] = by1; fill_bounds[2] = bx2 - bx1 + 1; fill_bounds[3] = by2 - by1 + 1; }
    return n;
}

/* ---------------------------------------------------------------- shapes */

static void ellipse(bb_canvas *c, int32_t cx, int32_t cy, int32_t rx, int32_t ry, uint32_t col, int filled)
{
    /* half widths per row and half heights per column: a connected outline, exact fills */
    int32_t k;
    if (rx < 0 || ry < 0) return;
    if (rx == 0 || ry == 0) {
        for (k = -ry; k <= ry; k++) hspan(c, cx - rx, cx + rx, cy + k, col);
        return;
    }
    for (k = -ry; k <= ry; k++) {
        double t = 1.0 - ((double)k * k) / ((double)ry * ry);
        int32_t hw = (int32_t)floor(rx * sqrt(t < 0 ? 0 : t) + 0.5);
        if (filled) hspan(c, cx - hw, cx + hw, cy + k, col);
        else { plot(c, cx - hw, cy + k, col); plot(c, cx + hw, cy + k, col); }
    }
    if (!filled)
        for (k = -rx; k <= rx; k++) {
            double t = 1.0 - ((double)k * k) / ((double)rx * rx);
            int32_t hh = (int32_t)floor(ry * sqrt(t < 0 ? 0 : t) + 0.5);
            plot(c, cx + k, cy - hh, col);
            plot(c, cx + k, cy + hh, col);
        }
}

/* a round (shape 0) or square (1) dab of diameter size centred on (x, y) */
static void dab(bb_canvas *c, int32_t x, int32_t y, int32_t size, uint32_t col, int shape)
{
    int32_t r = size / 2, k;
    if (size <= 1) { plot(c, x, y, col); return; }
    if (shape == 1) { fill_rect(c, x - r, y - r, x - r + size - 1, y - r + size - 1, col); return; }
    {
        /* disc of diameter `size`: works for even sizes too (centre between pixels) */
        double rr = size / 2.0, cxf = x - r + (size - 1) / 2.0, cyf = y - r + (size - 1) / 2.0;
        for (k = 0; k < size; k++) {
            double dy = (y - r + k) - cyf, hw2 = rr * rr - dy * dy;
            int32_t x1, x2;
            double hw;
            if (hw2 < 0) continue;
            hw = 0;
            { double lo = 0, hi = rr; int it; for (it = 0; it < 20; it++) { double m = (lo + hi) / 2; if (m * m <= hw2) lo = m; else hi = m; } hw = lo; }
            x1 = (int32_t)(cxf - hw + 0.5);
            x2 = (int32_t)(cxf + hw + 0.5 - 1e-9);
            if (x2 < x1) continue;
            hspan(c, x1, x2, y - r + k, col);
        }
    }
}

/* call f for every point of the line, spaced every `step` pixels */
static void brush_line(bb_canvas *c, int32_t x1, int32_t y1, int32_t x2, int32_t y2, int32_t size, uint32_t col, int shape)
{
    int32_t dx = x2 > x1 ? x2 - x1 : x1 - x2, dy = y2 > y1 ? y1 - y2 : y2 - y1;
    int32_t sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1, e = dx + dy, e2;
    if (size <= 1) { line(c, x1, y1, x2, y2, col); return; }
    if (shape == 0 && size > 2) {
        /* round brush: one dab at each end, the body as a filled quad (fast for big brushes) */
        double len = sqrt((double)dx * dx + (double)dy * dy), r = size / 2.0;
        dab(c, x1, y1, size, col, 0);
        if (len >= 1) {
            double nx = -(y2 - y1) / len * r, ny = (x2 - x1) / len * r;
            int32_t xs[4], ys[4];
            double ox = (size % 2) ? 0 : -0.5;
            xs[0] = (int32_t)floor(x1 + nx + ox + 0.5); ys[0] = (int32_t)floor(y1 + ny + ox + 0.5);
            xs[1] = (int32_t)floor(x2 + nx + ox + 0.5); ys[1] = (int32_t)floor(y2 + ny + ox + 0.5);
            xs[2] = (int32_t)floor(x2 - nx + ox + 0.5); ys[2] = (int32_t)floor(y2 - ny + ox + 0.5);
            xs[3] = (int32_t)floor(x1 - nx + ox + 0.5); ys[3] = (int32_t)floor(y1 - ny + ox + 0.5);
            fill_poly(c, xs, ys, 4, col);
            dab(c, x2, y2, size, col, 0);
        }
        return;
    }
    for (;;) {
        dab(c, x1, y1, size, col, shape);
        if (x1 == x2 && y1 == y2) break;
        e2 = 2 * e;
        if (e2 >= dy) { e += dy; x1 += sx; }
        if (e2 <= dx) { e += dx; y1 += sy; }
    }
}

/* custom brush: image im centred on (x, y); tint -2 = its own colours, -1 = erase, else one colour */
static void stamp(bb_canvas *c, const cv_image *im, int32_t x, int32_t y, int32_t tint)
{
    int32_t i, j, ox = x - im->w / 2, oy = y - im->h / 2;
    uint32_t t = tint == -2 ? 0 : pcol(tint);
    if (im->px == c->tp) return;
    for (j = 0; j < im->h; j++) {
        int32_t yy = oy + j;
        const uint32_t *s;
        uint32_t *d;
        if ((uint32_t)yy >= (uint32_t)c->th) continue;
        s = im->px + j * im->w;
        d = c->tp + yy * c->tw;
        for (i = 0; i < im->w; i++) {
            int32_t xx = ox + i;
            if ((uint32_t)xx >= (uint32_t)c->tw || !(s[i] >> 24)) continue;
            d[xx] = tint == -2 ? s[i] : t;
        }
    }
}

static void stamp_line(bb_canvas *c, const cv_image *im, int32_t x1, int32_t y1, int32_t x2, int32_t y2,
                       int32_t tint, int32_t spacing)
{
    int32_t dx = x2 > x1 ? x2 - x1 : x1 - x2, dy = y2 > y1 ? y1 - y2 : y2 - y1;
    int32_t sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1, e = dx + dy, e2, k = 0;
    if (spacing < 1) spacing = 1;
    for (;;) {
        if (k % spacing == 0 || (x1 == x2 && y1 == y2)) stamp(c, im, x1, y1, tint);
        k++;
        if (x1 == x2 && y1 == y2) break;
        e2 = 2 * e;
        if (e2 >= dy) { e += dy; x1 += sx; }
        if (e2 <= dx) { e += dx; y1 += sy; }
    }
}

/* ---------------------------------------------------------------- scaled and blended blits */

/* nearest neighbour: source rect (sx, sy, sw, sh) of im to dest rect (dx, dy, dw, dh) of the target */
static void blit_scaled(bb_canvas *c, const cv_image *im, int32_t sx, int32_t sy, int32_t sw, int32_t sh,
                        int32_t dx, int32_t dy, int32_t dw, int32_t dh, int opaque)
{
    int32_t x0, x1, y0, y1, i, j;
    int32_t *xmap;
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 || im->px == c->tp) return;
    x0 = dx < 0 ? 0 : dx;
    y0 = dy < 0 ? 0 : dy;
    x1 = dx + dw > c->tw ? c->tw : dx + dw;
    y1 = dy + dh > c->th ? c->th : dy + dh;
    if (x0 >= x1 || y0 >= y1) return;
    xmap = (int32_t *)malloc(sizeof(int32_t) * (size_t)(x1 - x0));
    if (!xmap) bb_raise(7, NULL);
    for (i = x0; i < x1; i++) {
        int32_t s = sx + (int32_t)(((int64_t)(i - dx) * sw) / dw);
        xmap[i - x0] = (s < 0 || s >= im->w) ? -1 : s;
    }
    for (j = y0; j < y1; j++) {
        int32_t s = sy + (int32_t)(((int64_t)(j - dy) * sh) / dh);
        const uint32_t *src;
        uint32_t *d = c->tp + j * c->tw;
        if (s < 0 || s >= im->h) continue;
        src = im->px + s * im->w;
        /* rows that map to the same source row as the previous one: copy that row */
        if (j > y0 && sy + (int32_t)(((int64_t)(j - 1 - dy) * sh) / dh) == s && opaque) {
            memcpy(d + x0, d - c->tw + x0, sizeof(uint32_t) * (size_t)(x1 - x0));
            continue;
        }
        if (opaque) {
            for (i = x0; i < x1; i++) { int32_t m = xmap[i - x0]; if (m >= 0) d[i] = src[m]; }
        } else {
            for (i = x0; i < x1; i++) { int32_t m = xmap[i - x0]; if (m >= 0 && (src[m] >> 24)) d[i] = src[m]; }
        }
    }
    free(xmap);
}

/* u / 255 for u <= 255 * 255 + 127, without a divide (slow on the PPC guest); exact */
#define DIV255(u) (((u) + 1 + (((u) + 1) >> 8)) >> 8)

static inline uint32_t blend_px(uint32_t d, uint32_t s, uint32_t a)
{
    /* s over d with alpha a (0..255), rounded; result opaque if d was */
    uint32_t ia = 255 - a, r, g, b, da;
    if (!(d >> 24)) return (s & 0xFFFFFFu) | (a << 24);
    r = DIV255(((s >> 16) & 255) * a + ((d >> 16) & 255) * ia + 127);
    g = DIV255(((s >> 8) & 255) * a + ((d >> 8) & 255) * ia + 127);
    b = DIV255((s & 255) * a + (d & 255) * ia + 127);
    da = (d >> 24) + DIV255((255 - (d >> 24)) * a + 127);
    return (da << 24) | (r << 16) | (g << 8) | b;
}

static void blit_blend(bb_canvas *c, const cv_image *im, int32_t sx, int32_t sy, int32_t sw, int32_t sh,
                       int32_t x, int32_t y, int32_t alpha)
{
    int32_t i, j;
    if (alpha <= 0) return;
    if (alpha > 255) alpha = 255;
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
        for (i = 0; i < sw; i++) {
            uint32_t a = alpha == 255 ? s[i] >> 24 : DIV255((s[i] >> 24) * (uint32_t)alpha);
            if (!a) continue;
            d[i] = a == 255 ? s[i] : blend_px(d[i], s[i], a);
        }
    }
}

/* ---------------------------------------------------------------- image transforms */

static int32_t copy_image(bb_canvas *c, int32_t id, int32_t x, int32_t y, int32_t w, int32_t h)
{
    cv_image s = img0(c, id);
    uint32_t *px;
    int32_t j, i;
    px = px_alloc(w, h);
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++) {
            int32_t xx = x + i, yy = y + j;
            if ((uint32_t)xx < (uint32_t)s.w && (uint32_t)yy < (uint32_t)s.h) px[j * w + i] = s.px[yy * s.w + xx];
        }
    return add_image(c, w, h, px);
}

static void flip_image(bb_canvas *c, int32_t id, int vertical)
{
    cv_image s = img0(c, id);
    int32_t i, j;
    if (vertical) {
        for (j = 0; j < s.h / 2; j++)
            for (i = 0; i < s.w; i++) {
                uint32_t t = s.px[j * s.w + i];
                s.px[j * s.w + i] = s.px[(s.h - 1 - j) * s.w + i];
                s.px[(s.h - 1 - j) * s.w + i] = t;
            }
    } else {
        for (j = 0; j < s.h; j++)
            for (i = 0; i < s.w / 2; i++) {
                uint32_t t = s.px[j * s.w + i];
                s.px[j * s.w + i] = s.px[j * s.w + s.w - 1 - i];
                s.px[j * s.w + s.w - 1 - i] = t;
            }
    }
}

/* a new image: id turned quarter * 90 degrees clockwise */
static int32_t rotate_image(bb_canvas *c, int32_t id, int32_t quarter)
{
    cv_image s = img0(c, id);
    int32_t q = ((quarter % 4) + 4) % 4, w = (q & 1) ? s.h : s.w, h = (q & 1) ? s.w : s.h, i, j;
    uint32_t *px = px_alloc(w, h);
    for (j = 0; j < s.h; j++)
        for (i = 0; i < s.w; i++) {
            int32_t x, y;
            switch (q) {
            case 0: x = i; y = j; break;
            case 1: x = s.h - 1 - j; y = i; break;
            case 2: x = s.w - 1 - i; y = s.h - 1 - j; break;
            default: x = j; y = s.w - 1 - i; break;
            }
            px[y * w + x] = s.px[j * s.w + i];
        }
    return add_image(c, w, h, px);
}

/* a new image: id scaled to w x h; smooth = box filter when shrinking, bilinear when growing */
static int32_t scale_image(bb_canvas *c, int32_t id, int32_t w, int32_t h, int smooth)
{
    cv_image s = img0(c, id);
    uint32_t *px = px_alloc(w, h);
    int32_t i, j;
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++) {
            if (!smooth) {
                int32_t sx = (int32_t)(((int64_t)i * s.w) / w), sy = (int32_t)(((int64_t)j * s.h) / h);
                px[j * w + i] = s.px[sy * s.w + sx];
            } else {
                /* average of the source pixels covered (at least one) */
                int32_t x0 = (int32_t)(((int64_t)i * s.w) / w), x1 = (int32_t)(((int64_t)(i + 1) * s.w) / w);
                int32_t y0 = (int32_t)(((int64_t)j * s.h) / h), y1 = (int32_t)(((int64_t)(j + 1) * s.h) / h);
                uint32_t a = 0, r = 0, g = 0, b = 0, n = 0;
                int32_t xx, yy;
                if (x1 <= x0) x1 = x0 + 1;
                if (y1 <= y0) y1 = y0 + 1;
                for (yy = y0; yy < y1 && yy < s.h; yy++)
                    for (xx = x0; xx < x1 && xx < s.w; xx++) {
                        uint32_t p = s.px[yy * s.w + xx];
                        a += p >> 24; r += (p >> 16) & 255; g += (p >> 8) & 255; b += p & 255; n++;
                    }
                if (!n) n = 1;
                px[j * w + i] = ((a / n) << 24) | ((r / n) << 16) | ((g / n) << 8) | (b / n);
            }
        }
    return add_image(c, w, h, px);
}

static int32_t replace_color(bb_canvas *c, uint32_t from, uint32_t to, int32_t x, int32_t y, int32_t w, int32_t h)
{
    int32_t i, j, n = 0;
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > c->tw) w = c->tw - x;
    if (y + h > c->th) h = c->th - y;
    for (j = 0; j < h; j++) {
        uint32_t *d = c->tp + (y + j) * c->tw + x;
        for (i = 0; i < w; i++) if (d[i] == from) { d[i] = to; n++; }
    }
    return n;
}

/* ---------------------------------------------------------------- airbrush */

static uint32_t spray_seed = 0x2545F491u;

static uint32_t xrand(void)
{
    spray_seed ^= spray_seed << 13;
    spray_seed ^= spray_seed >> 17;
    spray_seed ^= spray_seed << 5;
    return spray_seed;
}

static void spray(bb_canvas *c, int32_t x, int32_t y, int32_t r, int32_t n, uint32_t col)
{
    int32_t k;
    if (r < 1) { plot(c, x, y, col); return; }
    for (k = 0; k < n; k++) {
        /* uniform in the disc, denser in the middle (two randoms, take the smaller radius) */
        int32_t dx, dy;
        do {
            dx = (int32_t)(xrand() % (uint32_t)(2 * r + 1)) - r;
            dy = (int32_t)(xrand() % (uint32_t)(2 * r + 1)) - r;
        } while (dx * dx + dy * dy > r * r);
        if ((xrand() & 3) == 0) { dx /= 2; dy /= 2; }
        plot(c, x + dx, y + dy, col);
    }
}

/* ---------------------------------------------------------------- palettes */

static int32_t last_pal[256], last_pal_n;

/* the distinct colours of an image (VB colours, transparent skipped), -1 if more than max */
static int32_t get_palette(const cv_image *s, int32_t *pal, int32_t max)
{
    int32_t n = 0, i, k;
    uint32_t *hs = (uint32_t *)malloc(4096 * sizeof(uint32_t));
    unsigned char *used = (unsigned char *)calloc(4096, 1);
    if (!hs || !used) { free(hs); free(used); bb_raise(7, NULL); }
    for (i = 0; i < s->w * s->h; i++) {
        uint32_t p = s->px[i], hk;
        if (!(p >> 24)) continue;
        p &= 0xFFFFFFu;
        hk = (p * 2654435761u) >> 20;
        for (k = 0; k < 4096; k++, hk = (hk + 1) & 4095) {
            if (!used[hk]) {
                if (n >= max) { free(hs); free(used); return -1; }
                used[hk] = 1;
                hs[hk] = p;
                pal[n++] = VBCOL(p);
                break;
            }
            if (hs[hk] == p) break;
        }
    }
    free(hs);
    free(used);
    return n;
}

typedef struct { int32_t lo, hi; } mc_box;     /* range into the colour list */

/* median cut: up to n colours for image s into pal (VB colours); returns the number made */
static int32_t quantize(const cv_image *s, int32_t *pal, int32_t n)
{
    /* histogram on 5 bits per channel, then median cut over the distinct cells (weighted by count) */
    uint32_t *hist, *cols;
    int32_t ncols = 0, i, nb = 1;
    mc_box boxes[256];
    if (n < 1) return 0;
    if (n > 256) n = 256;
    {
        int32_t direct = get_palette(s, pal, n);
        if (direct >= 0) return direct;
    }
    hist = (uint32_t *)calloc(32768, 4);
    cols = (uint32_t *)malloc(32768 * 8);
    if (!hist || !cols) { free(hist); free(cols); bb_raise(7, NULL); }
    for (i = 0; i < s->w * s->h; i++) {
        uint32_t p = s->px[i];
        if (!(p >> 24)) continue;
        hist[((p >> 9) & 0x7C00) | ((p >> 6) & 0x3E0) | ((p >> 3) & 0x1F)]++;
    }
    /* cols: pairs (colour as 0xRRGGBB of the cell centre, count) */
    for (i = 0; i < 32768; i++)
        if (hist[i]) {
            uint32_t r = ((i >> 10) & 31) * 8 + 4, g = ((i >> 5) & 31) * 8 + 4, b = (i & 31) * 8 + 4;
            cols[2 * ncols] = (r << 16) | (g << 8) | b;
            cols[2 * ncols + 1] = hist[i];
            ncols++;
        }
    free(hist);
    if (ncols == 0) { free(cols); return 0; }
    boxes[0].lo = 0;
    boxes[0].hi = ncols;
    while (nb < n) {
        /* split the box with the largest range (weighted by its pixel count) */
        int32_t best = -1, bestaxis = 0, b, ax;
        double bestscore = 0;
        for (b = 0; b < nb; b++) {
            int32_t mn[3] = {255, 255, 255}, mx[3] = {0, 0, 0};
            double cnt = 0;
            if (boxes[b].hi - boxes[b].lo < 2) continue;
            for (i = boxes[b].lo; i < boxes[b].hi; i++) {
                uint32_t p = cols[2 * i];
                for (ax = 0; ax < 3; ax++) {
                    int32_t v = (int32_t)((p >> (16 - 8 * ax)) & 255);
                    if (v < mn[ax]) mn[ax] = v;
                    if (v > mx[ax]) mx[ax] = v;
                }
                cnt += cols[2 * i + 1];
            }
            for (ax = 0; ax < 3; ax++) {
                double score = (double)(mx[ax] - mn[ax]) * (ax == 1 ? 1.2 : 1.0) * sqrt(cnt);
                if (score > bestscore) { bestscore = score; best = b; bestaxis = ax; }
            }
        }
        if (best < 0) break;
        {
            /* sort the box's colours along the axis (pairs: sort indexes via a temp array) */
            int32_t lo = boxes[best].lo, hi = boxes[best].hi, m = hi - lo, k;
            uint64_t *tmp = (uint64_t *)malloc(sizeof(uint64_t) * (size_t)m);
            double half = 0, acc = 0;
            int32_t split;
            if (!tmp) { free(cols); bb_raise(7, NULL); }
            for (k = 0; k < m; k++) {
                uint32_t p = cols[2 * (lo + k)];
                uint32_t key = (p >> (16 - 8 * bestaxis)) & 255;
                tmp[k] = ((uint64_t)key << 56) | ((uint64_t)cols[2 * (lo + k) + 1] << 24) | p;
            }
            {
                /* shell sort by the key in the top byte */
                int32_t a, gap;
                for (gap = m / 2; gap > 0; gap /= 2)
                    for (a = gap; a < m; a++) {
                        uint64_t t = tmp[a];
                        int32_t q = a;
                        while (q >= gap && (tmp[q - gap] >> 56) > (t >> 56)) { tmp[q] = tmp[q - gap]; q -= gap; }
                        tmp[q] = t;
                    }
            }
            for (k = 0; k < m; k++) {
                cols[2 * (lo + k)] = (uint32_t)(tmp[k] & 0xFFFFFFu);
                cols[2 * (lo + k) + 1] = (uint32_t)((tmp[k] >> 24) & 0xFFFFFFFFu);
                half += cols[2 * (lo + k) + 1];
            }
            free(tmp);
            half /= 2;
            split = lo + 1;
            for (k = lo; k < hi - 1; k++) {
                acc += cols[2 * k + 1];
                if (acc >= half) { split = k + 1; break; }
            }
            boxes[nb].lo = split;
            boxes[nb].hi = hi;
            boxes[best].hi = split;
            nb++;
        }
    }
    for (i = 0; i < nb; i++) {
        double r = 0, g = 0, b = 0, cnt = 0;
        int32_t k;
        for (k = boxes[i].lo; k < boxes[i].hi; k++) {
            uint32_t p = cols[2 * k];
            double w = cols[2 * k + 1];
            r += ((p >> 16) & 255) * w; g += ((p >> 8) & 255) * w; b += (p & 255) * w; cnt += w;
        }
        if (cnt <= 0) cnt = 1;
        pal[i] = VBCOL(((uint32_t)(r / cnt + 0.5) << 16) | ((uint32_t)(g / cnt + 0.5) << 8) | (uint32_t)(b / cnt + 0.5));
    }
    free(cols);
    return nb;
}

/* palette lookup with a small cache: pixel (0xRRGGBB) -> nearest palette index */
typedef struct { uint32_t key[1024]; int16_t idx[1024]; const uint32_t *pal; int32_t n; } pal_cache;

static void pc_init(pal_cache *pc, const uint32_t *pal, int32_t n)
{
    int32_t i;
    for (i = 0; i < 1024; i++) pc->idx[i] = -1;
    pc->pal = pal;
    pc->n = n;
}

static int32_t nearest(pal_cache *pc, uint32_t p)
{
    uint32_t h = ((p * 2654435761u) >> 22) & 1023;
    int32_t i, best = 0;
    int64_t bd = -1;
    p &= 0xFFFFFFu;
    if (pc->idx[h] >= 0 && pc->key[h] == p) return pc->idx[h];
    for (i = 0; i < pc->n; i++) {
        int32_t dr = (int32_t)((p >> 16) & 255) - (int32_t)((pc->pal[i] >> 16) & 255);
        int32_t dg = (int32_t)((p >> 8) & 255) - (int32_t)((pc->pal[i] >> 8) & 255);
        int32_t db = (int32_t)(p & 255) - (int32_t)(pc->pal[i] & 255);
        int64_t d = (int64_t)dr * dr * 3 + (int64_t)dg * dg * 4 + (int64_t)db * db * 2;
        if (bd < 0 || d < bd) { bd = d; best = i; if (!d) break; }
    }
    pc->key[h] = p;
    pc->idx[h] = (int16_t)best;
    return best;
}

/* map every opaque pixel of s to the nearest palette colour, optionally with Floyd-Steinberg */
static void remap(cv_image *s, const int32_t *vbpal, int32_t n, int dither)
{
    static uint32_t pal[256];
    pal_cache *pc = (pal_cache *)malloc(sizeof(pal_cache));
    int32_t i, x, y;
    int32_t *err = NULL;
    if (!pc) bb_raise(7, NULL);
    if (n < 1) { free(pc); return; }
    for (i = 0; i < n; i++) pal[i] = ARGB(vbpal[i]) & 0xFFFFFFu;
    pc_init(pc, pal, n);
    if (dither) {
        err = (int32_t *)calloc((size_t)(s->w + 2) * 2 * 3, sizeof(int32_t));
        if (!err) { free(pc); bb_raise(7, NULL); }
    }
    for (y = 0; y < s->h; y++) {
        int32_t *cur = err ? err + (y & 1) * (s->w + 2) * 3 : NULL, *nxt = err ? err + ((y + 1) & 1) * (s->w + 2) * 3 : NULL;
        if (nxt) memset(nxt, 0, sizeof(int32_t) * (size_t)(s->w + 2) * 3);
        for (x = 0; x < s->w; x++) {
            uint32_t p = s->px[y * s->w + x];
            int32_t r, g, b, k;
            if (!(p >> 24)) continue;
            r = (int32_t)((p >> 16) & 255); g = (int32_t)((p >> 8) & 255); b = (int32_t)(p & 255);
            if (cur) {
                r += cur[(x + 1) * 3] / 16; g += cur[(x + 1) * 3 + 1] / 16; b += cur[(x + 1) * 3 + 2] / 16;
                r = r < 0 ? 0 : r > 255 ? 255 : r; g = g < 0 ? 0 : g > 255 ? 255 : g; b = b < 0 ? 0 : b > 255 ? 255 : b;
            }
            k = nearest(pc, ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
            s->px[y * s->w + x] = 0xFF000000u | pal[k];
            if (cur) {
                int32_t e[3], q;
                e[0] = r - (int32_t)((pal[k] >> 16) & 255);
                e[1] = g - (int32_t)((pal[k] >> 8) & 255);
                e[2] = b - (int32_t)(pal[k] & 255);
                for (q = 0; q < 3; q++) {
                    cur[(x + 2) * 3 + q] += e[q] * 7;
                    nxt[x * 3 + q] += e[q] * 3;
                    nxt[(x + 1) * 3 + q] += e[q] * 5;
                    nxt[(x + 2) * 3 + q] += e[q];
                }
            }
        }
    }
    free(err);
    free(pc);
}

/* ---------------------------------------------------------------- PNG: inflate */

typedef struct {
    const uint8_t *in;
    size_t inlen, inpos;
    uint32_t bitbuf;
    int bitcnt;
    uint8_t *out;
    size_t outlen, outpos;
    int err;
} infl;

typedef struct { short count[16]; short symbol[288]; } huff;

static int inf_bits(infl *s, int need)
{
    uint32_t val = s->bitbuf;
    while (s->bitcnt < need) {
        if (s->inpos >= s->inlen) { s->err = 1; return 0; }
        val |= (uint32_t)s->in[s->inpos++] << s->bitcnt;
        s->bitcnt += 8;
    }
    s->bitbuf = val >> need;
    s->bitcnt -= need;
    return (int)(val & ((1u << need) - 1));
}

static int inf_decode(infl *s, const huff *h)
{
    int code = 0, first = 0, index = 0, len, count;
    for (len = 1; len <= 15; len++) {
        code |= inf_bits(s, 1);
        if (s->err) return -1;
        count = h->count[len];
        if (code - count < first) return h->symbol[index + (code - first)];
        index += count;
        first += count;
        first <<= 1;
        code <<= 1;
    }
    s->err = 1;
    return -1;
}

static int inf_construct(huff *h, const short *length, int n)
{
    short offs[16];
    int symbol, len, left;
    for (len = 0; len <= 15; len++) h->count[len] = 0;
    for (symbol = 0; symbol < n; symbol++) h->count[length[symbol]]++;
    if (h->count[0] == n) return 0;
    left = 1;
    for (len = 1; len <= 15; len++) {
        left <<= 1;
        left -= h->count[len];
        if (left < 0) return left;
    }
    offs[1] = 0;
    for (len = 1; len < 15; len++) offs[len + 1] = (short)(offs[len] + h->count[len]);
    for (symbol = 0; symbol < n; symbol++)
        if (length[symbol]) h->symbol[offs[length[symbol]]++] = (short)symbol;
    return left;
}

static const short z_lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
static const short z_lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
static const short z_dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
static const short z_dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};

static void inf_codes(infl *s, const huff *lc, const huff *dc)
{
    for (;;) {
        int sym = inf_decode(s, lc);
        if (s->err) return;
        if (sym < 256) {
            if (s->outpos >= s->outlen) { s->err = 2; return; }
            s->out[s->outpos++] = (uint8_t)sym;
        } else if (sym == 256) return;
        else {
            int len, dist;
            sym -= 257;
            if (sym >= 29) { s->err = 1; return; }
            len = z_lbase[sym] + inf_bits(s, z_lext[sym]);
            sym = inf_decode(s, dc);
            if (s->err || sym < 0 || sym >= 30) { s->err = 1; return; }
            dist = z_dbase[sym] + inf_bits(s, z_dext[sym]);
            if (s->err || (size_t)dist > s->outpos) { s->err = 1; return; }
            if (s->outpos + (size_t)len > s->outlen) { s->err = 2; return; }
            while (len--) { s->out[s->outpos] = s->out[s->outpos - (size_t)dist]; s->outpos++; }
        }
    }
}

static int inflate_buf(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen)
{
    infl s;
    int last;
    static const short order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
    huff *lc = (huff *)malloc(sizeof(huff) * 2), *dc;
    if (!lc) return 0;
    dc = lc + 1;
    memset(&s, 0, sizeof s);
    s.in = in; s.inlen = inlen; s.out = out; s.outlen = outlen;
    if (inlen < 2 || (in[0] & 0x0F) != 8) { free(lc); return 0; }
    s.inpos = 2;
    do {
        int type;
        last = inf_bits(&s, 1);
        type = inf_bits(&s, 2);
        if (s.err) break;
        if (type == 0) {
            unsigned len;
            s.bitbuf = 0; s.bitcnt = 0;
            if (s.inpos + 4 > s.inlen) { s.err = 1; break; }
            len = s.in[s.inpos] | (s.in[s.inpos + 1] << 8);
            s.inpos += 4;
            if (s.inpos + len > s.inlen || s.outpos + len > s.outlen) { s.err = 1; break; }
            memcpy(s.out + s.outpos, s.in + s.inpos, len);
            s.inpos += len; s.outpos += len;
        } else if (type == 1) {
            short lengths[320];
            int k;
            for (k = 0; k < 144; k++) lengths[k] = 8;
            for (; k < 256; k++) lengths[k] = 9;
            for (; k < 280; k++) lengths[k] = 7;
            for (; k < 288; k++) lengths[k] = 8;
            inf_construct(lc, lengths, 288);
            for (k = 0; k < 30; k++) lengths[k] = 5;
            inf_construct(dc, lengths, 30);
            inf_codes(&s, lc, dc);
        } else if (type == 2) {
            short lengths[320];
            int nlen = inf_bits(&s, 5) + 257, ndist = inf_bits(&s, 5) + 1, ncode = inf_bits(&s, 4) + 4, k;
            if (s.err || nlen > 286 || ndist > 30) { s.err = 1; break; }
            for (k = 0; k < ncode; k++) lengths[order[k]] = (short)inf_bits(&s, 3);
            for (; k < 19; k++) lengths[order[k]] = 0;
            if (inf_construct(lc, lengths, 19) != 0) { s.err = 1; break; }
            k = 0;
            while (k < nlen + ndist && !s.err) {
                int sym = inf_decode(&s, lc), len = 0, rep;
                if (sym < 0) break;
                if (sym < 16) { lengths[k++] = (short)sym; continue; }
                if (sym == 16) { if (k == 0) { s.err = 1; break; } len = lengths[k - 1]; rep = 3 + inf_bits(&s, 2); }
                else if (sym == 17) rep = 3 + inf_bits(&s, 3);
                else rep = 11 + inf_bits(&s, 7);
                if (k + rep > nlen + ndist) { s.err = 1; break; }
                while (rep--) lengths[k++] = (short)len;
            }
            if (s.err) break;
            if (inf_construct(lc, lengths, nlen) < 0 || inf_construct(dc, lengths + nlen, ndist) < 0) { s.err = 1; break; }
            inf_codes(&s, lc, dc);
        } else s.err = 1;
    } while (!last && !s.err);
    free(lc);
    return !s.err && s.outpos == outlen;
}

/* ---------------------------------------------------------------- PNG: deflate (fixed Huffman, LZ77) */

typedef struct { uint8_t *buf; size_t len, cap; uint32_t bb; int bc; } bitw;

static void bw_byte(bitw *w, uint8_t b)
{
    if (w->len == w->cap) {
        w->cap = w->cap ? w->cap * 2 : 65536;
        w->buf = (uint8_t *)bb_realloc(w->buf, w->cap);
    }
    w->buf[w->len++] = b;
}

static void bw_bits(bitw *w, uint32_t v, int n)
{
    w->bb |= v << w->bc;
    w->bc += n;
    while (w->bc >= 8) { bw_byte(w, (uint8_t)w->bb); w->bb >>= 8; w->bc -= 8; }
}

static uint32_t rev_bits(uint32_t v, int n)
{
    uint32_t r = 0;
    int i;
    for (i = 0; i < n; i++) { r = (r << 1) | (v & 1); v >>= 1; }
    return r;
}

static void bw_sym(bitw *w, int sym)
{
    if (sym < 144) bw_bits(w, rev_bits(0x30 + sym, 8), 8);
    else if (sym < 256) bw_bits(w, rev_bits(0x190 + sym - 144, 9), 9);
    else if (sym < 280) bw_bits(w, rev_bits(sym - 256, 7), 7);
    else bw_bits(w, rev_bits(0xC0 + sym - 280, 8), 8);
}

static uint8_t *deflate_buf(const uint8_t *in, size_t n, size_t *outlen)
{
    bitw w;
    int32_t *head, *prev;
    size_t i;
    uint32_t a = 1, b = 0;
    memset(&w, 0, sizeof w);
    head = (int32_t *)malloc(sizeof(int32_t) * 65536);
    prev = (int32_t *)malloc(sizeof(int32_t) * 32768);
    if (!head || !prev) { free(head); free(prev); bb_raise(7, NULL); }
    for (i = 0; i < 65536; i++) head[i] = -1;
    bw_byte(&w, 0x78);
    bw_byte(&w, 0x01);
    bw_bits(&w, 1, 1);          /* BFINAL */
    bw_bits(&w, 1, 2);          /* fixed Huffman */
#define HASH3(p) ((((uint32_t)(p)[0] << 10) ^ ((uint32_t)(p)[1] << 5) ^ (uint32_t)(p)[2]) & 0xFFFF)
    i = 0;
    while (i < n) {
        int32_t bestlen = 0, bestdist = 0;
        if (i + 3 <= n) {
            uint32_t hk = HASH3(in + i);
            int32_t cand = head[hk], chain = 48;
            while (cand >= 0 && chain-- > 0 && i - (size_t)cand <= 32768) {
                int32_t l = 0, maxl = (int32_t)(n - i < 258 ? n - i : 258);
                const uint8_t *p = in + cand, *q = in + i;
                if (p[bestlen] == q[bestlen]) {
                    while (l < maxl && p[l] == q[l]) l++;
                    if (l > bestlen) { bestlen = l; bestdist = (int32_t)(i - (size_t)cand); if (l == maxl) break; }
                }
                cand = prev[cand & 32767];
            }
        }
        if (bestlen >= 3) {
            int k, lc = 28, dcode = 29;
            size_t j;
            for (k = 0; k < 29; k++) if (z_lbase[k] > bestlen) { lc = k - 1; break; }
            if (bestlen == 258) lc = 28;
            bw_sym(&w, 257 + lc);
            if (z_lext[lc]) bw_bits(&w, (uint32_t)(bestlen - z_lbase[lc]), z_lext[lc]);
            for (k = 0; k < 30; k++) if (z_dbase[k] > bestdist) { dcode = k - 1; break; }
            bw_bits(&w, rev_bits((uint32_t)dcode, 5), 5);
            if (z_dext[dcode]) bw_bits(&w, (uint32_t)(bestdist - z_dbase[dcode]), z_dext[dcode]);
            for (j = 0; j < (size_t)bestlen; j++, i++)
                if (i + 3 <= n) { uint32_t hk = HASH3(in + i); prev[i & 32767] = head[hk]; head[hk] = (int32_t)i; }
        } else {
            if (i + 3 <= n) { uint32_t hk = HASH3(in + i); prev[i & 32767] = head[hk]; head[hk] = (int32_t)i; }
            bw_sym(&w, in[i]);
            i++;
        }
    }
#undef HASH3
    bw_sym(&w, 256);
    if (w.bc) bw_bits(&w, 0, 8 - w.bc);
    for (i = 0; i < n; i++) { a = (a + in[i]) % 65521; b = (b + a) % 65521; }
    bw_byte(&w, (uint8_t)(b >> 8)); bw_byte(&w, (uint8_t)b); bw_byte(&w, (uint8_t)(a >> 8)); bw_byte(&w, (uint8_t)a);
    free(head);
    free(prev);
    *outlen = w.len;
    return w.buf;
}

/* ---------------------------------------------------------------- PNG: files */

static uint32_t crc_table[256];

static uint32_t crc32_buf(uint32_t crc, const uint8_t *p, size_t n)
{
    size_t i;
    if (!crc_table[1]) {
        uint32_t k, c2;
        int j;
        for (k = 0; k < 256; k++) {
            c2 = k;
            for (j = 0; j < 8; j++) c2 = (c2 & 1) ? 0xEDB88320u ^ (c2 >> 1) : c2 >> 1;
            crc_table[k] = c2;
        }
    }
    crc ^= 0xFFFFFFFFu;
    for (i = 0; i < n; i++) crc = crc_table[(crc ^ p[i]) & 255] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static void put_be32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }

static uint8_t *read_file(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    uint8_t *buf;
    long sz;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz > 64L * 1024 * 1024) { fclose(f); return NULL; }
    buf = (uint8_t *)malloc((size_t)sz);
    if (buf && fread(buf, 1, (size_t)sz, f) != (size_t)sz) { free(buf); buf = NULL; }
    fclose(f);
    *n = (size_t)sz;
    return buf;
}

static int paeth(int a, int b, int c2)
{
    int p = a + b - c2, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c2);
    return (pa <= pb && pa <= pc) ? a : pb <= pc ? b : c2;
}

static uint32_t *load_png_mem(const uint8_t *d, size_t n, int32_t *ow, int32_t *oh)
{
    size_t pos = 8, idlen = 0, rowbytes, rawlen;
    uint8_t *idat = NULL, *raw = NULL;
    uint32_t w = 0, h = 0, y, x;
    static uint32_t plte[256];          /* static: keep the frame small (OS4 runs us on 64 KB) */
    static uint8_t trns[256];
    int depth = 0, ctype = -1, inter = 0, ch, bpp, npal = 0, ntrns = 0, i;
    int32_t trgray = -1;
    uint32_t *px = NULL;
    memset(trns, 255, sizeof trns);
    while (pos + 12 <= n) {
        uint32_t len = be32(d + pos);
        const uint8_t *t = d + pos + 4, *cd = d + pos + 8;
        if (pos + 12 + len > n) break;
        if (!memcmp(t, "IHDR", 4) && len >= 13) {
            w = be32(cd); h = be32(cd + 4); depth = cd[8]; ctype = cd[9]; inter = cd[12];
        } else if (!memcmp(t, "PLTE", 4)) {
            npal = (int)(len / 3) > 256 ? 256 : (int)(len / 3);
            for (i = 0; i < npal; i++) plte[i] = ((uint32_t)cd[3 * i] << 16) | ((uint32_t)cd[3 * i + 1] << 8) | cd[3 * i + 2];
        } else if (!memcmp(t, "tRNS", 4)) {
            if (ctype == 3) { ntrns = len > 256 ? 256 : (int)len; memcpy(trns, cd, (size_t)ntrns); }
            else if (ctype == 0 && len >= 2) trgray = (cd[0] << 8) | cd[1];
        } else if (!memcmp(t, "IDAT", 4)) {
            idat = (uint8_t *)bb_realloc(idat, idlen + len + 1);
            memcpy(idat + idlen, cd, len);
            idlen += len;
        } else if (!memcmp(t, "IEND", 4)) break;
        pos += 12 + len;
    }
    (void)ntrns;
    if (!w || !h || w > 8192 || h > 8192 || inter || !idat) { free(idat); return NULL; }
    switch (ctype) {
    case 0: ch = 1; break;
    case 2: ch = 3; break;
    case 3: ch = 1; break;
    case 4: ch = 2; break;
    case 6: ch = 4; break;
    default: free(idat); return NULL;
    }
    if (depth != 8 && depth != 16 && !((ctype == 0 || ctype == 3) && (depth == 1 || depth == 2 || depth == 4))) { free(idat); return NULL; }
    bpp = (ch * depth + 7) / 8;
    rowbytes = ((size_t)w * (size_t)ch * (size_t)depth + 7) / 8;
    rawlen = (rowbytes + 1) * h;
    raw = (uint8_t *)malloc(rawlen);
    if (!raw || !inflate_buf(idat, idlen, raw, rawlen)) { free(idat); free(raw); return NULL; }
    free(idat);
    /* unfilter in place */
    for (y = 0; y < h; y++) {
        uint8_t *r = raw + y * (rowbytes + 1), ft = r[0], *cur = r + 1, *up = y ? raw + (y - 1) * (rowbytes + 1) + 1 : NULL;
        size_t k;
        for (k = 0; k < rowbytes; k++) {
            int a = k >= (size_t)bpp ? cur[k - bpp] : 0, b = up ? up[k] : 0, c2 = (up && k >= (size_t)bpp) ? up[k - bpp] : 0;
            switch (ft) {
            case 0: break;
            case 1: cur[k] = (uint8_t)(cur[k] + a); break;
            case 2: cur[k] = (uint8_t)(cur[k] + b); break;
            case 3: cur[k] = (uint8_t)(cur[k] + ((a + b) >> 1)); break;
            case 4: cur[k] = (uint8_t)(cur[k] + paeth(a, b, c2)); break;
            default: free(raw); return NULL;
            }
        }
    }
    px = (uint32_t *)malloc((size_t)w * h * 4);
    if (!px) { free(raw); return NULL; }
    last_pal_n = 0;
    if (ctype == 3) {
        for (i = 0; i < npal; i++) last_pal[i] = VBCOL(plte[i]);
        last_pal_n = npal;
    }
    for (y = 0; y < h; y++) {
        const uint8_t *r = raw + y * (rowbytes + 1) + 1;
        for (x = 0; x < w; x++) {
            uint32_t p = 0;
            if (depth < 8) {
                int v = (r[(x * depth) / 8] >> (8 - depth - (int)((x * depth) % 8))) & ((1 << depth) - 1);
                if (ctype == 3) p = (v < npal ? plte[v] : 0) | ((uint32_t)trns[v] << 24);
                else { int g = v * 255 / ((1 << depth) - 1); p = 0xFF000000u | ((uint32_t)g * 0x010101u); if (v == trgray) p &= 0xFFFFFFu; }
            } else {
                int s = depth / 8;     /* 1 or 2 bytes per sample; take the high byte */
                const uint8_t *q = r + (size_t)x * ch * s;
                switch (ctype) {
                case 0: p = 0xFF000000u | ((uint32_t)q[0] * 0x010101u);
                        if (trgray >= 0 && (s == 1 ? q[0] : (q[0] << 8 | q[1])) == trgray) p &= 0xFFFFFFu; break;
                case 2: p = 0xFF000000u | ((uint32_t)q[0] << 16) | ((uint32_t)q[s] << 8) | q[2 * s]; break;
                case 3: p = (q[0] < npal ? plte[q[0]] : 0) | ((uint32_t)trns[q[0]] << 24); break;
                case 4: p = ((uint32_t)q[s] << 24) | ((uint32_t)q[0] * 0x010101u); break;
                default: p = ((uint32_t)q[3 * s] << 24) | ((uint32_t)q[0] << 16) | ((uint32_t)q[s] << 8) | q[2 * s]; break;
                }
            }
            /* a fully transparent pixel is 0, as the canvas's own transparent */
            px[y * w + x] = (p >> 24) ? p : 0;
        }
    }
    free(raw);
    *ow = (int32_t)w;
    *oh = (int32_t)h;
    return px;
}

static void png_chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len)
{
    uint8_t hdr[8];
    uint32_t crc;
    put_be32(hdr, len);
    memcpy(hdr + 4, type, 4);
    fwrite(hdr, 1, 8, f);
    if (len) fwrite(data, 1, len, f);
    crc = crc32_buf(0, hdr + 4, 4);
    crc = crc32_buf(crc, data, len);
    put_be32(hdr, crc);
    fwrite(hdr, 1, 4, f);
}

/* PNG: truecolour (RGB, or RGBA if any pixel is not opaque), or indexed when pal/npal given */
static int save_png(const char *path, const cv_image *s, const int32_t *vbpal, int32_t npal)
{
    int alpha = 0, ch, ft;
    int32_t i, x, y;
    size_t rowbytes, rawlen, zlen;
    uint8_t *raw, *z, ihdr[13], *prevrow, *cand[5];
    FILE *f;
    static uint32_t pal[256];
    pal_cache *pc = NULL;
    for (i = 0; i < s->w * s->h; i++) if ((s->px[i] >> 24) != 255) { alpha = 1; break; }
    if (vbpal && npal > 0) {
        if (npal > 256) npal = 256;
        ch = 1;
        for (i = 0; i < npal; i++) pal[i] = ARGB(vbpal[i]) & 0xFFFFFFu;
        pc = (pal_cache *)malloc(sizeof(pal_cache));
        if (!pc) bb_raise(7, NULL);
        pc_init(pc, pal, npal);
    } else ch = alpha ? 4 : 3;
    rowbytes = (size_t)s->w * (size_t)ch;
    rawlen = (rowbytes + 1) * (size_t)s->h;
    raw = (uint8_t *)malloc(rawlen);
    prevrow = (uint8_t *)calloc(rowbytes, 1);
    for (ft = 0; ft < 5; ft++) cand[ft] = (uint8_t *)malloc(rowbytes);
    if (!raw || !prevrow || !cand[4]) bb_raise(7, NULL);
    for (y = 0; y < s->h; y++) {
        uint8_t *line = cand[0];
        int best = 0;
        long bestsum = -1;
        for (x = 0; x < s->w; x++) {
            uint32_t p = s->px[y * s->w + x];
            if (ch == 1) line[x] = (uint8_t)nearest(pc, p);
            else {
                line[x * ch] = (uint8_t)(p >> 16); line[x * ch + 1] = (uint8_t)(p >> 8); line[x * ch + 2] = (uint8_t)p;
                if (ch == 4) line[x * ch + 3] = (uint8_t)(p >> 24);
            }
        }
        if (ch == 1) best = 0;          /* indexed: no filter (PNG's recommendation) */
        else {
            size_t k;
            int bp = ch;
            for (ft = 1; ft < 5; ft++)
                for (k = 0; k < rowbytes; k++) {
                    int a = k >= (size_t)bp ? line[k - bp] : 0, b = prevrow[k], c2 = k >= (size_t)bp ? prevrow[k - bp] : 0;
                    int pr = ft == 1 ? a : ft == 2 ? b : ft == 3 ? (a + b) >> 1 : paeth(a, b, c2);
                    cand[ft][k] = (uint8_t)(line[k] - pr);
                }
            for (ft = 0; ft < 5; ft++) {
                long sum = 0;
                for (k = 0; k < rowbytes; k++) sum += cand[ft][k] < 128 ? cand[ft][k] : 256 - cand[ft][k];
                if (bestsum < 0 || sum < bestsum) { bestsum = sum; best = ft; }
            }
        }
        raw[y * (rowbytes + 1)] = (uint8_t)best;
        memcpy(raw + y * (rowbytes + 1) + 1, cand[best], rowbytes);
        memcpy(prevrow, line, rowbytes);
    }
    for (ft = 0; ft < 5; ft++) free(cand[ft]);
    free(prevrow);
    free(pc);
    z = deflate_buf(raw, rawlen, &zlen);
    free(raw);
    f = fopen(path, "wb");
    if (!f) { free(z); return 0; }
    fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
    put_be32(ihdr, (uint32_t)s->w);
    put_be32(ihdr + 4, (uint32_t)s->h);
    ihdr[8] = 8;
    ihdr[9] = (uint8_t)(ch == 1 ? 3 : ch == 4 ? 6 : 2);
    ihdr[10] = ihdr[11] = ihdr[12] = 0;
    png_chunk(f, "IHDR", ihdr, 13);
    if (ch == 1) {
        uint8_t pl[768];
        for (i = 0; i < npal; i++) { pl[3 * i] = (uint8_t)(pal[i] >> 16); pl[3 * i + 1] = (uint8_t)(pal[i] >> 8); pl[3 * i + 2] = (uint8_t)pal[i]; }
        png_chunk(f, "PLTE", pl, (uint32_t)(3 * npal));
    }
    png_chunk(f, "IDAT", z, (uint32_t)zlen);
    png_chunk(f, "IEND", NULL, 0);
    free(z);
    return fclose(f) == 0;
}

/* ---------------------------------------------------------------- IFF ILBM */

static uint16_t be16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }

static uint32_t *load_ilbm_mem(const uint8_t *d, size_t n, int32_t *ow, int32_t *oh)
{
    size_t pos = 12, bodylen = 0;
    const uint8_t *body = NULL;
    int w = 0, h = 0, planes = 0, masking = 0, comp = 0, tcol = 0, npal = 0, i, have_bmhd = 0;
    uint32_t camg = 0;
    static uint32_t pal[256];
    uint32_t *px;
    uint8_t *rowbuf;
    int rowbytes, tplanes, y, x, p;
    if (n < 12 || memcmp(d, "FORM", 4) || (memcmp(d + 8, "ILBM", 4) && memcmp(d + 8, "PBM ", 4))) return NULL;
    if (!memcmp(d + 8, "PBM ", 4)) return NULL;     /* chunky PBM: leave it to the datatypes */
    while (pos + 8 <= n) {
        uint32_t len = be32(d + pos + 4);
        const uint8_t *cd = d + pos + 8;
        if (pos + 8 + len > n) len = (uint32_t)(n - pos - 8);
        if (!memcmp(d + pos, "BMHD", 4) && len >= 20) {
            w = be16(cd); h = be16(cd + 2); planes = cd[8]; masking = cd[9]; comp = cd[10]; tcol = be16(cd + 12);
            have_bmhd = 1;
        } else if (!memcmp(d + pos, "CMAP", 4)) {
            npal = (int)(len / 3) > 256 ? 256 : (int)(len / 3);
            for (i = 0; i < npal; i++) pal[i] = ((uint32_t)cd[3 * i] << 16) | ((uint32_t)cd[3 * i + 1] << 8) | cd[3 * i + 2];
        } else if (!memcmp(d + pos, "CAMG", 4) && len >= 4) {
            camg = be32(cd);
        } else if (!memcmp(d + pos, "BODY", 4)) {
            body = cd;
            bodylen = len;
        }
        pos += 8 + len + (len & 1);
    }
    if (!have_bmhd || !body || w <= 0 || h <= 0 || w > 8192 || h > 8192 || planes < 1 || (planes > 8 && planes != 24 && planes != 32) || comp > 1)
        return NULL;
    /* old 4-bit CMAPs (all low nibbles 0): scale up */
    {
        int old = npal > 0;
        for (i = 0; i < npal && old; i++) if (pal[i] & 0x0F0F0F) old = 0;
        if (old) for (i = 0; i < npal; i++) pal[i] |= (pal[i] >> 4) & 0x0F0F0F;
    }
    for (i = npal; i < 256; i++) pal[i] = 0;
    if ((camg & 0x80) && planes == 6) {      /* extra half-brite */
        for (i = 0; i < 32; i++) pal[32 + i] = (pal[i] >> 1) & 0x7F7F7F;
        if (npal < 64) npal = 64;
    }
    last_pal_n = planes <= 8 ? (npal < (1 << planes) ? npal : (1 << planes)) : 0;
    if ((camg & 0x800)) last_pal_n = 0;
    for (i = 0; i < last_pal_n; i++) last_pal[i] = VBCOL(pal[i]);
    rowbytes = ((w + 15) / 16) * 2;
    tplanes = planes + (masking == 1 ? 1 : 0);
    rowbuf = (uint8_t *)malloc((size_t)rowbytes * (size_t)tplanes);
    px = (uint32_t *)malloc((size_t)w * (size_t)h * 4);
    if (!rowbuf || !px) { free(rowbuf); free(px); return NULL; }
    pos = 0;
    for (y = 0; y < h; y++) {
        uint32_t hamc = pal[0];
        for (p = 0; p < tplanes; p++) {
            uint8_t *dst = rowbuf + (size_t)p * rowbytes;
            if (comp == 0) {
                if (pos + (size_t)rowbytes > bodylen) memset(dst, 0, (size_t)rowbytes);
                else memcpy(dst, body + pos, (size_t)rowbytes);
                pos += (size_t)rowbytes;
            } else {
                int k = 0;
                while (k < rowbytes && pos < bodylen) {
                    int8_t c2 = (int8_t)body[pos++];
                    if (c2 >= 0) {
                        int cnt = c2 + 1;
                        while (cnt-- && k < rowbytes) dst[k++] = pos < bodylen ? body[pos++] : 0;
                    } else if (c2 != -128) {
                        int cnt = -c2 + 1;
                        uint8_t v = pos < bodylen ? body[pos++] : 0;
                        while (cnt-- && k < rowbytes) dst[k++] = v;
                    }
                }
                while (k < rowbytes) dst[k++] = 0;
            }
        }
        for (x = 0; x < w; x++) {
            uint32_t v = 0, out;
            int bit = 7 - (x & 7), byte = x >> 3;
            for (p = 0; p < planes; p++) v |= (uint32_t)((rowbuf[(size_t)p * rowbytes + byte] >> bit) & 1) << p;
            if (planes == 24 || planes == 32) {
                out = 0xFF000000u | ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF);
                if (planes == 32) out = (out & 0xFFFFFFu) | ((v >> 24) << 24);
            } else if (camg & 0x800) {    /* HAM6 / HAM8 */
                int cb = planes - 2, ctl = (int)(v >> cb), val = (int)(v & ((1u << cb) - 1));
                int sh = 8 - cb;
                uint32_t vv = (uint32_t)((val << sh) | (val >> (cb - sh > 0 ? cb - sh : 0)));
                if (cb == 4) vv = (uint32_t)(val * 17);
                switch (ctl) {
                case 0: hamc = pal[val]; break;
                case 1: hamc = (hamc & 0xFFFF00u) | vv; break;
                case 2: hamc = (hamc & 0x00FFFFu) | (vv << 16); break;
                default: hamc = (hamc & 0xFF00FFu) | (vv << 8); break;
                }
                out = 0xFF000000u | hamc;
            } else {
                out = 0xFF000000u | pal[v & 255];
                if (masking == 2 && (int)v == tcol) out = 0;
            }
            if (masking == 1 && !((rowbuf[(size_t)planes * rowbytes + byte] >> bit) & 1)) out = 0;
            px[y * w + x] = out;
        }
    }
    free(rowbuf);
    *ow = w;
    *oh = h;
    return px;
}

static void byterun1(const uint8_t *src, int n, bitw *o)
{
    int i = 0;
    while (i < n) {
        int run = 1;
        while (i + run < n && run < 128 && src[i + run] == src[i]) run++;
        if (run >= 3 || (run == 2 && i + run >= n)) {
            bw_byte(o, (uint8_t)(int8_t)(1 - run));
            bw_byte(o, src[i]);
            i += run;
        } else {
            int start = i, lit = 0;
            while (i < n && lit < 128) {
                if (i + 2 < n && src[i] == src[i + 1] && src[i] == src[i + 2]) break;
                i++;
                lit++;
            }
            bw_byte(o, (uint8_t)(lit - 1));
            while (start < i) bw_byte(o, src[start++]);
        }
    }
}

static void put_chunk_hdr(bitw *o, const char *id, uint32_t len)
{
    int k;
    for (k = 0; k < 4; k++) bw_byte(o, (uint8_t)id[k]);
    bw_byte(o, (uint8_t)(len >> 24)); bw_byte(o, (uint8_t)(len >> 16)); bw_byte(o, (uint8_t)(len >> 8)); bw_byte(o, (uint8_t)len);
}

/* IFF ILBM: 24 planes, or indexed (1..8 planes) with the palette, ByteRun1 compressed */
static int save_ilbm(const char *path, const cv_image *s, const int32_t *vbpal, int32_t npal)
{
    bitw o, body;
    int planes, rowbytes, y, x, p, i;
    static uint32_t pal[256];
    pal_cache *pc = NULL;
    uint8_t *prow, *idx = NULL;
    FILE *f;
    size_t formlen;
    memset(&o, 0, sizeof o);
    memset(&body, 0, sizeof body);
    if (vbpal && npal > 0) {
        if (npal > 256) npal = 256;
        for (i = 0; i < npal; i++) pal[i] = ARGB(vbpal[i]) & 0xFFFFFFu;
        planes = 1;
        while ((1 << planes) < npal) planes++;
        pc = (pal_cache *)malloc(sizeof(pal_cache));
        if (!pc) bb_raise(7, NULL);
        pc_init(pc, pal, npal);
    } else planes = 24;
    rowbytes = ((s->w + 15) / 16) * 2;
    prow = (uint8_t *)malloc((size_t)rowbytes);
    idx = (uint8_t *)malloc((size_t)s->w);
    if (!prow || !idx) bb_raise(7, NULL);
    for (y = 0; y < s->h; y++) {
        const uint32_t *row = s->px + y * s->w;
        if (pc) for (x = 0; x < s->w; x++) idx[x] = (uint8_t)nearest(pc, row[x]);
        for (p = 0; p < planes; p++) {
            memset(prow, 0, (size_t)rowbytes);
            for (x = 0; x < s->w; x++) {
                uint32_t v;
                if (pc) v = idx[x];
                else { uint32_t q = row[x]; v = ((q >> 16) & 255) | (q & 0xFF00) | ((q & 255) << 16); }
                if ((v >> p) & 1) prow[x >> 3] |= (uint8_t)(0x80 >> (x & 7));
            }
            byterun1(prow, rowbytes, &body);
        }
    }
    free(prow);
    free(idx);
    free(pc);
    /* FORM ILBM: BMHD, CMAP (indexed), CAMG, BODY */
    formlen = 4 + (8 + 20) + (8 + 4) + 8 + body.len + (body.len & 1);
    if (vbpal && npal > 0) formlen += 8 + (size_t)(3 * npal + ((3 * npal) & 1));
    put_chunk_hdr(&o, "FORM", (uint32_t)formlen);
    bw_byte(&o, 'I'); bw_byte(&o, 'L'); bw_byte(&o, 'B'); bw_byte(&o, 'M');
    put_chunk_hdr(&o, "BMHD", 20);
    bw_byte(&o, (uint8_t)(s->w >> 8)); bw_byte(&o, (uint8_t)s->w);
    bw_byte(&o, (uint8_t)(s->h >> 8)); bw_byte(&o, (uint8_t)s->h);
    for (i = 0; i < 4; i++) bw_byte(&o, 0);          /* x, y */
    bw_byte(&o, (uint8_t)planes);
    bw_byte(&o, 0);                                   /* masking */
    bw_byte(&o, 1);                                   /* ByteRun1 */
    bw_byte(&o, 0);
    bw_byte(&o, 0); bw_byte(&o, 0);                   /* transparent colour */
    bw_byte(&o, 10); bw_byte(&o, 11);                 /* aspect */
    bw_byte(&o, (uint8_t)(s->w >> 8)); bw_byte(&o, (uint8_t)s->w);
    bw_byte(&o, (uint8_t)(s->h >> 8)); bw_byte(&o, (uint8_t)s->h);
    if (vbpal && npal > 0) {
        put_chunk_hdr(&o, "CMAP", (uint32_t)(3 * npal));
        for (i = 0; i < npal; i++) { bw_byte(&o, (uint8_t)(pal[i] >> 16)); bw_byte(&o, (uint8_t)(pal[i] >> 8)); bw_byte(&o, (uint8_t)pal[i]); }
        if ((3 * npal) & 1) bw_byte(&o, 0);
    }
    put_chunk_hdr(&o, "CAMG", 4);
    bw_byte(&o, 0); bw_byte(&o, 0); bw_byte(&o, 0); bw_byte(&o, 0);     /* CAMG 0: no HAM, no EHB */
    put_chunk_hdr(&o, "BODY", (uint32_t)body.len);
    for (i = 0; i < (int)body.len; i++) bw_byte(&o, body.buf[i]);
    if (body.len & 1) bw_byte(&o, 0);
    free(body.buf);
    f = fopen(path, "wb");
    if (!f) { free(o.buf); return 0; }
    fwrite(o.buf, 1, o.len, f);
    free(o.buf);
    return fclose(f) == 0;
}

/* PNG and ILBM by their magic, before the platform's loader; NULL = not one of ours */
static uint32_t *paint_load_picture(const char *path, int32_t *w, int32_t *h)
{
    size_t n = 0;
    uint8_t *d = read_file(path, &n);
    uint32_t *px = NULL;
    if (!d) return NULL;
    if (n > 8 && !memcmp(d, "\x89PNG\r\n\x1a\n", 8)) px = load_png_mem(d, n, w, h);
    else if (n > 12 && !memcmp(d, "FORM", 4)) px = load_ilbm_mem(d, n, w, h);
    free(d);
    return px;
}

/* palette argument: array (Long or Variant) and a count */
static int32_t arg_palette(int argc, bb_value *argv, int i, int32_t *pal)
{
    bb_array *a;
    int32_t n, k;
    if (missing(argc, argv, i)) return 0;
    a = arg_array(argc, argv, i);
    n = argl_opt(argc, argv, i + 1, a->count);
    if (n > 256) n = 256;
    need_count(a, n);
    for (k = 0; k < n; k++) pal[k] = elem_l(a, k);
    return n;
}

/* ---------------------------------------------------------------- dispatch */

static void paint_invoke(bb_canvas *c, int32_t id, int argc, bb_value *argv, bb_value *ret)
{
    bb_str *hold = NULL;
    int32_t len;
    const char *s;
    switch (id) {
    case MP_FLOODFILL:
        *ret = bb_v_long(flood(c, argl(argc, argv, 0), argl(argc, argv, 1), pcol(argl_opt(argc, argv, 2, c->fore)),
                               argl_opt(argc, argv, 3, 0)));
        return;
    case MP_ELLIPSE:
        ellipse(c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3),
                pcol(argl_opt(argc, argv, 4, c->fore)), argl_opt(argc, argv, 5, 0) != 0);
        return;
    case MP_BRUSHLINE:   /* BrushLine x1, y1, x2, y2, size [, colour [, shape]] */
        brush_line(c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3),
                   argl(argc, argv, 4), pcol(argl_opt(argc, argv, 5, c->fore)), argl_opt(argc, argv, 6, 0));
        return;
    case MP_STAMPLINE: { /* StampLine id, x1, y1, x2, y2 [, tint [, spacing]] */
        cv_image *im = image(c, argl(argc, argv, 0));
        stamp_line(c, im, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4),
                   argl_opt(argc, argv, 5, -2), argl_opt(argc, argv, 6, 1));
        return;
    }
    case MP_DRAWIMAGESCALED: { /* id, sx, sy, sw, sh, dx, dy, dw, dh [, opaque] */
        cv_image im = img0(c, argl(argc, argv, 0));
        blit_scaled(c, &im, argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3), argl(argc, argv, 4),
                    argl(argc, argv, 5), argl(argc, argv, 6), argl(argc, argv, 7), argl(argc, argv, 8),
                    argl_opt(argc, argv, 9, 0) != 0);
        return;
    }
    case MP_DRAWIMAGEBLEND: { /* id, x, y, alpha [, sx, sy, w, h] */
        cv_image *im = image(c, argl(argc, argv, 0));
        blit_blend(c, im, argl_opt(argc, argv, 4, 0), argl_opt(argc, argv, 5, 0), argl_opt(argc, argv, 6, im->w),
                   argl_opt(argc, argv, 7, im->h), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3));
        return;
    }
    case MP_COPYIMAGE: { /* CopyImage(id [, x, y, w, h]); id 0 = the back buffer */
        int32_t src = argl(argc, argv, 0);
        cv_image im = img0(c, src);
        *ret = bb_v_long(copy_image(c, src, argl_opt(argc, argv, 1, 0), argl_opt(argc, argv, 2, 0),
                                    argl_opt(argc, argv, 3, im.w), argl_opt(argc, argv, 4, im.h)));
        return;
    }
    case MP_FLIPIMAGE:
        flip_image(c, argl(argc, argv, 0), argl_opt(argc, argv, 1, 0) != 0);
        return;
    case MP_ROTATEIMAGE:
        *ret = bb_v_long(rotate_image(c, argl(argc, argv, 0), argl_opt(argc, argv, 1, 1)));
        return;
    case MP_SCALEIMAGE:
        *ret = bb_v_long(scale_image(c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2),
                                     argl_opt(argc, argv, 3, 0) != 0));
        return;
    case MP_REPLACECOLOR: /* ReplaceColor from, to [, x, y, w, h] -> count */
        *ret = bb_v_long(replace_color(c, pcol(argl(argc, argv, 0)), pcol(argl(argc, argv, 1)), argl_opt(argc, argv, 2, 0),
                                       argl_opt(argc, argv, 3, 0), argl_opt(argc, argv, 4, c->tw), argl_opt(argc, argv, 5, c->th)));
        return;
    case MP_SPRAY: /* Spray x, y, radius, count [, colour [, seed]] */
        if (!missing(argc, argv, 5)) { spray_seed = (uint32_t)argl(argc, argv, 5); if (!spray_seed) spray_seed = 1; }
        spray(c, argl(argc, argv, 0), argl(argc, argv, 1), argl(argc, argv, 2), argl(argc, argv, 3),
              pcol(argl_opt(argc, argv, 4, c->fore)));
        return;
    case MP_SAVEPNG: case MP_SAVEILBM: { /* SavePNG path [, id [, pal(), n]] */
        static int32_t pal[256];
        int32_t np, ok;
        cv_image im;
        s = args_(argc, argv, 0, &hold, &len);
        im = img0(c, argl_opt(argc, argv, 1, 0));
        np = arg_palette(argc, argv, 2, pal);
        ok = id == MP_SAVEPNG ? save_png(s, &im, np ? pal : NULL, np) : save_ilbm(s, &im, np ? pal : NULL, np);
        bb_str_release(hold);
        if (!ok) bb_raise(75, NULL);
        return;
    }
    case MP_LASTPALETTE: /* LastPalette() -> the last loaded file's palette (Long array), Empty if none */
        *ret = long_array(last_pal, last_pal_n);
        return;
    case MP_GETPALETTE: case MP_QUANTIZE: { /* GetPalette(id, max) / Quantize(id, n) -> Long array */
        cv_image im = img0(c, argl(argc, argv, 0));
        static int32_t pal[256];
        int32_t mx = argl(argc, argv, 1), n;
        if (mx < 1 || mx > 256) bb_raise(5, NULL);
        n = id == MP_GETPALETTE ? get_palette(&im, pal, mx) : quantize(&im, pal, mx);
        *ret = long_array(pal, n);
        return;
    }
    case MP_REMAPIMAGE: { /* RemapImage id, pal(), n [, dither] */
        cv_image im = img0(c, argl(argc, argv, 0));
        static int32_t pal[256];
        int32_t n = arg_palette(argc, argv, 1, pal);
        remap(&im, pal, n, argl_opt(argc, argv, 3, 0) != 0);
        return;
    }
    case MP_DASHRECT: { /* DashRect x, y, w, h, col1, col2 [, phase]: marching ants */
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3);
        uint32_t c1 = pcol(argl(argc, argv, 4)), c2 = pcol(argl(argc, argv, 5));
        int32_t ph = argl_opt(argc, argv, 6, 0), k, t = 0;
        if (w <= 0 || h <= 0) return;
        for (k = 0; k < w; k++, t++) plot(c, x + k, y, ((t + ph) & 4) ? c1 : c2);
        for (k = 1; k < h; k++, t++) plot(c, x + w - 1, y + k, ((t + ph) & 4) ? c1 : c2);
        for (k = w - 2; k >= 0; k--, t++) plot(c, x + k, y + h - 1, ((t + ph) & 4) ? c1 : c2);
        for (k = h - 2; k > 0; k--, t++) plot(c, x, y + k, ((t + ph) & 4) ? c1 : c2);
        return;
    }
    case MP_IMAGEHASH: {
        cv_image im = img0(c, argl(argc, argv, 0));
        uint32_t hh = 2166136261u;
        int32_t i;
        for (i = 0; i < im.w * im.h; i++) hh = (hh ^ im.px[i]) * 16777619u;
        *ret = bb_v_long((int32_t)(hh & 0x7FFFFFFFu));
        return;
    }
    case MP_DRAWTEXTSCALED: { /* DrawTextScaled x, y, text, colour, scale */
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), sc, k, r, b;
        uint32_t col;
        s = args_(argc, argv, 2, &hold, &len);
        col = pcol(argl_opt(argc, argv, 3, c->fore));
        sc = argl_opt(argc, argv, 4, 1);
        if (sc < 1) sc = 1;
        for (k = 0; k < len; k++, x += CV_FONT_W * sc) {
            unsigned ch = (unsigned char)s[k];
            const unsigned char *g;
            if (ch == ' ') continue;
            if (ch < 32 || ch > 126) ch = '?';
            g = cv_font[ch - 32];
            for (r = 0; r < CV_FONT_H; r++) {
                unsigned bits = g[r];
                for (b = 0; bits; b++, bits = (bits << 1) & 0xFF)
                    if (bits & 0x80) fill_rect(c, x + b * sc, y + r * sc, x + b * sc + sc - 1, y + r * sc + sc - 1, col);
            }
        }
        bb_str_release(hold);
        return;
    }
    case MP_IMAGEPOINT: { /* ImagePoint(id, x, y): VB colour, -1 transparent or outside */
        cv_image im = img0(c, argl(argc, argv, 0));
        int32_t x = argl(argc, argv, 1), y = argl(argc, argv, 2);
        uint32_t p;
        if ((uint32_t)x >= (uint32_t)im.w || (uint32_t)y >= (uint32_t)im.h) { *ret = bb_v_long(-1); return; }
        p = im.px[y * im.w + x];
        *ret = bb_v_long((p >> 24) ? VBCOL(p) : -1);
        return;
    }
    case MP_CLEARRECT: /* ClearRect x, y, w, h: transparent */
    {
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3);
        if (w > 0 && h > 0) fill_rect(c, x, y, x + w - 1, y + h - 1, 0);
        return;
    }
    case MP_IMAGEBOUNDS: { /* ImageBounds(id) -> Long array x, y, w, h of the opaque pixels; Empty if none */
        cv_image im = img0(c, argl(argc, argv, 0));
        int32_t x0 = im.w, y0 = im.h, x1 = -1, y1 = -1, x, y, r[4];
        for (y = 0; y < im.h; y++)
            for (x = 0; x < im.w; x++)
                if (im.px[y * im.w + x] >> 24) {
                    if (x < x0) x0 = x;
                    if (x > x1) x1 = x;
                    if (y < y0) y0 = y;
                    if (y > y1) y1 = y;
                }
        r[0] = x0; r[1] = y0; r[2] = x1 - x0 + 1; r[3] = y1 - y0 + 1;
        *ret = long_array(r, x1 < 0 ? 0 : 4);
        return;
    }
    case MP_GRADIENT: { /* Gradient x, y, w, h, topleft, topright [, bottomleft, bottomright]: bilinear */
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3), i, j;
        uint32_t cc[4];
        int32_t k;
        cc[0] = ARGB(argl(argc, argv, 4));
        cc[1] = ARGB(argl(argc, argv, 5));
        cc[2] = missing(argc, argv, 6) ? cc[0] : ARGB(argl(argc, argv, 6));
        cc[3] = missing(argc, argv, 7) ? cc[1] : ARGB(argl(argc, argv, 7));
        if (w <= 0 || h <= 0) return;
        for (j = 0; j < h; j++) {
            int32_t yy = y + j, fy = h > 1 ? (j * 256) / (h - 1) : 0;
            uint32_t *d;
            int32_t l[3], r[3];
            if ((uint32_t)yy >= (uint32_t)c->th) continue;
            d = c->tp + yy * c->tw;
            for (k = 0; k < 3; k++) {
                int32_t sh = 16 - 8 * k;
                l[k] = (int32_t)((cc[0] >> sh) & 255) * (256 - fy) + (int32_t)((cc[2] >> sh) & 255) * fy;
                r[k] = (int32_t)((cc[1] >> sh) & 255) * (256 - fy) + (int32_t)((cc[3] >> sh) & 255) * fy;
            }
            for (i = 0; i < w; i++) {
                int32_t xx = x + i, fx = w > 1 ? (i * 256) / (w - 1) : 0, v[3];
                if ((uint32_t)xx >= (uint32_t)c->tw) continue;
                for (k = 0; k < 3; k++) v[k] = (l[k] * (256 - fx) + r[k] * fx + 32768) >> 16;
                d[xx] = 0xFF000000u | ((uint32_t)v[0] << 16) | ((uint32_t)v[1] << 8) | (uint32_t)v[2];
            }
        }
        return;
    }
    case MP_LINEARGRADIENT: { /* LinearGradient x, y, w, h, x1, y1, x2, y2, colour1, colour2 [, dither] */
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3);
        int32_t gx1 = argl(argc, argv, 4), gy1 = argl(argc, argv, 5), gx2 = argl(argc, argv, 6), gy2 = argl(argc, argv, 7);
        uint32_t ca = ARGB(argl(argc, argv, 8)), cb = ARGB(argl(argc, argv, 9));
        int dith = argl_opt(argc, argv, 10, 1) != 0;
        static const int bayer[4][4] = {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}};
        double dx = gx2 - gx1, dy = gy2 - gy1, len2 = dx * dx + dy * dy;
        int32_t i, j;
        if (x < 0) { w += x; x = 0; }
        if (y < 0) { h += y; y = 0; }
        if (x + w > c->tw) w = c->tw - x;
        if (y + h > c->th) h = c->th - y;
        if (w <= 0 || h <= 0) return;
        if (len2 < 1) len2 = 1;
        for (j = 0; j < h; j++) {
            uint32_t *d = c->tp + (y + j) * c->tw + x;
            for (i = 0; i < w; i++) {
                double t = ((x + i - gx1) * dx + (y + j - gy1) * dy) / len2;
                int32_t f, k;
                uint32_t out = 0xFF000000u;
                if (t < 0) t = 0;
                if (t > 1) t = 1;
                f = (int32_t)(t * 4096);
                for (k = 0; k < 3; k++) {
                    int32_t sh = 16 - 8 * k, va = (int32_t)((ca >> sh) & 255), vb = (int32_t)((cb >> sh) & 255);
                    int32_t v16 = (va * (4096 - f) + vb * f) >> 8;          /* value * 16 */
                    int32_t v = dith ? (v16 + bayer[(y + j) & 3][(x + i) & 3]) >> 4 : (v16 + 8) >> 4;
                    if (v > 255) v = 255;
                    out |= (uint32_t)v << sh;
                }
                d[i] = out;
            }
        }
        return;
    }
    case MP_FILLBOUNDS: /* FillBounds() -> x, y, w, h of what the last FloodFill changed */
        *ret = long_array(fill_bounds, 4);
        return;
    case MP_CHECKER: { /* Checker x, y, w, h, size, col1, col2: transparency backdrop */
        int32_t x = argl(argc, argv, 0), y = argl(argc, argv, 1), w = argl(argc, argv, 2), h = argl(argc, argv, 3);
        int32_t sz = argl(argc, argv, 4), i, j;
        uint32_t c1 = pcol(argl(argc, argv, 5)), c2 = pcol(argl(argc, argv, 6));
        if (sz < 1) sz = 1;
        for (j = y < 0 ? 0 : y; j < y + h && j < c->th; j++) {
            uint32_t *d = c->tp + j * c->tw;
            for (i = x < 0 ? 0 : x; i < x + w && i < c->tw; i++) d[i] = ((((i - x) / sz) + ((j - y) / sz)) & 1) ? c2 : c1;
        }
        return;
    }
    }
    bb_raise(438, NULL);
}
