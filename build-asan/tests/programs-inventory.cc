main.bas:20:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   20 |     bbL.t14 = bb_format((&bbL.t13), bb_k[8]);
      |                         ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:652:35: note: passing argument to parameter 'v' here
  652 | bb_str *bb_format(const bb_value *v, bb_str *fmt);
      |                                   ^
main.bas:31:25: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   31 |     bbL.t27 = bb_format((&bbL.t26), bb_k[8]);
      |                         ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:652:35: note: passing argument to parameter 'v' here
  652 | bb_str *bb_format(const bb_value *v, bb_str *fmt);
      |                                   ^
Inventory.cls:29:68: warning: passing 'volatile bb_value[1]' (aka 'volatile struct bb_value[1]') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   29 |     bbL.t1 = bb_invoke(((C1_inventory *)self)->f_mitems, "", 3, 1, bbL.t0);
      |                                                                    ^~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:471:79: note: passing argument to parameter 'argv' here
  471 | bb_value bb_invoke(bb_obj *o, const char *name, int kind, int argc, bb_value *argv);
      |                                                                               ^
Inventory.cls:30:62: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'const bb_value *' (aka 'const struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   30 |     bb_obj_set((bb_obj **)&bbL.l_find, bb_chkcls(bb_v_to_obj((&bbL.t1)), &C0_item_class));
      |                                                              ^~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:217:39: note: passing argument to parameter 'v' here
  217 | bb_obj   *bb_v_to_obj(const bb_value *v);    /* owned (retained); Nothing = NULL */
      |                                       ^
Inventory.cls:31:18: warning: passing 'volatile bb_value *' (aka 'volatile struct bb_value *') to parameter of type 'bb_value *' (aka 'struct bb_value *') discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
   31 |     bb_v_release(&bbL.t0[0]);
      |                  ^~~~~~~~~~
/Users/chris/code/claude_world/boing_basic-core/build-asan/include/boing.h:199:29: note: passing argument to parameter 'v' here
  199 | void bb_v_release(bb_value *v);                         /* free contents, set Empty */
      |                             ^
5 warnings generated.
