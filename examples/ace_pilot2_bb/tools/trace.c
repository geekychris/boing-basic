/* Ace Pilot 2: the C original's autopilot campaigns, for checking the BASIC port (see trace.sh).
 * Prints the same lines as `boing run Trace.bbp`. */
#include <stdio.h>
#include "a3d.h"
#include "ap.h"
#include "vectors.h"

static APGame g;

static uint32_t fnv(uint32_t h, uint32_t v) { return (h ^ v) * 16777619UL; }

/* the whole campaign from mission m, missions advancing as they end (tests/test_cases.c);
 * every `every` ticks a line with the state hash */
static void campaign(uint32_t seed, int m, int ticks, int every)
{
    APEvent e;
    int t, nev = 0;
    uint32_t evh = 2166136261UL;
    ap_new_game(&g, seed, m);
    for (t = 0; t < ticks && !g.over && !g.won; t++) {
        ap_tick(&g, ap_bot(&g));
        while (ap_pop_event(&g, &e)) {
            evh = fnv(fnv(fnv(evh, (uint32_t)e.type), (uint32_t)e.a), (uint32_t)e.b);
            evh = fnv(fnv(fnv(evh, (uint32_t)e.x), (uint32_t)e.y), (uint32_t)e.z);
            nev++;
        }
        if (g.phase >= PH_DONE && g.end_t == 0) ap_next(&g);
        if (every && (t + 1) % every == 0)
            printf("  t %d mission %d phase %d score %ld hash %08lX\n", t + 1, g.mission, g.phase, (long)g.score,
                   (unsigned long)ap_state_hash(&g));
    }
    printf("seed %lu from mission %d, %d ticks: mission %d phase %d score %ld kills %d ground %d shots %d hits %d lives %d over %d won %d events %d/%08lX hash %08lX\n",
           (unsigned long)seed, m, t, g.mission, g.phase, (long)g.score, g.kills, g.gkills, g.shots, g.hits, g.lives,
           g.over, g.won, nev, (unsigned long)evh, (unsigned long)ap_state_hash(&g));
}

int main(void)
{
    int m;
    campaign(1234, 1, 20000, 1000);
    printf("  vectors.h: %08lX\n", (unsigned long)AP_TRACE_HASH);
    for (m = 1; m <= AP_MISSIONS; m++) campaign((uint32_t)(m * 31 + 5), m, 4000, 0);
    return 0;
}
