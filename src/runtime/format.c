/* format.c - the Format() function */
#include "boing.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <math.h>

void bb_date_split_(bb_date d, long *y, long *m, long *dd, long *h, long *n, long *s);
const char *bb_month_name_(int m);
const char *bb_day_name_(int d);

typedef struct sbuf { char *p; size_t n, cap; } sbuf;
static void sb_putn(sbuf *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        b->cap = (b->n + n + 1) * 2;
        b->p = (char *)realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = 0;
}
static void sb_puts(sbuf *b, const char *s) { sb_putn(b, s, strlen(s)); }
static void sb_putc(sbuf *b, char c) { sb_putn(b, &c, 1); }
static bb_str *sb_done(sbuf *b) { bb_str *s = bb_str_new(b->p, (int32_t)b->n); free(b->p); return s; }

/* integer digits of a non-negative double rounded to `dec` decimals, half away from zero */
static void num_digits(double x, int dec, char *ip, size_t ipn, char *fp, size_t fpn)
{
    char buf[400];
    char *dot;
    if (dec >= 0 && dec <= 9 && x >= 0 && x < 1e15) {
        /* small enough to round in integers: no snprintf (slow on newlib) */
        static const double p10[] = {1, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9};
        double v = x * p10[dec];
        if (v < 1e12) {
            uint64_t r = (uint64_t)floor(v + v * 1e-15 + 0.5), pw = (uint64_t)p10[dec];
            uint64_t ipart = r / pw, fpart = r % pw;
            int k;
            if (ipart) bb_u64_to_dec_(ipart, 0, ip); else ip[0] = 0;
            for (k = dec - 1; k >= 0; k--) { fp[k] = (char)('0' + (int)(fpart % 10)); fpart /= 10; }
            fp[dec] = 0;
            (void)ipn; (void)fpn;
            return;
        }
    }
    snprintf(buf, sizeof buf, "%.*f", dec, x + (x > 0 ? x * 1e-15 : 0));
    dot = strchr(buf, '.');
    if (dot) {
        *dot = 0;
        snprintf(fp, fpn, "%s", dot + 1);
    } else fp[0] = 0;
    snprintf(ip, ipn, "%s", buf);
    if (strcmp(ip, "0") == 0) ip[0] = 0;
}

static void group3(const char *d, char *out, size_t on)
{
    size_t l = strlen(d), i, k = 0;
    for (i = 0; i < l && k + 2 < on; i++) {
        out[k++] = d[i];
        if ((l - 1 - i) % 3 == 0 && i + 1 < l) out[k++] = ',';
    }
    out[k] = 0;
}

