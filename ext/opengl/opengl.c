/* opengl.c - the OpenGL standard extension (docs/opengl.md): Extension=opengl
 *
 * OpenGL 1.x (fixed function) through Mesa 7.8.2's software renderer, OSMesa. It draws straight
 * into a Canvas's pixels: GLAttach binds the GL context to the canvas's current target (its
 * back buffer, or an image), GLPresent waits for GL to finish, then the program shows the canvas
 * with Refresh as usual (drawing a HUD with the Canvas methods first, if it likes). So it works
 * the same in a form's canvas and off-screen, on AmigaOS 4 and on the host (tests).
 *
 * The plain functions (glVertex3f & co.) are generated from the table in tools/gen-opengl.py
 * (opengl_gen.h); this file has the context, the functions that take arrays, GLU's camera
 * helpers and GLUT's solid shapes.
 */
#include "boing_ext.h"
#include "canvas.h"
#define GL_GLEXT_LEGACY
#include "GL/gl.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* OSMesa (osmesa.h includes <GL/gl.h>, which a build of this file may not have on its path) */
typedef struct osmesa_context *OSMesaContext;
#define OSMESA_BGRA 0x1
#define OSMESA_ARGB 0x2
#define OSMESA_Y_UP 0x11
OSMesaContext OSMesaCreateContextExt(GLenum format, GLint depthBits, GLint stencilBits, GLint accumBits, OSMesaContext sharelist);
void OSMesaDestroyContext(OSMesaContext ctx);
GLboolean OSMesaMakeCurrent(OSMesaContext ctx, void *buffer, GLenum type, GLsizei width, GLsizei height);
void OSMesaPixelStore(GLint pname, GLint value);

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static OSMesaContext ctx;
static bb_obj *canvas;              /* the attached canvas (a reference) */
static uint32_t *bound_px;          /* the pixels the context draws into now */
static int32_t bound_w, bound_h;

static GLenum pixel_format(void)
{
    /* the canvas keeps 0xAARRGGBB words: bytes A R G B on big-endian PPC, B G R A on x86/ARM */
    const uint32_t one = 1;
    return *(const unsigned char *)&one ? OSMESA_BGRA : OSMESA_ARGB;
}

/* (re)bind the context to the canvas's current target if its pixels moved or changed size */
static void bind(void)
{
    int32_t w, h;
    uint32_t *px;
    if (!canvas) bb_raise(91, "OpenGL: no canvas attached (call GLAttach first)");
    px = bb_canvas_pixels(canvas, &w, &h);
    if (!px || w <= 0 || h <= 0) bb_raise(5, "OpenGL: the canvas has no pixels");
    if (w > 1024 || h > 1024) bb_raise(5, "OpenGL: the canvas is bigger than 1024 x 1024 (the most this OpenGL draws)");
    if (px == bound_px && w == bound_w && h == bound_h) return;
    if (!ctx) {
        ctx = OSMesaCreateContextExt(pixel_format(), 16, 8, 0, NULL);
        if (!ctx) bb_raise(7, "OpenGL: cannot create the context (out of memory?)");
    }
    if (!OSMesaMakeCurrent(ctx, px, GL_UNSIGNED_BYTE, w, h)) bb_raise(5, "OpenGL: cannot draw into this canvas");
    OSMesaPixelStore(OSMESA_Y_UP, 0);        /* row 0 at the top, as in the canvas */
    if (w != bound_w || h != bound_h) glViewport(0, 0, w, h);
    bound_px = px;
    bound_w = w;
    bound_h = h;
}

static bb_value f_attach(int argc, bb_value *argv)
{
    bb_obj *o = bb_arg_obj(argv, 0);
    (void)argc;
    if (!o || !bb_is_canvas(o)) bb_raise(13, "GLAttach: expected a Canvas");
    bb_obj_retain(o);
    bb_obj_release(canvas);
    canvas = o;
    bound_px = NULL;
    bind();
    return bb_ret_empty();
}

static bb_value f_detach(int argc, bb_value *argv)
{
    (void)argc; (void)argv;
    if (ctx) glFinish();
    bb_obj_release(canvas);
    canvas = NULL;
    bound_px = NULL;
    bound_w = bound_h = 0;
    return bb_ret_empty();
}

static bb_value f_present(int argc, bb_value *argv)
{
    (void)argc; (void)argv;
    bind();
    glFinish();
    return bb_ret_empty();
}

