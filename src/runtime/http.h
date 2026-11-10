/* http.h - a small HTTP/1.1 client on net.h, used by the Http class (http_obj.c).
 * Portable: plain C on net.h; no OS calls. */
#ifndef BB_HTTP_H
#define BB_HTTP_H

#include <stdio.h>

struct bb_net;

/* A session (one per Http object): its cookie jar and the connection kept open for the next
 * request to the same server. Zero-initialise, then set the switches. */
typedef struct bb_http_cookie {
    char *name, *value;
    char *domain;               /* lower case, no leading dot */
    char *path;
    int host_only;              /* no Domain attribute: only for exactly that host */
    int secure;                 /* only over HTTPS */
    long long expires;          /* Unix time (UTC), 0 = until the program ends */
} bb_http_cookie;

typedef struct bb_http_session {
    int use_cookies;            /* store Set-Cookie answers and send them back */
    int keep_alive;             /* keep the connection open for the next request */
    bb_http_cookie *cookies;
    int ncookies, capcookies;
    struct bb_net *conn;        /* the open connection, to conn_host:conn_port (TLS if conn_tls) */
    char *conn_host;
    int conn_port, conn_tls;
    int reused;                 /* the last request went over a kept connection (for tests) */
} bb_http_session;

typedef struct bb_http_req {
    const char *method;         /* "GET", "POST", ... */
    const char *url;            /* http://host[:port]/path or https://... */
    const char *body;           /* request body (may contain NULs), or NULL */
    long body_len;
    const char *headers;        /* extra request headers, "Name: value\r\n" lines, or NULL */
    const char *user_agent;
    int timeout_ms;             /* per connect / read / write */
    int follow_redirects;
    int max_redirects;
    int verify;                 /* TLS certificate checks */
    const char *ca_file;
    FILE *out;                  /* the body goes to this file instead of memory, if set */
    /* progress: called as data arrives (total = -1 when unknown); nonzero return cancels */
    int (*progress)(void *ud, long got, long total);
    void *progress_ud;
    bb_http_session *session;   /* cookies and keep-alive, or NULL for neither */
    int decompress;             /* ask for gzip/deflate (when zlib is there) and unpack the answer */
} bb_http_req;

typedef struct bb_http_resp {
    int status;                 /* 200, 404, ... */
    char *status_text;          /* "OK" */
    char *headers;              /* the response headers as received, "Name: value\r\n" lines */
    char *body;                 /* NUL-terminated as well (len body_len); NULL when sent to a file */
    long body_len;              /* bytes received (also when sent to a file) */
    char *final_url;            /* the URL after redirects */
    int redirects;
    long wire_len;              /* body bytes as received (compressed, if it was) */
} bb_http_resp;

/* Do the request (following redirects as asked). 0, or an error number (net.h) with err set.
 * resp is filled in either way as far as it got; free it with bb_http_resp_free. */
int bb_http_do(const bb_http_req *req, bb_http_resp *resp, char *err, int errlen);
void bb_http_resp_free(bb_http_resp *resp);

/* A response header's value (case-insensitive name), malloc'd; NULL if absent. */
char *bb_http_header(const char *headers, const char *name);

/* Split a URL: returns 0 or BB_E_NET_URL. host and path are malloc'd. */
int bb_http_parse_url(const char *url, int *tls, char **host, int *port, char **path);

/* sessions (http_cookie.c) */
void bb_http_session_close(bb_http_session *s);         /* close the kept connection */
void bb_http_session_free(bb_http_session *s);          /* and forget the cookies */
void bb_http_cookies_from_response(bb_http_session *s, const char *host, const char *rpath, const char *headers);
char *bb_http_cookie_header(bb_http_session *s, const char *host, const char *rpath, int tls); /* malloc'd or NULL */
int bb_http_cookie_set(bb_http_session *s, const char *name, const char *value, const char *domain, const char *path);
const char *bb_http_cookie_get(bb_http_session *s, const char *name, const char *host);
int bb_http_cookie_count(bb_http_session *s);
void bb_http_cookies_clear(bb_http_session *s);
char *bb_http_cookies_text(bb_http_session *s);         /* cookies.txt layout, malloc'd */
int bb_http_cookies_load(bb_http_session *s, const char *text);

#endif
