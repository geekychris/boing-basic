/* stdhello: a test standard extension (tests/ext/run.sh links it into a stock interpreter with
   STD_EXTS=stdhello STD_EXT_DIR=tests/ext/std); uses libm through its .bbx 'link m' */
#include "boing_ext.h"
#include <math.h>

static bb_value fn_cuberoot(int argc, bb_value *argv)
{
    (void)argc;
    return bb_ret_double(cbrt(bb_arg_double(argv, 0)));
}

BB_EXTENSION(stdhello)
{
    bb_register_function("CubeRoot", fn_cuberoot);
}
