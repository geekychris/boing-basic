/* bbmix.c - the mixer: the music (bbmod.c) plus the sound-effect voices, to signed 16-bit
 * stereo. Integer arithmetic only (the same samples on every platform). The voice code
 * follows sound_ahi.c's idea from amiga_mcp's amiga3d (MIT, Chris Collins): effects on voices
 * of their own, a new one never cutting one of higher priority.
 */
#include <stdlib.h>
#include <string.h>
#include "bbaudio.h"

void bba_mixer_init(bba_mixer *m, int rate)
{
    memset(m, 0, sizeof *m);
    bba_player_init(&m->music, rate);
    m->rate = rate;
    m->master = 64;
    m->music_vol = 48;
    m->sound_vol = 64;
    m->music_on = m->sound_on = 1;
    m->next_voice_id = 1;
    m->hash = 2166136261u;
}

void bba_mixer_free(bba_mixer *m)
{
    free(m->mixbuf);
    m->mixbuf = NULL;
    m->mixcap = 0;
}

static uint32_t voice_step(int rate, int out)
{
    if (rate < 1) rate = 1;
    if (rate > 200000) rate = 200000;
    return (uint32_t)(((uint64_t)rate << 16) / (uint64_t)out);
}

uint32_t bba_voice_start(bba_mixer *m, bba_sound *s, int vol, int pan, int rate, int loop, int pri)
{
    int i, pick = -1;
    bba_voice *v;
    if (!s || !s->len) return 0;
    for (i = 0; i < BBA_VOICES && pick < 0; i++) if (!m->voice[i].snd) pick = i;
    if (pick < 0) {         /* all busy: the lowest priority (oldest first), if not above ours */
        for (i = 0; i < BBA_VOICES; i++)
            if (m->voice[i].pri <= pri && (pick < 0 || m->voice[i].pri < m->voice[pick].pri ||
                (m->voice[i].pri == m->voice[pick].pri && m->voice[i].id < m->voice[pick].id)))
                pick = i;
        if (pick < 0) return 0;
    }
    v = &m->voice[pick];
    v->snd = s;
    v->id = m->next_voice_id++;
    if (!m->next_voice_id) m->next_voice_id = 1;
    v->pos = v->frac = 0;
    v->vol = vol < 0 ? 0 : vol > 64 ? 64 : vol;
    v->pan = pan < -64 ? -64 : pan > 64 ? 64 : pan;
    v->rate = rate > 0 ? rate : s->rate;
    v->step = voice_step(v->rate, m->rate);
    v->loop = loop < 0 ? s->loop : loop != 0;
    v->pri = pri;
    return v->id;
}

bba_voice *bba_voice_find(bba_mixer *m, uint32_t id)
{
    int i;
    if (!id) return NULL;
    for (i = 0; i < BBA_VOICES; i++)
        if (m->voice[i].snd && m->voice[i].id == id) return &m->voice[i];
    return NULL;
}

void bba_voice_set_rate(bba_mixer *m, bba_voice *v, int rate)
{
    v->rate = rate;
    v->step = voice_step(rate, m->rate);
}

void bba_sound_gone(bba_mixer *m, bba_sound *s)
{
    int i;
    for (i = 0; i < BBA_VOICES; i++) if (m->voice[i].snd == s) m->voice[i].snd = NULL;
}

static void mix_voice(bba_mixer *m, bba_voice *v, int32_t *mix, int n)
{
    bba_sound *s = v->snd;
    uint32_t pos = v->pos, frac = v->frac, step = v->step, end, ls;
    int gl, gr, f;
    /* constant-power-ish balance: centre = full on both sides */
    gl = v->pan <= 0 ? 256 : (64 - v->pan) * 4;
    gr = v->pan >= 0 ? 256 : (64 + v->pan) * 4;
    gl = gl * v->vol * m->sound_vol / 4096;          /* 1/256 units, with both volumes */
    gr = gr * v->vol * m->sound_vol / 4096;
    if (s->loop_len > 0 && s->loop_start < s->len) {
        ls = s->loop_start;
        end = s->loop_start + s->loop_len > s->len ? s->len : s->loop_start + s->loop_len;
    } else {
        ls = 0;
        end = s->len;
    }
    for (f = 0; f < n; f++) {
        int x;
        if (pos >= (v->loop ? end : s->len)) {
            if (v->loop && end > ls) pos = ls + (pos - end) % (end - ls);
            else { v->snd = NULL; break; }
        }
        x = s->bits == 8 ? ((const int8_t *)s->data)[pos] * 256 : ((const int16_t *)s->data)[pos];
        mix[2 * f] += (x * gl) >> 8;
        mix[2 * f + 1] += (x * gr) >> 8;
        frac += step;
        pos += frac >> 16;
        frac &= 0xFFFF;
    }
    v->pos = pos;
    v->frac = frac;
}

void bba_mix(bba_mixer *m, int16_t *out, int frames)
{
    int i, k;
    while (frames > 0) {
        int n = frames > 4096 ? 4096 : frames;
        int32_t *mix;
        int mv = m->music_on ? m->music_vol : 0;
        if (m->mixcap < n) {
            int32_t *b = (int32_t *)realloc(m->mixbuf, (size_t)n * 2 * sizeof(int32_t));
            if (!b) { memset(out, 0, (size_t)frames * 4); return; }
            m->mixbuf = b;
            m->mixcap = n;
        }
        mix = m->mixbuf;
        memset(mix, 0, (size_t)n * 2 * sizeof(int32_t));
        bba_player_render(&m->music, mix, n);
        for (k = 0; k < 2 * n; k++) mix[k] = ((mix[k] >> 8) * mv) >> 6;
        for (i = 0; i < BBA_VOICES; i++) if (m->voice[i].snd) mix_voice(m, &m->voice[i], mix, n);
        for (k = 0; k < 2 * n; k++) {
            int32_t x = (mix[k] * m->master) >> 6;
            int16_t o = (int16_t)(x > 32767 ? 32767 : x < -32768 ? -32768 : x);
            out[k] = o;
            m->hash = (m->hash ^ (uint16_t)o) * 16777619u;
        }
        for (k = 0; k < n; k++) {
            m->scope_mix[m->scope_mix_pos & (BBA_SCOPE * 2 - 1)] = out[2 * k];
            m->scope_mix[(m->scope_mix_pos + 1) & (BBA_SCOPE * 2 - 1)] = out[2 * k + 1];
            m->scope_mix_pos += 2;
        }
        out += 2 * n;
        frames -= n;
    }
}

void bba_wav_header(uint8_t h[44], int rate, uint32_t frames)
{
    uint32_t data = frames * 4, v;
    int i;
    static const uint8_t tmpl[44] = {
        'R','I','F','F', 0,0,0,0, 'W','A','V','E', 'f','m','t',' ', 16,0,0,0, 1,0, 2,0,
        0,0,0,0, 0,0,0,0, 4,0, 16,0, 'd','a','t','a', 0,0,0,0
    };
    memcpy(h, tmpl, 44);
    v = data + 36; for (i = 0; i < 4; i++) h[4 + i] = (uint8_t)(v >> (8 * i));
    v = (uint32_t)rate; for (i = 0; i < 4; i++) h[24 + i] = (uint8_t)(v >> (8 * i));
    v = (uint32_t)rate * 4; for (i = 0; i < 4; i++) h[28 + i] = (uint8_t)(v >> (8 * i));
    v = data; for (i = 0; i < 4; i++) h[40 + i] = (uint8_t)(v >> (8 * i));
}