static bb_value f_width(int argc, bb_value *argv) { (void)argc; (void)argv; bind(); return bb_ret_long(bound_w); }
static bb_value f_height(int argc, bb_value *argv) { (void)argc; (void)argv; bind(); return bb_ret_long(bound_h); }
static bb_value f_version(int argc, bb_value *argv)
{
    (void)argc; (void)argv;
    if (!ctx) return bb_ret_str("Mesa 7.8.2 OSMesa (no context yet)");
    return bb_ret_str((const char *)glGetString(GL_VERSION));
}

static bb_value f_clear(int argc, bb_value *argv)
{
    (void)argc;
    bind();          /* the start of a frame: follow the canvas if its target changed */
    glClear((GLbitfield)bb_arg_long(argv, 0));
    return bb_ret_empty();
}

static bb_value f_finish(int argc, bb_value *argv) { (void)argc; (void)argv; glFinish(); return bb_ret_empty(); }

static bb_value f_getstring(int argc, bb_value *argv)
{
    const GLubyte *s;
    (void)argc;
    if (!ctx) bb_raise(91, "OpenGL: no canvas attached (call GLAttach first)");
    s = glGetString((GLenum)bb_arg_long(argv, 0));
    return bb_ret_str(s ? (const char *)s : "");
}

/* a VB colour (&HBBGGRR, as RGB() makes) */
static bb_value f_color_rgb(int argc, bb_value *argv)
{
    bb_long c = bb_arg_long(argv, 0);
    (void)argc;
    glColor3ub((GLubyte)(c & 255), (GLubyte)((c >> 8) & 255), (GLubyte)((c >> 16) & 255));
    return bb_ret_empty();
}

/* ---- arrays ---- */

/* the array in an argument: array variables arrive by reference (no copy), other expressions
   (Array(...), a function's result) as a value */
static bb_array *arr_of(bb_value *v, const char *fn)
{
    bb_value t;
    const bb_value *d = bb_v_deref(v, &t);
    if (!(d->type & BB_ARRAY)) bb_raise(13, fn);
    if (!d->u.a) bb_raise(9, fn);
    return d->u.a;
}

/* the numbers of a numeric array (any element type, any dimensions, in storage order) */
static bb_array *num_array(bb_value *v, const char *fn)
{
    bb_array *a = arr_of(v, fn);
    switch (a->etype) {
    case BB_INTEGER: case BB_LONG: case BB_SINGLE: case BB_DOUBLE: case BB_BYTE: case BB_VARIANT: break;
    default: bb_raise(13, fn);
    }
    return a;
}

static double num_at(const bb_array *a, int32_t i)
{
    const char *p = (const char *)a->data + (size_t)i * (size_t)a->esize;
    switch (a->etype) {
    case BB_INTEGER: return *(const bb_int *)p;
    case BB_LONG: return *(const bb_long *)p;
    case BB_SINGLE: return *(const bb_single *)p;
    case BB_DOUBLE: return *(const bb_double *)p;
    case BB_BYTE: return *(const bb_byte *)p;
    default: return bb_v_to_double((const bb_value *)p);
    }
}

/* the array's numbers as floats in buf (grown as needed); returns the count */
static int32_t to_floats(bb_value *v, GLfloat **buf, int32_t *cap, const char *fn)
{
    bb_array *a = num_array(v, fn);
    int32_t i, n = a->count;
    if (n > *cap) {
        GLfloat *nb = (GLfloat *)realloc(*buf, sizeof(GLfloat) * (size_t)n);
        if (!nb) bb_raise(7, fn);
        *buf = nb;
        *cap = n;
    }
    if (a->etype == BB_SINGLE) memcpy(*buf, a->data, sizeof(GLfloat) * (size_t)n);
    else for (i = 0; i < n; i++) (*buf)[i] = (GLfloat)num_at(a, i);
    return n;
}

static void four(bb_value *v, GLfloat out[4], const char *fn)
{
    bb_array *a = num_array(v, fn);
    int32_t i;
    out[0] = out[1] = out[2] = 0;
    out[3] = 1;
    for (i = 0; i < a->count && i < 4; i++) out[i] = (GLfloat)num_at(a, i);
}

#define ARGS4(f, i) GLfloat f[4]; f[0] = (GLfloat)bb_arg_double(argv, i); f[1] = (GLfloat)bb_arg_double(argv, i + 1); \
                    f[2] = (GLfloat)bb_arg_double(argv, i + 2); f[3] = (GLfloat)bb_arg_double(argv, i + 3)

