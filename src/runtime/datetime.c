/* datetime.c - Date values and the date/time built-ins */
#include "boing.h"
#include "platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <math.h>

static const char *month_names[] = {"January", "February", "March", "April", "May", "June", "July",
                                    "August", "September", "October", "November", "December"};
static const char *day_names[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};

/* days from civil (proleptic Gregorian), relative to 1899-12-30 */
static long days_from_civil(long y, long m, long d)
{
    long era, yoe, doy, doe;
    y -= m <= 2;
    era = (y >= 0 ? y : y - 399) / 400;
    yoe = y - era * 400;
    doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468 + 25569; /* 1970-01-01 is serial 25569 */
}

static void civil_from_days(long z, long *py, long *pm, long *pd)
{
    long era, doe, yoe, y, doy, mp, d, m;
    z -= 25569;
    z += 719468;
    era = (z >= 0 ? z : z - 146096) / 146097;
    doe = z - era * 146097;
    yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    y = yoe + era * 400;
    doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    mp = (5 * doy + 2) / 153;
    d = doy - (153 * mp + 2) / 5 + 1;
    m = mp + (mp < 10 ? 3 : -9);
    *py = y + (m <= 2);
    *pm = m;
    *pd = d;
}

static void split_date(bb_date dt, long *y, long *m, long *d, long *h, long *n, long *s)
{
    double day = floor(dt);
    double frac = fabs(dt - day);
    long secs;
    if (dt < 0 && frac != 0) { day = ceil(dt); frac = fabs(dt - day); }
    secs = (long)floor(frac * 86400.0 + 0.5);
    if (secs >= 86400) { secs -= 86400; day += 1; }
    civil_from_days((long)day, y, m, d);
    *h = secs / 3600;
    *n = (secs / 60) % 60;
    *s = secs % 60;
}

bb_date bb_dateserial(bb_long y, bb_long m, bb_long d)
{
    long yy = y, mm = m;
    if (yy >= 0 && yy < 30) yy += 2000;
    else if (yy >= 30 && yy < 100) yy += 1900;
    /* normalise month overflow */
    mm -= 1;
    yy += mm >= 0 ? mm / 12 : -((11 - mm) / 12);
    mm = ((mm % 12) + 12) % 12 + 1;
    if (yy < 100 || yy > 9999) bb_raise(5, NULL);
    return (bb_date)(days_from_civil(yy, mm, 1) + (d - 1));
}

bb_date bb_timeserial(bb_long h, bb_long m, bb_long s)
{
    double t = ((double)h * 3600.0 + (double)m * 60.0 + (double)s) / 86400.0;
    return t;
}

bb_long bb_year(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return y; }
bb_long bb_month(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return m; }
bb_long bb_day(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return dd; }
bb_long bb_hour(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return h; }
bb_long bb_minute(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return n; }
bb_long bb_second(bb_date d) { long y, m, dd, h, n, s; split_date(d, &y, &m, &dd, &h, &n, &s); return s; }

bb_long bb_weekday(bb_date d, bb_long first)
{
    long day = (long)floor(d);
    long wd = (((day + 6) % 7) + 7) % 7 + 1;   /* 1 = Sunday */
    if (first < 1 || first > 7) first = 1;
    return (bb_long)(((wd - first) % 7 + 7) % 7 + 1);
}

bb_date bb_now(void)
{
    bb_tm t;
    bb_plat_localtime(&t);
    return bb_dateserial(t.year, t.month, t.day) + bb_timeserial(t.hour, t.minute, t.second);
}

bb_date bb_date_fn(void) { return floor(bb_now()); }
bb_date bb_time_fn(void) { bb_date n = bb_now(); return n - floor(n); }

bb_single bb_timer(void)
{
    bb_tm t;
    bb_plat_localtime(&t);
    return (bb_single)(t.hour * 3600 + t.minute * 60 + t.second + t.msec / 1000.0);
}

bb_double bb_timer_ms(void) { return bb_plat_seconds() * 1000.0; }

bb_str *bb_monthname(bb_long m, bb_bool abbrev)
{
    char b[16];
    if (m < 1 || m > 12) bb_raise(5, NULL);
    snprintf(b, sizeof b, "%s", month_names[m - 1]);
    if (abbrev) b[3] = 0;
    return bb_str_from_c(b);
}

bb_str *bb_weekdayname(bb_long d, bb_bool abbrev)
{
    char b[16];
    if (d < 1 || d > 7) bb_raise(5, NULL);
    snprintf(b, sizeof b, "%s", day_names[d - 1]);
    if (abbrev) b[3] = 0;
    return bb_str_from_c(b);
}

static void fmt_time(char *b, size_t n, long h, long mi, long s)
{
    snprintf(b, n, "%ld:%02ld:%02ld %s", h % 12 == 0 ? 12 : h % 12, mi, s, h < 12 ? "AM" : "PM");
}

