/* bbmod.c - ProTracker modules for Boing BASIC: loading, saving, editing and playing.
 *
 * Derived from modplay.c of amiga_mcp's examples/amiga3d (MIT, Copyright (c) 2026 Chris
 * Collins <chris@hitorro.com>): the same tick/row engine and period arithmetic, here with the
 * state in a struct instead of globals, 4/6/8 channels, the rest of the effects (tremolo, pan,
 * pattern loop, waveforms, finetune), song-end detection, live notes, and scope/VU data.
 * Integer arithmetic only, so every platform renders the same samples.
 */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "bbaudio.h"

#define PAULA_CLOCK 3546895u        /* PAL */

static const uint8_t vib_sine[32] = {
    0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
    255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24
};

/* 2^(-n/12) and 2^(-ft/96), 16.16 */
static const int32_t semitone_mul[16] = {
    65536, 61858, 58386, 55109, 52016, 49097, 46341, 43740,
    41285, 38968, 36781, 34716, 32768, 30929, 29193, 27554
};
static const int32_t finetune_mul[16] = {
    65536, 65065, 64596, 64132, 63670, 63212, 62757, 62306,   /* 0..7 */
    69433, 68933, 68438, 67945, 67456, 66971, 66489, 66010    /* -8..-1 */
};

static const int16_t periods[BBA_NOTES] = {
    856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
    428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
    214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113
};

int bba_note_period(int note, int finetune)
{
    if (note < 1 || note > BBA_NOTES) return 0;
    return (int)(((int64_t)periods[note - 1] * finetune_mul[finetune & 15]) >> 16);
}

int bba_period_note(int period)
{
    int i, best = 0, bd = 1 << 30;
    if (period <= 0) return 0;
    for (i = 0; i < BBA_NOTES; i++) {
        int d = period > periods[i] ? period - periods[i] : periods[i] - period;
        if (d < bd) { bd = d; best = i + 1; }
    }
    return best;
}

/* ---------------------------------------------------------------- songs */

bba_song *bba_song_new(int nch)
{
    bba_song *s;
    if (nch != 4 && nch != 6 && nch != 8) return NULL;
    s = (bba_song *)calloc(1, sizeof *s);
    if (!s) return NULL;
    s->nch = nch;
    s->song_len = 1;
    s->npat = 1;
    s->pat = (uint8_t *)calloc(1, (size_t)BBA_ROWS * nch * 4);
    if (!s->pat) { free(s); return NULL; }
    return s;
}

void bba_song_free(bba_song *s)
{
    int i;
    if (!s) return;
    for (i = 0; i < 31; i++) free(s->smp[i].data);
    free(s->pat);
    free(s);
}

static int tag_channels(const uint8_t *t)
{
    if (!memcmp(t, "M.K.", 4) || !memcmp(t, "M!K!", 4) || !memcmp(t, "4CHN", 4) || !memcmp(t, "FLT4", 4))
        return 4;
    if (!memcmp(t, "6CHN", 4)) return 6;
    if (!memcmp(t, "8CHN", 4) || !memcmp(t, "OCTA", 4) || !memcmp(t, "CD81", 4)) return 8;
    return 0;
}

static void copy_name(char *dst, const uint8_t *src, int n)
{
    int i;
    for (i = 0; i < n && src[i]; i++) dst[i] = (char)(src[i] >= 32 && src[i] < 127 ? src[i] : ' ');
    dst[i] = 0;
}

