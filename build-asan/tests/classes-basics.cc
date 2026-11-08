main.bas:47:14: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_v_set(&s7, bb_invoke(l_accounts, "Item", 3, 1, t54));
      |              ^~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:192:35: note: passing argument to parameter 'dst' here
  192 | BB_INLINE void bb_v_set(bb_value *dst, bb_value owned) { bb_value o = *dst; *dst = owned; bb_v_release(&o); }
      |                                   ^
main.bas:55:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   55 |     bb_v_release(&s7);
      |                  ^~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:190:29: note: passing argument to parameter 'v' here
  190 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
2 warnings generated.
