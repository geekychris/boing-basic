/* Block Breaker 3D: the C original's autopilot games, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "a3d.h"
#include "bb.h"
static BBGame g;
static void play(uint32_t seed, int level, int max)
{
    int t = 0;
    BBEvent e;
    bb_new_game(&g, seed, level);
    while (t < max && !g.over && !g.won) {
        bb_tick(&g, bb_bot(&g));
        while (bb_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu level %d, %d ticks: level %d score %ld lives %d broken %d caps %d hash %08lX\n",
           (unsigned long)seed, level, t, g.level, (long)g.score, g.lives, g.broken, g.caps_dropped,
           (unsigned long)bb_state_hash(&g));
}
int main(void)
{
    play(1234, 1, 20000);
    play(7, 3, 6000);
    play(99, 5, 6000);
    play(2026, 8, 8000);
    return 0;
}
