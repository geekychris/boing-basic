/* builtins.c - maths, inspection and misc built-ins */
#include "boing.h"
#include "platform.h"
#include "bb_sys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int missing(const bb_value *v) { return !v || (v->type == BB_ERROR && (v->flags & BB_VF_MISSING)); }

bb_value bb_abs(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    switch (v->type) {
    case BB_NULL: return bb_v_null();
    case BB_EMPTY: return bb_v_int(0);
    case BB_INTEGER: case BB_BOOLEAN: if (v->u.i == -32768) return bb_v_long(32768); return bb_v_int((bb_int)(v->u.i < 0 ? -v->u.i : v->u.i));
    case BB_LONG: if (v->u.l == INT32_MIN) return bb_v_double(2147483648.0); return bb_v_long(v->u.l < 0 ? -v->u.l : v->u.l);
    case BB_BYTE: return bb_v_byte(v->u.by);
    case BB_SINGLE: return bb_v_single(fabsf(v->u.f));
    case BB_CURRENCY: return bb_v_cur(v->u.c < 0 ? -v->u.c : v->u.c);
    case BB_DECIMAL: return bb_dec_abs(v);
    case BB_DATE: return bb_v_date(fabs(v->u.dt));
    default: return bb_v_double(fabs(bb_v_to_double(v)));
    }
}

bb_value bb_sgn(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    double d;
    if (v->type == BB_NULL) return bb_v_null();
    if (v->type == BB_DECIMAL) { bb_value z = bb_v_int(0); return bb_v_int((bb_int)bb_dec_compare(v, &z)); }
    d = bb_v_to_double(v);
    return bb_v_int((bb_int)(d > 0 ? 1 : d < 0 ? -1 : 0));
}

static bb_value int_fix(const bb_value *v0, int fix)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    switch (v->type) {
    case BB_NULL: return bb_v_null();
    case BB_EMPTY: return bb_v_int(0);
    case BB_INTEGER: case BB_LONG: case BB_BYTE: return *v;
    case BB_BOOLEAN: return bb_v_int(v->u.b);
    case BB_SINGLE: return bb_v_single(fix ? truncf(v->u.f) : floorf(v->u.f));
    case BB_CURRENCY: {
        bb_cur c = v->u.c, q = c / 10000, r = c % 10000;
        if (!fix && r < 0) q--;
        return bb_v_cur(q * 10000);
    }
    case BB_DATE: return bb_v_date(fix ? trunc(v->u.dt) : floor(v->u.dt));
    case BB_DECIMAL: return bb_dec_trunc(v, !fix);
    default: { double d = bb_v_to_double(v); return bb_v_double(fix ? trunc(d) : floor(d)); }
    }
}

bb_value bb_int_fn(const bb_value *v) { return int_fix(v, 0); }
bb_value bb_fix(const bb_value *v) { return int_fix(v, 1); }

bb_double bb_sqr(bb_double d) { if (d < 0) bb_raise(5, NULL); return sqrt(d); }
bb_double bb_log(bb_double d) { if (d <= 0) bb_raise(5, NULL); return log(d); }
bb_double bb_exp(bb_double d) { return bb_chk_double(exp(d)); }

/* VB's generator, bit-exact */
static uint32_t rnd_seed = 0x50000;
static float rnd_last;

bb_single bb_rnd(const bb_value *v0)
{
    bb_value t;
    if (!missing(v0)) {
        float x = bb_v_to_single(bb_v_deref(v0, &t));
        if (x == 0) return rnd_last;
        if (x < 0) {
            union { float f; uint32_t u; } fu;
            fu.f = x;
            rnd_seed = (fu.u + (fu.u >> 24)) & 0xFFFFFF;
        }
    }
    rnd_seed = (rnd_seed * 0x43FD43FDu + 0xC39EC3u) & 0xFFFFFF;
    rnd_last = (float)rnd_seed / 16777216.0f;
    return rnd_last;
}

void bb_randomize(const bb_value *seed)
{
    double d;
    union { double d; uint64_t u; } du;
    uint32_t hi, lv;
    bb_value t;
    if (missing(seed)) d = bb_timer();
    else d = bb_v_to_double(bb_v_deref(seed, &t));
    du.d = d;
    hi = (uint32_t)(du.u >> 32);
    lv = ((hi & 0xFFFF) ^ (hi >> 16)) << 8;
    rnd_seed = (rnd_seed & 0xFF0000FFu) | (lv & 0x00FFFF00u);
}

