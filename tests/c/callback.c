/* callback.c - AddressOf stubs called from C the way an OS callback would call them */
#include "boing.h"
#include <stdio.h>
#include <string.h>

typedef uint32_t (*cb8)(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);

static void *find(const char *mod, const char *name)
{
    (void)mod;
    if (!strcmp(name, "Sum")) return (void *)1;
    if (!strcmp(name, "Fail")) return (void *)2;
    return NULL;
}
static void call(void *proc, int argc, bb_value *argv, bb_value *ret)
{
    bb_long s = 0;
    int i;
    if (proc == (void *)2) bb_raise(5, NULL);
    for (i = 0; i < argc; i++) s += bb_v_to_long(&argv[i]) * (i + 1);
    *ret = bb_v_long(s);
}
static void *glob(const char *m, const char *n, int *t) { (void)m; (void)n; (void)t; return NULL; }
static const bb_program_ops ops = {find, call, glob};

int main(int argc, char **argv)
{
    cb8 f, g;
    int ok = 1;
    bb_rt_init(argc, argv);
    bb_set_program(&ops);
    f = (cb8)bb_addressof_ptr("M", "Sum", 3);
    g = (cb8)bb_addressof_ptr("M", "Sum", 3);
    if (f != g) { printf("FAIL same proc, different stubs\n"); ok = 0; }
    if (f(10, 20, 30, 0, 0, 0, 0, 0) != 10 + 40 + 90) { printf("FAIL result %u\n", (unsigned)f(10, 20, 30, 0, 0, 0, 0, 0)); ok = 0; }
    if (f(0xffffffffu, 0, 0, 0, 0, 0, 0, 0) != 0xffffffffu) { printf("FAIL -1\n"); ok = 0; }
    printf(ok ? "PASS callback\n" : "FAIL callback\n");
    return ok ? 0 : 1;
}