bba_song *bba_song_load(const uint8_t *d, long len)
{
    bba_song *s;
    int i, npat = 0, nch;
    long off, psize;
    if (len < 1084 || !(nch = tag_channels(d + 1080))) return NULL;
    if (d[950] < 1 || d[950] > 128) return NULL;
    s = (bba_song *)calloc(1, sizeof *s);
    if (!s) return NULL;
    s->nch = nch;
    copy_name(s->name, d, 20);
    s->song_len = d[950];
    s->restart = d[951] < s->song_len ? d[951] : 0;
    memcpy(s->order, d + 952, 128);
    for (i = 0; i < 128; i++) {
        if (s->order[i] >= BBA_MAXPAT) s->order[i] = 0;
        if (s->order[i] + 1 > npat) npat = s->order[i] + 1;
    }
    psize = (long)BBA_ROWS * nch * 4;
    off = 1084 + npat * psize;
    if (off > len) { free(s); return NULL; }
    s->npat = npat;
    s->pat = (uint8_t *)malloc((size_t)(npat * psize));
    if (!s->pat) { free(s); return NULL; }
    memcpy(s->pat, d + 1084, (size_t)(npat * psize));
    for (i = 0; i < 31; i++) {
        const uint8_t *h = d + 20 + i * 30;
        bba_sample *sm = &s->smp[i];
        uint32_t l = (uint32_t)((h[22] << 8) | h[23]) * 2, have;
        copy_name(sm->name, h, 22);
        sm->finetune = h[24] & 15;
        sm->vol = h[25] > 64 ? 64 : h[25];
        sm->loop_start = (uint32_t)((h[26] << 8) | h[27]) * 2;
        sm->loop_len = (uint32_t)((h[28] << 8) | h[29]) * 2;
        have = off >= len ? 0 : (uint32_t)(len - off) < l ? (uint32_t)(len - off) : l;
        if (l) {
            sm->data = (int8_t *)calloc(1, l);
            if (!sm->data) { bba_song_free(s); return NULL; }
            if (have) memcpy(sm->data, d + off, have);
            sm->len = l;
        }
        off += l;
        if (sm->loop_len <= 2 || sm->loop_start >= sm->len) sm->loop_len = sm->loop_len > 2 ? 0 : sm->loop_len;
        else if (sm->loop_start + sm->loop_len > sm->len) sm->loop_len = sm->len - sm->loop_start;
        if (sm->loop_start >= sm->len) sm->loop_start = 0;
    }
    return s;
}

static void put16(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }

uint8_t *bba_song_save(const bba_song *s, long *len)
{
    int i, npat = 0;
    long psize = (long)BBA_ROWS * s->nch * 4, total, off;
    uint8_t *d;
    for (i = 0; i < 128; i++) if (s->order[i] + 1 > npat) npat = s->order[i] + 1;
    if (npat > s->npat) npat = s->npat;
    total = 1084 + npat * psize;
    for (i = 0; i < 31; i++) total += (long)(s->smp[i].len & ~1u);
    d = (uint8_t *)calloc(1, (size_t)total);
    if (!d) return NULL;
    memcpy(d, s->name, strlen(s->name));
    for (i = 0; i < 31; i++) {
        const bba_sample *sm = &s->smp[i];
        uint8_t *h = d + 20 + i * 30;
        uint32_t ll = sm->loop_len > 2 ? sm->loop_len : 2;
        memcpy(h, sm->name, strlen(sm->name));
        put16(h + 22, sm->len / 2);
        h[24] = (uint8_t)(sm->finetune & 15);
        h[25] = (uint8_t)sm->vol;
        put16(h + 26, sm->loop_len > 2 ? sm->loop_start / 2 : 0);
        put16(h + 28, ll / 2);
    }
    d[950] = (uint8_t)s->song_len;
    d[951] = 127;
    memcpy(d + 952, s->order, 128);
    memcpy(d + 1080, s->nch == 4 ? "M.K." : s->nch == 6 ? "6CHN" : "8CHN", 4);
    memcpy(d + 1084, s->pat, (size_t)(npat * psize));
    off = 1084 + npat * psize;
    for (i = 0; i < 31; i++) {
        uint32_t l = s->smp[i].len & ~1u;
        if (l) memcpy(d + off, s->smp[i].data, l);
        off += l;
    }
    *len = total;
    return d;
}

int bba_song_add_pattern(bba_song *s)
{
    size_t psize = (size_t)BBA_ROWS * s->nch * 4;
    uint8_t *p;
    if (s->npat >= BBA_MAXPAT) return -1;
    p = (uint8_t *)realloc(s->pat, psize * (size_t)(s->npat + 1));
    if (!p) return -1;
    memset(p + psize * (size_t)s->npat, 0, psize);
    s->pat = p;
    return s->npat++;
}

uint8_t *bba_cell(bba_song *s, int pat, int row, int ch)
{
    return s->pat + (((size_t)pat * BBA_ROWS + (size_t)row) * (size_t)s->nch + (size_t)ch) * 4;
}

