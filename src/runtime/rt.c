/* rt.c - runtime start-up, memory, errors, program ops */
#include "boing.h"
#include "platform.h"
#include "bb_declare.h"
#include "bb_sys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bb_errstate bb_err;
bb_errframe *bb_errtop;
bb_cleanup *bb_cleanups;
int32_t bb_line;
const char *bb_file = "";

static const bb_program_ops *g_prog;

void *bb_alloc(size_t n)
{
    void *p = calloc(1, n ? n : 1);
    if (!p) bb_raise(7, NULL);
    return p;
}

void *bb_realloc(void *p, size_t n)
{
    void *q = realloc(p, n ? n : 1);
    if (!q) bb_raise(7, NULL);
    return q;
}

void bb_free(void *p) { free(p); }

void bb_set_args_(int argc, char **argv);

void bb_rt_init(int argc, char **argv)
{
    bb_set_args_(argc, argv);
    bb_plat_init(argc, argv);
    {
        char here;
        bb_stack_limit = bb_plat_stack_limit(&here);
    }
    bb_sys_init(argc, argv, NULL);
    if (getenv("BOING_ERROR_FILE")) bb_set_error_file(getenv("BOING_ERROR_FILE"));
}

void bb_rt_shutdown(void)
{
    bb_close_all();
    bb_console_flush();
    bb_forms_shutdown_();
    bb_decl_cleanup();
    bb_plat_shutdown();
}

void bb_exit(int code)
{
    bb_rt_shutdown();
    exit(code);
}

void bb_end(void) { bb_exit(0); }

static const struct { int32_t n; const char *msg; } errmsgs[] = {
    {3, "Return without GoSub"},
    {5, "Invalid procedure call or argument"},
    {6, "Overflow"},
    {7, "Out of memory"},
    {9, "Subscript out of range"},
    {10, "This array is fixed or temporarily locked"},
    {11, "Division by zero"},
    {13, "Type mismatch"},
    {14, "Out of string space"},
    {16, "Expression too complex"},
    {17, "Can't perform requested operation"},
    {18, "User interrupt occurred"},
    {20, "Resume without error"},
    {28, "Out of stack space"},
    {35, "Sub or Function not defined"},
    {47, "Too many DLL application clients"},
    {48, "Error in loading DLL"},
    {49, "Bad DLL calling convention"},
    {51, "Internal error"},
    {52, "Bad file name or number"},
    {53, "File not found"},
    {54, "Bad file mode"},
    {55, "File already open"},
    {57, "Device I/O error"},
    {58, "File already exists"},
    {59, "Bad record length"},
    {61, "Disk full"},
    {62, "Input past end of file"},
    {63, "Bad record number"},
    {67, "Too many files"},
    {68, "Device unavailable"},
    {70, "Permission denied"},
    {71, "Disk not ready"},
    {74, "Can't rename with different drive"},
    {75, "Path/File access error"},
    {76, "Path not found"},
    {91, "Object variable or With block variable not set"},
    {92, "For loop not initialized"},
    {93, "Invalid pattern string"},
    {94, "Invalid use of Null"},
    {380, "Invalid property value"},
    {381, "Invalid property array index"},
    {382, "Set not supported at runtime"},
    {383, "Set not supported (read-only property)"},
    {385, "Need property array index"},
    {387, "Set not permitted"},
    {393, "Get not supported at runtime"},
    {394, "Get not supported (write-only property)"},
    {422, "Property not found"},
    {423, "Property or method not found"},
    {424, "Object required"},
    {429, "ActiveX component can't create object"},
    {430, "Class does not support Automation or does not support expected interface"},
    {438, "Object doesn't support this property or method"},
    {440, "Automation error"},
    {445, "Object doesn't support this action"},
    {446, "Object doesn't support named arguments"},
    {448, "Named argument not found"},
    {449, "Argument not optional"},
    {450, "Wrong number of arguments or invalid property assignment"},
    {451, "Property let procedure not defined and property get procedure did not return an object"},
    {453, "Specified DLL function not found"},
    {455, "Code resource lock error"},
    {457, "This key is already associated with an element of this collection"},
    {458, "Variable uses an Automation type not supported in Visual Basic"},
    {459, "Object or class does not support the set of events"},
    {460, "Invalid clipboard format"},
    {735, "Can't save file to TEMP"},
    {744, "Search text not found"},
    {746, "Replacements too long"},
    {0, NULL}
};

const char *bb_error_message(int32_t num)
{
    int i;
    for (i = 0; errmsgs[i].msg; i++)
        if (errmsgs[i].n == num) return errmsgs[i].msg;
    return "Application-defined or object-defined error";
}

void bb_err_clear(void)
{
    bb_err.number = 0;
    bb_str_set(&bb_err.description, NULL);
    bb_str_set(&bb_err.source, NULL);
}

static char *g_error_file;
void bb_set_error_file(const char *path)
{
    free(g_error_file);
    g_error_file = path ? strdup(path) : NULL;
}

int32_t bb_poll_count = 4096;
char *bb_stack_limit;
void bb_stack_overflow(void) { bb_raise(28, NULL); }
void bb_poll_slow(void)
{
    bb_poll_count = 4096;
    if (bb_plat_break()) {
        char buf[512];
        bb_console_flush();
        snprintf(buf, sizeof buf, "%s:%ld: ***Break\n", bb_file ? bb_file : "?", (long)bb_line);
        bb_plat_write_err(buf, strlen(buf));
        bb_exit(20);
    }
}

