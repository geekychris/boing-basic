/* bbsound.c - sound effects: 8SVX, WAV and raw files, and synthesised tones and noise
 * (the synthesis follows a3d_sound.c's a3_tone/a3_noise from amiga_mcp's amiga3d, MIT,
 * Chris Collins). Integer arithmetic, so the same sound everywhere.
 */
#include <stdlib.h>
#include <string.h>
#include "bbaudio.h"

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static uint32_t le32(const uint8_t *p) { return ((uint32_t)p[3] << 24) | ((uint32_t)p[2] << 16) | ((uint32_t)p[1] << 8) | p[0]; }
static int le16(const uint8_t *p) { return p[0] | (p[1] << 8); }

bba_sound *bba_sound_new(uint32_t len, int rate, int bits)
{
    bba_sound *s;
    if (bits != 8 && bits != 16) return NULL;
    s = (bba_sound *)calloc(1, sizeof *s);
    if (!s) return NULL;
    s->bits = bits;
    s->len = len;
    s->rate = rate > 0 ? rate : 22050;
    s->data = calloc(len ? len : 1, (size_t)bits / 8);
    if (!s->data) { free(s); return NULL; }
    return s;
}

void bba_sound_free(bba_sound *s)
{
    if (!s) return;
    free(s->data);
    free(s);
}

int bba_sound_get(const bba_sound *s, uint32_t i)
{
    if (i >= s->len) return 0;
    return s->bits == 8 ? ((const int8_t *)s->data)[i] : ((const int16_t *)s->data)[i];
}

void bba_sound_set(bba_sound *s, uint32_t i, int v)
{
    if (i >= s->len) return;
    if (s->bits == 8) ((int8_t *)s->data)[i] = (int8_t)(v < -128 ? -128 : v > 127 ? 127 : v);
    else ((int16_t *)s->data)[i] = (int16_t)(v < -32768 ? -32768 : v > 32767 ? 32767 : v);
}

static bba_sound *parse_8svx(const uint8_t *d, long len)
{
    const uint8_t *vhdr = NULL, *body = NULL;
    uint32_t blen = 0;
    long off = 12;
    bba_sound *s;
    while (off + 8 <= len) {
        uint32_t cl = be32(d + off + 4);
        if (cl > (uint32_t)(len - off - 8)) cl = (uint32_t)(len - off - 8);
        if (!memcmp(d + off, "VHDR", 4) && cl >= 20) vhdr = d + off + 8;
        else if (!memcmp(d + off, "BODY", 4)) { body = d + off + 8; blen = cl; }
        off += 8 + ((cl + 1) & ~1u);
    }
    if (!vhdr || !body) return NULL;
    {
        uint32_t one = be32(vhdr), rep = be32(vhdr + 4);
        int rate = (vhdr[12] << 8) | vhdr[13], comp = vhdr[15];
        uint32_t n = comp == 1 ? (blen > 2 ? (blen - 2) * 2 : 0) : blen;
        if (one + rep > 0 && one + rep < n) n = one + rep;     /* first octave only */
        s = bba_sound_new(n, rate ? rate : 8363, 8);
        if (!s) return NULL;
        if (comp == 1) {        /* Fibonacci delta */
            static const int8_t fib[16] = { -34, -21, -13, -8, -5, -3, -2, -1, 0, 1, 2, 3, 5, 8, 13, 21 };
            int x = (int8_t)body[1];
            uint32_t i;
            for (i = 0; i < n; i++) {
                int b = body[2 + i / 2];
                x += fib[(i & 1) ? b & 15 : b >> 4];
                ((int8_t *)s->data)[i] = (int8_t)x;
            }
        } else if (comp == 0) {
            memcpy(s->data, body, n);
        } else { bba_sound_free(s); return NULL; }
        if (rep > 0 && one < n) {
            s->loop = 1;
            s->loop_start = one;
            s->loop_len = n - one;
        }
    }
    return s;
}

static bba_sound *parse_wav(const uint8_t *d, long len)
{
    const uint8_t *fmt = NULL, *data = NULL;
    uint32_t dlen = 0, n, i;
    long off = 12;
    int fmtcode, chans, rate, bits, bpf;
    bba_sound *s;
    while (off + 8 <= len) {
        uint32_t cl = le32(d + off + 4);
        if (cl > (uint32_t)(len - off - 8)) cl = (uint32_t)(len - off - 8);
        if (!memcmp(d + off, "fmt ", 4) && cl >= 16) fmt = d + off + 8;
        else if (!memcmp(d + off, "data", 4)) { data = d + off + 8; dlen = cl; }
        off += 8 + ((cl + 1) & ~1u);
    }
    if (!fmt || !data) return NULL;
    fmtcode = le16(fmt);
    chans = le16(fmt + 2);
    rate = (int)le32(fmt + 4);
    bits = le16(fmt + 14);
    if ((fmtcode != 1 && fmtcode != 0xFFFE) || chans < 1 || chans > 8 || (bits != 8 && bits != 16)) return NULL;
    bpf = chans * bits / 8;
    n = dlen / (uint32_t)bpf;
    s = bba_sound_new(n, rate, bits);
    if (!s) return NULL;
    for (i = 0; i < n; i++) {
        const uint8_t *f = data + (size_t)i * bpf;
        int c, sum = 0;
        for (c = 0; c < chans; c++)
            sum += bits == 8 ? (int)f[c] - 128 : (int16_t)le16(f + 2 * c);
        sum /= chans;
        if (bits == 8) ((int8_t *)s->data)[i] = (int8_t)sum;
        else ((int16_t *)s->data)[i] = (int16_t)sum;
    }
    return s;
}

