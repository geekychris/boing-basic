/* Canyon Rail: the C original's games, for checking the BASIC port (see trace.sh) */
#include <stdio.h>
#include "cr.h"
static CRGame g;
static void play(uint32_t seed, int stage, int max, int wobble)
{
    int t = 0;
    uint32_t s = 7;
    unsigned in = 0;
    CREvent e;
    cr_new_game(&g, seed, stage);
    while (t < max && !g.over && !g.won) {
        if (wobble) { if (t % 6 == 0) in = a3_rand(&s) % 32; }
        else in = cr_bot(&g);
        cr_tick(&g, in);
        while (cr_pop_event(&g, &e)) continue;
        t++;
    }
    printf("seed %lu stage %d%s, %d ticks: stage %d score %ld shield %d hits %d/%d combo %d hash %08lX\n",
           (unsigned long)seed, stage, wobble ? " random input" : "", t, g.stage, (long)g.score, g.shield,
           g.hits, g.shots, g.best_combo, (unsigned long)cr_state_hash(&g));
}
int main(void)
{
    play(1234, 1, 4500, 0);
    play(5, 2, 3000, 0);
    play(99, 3, 3000, 0);
    play(42, 1, 2500, 1);
    return 0;
}
