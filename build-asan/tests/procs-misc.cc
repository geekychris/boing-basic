misc.bas:12:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   12 |     bbL.t5 = bb_v_cat((&bbL.t4), (&bb_vk_null));
      |                       ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:232:35: note: passing argument to parameter 'a' here
  232 | bb_value bb_v_cat(const bb_value *a, const bb_value *b);   /* &   */
      |                                   ^
misc.bas:13:46: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   13 |     bb_str_set((bb_str **)&g1_s, bb_v_to_str((&bbL.t5)));
      |                                              ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:216:39: note: passing argument to parameter 'v' here
  216 | bb_str   *bb_v_to_str(const bb_value *v);    /* owned */
      |                                       ^
misc.bas:18:21: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   18 |     bbL.t9 = bb_iif((&bbL.t6), (&bbL.t7), (&bbL.t8));
      |                     ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:672:33: note: passing argument to parameter 'c' here
  672 | bb_value bb_iif(const bb_value *c, const bb_value *a, const bb_value *b);
      |                                 ^
misc.bas:18:32: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   18 |     bbL.t9 = bb_iif((&bbL.t6), (&bbL.t7), (&bbL.t8));
      |                                ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:672:52: note: passing argument to parameter 'a' here
  672 | bb_value bb_iif(const bb_value *c, const bb_value *a, const bb_value *b);
      |                                                    ^
misc.bas:18:43: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   18 |     bbL.t9 = bb_iif((&bbL.t6), (&bbL.t7), (&bbL.t8));
      |                                           ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:672:71: note: passing argument to parameter 'b' here
  672 | bb_value bb_iif(const bb_value *c, const bb_value *a, const bb_value *b);
      |                                                                       ^
misc.bas:19:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   19 |     bb_print_value(0, (&bbL.t9));
      |                       ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
misc.bas:27:42: warning: passing 'volatile bb_value[3]' (aka 'volatile struct bb_value[3]') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   27 |     bbL.t11 = bb_choose(((bb_long)2), 3, bbL.t10);
      |                                          ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:673:57: note: passing argument to parameter 'argv' here
  673 | bb_value bb_choose(bb_long n, int argc, const bb_value *argv);
      |                                                         ^
misc.bas:28:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   28 |     bb_print_value(0, (&bbL.t11));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
misc.bas:29:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bb_v_release(&bbL.t10[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
misc.bas:30:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_v_release(&bbL.t10[1]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
misc.bas:31:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   31 |     bb_v_release(&bbL.t10[2]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
misc.bas:26:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   26 |     bbL.t13 = bb_str_fn((&bbL.t12));
      |                         ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:649:35: note: passing argument to parameter 'v' here
  649 | bb_str *bb_str_fn(const bb_value *v);    /* Str(): leading space for >= 0 */
      |                                   ^
misc.bas:29:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bbL.t20 = bb_int_fn((&bbL.t19));
      |                         ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:658:36: note: passing argument to parameter 'v' here
  658 | bb_value bb_int_fn(const bb_value *v);       /* Int (floor), keeps type */
      |                                    ^
misc.bas:30:39: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_print_double(0, bb_v_to_double((&bbL.t20)));
      |                                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:211:42: note: passing argument to parameter 'v' here
  211 | bb_double bb_v_to_double(const bb_value *v);
      |                                          ^
misc.bas:34:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   34 |     bbL.t22 = bb_fix((&bbL.t21));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:659:33: note: passing argument to parameter 'v' here
  659 | bb_value bb_fix(const bb_value *v);
      |                                 ^
misc.bas:35:39: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   35 |     bb_print_double(0, bb_v_to_double((&bbL.t22)));
      |                                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:211:42: note: passing argument to parameter 'v' here
  211 | bb_double bb_v_to_double(const bb_value *v);
      |                                          ^
misc.bas:30:31: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_print_single(0, bb_rnd((&bbL.t23)));
      |                               ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:663:34: note: passing argument to parameter 'v' here
  663 | bb_single bb_rnd(const bb_value *v);         /* VB's exact generator */
      |                                  ^
misc.bas:34:31: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   34 |     bb_print_single(0, bb_rnd((&bbL.t24)));
      |                               ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:663:34: note: passing argument to parameter 'v' here
  663 | bb_single bb_rnd(const bb_value *v);         /* VB's exact generator */
      |                                  ^
misc.bas:31:24: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   31 |     (void)bb_randomize((&bbL.t25));
      |                        ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:664:35: note: passing argument to parameter 'seed' here
  664 | void bb_randomize(const bb_value *seed);     /* Missing: Timer */
      |                                   ^
misc.bas:35:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   35 |     bbL.t27 = bb_hex((&bbL.t26));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:650:32: note: passing argument to parameter 'v' here
  650 | bb_str *bb_hex(const bb_value *v);
      |                                ^
misc.bas:40:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   40 |     bbL.t29 = bb_oct((&bbL.t28));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:651:32: note: passing argument to parameter 'v' here
  651 | bb_str *bb_oct(const bb_value *v);
      |                                ^
misc.bas:36:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   36 |     bbL.t31 = bb_typename((&bbL.t30));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
misc.bas:41:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bbL.t33 = bb_typename((&bbL.t32));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
misc.bas:46:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   46 |     bbL.t35 = bb_typename((&bbL.t34));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
misc.bas:51:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   51 |     bbL.t37 = bb_typename((&bbL.t36));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
misc.bas:56:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   56 |     bbL.t39 = bb_typename((&bbL.t38));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
misc.bas:61:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   61 |     bbL.t41 = bb_typename((&bbL.t40));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
27 warnings generated.
