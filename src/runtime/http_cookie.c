/* http_cookie.c - the cookie jar of an Http object's session (http.h): Set-Cookie answers are
 * stored (RFC 6265: Domain, Path, Expires, Max-Age, Secure; host-only cookies without Domain)
 * and sent back with the requests they match. Plain C, no OS calls; the time comes from
 * isodate.c's UTC clock. */
#include "http.h"
#include "boing.h"
#include "net.h"
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>

#define MAX_COOKIES 300

static long long now_utc(void) { return (long long)bb_unixtime(bb_nowutc()); }

static char *dupn(const char *s, size_t n)
{
    char *o = malloc(n + 1);
    memcpy(o, s, n);
    o[n] = 0;
    return o;
}

static char *trimdup(const char *a, const char *b)
{
    while (a < b && (*a == ' ' || *a == '\t')) a++;
    while (b > a && (b[-1] == ' ' || b[-1] == '\t')) b--;
    return dupn(a, (size_t)(b - a));
}

static void lower(char *s) { for (; *s; s++) *s = (char)tolower((unsigned char)*s); }

static void cookie_free(bb_http_cookie *c)
{
    free(c->name); free(c->value); free(c->domain); free(c->path);
}

static void remove_at(bb_http_session *s, int i)
{
    cookie_free(&s->cookies[i]);
    memmove(&s->cookies[i], &s->cookies[i + 1], sizeof s->cookies[0] * (size_t)(s->ncookies - i - 1));
    s->ncookies--;
}

static void purge(bb_http_session *s)
{
    long long t = now_utc();
    for (int i = s->ncookies - 1; i >= 0; i--)
        if (s->cookies[i].expires && s->cookies[i].expires <= t) remove_at(s, i);
}

/* store c (taking its strings), replacing one with the same name, domain and path */
static void store(bb_http_session *s, bb_http_cookie *c)
{
    for (int i = 0; i < s->ncookies; i++) {
        bb_http_cookie *o = &s->cookies[i];
        if (!strcmp(o->name, c->name) && !strcmp(o->domain, c->domain) && !strcmp(o->path, c->path)) {
            remove_at(s, i);
            break;
        }
    }
    if (c->expires && c->expires <= now_utc()) {        /* an expiry in the past deletes it */
        cookie_free(c);
        return;
    }
    if (s->ncookies >= MAX_COOKIES) remove_at(s, 0);
    if (s->ncookies == s->capcookies) {
        s->capcookies = s->capcookies ? s->capcookies * 2 : 16;
        s->cookies = realloc(s->cookies, sizeof s->cookies[0] * (size_t)s->capcookies);
    }
    s->cookies[s->ncookies++] = *c;
}

static int domain_match(const char *host, const char *domain)
{
    size_t hl = strlen(host), dl = strlen(domain);
    if (!strcasecmp(host, domain)) return 1;
    return hl > dl && host[hl - dl - 1] == '.' && !strcasecmp(host + hl - dl, domain);
}

static int path_match(const char *rpath, const char *cpath)
{
    size_t cl = strlen(cpath);
    if (strncmp(rpath, cpath, cl)) return 0;
    return cpath[cl - 1] == '/' || rpath[cl] == 0 || rpath[cl] == '/' || rpath[cl] == '?';
}

/* the directory of a request path ("/a/b?x" -> "/a"), for cookies without Path */
static char *default_path(const char *rpath)
{
    size_t n = strcspn(rpath, "?#");
    const char *e = rpath + n;
    if (*rpath != '/') return strdup("/");
    while (e > rpath && e[-1] != '/') e--;
    if (e - rpath <= 1) return strdup("/");
    return dupn(rpath, (size_t)(e - rpath - 1));
}

