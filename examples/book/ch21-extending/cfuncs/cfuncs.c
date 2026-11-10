/* cfuncs.c - plain C functions that a Boing BASIC program calls with Declare ... Lib "C".
 * Nothing Boing-specific here: no headers of Boing BASIC, just C types. */
#include <stdint.h>
#include <math.h>
#include <stdio.h>

/* the CRC-32 of a string (the same as zip and PNG use) */
int32_t crc32_text(const char *s)
{
    uint32_t c = 0xFFFFFFFFu;
    for (; *s; s++) {
        int k;
        c ^= (unsigned char)*s;
        for (k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1)));
    }
    return (int32_t)~c;
}

double distance3(double x, double y, double z)
{
    return sqrt(x * x + y * y + z * z);
}

/* a returned string is copied by Boing BASIC, so a static buffer is fine */
const char *ordinal(int32_t n)
{
    static char buf[32];
    const char *suffix = "th";
    if (n % 100 < 11 || n % 100 > 13) {
        if (n % 10 == 1) suffix = "st";
        else if (n % 10 == 2) suffix = "nd";
        else if (n % 10 == 3) suffix = "rd";
    }
    snprintf(buf, sizeof buf, "%ld%s", (long)n, suffix);
    return buf;
}
