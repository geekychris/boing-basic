/* Lander 3D: the C original's flights, for checking the BASIC port (LdCore.bas).
 * See trace.sh (needs amiga_mcp beside boing_basic, or AMIGA_MCP=...). */
#include <stdio.h>
#include "a3d.h"
#include "ld.h"

static Level L;

/* amiga3d's a3_tone / a3_noise (a3d_sound.c: Amiga headers, so copied here) and
 * game.c's effects, for a checksum of the samples */
#define FX_RATE (3546895L / 300)
static uint32_t nrng = 4242;
static int noise8(void) { nrng = nrng * 1103515245UL + 12345UL; return (int)((nrng >> 16) & 255) - 128; }
static void tone(int8_t *d, int n, int f0, int f1, int amp, int fade)
{
    uint32_t ph = 0; int i;
    if (fade < 1) fade = 1;
    for (i = 0; i < n; i++) {
        int f = f0 + ((f1 - f0) * i) / n, t, a = amp;
        ph += (uint32_t)((f * 65536L) / FX_RATE);
        t = (int)((ph >> 8) & 255);
        t = t < 128 ? t * 2 - 128 : 383 - t * 2;
        if (i > n - fade) a = (amp * (n - i)) / fade;
        d[i] = (int8_t)((t * a) / 128);
    }
}
static void noise(int8_t *d, int n, int amp, int lp, int attack)
{
    int i, acc = 0;
    if (lp < 1) lp = 1;
    for (i = 0; i < n; i++) {
        int env = i < attack ? (amp * i) / attack : (amp * (n - i)) / (n - attack);
        acc += noise8() - acc / lp;
        d[i] = (int8_t)(((acc / lp) * env) / 128);
    }
}
static uint32_t fnv(uint32_t h, int32_t v);
static uint32_t sounds_hash(void)
{
    static int8_t d[5000];
    uint32_t h = 0x811C9DC5u; int k;
#define SUM(n) for (k = 0; k < (n); k++) h = fnv(h, d[k])
    noise(d, 1200, 70, 10, 60); SUM(1200);
    noise(d, 300, 50, 1, 10); SUM(300);
    tone(d, 1300, 523, 523, 90, 100); tone(d + 1300, 1300, 659, 659, 90, 100); tone(d + 2600, 1400, 784, 784, 100, 1000); SUM(4000);
    noise(d, 5000, 127, 3, 20); SUM(5000);
    tone(d, 1200, 880, 880, 90, 60); tone(d + 1200, 1200, 660, 660, 90, 300); SUM(2400);
    tone(d, 300, 1400, 1400, 70, 150); SUM(300);
    return h;
}

static uint32_t fnv(uint32_t h, int32_t v) { return (h ^ (uint32_t)v) * 16777619u; }

uint32_t terrain_hash(const Terrain *T)
{
    uint32_t h = 0x811C9DC5u;
    int k;
    for (k = 0; k < T->n * T->n; k++) h = fnv(h, T->h[k]);
    for (k = 0; k < 3; k++) {
        h = fnv(h, T->pads[k].x); h = fnv(h, T->pads[k].z); h = fnv(h, T->pads[k].r);
        h = fnv(h, T->pads[k].y); h = fnv(h, T->pads[k].mult);
    }
    return h;
}

uint32_t state_hash(const Level *L)
{
    uint32_t h = 0x811C9DC5u;
    int d;
    for (d = 0; d < 3; d++) { h = fnv(h, L->c.p[d]); h = fnv(h, L->c.v[d]); }
    h = fnv(h, L->c.pitch); h = fnv(h, L->c.roll); h = fnv(h, L->c.wp); h = fnv(h, L->c.wr);
    h = fnv(h, L->c.throttle); h = fnv(h, L->c.rcs[0]); h = fnv(h, L->c.rcs[1]);
    h = fnv(h, L->fuel); h = fnv(h, L->fuel_max); h = fnv(h, L->t); h = fnv(h, L->outcome);
    h = fnv(h, L->result.score); h = fnv(h, L->result.soft); h = fnv(h, L->result.fuel_bonus);
    h = fnv(h, L->result.pad); h = fnv(h, L->ap_down); h = fnv(h, L->ap_target);
    h = fnv(h, L->wind[0]); h = fnv(h, L->wind[1]); h = fnv(h, L->nev);
    return h;
}

