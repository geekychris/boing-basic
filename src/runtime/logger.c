/* logger.c - Boing.Logger, logging to a file and/or the console (docs/logging.md):
 *
 *     Dim lg As Logger
 *     Set lg = CreateObject("Logger")
 *     lg.FileName = "PROGDIR:app.log"
 *     lg.Level = logDebug
 *     lg.Info "started, version " & App.Major
 *     lg.Error "can't open " & f
 *
 * Each message is one line, laid out by Pattern ({date} {time} {level} {source} {message}).
 * The file is opened for appending at the first message and flushed after every line (so a
 * crash keeps the log); with MaxSize it is renamed to <name>.old when it grows past that. */
#include "boing.h"
#include "platform.h"
#include "bb_sys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum { LV_DEBUG = 10, LV_INFO = 20, LV_WARNING = 30, LV_ERROR = 40, LV_FATAL = 50, LV_OFF = 100 };

enum {
    M_DEBUG = 1, M_INFO, M_WARNING, M_ERROR, M_FATAL, M_LOG, M_FLUSH, M_CLOSE,
    P_FILENAME, P_LEVEL, P_CONSOLE, P_PATTERN, P_SOURCE, P_MAXSIZE, P_COUNT, P_LASTMESSAGE, P_AUTOFLUSH,
};
static const struct { const char *name; int id; } members[] = {
    {"Debug", M_DEBUG}, {"Info", M_INFO}, {"Warning", M_WARNING}, {"Error", M_ERROR}, {"Fatal", M_FATAL},
    {"Log", M_LOG}, {"Flush", M_FLUSH}, {"Close", M_CLOSE},
    {"FileName", P_FILENAME}, {"Level", P_LEVEL}, {"Console", P_CONSOLE}, {"Pattern", P_PATTERN},
    {"Source", P_SOURCE}, {"MaxSize", P_MAXSIZE}, {"Count", P_COUNT}, {"LastMessage", P_LASTMESSAGE},
    {"AutoFlush", P_AUTOFLUSH},
};

typedef struct {
    bb_obj hdr;
    char *file, *pattern, *source;
    int level, console, autoflush;
    long maxsize, count;
    FILE *f;
    bb_str *last;
} log_obj;

static const bb_class log_class;

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static char *arg_c(int argc, bb_value *argv, int i)
{
    bb_str *s = arg_str(argc, argv, i);
    char *c = malloc((size_t)bb_str_len(s) + 1);
    memcpy(c, bb_str_ptr(s), (size_t)bb_str_len(s));
    c[bb_str_len(s)] = 0;
    bb_str_release(s);
    return c;
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static const char *level_name(int lv)
{
    if (lv >= LV_FATAL) return "FATAL";
    if (lv >= LV_ERROR) return "ERROR";
    if (lv >= LV_WARNING) return "WARNING";
    if (lv >= LV_INFO) return "INFO";
    return "DEBUG";
}

static void close_file(log_obj *g)
{
    if (g->f) fclose(g->f);
    g->f = NULL;
}

typedef struct { char *p; size_t n, cap; } sbuf;
static void sb_add(sbuf *b, const char *p, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2 + 64;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, p, n);
    b->n += n;
    b->p[b->n] = 0;
}

static void write_line(log_obj *g, int lv, const char *msg, size_t msglen)
{
    sbuf b = {NULL, 0, 0};
    const char *p = g->pattern ? g->pattern : "{date} {time} {level} {message}";
    bb_tm tm;
    char tmp[64];
    bb_plat_localtime(&tm);
    while (*p) {
        const char *br = strchr(p, '{'), *end;
        if (!br) {
            sb_add(&b, p, strlen(p));
            break;
        }
        sb_add(&b, p, (size_t)(br - p));
        end = strchr(br, '}');
        if (!end) {
            sb_add(&b, br, strlen(br));
            break;
        }
#define TOKEN(t) ((size_t)(end - br - 1) == strlen(t) && !strncasecmp(br + 1, t, strlen(t)))
        if (TOKEN("date")) {
            snprintf(tmp, sizeof tmp, "%04d-%02d-%02d", tm.year, tm.month, tm.day);
            sb_add(&b, tmp, strlen(tmp));
        } else if (TOKEN("time")) {
            snprintf(tmp, sizeof tmp, "%02d:%02d:%02d", tm.hour, tm.minute, tm.second);
            sb_add(&b, tmp, strlen(tmp));
        } else if (TOKEN("ms")) {
            snprintf(tmp, sizeof tmp, "%03d", tm.msec);
            sb_add(&b, tmp, strlen(tmp));
        } else if (TOKEN("level")) {
            const char *n = level_name(lv);
            sb_add(&b, n, strlen(n));
        } else if (TOKEN("source")) {
            if (g->source) sb_add(&b, g->source, strlen(g->source));
        } else if (TOKEN("message")) {
            sb_add(&b, msg, msglen);
        } else if (TOKEN("line")) {
            snprintf(tmp, sizeof tmp, "%ld", (long)bb_line);
            sb_add(&b, tmp, strlen(tmp));
        } else
            sb_add(&b, br, (size_t)(end - br + 1));
#undef TOKEN
        p = end + 1;
    }
    bb_str_set(&g->last, bb_str_new(b.p ? b.p : "", (int32_t)b.n));
    sb_add(&b, "\n", 1);
    g->count++;
    if (g->console || !(g->file && *g->file)) {        /* no file: the console */
        bb_console_flush();
        bb_plat_write_err(b.p, b.n);
    }
    if (g->file && *g->file) {
        if (!g->f) {
            g->f = fopen(g->file, "ab");
            if (!g->f) {
                free(b.p);
                bb_raise(75, NULL);
            }
        }
        if (g->maxsize > 0 && ftell(g->f) + (long)b.n > g->maxsize && ftell(g->f) > 0) {
            /* rotate: the full log becomes <name>.old */
            char *old = malloc(strlen(g->file) + 5);
            sprintf(old, "%s.old", g->file);
            close_file(g);
            remove(old);
            rename(g->file, old);
            free(old);
            g->f = fopen(g->file, "ab");
            if (!g->f) {
                free(b.p);
                bb_raise(75, NULL);
            }
        }
        if (fwrite(b.p, 1, b.n, g->f) != b.n) {
            free(b.p);
            bb_raise(61, NULL);
        }
        if (g->autoflush) fflush(g->f);
    }
    free(b.p);
}

