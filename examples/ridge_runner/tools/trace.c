/* Ridge Runner: the C original's races, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "a3d.h"
#include "rr.h"
static RRGame g;
static void play(uint32_t seed, int track, int max, int whole, int wobble)
{
    int t = 0;
    uint32_t s = 3;
    unsigned in = 0;
    RREvent e;
    rr_new_game(&g, seed, track);
    while (t < max && !g.over && !g.won && (whole || !g.finished)) {
        if (wobble) { if (t % 10 == 0) in = a3_rand(&s) % 32; } else in = rr_bot(&g);
        rr_tick(&g, in);
        while (rr_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu track %d%s%s, %d ticks: track %d place %d score %ld gates %d jumps %d bumps %d hash %08lX\n",
           (unsigned long)seed, track, whole ? " whole game" : "", wobble ? " random input" : "", t, g.track, g.place,
           (long)g.score, g.gates_hit, g.jumps, g.bumps, (unsigned long)rr_state_hash(&g));
}
int main(void)
{
    play(1234, 3, 4000, 0, 0);
    play(1, 1, 12000, 1, 0);
    play(77, 5, 3000, 0, 0);
    play(8, 2, 1500, 0, 1);
    return 0;
}
