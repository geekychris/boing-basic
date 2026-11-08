main.bas:41:16: warning: passing 'bb_obj *volatile *' (aka 'struct bb_obj *volatile *') to parameter of type 'bb_obj **' (aka 'struct bb_obj **') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   41 |     bb_obj_set(&s4, p0_makenode(bb_str_retain(bb_k[9])));
      |                ^~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:454:36: note: passing argument to parameter 'dst' here
  454 | BB_INLINE void bb_obj_set(bb_obj **dst, bb_obj *owned) { bb_obj *o = *dst; *dst = owned; bb_obj_release(o); }
      |                                    ^
main.bas:47:16: warning: passing 'bb_obj *volatile *' (aka 'struct bb_obj *volatile *') to parameter of type 'bb_obj **' (aka 'struct bb_obj **') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   47 |     bb_obj_set(&s4, NULL);
      |                ^~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:454:36: note: passing argument to parameter 'dst' here
  454 | BB_INLINE void bb_obj_set(bb_obj **dst, bb_obj *owned) { bb_obj *o = *dst; *dst = owned; bb_obj_release(o); }
      |                                    ^
2 warnings generated.