static bb_value f_light4f(int argc, bb_value *argv) { ARGS4(f, 2); (void)argc; glLightfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f); return bb_ret_empty(); }
static bb_value f_material4f(int argc, bb_value *argv) { ARGS4(f, 2); (void)argc; glMaterialfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f); return bb_ret_empty(); }
static bb_value f_lightmodel4f(int argc, bb_value *argv) { ARGS4(f, 1); (void)argc; glLightModelfv((GLenum)bb_arg_long(argv, 0), f); return bb_ret_empty(); }
static bb_value f_fog4f(int argc, bb_value *argv) { ARGS4(f, 1); (void)argc; glFogfv((GLenum)bb_arg_long(argv, 0), f); return bb_ret_empty(); }
static bb_value f_texenv4f(int argc, bb_value *argv) { ARGS4(f, 2); (void)argc; glTexEnvfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f); return bb_ret_empty(); }
static bb_value f_texgen4f(int argc, bb_value *argv) { ARGS4(f, 2); (void)argc; glTexGenfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f); return bb_ret_empty(); }

static bb_value f_lightfv(int argc, bb_value *argv)
{
    GLfloat f[4];
    (void)argc;
    four(&argv[2], f, "glLightfv: expected an array of numbers");
    glLightfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f);
    return bb_ret_empty();
}

static bb_value f_materialfv(int argc, bb_value *argv)
{
    GLfloat f[4];
    (void)argc;
    four(&argv[2], f, "glMaterialfv: expected an array of numbers");
    glMaterialfv((GLenum)bb_arg_long(argv, 0), (GLenum)bb_arg_long(argv, 1), f);
    return bb_ret_empty();
}

static void matrix16(bb_value *v, GLfloat m[16], const char *fn)
{
    bb_array *a = num_array(v, fn);
    int32_t i;
    if (a->count < 16) bb_raise(9, fn);
    for (i = 0; i < 16; i++) m[i] = (GLfloat)num_at(a, i);
}

static bb_value f_loadmatrix(int argc, bb_value *argv) { GLfloat m[16]; (void)argc; matrix16(&argv[0], m, "glLoadMatrixf: expected 16 numbers"); glLoadMatrixf(m); return bb_ret_empty(); }
static bb_value f_multmatrix(int argc, bb_value *argv) { GLfloat m[16]; (void)argc; matrix16(&argv[0], m, "glMultMatrixf: expected 16 numbers"); glMultMatrixf(m); return bb_ret_empty(); }

/* GLGetMatrix GL_MODELVIEW_MATRIX, m(): the 16 numbers into a Single or Double array */
static bb_value f_getmatrix(int argc, bb_value *argv)
{
    GLfloat m[16];
    bb_array *a;
    int32_t i;
    (void)argc;
    a = arr_of(&argv[1], "GLGetMatrix: expected a Single or Double array");
    if (a->etype != BB_SINGLE && a->etype != BB_DOUBLE) bb_raise(13, "GLGetMatrix: expected a Single or Double array");
    if (a->count < 16) bb_raise(9, "GLGetMatrix: the array needs 16 elements");
    glGetFloatv((GLenum)bb_arg_long(argv, 0), m);
    for (i = 0; i < 16; i++) {
        if (a->etype == BB_SINGLE) ((bb_single *)a->data)[i] = m[i];
        else ((bb_double *)a->data)[i] = m[i];
    }
    return bb_ret_empty();
}

/* glGetInteger / glGetFloat (opengl_gen.h) */
static long bbgl_get_integer(GLenum pname) { GLint v[16]; v[0] = 0; glGetIntegerv(pname, v); return v[0]; }
static double bbgl_get_float(GLenum pname, int index)
{
    GLfloat v[16];
    memset(v, 0, sizeof v);
    if (index < 0 || index > 15) bb_raise(9, "glGetFloat: index 0..15");
    glGetFloatv(pname, v);
    return v[index];
}

/* vertex arrays: GL keeps a pointer to the data, so each array is copied into a float buffer
   that stays until the next call of the same function */
static GLfloat *vbuf, *cbuf, *nbuf, *tbuf;
static int32_t vcap, ccap, ncap, tcap, vcount;
static GLuint *ibuf;
static int32_t icap;

static bb_value f_vertexpointer(int argc, bb_value *argv)
{
    long size = bb_arg_long(argv, 0);
    (void)argc;
    if (size < 2 || size > 4) bb_raise(5, "glVertexPointer: size 2, 3 or 4");
    vcount = to_floats(&argv[1], &vbuf, &vcap, "glVertexPointer: expected an array of numbers") / (int32_t)size;
    glVertexPointer((GLint)size, GL_FLOAT, 0, vbuf);
    return bb_ret_empty();
}

