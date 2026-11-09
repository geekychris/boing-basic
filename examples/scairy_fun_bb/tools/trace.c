/* ScAIry Fun: the C original's drives, for checking the BASIC port (see trace.sh).
 * Prints the same lines as `boing run Trace.bbp`. */
#include <stdio.h>
#include <string.h>
#include "sc.h"

static World w;

static uint32_t fnv(uint32_t h, uint32_t v) { return (h ^ v) * 16777619UL; }

static uint32_t state_hash(void)
{
    uint32_t h = 2166136261UL;
    int i;
    h = fnv(h, w.route); h = fnv(h, w.state); h = fnv(h, w.frame); h = fnv(h, w.state_timer); h = fnv(h, w.rng);
    h = fnv(h, w.car.state); h = fnv(h, w.car.z); h = fnv(h, w.car.d); h = fnv(h, w.car.v); h = fnv(h, w.car.s); h = fnv(h, w.car.lat);
    h = fnv(h, w.car.timer); h = fnv(h, w.car.cool);
    h = fnv(h, w.ai.on); h = fnv(h, w.ai.lane); h = fnv(h, w.ai.target_v); h = fnv(h, w.ai.blinded); h = fnv(h, w.ai.phantom_timer);
    h = fnv(h, w.ai.nseen);
    for (i = 0; i < 16; i++) h = fnv(h, w.ai.plan[i]);
    for (i = 0; i < MAX_OBJS; i++)
        if (w.obj[i].type) {
            h = fnv(h, i); h = fnv(h, w.obj[i].type); h = fnv(h, w.obj[i].flags); h = fnv(h, w.obj[i].lane);
            h = fnv(h, w.obj[i].z); h = fnv(h, w.obj[i].d); h = fnv(h, w.obj[i].v); h = fnv(h, w.obj[i].timer);
        }
    for (i = 0; i < w.nhaz; i++) h = fnv(h, w.haz_state[i]);
    h = fnv(h, w.score); h = fnv(h, w.cover); h = fnv(h, w.mult); h = fnv(h, w.ap_frames); h = fnv(h, w.dist_ap); h = fnv(h, w.dist_all);
    h = fnv(h, w.saves); h = fnv(h, w.needless); h = fnv(h, w.takeovers); h = fnv(h, w.msg); h = fnv(h, w.glare); h = fnv(h, w.siren);
    return h;
}

/* mode 0: the title's demo; 1: the perfect autopilot from route r; 2: the shipped autopilot,
 * hands off; 3: random hands (a new input every 10 frames) */
static void drive(int mode, int r, int traffic, int frames, int every)
{
    Event e;
    int f, nev = 0;
    uint32_t evh = 2166136261UL, lcg = (uint32_t)(r * 7 + mode * 131 + 1);
    unsigned in = 0;
    static const unsigned pick[6] = { 0, IN_LEFT, IN_RIGHT, IN_UP, IN_DOWN, IN_FIRE };
    w.tune.speed_pct = 0;               /* world_init: the defaults */
    world_init(&w);
    w.tune.traffic_pct = traffic;
    if (mode == 1) w.tune.ai_perfect = 1;
    if (mode) {
        world_start_game(&w);
        if (r) world_start_route(&w, r);
        w.state = GS_PLAY;
    }
    for (f = 0; f < frames; f++) {
        if (mode == 3 && f % 10 == 0) { lcg = lcg * 1103515245UL + 12345; in = pick[(lcg >> 16) % 6]; }
        world_update(&w, in);
        while (world_pop_event(&w, &e)) { evh = fnv(fnv(fnv(evh, (uint32_t)e.type), (uint32_t)e.a), (uint32_t)e.b); nev++; }
        if (every && (f + 1) % every == 0)
            printf("  f %d route %d state %d seg %d score %ld cover %ld hash %08lX\n", f + 1, w.route + 1, w.state,
                   seg_of(w.car.z), (long)w.score, (long)w.cover, (unsigned long)state_hash());
        if (mode && mode != 3 && w.state != GS_PLAY && w.state != GS_INTRO) break;
    }
    printf("mode %d route %d traffic %d, %d frames: route %d state %d seg %d score %ld cover %ld saves %ld needless %ld takeovers %ld events %d/%08lX hash %08lX\n",
           mode, r + 1, traffic, f, w.route + 1, w.state, seg_of(w.car.z), (long)w.score, (long)w.cover, (long)w.saves,
           (long)w.needless, (long)w.takeovers, nev, (unsigned long)evh, (unsigned long)state_hash());
}

int main(void)
{
    int r;
    drive(0, 0, 100, 3000, 0);
    for (r = 0; r < NUM_ROUTES; r++) drive(1, r, 100, 9000, 1000);
    for (r = 0; r < NUM_ROUTES; r++) drive(2, r, 100, 9000, 1000);
    for (r = 0; r < NUM_ROUTES; r++) drive(3, r, 60, 4000, 0);
    return 0;
}