bb_str *bb_str_from_date(bb_date d)
{
    long y, m, dd, h, n, s;
    char b[64], t[32];
    split_date(d, &y, &m, &dd, &h, &n, &s);
    fmt_time(t, sizeof t, h, n, s);
    if (floor(d) == 0 && d >= 0) return bb_str_from_c(t);
    if (h == 0 && n == 0 && s == 0) snprintf(b, sizeof b, "%ld/%ld/%ld", m, dd, y);
    else snprintf(b, sizeof b, "%ld/%ld/%ld %s", m, dd, y, t);
    return bb_str_from_c(b);
}

static int month_from_name(const char *p, int n)
{
    int i;
    if (n < 3) return 0;
    for (i = 0; i < 12; i++)
        if (strncasecmp(p, month_names[i], (size_t)n) == 0 && (n == 3 || (size_t)n == strlen(month_names[i]))) return i + 1;
    return 0;
}

/* Parse a date/time string; 1 on success */
static int parse_date(const char *p, bb_date *out)
{
    long nums[6];
    int month = 0, have_time = 0, pm = -1, i;
    long tparts[3] = {0, 0, 0};
    int nt = 0;
    long dparts[3];
    int nd = 0;
    const char *q = p;
    int sep_dash = 0;
    (void)nums;
    while (*q) {
        if (isspace((unsigned char)*q) || *q == ',') { q++; continue; }
        if (isdigit((unsigned char)*q)) {
            long v = 0;
            const char *st = q;
            while (isdigit((unsigned char)*q)) v = v * 10 + (*q++ - '0');
            (void)st;
            if (*q == ':' || (nt > 0 && nt < 3 && q > p && st > p && st[-1] == ':')) {
                if (nt < 3) tparts[nt++] = v;
                have_time = 1;
                if (*q == ':') q++;
            } else {
                if (nd < 3) dparts[nd++] = v; else return 0;
                if (*q == '-') sep_dash = 1;
                if (*q == '/' || *q == '-' || *q == '.') q++;
            }
        } else if (isalpha((unsigned char)*q)) {
            const char *st = q;
            int len;
            while (isalpha((unsigned char)*q)) q++;
            len = (int)(q - st);
            if ((len == 2 || len == 1) && (toupper((unsigned char)st[0]) == 'A' || toupper((unsigned char)st[0]) == 'P') &&
                (len == 1 || toupper((unsigned char)st[1]) == 'M')) {
                pm = toupper((unsigned char)st[0]) == 'P';
            } else {
                int mo = month_from_name(st, len);
                if (!mo) {
                    /* day names are ignored */
                    int k, ok = 0;
                    for (k = 0; k < 7; k++) if (strncasecmp(st, day_names[k], (size_t)(len < 3 ? 3 : len)) == 0) ok = 1;
                    if (!ok) return 0;
                } else month = mo;
            }
            if (*q == '-' || *q == '/' || *q == '.') q++;
        } else return 0;
    }
    (void)sep_dash;
    {
        double dv = 0;
        if (month) {
            long y, d;
            if (nd == 2) {
                if (dparts[0] > 31) { y = dparts[0]; d = dparts[1]; } else { d = dparts[0]; y = dparts[1]; }
            } else if (nd == 1) {
                bb_tm t;
                bb_plat_localtime(&t);
                d = dparts[0]; y = t.year;
            } else return 0;
            dv = bb_dateserial(y, month, d);
        } else if (nd == 3) {
            long y, m, d;
            if (dparts[0] > 31) { y = dparts[0]; m = dparts[1]; d = dparts[2]; }     /* yyyy-mm-dd */
            else { m = dparts[0]; d = dparts[1]; y = dparts[2]; }                    /* m/d/y */
            if (m < 1 || m > 12 || d < 1 || d > 31) return 0;
            dv = bb_dateserial(y, m, d);
        } else if (nd == 2) {
            bb_tm t;
            long m = dparts[0], d = dparts[1];
            bb_plat_localtime(&t);
            if (m > 12) return 0;
            dv = bb_dateserial(t.year, m, d);
        } else if (nd != 0) return 0;
        if (have_time || pm >= 0) {
            if (!have_time && nd == 1) { tparts[0] = dparts[0]; nt = 1; nd = 0; dv = 0; }
            if (tparts[0] > 23 || tparts[1] > 59 || tparts[2] > 59) return 0;
            if (pm == 1 && tparts[0] < 12) tparts[0] += 12;
            if (pm == 0 && tparts[0] == 12) tparts[0] = 0;
            dv += bb_timeserial(tparts[0], tparts[1], tparts[2]);
        } else if (nd == 0) return 0;
        for (i = 0; i < 0; i++) ;
        *out = dv;
    }
    return 1;
}

bb_date bb_str_to_date(const bb_str *s)
{
    bb_date d;
    double x;
    if (parse_date(bb_str_ptr(s), &d)) return d;
    if (bb_parse_number(bb_str_ptr(s), bb_str_len(s), &x)) return x;
    bb_raise(13, NULL);
    return 0;
}