static bb_value f_colorpointer(int argc, bb_value *argv)
{
    long size = bb_arg_long(argv, 0);
    (void)argc;
    if (size < 3 || size > 4) bb_raise(5, "glColorPointer: size 3 or 4");
    to_floats(&argv[1], &cbuf, &ccap, "glColorPointer: expected an array of numbers");
    glColorPointer((GLint)size, GL_FLOAT, 0, cbuf);
    return bb_ret_empty();
}

static bb_value f_normalpointer(int argc, bb_value *argv)
{
    (void)argc;
    to_floats(&argv[0], &nbuf, &ncap, "glNormalPointer: expected an array of numbers");
    glNormalPointer(GL_FLOAT, 0, nbuf);
    return bb_ret_empty();
}

static bb_value f_texcoordpointer(int argc, bb_value *argv)
{
    long size = bb_arg_long(argv, 0);
    (void)argc;
    if (size < 1 || size > 4) bb_raise(5, "glTexCoordPointer: size 1 to 4");
    to_floats(&argv[1], &tbuf, &tcap, "glTexCoordPointer: expected an array of numbers");
    glTexCoordPointer((GLint)size, GL_FLOAT, 0, tbuf);
    return bb_ret_empty();
}

static void check_range(long last, const char *fn)
{
    GLboolean on = glIsEnabled(GL_VERTEX_ARRAY);
    if (on && (last >= vcount || !vbuf)) bb_raise(9, fn);
}

static void bbgl_draw_arrays(GLenum mode, GLint first, GLsizei count)
{
    if (first < 0 || count < 0) bb_raise(5, "glDrawArrays: negative first or count");
    if (count) check_range((long)first + count - 1, "glDrawArrays: past the end of the vertex array");
    glDrawArrays(mode, first, count);
}

static bb_value f_drawelements(int argc, bb_value *argv)
{
    long count = bb_arg_long(argv, 1);
    bb_array *a = num_array(&argv[2], "glDrawElements: expected an array of indices");
    int32_t i;
    long hi = -1;
    (void)argc;
    if (count < 0 || count > a->count) bb_raise(9, "glDrawElements: count is more than the indices");
    if (count > icap) {
        GLuint *nb = (GLuint *)realloc(ibuf, sizeof(GLuint) * (size_t)count);
        if (!nb) bb_raise(7, "glDrawElements");
        ibuf = nb;
        icap = (int32_t)count;
    }
    for (i = 0; i < count; i++) {
        long k = (long)num_at(a, i);
        if (k < 0) bb_raise(9, "glDrawElements: a negative index");
        if (k > hi) hi = k;
        ibuf[i] = (GLuint)k;
    }
    if (count) check_range(hi, "glDrawElements: an index past the end of the vertex array");
    glDrawElements((GLenum)bb_arg_long(argv, 0), (GLsizei)count, GL_UNSIGNED_INT, ibuf);
    return bb_ret_empty();
}

/* ---- textures ---- */

static bb_value f_gentexture(int argc, bb_value *argv) { GLuint t = 0; (void)argc; (void)argv; glGenTextures(1, &t); return bb_ret_long((bb_long)t); }
static bb_value f_deletetexture(int argc, bb_value *argv) { GLuint t = (GLuint)bb_arg_long(argv, 0); (void)argc; glDeleteTextures(1, &t); return bb_ret_empty(); }

