/* uuid.c - CreateUUID(): a random (version 4) UUID, "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx" in
 * lower case (docs/uuid.md). Randomness: /dev/urandom where there is one (the host); else, and
 * mixed in always, the high-resolution clock (EClock on AmigaOS), the time, addresses and a
 * counter, stirred through SplitMix64 into a xoshiro256** generator seeded once per program. */
#include "boing.h"
#include "platform.h"

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

static uint64_t st[4];
static int seeded;

static uint64_t splitmix(uint64_t *x)
{
    uint64_t z = (*x += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }

static uint64_t next(void)
{
    uint64_t r = rotl(st[1] * 5, 7) * 9, t = st[1] << 17;
    st[2] ^= st[0];
    st[3] ^= st[1];
    st[1] ^= st[2];
    st[0] ^= st[3];
    st[2] ^= t;
    st[3] = rotl(st[3], 45);
    return r;
}

static void seed(void)
{
    uint64_t x = 0, dev[4] = {0, 0, 0, 0};
    double s = bb_plat_seconds();
    int local, i;
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        if (fread(dev, 1, sizeof dev, f) != sizeof dev) memset(dev, 0, sizeof dev);
        fclose(f);
    }
    memcpy(&x, &s, sizeof x < sizeof s ? sizeof x : sizeof s);
    x ^= (uint64_t)time(NULL) << 20;
    x ^= (uint64_t)clock();
    x ^= (uint64_t)(uintptr_t)&local;
    x ^= (uint64_t)(uintptr_t)&seed << 32;
    for (i = 0; i < 4; i++) st[i] = splitmix(&x) ^ dev[i];
    if (!(st[0] | st[1] | st[2] | st[3])) st[0] = 1;
    seeded = 1;
}

bb_str *bb_create_uuid(void)
{
    static const char hex[] = "0123456789abcdef";
    unsigned char b[16];
    char out[37];
    uint64_t a, c;
    double s;
    int i, k = 0;
    if (!seeded) seed();
    /* stir in the clock each time, so two programs started together still differ */
    s = bb_plat_seconds();
    memcpy(&a, &s, sizeof a < sizeof s ? sizeof a : sizeof s);
    st[3] ^= splitmix(&a);
    a = next();
    c = next();
    for (i = 0; i < 8; i++) {
        b[i] = (unsigned char)(a >> (8 * i));
        b[8 + i] = (unsigned char)(c >> (8 * i));
    }
    b[6] = (unsigned char)((b[6] & 0x0F) | 0x40);     /* version 4 */
    b[8] = (unsigned char)((b[8] & 0x3F) | 0x80);     /* RFC 4122 variant */
    for (i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) out[k++] = '-';
        out[k++] = hex[b[i] >> 4];
        out[k++] = hex[b[i] & 15];
    }
    out[k] = 0;
    return bb_str_new(out, 36);
}