/* format one numeric section */
static void fmt_numeric(sbuf *b, const char *fmt, size_t flen, double x, int neg_sign)
{
    size_t i;
    int nint = 0, nzero_int = 0, ndec = 0, minfrac = 0, has_dot = 0, group = 0, pct = 0, sci = 0;
    int first_int_zero = -1;
    char ip[340], fp[340], grouped[460];
    int exp10 = 0;
    /* analyse */
    for (i = 0; i < flen; i++) {
        char c = fmt[i];
        if (c == '"') { for (i++; i < flen && fmt[i] != '"'; i++) {} continue; }
        if (c == '\\') { i++; continue; }
        if (sci) continue;
        if (c == '0' || c == '#') {
            if (has_dot) { ndec++; if (c == '0') minfrac = ndec; }
            else { nint++; if (c == '0') { nzero_int++; if (first_int_zero < 0) first_int_zero = nint; } }
        } else if (c == '.' && !has_dot) has_dot = 1;
        else if (c == ',' && !has_dot) { if (nint) group = 1; }
        else if (c == '%') pct = 1;
        else if ((c == 'E' || c == 'e') && i + 1 < flen && (fmt[i + 1] == '+' || fmt[i + 1] == '-')) sci = 1;
    }
    if (first_int_zero > 0) nzero_int = nint - first_int_zero + 1;
    if (pct) x *= 100;
    if (sci && x != 0) {
        exp10 = (int)floor(log10(x));
        x /= pow(10, exp10 - (nint > 0 ? nint - 1 : 0));
        exp10 -= (nint > 0 ? nint - 1 : 0);
        /* rounding might push mantissa to 10 */
        {
            double r = floor(x * pow(10, ndec) + 0.5) / pow(10, ndec);
            if (r >= pow(10, nint > 0 ? nint : 1)) { x /= 10; exp10++; }
        }
    }
    num_digits(x, ndec, ip, sizeof ip, fp, sizeof fp);
    /* trim optional trailing fraction digits */
    {
        int l = (int)strlen(fp);
        while (l > minfrac && fp[l - 1] == '0') fp[--l] = 0;
    }
    /* pad integer zeros */
    {
        int l = (int)strlen(ip);
        if (l < nzero_int) {
            char t[340];
            int k = nzero_int - l;
            memset(t, '0', (size_t)k);
            snprintf(t + k, sizeof t - (size_t)k, "%s", ip);
            snprintf(ip, sizeof ip, "%s", t);
        }
    }
    if (neg_sign && (ip[0] || fp[0] || 1)) {
        int nonzero = 0;
        const char *q;
        for (q = ip; *q; q++) if (*q != '0') nonzero = 1;
        for (q = fp; *q; q++) if (*q != '0') nonzero = 1;
        if (nonzero || nzero_int || minfrac) sb_putc(b, '-');
    }
    if (group) { group3(ip, grouped, sizeof grouped); snprintf(ip, sizeof ip, "%s", grouped); }
    /* emit */
    {
        int int_seen = 0, dot_done = 0, frac_i = 0, k;
        int ipl = (int)strlen(ip);
        /* distribute integer digits right to left when not grouped */
        int remaining = nint;
        int ipos = 0;   /* next index into ip */
        int sci_done = 0;
        for (i = 0; i < flen; i++) {
            char c = fmt[i];
            if (c == '"') {
                size_t j = i + 1;
                while (j < flen && fmt[j] != '"') j++;
                sb_putn(b, fmt + i + 1, j - i - 1);
                i = j;
                continue;
            }
            if (c == '\\') { if (i + 1 < flen) sb_putc(b, fmt[++i]); continue; }
            if (sci_done && (c == '0' || c == '#')) continue;
            if ((c == '0' || c == '#') && !dot_done) {
                if (group) {
                    if (!int_seen) sb_puts(b, ip);
                } else {
                    /* this placeholder covers digits so that `remaining-1` placeholders follow */
                    int take = (ipl - ipos) - (remaining - 1);
                    if (take < 0) take = 0;
                    if (take > 0) { sb_putn(b, ip + ipos, (size_t)take); ipos += take; }
                    else if (ipl - ipos < remaining && c == '0' && ipos >= ipl) sb_putc(b, '0');
                }
                remaining--;
                int_seen = 1;
                continue;
            }
            if (c == ',' && !dot_done) continue;
            if (c == '.' && !dot_done) { dot_done = 1; sb_putc(b, '.'); continue; }
            if ((c == '0' || c == '#') && dot_done) {
                if (fp[frac_i]) sb_putc(b, fp[frac_i++]);
                else if (c == '0') sb_putc(b, '0');
                continue;
            }
            if ((c == 'E' || c == 'e') && i + 1 < flen && (fmt[i + 1] == '+' || fmt[i + 1] == '-') && sci) {
                char eb[16];
                int ez = 0;
                size_t j = i + 2;
                while (j < flen && (fmt[j] == '0' || fmt[j] == '#')) { if (fmt[j] == '0') ez++; j++; }
                sb_putc(b, c);
                if (exp10 < 0) sb_putc(b, '-'); else if (fmt[i + 1] == '+') sb_putc(b, '+');
                snprintf(eb, sizeof eb, "%0*d", ez ? ez : 1, abs(exp10));
                sb_puts(b, eb);
                i = j - 1;
                sci_done = 1;
                continue;
            }
            sb_putc(b, c);
        }
        (void)k;
    }
}

static int is_date_fmt(const char *f)
{
    int has_num = 0, has_date = 0;
    for (; *f; f++) {
        char c = (char)tolower((unsigned char)*f);
        if (*f == '"') { for (f++; *f && *f != '"'; f++) {} if (!*f) break; continue; }
        if (*f == '\\') { if (f[1]) f++; continue; }
        if (c == '0' || c == '#') has_num = 1;
        if (c == 'd' || c == 'm' || c == 'y' || c == 'h' || c == 'n' || c == 's' || c == 'w' || c == 'q' || c == 'c' || c == 't')
            has_date = 1;
    }
    return has_date && !has_num;
}