int bba_sample_resize(bba_sample *sm, uint32_t len)
{
    int8_t *d;
    len &= ~1u;
    if (len == 0) { free(sm->data); sm->data = NULL; sm->len = 0; sm->loop_start = sm->loop_len = 0; return 1; }
    d = (int8_t *)realloc(sm->data, len);
    if (!d) return 0;
    if (len > sm->len) memset(d + sm->len, 0, len - sm->len);
    sm->data = d;
    sm->len = len;
    if (sm->loop_start >= len) { sm->loop_start = 0; sm->loop_len = 0; }
    else if (sm->loop_start + sm->loop_len > len) sm->loop_len = len - sm->loop_start;
    return 1;
}

/* ---------------------------------------------------------------- the player */

static void set_step(bba_player *p, bba_chan *c, int period)
{
    uint32_t q;
    if (period <= 0) { c->step = 0; return; }
    q = (uint32_t)(((int64_t)period * finetune_mul[c->finetune & 15]) >> 16);
    if (q < 1) q = 1;
    c->step = (uint32_t)(((uint64_t)PAULA_CLOCK << 16) / ((uint64_t)q * (uint64_t)p->rate));
}

void bba_player_init(bba_player *p, int rate)
{
    int i;
    memset(p, 0, sizeof *p);
    p->rate = rate;
    p->loop = 1;
    p->speed = 6;
    p->bpm = 125;
    p->jump_pos = p->break_row = -1;
    for (i = 0; i < BBA_MAXCH; i++) p->ch[i].pan = -1;
}

static void reset_channels(bba_player *p)
{
    int i;
    for (i = 0; i < BBA_MAXCH; i++) {
        bba_chan *c = &p->ch[i];
        int muted = c->muted;
        uint32_t sp = c->scope_pos;
        memset(c, 0, offsetof(bba_chan, scope));
        c->muted = muted;
        c->scope_pos = sp;
        c->pan = -1;
    }
}

void bba_play(bba_player *p, bba_song *s, int pos, int row)
{
    p->song = s;
    reset_channels(p);
    p->speed = 6;
    p->bpm = 125;
    p->tick = 0;
    p->pos = pos >= 0 && pos < s->song_len ? pos : 0;
    p->row = row >= 0 && row < BBA_ROWS ? row : 0;
    p->pat_delay = p->delay_rows = 0;
    p->jump_pos = p->break_row = -1;
    p->tick_left = 0;
    p->ended = 0;
    p->playing = 1;
    p->paused = 0;
}

void bba_stop(bba_player *p)
{
    int i;
    p->playing = 0;
    p->paused = 0;
    for (i = 0; i < BBA_MAXCH; i++) p->ch[i].active = 0;
}

void bba_jump(bba_player *p, int pos, int row)
{
    if (!p->song) return;
    p->jump_pos = pos >= 0 && pos < p->song->song_len ? pos : 0;
    p->break_row = row >= 0 && row < BBA_ROWS ? row : 0;
    p->pat_delay = p->delay_rows = 0;
    if (!p->playing) { p->pos = p->jump_pos; p->row = p->break_row; p->jump_pos = p->break_row = -1; }
}

void bba_note_off(bba_player *p, int ch)
{
    if (ch >= 0 && ch < BBA_MAXCH) p->ch[ch].active = 0;
}

void bba_song_gone(bba_player *p, bba_song *s)
{
    if (p->song != s) return;
    bba_stop(p);
    p->song = NULL;
}

void bba_sample_changed(bba_player *p, int smp)
{
    int i;
    for (i = 0; i < BBA_MAXCH; i++)
        if (p->ch[i].smp == smp) p->ch[i].active = 0;
}

static void trigger(bba_player *p, bba_chan *c, int period)
{
    const bba_sample *sm;
    if (!c->smp || !p->song) return;
    sm = &p->song->smp[c->smp - 1];
    c->period = c->base = period;
    c->pos = c->frac = 0;
    if (!(c->vib_wave & 4)) c->vib_pos = 0;
    if (!(c->trem_wave & 4)) c->trem_pos = 0;
    c->active = sm->len > 2 && sm->data;
    c->note = bba_period_note(period);
    set_step(p, c, period);
}

