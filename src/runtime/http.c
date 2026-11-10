/* http.c - HTTP/1.1 client (see http.h): one connection per request ("Connection: close"),
 * Content-Length, chunked and until-close bodies, redirects 301/302/303/307/308. */
#include "http.h"
#include "net.h"
#include "zio.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* case-insensitive strstr (strcasestr isn't in C99, nor in every libc) */
static const char *icontains(const char *h, const char *n)
{
    size_t nl = strlen(n);
    for (; h && *h; h++)
        if (!strncasecmp(h, n, nl)) return h;
    return NULL;
}

static int has_header(const char *headers, const char *name)
{
    char *v = headers ? bb_http_header(headers, name) : NULL;
    int r = v != NULL;
    free(v);
    return r;
}

static char *xdup(const char *s, size_t n)
{
    char *o = malloc(n + 1);
    if (!o) return NULL;
    memcpy(o, s, n);
    o[n] = 0;
    return o;
}

int bb_http_parse_url(const char *url, int *tls, char **host, int *port, char **path)
{
    const char *p;
    *host = *path = NULL;
    if (!strncasecmp(url, "http://", 7)) {
        *tls = 0;
        *port = 80;
        p = url + 7;
    } else if (!strncasecmp(url, "https://", 8)) {
        *tls = 1;
        *port = 443;
        p = url + 8;
    } else
        return BB_E_NET_URL;
    const char *end = p + strcspn(p, "/?#");
    const char *at = memchr(p, '@', end - p);       /* user:pass@ isn't supported: skip it */
    if (at) p = at + 1;
    const char *hs = p, *he = end;
    if (*p == '[') {                                 /* [IPv6] */
        const char *rb = memchr(p, ']', end - p);
        if (!rb) return BB_E_NET_URL;
        hs = p + 1;
        he = rb;
        p = rb + 1;
    } else {
        const char *colon = memchr(p, ':', end - p);
        if (colon) he = colon;
        p = colon ? colon : end;
    }
    if (*p == ':') {
        char *e;
        long v = strtol(p + 1, &e, 10);
        if (e == p + 1 || e != end || v <= 0 || v > 65535) return BB_E_NET_URL;
        *port = (int)v;
    }
    if (he <= hs) return BB_E_NET_URL;
    *host = xdup(hs, he - hs);
    const char *frag = strchr(end, '#');
    size_t pl = frag ? (size_t)(frag - end) : strlen(end);
    if (pl == 0 || *end == '?') {
        char *pp = malloc(pl + 2);
        pp[0] = '/';
        memcpy(pp + 1, end, pl);
        pp[pl + 1] = 0;
        *path = pp;
    } else
        *path = xdup(end, pl);
    return 0;
}

char *bb_http_header(const char *headers, const char *name)
{
    size_t nl = strlen(name);
    const char *p = headers;
    while (p && *p) {
        const char *eol = strstr(p, "\r\n");
        if (!eol) eol = p + strlen(p);
        if ((size_t)(eol - p) > nl && !strncasecmp(p, name, nl) && p[nl] == ':') {
            const char *v = p + nl + 1;
            while (v < eol && (*v == ' ' || *v == '\t')) v++;
            const char *ve = eol;
            while (ve > v && (ve[-1] == ' ' || ve[-1] == '\t')) ve--;
            return xdup(v, ve - v);
        }
        p = *eol ? eol + 2 : eol;
    }
    return NULL;
}

void bb_http_resp_free(bb_http_resp *r)
{
    free(r->status_text);
    free(r->headers);
    free(r->body);
    free(r->final_url);
    memset(r, 0, sizeof *r);
}

/* --- a buffered reader on a connection ---------------------------------------------------- */

typedef struct {
    bb_net *n;
    char buf[16384];
    int have, pos;
    int timeout;
    char *err;
    int errlen;
    int eof;
} rd;

/* fill the buffer: >0 bytes now buffered, 0 end of stream, <0 -error */
static int fill(rd *r)
{
    if (r->pos < r->have) return r->have - r->pos;
    if (r->eof) return 0;
    int k = bb_net_read(r->n, r->buf, sizeof r->buf, r->timeout, r->err, r->errlen);
    if (k <= 0) {
        if (k == 0) r->eof = 1;
        return k;
    }
    r->have = k;
    r->pos = 0;
    return k;
}

