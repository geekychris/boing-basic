/* process.c - Boing.Process: run a command and capture its output and exit code, and the
 * environment (docs/process.md):
 *
 *     Dim p As Process
 *     Set p = CreateObject("Process")
 *     If p.Run("list RAM: LFORMAT %N") = 0 Then Print p.Output
 *     For Each v In p.Environment: Print v: Next
 *
 * The platform part is bb_sys_run / bb_sys_setenv (os4/sys.c: SystemTags with T: files;
 * posix/sys.c: /bin/sh -c with pipes) and bb_plat_env_at. */
#include "boing.h"
#include "bb_sys.h"
#include "platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define E_PROC_START 31201

enum { M_RUN = 1, M_GETENV, M_SETENV, M_ENVIRONMENT, M_OUTPUTLINES,
       P_OUTPUT, P_ERROROUTPUT, P_EXITCODE, P_COMMANDLINE };
static const struct { const char *name; int id; } members[] = {
    {"Run", M_RUN}, {"GetEnv", M_GETENV}, {"SetEnv", M_SETENV}, {"Environment", M_ENVIRONMENT},
    {"OutputLines", M_OUTPUTLINES},
    {"Output", P_OUTPUT}, {"ErrorOutput", P_ERROROUTPUT}, {"ExitCode", P_EXITCODE}, {"CommandLine", P_COMMANDLINE},
};

typedef struct {
    bb_obj hdr;
    bb_str *out, *eout, *cmd;
    int32_t exitcode;
} proc_obj;

static const bb_class process_class;

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static char *cstr(const bb_str *s)
{
    long n = bb_str_len(s);
    char *o = malloc((size_t)n + 1);
    memcpy(o, bb_str_ptr(s), (size_t)n);
    o[n] = 0;
    return o;
}

static bb_array *str_array(char **items, int n)
{
    bb_array *a = bb_arr_new1(BB_STRING, 0, n - 1);
    int i;
    for (i = 0; i < n; i++) *(bb_str **)bb_arr_elem1(a, i) = bb_str_from_c(items[i]);
    return a;
}

/* the environment as "NAME=value" strings */
static bb_array *environment(void)
{
    char **items = NULL;
    int n = 0, i;
    const char *e;
    bb_array *a;
    for (i = 1; (e = bb_plat_env_at(i)); i++) {
        items = realloc(items, sizeof(char *) * (size_t)(n + 1));
        items[n++] = (char *)e;
    }
    a = str_array(items, n);
    free(items);
    return a;
}

/* the output split into lines (LF or CRLF; no empty last line) */
static bb_array *lines_of(const bb_str *s)
{
    const char *p = bb_str_ptr(s), *end = p + bb_str_len(s);
    int n = 0, i = 0;
    const char *q;
    bb_array *a;
    for (q = p; q < end; q++) if (*q == '\n') n++;
    if (end > p && end[-1] != '\n') n++;
    a = bb_arr_new1(BB_STRING, 0, n - 1);
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *e = nl ? nl : end;
        long len = e - p;
        if (len > 0 && p[len - 1] == '\r') len--;
        *(bb_str **)bb_arr_elem1(a, i++) = bb_str_new(p, (int32_t)len);
        p = nl ? nl + 1 : end;
    }
    return a;
}

static void p_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    proc_obj *p = (proc_obj *)self;
    if ((kind & (BB_INV_LET | BB_INV_SET)) && id != P_COMMANDLINE) bb_raise(383, NULL);
    switch (id) {
    case M_RUN: {
        bb_str *cmd = arg_str(argc, argv, 0), *in = present(argc, argv, 1) ? arg_str(argc, argv, 1) : NULL;
        char *c = cstr(cmd), *out = NULL, *eout = NULL, err[300] = "";
        long outlen = 0, eoutlen = 0;
        int rc;
        bb_console_flush();
        rc = bb_sys_run(c, in ? bb_str_ptr(in) : NULL, in ? bb_str_len(in) : 0, &out, &outlen, &eout, &eoutlen, err,
                        sizeof err);
        free(c);
        bb_str_release(in);
        bb_str_set(&p->cmd, cmd);
        bb_str_set(&p->out, bb_str_new(out ? out : "", (int32_t)outlen));
        bb_str_set(&p->eout, bb_str_new(eout ? eout : "", (int32_t)eoutlen));
        free(out);
        free(eout);
        p->exitcode = rc;
        if (rc < 0 && *err) {
            char msg[400];
            snprintf(msg, sizeof msg, "%s: %s", bb_str_ptr(p->cmd), err);
            bb_raise(E_PROC_START, msg);
        }
        *ret = bb_v_long(rc);
        return;
    }
    case M_GETENV: {
        bb_str *n = arg_str(argc, argv, 0);
        char *c = cstr(n), *v = bb_sys_environ(c);
        free(c);
        bb_str_release(n);
        *ret = bb_v_str(bb_str_from_c(v ? v : ""));
        free(v);
        return;
    }
    case M_SETENV: {
        bb_str *n = arg_str(argc, argv, 0), *v = present(argc, argv, 1) ? arg_str(argc, argv, 1) : NULL;
        char *cn = cstr(n), *cv = v ? cstr(v) : NULL;
        int rc = bb_sys_setenv(cn, cv);       /* no value or "": remove it */
        int remove = !v || !bb_str_len(v);
        if (remove && cv) {
            free(cv);
            cv = NULL;
            rc = bb_sys_setenv(cn, NULL);
        }
        free(cn);
        free(cv);
        bb_str_release(n);
        bb_str_release(v);
        if (rc) bb_raise(5, "bad environment variable name");
        return;
    }
    case M_ENVIRONMENT:
        *ret = bb_v_arr(environment());
        return;
    case M_OUTPUTLINES:
        *ret = bb_v_arr(lines_of(p->out));
        return;
    case P_OUTPUT:
        *ret = bb_v_str(bb_str_retain(p->out));
        return;
    case P_ERROROUTPUT:
        *ret = bb_v_str(bb_str_retain(p->eout));
        return;
    case P_EXITCODE:
        *ret = bb_v_long(p->exitcode);
        return;
    case P_COMMANDLINE:
        if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);
        *ret = bb_v_str(bb_str_retain(p->cmd));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t p_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return P_OUTPUT;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void p_terminate(bb_obj *self)
{
    proc_obj *p = (proc_obj *)self;
    bb_str_release(p->out);
    bb_str_release(p->eout);
    bb_str_release(p->cmd);
}

static const bb_class process_class = {
    "Process", sizeof(proc_obj), p_find, p_invoke, p_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_process_class(void) { return &process_class; }
bb_obj *bb_process_new(void) { return bb_obj_new(&process_class); }