/* "Wed, 21 Oct 2015 07:28:00 GMT", "Wednesday, 21-Oct-15 07:28:00 GMT", "Wed Oct 21 07:28:00 2015" */
static long long parse_http_date(const char *p)
{
    static const char *mon = "janfebmaraprmayjunjulaugsepoctnovdec";
    long day = -1, year = -1, h = -1, mi = 0, se = 0;
    int month = -1;
    while (*p) {
        while (*p && !isalnum((unsigned char)*p)) p++;
        const char *t = p;
        while (isalnum((unsigned char)*p) || *p == ':') p++;
        size_t n = (size_t)(p - t);
        if (!n) break;
        if (memchr(t, ':', n) && h < 0) {
            sscanf(t, "%ld:%ld:%ld", &h, &mi, &se);
        } else if (isdigit((unsigned char)*t)) {
            long v = atol(t);
            if (day < 0 && n <= 2) day = v;
            else if (year < 0) year = v;
        } else if (n >= 3 && month < 0) {
            for (int m = 0; m < 12; m++)
                if (!strncasecmp(t, mon + m * 3, 3)) month = m + 1;
        }
    }
    if (day < 1 || month < 1 || year < 0) return -1;
    if (year < 70) year += 2000;
    else if (year < 100) year += 1900;
    if (h < 0) h = 0;
    /* days from 1970-01-01 (H. Hinnant's days_from_civil) */
    long y = year - (month <= 2);
    long era = (y >= 0 ? y : y - 399) / 400;
    long yoe = y - era * 400;
    long doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    long long days = (long long)era * 146097 + doe - 719468;
    return days * 86400 + h * 3600 + mi * 60 + se;
}

/* one Set-Cookie value from a response to host/rpath */
static void set_cookie(bb_http_session *s, const char *host, const char *rpath, const char *v)
{
    const char *semi = strchr(v, ';');
    const char *end = semi ? semi : v + strlen(v);
    const char *eq = memchr(v, '=', (size_t)(end - v));
    if (!eq) return;
    bb_http_cookie c;
    memset(&c, 0, sizeof c);
    c.name = trimdup(v, eq);
    if (!*c.name) { free(c.name); return; }
    c.value = trimdup(eq + 1, end);
    long long maxage_set = 0, maxage = 0, expires = 0;
    while (semi) {
        const char *a = semi + 1;
        semi = strchr(a, ';');
        const char *ae = semi ? semi : a + strlen(a);
        const char *aeq = memchr(a, '=', (size_t)(ae - a));
        char *an = trimdup(a, aeq ? aeq : ae);
        char *av = aeq ? trimdup(aeq + 1, ae) : strdup("");
        if (!strcasecmp(an, "Domain") && *av) {
            free(c.domain);
            c.domain = strdup(av[0] == '.' ? av + 1 : av);
            lower(c.domain);
        } else if (!strcasecmp(an, "Path") && av[0] == '/') {
            free(c.path);
            c.path = strdup(av);
        } else if (!strcasecmp(an, "Max-Age")) {
            maxage_set = 1;
            maxage = atoll(av);
        } else if (!strcasecmp(an, "Expires")) {
            long long t = parse_http_date(av);
            if (t >= 0) expires = t ? t : 1;
        } else if (!strcasecmp(an, "Secure")) {
            c.secure = 1;
        }
        free(an);
        free(av);
    }
    if (c.domain) {
        if (!domain_match(host, c.domain)) { cookie_free(&c); return; }   /* for another site */
    } else {
        c.domain = strdup(host);
        lower(c.domain);
        c.host_only = 1;
    }
    if (!c.path) c.path = default_path(rpath);
    if (maxage_set) c.expires = maxage <= 0 ? 1 : now_utc() + maxage;
    else c.expires = expires;
    store(s, &c);
}

void bb_http_cookies_from_response(bb_http_session *s, const char *host, const char *rpath, const char *headers)
{
    const char *p = headers;
    while (p && *p) {
        const char *e = strstr(p, "\r\n");
        if (!e) e = p + strlen(p);
        if (!strncasecmp(p, "Set-Cookie:", 11)) {
            char *v = trimdup(p + 11, e);
            set_cookie(s, host, rpath, v);
            free(v);
        }
        p = *e ? e + 2 : e;
    }
}

char *bb_http_cookie_header(bb_http_session *s, const char *host, const char *rpath, int tls)
{
    purge(s);
    size_t cap = 64, len = 0;
    char *o = NULL;
    /* longer paths first (RFC 6265 5.4) */
    for (size_t pl = 4096;; ) {
        size_t next = 0;
        for (int i = 0; i < s->ncookies; i++) {
            bb_http_cookie *c = &s->cookies[i];
            size_t l = strlen(c->path);
            if (l < pl && l > next) next = l;
            if (l != pl) continue;
            if (c->secure && !tls) continue;
            if (c->host_only ? strcasecmp(host, c->domain) : !domain_match(host, c->domain)) continue;
            if (!path_match(rpath, c->path)) continue;
            size_t need = strlen(c->name) + strlen(c->value) + 4;
            if (!o) o = malloc(cap);
            while (len + need >= cap) o = realloc(o, cap *= 2);
            len += (size_t)sprintf(o + len, "%s%s=%s", len ? "; " : "", c->name, c->value);
        }
        if (!next) break;
        pl = next;
    }
    return o;
}

