/* ext_events.c - the registry's runtime-class events (bb_register_class_events), which the
   compiler reads to accept WithEvents on a runtime class */
#include "boing.h"
#include "boing_ext.h"
#include <stdio.h>
#include <string.h>

static const char *const evs[] = {"Connect", "DataArrival", "Close", NULL};

int main(void)
{
    const char *const *e;
    bb_register_class("EvTest", bb_runtime_class("Canvas"), NULL);
    if (bb_runtime_class_events("EvTest") != NULL) { puts("FAIL ext_events: events before registering"); return 1; }
    bb_register_class_events("EvTest", evs);
    e = bb_runtime_class_events("evtest");
    if (!e || strcmp(e[0], "Connect") || strcmp(e[1], "DataArrival") || strcmp(e[2], "Close") || e[3]) {
        puts("FAIL ext_events: registered list");
        return 1;
    }
    if (bb_runtime_class_events("NoSuchClass") != NULL) { puts("FAIL ext_events: unknown class"); return 1; }
    bb_register_class_events("NoSuchClass", evs);      /* ignored */
    puts("ext_events ok");
    return 0;
}