bb_value bb_round(const bb_value *v0, bb_long digits)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    double d, p;
    if (digits < 0) bb_raise(5, NULL);
    switch (v->type) {
    case BB_NULL: return bb_v_null();
    case BB_INTEGER: case BB_LONG: case BB_BYTE: return *v;
    case BB_EMPTY: return bb_v_int(0);
    default: break;
    }
    d = bb_v_to_double(v);
    p = pow(10.0, (double)digits);
    {
        double x = d * p, r = bb_round_even(x);
        /* guard against representation noise like 2.675 * 100 = 267.49999 */
        if (fabs(x - r) != 0.5 && fabs(fabs(x - floor(x)) - 0.5) < 1e-9) r = bb_round_even(floor(x) + 0.5);
        d = r / p;
    }
    if (v->type == BB_SINGLE) return bb_v_single((float)d);
    if (v->type == BB_CURRENCY) return bb_v_cur(bb_ccur(d));
    return bb_v_double(d);
}

bb_str *bb_str_fn(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    bb_str *s, *r;
    if (v->type == BB_NULL) bb_raise(94, NULL);
    if (v->type == BB_STRING) {
        double d = bb_str_to_double(v->u.s);
        bb_value dv = bb_v_double(d);
        return bb_str_fn(&dv);
    }
    s = bb_v_to_str(v);
    if (v->type == BB_BOOLEAN || v->type == BB_DATE) return s;
    {
        /* no leading zero: Str(0.5) = " .5" */
        const char *p = bb_str_ptr(s);
        int32_t n = bb_str_len(s);
        if (n >= 2 && p[0] == '0' && p[1] == '.') { bb_str *t = bb_str_new(p + 1, n - 1); bb_str_release(s); s = t; }
        else if (n >= 3 && p[0] == '-' && p[1] == '0' && p[2] == '.') {
            bb_str *t = bb_str_alloc(n - 1);
            t->data[0] = '-';
            memcpy(t->data + 1, p + 2, (size_t)(n - 2));
            bb_str_release(s);
            s = t;
        }
    }
    if (bb_str_len(s) && s->data[0] == '-') return s;
    {
        bb_str *sp = bb_str_from_c(" ");
        r = bb_str_concat(sp, s);
        bb_str_release(sp);
    }
    bb_str_release(s);
    return r;
}

static bb_str *radix(const bb_value *v0, int hex)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    char b[40];
    uint32_t u;
    if (v->type == BB_NULL) bb_raise(94, NULL);
    if (v->type == BB_INTEGER || v->type == BB_BOOLEAN) u = (uint16_t)v->u.i;
    else if (v->type == BB_BYTE) u = v->u.by;
    else {
        bb_long l = bb_v_to_long(v);
        if (v->type != BB_LONG && l >= -32768 && l <= 32767 && v->type != BB_DOUBLE && v->type != BB_SINGLE &&
            v->type != BB_STRING && v->type != BB_CURRENCY) u = (uint16_t)l;
        else u = (uint32_t)l;
    }
    snprintf(b, sizeof b, hex ? "%lX" : "%lo", (unsigned long)u);
    return bb_str_from_c(b);
}

bb_str *bb_hex(const bb_value *v) { return radix(v, 1); }
bb_str *bb_oct(const bb_value *v) { return radix(v, 0); }

bb_bool bb_isnumeric(const bb_value *v) { return bb_v_is_numeric(v) ? BB_TRUE : BB_FALSE; }

static const char *type_name(int t)
{
    switch (t) {
    case BB_EMPTY: return "Empty";
    case BB_NULL: return "Null";
    case BB_INTEGER: return "Integer";
    case BB_LONG: return "Long";
    case BB_SINGLE: return "Single";
    case BB_DOUBLE: return "Double";
    case BB_CURRENCY: return "Currency";
    case BB_DECIMAL: return "Decimal";
    case BB_DATE: return "Date";
    case BB_STRING: return "String";
    case BB_OBJECT: return "Object";
    case BB_ERROR: return "Error";
    case BB_BOOLEAN: return "Boolean";
    case BB_VARIANT: return "Variant";
    case BB_BYTE: return "Byte";
    case BB_UDT: return "UserDefinedType";
    default: return "Unknown";
    }
}

bb_str *bb_typename(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    char b[64];
    if (v->type == BB_OBJECT) return bb_typename_obj(v->u.o);
    if (v->type & BB_ARRAY) {
        snprintf(b, sizeof b, "%s()", type_name(BB_BASETYPE(v->type)));
        return bb_str_from_c(b);
    }
    return bb_str_from_c(type_name(v->type));
}

bb_long bb_vartype(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    return v->type;
}

bb_value bb_array_fn(int argc, const bb_value *argv)
{
    int32_t lb = 0, ub = argc - 1, i;
    bb_array *a = bb_arr_new(BB_VARIANT, NULL, 1, &lb, &ub);
    for (i = 0; i < argc; i++) {
        bb_value t;
        bb_v_copy(&((bb_value *)a->data)[i], bb_v_deref(&argv[i], &t));
    }
    return bb_v_arr(a);
}

bb_value bb_iif(const bb_value *c, const bb_value *a, const bb_value *b)
{
    bb_value t;
    return bb_v_dup(bb_v_deref(bb_v_truth(c) ? a : b, &t));
}