bb_bool bb_isdate(const bb_value *v)
{
    bb_value t;
    bb_date d;
    v = bb_v_deref(v, &t);
    if (v->type == BB_DATE) return BB_TRUE;
    if (v->type == BB_STRING) return parse_date(bb_str_ptr(v->u.s), &d) ? BB_TRUE : BB_FALSE;
    return BB_FALSE;
}

static int interval_of(bb_str *iv)
{
    const char *p = bb_str_ptr(iv);
    if (!strcasecmp(p, "yyyy")) return 'Y';
    if (!strcasecmp(p, "q")) return 'Q';
    if (!strcasecmp(p, "m")) return 'M';
    if (!strcasecmp(p, "y")) return 'y';
    if (!strcasecmp(p, "d")) return 'D';
    if (!strcasecmp(p, "w")) return 'w';
    if (!strcasecmp(p, "ww")) return 'W';
    if (!strcasecmp(p, "h")) return 'h';
    if (!strcasecmp(p, "n")) return 'n';
    if (!strcasecmp(p, "s")) return 's';
    bb_raise(5, NULL);
    return 0;
}

bb_date bb_dateadd(bb_str *interval, bb_double n, bb_date d)
{
    int iv = interval_of(interval);
    long k = (long)(n < 0 ? ceil(n) : floor(n));
    long y, m, dd, h, mi, s;
    switch (iv) {
    case 'Y': case 'Q': case 'M': {
        long months = iv == 'Y' ? k * 12 : iv == 'Q' ? k * 3 : k, mdays;
        double tfrac = d - floor(d);
        split_date(d, &y, &m, &dd, &h, &mi, &s);
        m += months;
        y += (m - 1) >= 0 ? (m - 1) / 12 : -((12 - m) / 12);
        m = (((m - 1) % 12) + 12) % 12 + 1;
        mdays = (long)(bb_dateserial(y, m + 1, 1) - bb_dateserial(y, m, 1));
        if (dd > mdays) dd = mdays;
        return bb_dateserial(y, m, dd) + tfrac;
    }
    case 'y': case 'D': case 'w': return d + k;
    case 'W': return d + 7 * k;
    case 'h': return d + n / 24.0;
    case 'n': return d + n / 1440.0;
    case 's': return d + n / 86400.0;
    }
    return d;
}

bb_long bb_datediff(bb_str *interval, bb_date a, bb_date b)
{
    int iv = interval_of(interval);
    long y1, m1, d1, h1, n1, s1, y2, m2, d2, h2, n2, s2;
    split_date(a, &y1, &m1, &d1, &h1, &n1, &s1);
    split_date(b, &y2, &m2, &d2, &h2, &n2, &s2);
    switch (iv) {
    case 'Y': return (bb_long)(y2 - y1);
    case 'Q': return (bb_long)((y2 * 4 + (m2 - 1) / 3) - (y1 * 4 + (m1 - 1) / 3));
    case 'M': return (bb_long)((y2 * 12 + m2) - (y1 * 12 + m1));
    case 'y': case 'D': return (bb_long)(floor(b) - floor(a));
    case 'w': return (bb_long)((floor(b) - floor(a)) / 7);
    case 'W': {
        long wa = (long)floor(a) - (bb_weekday(a, 1) - 1), wb = (long)floor(b) - (bb_weekday(b, 1) - 1);
        return (bb_long)((wb - wa) / 7);
    }
    case 'h': return (bb_long)floor((b - a) * 24.0 + 1e-9 * (b > a ? 1 : -1));
    case 'n': return (bb_long)floor((b - a) * 1440.0 + 1e-7);
    case 's': return (bb_long)floor((b - a) * 86400.0 + 1e-5);
    }
    return 0;
}

bb_long bb_datepart(bb_str *interval, bb_date d)
{
    int iv = interval_of(interval);
    long y, m, dd, h, n, s;
    split_date(d, &y, &m, &dd, &h, &n, &s);
    switch (iv) {
    case 'Y': return y;
    case 'Q': return (m - 1) / 3 + 1;
    case 'M': return m;
    case 'y': return (bb_long)(floor(d) - bb_dateserial(y, 1, 1)) + 1;
    case 'D': return dd;
    case 'w': return bb_weekday(d, 1);
    case 'W': {
        bb_date j1 = bb_dateserial(y, 1, 1);
        long off = bb_weekday(j1, 1) - 1;
        return (bb_long)((floor(d) - j1 + off) / 7) + 1;
    }
    case 'h': return h;
    case 'n': return n;
    case 's': return s;
    }
    return 0;
}

/* exposed for format.c */
void bb_date_split_(bb_date d, long *y, long *m, long *dd, long *h, long *n, long *s)
{
    split_date(d, y, m, dd, h, n, s);
}
const char *bb_month_name_(int m) { return month_names[m - 1]; }
const char *bb_day_name_(int d) { return day_names[d - 1]; }
