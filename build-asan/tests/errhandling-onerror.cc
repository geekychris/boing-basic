onerror.bas:25:43: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   25 |     (void)bb_err_raise_v(((bb_long)1000), (&bbL.t0), (&bbL.t1));
      |                                           ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:533:50: note: passing argument to parameter 'source' here
  533 | void bb_err_raise_v(bb_long num, const bb_value *source, const bb_value *desc) BB_NORETURN;
      |                                                  ^
onerror.bas:25:54: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   25 |     (void)bb_err_raise_v(((bb_long)1000), (&bbL.t0), (&bbL.t1));
      |                                                      ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:533:74: note: passing argument to parameter 'desc' here
  533 | void bb_err_raise_v(bb_long num, const bb_value *source, const bb_value *desc) BB_NORETURN;
      |                                                                          ^
onerror.bas:34:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   34 |     bb_print_value(0, (&bbL.t4));
      |                       ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
onerror.bas:38:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   38 |     bb_print_value(0, (&bbL.t5));
      |                       ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
onerror.bas:76:43: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   76 |     bbL.t7 = bb_invoke(g2_o, "Foo", 1, 0, bbL.t6);
      |                                           ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
5 warnings generated.