/* Switch(expr1, value1, expr2, value2, ...): the value after the first True expression; Null
   if none (all arguments are evaluated, as in VB) */
bb_value bb_switch(int argc, const bb_value *argv)
{
    int i;
    bb_value t;
    if (argc < 2 || (argc & 1)) bb_raise(5, NULL);
    for (i = 0; i < argc; i += 2)
        if (bb_v_truth(&argv[i])) return bb_v_dup(bb_v_deref(&argv[i + 1], &t));
    return bb_v_null();
}

/* QBColor(0..15): the QuickBASIC palette as an RGB() value */
bb_long bb_qbcolor(bb_long n)
{
    static const int32_t pal[16] = {
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF };
    if (n < 0 || n > 15) bb_raise(5, NULL);
    return pal[n];
}

/* Date$ "mm-dd-yyyy", Time$ "hh:mm:ss" */
bb_str *bb_date_str(void)
{
    bb_tm t;
    char b[16];
    bb_plat_localtime(&t);
    snprintf(b, sizeof b, "%02d-%02d-%04d", (int)t.month, (int)t.day, (int)t.year);
    return bb_str_from_c(b);
}

bb_str *bb_time_str(void)
{
    bb_tm t;
    char b[16];
    bb_plat_localtime(&t);
    snprintf(b, sizeof b, "%02d:%02d:%02d", (int)t.hour, (int)t.minute, (int)t.second);
    return bb_str_from_c(b);
}

bb_value bb_choose(bb_long n, int argc, const bb_value *argv)
{
    bb_value t;
    if (n < 1 || n > argc) return bb_v_null();
    return bb_v_dup(bb_v_deref(&argv[n - 1], &t));
}

/* ---- environment ---- */

static int g_argc;
static char **g_argv;
void bb_set_args_(int argc, char **argv) { g_argc = argc; g_argv = argv; }

bb_str *bb_command(void)
{
    size_t total = 0, k = 0;
    int i;
    char *b;
    bb_str *s;
    for (i = 1; i < g_argc; i++) total += strlen(g_argv[i]) + 1;
    if (!total) return NULL;
    b = (char *)malloc(total);
    for (i = 1; i < g_argc; i++) {
        size_t l = strlen(g_argv[i]);
        if (k) b[k++] = ' ';
        memcpy(b + k, g_argv[i], l);
        k += l;
    }
    s = bb_str_new(b, (int32_t)k);
    free(b);
    return s;
}

bb_str *bb_environ(const bb_value *v0)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    if (v->type == BB_STRING) return bb_str_from_c(bb_plat_getenv(bb_str_ptr(v->u.s)));
    {
        bb_long n = bb_v_to_long(v);
        if (n < 1) bb_raise(5, NULL);
        return bb_str_from_c(bb_plat_env_at((int)n));
    }
}

bb_long bb_shell(bb_str *cmd)
{
    bb_console_flush();
    return bb_plat_system(bb_str_ptr(cmd));
}

void bb_beep(void) { bb_plat_beep(); }
/* Sleep / DoEvents look for Ctrl-C at once (a waiting loop polls rarely) */
void bb_sleep_ms(bb_long ms) { bb_console_flush(); bb_plat_sleep_ms(ms); bb_poll_slow(); }

static bb_int (*g_doevents)(void);
void bb_set_doevents(bb_int (*fn)(void)) { g_doevents = fn; }
bb_int bb_doevents(void) { bb_int r; bb_console_flush(); r = g_doevents ? g_doevents() : 0; bb_poll_slow(); return r; }
bb_long bb_rgb(bb_long r, bb_long g, bb_long b)
{
    return (bb_long)((r & 255) | ((g & 255) << 8) | ((b & 255) << 16));
}
bb_long bb_erl(void) { return bb_err.number ? bb_err.line : 0; }
bb_str *bb_error_fn(const bb_value *num)
{
    if (missing(num)) return bb_str_retain(bb_err.description);
    return bb_str_from_c(bb_error_message(bb_v_to_long(num)));
}
bb_date bb_timevalue_(bb_date d) { return d - floor(d); }

/* App and Clipboard objects (bb_sys.h) */
bb_str *bb_app_path(void) { return bb_str_from_c(bb_sys_app_path()); }
bb_str *bb_app_exename(void) { return bb_str_from_c(bb_sys_app_exename()); }
static bb_str *app_title;
void bb_set_app_title(const char *t) { bb_str_set(&app_title, bb_str_from_c(t)); }
bb_str *bb_app_title(void) { return app_title ? bb_str_retain(app_title) : bb_app_exename(); }
int bb_sys_clip_unit;

bb_str *bb_clipboard_get(void)
{
    char *t = bb_sys_clipboard_get();
    bb_str *s = bb_str_from_c(t);
    free(t);
    return s;
}
void bb_clipboard_set(bb_str *s) { bb_sys_clipboard_set(bb_str_ptr(s)); }
void bb_clipboard_clear(void) { bb_sys_clipboard_set(""); }
