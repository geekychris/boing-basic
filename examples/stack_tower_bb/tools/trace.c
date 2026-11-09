/* Stack Tower: the C original's games, for checking the BASIC port (see trace.sh).
 * Prints the same lines as `boing run Trace.bbp`. */
#include <stdio.h>
#include <string.h>
#include "a3d.h"
#include "st.h"
#include "vectors.h"

static StGame g;

static uint32_t fnv(uint32_t h, uint32_t v) { return (h ^ v) * 16777619UL; }

static uint32_t state_hash(const StGame *s)
{
    uint32_t h = 2166136261UL;
    int i;
    for (i = 0; i < ST_COLS * ST_TOTAL; i++) h = fnv(h, s->board[i]);
    h = fnv(h, s->mode); h = fnv(h, s->rng); h = fnv(h, s->nqueue);
    for (i = 0; i < s->nqueue; i++) h = fnv(h, s->queue[i]);
    h = fnv(h, s->hold); h = fnv(h, s->can_hold);
    h = fnv(h, s->piece.type); h = fnv(h, s->piece.rot); h = fnv(h, s->piece.col); h = fnv(h, s->piece.row);
    h = fnv(h, s->level); h = fnv(h, s->lines); h = fnv(h, s->combo); h = fnv(h, s->pieces);
    h = fnv(h, (uint32_t)s->score); h = fnv(h, (uint32_t)s->time_ms);
    h = fnv(h, s->fall_ms); h = fnv(h, s->lock_ms); h = fnv(h, s->resets); h = fnv(h, s->soft);
    h = fnv(h, s->over); h = fnv(h, s->won); h = fnv(h, s->rise_ms); h = fnv(h, s->garbage_left);
    h = fnv(h, s->last_col);
    return h;
}

static uint32_t board_hash(const StGame *s)
{
    uint32_t h = 2166136261UL;
    int i;
    for (i = 0; i < ST_COLS * ST_TOTAL; i++) h = fnv(h, s->board[i]);
    return h;
}

/* the browser vectors' script (tests/test_cases.c) */
static void script(int mode, uint32_t seed)
{
    int k, i, q[5];
    st_new_game(&g, mode, seed, 1, 0);
    for (k = 0; k < 120 && !g.over && !g.won; k++) {
        int r = (int)((k * 7 + seed) % 5), m = (int)((k * 13 + seed) % 9) - 4;
        if (k % 11 == 5) st_hold(&g);
        for (i = 0; i < r; i++) st_rotate(&g, i % 2 ? -1 : 1);
        for (i = 0; i < (m < 0 ? -m : m); i++) st_move(&g, m < 0 ? -1 : 1);
        st_hard_drop(&g);
    }
    st_preview(&g, 5, q);
    printf("script %s %lu: pieces %d score %ld rings %d over %d won %d board %lu queue %d %d %d %d %d hold %d hash %08lX\n",
           st_mode_names[mode], (unsigned long)seed, k, (long)g.score, g.lines, g.over, g.won,
           (unsigned long)board_hash(&g), q[0], q[1], q[2], q[3], q[4], g.hold, (unsigned long)state_hash(&g));
}

/* the best place for the piece, as the title's demo picks it (game.c demo_step) */
static void best_place(StGame *s, int *bc, int *br)
{
    int best = 1 << 30, r, c;
    *bc = 0; *br = 0;
    for (r = 0; r < 4; r++)
        for (c = 0; c < ST_COLS; c++) {
            Piece p = s->piece;
            int cells[5][2], n, k, h = 0;
            p.rot = r;
            p.col = c;
            if (st_collides(s, &p)) continue;
            while (1) { p.row--; if (st_collides(s, &p)) { p.row++; break; } }
            n = st_cells_of(&p, cells);
            for (k = 0; k < n; k++) h += cells[k][1] * 4;
            h += (int)(a3_hash((uint32_t)(c * 4 + r + s->pieces * 64)) & 3);
            if (h < best) { best = h; *bc = c; *br = r; }
        }
}

/* the title's demo: every 6th tick a piece goes straight to its best place */
static int demo_t;
static void demo_step(void)
{
    int c, r;
    if (++demo_t < 6) return;
    demo_t = 0;
    if (g.over) { st_new_game(&g, MODE_MARATHON, a3_hash((uint32_t)g.seed), 1, 0); return; }
    best_place(&g, &c, &r);
    g.piece.rot = r;
    g.piece.col = c;
    g.last_col = c;
    st_hard_drop(&g);
}

