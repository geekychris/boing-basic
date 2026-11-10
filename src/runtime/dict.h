/* dict.h - Boing.Dictionary, a hash map from keys (strings, numbers, objects) to values,
 * keeping insertion order (dict.c). The C side is used by JSON (json.c). */
#ifndef BB_DICT_H
#define BB_DICT_H

#include "boing.h"

const bb_class *bb_dict_class(void);
bb_obj *bb_dict_new(void);                                  /* reference count 1 */
int bb_is_dict(const bb_obj *o);
/* set (add or replace) key -> value; both borrowed (copied) */
void bb_dict_set(bb_obj *d, const bb_value *key, const bb_value *value);
/* the value for key, or NULL (borrowed, valid until the dictionary changes) */
const bb_value *bb_dict_get(bb_obj *d, const bb_value *key);
int32_t bb_dict_count(bb_obj *d);
/* the i-th live entry in insertion order (0 <= i < count): borrowed key and value */
void bb_dict_entry(bb_obj *d, int32_t i, const bb_value **key, const bb_value **value);

#endif