/* a line ending in \n (without \r\n), malloc'd; NULL at the end, *rc set on error */
static char *read_line(rd *r, int *rc)
{
    size_t cap = 128, len = 0;
    char *l = malloc(cap);
    *rc = 0;
    for (;;) {
        int k = fill(r);
        if (k < 0) {
            *rc = -k;
            free(l);
            return NULL;
        }
        if (k == 0) {
            if (len == 0) {
                free(l);
                return NULL;
            }
            break;
        }
        char c = r->buf[r->pos++];
        if (c == '\n') break;
        if (len + 2 > cap) l = realloc(l, cap *= 2);
        if (len > 65536) {
            *rc = BB_E_NET_PROTOCOL;
            snprintf(r->err, r->errlen, "a header line is too long");
            free(l);
            return NULL;
        }
        l[len++] = c;
    }
    if (len && l[len - 1] == '\r') len--;
    l[len] = 0;
    return l;
}

/* --- body sinks --------------------------------------------------------------------------- */

typedef struct {
    const bb_http_req *req;
    bb_http_resp *resp;
    size_t cap;
    long total;
    char *err;
    int errlen;
} sink;

static int put(sink *s, const char *p, long n)
{
    if (n <= 0) return 0;
    if (s->req->out) {
        if (fwrite(p, 1, n, s->req->out) != (size_t)n) {
            snprintf(s->err, s->errlen, "can't write the downloaded data to the file");
            return BB_E_NET_IO;
        }
    } else {
        if ((size_t)(s->resp->body_len + n + 1) > s->cap) {
            size_t nc = s->cap ? s->cap : 16384;
            while (nc < (size_t)(s->resp->body_len + n + 1)) nc *= 2;
            char *nb = realloc(s->resp->body, nc);
            if (!nb) {
                snprintf(s->err, s->errlen, "out of memory for the response body");
                return 7;
            }
            s->resp->body = nb;
            s->cap = nc;
        }
        memcpy(s->resp->body + s->resp->body_len, p, n);
        s->resp->body[s->resp->body_len + n] = 0;
    }
    s->resp->body_len += n;
    if (s->req->progress && s->req->progress(s->req->progress_ud, s->resp->body_len, s->total)) {
        snprintf(s->err, s->errlen, "cancelled");
        return 18;                                  /* VB: "User interrupt occurred" */
    }
    return 0;
}

/* copy n bytes (n < 0: until the end of the stream) from the reader to the sink */
static int copy_body(rd *r, sink *s, long n)
{
    while (n != 0) {
        int k = fill(r);
        if (k < 0) return -k;
        if (k == 0) {
            if (n < 0) return 0;
            snprintf(r->err, r->errlen, "the connection closed %ld bytes before the end of the body", n);
            return BB_E_NET_PROTOCOL;
        }
        long take = n < 0 || n > k ? k : n;
        int e = put(s, r->buf + r->pos, take);
        if (e) return e;
        r->pos += (int)take;
        if (n > 0) n -= take;
    }
    return 0;
}

static int read_chunked(rd *r, sink *s)
{
    for (;;) {
        int rc;
        char *l = read_line(r, &rc);
        if (!l) {
            if (!rc) {
                snprintf(r->err, r->errlen, "the connection closed inside a chunked body");
                rc = BB_E_NET_PROTOCOL;
            }
            return rc;
        }
        char *e;
        long n = strtol(l, &e, 16);
        int bad = e == l || n < 0;
        free(l);
        if (bad) {
            snprintf(r->err, r->errlen, "bad chunk size in the response");
            return BB_E_NET_PROTOCOL;
        }
        if (n == 0) {
            /* trailers up to the empty line */
            while ((l = read_line(r, &rc)) && *l) free(l);
            free(l);
            return rc;
        }
        rc = copy_body(r, s, n);
        if (rc) return rc;
        l = read_line(r, &rc);                      /* the CRLF after the chunk */
        free(l);
        if (rc) return rc;
    }
}

/* --- one request -------------------------------------------------------------------------- */