/* 0xAARRGGBB words -> R G B A bytes for glTexImage2D */
static void tex_upload(const uint32_t *px, const bb_array *a, int32_t w, int32_t h)
{
    unsigned char *rgba = (unsigned char *)malloc((size_t)w * (size_t)h * 4);
    int32_t i, n = w * h;
    if (!rgba) bb_raise(7, "OpenGL texture");
    for (i = 0; i < n; i++) {
        uint32_t c = px ? px[i] : (uint32_t)(int64_t)num_at(a, i);
        rgba[i * 4] = (unsigned char)(c >> 16);
        rgba[i * 4 + 1] = (unsigned char)(c >> 8);
        rgba[i * 4 + 2] = (unsigned char)c;
        rgba[i * 4 + 3] = (unsigned char)(c >> 24);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    free(rgba);
}

/* GLTexImage w, h, pixels(): the bound GL_TEXTURE_2D from w*h colours &HAARRGGBB (row by row,
   top row first; a 2-D array pixels(x, y) works too, it is stored x fastest) */
static bb_value f_teximage(int argc, bb_value *argv)
{
    long w = bb_arg_long(argv, 0), h = bb_arg_long(argv, 1);
    bb_array *a = num_array(&argv[2], "GLTexImage: expected an array of colours");
    (void)argc;
    if (w <= 0 || h <= 0 || w > 1024 || h > 1024) bb_raise(5, "GLTexImage: size 1..1024");
    if (a->count < w * h) bb_raise(9, "GLTexImage: the array has fewer than width * height colours");
    tex_upload(a->etype == BB_LONG ? (const uint32_t *)a->data : NULL, a, (int32_t)w, (int32_t)h);
    return bb_ret_empty();
}

/* GLTexImageCanvas cv, id: the bound texture from a canvas image (0 = its back buffer) */
static bb_value f_teximage_canvas(int argc, bb_value *argv)
{
    bb_obj *o = bb_arg_obj(argv, 0);
    int32_t w = 0, h = 0;
    uint32_t *px;
    (void)argc;
    if (!o || !bb_is_canvas(o)) bb_raise(13, "GLTexImageCanvas: expected a Canvas");
    px = bb_canvas_image_pixels(o, (int32_t)bb_arg_long(argv, 1), &w, &h);
    if (!px) bb_raise(5, "GLTexImageCanvas: no such image");
    if (w > 1024 || h > 1024) bb_raise(5, "GLTexImageCanvas: the image is bigger than 1024 x 1024");
    tex_upload(px, NULL, w, h);
    return bb_ret_empty();
}

/* ---- GLU ---- */

static bb_value f_perspective(int argc, bb_value *argv)
{
    double fovy = bb_arg_double(argv, 0), aspect = bb_arg_double(argv, 1);
    double zn = bb_arg_double(argv, 2), zf = bb_arg_double(argv, 3);
    double ymax = zn * tan(fovy * M_PI / 360.0), xmax = ymax * aspect;
    (void)argc;
    glFrustum(-xmax, xmax, -ymax, ymax, zn, zf);
    return bb_ret_empty();
}

static void normalize(double v[3])
{
    double l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l > 0) { v[0] /= l; v[1] /= l; v[2] /= l; }
}

static void cross(const double a[3], const double b[3], double r[3])
{
    r[0] = a[1] * b[2] - a[2] * b[1];
    r[1] = a[2] * b[0] - a[0] * b[2];
    r[2] = a[0] * b[1] - a[1] * b[0];
}

static bb_value f_lookat(int argc, bb_value *argv)
{
    double e[3], f[3], up[3], s[3], u[3];
    GLfloat m[16];
    int i;
    (void)argc;
    for (i = 0; i < 3; i++) {
        e[i] = bb_arg_double(argv, i);
        f[i] = bb_arg_double(argv, 3 + i) - e[i];
        up[i] = bb_arg_double(argv, 6 + i);
    }
    normalize(f);
    cross(f, up, s);
    normalize(s);
    cross(s, f, u);
    memset(m, 0, sizeof m);
    m[0] = (GLfloat)s[0]; m[4] = (GLfloat)s[1]; m[8] = (GLfloat)s[2];
    m[1] = (GLfloat)u[0]; m[5] = (GLfloat)u[1]; m[9] = (GLfloat)u[2];
    m[2] = (GLfloat)-f[0]; m[6] = (GLfloat)-f[1]; m[10] = (GLfloat)-f[2];
    m[15] = 1;
    glMultMatrixf(m);
    glTranslated(-e[0], -e[1], -e[2]);
    return bb_ret_empty();
}

static bb_value f_ortho2d(int argc, bb_value *argv)
{
    (void)argc;
    glOrtho(bb_arg_double(argv, 0), bb_arg_double(argv, 1), bb_arg_double(argv, 2), bb_arg_double(argv, 3), -1, 1);
    return bb_ret_empty();
}

/* GLProject(x, y, z, r()): where the point lands on the canvas: r(0) = x, r(1) = y (pixels from
   the top left), r(2) = depth 0..1. False if it is behind the camera. r is a Single, Double or
   Long array of 3 or more elements. */
