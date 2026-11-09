/* Drone Courier: the C original's flights, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "a3d.h"
#include "dc.h"
static DCGame g;
static void play(uint32_t seed, int day, int max, int wobble)
{
    int t = 0;
    uint32_t s = 5;
    unsigned in = 0;
    DCEvent e;
    dc_new_game(&g, seed, day);
    while (t < max && !g.over && !g.won) {
        if (wobble) { if (t % 8 == 0) in = a3_rand(&s) % 32; } else in = dc_bot(&g);
        dc_tick(&g, in);
        while (dc_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu day %d%s, %d ticks: day %d jobs %d fails %d bumps %d score %ld hash %08lX\n",
           (unsigned long)seed, day, wobble ? " random input" : "", t, g.day, g.jobs_done, g.fails, g.bumps,
           (long)g.score, (unsigned long)dc_state_hash(&g));
}
int main(void)
{
    play(1234, 1, 9000, 0);
    play(3, 2, 5000, 0);
    play(55, 4, 5000, 0);
    play(9, 3, 1500, 1);
    return 0;
}
