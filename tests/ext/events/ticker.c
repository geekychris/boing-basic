/* ticker.c - a test extension class with events (tests/ext/run.sh): Ticker.Run n raises
   Tick(i, label) n times, then Done(); the indices are the order of ticker.bbx's event lines */
#include "boing_ext.h"
#include <stdio.h>

typedef struct ticker { bb_obj hdr; long runs; } ticker;

enum { M_RUN, P_RUNS };
enum { EV_TICK, EV_DONE };
static const bb_member ticker_members[] = {
    {"Run", M_RUN, BB_INV_METHOD}, {"Runs", P_RUNS, BB_INV_GET},
};

static void ticker_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    ticker *t = (ticker *)self;
    (void)kind;
    switch (id) {
    case M_RUN: {
        long n = bb_arg_long(argv, 0), i;
        if (argc != 1) bb_raise(450, NULL);
        t->runs++;
        for (i = 1; i <= n; i++) {
            char label[32];
            bb_value a[2];
            snprintf(label, sizeof label, "tick %ld", i);
            a[0] = bb_ret_long(i);
            a[1] = bb_ret_str(label);
            bb_event_raise(self, EV_TICK, "Tick", 2, a);
            bb_v_release(&a[1]);
        }
        bb_event_raise(self, EV_DONE, "Done", 0, NULL);
        return;
    }
    case P_RUNS: *ret = bb_ret_long(t->runs); return;
    }
    bb_raise(438, NULL);
}

BB_CLASS(ticker_class, "Ticker", ticker, ticker_members, ticker_invoke, NULL);

static bb_obj *new_ticker(void) { return bb_obj_new(&ticker_class); }

BB_EXTENSION(ticker)
{
    bb_register_class("Ticker", &ticker_class, new_ticker);
}