static void vol_slide(bba_chan *c)
{
    if (c->prm >> 4) c->volume += c->prm >> 4;
    else c->volume -= c->prm & 15;
    if (c->volume > 64) c->volume = 64;
    if (c->volume < 0) c->volume = 0;
}

static void tone_porta(bba_player *p, bba_chan *c)
{
    if (!c->target) return;
    if (c->base < c->target) { c->base += c->porta; if (c->base > c->target) c->base = c->target; }
    else if (c->base > c->target) { c->base -= c->porta; if (c->base < c->target) c->base = c->target; }
    c->period = c->base;
    set_step(p, c, c->period);
}

static int wave(int w, int pos)
{
    int v;
    switch (w & 3) {
    case 1: v = (pos & 31) * 8; if (pos & 32) v = 255 - v; break;    /* ramp */
    case 2: v = 255; break;                                         /* square */
    default: v = vib_sine[pos & 31]; break;
    }
    return (pos & 32) ? -v : v;
}

static void vibrato(bba_player *p, bba_chan *c)
{
    int d = (wave(c->vib_wave, c->vib_pos) * (c->vib_prm & 15)) / 128;
    set_step(p, c, c->base + d);
    c->vib_pos = (c->vib_pos + (c->vib_prm >> 4)) & 63;
}

static void tremolo(bba_chan *c)
{
    int v = c->volume + (wave(c->trem_wave, c->trem_pos) * (c->trem_prm & 15)) / 64;
    c->outvol = v < 0 ? 0 : v > 64 ? 64 : v;
    c->trem_pos = (c->trem_pos + (c->trem_prm >> 4)) & 63;
}

static void clamp_base(bba_player *p, bba_chan *c)
{
    if (c->base < 113) c->base = 113;
    if (c->base > 856) c->base = 856;
    c->period = c->base;
    set_step(p, c, c->period);
}

/* tick 0 of a row on one channel; from_song: patterns can jump/break/loop */
static void do_cell(bba_player *p, int chn, const uint8_t *r, int from_song)
{
    bba_chan *c = &p->ch[chn];
    int s = (r[0] & 0xF0) | (r[2] >> 4);
    int period = ((r[0] & 0x0F) << 8) | r[1];
    int eff = r[2] & 15, prm = r[3], ex = prm >> 4, x = prm & 15;
    const bba_song *song = p->song;

    c->eff = eff;
    c->prm = prm;
    if (s >= 1 && s <= 31 && song) {
        c->smp = s;
        c->volume = song->smp[s - 1].vol;
        c->finetune = song->smp[s - 1].finetune;
    }
    c->delay_period = 0;
    if (period) {
        if (eff == 3 || eff == 5) c->target = period;
        else if (eff == 14 && ex == 13 && x) c->delay_period = period;
        else {
            if (eff == 14 && ex == 5) c->finetune = x;
            trigger(p, c, period);
            if (eff == 9 && c->active) {
                if (prm) c->offset = prm << 8;
                c->pos = (uint32_t)c->offset;
                if (c->pos >= song->smp[c->smp - 1].len) c->active = 0;
            }
        }
    } else if (c->period) {
        set_step(p, c, c->period);                      /* undo vibrato/arpeggio offsets */
    }
    switch (eff) {
    case 3: if (prm) c->porta = prm; break;
    case 4:
        if (x) c->vib_prm = (c->vib_prm & 0xF0) | x;
        if (ex) c->vib_prm = (c->vib_prm & 0x0F) | (prm & 0xF0);
        break;
    case 7:
        if (x) c->trem_prm = (c->trem_prm & 0xF0) | x;
        if (ex) c->trem_prm = (c->trem_prm & 0x0F) | (prm & 0xF0);
        break;
    case 8: c->pan = prm; break;
    case 11: if (from_song) { p->jump_pos = prm; } break;
    case 12: c->volume = prm > 64 ? 64 : prm; break;
    case 13:
        if (from_song) { p->break_row = ex * 10 + x; if (p->break_row > 63) p->break_row = 0; }
        break;
    case 14:
        switch (ex) {
        case 1: c->base -= x; clamp_base(p, c); break;
        case 2: c->base += x; clamp_base(p, c); break;
        case 4: c->vib_wave = x & 7; break;
        case 5: c->finetune = x; break;
        case 6:
            if (!from_song) break;
            if (x == 0) c->loop_row = p->row;
            else {
                if (c->loop_count == 0) c->loop_count = x;
                else c->loop_count--;
                if (c->loop_count) p->break_row = 1000 + c->loop_row;   /* in-pattern loop */
            }
            break;
        case 7: c->trem_wave = x & 7; break;
        case 10: c->volume += x; if (c->volume > 64) c->volume = 64; break;
        case 11: c->volume -= x; if (c->volume < 0) c->volume = 0; break;
        case 12: if (!x) c->volume = 0; break;
        case 14: if (from_song) p->pat_delay = x; break;
        }
        break;
    case 15:
        if (prm == 0) break;
        if (prm < 32) p->speed = prm; else p->bpm = prm;
        break;
    }
    c->outvol = c->volume;
}