/* Content-Encoding gzip / deflate: replace the body with its unpacked bytes */
static int unpack(bb_http_resp *resp, char *err, int errlen)
{
    char *ce = bb_http_header(resp->headers, "Content-Encoding");
    if (!ce) return 0;
    int fmt = icontains(ce, "gzip") ? BB_Z_GZIP : icontains(ce, "deflate") ? BB_Z_ZLIB : -1;
    free(ce);
    if (fmt < 0) return 0;                          /* identity, or one we didn't ask for */
    char *out = NULL;
    long outlen = 0;
    char zerr[200];
    int rc = bb_z_decompress(resp->body, resp->body_len, fmt, 0, &out, &outlen, NULL, zerr, sizeof zerr);
    if (rc && fmt == BB_Z_ZLIB)                     /* "deflate" sent as raw deflate (old IIS) */
        rc = bb_z_decompress(resp->body, resp->body_len, BB_Z_RAW, 0, &out, &outlen, NULL, zerr, sizeof zerr);
    if (rc) {
        snprintf(err, errlen, "the compressed answer can't be unpacked: %s", zerr);
        return BB_E_NET_PROTOCOL;
    }
    out = realloc(out, (size_t)outlen + 1);         /* NUL-terminated like every body */
    out[outlen] = 0;
    free(resp->body);
    resp->body = out;
    resp->body_len = outlen;
    return 0;
}

