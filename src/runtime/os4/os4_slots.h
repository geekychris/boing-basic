/* The interface slot table genbind writes (os4_slots.c): for Declares without Alias "#n". */
#ifndef BB_OS4_SLOTS_H
#define BB_OS4_SLOTS_H

struct bb_slot {
    const char *lib;      /* "dos.library", "gadgets/button.gadget", "timer.device" */
    const char *iface;    /* "main" */
    const char *name;     /* "Open" */
    short slot;           /* index in the interface's function table (Obtain = 0) */
    short argc;           /* arguments after Self */
};

extern const struct bb_slot bb_slots[];
extern const int bb_num_slots;

#endif
