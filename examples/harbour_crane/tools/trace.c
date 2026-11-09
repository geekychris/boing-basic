/* Harbour Crane: the C original's games, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "a3d.h"
#include "hc.h"
static HCGame g;
static void play(uint32_t seed, int level, int max, int wobble)
{
    int t = 0;
    uint32_t s = 11;
    unsigned in = 0;
    HCEvent e;
    hc_new_game(&g, seed, level);
    while (t < max && !g.over && !g.won) {
        if (wobble) { if (t % 7 == 0) in = a3_rand(&s) % 32; } else in = hc_bot(&g);
        hc_tick(&g, in);
        while (hc_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu level %d%s, %d ticks: level %d score %ld loaded %d lost %d dents %d hash %08lX\n",
           (unsigned long)seed, level, wobble ? " random input" : "", t, g.level, (long)g.score, g.total_loaded, g.lost,
           g.dents, (unsigned long)hc_state_hash(&g));
}
int main(void)
{
    play(1234, 1, 15000, 0);
    play(4, 4, 9000, 0);
    play(8, 7, 6000, 0);
    play(2, 3, 2000, 1);
    return 0;
}