static void log_msg(log_obj *g, int lv, int argc, bb_value *argv, int first)
{
    bb_str *m;
    if (lv < g->level || g->level >= LV_OFF) return;
    m = arg_str(argc, argv, first);
    write_line(g, lv, bb_str_ptr(m), (size_t)bb_str_len(m));
    bb_str_release(m);
}

static void g_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    log_obj *g = (log_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    switch (id) {
    case M_DEBUG: log_msg(g, LV_DEBUG, argc, argv, 0); return;
    case M_INFO: log_msg(g, LV_INFO, argc, argv, 0); return;
    case M_WARNING: log_msg(g, LV_WARNING, argc, argv, 0); return;
    case M_ERROR: log_msg(g, LV_ERROR, argc, argv, 0); return;
    case M_FATAL: log_msg(g, LV_FATAL, argc, argv, 0); return;
    case M_LOG: {
        int32_t lv = arg_long(argc, argv, 0);
        if (lv < 0 || lv >= LV_OFF) bb_raise(380, NULL);
        log_msg(g, (int)lv, argc, argv, 1);
        return;
    }
    case M_FLUSH:
        if (g->f) fflush(g->f);
        return;
    case M_CLOSE:
        close_file(g);
        return;
    case P_FILENAME:
        if (set) {
            close_file(g);
            free(g->file);
            g->file = arg_c(argc, argv, argc - 1);
        } else
            *ret = bb_v_str(bb_str_from_c(g->file ? g->file : ""));
        return;
    case P_PATTERN:
    case P_SOURCE: {
        char **f = id == P_PATTERN ? &g->pattern : &g->source;
        if (set) {
            free(*f);
            *f = arg_c(argc, argv, argc - 1);
        } else
            *ret = bb_v_str(bb_str_from_c(*f ? *f : id == P_PATTERN ? "{date} {time} {level} {message}" : ""));
        return;
    }
    case P_LEVEL:
        if (set) {
            int32_t lv = arg_long(argc, argv, argc - 1);
            if (lv < 0) bb_raise(380, NULL);
            g->level = (int)lv;
        } else
            *ret = bb_v_long(g->level);
        return;
    case P_CONSOLE:
    case P_AUTOFLUSH: {
        int *f = id == P_CONSOLE ? &g->console : &g->autoflush;
        if (set) {
            bb_value t;
            *f = bb_v_to_bool(bb_v_deref(&argv[argc - 1], &t)) != 0;
        } else
            *ret = bb_v_bool(*f);
        return;
    }
    case P_MAXSIZE:
        if (set) {
            int32_t m = arg_long(argc, argv, argc - 1);
            if (m < 0) bb_raise(380, NULL);
            g->maxsize = m;
        } else
            *ret = bb_v_long((bb_long)g->maxsize);
        return;
    case P_COUNT:
        *ret = bb_v_long((bb_long)g->count);
        return;
    case P_LASTMESSAGE:
        *ret = bb_v_str(bb_str_retain(g->last));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t g_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void g_terminate(bb_obj *self)
{
    log_obj *g = (log_obj *)self;
    close_file(g);
    free(g->file);
    free(g->pattern);
    free(g->source);
    bb_str_release(g->last);
}

static const bb_class log_class = {
    "Logger", sizeof(log_obj), g_find, g_invoke, g_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_logger_class(void) { return &log_class; }
bb_obj *bb_logger_new(void)
{
    log_obj *g = (log_obj *)bb_obj_new(&log_class);
    g->level = LV_INFO;
    g->autoflush = 1;
    return &g->hdr;
}