static int once(const bb_http_req *req, const char *url, const char *method, int send_body, bb_http_resp *resp,
                char **location, char *err, int errlen)
{
    int tls, port;
    char *host, *path;
    *location = NULL;
    if (bb_http_parse_url(url, &tls, &host, &port, &path)) {
        snprintf(err, errlen, "bad URL: %s", url);
        return BB_E_NET_URL;
    }
    bb_tls_opts o = { req->verify, req->ca_file };
    bb_http_session *ses = req->session;
    /* keep-alive: this task can reuse (and later keep) the session's connection */
    int pool = ses && ses->keep_alive && (!ses->conn || bb_net_owned(ses->conn));
    bb_net *n = NULL;
    int reused = 0, kept = 0, rc;
    if (ses) ses->reused = 0;
    if (pool && ses->conn) {
        if (ses->conn_tls == tls && ses->conn_port == port && !strcasecmp(ses->conn_host, host)) {
            n = ses->conn;
            reused = kept = 1;
        } else {
            bb_net_close(ses->conn);
        }
        ses->conn = NULL;                           /* back in the session only if it stays usable */
        free(ses->conn_host);
        ses->conn_host = NULL;
    }
    char *cookies = ses && ses->use_cookies && !has_header(req->headers, "Cookie") ?
                    bb_http_cookie_header(ses, host, path, tls) : NULL;
retry:
    if (!n) {
        rc = bb_net_open(host, port, tls, &o, req->timeout_ms, &n, err, errlen);
        if (rc) {
            free(host);
            free(path);
            free(cookies);
            return rc;
        }
    }
    /* the request */
    size_t cap = 512 + strlen(path) + strlen(host) + (req->headers ? strlen(req->headers) : 0) +
                 (req->user_agent ? strlen(req->user_agent) : 0) + (cookies ? strlen(cookies) : 0);
    char *q = malloc(cap);
    int dflt = (tls && port == 443) || (!tls && port == 80);
    int v6 = strchr(host, ':') != NULL;
    char portpart[16] = "";
    if (!dflt) snprintf(portpart, sizeof portpart, ":%d", port);
    int ql = snprintf(q, cap, "%s %s HTTP/1.1\r\nHost: %s%s%s%s\r\n%s", method, path,
                      v6 ? "[" : "", host, v6 ? "]" : "", portpart, pool ? "" : "Connection: close\r\n");
    if (cookies) ql += snprintf(q + ql, cap - ql, "Cookie: %s\r\n", cookies);
    if (req->user_agent && *req->user_agent && !has_header(req->headers, "User-Agent"))
        ql += snprintf(q + ql, cap - ql, "User-Agent: %s\r\n", req->user_agent);
    if (!has_header(req->headers, "Accept"))
        ql += snprintf(q + ql, cap - ql, "Accept: */*\r\n");
    /* compressed answers: only into memory (GetToFile streams), and not when the program asks
       for an encoding itself (then it gets the bytes as sent) */
    int gz = req->decompress && !req->out && !has_header(req->headers, "Accept-Encoding") && bb_z_available(NULL, 0);
    if (gz) ql += snprintf(q + ql, cap - ql, "Accept-Encoding: gzip, deflate\r\n");
    if (send_body && req->body)
        ql += snprintf(q + ql, cap - ql, "Content-Length: %ld\r\n", req->body_len);
    else if (send_body && (!strcasecmp(method, "POST") || !strcasecmp(method, "PUT")))
        ql += snprintf(q + ql, cap - ql, "Content-Length: 0\r\n");
    if (req->headers) ql += snprintf(q + ql, cap - ql, "%s", req->headers);
    ql += snprintf(q + ql, cap - ql, "\r\n");
    rc = bb_net_write(n, q, ql, req->timeout_ms, err, errlen);
    free(q);
    if (!rc && send_body && req->body && req->body_len)
        rc = bb_net_write(n, req->body, (int)req->body_len, req->timeout_ms, err, errlen);
    if (rc && reused) {                             /* the server closed the kept connection */
        bb_net_close(n);
        n = NULL;
        reused = kept = 0;
        goto retry;
    }
    if (rc) {
        bb_net_close(n);
        free(host);
        free(path);
        free(cookies);
        return rc;
    }

    /* the answer */
    rd *r = calloc(1, sizeof *r);
    r->n = n;
    r->timeout = req->timeout_ms;
    r->err = err;
    r->errlen = errlen;
    char *line;
    int http11 = 0, delimited = 0;
    for (;;) {                                      /* skip 1xx interim answers */
        line = read_line(r, &rc);
        if (!line && reused && r->have == 0 && rc != BB_E_NET_TIMEOUT) {   /* closed while idle */
            free(r);
            bb_net_close(n);
            n = NULL;
            reused = kept = 0;
            goto retry;
        }
        reused = 0;
        if (!line) {
            if (!rc) {
                snprintf(err, errlen, "the server closed the connection without an answer");
                rc = BB_E_NET_PROTOCOL;
            }
            goto out;
        }
        if (strncmp(line, "HTTP/", 5) || !strchr(line, ' ')) {
            snprintf(err, errlen, "not an HTTP answer");
            free(line);
            rc = BB_E_NET_PROTOCOL;
            goto out;
        }
        char *sp = strchr(line, ' ');
        http11 = !strncmp(line, "HTTP/1.1", 8);
        resp->status = atoi(sp + 1);
        char *st = strchr(sp + 1, ' ');
        free(resp->status_text);
        resp->status_text = strdup(st ? st + 1 : "");
        free(line);
        /* headers */
        size_t hcap = 1024, hlen = 0;
        free(resp->headers);
        resp->headers = malloc(hcap);
        resp->headers[0] = 0;
        while ((line = read_line(r, &rc)) && *line) {
            size_t ll = strlen(line);
            if (hlen + ll + 3 > hcap) {
                while (hlen + ll + 3 > hcap) hcap *= 2;
                resp->headers = realloc(resp->headers, hcap);
            }
            memcpy(resp->headers + hlen, line, ll);
            hlen += ll;
            memcpy(resp->headers + hlen, "\r\n", 3);
            hlen += 2;
            free(line);
        }
        free(line);
        if (rc) goto out;
        if (resp->status >= 200 || resp->status == 101) break;
    }
    if (ses && ses->use_cookies) bb_http_cookies_from_response(ses, host, path, resp->headers);

    int redirect = req->follow_redirects && (resp->status == 301 || resp->status == 302 || resp->status == 303 ||
                                             resp->status == 307 || resp->status == 308);
    if (redirect) {
        *location = bb_http_header(resp->headers, "Location");
        if (*location) goto out;                    /* the body of a redirect isn't needed */
    }
    {
        sink s = { req, resp, 0, -1, err, errlen };
        char *te = bb_http_header(resp->headers, "Transfer-Encoding");
        char *cl = bb_http_header(resp->headers, "Content-Length");
        int nobody = !strcasecmp(method, "HEAD") || resp->status == 204 || resp->status == 304 ||
                     (resp->status >= 100 && resp->status < 200);
        if (cl) s.total = atol(cl);
        free(resp->body);
        resp->body = NULL;
        resp->body_len = 0;
        if (!req->out) {                            /* an empty body is "" not NULL */
            resp->body = calloc(1, 1);
            s.cap = 1;
        }
        if (nobody) rc = 0;
        else if (te && icontains(te, "chunked")) rc = read_chunked(r, &s);
        else if (cl) rc = copy_body(r, &s, atol(cl));
        else rc = copy_body(r, &s, -1);
        delimited = nobody || (te && icontains(te, "chunked")) || cl;
        free(te);
        free(cl);
        resp->wire_len = resp->body_len;
        if (!rc && gz && resp->body && resp->body_len) rc = unpack(resp, err, errlen);
    }
    /* keep the connection: HTTP/1.1, the body's end known and read, no "Connection: close",
       and nothing more already received */
    if (pool && !rc && http11 && delimited && r->pos == r->have && resp->status != 101) {
        char *conn = bb_http_header(resp->headers, "Connection");
        int close = conn && icontains(conn, "close");
        free(conn);
        if (!close) {
            ses->conn = n;
            ses->conn_host = host;
            ses->conn_port = port;
            ses->conn_tls = tls;
            n = NULL;
            host = NULL;
        }
    }
out:
    if (ses) ses->reused = kept;
    free(r);
    if (n) bb_net_close(n);
    free(host);
    free(path);
    free(cookies);
    return rc;
}

