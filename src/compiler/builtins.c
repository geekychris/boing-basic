/* builtins.c - the built-in function table (see builtins.def) */
#include "bbc.h"
#include <string.h>

const Builtin builtins[] = {
#define BI(id, name, ret, mn, mx, params, defs, cfn, flags, vm) { name, ret, mn, mx, params, defs, cfn, flags },
#include "builtins.def"
#undef BI
};
const int nbuiltins = (int)(sizeof builtins / sizeof builtins[0]);

int builtin_find(const char *name)
{
    int i;
    for (i = 0; i < nbuiltins; i++)
        if (name_eq(builtins[i].name, name)) return i;
    return -1;
}