int bb_http_cookie_set(bb_http_session *s, const char *name, const char *value, const char *domain,
                       const char *path)
{
    if (!name || !*name || strpbrk(name, "=; \t\r\n") || strpbrk(value, ";\r\n") || !domain || !*domain)
        return -1;
    bb_http_cookie c;
    memset(&c, 0, sizeof c);
    c.name = strdup(name);
    c.value = strdup(value);
    c.domain = strdup(domain[0] == '.' ? domain + 1 : domain);
    lower(c.domain);
    c.path = strdup(path && *path == '/' ? path : "/");
    store(s, &c);
    return 0;
}

const char *bb_http_cookie_get(bb_http_session *s, const char *name, const char *host)
{
    purge(s);
    for (int i = s->ncookies - 1; i >= 0; i--) {
        bb_http_cookie *c = &s->cookies[i];
        if (strcmp(c->name, name)) continue;
        if (host && *host && (c->host_only ? strcasecmp(host, c->domain) : !domain_match(host, c->domain))) continue;
        return c->value;
    }
    return NULL;
}

int bb_http_cookie_count(bb_http_session *s)
{
    purge(s);
    return s->ncookies;
}

void bb_http_cookies_clear(bb_http_session *s)
{
    while (s->ncookies) remove_at(s, s->ncookies - 1);
}

/* the jar as text, one cookie per line in the cookies.txt layout curl and browsers use:
   domain TAB subdomains(TRUE/FALSE) TAB path TAB secure TAB expires(Unix time, 0 = session) TAB name TAB value */
char *bb_http_cookies_text(bb_http_session *s)
{
    purge(s);
    size_t cap = 1, len = 0;
    for (int i = 0; i < s->ncookies; i++) {
        bb_http_cookie *c = &s->cookies[i];
        cap += strlen(c->domain) + strlen(c->path) + strlen(c->name) + strlen(c->value) + 48;
    }
    char *o = malloc(cap);
    o[0] = 0;
    for (int i = 0; i < s->ncookies; i++) {
        bb_http_cookie *c = &s->cookies[i];
        len += (size_t)sprintf(o + len, "%s\t%s\t%s\t%s\t%lld\t%s\t%s\n", c->domain, c->host_only ? "FALSE" : "TRUE",
                               c->path, c->secure ? "TRUE" : "FALSE", c->expires, c->name, c->value);
    }
    return o;
}

/* replace the jar with cookies in that layout ('#' lines and blank lines are skipped); returns
   the number of lines that weren't cookies */
int bb_http_cookies_load(bb_http_session *s, const char *text)
{
    int bad = 0;
    bb_http_cookies_clear(s);
    const char *p = text;
    while (p && *p) {
        const char *e = p + strcspn(p, "\r\n");
        if (e > p && *p != '#') {
            char *f[7];
            int n = 0;
            const char *q = p;
            while (n < 7 && q <= e) {
                const char *t = n < 6 ? memchr(q, '\t', (size_t)(e - q)) : NULL;
                if (!t) t = e;
                f[n++] = dupn(q, (size_t)(t - q));
                q = t + 1;
                if (t == e) break;
            }
            if (n == 7 && *f[0] && *f[5]) {
                bb_http_cookie c;
                memset(&c, 0, sizeof c);
                c.domain = strdup(f[0][0] == '.' ? f[0] + 1 : f[0]);
                lower(c.domain);
                c.host_only = strcasecmp(f[1], "TRUE") != 0;
                c.path = strdup(f[2][0] == '/' ? f[2] : "/");
                c.secure = !strcasecmp(f[3], "TRUE");
                c.expires = atoll(f[4]);
                c.name = strdup(f[5]);
                c.value = strdup(f[6]);
                store(s, &c);
            } else {
                bad++;
            }
            for (int i = 0; i < n; i++) free(f[i]);
        }
        p = e;
        while (*p == '\r' || *p == '\n') p++;
    }
    return bad;
}

/* ---------------------------------------------------------------- the session */

void bb_http_session_close(bb_http_session *s)
{
    if (!s->conn || !bb_net_owned(s->conn)) return;   /* another task's socket stays theirs */
    bb_net_close(s->conn);
    s->conn = NULL;
    free(s->conn_host);
    s->conn_host = NULL;
}

void bb_http_session_free(bb_http_session *s)
{
    bb_http_session_close(s);
    bb_http_cookies_clear(s);
    free(s->cookies);
    s->cookies = NULL;
    s->capcookies = 0;
}
