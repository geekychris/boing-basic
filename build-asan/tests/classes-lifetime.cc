main.bas:32:48: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   32 |     bbL.t2 = bb_invoke(bbL.l_o, "Upper", 3, 0, bbL.t1);
      |                                                ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:33:23: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   33 |     bb_print_value(0, (&bbL.t2));
      |                       ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:598:45: note: passing argument to parameter 'v' here
  598 | void bb_print_value(int fn, const bb_value *v);   /* Print formatting of a Variant */
      |                                             ^
main.bas:37:26: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   37 |     bbL.t4 = bb_typename((&bbL.t3));
      |                          ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:669:37: note: passing argument to parameter 'v' here
  669 | bb_str *bb_typename(const bb_value *v);
      |                                     ^
main.bas:35:47: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   35 |     bbL.t6 = bb_invoke(bbL.l_o, "Fail", 3, 0, bbL.t5);
      |                                               ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:36:24: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   36 |     l_r = bb_v_to_long((&bbL.t6));
      |                        ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:209:40: note: passing argument to parameter 'v' here
  209 | bb_long   bb_v_to_long(const bb_value *v);
      |                                        ^
main.bas:38:50: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   38 |     bbL.t9 = bb_invoke(bbL.l_o, "Missing", 1, 0, bbL.t8);
      |                                                  ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
main.bas:41:16: warning: passing 'bb_obj *volatile *' (aka 'struct bb_obj *volatile *') to parameter of type 'bb_obj **' (aka 'struct bb_obj **') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bb_obj_set(&bbL.s4, p0_makenode(bb_str_retain(bb_k[9])));
      |                ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:463:36: note: passing argument to parameter 'dst' here
  463 | BB_INLINE void bb_obj_set(bb_obj **dst, bb_obj *owned) { bb_obj *o = *dst; *dst = owned; bb_obj_release(o); }
      |                                    ^
main.bas:47:16: warning: passing 'bb_obj *volatile *' (aka 'struct bb_obj *volatile *') to parameter of type 'bb_obj **' (aka 'struct bb_obj **') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_obj_set(&bbL.s4, NULL);
      |                ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:463:36: note: passing argument to parameter 'dst' here
  463 | BB_INLINE void bb_obj_set(bb_obj **dst, bb_obj *owned) { bb_obj *o = *dst; *dst = owned; bb_obj_release(o); }
      |                                    ^
8 warnings generated.
