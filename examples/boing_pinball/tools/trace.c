/* Boing Pinball: the C original's bot-played games, for checking the BASIC port
 * (see trace.sh). Prints a state hash every 1000 steps; BASIC's Trace.bbp prints the same. */
#include <stdio.h>
#include "a3d.h"
#include "pb.h"

static Table table;
static Game game;

static uint32_t fnv(uint32_t h, int32_t v) { return (h ^ (uint32_t)v) * 16777619u; }

static uint32_t state_hash(const Game *g)
{
    uint32_t h = 0x811C9DC5u;
    int i;
    const World *w = &g->w;
    h = fnv(h, g->score); h = fnv(h, g->time); h = fnv(h, g->state); h = fnv(h, g->ball_no); h = fnv(h, (int32_t)g->rng);
    for (i = 0; i < 3; i++) h = fnv(h, g->lanes[i]);
    h = fnv(h, g->skill_lane); h = fnv(h, g->bonus_x); h = fnv(h, g->locks); h = fnv(h, g->missions_done);
    h = fnv(h, g->mission); h = fnv(h, g->mission_n); h = fnv(h, g->multiball); h = fnv(h, g->jackpot);
    h = fnv(h, g->tilt_meter); h = fnv(h, g->tilt_warnings); h = fnv(h, g->pull); h = fnv(h, g->ntimers); h = fnv(h, g->nmsg);
    h = fnv(h, w->nballs);
    for (i = 0; i < w->nballs; i++) {
        const Ball *b = &w->balls[i];
        h = fnv(h, b->id); h = fnv(h, b->state); h = fnv(h, b->x); h = fnv(h, b->y); h = fnv(h, b->vx); h = fnv(h, b->vy);
        h = fnv(h, b->z); h = fnv(h, b->rs); h = fnv(h, b->rv); h = fnv(h, b->hold); h = fnv(h, b->nocatch); h = fnv(h, b->autol);
    }
    for (i = 0; i < w->nflip; i++) { h = fnv(h, w->flip[i].ang); h = fnv(h, w->flip[i].w); }
    for (i = 0; i < g->t->nspin; i++) { h = fnv(h, w->spin[i].ang); h = fnv(h, w->spin[i].w); }
    for (i = 0; i < g->t->ndrop; i++) h = fnv(h, g->t->seg[g->t->drop_seg[i]].up);
    return h;
}

static uint32_t table_hash(const Table *t)
{
    uint32_t h = 0x811C9DC5u;
    int i, x, y, k;
    for (i = 0; i < t->nseg; i++) {
        const Seg *s = &t->seg[i];
        h = fnv(h, s->ax); h = fnv(h, s->ay); h = fnv(h, s->bx); h = fnv(h, s->by); h = fnv(h, s->ux); h = fnv(h, s->uy);
        h = fnv(h, s->len); h = fnv(h, s->r); h = fnv(h, s->e); h = fnv(h, s->kind); h = fnv(h, s->bb[0]); h = fnv(h, s->bb[3]);
    }
    for (i = 0; i < t->nramp; i++) for (k = 0; k < t->ramp[i].n; k++) h = fnv(h, t->ramp[i].prof[k]);
    for (y = 0; y < PB_GY; y++) for (x = 0; x < PB_GX; x++) {
        h = fnv(h, t->ngrid[y][x]);
        for (k = 0; k < t->ngrid[y][x] && k < PB_GMAX; k++) h = fnv(h, t->grid[y][x][k]);
    }
    return h;
}

int main(int argc, char **argv)
{
    int t, gnum, games = argc > 1 ? atoi(argv[1]) : 2;
    long steps = argc > 2 ? atol(argv[2]) : 6000;
    for (t = 0; t < TB_COUNT; t++) {
        pb_build_table(&table, t);
        printf("table %d %s: nseg %d ncirc %d nsens %d hash %08lX\n", t, table.name, table.nseg, table.ncirc, table.nsens,
               (unsigned long)table_hash(&table));
        for (gnum = 0; gnum < games; gnum++) {
            Bot bot = { 0 };
            PbInput in;
            long s;
            bot.rng = 1234 + gnum * 77;
            pb_game_init(&game, &table, 99 + gnum);
            pb_game_start(&game);
            for (s = 1; s <= steps && game.state != GS_OVER; s++) {
                pb_bot(&game, &in, &bot);
                pb_game_tick(&game, &in);
                game.nev = 0;
                if (s % 1000 == 0) printf("  t%d g%d step %ld score %ld ball %d hash %08lX\n", t, gnum, s, (long)game.score,
                                          game.ball_no, (unsigned long)state_hash(&game));
            }
            printf("  t%d g%d end step %ld score %ld ball %d state %d hash %08lX\n", t, gnum, s - 1, (long)game.score,
                   game.ball_no, game.state, (unsigned long)state_hash(&game));
        }
    }
    /* random input: flippers, the plunger held, nudges (tilt), every 20 steps */
    for (t = 0; t < TB_COUNT; t++) {
        uint32_t r = 4242 + t;
        unsigned v = 0;
        long s;
        pb_build_table(&table, t);
        pb_game_init(&game, &table, 7 + t);
        pb_game_start(&game);
        for (s = 1; s <= steps && game.state != GS_OVER; s++) {
            PbInput in;
            if (s % 20 == 1) v = a3_rand(&r);
            in.left = v & 1; in.right = (v >> 1) & 1; in.plunger = ((v >> 2) & 3) == 0; in.pull_to = -1;
            in.nudge_x = s % 20 != 1 ? 0 : (v >> 4) % 31 == 0 ? (int)((v >> 7) % 3) - 1 : 0;
            in.nudge_y = s % 20 != 1 ? 0 : (v >> 9) % 37 == 0 ? 1 : 0;
            pb_game_tick(&game, &in);
            game.nev = 0;
            if (s % 1000 == 0) printf("  wobble t%d step %ld score %ld ball %d tilts %d hash %08lX\n", t, s, (long)game.score,
                                      game.ball_no, game.tilt_warnings, (unsigned long)state_hash(&game));
        }
        printf("  wobble t%d end step %ld score %ld ball %d hash %08lX\n", t, s - 1, (long)game.score, game.ball_no,
               (unsigned long)state_hash(&game));
    }
    return 0;
}
