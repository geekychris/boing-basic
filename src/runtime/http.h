/* http.h - a small HTTP/1.1 client on net.h, used by the Http class (http_obj.c).
 * Portable: plain C on net.h; no OS calls. */
#ifndef BB_HTTP_H
#define BB_HTTP_H

#include <stdio.h>

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
} bb_http_req;

typedef struct bb_http_resp {
    int status;                 /* 200, 404, ... */
    char *status_text;          /* "OK" */
    char *headers;              /* the response headers as received, "Name: value\r\n" lines */
    char *body;                 /* NUL-terminated as well (len body_len); NULL when sent to a file */
    long body_len;              /* bytes received (also when sent to a file) */
    char *final_url;            /* the URL after redirects */
    int redirects;
} bb_http_resp;

/* Do the request (following redirects as asked). 0, or an error number (net.h) with err set.
 * resp is filled in either way as far as it got; free it with bb_http_resp_free. */
int bb_http_do(const bb_http_req *req, bb_http_resp *resp, char *err, int errlen);
void bb_http_resp_free(bb_http_resp *resp);

/* A response header's value (case-insensitive name), malloc'd; NULL if absent. */
char *bb_http_header(const char *headers, const char *name);

/* Split a URL: returns 0 or BB_E_NET_URL. host and path are malloc'd. */
int bb_http_parse_url(const char *url, int *tls, char **host, int *port, char **path);

#endif