static bb_value f_project(int argc, bb_value *argv)
{
    GLfloat mv[16], pr[16];
    GLint vp[4];
    double in[4], t[4], c[4], out[3];
    bb_array *a;
    int i;
    (void)argc;
    a = arr_of(&argv[3], "GLProject: expected a Single, Double or Long array");
    if (a->etype != BB_SINGLE && a->etype != BB_DOUBLE && a->etype != BB_LONG)
        bb_raise(13, "GLProject: expected a Single, Double or Long array");
    if (a->count < 3) bb_raise(9, "GLProject: the array needs 3 elements");
    in[0] = bb_arg_double(argv, 0); in[1] = bb_arg_double(argv, 1); in[2] = bb_arg_double(argv, 2); in[3] = 1;
    glGetFloatv(GL_MODELVIEW_MATRIX, mv);
    glGetFloatv(GL_PROJECTION_MATRIX, pr);
    glGetIntegerv(GL_VIEWPORT, vp);
    for (i = 0; i < 4; i++) t[i] = mv[i] * in[0] + mv[4 + i] * in[1] + mv[8 + i] * in[2] + mv[12 + i] * in[3];
    for (i = 0; i < 4; i++) c[i] = pr[i] * t[0] + pr[4 + i] * t[1] + pr[8 + i] * t[2] + pr[12 + i] * t[3];
    if (c[3] <= 0) return bb_ret_bool(0);
    out[0] = vp[0] + (c[0] / c[3] + 1) * vp[2] / 2;
    out[1] = bound_h - (vp[1] + (c[1] / c[3] + 1) * vp[3] / 2);
    out[2] = (c[2] / c[3] + 1) / 2;
    for (i = 0; i < 3; i++) {
        if (a->etype == BB_SINGLE) ((bb_single *)a->data)[i] = (bb_single)out[i];
        else if (a->etype == BB_DOUBLE) ((bb_double *)a->data)[i] = out[i];
        else ((bb_long *)a->data)[i] = (bb_long)floor(out[i] + 0.5);
    }
    return bb_ret_bool(1);
}

/* ---- GLUT's shapes (normals for lighting, texture coordinates on the sphere and cube) ---- */