/* a redirect target relative to the current URL */
static char *resolve(const char *base, const char *loc)
{
    if (!strncasecmp(loc, "http://", 7) || !strncasecmp(loc, "https://", 8)) return strdup(loc);
    const char *scheme_end = strstr(base, "://");
    if (!scheme_end) return strdup(loc);
    const char *hostp = scheme_end + 3;
    if (loc[0] == '/' && loc[1] == '/') {           /* //host/path: same scheme */
        size_t sl = hostp - base - 2;
        char *o = malloc(sl + strlen(loc) + 1);
        memcpy(o, base, sl);
        strcpy(o + sl, loc);
        return o;
    }
    const char *path = hostp + strcspn(hostp, "/?#");
    if (loc[0] == '/') {
        size_t bl = path - base;
        char *o = malloc(bl + strlen(loc) + 1);
        memcpy(o, base, bl);
        strcpy(o + bl, loc);
        return o;
    }
    /* relative to the directory of the current path */
    const char *q = path + strcspn(path, "?#");
    const char *slash = q;
    while (slash > path && slash[-1] != '/') slash--;
    size_t bl = slash - base;
    char *o = malloc(bl + strlen(loc) + 2);
    memcpy(o, base, bl);
    if (slash == path) o[bl++] = '/';
    strcpy(o + bl, loc);
    return o;
}

int bb_http_do(const bb_http_req *req, bb_http_resp *resp, char *err, int errlen)
{
    memset(resp, 0, sizeof *resp);
    char *url = strdup(req->url ? req->url : "");
    const char *method = req->method && *req->method ? req->method : "GET";
    char *meth = strdup(method);
    for (char *p = meth; *p; p++) *p = (char)toupper((unsigned char)*p);
    int send_body = 1;
    int rc;
    long start = req->out ? ftell(req->out) : 0;
    for (;;) {
        char *loc = NULL;
        if (req->out && start >= 0) fseek(req->out, start, SEEK_SET);   /* a redirect's body never landed */
        rc = once(req, url, meth, send_body, resp, &loc, err, errlen);
        if (rc || !loc) {
            free(loc);
            break;
        }
        if (resp->redirects >= (req->max_redirects > 0 ? req->max_redirects : 0)) {
            snprintf(err, errlen, "more than %d redirects (last to %s)", req->max_redirects, loc);
            free(loc);
            rc = BB_E_NET_REDIRECTS;
            break;
        }
        char *next = resolve(url, loc);
        free(loc);
        free(url);
        url = next;
        resp->redirects++;
        /* 303 (and, as browsers do, 301/302 after a POST) continue with a GET without body */
        if (resp->status == 303 || ((resp->status == 301 || resp->status == 302) && strcmp(meth, "GET") &&
                                    strcmp(meth, "HEAD"))) {
            free(meth);
            meth = strdup("GET");
            send_body = 0;
        }
    }
    free(meth);
    resp->final_url = url;
    return rc;
}