void bb_fatal_error(void)
{
    char buf[1024];
    bb_console_flush();
    snprintf(buf, sizeof buf, "%s:%ld: runtime error %ld: %s\n",
             bb_err.file ? bb_err.file : "?", (long)bb_err.line, (long)bb_err.number,
             bb_str_len(bb_err.description) ? bb_str_ptr(bb_err.description)
                                            : bb_error_message(bb_err.number));
    bb_plat_write_err(buf, strlen(buf));
    if (g_error_file) {
        FILE *f = fopen(g_error_file, "w");
        if (f) { fputs(buf, f); fclose(f); }
    }
    bb_exit(20);
}

void bb_rethrow(void)
{
    if (!bb_errtop) bb_fatal_error();
    /* release the locals of the native procedures being unwound, while their stack
     * frames still exist (Class_Terminate may run) */
    while (bb_cleanups && bb_cleanups != bb_errtop->cmark) {
        bb_cleanup *c = bb_cleanups;
        bb_cleanups = c->prev;
        c->fn(c->ctx);
    }
    BB_LONGJMP(bb_errtop->jb, 1);
}

static BB_NORETURN void raise_common(void)
{
    bb_err.located = 0;
    bb_err.line = bb_line;
    bb_err.file = bb_file;
    bb_rethrow();
}

void bb_raise(int32_t num, const char *desc)
{
    bb_err.number = num;
    bb_str_set(&bb_err.description, bb_str_from_c(desc ? desc : bb_error_message(num)));
    bb_str_set(&bb_err.source, NULL);
    raise_common();
}

void bb_raise_str(int32_t num, bb_str *desc, bb_str *source)
{
    if (num <= 0 || num > 65535) {
        if (num == 0) bb_raise(5, NULL);
    }
    bb_err.number = num;
    if (bb_str_len(desc)) bb_str_assign(&bb_err.description, desc);
    else bb_str_set(&bb_err.description, bb_str_from_c(bb_error_message(num)));
    bb_str_assign(&bb_err.source, source);
    raise_common();
}

void bb_overflow(void) { bb_raise(6, NULL); }

/* ---- program ops ---- */

void bb_set_program(const bb_program_ops *ops) { g_prog = ops; }

void *bb_find_proc(const char *module, const char *name)
{
    return g_prog && g_prog->find_proc ? g_prog->find_proc(module, name) : NULL;
}

void *bb_find_global(const char *module, const char *name, int *type)
{
    return g_prog && g_prog->find_global ? g_prog->find_global(module, name, type) : NULL;
}

int32_t bb_call_proc(void *proc, int argc, bb_value *argv, bb_value *ret)
{
    bb_errframe f;
    bb_value dummy = bb_v_empty();
    volatile int32_t line = bb_line;
    const char *volatile file = bb_file;
    if (!ret) ret = &dummy;
    if (!g_prog || !proc) return 35;
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        g_prog->call_proc(proc, argc, argv, ret);
        bb_frame_pop(&f);
        bb_v_release(&dummy);
        bb_line = line; bb_file = file;
        return 0;
    }
    bb_frame_pop(&f);
    bb_line = line; bb_file = file;
    return bb_err.number ? bb_err.number : 51;
}

int bb_dispatch_event(const char *module, const char *object, const char *event,
                      int argc, bb_value *argv)
{
    char name[256];
    void *p;
    snprintf(name, sizeof name, "%s_%s", object, event);
    p = bb_find_proc(module, name);
    if (!p) return 0;
    if (bb_call_proc(p, argc, argv, NULL) != 0) bb_fatal_error();
    return 1;
}

/* ---- Err object ---- */
bb_long bb_err_number(void) { return bb_err.number; }
bb_str *bb_err_description(void) { return bb_str_retain(bb_err.description); }
bb_str *bb_err_source(void) { return bb_str_retain(bb_err.source); }
void bb_err_set_number(bb_long n)
{
    bb_err.number = n;
    if (n && !bb_str_len(bb_err.description)) bb_str_set(&bb_err.description, bb_str_from_c(bb_error_message(n)));
    if (!n) bb_str_set(&bb_err.description, NULL);
}
void bb_err_set_description(bb_str *s) { bb_str_assign(&bb_err.description, s); }
void bb_err_set_source(bb_str *s) { bb_str_assign(&bb_err.source, s); }

void bb_err_raise_v(bb_long num, const bb_value *source, const bb_value *desc)
{
    bb_str *src = NULL, *d = NULL;
    bb_value t;
    if (source && !(bb_v_deref(source, &t)->type == BB_ERROR && (bb_v_deref(source, &t)->flags & BB_VF_MISSING)))
        src = bb_v_to_str(source);
    if (desc && !(bb_v_deref(desc, &t)->type == BB_ERROR && (bb_v_deref(desc, &t)->flags & BB_VF_MISSING)))
        d = bb_v_to_str(desc);
    if (num < 0 && !d) d = bb_str_from_c("Automation error");
    if (!src) src = bb_str_from_c("");
    {
        bb_str *dd = d, *ss = src;
        bb_err.number = num;
        if (bb_str_len(dd)) bb_str_set(&bb_err.description, dd);
        else { bb_str_release(dd); bb_str_set(&bb_err.description, bb_str_from_c(bb_error_message(num))); }
        bb_str_set(&bb_err.source, ss);
    }
    bb_err.located = 0;
    bb_err.line = bb_line;
    bb_err.file = bb_file;
    bb_rethrow();
}
