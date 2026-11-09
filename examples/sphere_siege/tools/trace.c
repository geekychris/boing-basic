/* Sphere Siege: the C original's autopilot games, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "ss.h"
static SSGame g;
static void play(uint32_t seed, int wave, int max)
{
    int t = 0;
    SSEvent e;
    ss_new_game(&g, seed, wave);
    while (t < max && !g.over) {
        ss_tick(&g, ss_bot(&g));
        while (ss_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu wave %d, %d ticks: wave %d lives %d score %ld shots %d hits %d kills %d hash %08lX\n",
           (unsigned long)seed, wave, t, g.wave, g.lives, (long)g.score, g.shots, g.hits, g.kills,
           (unsigned long)ss_state_hash(&g));
}
int main(void)
{
    play(1234, 1, 6000);
    play(5, 4, 3000);
    play(31337, 6, 3000);
    return 0;
}