static void new_row(bba_player *p)
{
    bba_song *s = p->song;
    int i, pat = s->order[p->pos];
    if (pat >= s->npat) pat = 0;
    for (i = 0; i < s->nch; i++) do_cell(p, i, bba_cell(s, pat, p->row, i), 1);
}

static void effects(bba_player *p)
{
    int i, n = p->song ? p->song->nch : BBA_MAXCH;
    for (i = 0; i < n; i++) {
        bba_chan *c = &p->ch[i];
        int ex = c->prm >> 4, x = c->prm & 15;
        switch (c->eff) {
        case 0:
            if (c->prm) {
                int k = p->tick % 3 == 1 ? ex : p->tick % 3 == 2 ? x : 0;
                set_step(p, c, (int)(((int64_t)c->base * semitone_mul[k]) >> 16));
            }
            break;
        case 1: c->base -= c->prm; clamp_base(p, c); break;
        case 2: c->base += c->prm; clamp_base(p, c); break;
        case 3: tone_porta(p, c); break;
        case 4: vibrato(p, c); break;
        case 5: tone_porta(p, c); vol_slide(c); break;
        case 6: vibrato(p, c); vol_slide(c); break;
        case 7: tremolo(c); continue;
        case 10: vol_slide(c); break;
        case 14:
            if (ex == 9 && x && p->tick % x == 0 && c->smp) {
                const bba_sample *sm = p->song ? &p->song->smp[c->smp - 1] : NULL;
                c->pos = c->frac = 0;
                c->active = sm && sm->len > 2 && sm->data;
            } else if (ex == 12 && p->tick == x) c->volume = 0;
            else if (ex == 13 && p->tick == x && c->delay_period) {
                trigger(p, c, c->delay_period);
                c->delay_period = 0;
            }
            break;
        }
        c->outvol = c->volume;
    }
}

static void song_end(bba_player *p)
{
    p->ended++;
    if (!p->loop) bba_stop(p);
}

static void next_row(bba_player *p)
{
    bba_song *s = p->song;
    /* EEx: the row lasts x more rows, without its notes being read again */
    if (p->pat_delay) {
        p->delay_rows = p->pat_delay;
        p->pat_delay = 0;
        return;
    }
    if (p->delay_rows > 0 && --p->delay_rows > 0) return;
    if (p->break_row >= 1000) {                 /* E6x: back to the loop row, same position */
        p->row = p->break_row - 1000;
        p->break_row = -1;
        if (p->jump_pos >= 0) p->jump_pos = -1;
        return;
    }
    if (p->jump_pos >= 0 || p->break_row >= 0) {
        int np = p->jump_pos >= 0 ? p->jump_pos : p->pos + 1;
        int backward = p->jump_pos >= 0 && p->jump_pos <= p->pos;
        p->row = p->break_row >= 0 ? p->break_row : 0;
        p->jump_pos = p->break_row = -1;
        if (np >= s->song_len) { np = s->restart; backward = 1; }
        p->pos = np;
        if (backward) song_end(p);
    } else if (++p->row >= BBA_ROWS) {
        p->row = 0;
        if (++p->pos >= s->song_len) {
            p->pos = s->restart < s->song_len ? s->restart : 0;
            song_end(p);
        }
    }
}