static void fmt_date(sbuf *b, const char *f, bb_date d)
{
    long y, m, dd, h, n, s;
    char t[64];
    int last_h = 0;
    int ampm = 0;
    const char *q;
    bb_date_split_(d, &y, &m, &dd, &h, &n, &s);
    /* 12-hour clock if an AM/PM token is present */
    for (q = f; *q; q++)
        if (!strncasecmp(q, "am/pm", 5) || !strncasecmp(q, "a/p", 3) || !strncasecmp(q, "ampm", 4)) ampm = 1;
    while (*f) {
        char c = (char)tolower((unsigned char)*f);
        int k = 0;
        while (tolower((unsigned char)f[k]) == c && c != '"' && c != '\\') k++;
        if (*f == '"') {
            const char *e = strchr(f + 1, '"');
            if (!e) e = f + strlen(f);
            sb_putn(b, f + 1, (size_t)(e - f - 1));
            f = *e ? e + 1 : e;
            continue;
        }
        if (*f == '\\') { if (f[1]) { sb_putc(b, f[1]); f += 2; } else f++; continue; }
        if (!strncasecmp(f, "am/pm", 5)) {
            int up = f[0] == 'A' || f[0] == 'P';
            sb_puts(b, h < 12 ? (up ? "AM" : "am") : (up ? "PM" : "pm"));
            f += 5; continue;
        }
        if (!strncasecmp(f, "a/p", 3)) {
            int up = f[0] == 'A' || f[0] == 'P';
            sb_puts(b, h < 12 ? (up ? "A" : "a") : (up ? "P" : "p"));
            f += 3; continue;
        }
        if (!strncasecmp(f, "ampm", 4)) { sb_puts(b, h < 12 ? "AM" : "PM"); f += 4; continue; }
        switch (c) {
        case 'd':
            if (k == 1) snprintf(t, sizeof t, "%ld", dd);
            else if (k == 2) snprintf(t, sizeof t, "%02ld", dd);
            else if (k == 3) snprintf(t, sizeof t, "%.3s", bb_day_name_((int)bb_weekday(d, 1)));
            else if (k == 4) snprintf(t, sizeof t, "%s", bb_day_name_((int)bb_weekday(d, 1)));
            else if (k == 5) snprintf(t, sizeof t, "%ld/%ld/%ld", m, dd, y);
            else snprintf(t, sizeof t, "%s, %s %ld, %ld", bb_day_name_((int)bb_weekday(d, 1)), bb_month_name_((int)m), dd, y);
            sb_puts(b, t); break;
        case 'm':
            if (last_h && k <= 2) {
                snprintf(t, sizeof t, k == 1 ? "%ld" : "%02ld", n);
            } else {
                /* minutes if followed by :s */
                const char *r = f + k;
                while (*r == ' ') r++;
                if (k <= 2 && *r == ':' && tolower((unsigned char)r[1]) == 's') snprintf(t, sizeof t, k == 1 ? "%ld" : "%02ld", n);
                else if (k == 1) snprintf(t, sizeof t, "%ld", m);
                else if (k == 2) snprintf(t, sizeof t, "%02ld", m);
                else if (k == 3) snprintf(t, sizeof t, "%.3s", bb_month_name_((int)m));
                else snprintf(t, sizeof t, "%s", bb_month_name_((int)m));
            }
            sb_puts(b, t); break;
        case 'y':
            if (k == 1) snprintf(t, sizeof t, "%ld", (long)(floor(d) - bb_dateserial(y, 1, 1)) + 1);
            else if (k == 2) snprintf(t, sizeof t, "%02ld", y % 100);
            else snprintf(t, sizeof t, "%ld", y);
            sb_puts(b, t); break;
        case 'h': {
            long hh = ampm ? (h % 12 == 0 ? 12 : h % 12) : h;
            snprintf(t, sizeof t, k == 1 ? "%ld" : "%02ld", hh);
            sb_puts(b, t);
            f += k; last_h = 1;
            continue;
        }
        case 'n': snprintf(t, sizeof t, k == 1 ? "%ld" : "%02ld", n); sb_puts(b, t); break;
        case 's': snprintf(t, sizeof t, k == 1 ? "%ld" : "%02ld", s); sb_puts(b, t); break;
        case 'w':
            if (k == 1) snprintf(t, sizeof t, "%ld", (long)bb_weekday(d, 1));
            else { bb_date j1 = bb_dateserial(y, 1, 1); snprintf(t, sizeof t, "%ld", (long)((floor(d) - j1 + (bb_weekday(j1, 1) - 1)) / 7) + 1); }
            sb_puts(b, t); break;
        case 'q': snprintf(t, sizeof t, "%ld", (m - 1) / 3 + 1); sb_puts(b, t); break;
        case 'c': { bb_str *x = bb_str_from_date(d); sb_puts(b, bb_str_ptr(x)); bb_str_release(x); break; }
        case 't':
            if (k >= 5) {
                snprintf(t, sizeof t, "%ld:%02ld:%02ld %s", h % 12 == 0 ? 12 : h % 12, n, s, h < 12 ? "AM" : "PM");
                sb_puts(b, t);
            } else sb_putn(b, f, (size_t)k);
            break;
        default:
            sb_putn(b, f, (size_t)k);
        }
        if (c != ':' && c != ' ' && c != 'h') last_h = (c == ':' ) ? last_h : 0;
        if (c == ':') { /* keep last_h across the separator */ }
        f += k;
    }
}

