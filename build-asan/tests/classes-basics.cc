main.bas:13:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   13 |     bbL.t12 = bb_typename((&bbL.t11));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
main.bas:28:53: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   28 |     bbL.t19 = bb_invoke(bbL.l_o, "Increment", 1, 1, bbL.t18);
      |                                                     ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:29:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bb_v_release(&bbL.t18[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:29:49: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bbL.t21 = bb_invoke(bbL.l_o, "Label", 4, 1, bbL.t20);
      |                                                 ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:30:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_v_release(&bbL.t20[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:29:49: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bbL.t23 = bb_invoke(bbL.l_o, "Value", 3, 0, bbL.t22);
      |                                                 ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:30:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_print_value(0, (&bbL.t23));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:32:49: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   32 |     bbL.t25 = bb_invoke(bbL.l_o, "Twice", 3, 0, bbL.t24);
      |                                                 ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:33:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   33 |     bb_print_value(0, (&bbL.t25));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:35:52: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   35 |     bbL.t27 = bb_invoke(bbL.l_o, "Describe", 3, 0, bbL.t26);
      |                                                    ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:36:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   36 |     bb_print_value(0, (&bbL.t27));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:38:54: warning: passing 'volatile bb_value[2]' (aka 'volatile struct bb_value[2]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   38 |     bbL.t30 = bb_invoke(bbL.l_accounts, "Add", 1, 2, bbL.t29);
      |                                                      ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:39:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   39 |     bb_v_release(&bbL.t29[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:40:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   40 |     bb_v_release(&bbL.t29[1]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:41:54: warning: passing 'volatile bb_value[2]' (aka 'volatile struct bb_value[2]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bbL.t33 = bb_invoke(bbL.l_accounts, "Add", 1, 2, bbL.t32);
      |                                                      ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:42:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   42 |     bb_v_release(&bbL.t32[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:43:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   43 |     bb_v_release(&bbL.t32[1]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:41:51: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bbL.t36 = bb_invoke(bbL.l_accounts, "", 3, 1, bbL.t35);
      |                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:43:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   43 |     bbL.t37 = bb_v_invoke((&bbL.t36), "Deposit", 1, 1, bbL.t34);
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:38: note: passing argument to parameter 'v' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                      ^
main.bas:43:56: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   43 |     bbL.t37 = bb_v_invoke((&bbL.t36), "Deposit", 1, 1, bbL.t34);
      |                                                        ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:44:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   44 |     bb_v_release(&bbL.t35[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:46:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   46 |     bb_v_release(&bbL.t34[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:41:56: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bbL.t39 = bb_invoke(bbL.l_accounts, "Count", 3, 0, bbL.t38);
      |                                                        ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:42:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   42 |     bb_print_value(0, (&bbL.t39));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:45:51: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   45 |     bbL.t42 = bb_invoke(bbL.l_accounts, "", 3, 1, bbL.t41);
      |                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:46:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   46 |     bbL.t43 = bb_v_invoke((&bbL.t42), "Balance", 3, 0, bbL.t40);
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:38: note: passing argument to parameter 'v' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                      ^
main.bas:46:56: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   46 |     bbL.t43 = bb_v_invoke((&bbL.t42), "Balance", 3, 0, bbL.t40);
      |                                                        ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:47:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_print_value(0, (&bbL.t43));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:48:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   48 |     bb_v_release(&bbL.t41[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:52:51: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   52 |     bbL.t46 = bb_invoke(bbL.l_accounts, "", 3, 1, bbL.t45);
      |                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:53:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   53 |     bbL.t47 = bb_v_invoke((&bbL.t46), "Balance", 3, 0, bbL.t44);
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:38: note: passing argument to parameter 'v' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                      ^
main.bas:53:56: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   53 |     bbL.t47 = bb_v_invoke((&bbL.t46), "Balance", 3, 0, bbL.t44);
      |                                                        ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:54:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   54 |     bb_print_value(0, (&bbL.t47));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:55:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   55 |     bb_v_release(&bbL.t45[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:44:73: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   44 |         bbL.t49 = bb_v_invoke(((bb_value *)&bbL.l_item), "Owner", 3, 0, bbL.t48);
      |                                                                         ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:45:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   45 |         bb_print_value(0, (&bbL.t49));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:49:76: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   49 |         bbL.t51 = bb_v_invoke(((bb_value *)&bbL.l_item), "Withdraw", 3, 1, bbL.t50);
      |                                                                            ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:50:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   50 |         bb_print_value(0, (&bbL.t51));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:51:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   51 |         bb_v_release(&bbL.t50[0]);
      |                      ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:53:75: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   53 |         bbL.t53 = bb_v_invoke(((bb_value *)&bbL.l_item), "Balance", 3, 0, bbL.t52);
      |                                                                           ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:54:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   54 |         bb_print_value(0, (&bbL.t53));
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:47:63: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_v_set(&bbL.s7, bb_invoke(bbL.l_accounts, "Item", 3, 1, bbL.t54));
      |                                                               ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:47:14: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_v_set(&bbL.s7, bb_invoke(bbL.l_accounts, "Item", 3, 1, bbL.t54));
      |              ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:201:35: note: passing argument to parameter 'dst' here
  201 | BB_INLINE void bb_v_set(bb_value *dst, bb_value owned) { bb_value o = *dst; *dst = owned; bb_v_release(&o); }
      |                                   ^
main.bas:48:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   48 |     bb_v_release(&bbL.t54[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:48:67: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   48 |     bbL.t56 = bb_v_invoke(((bb_value *)&bbL.s7), "Deposit", 1, 1, bbL.t55);
      |                                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:49:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   49 |     bb_v_release(&bbL.t55[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:48:65: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   48 |     bbL.t58 = bb_v_invoke(((bb_value *)&bbL.s7), "Owner", 3, 0, bbL.t57);
      |                                                                 ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:49:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   49 |     bb_print_value(0, (&bbL.t58));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:51:67: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   51 |     bbL.t60 = bb_v_invoke(((bb_value *)&bbL.s7), "Balance", 3, 0, bbL.t59);
      |                                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:52:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   52 |     bb_print_value(0, (&bbL.t60));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:55:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   55 |     bb_v_release(&bbL.s7);
      |                  ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:51:57: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   51 |     bbL.t62 = bb_invoke(bbL.l_accounts, "Remove", 1, 1, bbL.t61);
      |                                                         ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:52:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   52 |     bb_v_release(&bbL.t61[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
main.bas:51:56: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   51 |     bbL.t64 = bb_invoke(bbL.l_accounts, "Count", 3, 0, bbL.t63);
      |                                                        ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:52:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   52 |     bb_print_value(0, (&bbL.t64));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:55:51: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   55 |     bbL.t67 = bb_invoke(bbL.l_accounts, "", 3, 1, bbL.t66);
      |                                                   ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:56:27: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   56 |     bbL.t68 = bb_v_invoke((&bbL.t67), "Owner", 3, 0, bbL.t65);
      |                           ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:38: note: passing argument to parameter 'v' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                      ^
main.bas:56:54: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   56 |     bbL.t68 = bb_v_invoke((&bbL.t67), "Owner", 3, 0, bbL.t65);
      |                                                      ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:474:89: note: passing argument to parameter 'argv' here
  474 | bb_value bb_v_invoke(const bb_value *v, const char *name, int kind, int argc, bb_value *argv);
      |                                                                                         ^
main.bas:57:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   57 |     bb_print_value(0, (&bbL.t68));
      |                       ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:58:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   58 |     bb_v_release(&bbL.t66[0]);
      |                  ^~~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
60 warnings generated.
