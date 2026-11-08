adventure.bas:78:46: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   78 |     bbL.t1 = bb_invoke(g1_itemsat, "", 3, 1, bbL.t0);
      |                                              ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
adventure.bas:80:34: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   80 |     bbL.t3 = bb_v_cmp(BB_CMP_NE, (&bbL.t1), (&bbL.t2), 0);
      |                                  ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:241:43: note: passing argument to parameter 'a' here
  241 | bb_value bb_v_cmp(int op, const bb_value *a, const bb_value *b, int text);
      |                                           ^
adventure.bas:80:45: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   80 |     bbL.t3 = bb_v_cmp(BB_CMP_NE, (&bbL.t1), (&bbL.t2), 0);
      |                                             ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:241:62: note: passing argument to parameter 'b' here
  241 | bb_value bb_v_cmp(int op, const bb_value *a, const bb_value *b, int text);
      |                                                              ^
adventure.bas:81:21: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   81 |     c4 = bb_v_truth((&bbL.t3));
      |                     ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:219:32: note: passing argument to parameter 'v' here
  219 | int bb_v_truth(const bb_value *v);           /* condition value (Null -> false) */
      |                                ^
adventure.bas:82:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   82 |     bb_v_release(&bbL.t0[0]);
      |                  ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
adventure.bas:79:52: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   79 |     bbL.t6 = bb_invoke(g1_itemsat, "Remove", 1, 1, bbL.t5);
      |                                                    ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
adventure.bas:80:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   80 |     bb_v_release(&bbL.t5[0]);
      |                  ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
adventure.bas:81:49: warning: passing 'volatile bb_value[2]' (aka 'volatile struct bb_value[2]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   81 |     bbL.t8 = bb_invoke(g1_itemsat, "Add", 1, 2, bbL.t7);
      |                                                 ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
adventure.bas:82:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   82 |     bb_v_release(&bbL.t7[0]);
      |                  ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
adventure.bas:83:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   83 |     bb_v_release(&bbL.t7[1]);
      |                  ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
10 warnings generated.