bba_sound *bba_sound_parse(const uint8_t *d, long len, const char *fmt, int rate)
{
    if (fmt && *fmt) {
        bba_sound *s;
        uint32_t i, n;
        int b16 = !strcmp(fmt, "s16le") || !strcmp(fmt, "s16be");
        if (!b16 && strcmp(fmt, "s8") && strcmp(fmt, "u8")) return NULL;
        n = (uint32_t)(b16 ? len / 2 : len);
        s = bba_sound_new(n, rate > 0 ? rate : 8363, b16 ? 16 : 8);
        if (!s) return NULL;
        for (i = 0; i < n; i++) {
            if (!strcmp(fmt, "s8")) ((int8_t *)s->data)[i] = (int8_t)d[i];
            else if (!strcmp(fmt, "u8")) ((int8_t *)s->data)[i] = (int8_t)(d[i] - 128);
            else if (fmt[3] == 'l') ((int16_t *)s->data)[i] = (int16_t)(d[2 * i] | (d[2 * i + 1] << 8));
            else ((int16_t *)s->data)[i] = (int16_t)((d[2 * i] << 8) | d[2 * i + 1]);
        }
        return s;
    }
    if (len >= 12 && !memcmp(d, "FORM", 4) && !memcmp(d + 8, "8SVX", 4)) return parse_8svx(d, len);
    if (len >= 12 && !memcmp(d, "RIFF", 4) && !memcmp(d + 8, "WAVE", 4)) return parse_wav(d, len);
    return NULL;
}

/* one period of a waveform at phase ph (0..65535) -> -32767..32767 */
static int osc(int wave, uint32_t ph)
{
    int x = (int)(ph & 0xFFFF);
    switch (wave) {
    case 1: return x < 32768 ? 32767 : -32767;                       /* square */
    case 2: {                                                        /* sine (parabolic) */
        int t = x < 32768 ? x : x - 32768, y;                        /* half period 0..32767 */
        y = (int)(((int64_t)t * (32768 - t)) >> 13);                 /* peak 32768 at t=16384 */
        y = y > 32767 ? 32767 : y;
        return x < 32768 ? y : -y;
    }
    case 3: return x - 32768;                                        /* saw */
    default:                                                         /* triangle */
        return x < 16384 ? x * 2 : x < 49152 ? 65535 - x * 2 : x * 2 - 131072;
    }
}

bba_sound *bba_synth_tone(int rate, int ms, int f0, int f1, int vol, int wave)
{
    uint32_t n, i, ph = 0, fade;
    bba_sound *s;
    if (ms < 1 || ms > 60000 || f0 < 1 || f1 < 1) return NULL;
    n = (uint32_t)((int64_t)rate * ms / 1000);
    s = bba_sound_new(n, rate, 16);
    if (!s) return NULL;
    fade = n / 4 < (uint32_t)rate / 100 ? n / 4 : (uint32_t)rate / 100;     /* <= 10 ms */
    if (vol < 0) vol = 0;
    if (vol > 64) vol = 64;
    for (i = 0; i < n; i++) {
        int f = f0 + (int)((int64_t)(f1 - f0) * i / n);
        int64_t a = (int64_t)osc(wave, ph) * vol / 64;
        if (i < fade) a = a * (int64_t)i / fade;
        else if (n - i < 4 * fade) a = a * (int64_t)(n - i) / (4 * fade);
        ((int16_t *)s->data)[i] = (int16_t)a;
        ph += (uint32_t)(((uint64_t)f << 16) / (uint32_t)rate);
    }
    return s;
}

bba_sound *bba_synth_noise(int rate, int ms, int vol, int smooth, int attack_ms)
{
    uint32_t n, i, att, seed = 0x1234567u;
    int32_t y = 0;
    bba_sound *s;
    if (ms < 1 || ms > 60000) return NULL;
    n = (uint32_t)((int64_t)rate * ms / 1000);
    s = bba_sound_new(n, rate, 16);
    if (!s) return NULL;
    if (vol < 0) vol = 0;
    if (vol > 64) vol = 64;
    if (smooth < 0) smooth = 0;
    if (smooth > 15) smooth = 15;
    att = (uint32_t)((int64_t)rate * (attack_ms < 0 ? 0 : attack_ms) / 1000);
    for (i = 0; i < n; i++) {
        int32_t x;
        int64_t a;
        seed = seed * 1103515245u + 12345u;
        x = (int32_t)((seed >> 8) & 0xFFFF) - 32768;
        y += (x - y) * (16 - smooth) / 16;
        a = (int64_t)y * vol / 64 * (int64_t)(n - i) / n;           /* decays to 0 */
        if (i < att) a = a * (int64_t)i / att;
        ((int16_t *)s->data)[i] = (int16_t)(a > 32767 ? 32767 : a < -32768 ? -32768 : a);
    }
    return s;
}
