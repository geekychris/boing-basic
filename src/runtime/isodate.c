/* isodate.c - UTC, Unix time and ISO 8601 (docs/datetime.md):
 *   NowUtc() As Date                  the current UTC date and time
 *   UtcOffset() As Long               minutes local time is ahead of UTC (+60 in CET, -300 in EST)
 *   LocalToUtc(d) / UtcToLocal(d)     with the current offset
 *   UnixTime(d) As Double             seconds since 1970-01-01 00:00 UTC of a UTC Date
 *   FromUnixTime(seconds) As Date     the UTC Date of a Unix time
 *   FormatIso8601(d [, offset])       "2026-11-10T08:45:00"; offset 0 adds "Z", other offsets
 *                                     "+01:00" (minutes, ahead of UTC); omitted: no zone
 *   ParseIso8601(s) As Date           dates, date-times, fractions of seconds, Z and +hh:mm zones;
 *                                     with a zone the result is UTC, without as written
 * The offset comes from the platform (locale.library's time zone on AmigaOS, the C library's on
 * the host); the environment variable BOING_UTC_OFFSET (minutes ahead of UTC) overrides it for
 * systems whose clock or time zone setting is off. Bad ISO 8601 text raises 31401. */
#include "boing.h"
#include "platform.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define UNIX_EPOCH 25569.0          /* 1970-01-01 as a Date */

bb_long bb_utcoffset(void)
{
    const char *e = bb_plat_getenv("BOING_UTC_OFFSET");
    if (e && *e) return atol(e);
    return bb_plat_utc_offset();
}

bb_date bb_nowutc(void) { return bb_now() - bb_utcoffset() / 1440.0; }
bb_date bb_localtoutc(bb_date d) { return d - bb_utcoffset() / 1440.0; }
bb_date bb_utctolocal(bb_date d) { return d + bb_utcoffset() / 1440.0; }
bb_double bb_unixtime(bb_date d) { return floor((d - UNIX_EPOCH) * 86400.0 * 1000.0 + 0.5) / 1000.0; }
bb_date bb_fromunixtime(bb_double s) { return UNIX_EPOCH + s / 86400.0; }

/* civil date from days since 1970-01-01 (Howard Hinnant) */
static void civil(long z, long *y, int *m, int *d)
{
    z += 719468;
    long era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned long doe = (unsigned long)(z - era * 146097);
    unsigned long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    unsigned long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    unsigned long mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = (long)yoe + era * 400 + (*m <= 2);
}

static long days_from_civil(long y, int m, int d)
{
    y -= m <= 2;
    long era = (y >= 0 ? y : y - 399) / 400;
    unsigned long yoe = (unsigned long)(y - era * 400);
    unsigned long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    unsigned long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + (long)doe - 719468;
}

bb_str *bb_formatiso8601(bb_date dt, bb_long offset)
{
    double ms_total = floor(dt * 86400000.0 + 0.5);               /* milliseconds since 1899-12-30 */
    double dayf = floor(ms_total / 86400000.0);
    long ms = (long)(ms_total - dayf * 86400000.0);
    long y;
    int m, d;
    civil((long)dayf - 25569, &y, &m, &d);
    char t[48];
    int n = snprintf(t, sizeof t, "%04ld-%02d-%02dT%02ld:%02ld:%02ld", y, m, d, ms / 3600000, (ms / 60000) % 60,
                     (ms / 1000) % 60);
    if (ms % 1000) n += snprintf(t + n, sizeof t - n, ".%03ld", ms % 1000);
    if (offset == 0) snprintf(t + n, sizeof t - n, "Z");
    else if (offset != -99999)
        snprintf(t + n, sizeof t - n, "%c%02ld:%02ld", offset < 0 ? '-' : '+', labs((long)offset) / 60,
                 labs((long)offset) % 60);
    return bb_str_from_c(t);
}

static void bad(const char *s, const char *what)
{
    char m[200];
    snprintf(m, sizeof m, "ISO 8601: %s in \"%.60s\"", what, s);
    bb_raise(31401, m);
}

static int digits(const char **p, int n, long *out)
{
    long v = 0;
    for (int i = 0; i < n; i++) {
        if ((*p)[i] < '0' || (*p)[i] > '9') return 0;
        v = v * 10 + ((*p)[i] - '0');
    }
    *p += n;
    *out = v;
    return 1;
}

bb_date bb_parseiso8601(bb_str *str)
{
    const char *s = bb_str_ptr(str), *p = s;
    long y, mo = 1, d = 1, h = 0, mi = 0, se = 0;
    double frac = 0;
    while (*p == ' ') p++;
    if (!digits(&p, 4, &y)) bad(s, "the year is missing");
    int ext = *p == '-';                            /* 2026-11-10 or 20261110 */
    if (ext) p++;
    if (*p) {
        if (!digits(&p, 2, &mo)) bad(s, "a bad month");
        if (ext && *p == '-') p++;
        else if (ext && *p) bad(s, "'-' expected after the month");
        if (*p && *p != 'T' && *p != ' ' && !digits(&p, 2, &d)) bad(s, "a bad day");
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31) bad(s, "the month or day is out of range");
    int zone = 0;
    long zmin = 0;
    if (*p == 'T' || *p == 't' || (*p == ' ' && p[1] >= '0' && p[1] <= '9')) {
        p++;
        if (!digits(&p, 2, &h)) bad(s, "a bad hour");
        if (*p == ':') p++;
        if (*p >= '0' && *p <= '9') {
            if (!digits(&p, 2, &mi)) bad(s, "bad minutes");
            if (*p == ':') p++;
            if (*p >= '0' && *p <= '9') {
                if (!digits(&p, 2, &se)) bad(s, "bad seconds");
                if (*p == '.' || *p == ',') {
                    p++;
                    double scale = 0.1;
                    if (!(*p >= '0' && *p <= '9')) bad(s, "a bad fraction of a second");
                    while (*p >= '0' && *p <= '9') {
                        frac += (*p - '0') * scale;
                        scale /= 10;
                        p++;
                    }
                }
            }
        }
        if (h > 24 || mi > 59 || se > 60) bad(s, "the time is out of range");
        if (*p == 'Z' || *p == 'z') {
            zone = 1;
            p++;
        } else if (*p == '+' || *p == '-') {
            int neg = *p == '-';
            long zh, zm = 0;
            p++;
            if (!digits(&p, 2, &zh)) bad(s, "a bad time zone");
            if (*p == ':') p++;
            if (*p >= '0' && *p <= '9' && !digits(&p, 2, &zm)) bad(s, "a bad time zone");
            zone = 1;
            zmin = (neg ? -1 : 1) * (zh * 60 + zm);
        }
    }
    while (*p == ' ') p++;
    if (*p) bad(s, "unexpected text at the end");
    double dt = days_from_civil(y, (int)mo, (int)d) + 25569.0 + (h * 3600 + mi * 60 + se + frac) / 86400.0;
    if (zone) dt -= zmin / 1440.0;                  /* to UTC */
    return dt;
}