static bb_str *fmt_string(const char *f, bb_str *s)
{
    sbuf b = {0, 0, 0};
    int nph = 0, lower = 0, upper = 0, left = 0, i, si, l = bb_str_len(s);
    const char *p;
    for (p = f; *p; p++) {
        if (*p == '@' || *p == '&') nph++;
        else if (*p == '<') lower = 1;
        else if (*p == '>') upper = 1;
        else if (*p == '!') left = 1;
    }
    /* right-to-left fill unless '!' */
    {
        int start = left ? 0 : (l > nph ? 0 : l - nph);  /* negative: leading placeholders get padding */
        int extra = l > nph ? l - nph : 0;
        si = start;
        sb_putc(&b, 0); b.n = 0;
        for (p = f; *p; p++) {
            if (*p == '@' || *p == '&') {
                if (extra && si == 0 && !left) { sb_putn(&b, bb_str_ptr(s), (size_t)extra); si = extra; extra = 0; }
                if (si < 0) { if (*p == '@') sb_putc(&b, ' '); si++; }
                else if (si < l) sb_putc(&b, bb_str_ptr(s)[si++]);
                else if (*p == '@') sb_putc(&b, ' ');
            } else if (*p == '<' || *p == '>' || *p == '!') ;
            else if (*p == '\\' && p[1]) sb_putc(&b, *++p);
            else sb_putc(&b, *p);
        }
        if (left && si < l) sb_putn(&b, bb_str_ptr(s) + si, (size_t)(l - si));
    }
    if (nph == 0) { b.n = 0; sb_putn(&b, bb_str_ptr(s), (size_t)l); }
    for (i = 0; i < (int)b.n; i++) {
        if (lower) b.p[i] = (char)tolower((unsigned char)b.p[i]);
        if (upper) b.p[i] = (char)toupper((unsigned char)b.p[i]);
    }
    return sb_done(&b);
}

