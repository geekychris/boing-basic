/* Tank Duel: the C original's autopilot fights, for checking the BASIC port.
 * cc -I$A3D -I$TD -o trace trace.c $TD/td_core.c $A3D/a3d_math.c $A3D/a3d_fix.c
 * (see trace.sh; A3D/TD = amiga_mcp's examples/amiga3d and examples/tank_duel) */
#include <stdio.h>
#include "a3d.h"
#include "td.h"
static TDGame g;
static void fight(uint32_t seed, int round, int max)
{
    int t = 0;
    TDEvent e;
    td_new_game(&g, seed, round);
    while (t < max && !g.over && !g.won) { td_tick(&g, td_bot(&g)); while (td_pop_event(&g, &e)) continue; t++; }
    printf("seed %lu round %d, %d ticks: round %d score %ld kills %d shots %d hits %d hp %d hash %08lX\n",
           (unsigned long)seed, round, t, g.round, (long)g.score, g.kills, g.shots, g.hits, g.tk[0].hp,
           (unsigned long)td_state_hash(&g));
}
int main(void)
{
    fight(1234, 1, 9000);
    fight(1, 1, 3000);
    fight(77, 3, 4000);
    fight(4242, 5, 4000);
    fight(9, 8, 3000);
    return 0;
}
