/* http_obj.c - Boing.Http, the HTTP/HTTPS client class (docs/http.md):
 *
 *     Dim h As Http
 *     Set h = New Http                 ' or CreateObject("Http")
 *     h.SetHeader "Accept", "application/json"
 *     s = h.Get("https://example.com/")
 *     If h.Status = 200 Then Print Len(s); " bytes"
 *
 * Requests are synchronous; network and TLS failures raise run-time errors 31101-31110 (net.h),
 * while HTTP error statuses (404, 500, ...) are answers: check Status. The body is kept as bytes
 * (a String; no character set conversion). */
#include "boing.h"
#include "http.h"
#include "net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum {
    M_GET = 1, M_POST, M_PUT, M_DELETE, M_HEAD, M_SEND, M_GETTOFILE, M_SETHEADER, M_CLEARHEADERS,
    M_RESPONSEHEADER, M_TLSAVAILABLE,
    P_STATUS, P_STATUSTEXT, P_RESPONSETEXT, P_RESPONSEHEADERS, P_URL, P_CONTENTTYPE, P_TIMEOUT,
    P_FOLLOWREDIRECTS, P_MAXREDIRECTS, P_VERIFYCERTIFICATE, P_CACERTFILE, P_USERAGENT, P_BYTESRECEIVED,
    P_REDIRECTS,
};

static const struct { const char *name; int id; } members[] = {
    {"Get", M_GET}, {"Post", M_POST}, {"Put", M_PUT}, {"Delete", M_DELETE}, {"Head", M_HEAD},
    {"Send", M_SEND}, {"GetToFile", M_GETTOFILE}, {"SetHeader", M_SETHEADER}, {"ClearHeaders", M_CLEARHEADERS},
    {"ResponseHeader", M_RESPONSEHEADER}, {"TlsAvailable", M_TLSAVAILABLE},
    {"Status", P_STATUS}, {"StatusText", P_STATUSTEXT}, {"ResponseText", P_RESPONSETEXT},
    {"ResponseHeaders", P_RESPONSEHEADERS}, {"Url", P_URL}, {"ContentType", P_CONTENTTYPE},
    {"Timeout", P_TIMEOUT}, {"FollowRedirects", P_FOLLOWREDIRECTS}, {"MaxRedirects", P_MAXREDIRECTS},
    {"VerifyCertificate", P_VERIFYCERTIFICATE}, {"CACertFile", P_CACERTFILE}, {"UserAgent", P_USERAGENT},
    {"BytesReceived", P_BYTESRECEIVED}, {"Redirects", P_REDIRECTS},
};

typedef struct {
    bb_obj hdr;
    char *headers;              /* request headers, "Name: value\r\n" lines */
    char *ca_file, *user_agent;
    int timeout_ms, follow, max_redirects, verify;
    bb_http_resp resp;
    int have_resp;
} http_obj;

static char *dupstr(const char *s) { return strdup(s ? s : ""); }

/* argument i as a malloc'd C string; *len the byte length (Strings may hold NULs) */
static char *arg_str(int argc, bb_value *argv, int i, long *len)
{
    if (i >= argc) {
        if (len) *len = 0;
        return dupstr("");
    }
    bb_value t;
    const bb_value *v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_ERROR && (v->flags & BB_VF_MISSING)) {
        if (len) *len = 0;
        return dupstr("");
    }
    bb_str *s = bb_v_to_str(v);
    long n = bb_str_len(s);
    char *o = malloc(n + 1);
    memcpy(o, bb_str_ptr(s), n);
    o[n] = 0;
    bb_str_release(s);
    if (len) *len = n;
    return o;
}