static void show_level(const Level *L)
{
    int k;
    printf("level w%d l%d seed %lu terrain %08lX start %ld %ld %ld v %ld %ld %ld fuel %ld\n", L->world, L->level,
           (unsigned long)L->seed, (unsigned long)terrain_hash(&L->T), (long)L->c.p[0], (long)L->c.p[1], (long)L->c.p[2],
           (long)L->c.v[0], (long)L->c.v[1], (long)L->c.v[2], (long)L->fuel);
    for (k = 0; k < 3; k++)
        printf(" pad%d %ld %ld r %ld y %ld x%d\n", k, (long)L->T.pads[k].x, (long)L->T.pads[k].z, (long)L->T.pads[k].r,
               (long)L->T.pads[k].y, L->T.pads[k].mult);
}

/* mode 0 autopilot, 1 scripted pilot (assist), 2 scripted pilot (no assist) */
static void fly(int world, int lv, uint32_t seed, int mode, int max)
{
    LdInput in;
    int t, e, nev = 0;
    ld_new_level(&L, world, lv, seed, 0);
    if (mode == 2) L.assist = 0;
    show_level(&L);
    for (t = 0; t < max && !L.outcome; t++) {
        if (mode == 0) ld_autopilot(&L, &in);
        else {
            uint32_t r = a3_hash((uint32_t)(t / 37) * 2654435761u + seed);
            in.throttle = (fix)((r & 15) * 4369);
            in.pitch = (r & 0x30) == 0x10 ? FONE : (r & 0x30) == 0x20 ? -FONE : 0;
            in.roll = (r & 0xC0) == 0x40 ? FONE : (r & 0xC0) == 0x80 ? -FONE : 0;
            if (L.c.v[1] < FX(-6)) in.throttle = FONE;
        }
        ld_step(&L, &in);
        while ((e = ld_pop_event(&L)) != LDE_NONE) nev = nev * 7 + e;
        if (t % 1000 == 999) printf(" t%d hash %08lX\n", t + 1, (unsigned long)state_hash(&L));
    }
    printf("end t%d outcome %d score %ld soft %ld fb %ld vs %ld hs %ld tilt %ld ev %d agl %ld tiltnow %ld near %d hash %08lX\n",
           t, L.outcome, (long)L.result.score, (long)L.result.soft, (long)L.result.fuel_bonus, (long)L.result.vs,
           (long)L.result.hs, (long)L.result.tilt, nev, (long)ld_agl(&L), (long)ld_tilt(&L.c), ld_nearest_pad(&L, 0),
           (unsigned long)state_hash(&L));
}

static void probe(int world, int lv, uint32_t seed)
{
    ld_new_level(&L, world, lv, seed, 1);
    printf("probe w%d l%d seed %lu used %ld outcome %d fuel %ld max %ld\n", world, lv, (unsigned long)seed,
           (long)L.probe_used, L.probe_outcome, (long)L.fuel, (long)L.fuel_max);
}

int main(void)
{
    int w, lv;
    static const int lvs[3] = { 1, 3, 7 };
    LevelParams P;
    for (w = 0; w < 3; w++)
        for (lv = 1; lv <= 10; lv += 3) {
            ld_level_params(w, lv, &P);
            printf("params w%d l%d %ld %ld %ld %ld %ld %ld\n", w, lv, (long)P.fuel, (long)P.start_alt, (long)P.start_h,
                   (long)P.start_dist, (long)P.pad_scale, (long)P.wind);
        }
    fly(0, 1, 1018, 0, 40000);
    for (w = 0; w < 3; w++)
        for (lv = 0; lv < 3; lv++) fly(w, lvs[lv], 1000 + w * 10 + lvs[lv], 0, 40000);
    fly(0, 2, 2026, 1, 40000);
    fly(1, 1, 2027, 1, 40000);
    fly(2, 1, 2028, 2, 40000);
    fly(1, 5, 31337, 2, 40000);
    probe(0, 1, 2026);
    probe(1, 4, 77);
    probe(2, 2, 5);
    printf("sounds %08lX\n", (unsigned long)sounds_hash());
    return 0;
}
