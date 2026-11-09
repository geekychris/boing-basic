/* Marble Tilt: the C original's autopilot games, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "a3d.h"
#include "mt.h"
static MTGame g;
static void play(int level, int max)
{
    int t = 0;
    MTEvent e;
    mt_new_game(&g, 1, level);
    while (t < max && !g.over && !g.won) {
        mt_tick(&g, mt_bot(&g));
        while (mt_pop_event(&g, &e)) continue;
        t++;
    }
    printf("from level %d, %d ticks: level %d score %ld falls %d bumps %d time %ld won %d hash %08lX\n",
           level, t, g.level, (long)g.score, g.falls, g.bumps, (long)g.time_left, g.won, (unsigned long)mt_state_hash(&g));
}
/* random tilting (bumpers, walls, holes, falls): a3_rand picks the input every 8 ticks */
static void wobble(int level, int max)
{
    uint32_t s = 99;
    unsigned in = 0;
    int t;
    MTEvent e;
    mt_new_game(&g, 1, level);
    for (t = 0; t < max && !g.over && !g.won; t++) {
        if (t % 8 == 0) in = a3_rand(&s) % 16;
        mt_tick(&g, in);
        while (mt_pop_event(&g, &e)) continue;
    }
    printf("wobble level %d, %d ticks: level %d falls %d bumps %d time %ld hash %08lX\n",
           level, t, g.level, g.falls, g.bumps, (long)g.time_left, (unsigned long)mt_state_hash(&g));
}
int main(void)
{
    int k;
    wobble(5, 1500);
    wobble(4, 1500);
    wobble(8, 1500);
    play(1, 6000);
    for (k = 2; k <= 8; k++) play(k, 2000);
    return 0;
}
