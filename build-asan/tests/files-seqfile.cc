seqfile.bas:9:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
    9 |     bb_write_value(fn2, (&bbL.t3), 0);
      |                         ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:12:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   12 |     bb_write_value(fn2, (&bbL.t4), 0);
      |                         ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:15:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   15 |     bb_write_value(fn2, (&bbL.t5), 1);
      |                         ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:16:50: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   16 |         bb_str_set((bb_str **)&g1_s, bb_v_to_str(&bbL.t9)); bb_v_release(&bbL.t9);
      |                                                  ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:216:39: note: passing argument to parameter 'v' here
  216 | bb_str   *bb_v_to_str(const bb_value *v);    /* owned */
      |                                       ^
seqfile.bas:16:74: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   16 |         bb_str_set((bb_str **)&g1_s, bb_v_to_str(&bbL.t9)); bb_v_release(&bbL.t9);
      |                                                                          ^~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
seqfile.bas:21:26: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   21 |     bb_write_value(fn10, (&bbL.t11), 0);
      |                          ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:24:26: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   24 |     bb_write_value(fn10, (&bbL.t12), 1);
      |                          ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:22:26: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   22 |     bb_write_value(fn13, (&bbL.t14), 0);
      |                          ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:25:26: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   25 |     bb_write_value(fn13, (&bbL.t15), 1);
      |                          ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:609:45: note: passing argument to parameter 'v' here
  609 | void bb_write_value(int fn, const bb_value *v, int last);  /* Write # item */
      |                                             ^
seqfile.bas:26:53: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   26 |         bb_str_set((bb_str **)&g4_name, bb_v_to_str(&bbL.t18)); bb_v_release(&bbL.t18);
      |                                                     ^~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:216:39: note: passing argument to parameter 'v' here
  216 | bb_str   *bb_v_to_str(const bb_value *v);    /* owned */
      |                                       ^
seqfile.bas:26:78: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   26 |         bb_str_set((bb_str **)&g4_name, bb_v_to_str(&bbL.t18)); bb_v_release(&bbL.t18);
      |                                                                              ^~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
seqfile.bas:28:29: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   28 |         g2_n = bb_v_to_long(&bbL.t19); bb_v_release(&bbL.t19);
      |                             ^~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:209:40: note: passing argument to parameter 'v' here
  209 | bb_long   bb_v_to_long(const bb_value *v);
      |                                        ^
seqfile.bas:28:53: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   28 |         g2_n = bb_v_to_long(&bbL.t19); bb_v_release(&bbL.t19);
      |                                                     ^~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
seqfile.bas:36:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   36 |     bbL.t21 = bb_dir((&bbL.t20), ((bb_long)0));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:738:32: note: passing argument to parameter 'pattern' here
  738 | bb_str *bb_dir(const bb_value *pattern, bb_long attr);   /* Missing pattern: next match */
      |                                ^
seqfile.bas:37:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   37 |     bbL.t23 = bb_dir((&bbL.t22), ((bb_long)0));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:738:32: note: passing argument to parameter 'pattern' here
  738 | bb_str *bb_dir(const bb_value *pattern, bb_long attr);   /* Missing pattern: next match */
      |                                ^
seqfile.bas:39:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   39 |     bbL.t25 = bb_dir((&bbL.t24), ((bb_long)0));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:738:32: note: passing argument to parameter 'pattern' here
  738 | bb_str *bb_dir(const bb_value *pattern, bb_long attr);   /* Missing pattern: next match */
      |                                ^
seqfile.bas:43:22: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   43 |     bbL.t28 = bb_dir((&bbL.t27), ((bb_long)0));
      |                      ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:738:32: note: passing argument to parameter 'pattern' here
  738 | bb_str *bb_dir(const bb_value *pattern, bb_long attr);   /* Missing pattern: next match */
      |                                ^
17 warnings generated.