static int present(int argc, bb_value *argv, int i)
{
    if (i >= argc) return 0;
    bb_value t;
    const bb_value *v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static void remove_header(http_obj *h, const char *name)
{
    size_t nl = strlen(name);
    char *p = h->headers;
    while (p && *p) {
        char *eol = strstr(p, "\r\n");
        char *next = eol ? eol + 2 : p + strlen(p);
        if (!strncasecmp(p, name, nl) && p[nl] == ':') memmove(p, next, strlen(next) + 1);
        else p = next;
    }
}

static void set_header(http_obj *h, const char *name, const char *value)
{
    if (!*name || strpbrk(name, ":\r\n") || strpbrk(value, "\r\n")) bb_raise(5, "bad header name or value");
    remove_header(h, name);
    if (!*value) return;                    /* SetHeader name, "" removes it */
    size_t old = h->headers ? strlen(h->headers) : 0;
    h->headers = realloc(h->headers, old + strlen(name) + strlen(value) + 5);
    sprintf(h->headers + old, "%s: %s\r\n", name, value);
}

static bb_value body_value(http_obj *h)
{
    if (!h->have_resp || !h->resp.body) return bb_v_str(bb_str_from_c(""));
    return bb_v_str(bb_str_new(h->resp.body, (int32_t)h->resp.body_len));
}

/* do a request; raises on network errors. out: the body goes to this file instead. */
static void request(http_obj *h, const char *method, const char *url, const char *body, long body_len,
                    const char *ctype, FILE *out)
{
    char err[512] = "";
    char *hdrs = dupstr(h->headers);
    if (ctype && *ctype) {
        /* the given content type replaces one set with SetHeader for this request */
        http_obj tmp;
        tmp.headers = hdrs;
        remove_header(&tmp, "Content-Type");
        hdrs = realloc(tmp.headers, strlen(tmp.headers) + strlen(ctype) + 20);
        sprintf(hdrs + strlen(hdrs), "Content-Type: %s\r\n", ctype);
    }
    bb_http_req rq;
    memset(&rq, 0, sizeof rq);
    rq.method = method;
    rq.url = url;
    rq.body = body;
    rq.body_len = body_len;
    rq.headers = hdrs;
    rq.user_agent = h->user_agent;
    rq.timeout_ms = h->timeout_ms;
    rq.follow_redirects = h->follow;
    rq.max_redirects = h->max_redirects;
    rq.verify = h->verify;
    rq.ca_file = h->ca_file && *h->ca_file ? h->ca_file : NULL;
    rq.out = out;
    if (h->have_resp) bb_http_resp_free(&h->resp);
    int rc = bb_http_do(&rq, &h->resp, err, sizeof err);
    h->have_resp = 1;
    free(hdrs);
    if (rc) bb_raise(rc, err);
}

static int32_t h_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return P_RESPONSETEXT;            /* the default member */
    for (size_t i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void h_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    http_obj *h = (http_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char *a = NULL, *b = NULL, *c = NULL, *d = NULL;
    long blen = 0;
    switch (id) {
    case M_GET:
    case M_DELETE:
    case M_HEAD:
        a = arg_str(argc, argv, 0, NULL);
        request(h, id == M_GET ? "GET" : id == M_DELETE ? "DELETE" : "HEAD", a, NULL, 0, NULL, NULL);
        free(a);
        *ret = body_value(h);
        return;
    case M_POST:
    case M_PUT:
        a = arg_str(argc, argv, 0, NULL);
        b = arg_str(argc, argv, 1, &blen);
        c = present(argc, argv, 2) ? arg_str(argc, argv, 2, NULL) : dupstr("application/x-www-form-urlencoded");
        request(h, id == M_POST ? "POST" : "PUT", a, b, blen, c, NULL);
        free(a);
        free(b);
        free(c);
        *ret = body_value(h);
        return;
    case M_SEND:
        a = arg_str(argc, argv, 0, NULL);
        b = arg_str(argc, argv, 1, NULL);
        c = present(argc, argv, 2) ? arg_str(argc, argv, 2, &blen) : NULL;
        d = present(argc, argv, 3) ? arg_str(argc, argv, 3, NULL) : NULL;
        request(h, a, b, c, blen, d, NULL);
        free(a);
        free(b);
        free(c);
        free(d);
        *ret = body_value(h);
        return;
    case M_GETTOFILE: {
        a = arg_str(argc, argv, 0, NULL);
        b = arg_str(argc, argv, 1, NULL);
        FILE *f = fopen(b, "wb");
        if (!f) {
            char m[600];
            snprintf(m, sizeof m, "can't create %s", b);
            free(a);
            free(b);
            bb_raise(75, m);
        }
        int ok = 0;
        bb_errframe fr;
        bb_frame_push(&fr);
        if (BB_SETJMP(fr.jb) == 0) {
            request(h, "GET", a, NULL, 0, NULL, f);
            ok = 1;
            bb_frame_pop(&fr);
        } else
            bb_frame_pop(&fr);
        fclose(f);
        free(a);
        if (!ok) {
            remove(b);
            free(b);
            bb_rethrow();
        }
        free(b);
        *ret = bb_v_long((bb_long)h->resp.body_len);
        return;
    }
    case M_SETHEADER:
        a = arg_str(argc, argv, 0, NULL);
        b = arg_str(argc, argv, 1, NULL);
        set_header(h, a, b);
        free(a);
        free(b);
        return;
    case M_CLEARHEADERS:
        free(h->headers);
        h->headers = NULL;
        return;
    case M_RESPONSEHEADER: {
        a = arg_str(argc, argv, 0, NULL);
        char *v = h->have_resp && h->resp.headers ? bb_http_header(h->resp.headers, a) : NULL;
        free(a);
        *ret = bb_v_str(bb_str_from_c(v ? v : ""));
        free(v);
        return;
    }
    case M_TLSAVAILABLE:
        *ret = bb_v_bool(bb_net_tls_available(NULL, 0));
        return;
    case P_STATUS: *ret = bb_v_long(h->have_resp ? h->resp.status : 0); return;
    case P_STATUSTEXT: *ret = bb_v_str(bb_str_from_c(h->have_resp && h->resp.status_text ? h->resp.status_text : "")); return;
    case P_RESPONSETEXT: *ret = body_value(h); return;
    case P_RESPONSEHEADERS: *ret = bb_v_str(bb_str_from_c(h->have_resp && h->resp.headers ? h->resp.headers : "")); return;
    case P_URL: *ret = bb_v_str(bb_str_from_c(h->have_resp && h->resp.final_url ? h->resp.final_url : "")); return;
    case P_CONTENTTYPE: {
        char *v = h->have_resp && h->resp.headers ? bb_http_header(h->resp.headers, "Content-Type") : NULL;
        *ret = bb_v_str(bb_str_from_c(v ? v : ""));
        free(v);
        return;
    }
    case P_BYTESRECEIVED: *ret = bb_v_long(h->have_resp ? (bb_long)h->resp.body_len : 0); return;
    case P_REDIRECTS: *ret = bb_v_long(h->have_resp ? h->resp.redirects : 0); return;
    case P_TIMEOUT:
        if (set) {
            int32_t v = arg_long(argc, argv, argc - 1);
            if (v < 1) bb_raise(380, NULL);
            h->timeout_ms = v;
        } else *ret = bb_v_long(h->timeout_ms);
        return;
    case P_MAXREDIRECTS:
        if (set) {
            int32_t v = arg_long(argc, argv, argc - 1);
            if (v < 0) bb_raise(380, NULL);
            h->max_redirects = v;
        } else *ret = bb_v_long(h->max_redirects);
        return;
    case P_FOLLOWREDIRECTS:
        if (set) h->follow = arg_long(argc, argv, argc - 1) != 0;
        else *ret = bb_v_bool(h->follow);
        return;
    case P_VERIFYCERTIFICATE:
        if (set) h->verify = arg_long(argc, argv, argc - 1) != 0;
        else *ret = bb_v_bool(h->verify);
        return;
    case P_CACERTFILE:
        if (set) {
            free(h->ca_file);
            h->ca_file = arg_str(argc, argv, argc - 1, NULL);
        } else *ret = bb_v_str(bb_str_from_c(h->ca_file ? h->ca_file : ""));
        return;
    case P_USERAGENT:
        if (set) {
            free(h->user_agent);
            h->user_agent = arg_str(argc, argv, argc - 1, NULL);
        } else *ret = bb_v_str(bb_str_from_c(h->user_agent ? h->user_agent : ""));
        return;
    }
    bb_raise(438, NULL);
}

static void h_terminate(bb_obj *self)
{
    http_obj *h = (http_obj *)self;
    free(h->headers);
    free(h->ca_file);
    free(h->user_agent);
    if (h->have_resp) bb_http_resp_free(&h->resp);
}

static const bb_class http_class = {
    "Http", sizeof(http_obj), h_find, h_invoke, h_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

const bb_class *bb_http_class(void) { return &http_class; }

bb_obj *bb_http_new(void)
{
    http_obj *h = (http_obj *)bb_obj_new(&http_class);
    h->timeout_ms = 30000;
    h->follow = 1;
    h->max_redirects = 10;
    h->verify = 1;
    h->user_agent = dupstr("BoingBASIC/1.0");
    return &h->hdr;
}