/* the bot's choice: low, filling rings, few holes under the piece */
static void bot_place(StGame *s, int *bc, int *br)
{
    int best = 1 << 30, r, c;
    *bc = s->piece.col; *br = s->piece.rot;
    for (r = 0; r < 4; r++)
        for (c = 0; c < ST_COLS; c++) {
            Piece p = s->piece;
            int cells[5][2], n, k, j, h = 0, row, full;
            p.rot = r;
            p.col = c;
            if (st_collides(s, &p)) continue;
            while (1) { p.row--; if (st_collides(s, &p)) { p.row++; break; } }
            n = st_cells_of(&p, cells);
            for (k = 0; k < n; k++) {
                h += cells[k][1] * 6;
                row = cells[k][1] - 1;           /* a hole: an empty cell right under, not the piece's own */
                if (row >= 0 && !s->board[row * ST_COLS + cells[k][0]]) {
                    for (j = 0; j < n; j++) if (cells[j][0] == cells[k][0] && cells[j][1] == row) break;
                    if (j == n) h += 10;
                }
            }
            for (k = 0; k < n; k++) {            /* rings it fills (a row counted once per cell in it) */
                row = cells[k][1];
                for (full = 1, j = 0; j < ST_COLS && full; j++) {
                    int m, inp = 0;
                    for (m = 0; m < n; m++) if (cells[m][0] == j && cells[m][1] == row) inp = 1;
                    if (!inp && !s->board[row * ST_COLS + j]) full = 0;
                }
                if (full) h -= 40;
            }
            h += (int)(a3_hash((uint32_t)(c * 4 + r + s->pieces * 64)) & 3);
            if (h < best) { best = h; *bc = c; *br = r; }
        }
}

/* a bot that plays like a person: holds now and then, rotates and turns a step a
 * tick, then soft drops, hard drops or waits for gravity */
static int bot_pieces = -1, bot_col, bot_rot, bot_hold_tries;
static void bot_tick(void)
{
    if (g.pieces != bot_pieces || bot_hold_tries) {
        if (g.pieces != bot_pieces) bot_hold_tries = 0;
        bot_pieces = g.pieces;
        if (g.pieces % 7 == 3 && g.can_hold && !bot_hold_tries) { st_hold(&g); bot_hold_tries = 1; }
        else bot_hold_tries = 0;
        bot_place(&g, &bot_col, &bot_rot);
    }
    if (g.piece.rot != bot_rot) {
        if (!st_rotate(&g, 1)) bot_rot = g.piece.rot;
        st_soft_drop(&g, 0);
    } else if (g.piece.col != bot_col) {
        int d = st_mod(bot_col - g.piece.col, ST_COLS) <= 8 ? 1 : -1;
        if (!st_move(&g, d)) bot_col = g.piece.col;
        st_soft_drop(&g, 0);
    } else if (g.pieces % 3 == 0) st_soft_drop(&g, 1);
    else if (g.pieces % 3 == 1) { st_soft_drop(&g, 0); st_hard_drop(&g); }
    else st_soft_drop(&g, 0);
}

static void play(int bot, int mode, uint32_t seed, int level, int ticks)
{
    StEvent e;
    int t, games = 1, nev = 0;
    uint32_t evh = 2166136261UL;
    demo_t = 0; bot_pieces = -1; bot_hold_tries = 0;
    st_new_game(&g, mode, seed, level, 0);
    for (t = 1; t <= ticks; t++) {
        if (bot) bot_tick(); else demo_step();
        st_tick(&g, 40);
        while (st_pop_event(&g, &e)) { evh = fnv(fnv(fnv(evh, e.type), (uint32_t)e.a), (uint32_t)e.b); nev++; }
        if (g.over || g.won) {
            printf("  t %d game %d over %d won %d score %ld rings %d level %d pieces %d hash %08lX\n", t, games,
                   g.over, g.won, (long)g.score, g.lines, g.level, g.pieces, (unsigned long)state_hash(&g));
            games++;
            st_new_game(&g, mode, a3_hash(g.seed) & 0x7FFFFFFF, level, g.last_col);
            bot_pieces = -1;
        }
    }
    printf("%s %s seed %lu level %d, %d ticks: games %d score %ld rings %d level %d pieces %d events %d/%08lX hash %08lX\n",
           bot ? "bot" : "demo", st_mode_names[mode], (unsigned long)seed, level, ticks, games, (long)g.score,
           g.lines, g.level, g.pieces, nev, (unsigned long)evh, (unsigned long)state_hash(&g));
}

int main(void)
{
    int v;
    for (v = 0; v < (int)(sizeof(vectors) / sizeof(vectors[0])); v++) {
        script(vectors[v].mode, (uint32_t)vectors[v].seed);
        printf("  browser: pieces %d score %ld board %lu queue %d %d %d %d %d hold %d\n", vectors[v].pieces,
               vectors[v].score, vectors[v].board, vectors[v].queue[0], vectors[v].queue[1], vectors[v].queue[2],
               vectors[v].queue[3], vectors[v].queue[4], vectors[v].hold);
    }
    play(0, MODE_MARATHON, 778, 1, 6000);
    play(1, MODE_MARATHON, 1, 1, 20000);
    play(1, MODE_RISING, 7, 3, 12000);
    play(1, MODE_DIG, 42, 1, 8000);
    play(1, MODE_MARATHON, 2026, 9, 8000);
    return 0;
}