bb_str *bb_format(const bb_value *v0, bb_str *fmt)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    const char *f = bb_str_ptr(fmt);
    sbuf b = {0, 0, 0};
    double x;
    if (v->type == BB_NULL || v->type == BB_EMPTY) {
        if (v->type == BB_EMPTY && bb_str_len(fmt) && !is_date_fmt(f)) { bb_value z = bb_v_int(0); return bb_format(&z, fmt); }
        return NULL;
    }
    if (!bb_str_len(fmt)) {
        return bb_v_to_str(v);
    }
    /* named formats */
    if (!strcasecmp(f, "General Number")) { x = bb_v_to_double(v); return bb_str_from_double(x); }
    if (!strcasecmp(f, "Currency")) {
        x = bb_v_to_double(v);
        if (x < 0) { bb_str *r, *pos; bb_value nv = bb_v_double(-x); pos = bb_format(&nv, fmt);
            sb_puts(&b, "("); sb_puts(&b, bb_str_ptr(pos)); sb_puts(&b, ")"); bb_str_release(pos); r = sb_done(&b); return r; }
        sb_putc(&b, '$'); fmt_numeric(&b, "#,##0.00", 8, x, 0); return sb_done(&b);
    }
    if (!strcasecmp(f, "Fixed")) { x = bb_v_to_double(v); fmt_numeric(&b, "0.00", 4, fabs(x), x < 0); return sb_done(&b); }
    if (!strcasecmp(f, "Standard")) { x = bb_v_to_double(v); fmt_numeric(&b, "#,##0.00", 8, fabs(x), x < 0); return sb_done(&b); }
    if (!strcasecmp(f, "Percent")) { x = bb_v_to_double(v); fmt_numeric(&b, "0.00%", 5, fabs(x), x < 0); return sb_done(&b); }
    if (!strcasecmp(f, "Scientific")) { x = bb_v_to_double(v); fmt_numeric(&b, "0.00E+00", 8, fabs(x), x < 0); return sb_done(&b); }
    if (!strcasecmp(f, "Yes/No")) return bb_str_from_c(bb_v_to_double(v) != 0 ? "Yes" : "No");
    if (!strcasecmp(f, "True/False")) return bb_str_from_c(bb_v_to_double(v) != 0 ? "True" : "False");
    if (!strcasecmp(f, "On/Off")) return bb_str_from_c(bb_v_to_double(v) != 0 ? "On" : "Off");
    if (!strcasecmp(f, "General Date")) return bb_str_from_date(bb_v_to_date(v));
    if (!strcasecmp(f, "Long Date")) { fmt_date(&b, "dddddd", bb_v_to_date(v)); return sb_done(&b); }
    if (!strcasecmp(f, "Medium Date")) { fmt_date(&b, "dd-mmm-yy", bb_v_to_date(v)); return sb_done(&b); }
    if (!strcasecmp(f, "Short Date")) { fmt_date(&b, "ddddd", bb_v_to_date(v)); return sb_done(&b); }
    if (!strcasecmp(f, "Long Time")) { fmt_date(&b, "ttttt", bb_v_to_date(v)); return sb_done(&b); }
    if (!strcasecmp(f, "Medium Time")) { fmt_date(&b, "hh:nn AM/PM", bb_v_to_date(v)); return sb_done(&b); }
    if (!strcasecmp(f, "Short Time")) { fmt_date(&b, "hh:nn", bb_v_to_date(v)); return sb_done(&b); }

    if (v->type == BB_DATE || (is_date_fmt(f) && (v->type != BB_STRING || bb_isdate(v)))) {
        fmt_date(&b, f, bb_v_to_date(v));
        return sb_done(&b);
    }
    if (v->type == BB_STRING && !bb_v_is_numeric(v)) return fmt_string(f, v->u.s);
    if ((strchr(f, '@') || strchr(f, '&')) && !strpbrk(f, "0#")) {
        bb_str *s = bb_v_to_str(v), *r = fmt_string(f, s);
        bb_str_release(s);
        return r;
    }
    if (v->type == BB_STRING && (strchr(f, '@') || strchr(f, '&') || strchr(f, '<') || strchr(f, '>'))) return fmt_string(f, v->u.s);
    /* numeric with sections */
    x = bb_v_to_double(v);
    {
        const char *sec[4];
        size_t slen[4];
        int ns = 0;
        const char *p = f, *st = f;
        for (;; p++) {
            if (*p == '"') { p++; while (*p && *p != '"') p++; if (!*p) p--; continue; }
            if (*p == '\\' && p[1]) { p++; continue; }
            if (*p == ';' || *p == 0) {
                if (ns < 4) { sec[ns] = st; slen[ns] = (size_t)(p - st); ns++; }
                if (!*p) break;
                st = p + 1;
            }
        }
        if (x < 0 && ns >= 2 && slen[1]) fmt_numeric(&b, sec[1], slen[1], -x, 0);
        else if (x == 0 && ns >= 3 && slen[2]) fmt_numeric(&b, sec[2], slen[2], 0, 0);
        else fmt_numeric(&b, sec[0], slen[0], fabs(x), x < 0 && !(ns >= 2 && slen[1]));
    }
    if (!b.p) return NULL;
    return sb_done(&b);
}