static void cube(double size, GLenum mode)
{
    static const GLfloat n[6][3] = {{-1, 0, 0}, {0, 1, 0}, {1, 0, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
    static const int f[6][4] = {{0, 1, 2, 3}, {3, 2, 6, 7}, {7, 6, 5, 4}, {4, 5, 1, 0}, {5, 6, 2, 1}, {7, 4, 0, 3}};
    static const GLfloat tc[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
    GLfloat v[8][3], s = (GLfloat)(size / 2);
    int i, j;
    v[0][0] = v[1][0] = v[2][0] = v[3][0] = -s;
    v[4][0] = v[5][0] = v[6][0] = v[7][0] = s;
    v[0][1] = v[1][1] = v[4][1] = v[5][1] = -s;
    v[2][1] = v[3][1] = v[6][1] = v[7][1] = s;
    v[0][2] = v[3][2] = v[4][2] = v[7][2] = -s;
    v[1][2] = v[2][2] = v[5][2] = v[6][2] = s;
    for (i = 5; i >= 0; i--) {
        glBegin(mode);
        glNormal3fv(n[i]);
        for (j = 0; j < 4; j++) {
            if (mode == GL_QUADS) glTexCoord2fv(tc[j]);
            glVertex3fv(v[f[i][j]]);
        }
        glEnd();
    }
}

static bb_value f_solidcube(int argc, bb_value *argv) { (void)argc; cube(bb_arg_double(argv, 0), GL_QUADS); return bb_ret_empty(); }
static bb_value f_wirecube(int argc, bb_value *argv) { (void)argc; cube(bb_arg_double(argv, 0), GL_LINE_LOOP); return bb_ret_empty(); }

/* a sphere of quads strips, slices around z... GLUT's orientation: the poles on the z axis.
   check != 0: alternate colours c1, c2 in a checkerboard (the Boing ball) */
static void sphere(double r, int slices, int stacks, int wire, int check, bb_long c1, bb_long c2)
{
    int i, j;
    if (slices < 3) slices = 3;
    if (stacks < 2) stacks = 2;
    if (slices > 256) slices = 256;
    if (stacks > 256) stacks = 256;
    for (i = 0; i < stacks; i++) {
        double a0 = M_PI * i / stacks, a1 = M_PI * (i + 1) / stacks;
        double z0 = cos(a0), r0 = sin(a0), z1 = cos(a1), r1 = sin(a1);
        if (wire) {
            glBegin(GL_LINE_LOOP);
            for (j = 0; j < slices; j++) {
                double b = 2 * M_PI * j / slices;
                glNormal3d(r0 * cos(b), r0 * sin(b), z0);
                glVertex3d(r * r0 * cos(b), r * r0 * sin(b), r * z0);
            }
            glEnd();
            continue;
        }
        if (check) {
            glBegin(GL_QUADS);
            for (j = 0; j < slices; j++) {
                double b0 = 2 * M_PI * j / slices, b1 = 2 * M_PI * (j + 1) / slices;
                bb_long c = ((i + j) & 1) ? c2 : c1;
                glColor3ub((GLubyte)(c & 255), (GLubyte)((c >> 8) & 255), (GLubyte)((c >> 16) & 255));
                glNormal3d(r0 * cos(b0), r0 * sin(b0), z0); glVertex3d(r * r0 * cos(b0), r * r0 * sin(b0), r * z0);
                glNormal3d(r1 * cos(b0), r1 * sin(b0), z1); glVertex3d(r * r1 * cos(b0), r * r1 * sin(b0), r * z1);
                glNormal3d(r1 * cos(b1), r1 * sin(b1), z1); glVertex3d(r * r1 * cos(b1), r * r1 * sin(b1), r * z1);
                glNormal3d(r0 * cos(b1), r0 * sin(b1), z0); glVertex3d(r * r0 * cos(b1), r * r0 * sin(b1), r * z0);
            }
            glEnd();
            continue;
        }
        glBegin(GL_QUAD_STRIP);
        for (j = 0; j <= slices; j++) {
            double b = 2 * M_PI * j / slices, cb = cos(b), sb = sin(b);
            glNormal3d(r0 * cb, r0 * sb, z0);
            glTexCoord2d((double)j / slices, 1.0 - (double)i / stacks);
            glVertex3d(r * r0 * cb, r * r0 * sb, r * z0);
            glNormal3d(r1 * cb, r1 * sb, z1);
            glTexCoord2d((double)j / slices, 1.0 - (double)(i + 1) / stacks);
            glVertex3d(r * r1 * cb, r * r1 * sb, r * z1);
        }
        glEnd();
    }
}

static int clampi(long v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : (int)v; }

static bb_value f_solidsphere(int argc, bb_value *argv) { (void)argc; sphere(bb_arg_double(argv, 0), clampi(bb_arg_long(argv, 1), 3, 256), clampi(bb_arg_long(argv, 2), 2, 256), 0, 0, 0, 0); return bb_ret_empty(); }
static bb_value f_wiresphere(int argc, bb_value *argv) { (void)argc; sphere(bb_arg_double(argv, 0), clampi(bb_arg_long(argv, 1), 3, 256), clampi(bb_arg_long(argv, 2), 2, 256), 1, 0, 0, 0); return bb_ret_empty(); }
static bb_value f_checkersphere(int argc, bb_value *argv)
{
    (void)argc;
    sphere(bb_arg_double(argv, 0), clampi(bb_arg_long(argv, 1), 3, 256), clampi(bb_arg_long(argv, 2), 2, 256), 0, 1,
           bb_arg_long(argv, 3), bb_arg_long(argv, 4));
    return bb_ret_empty();
}

static void torus(double ri, double ro, int sides, int rings, int wire)
{
    int i, j;
    for (i = 0; i < rings; i++) {
        double t0 = 2 * M_PI * i / rings, t1 = 2 * M_PI * (i + 1) / rings;
        glBegin(wire ? GL_LINE_STRIP : GL_QUAD_STRIP);
        for (j = 0; j <= sides; j++) {
            double p = 2 * M_PI * j / sides, cp = cos(p), sp = sin(p);
            double rr = ro + ri * cp;
            glNormal3d(cos(t1) * cp, sin(t1) * cp, sp);
            glVertex3d(cos(t1) * rr, sin(t1) * rr, ri * sp);
            glNormal3d(cos(t0) * cp, sin(t0) * cp, sp);
            glVertex3d(cos(t0) * rr, sin(t0) * rr, ri * sp);
        }
        glEnd();
    }
}

static bb_value f_solidtorus(int argc, bb_value *argv) { (void)argc; torus(bb_arg_double(argv, 0), bb_arg_double(argv, 1), clampi(bb_arg_long(argv, 2), 3, 256), clampi(bb_arg_long(argv, 3), 3, 256), 0); return bb_ret_empty(); }
static bb_value f_wiretorus(int argc, bb_value *argv) { (void)argc; torus(bb_arg_double(argv, 0), bb_arg_double(argv, 1), clampi(bb_arg_long(argv, 2), 3, 256), clampi(bb_arg_long(argv, 3), 3, 256), 1); return bb_ret_empty(); }

/* a cone (top = 0) or cylinder (top = base) along +z from z = 0 to height, with caps */
static void cone(double base, double top, double height, int slices, int stacks, int wire)
{
    int i, j;
    double sl = sqrt((base - top) * (base - top) + height * height), nz = (base - top) / sl, nr = height / sl;
    for (i = 0; i < stacks; i++) {
        double z0 = height * i / stacks, z1 = height * (i + 1) / stacks;
        double r0 = base + (top - base) * i / stacks, r1 = base + (top - base) * (i + 1) / stacks;
        glBegin(wire ? GL_LINE_STRIP : GL_QUAD_STRIP);
        for (j = 0; j <= slices; j++) {
            double b = 2 * M_PI * j / slices, cb = cos(b), sb = sin(b);
            glNormal3d(cb * nr, sb * nr, nz);
            glVertex3d(r0 * cb, r0 * sb, z0);
            glVertex3d(r1 * cb, r1 * sb, z1);
        }
        glEnd();
    }
    if (wire) return;
    glBegin(GL_TRIANGLE_FAN);                 /* the base */
    glNormal3d(0, 0, -1);
    glVertex3d(0, 0, 0);
    for (j = slices; j >= 0; j--) { double b = 2 * M_PI * j / slices; glVertex3d(base * cos(b), base * sin(b), 0); }
    glEnd();
    if (top > 0) {
        glBegin(GL_TRIANGLE_FAN);
        glNormal3d(0, 0, 1);
        glVertex3d(0, 0, height);
        for (j = 0; j <= slices; j++) { double b = 2 * M_PI * j / slices; glVertex3d(top * cos(b), top * sin(b), height); }
        glEnd();
    }
}

static bb_value f_solidcone(int argc, bb_value *argv) { (void)argc; cone(bb_arg_double(argv, 0), 0, bb_arg_double(argv, 1), clampi(bb_arg_long(argv, 2), 3, 256), clampi(bb_arg_long(argv, 3), 1, 256), 0); return bb_ret_empty(); }
static bb_value f_wirecone(int argc, bb_value *argv) { (void)argc; cone(bb_arg_double(argv, 0), 0, bb_arg_double(argv, 1), clampi(bb_arg_long(argv, 2), 3, 256), clampi(bb_arg_long(argv, 3), 1, 256), 1); return bb_ret_empty(); }
static bb_value f_solidcylinder(int argc, bb_value *argv) { (void)argc; cone(bb_arg_double(argv, 0), bb_arg_double(argv, 0), bb_arg_double(argv, 1), clampi(bb_arg_long(argv, 2), 3, 256), clampi(bb_arg_long(argv, 3), 1, 256), 0); return bb_ret_empty(); }

#include "opengl_gen.h"

BB_EXTENSION(opengl)
{
    bbgl_register_generated();
    bb_register_function("GLAttach", f_attach);
    bb_register_function("GLDetach", f_detach);
    bb_register_function("GLPresent", f_present);
    bb_register_function("GLWidth", f_width);
    bb_register_function("GLHeight", f_height);
    bb_register_function("GLVersion", f_version);
    bb_register_function("glClear", f_clear);
    bb_register_function("glFinish", f_finish);
    bb_register_function("glGetString", f_getstring);
    bb_register_function("glColorRGB", f_color_rgb);
    bb_register_function("glLight4f", f_light4f);
    bb_register_function("glLightfv", f_lightfv);
    bb_register_function("glMaterial4f", f_material4f);
    bb_register_function("glMaterialfv", f_materialfv);
    bb_register_function("glLightModel4f", f_lightmodel4f);
    bb_register_function("glFog4f", f_fog4f);
    bb_register_function("glTexEnv4f", f_texenv4f);
    bb_register_function("glTexGen4f", f_texgen4f);
    bb_register_function("glLoadMatrixf", f_loadmatrix);
    bb_register_function("glMultMatrixf", f_multmatrix);
    bb_register_function("GLGetMatrix", f_getmatrix);
    bb_register_function("glGenTexture", f_gentexture);
    bb_register_function("glDeleteTexture", f_deletetexture);
    bb_register_function("GLTexImage", f_teximage);
    bb_register_function("GLTexImageCanvas", f_teximage_canvas);
    bb_register_function("glVertexPointer", f_vertexpointer);
    bb_register_function("glColorPointer", f_colorpointer);
    bb_register_function("glNormalPointer", f_normalpointer);
    bb_register_function("glTexCoordPointer", f_texcoordpointer);
    bb_register_function("glDrawElements", f_drawelements);
    bb_register_function("gluPerspective", f_perspective);
    bb_register_function("gluLookAt", f_lookat);
    bb_register_function("gluOrtho2D", f_ortho2d);
    bb_register_function("GLProject", f_project);
    bb_register_function("glutSolidCube", f_solidcube);
    bb_register_function("glutWireCube", f_wirecube);
    bb_register_function("glutSolidSphere", f_solidsphere);
    bb_register_function("glutWireSphere", f_wiresphere);
    bb_register_function("glutSolidTorus", f_solidtorus);
    bb_register_function("glutWireTorus", f_wiretorus);
    bb_register_function("glutSolidCone", f_solidcone);
    bb_register_function("glutWireCone", f_wirecone);
    bb_register_function("glutSolidCylinder", f_solidcylinder);
    bb_register_function("glutSolidCheckerSphere", f_checkersphere);
}