static void do_tick(bba_player *p)
{
    if (p->playing && p->song) {
        if (p->tick == 0 && p->delay_rows == 0) new_row(p);
        else effects(p);
        if (++p->tick >= p->speed) {
            p->tick = 0;
            next_row(p);
        }
    } else {                                    /* live notes: effects run, no rows */
        if (p->tick != 0) effects(p);
        if (++p->tick >= p->speed) p->tick = 0;
    }
}

void bba_play_cell(bba_player *p, int ch, const uint8_t *cell)
{
    if (ch < 0 || ch >= BBA_MAXCH) return;
    do_cell(p, ch, cell, 0);
}

void bba_play_row(bba_player *p, int pat, int row)
{
    int i;
    bba_song *s = p->song;
    if (!s || pat < 0 || pat >= s->npat || row < 0 || row >= BBA_ROWS) return;
    for (i = 0; i < s->nch; i++) do_cell(p, i, bba_cell(s, pat, row, i), 0);
    p->tick = 1 % p->speed;
}

/* the Amiga's LRRL panning, with a quarter of each side in the other (headphones);
 * gains in 1/256 */
static void chan_gains(const bba_chan *c, int i, int *gl, int *gr)
{
    if (c->pan < 0) {
        int left = (i & 3) == 0 || (i & 3) == 3;
        *gl = left ? 288 : 96;
        *gr = left ? 96 : 288;
    } else {
        *gl = (255 - c->pan) * 384 / 255;
        *gr = c->pan * 384 / 255;
    }
}

static void mix_chan(bba_player *p, bba_chan *c, int i, int32_t *mix, int n)
{
    const bba_sample *sm;
    uint32_t end, pos = c->pos, frac = c->frac, step = c->step, sp = c->scope_pos;
    int gl, gr, vol = c->outvol, peak = c->peak, f;
    if (!c->active || !p->song || !c->smp) {
        for (f = 0; f < n; f++) c->scope[(sp + f) & (BBA_SCOPE - 1)] = 0;
        c->scope_pos = sp + n;
        return;
    }
    sm = &p->song->smp[c->smp - 1];
    if (!sm->data) { c->active = 0; return; }
    end = sm->loop_len > 2 ? sm->loop_start + sm->loop_len : sm->len;
    if (end > sm->len) end = sm->len;
    chan_gains(c, i, &gl, &gr);
    if (c->muted) gl = gr = 0;
    for (f = 0; f < n; f++) {
        int v;
        if (pos >= end) {
            if (sm->loop_len > 2 && end > sm->loop_start) pos = sm->loop_start + (pos - end) % (end - sm->loop_start);
            else { c->active = 0; for (; f < n; f++) c->scope[(sp + f) & (BBA_SCOPE - 1)] = 0; break; }
        }
        v = sm->data[pos] * vol;
        c->scope[(sp + f) & (BBA_SCOPE - 1)] = (int8_t)(v >> 6);
        if (v < 0 ? -v > peak : v > peak) peak = v < 0 ? -v : v;
        mix[2 * f] += v * gl;
        mix[2 * f + 1] += v * gr;
        frac += step;
        pos += frac >> 16;
        frac &= 0xFFFF;
    }
    c->pos = pos;
    c->frac = frac;
    c->scope_pos = sp + n;
    c->peak = c->muted ? 0 : peak;
}

void bba_player_render(bba_player *p, int32_t *mix, int frames)
{
    int i, nch = p->song ? p->song->nch : 4;
    for (i = 0; i < BBA_MAXCH; i++) p->ch[i].peak = 0;
    if (p->paused) {
        for (i = 0; i < BBA_MAXCH; i++) p->ch[i].vu = 0;
        return;
    }
    while (frames > 0) {
        int n;
        if (p->tick_left <= 0) {
            do_tick(p);
            p->tick_left = p->rate * 5 / (p->bpm * 2);   /* 2.5 / bpm seconds */
            if (p->tick_left < 1) p->tick_left = 1;
            nch = p->song ? p->song->nch : 4;
        }
        n = frames < p->tick_left ? frames : p->tick_left;
        for (i = 0; i < nch; i++) mix_chan(p, &p->ch[i], i, mix, n);
        mix += 2 * n;
        frames -= n;
        p->tick_left -= n;
    }
    for (i = 0; i < BBA_MAXCH; i++) p->ch[i].vu = p->ch[i].peak / 128;   /* 8128 -> 63 */
}
