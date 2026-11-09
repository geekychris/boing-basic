/* Orbit Docking: the C original's games, for checking the BASIC port (see trace.sh).
 * Prints the same lines as `boing run Trace.bbp`. */
#include <stdio.h>
#include "a3d.h"
#include "od.h"
#include "vectors.h"

static ODGame g;

static uint32_t fnv(uint32_t h, uint32_t v) { return (h ^ v) * 16777619UL; }

/* bot = 1: the autopilot; 0: random thrusters (a new input every 5 ticks) */
static void play(int bot, uint32_t seed, int level, int max)
{
    ODEvent e;
    int t = 0, nev = 0;
    uint32_t evh = 2166136261UL, lcg = seed * 2654435761UL + 1;
    unsigned in = 0;
    od_new_game(&g, seed, level);
    while (t < max && !g.over && !g.won) {
        if (bot) in = od_bot(&g);
        else if (t % 5 == 0) { lcg = lcg * 1103515245UL + 12345; in = (lcg >> 16) & 255; }
        od_tick(&g, in);
        while (od_pop_event(&g, &e)) { evh = fnv(fnv(fnv(evh, (uint32_t)e.type), (uint32_t)e.a), (uint32_t)e.b); nev++; }
        t++;
    }
    printf("%s seed %lu level %d, %d ticks: level %d docks %d crashes %d lives %d score %ld fuel %ld fail %d over %d won %d events %d/%08lX hash %08lX\n",
           bot ? "bot" : "random", (unsigned long)seed, level, t, g.level, g.docks, g.crashes, g.lives, (long)g.score,
           (long)g.fuel, g.last_fail, g.over, g.won, nev, (unsigned long)evh, (unsigned long)od_state_hash(&g));
}

int main(void)
{
    int s, lv;
    play(1, 1234, 1, 100000);
    printf("  vectors.h: %08lX\n", (unsigned long)OD_TRACE_HASH);
    for (lv = 1; lv <= OD_LEVELS; lv++)
        for (s = 1; s <= 3; s++) play(1, (uint32_t)(s * 7919 + lv), lv, 6000);
    for (s = 1; s <= 6; s++) play(0, (uint32_t)(s * 101), 1 + s % OD_LEVELS, 3000);
    return 0;
}
