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
#include "platform.h"
#include "zio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum {
    M_GET = 1, M_POST, M_PUT, M_DELETE, M_HEAD, M_SEND, M_GETTOFILE, M_SETHEADER, M_CLEARHEADERS,
    M_RESPONSEHEADER, M_TLSAVAILABLE, M_SENDASYNC, M_GETASYNC, M_CANCEL, M_WAIT,
    P_STATUS, P_STATUSTEXT, P_RESPONSETEXT, P_RESPONSEHEADERS, P_URL, P_CONTENTTYPE, P_TIMEOUT,
    P_FOLLOWREDIRECTS, P_MAXREDIRECTS, P_VERIFYCERTIFICATE, P_CACERTFILE, P_USERAGENT, P_BYTESRECEIVED,
    P_REDIRECTS, P_BUSY, P_ONDONE, P_ONPROGRESS, P_ERRORNUMBER, P_ERRORTEXT,
    P_AUTODECOMPRESS, P_KEEPALIVE, P_USECOOKIES, P_COOKIES, M_GETCOOKIE, M_SETCOOKIE, M_CLEARCOOKIES, P_COOKIECOUNT, P_REUSED,
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
    {"SendAsync", M_SENDASYNC}, {"GetAsync", M_GETASYNC}, {"Cancel", M_CANCEL}, {"Wait", M_WAIT},
    {"Busy", P_BUSY}, {"OnDone", P_ONDONE}, {"OnProgress", P_ONPROGRESS}, {"ErrorNumber", P_ERRORNUMBER},
    {"ErrorText", P_ERRORTEXT},
    {"AutoDecompress", P_AUTODECOMPRESS}, {"KeepAlive", P_KEEPALIVE}, {"UseCookies", P_USECOOKIES}, {"Cookies", P_COOKIES}, {"GetCookie", M_GETCOOKIE},
    {"SetCookie", M_SETCOOKIE}, {"ClearCookies", M_CLEARCOOKIES}, {"CookieCount", P_COOKIECOUNT},
    {"ConnectionReused", P_REUSED},
};

/* An asynchronous request: the worker (bb_plat_thread_start) owns everything in here until it
 * sets done; the main task then takes the answer. */
typedef struct job {
    bb_http_req req;
    char *method, *url, *body, *headers, *ua, *ca;
    bb_http_resp resp;
    int rc;
    char err[512];
    volatile int done, cancel;
    volatile long got, total;
    void *thread;
} job;

typedef struct http_obj {
    bb_obj hdr;
    char *headers;              /* request headers, "Name: value\r\n" lines */
    char *ca_file, *user_agent;
    int timeout_ms, follow, max_redirects, verify, decompress;
    bb_http_resp resp;
    int have_resp;
    /* async */
    job *job;
    char *ondone, *onprogress;  /* names of Subs to call */
    long reported;              /* bytes last reported to OnProgress */
    int err_number;
    char *err_text;
    struct http_obj *next_busy; /* the list of objects with a request running */
    bb_http_session session;    /* cookies, the kept connection */
} http_obj;

static http_obj *busy_list;
static void clear_answer(http_obj *h);

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
    if (h->job) bb_raise(5, "a request of this Http object is still running (SendAsync)");
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
    rq.session = &h->session;
    rq.decompress = h->decompress;
    if (h->have_resp) bb_http_resp_free(&h->resp);
    int rc = bb_http_do(&rq, &h->resp, err, sizeof err);
    h->have_resp = 1;
    free(hdrs);
    h->err_number = rc;
    free(h->err_text);
    h->err_text = dupstr(rc ? err : "");
    if (rc) {
        clear_answer(h);
        bb_raise(rc, err);
    }
}

/* --- asynchronous requests ---------------------------------------------------------------- */

static int job_progress(void *ud, long got, long total)
{
    job *j = ud;
    j->got = got;
    j->total = total;
    bb_plat_wake();
    return j->cancel;
}

static void job_run(void *arg)
{
    job *j = arg;
    bb_net_set_cancel(&j->cancel);          /* Cancel ends a connect or a wait for data at once */
    j->rc = bb_http_do(&j->req, &j->resp, j->err, sizeof j->err);
    if (j->rc && j->cancel) {               /* (a TLS handshake broken off reports a TLS error) */
        j->rc = 18;
        snprintf(j->err, sizeof j->err, "cancelled");
    }
    if (j->req.session) bb_http_session_close(j->req.session);   /* a connection this worker kept */
    bb_net_task_done();                     /* this worker's bsdsocket / AmiSSL (OS4) */
    j->done = 1;
}

static void job_free(job *j)
{
    free(j->method); free(j->url); free(j->body); free(j->headers); free(j->ua); free(j->ca);
    bb_http_resp_free(&j->resp);
    free(j);
}

/* events for Dim WithEvents x As Http (registered in ext.c, in this order) */
enum { EV_DONE, EV_PROGRESS, EV_FAILED };
const char *const bb_http_events[] = { "Done", "Progress", "Failed", NULL };

static void call_named(const char *name, int argc, bb_value *argv)
{
    if (!name || !*name) return;
    void *p = bb_find_proc(NULL, name);
    if (!p) {
        char m[200];
        snprintf(m, sizeof m, "Http: there is no Sub %s to call", name);
        bb_raise(35, m);                    /* Sub or Function not defined */
    }
    bb_value r = bb_v_empty();
    int32_t e = bb_call_proc(p, argc, argv, &r);
    bb_v_release(&r);
    if (e) bb_raise(e, NULL);
}

static void clear_answer(http_obj *h)
{
    h->resp.status = 0;
    free(h->resp.body);
    h->resp.body = NULL;
    h->resp.body_len = 0;
}

/* the request of h finished: take the answer (the main task) */
static void finish(http_obj *h)
{
    job *j = h->job;
    bb_plat_thread_join(j->thread);
    if (h->have_resp) bb_http_resp_free(&h->resp);
    h->resp = j->resp;
    memset(&j->resp, 0, sizeof j->resp);
    h->have_resp = 1;
    h->err_number = j->rc;
    if (j->rc) clear_answer(h);             /* no half answers after an error */
    free(h->err_text);
    h->err_text = dupstr(j->rc ? j->err : "");
    h->job = NULL;
    job_free(j);
    for (http_obj **pp = &busy_list; *pp; pp = &(*pp)->next_busy)
        if (*pp == h) {
            *pp = h->next_busy;
            break;
        }
}

/* Check the running requests: report progress, finish the ones that are done and call their
 * OnDone Subs. Called from DoEvents, the forms event loop, Busy and Wait. */
void bb_http_async_poll(void)
{
    static int polling;
    if (polling) return;                    /* an OnDone Sub that calls DoEvents */
    polling = 1;
    bb_errframe f;
    bb_frame_push(&f);
    if (BB_SETJMP(f.jb) == 0) {
        for (http_obj *h = busy_list, *next; h; h = next) {
            next = h->next_busy;
            job *j = h->job;
            if (!j) continue;
            if (((h->onprogress && *h->onprogress) || h->hdr.sinks) && j->got != h->reported) {
                h->reported = j->got;
                bb_value a[2] = { bb_v_long((bb_long)j->got), bb_v_long((bb_long)j->total) };
                bb_obj_retain(&h->hdr);
                bb_event_raise(&h->hdr, EV_PROGRESS, "Progress", 2, a);
                call_named(h->onprogress, 2, a);
                bb_obj_release(&h->hdr);
            }
            if (j->done) {
                bb_obj_retain(&h->hdr);     /* the Sub may drop the last reference */
                finish(h);
                if (h->err_number) {
                    bb_value a[2] = { bb_v_long(h->err_number), bb_v_str(bb_str_from_c(h->err_text)) };
                    bb_event_raise(&h->hdr, EV_FAILED, "Failed", 2, a);
                    bb_v_release(&a[1]);
                } else {
                    bb_event_raise(&h->hdr, EV_DONE, "Done", 0, NULL);
                }
                call_named(h->ondone, 0, NULL);
                bb_obj_release(&h->hdr);    /* the busy list's reference */
                bb_obj_release(&h->hdr);
                next = busy_list;           /* the list may have changed */
            }
        }
        bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        polling = 0;
        bb_rethrow();
    }
    polling = 0;
}

/* At program end (End, the last line, an error, Ctrl-C): cancel the requests still running and
   wait for their workers. On OS4 a worker is a child process of the program, which DOS would
   otherwise keep suspended until it ends. */
static int exit_hook;
static void stop_workers(void)
{
    for (http_obj *h = busy_list; h; h = h->next_busy)
        if (h->job) {
            h->job->cancel = 1;
            bb_plat_thread_break(h->job->thread);
        }
    for (http_obj *h = busy_list; h; h = h->next_busy)
        if (h->job && h->job->thread) {
            bb_plat_thread_join(h->job->thread);
            h->job->thread = NULL;
        }
}

static void start_async(http_obj *h, const char *method, const char *url, const char *body, long blen,
                        const char *ctype)
{
    if (h->job) bb_raise(5, "a request of this Http object is still running");
    job *j = calloc(1, sizeof *j);
    j->method = dupstr(method);
    j->url = dupstr(url);
    if (body) {
        j->body = malloc(blen + 1);
        memcpy(j->body, body, blen);
        j->body[blen] = 0;
    }
    j->headers = dupstr(h->headers);
    if (ctype && *ctype) {
        http_obj tmp;
        tmp.headers = j->headers;
        remove_header(&tmp, "Content-Type");
        j->headers = realloc(tmp.headers, strlen(tmp.headers) + strlen(ctype) + 20);
        sprintf(j->headers + strlen(j->headers), "Content-Type: %s\r\n", ctype);
    }
    j->ua = dupstr(h->user_agent);
    j->ca = h->ca_file && *h->ca_file ? dupstr(h->ca_file) : NULL;
    j->req.method = j->method;
    j->req.url = j->url;
    j->req.body = j->body;
    j->req.body_len = blen;
    j->req.headers = j->headers;
    j->req.user_agent = j->ua;
    j->req.timeout_ms = h->timeout_ms;
    j->req.follow_redirects = h->follow;
    j->req.max_redirects = h->max_redirects;
    j->req.verify = h->verify;
    j->req.ca_file = j->ca;
    j->req.progress = job_progress;
    j->req.progress_ud = j;
    j->req.session = &h->session;
    j->req.decompress = h->decompress;
    if (h->decompress) bb_z_available(NULL, 0);    /* open zlib here, not in the worker */
    j->total = -1;
    h->err_number = 0;
    free(h->err_text);
    h->err_text = dupstr("");
    h->reported = -1;
    h->job = j;
    if (!exit_hook) {
        exit_hook = 1;
        atexit(stop_workers);
    }
    bb_obj_retain(&h->hdr);                 /* kept alive while the request runs */
    h->next_busy = busy_list;
    busy_list = h;
    j->thread = bb_plat_thread_start(job_run, j);
    if (!j->thread) {
        busy_list = h->next_busy;
        h->job = NULL;
        job_free(j);
        bb_obj_release(&h->hdr);
        bb_raise(7, "can't start a background task for the request");
    }
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
    case M_SENDASYNC:
        a = arg_str(argc, argv, 0, NULL);
        b = arg_str(argc, argv, 1, NULL);
        c = present(argc, argv, 2) ? arg_str(argc, argv, 2, &blen) : NULL;
        d = present(argc, argv, 3) ? arg_str(argc, argv, 3, NULL) : NULL;
        start_async(h, a, b, c, blen, d);
        free(a); free(b); free(c); free(d);
        return;
    case M_GETASYNC:
        a = arg_str(argc, argv, 0, NULL);
        start_async(h, "GET", a, NULL, 0, NULL);
        free(a);
        return;
    case M_CANCEL:
        if (h->job) {
            h->job->cancel = 1;
            bb_plat_thread_break(h->job->thread);
        }
        return;
    case M_WAIT: {                           /* Wait [timeoutMs]: True when done */
        long limit = present(argc, argv, 0) ? arg_long(argc, argv, 0) : -1;
        double t0 = bb_plat_seconds();
        while (h->job) {
            bb_http_async_poll();
            if (!h->job) break;
            if (limit >= 0 && (bb_plat_seconds() - t0) * 1000.0 >= limit) break;
            bb_doevents();
            bb_plat_sleep_ms(10);
        }
        *ret = bb_v_bool(h->job == NULL);
        return;
    }
    case P_BUSY:
        bb_http_async_poll();
        *ret = bb_v_bool(h->job != NULL);
        return;
    case P_ONDONE:
    case P_ONPROGRESS: {
        char **slot = id == P_ONDONE ? &h->ondone : &h->onprogress;
        if (set) {
            char *name = arg_str(argc, argv, argc - 1, NULL);
            if (*name && !bb_find_proc(NULL, name)) {   /* say so here, not later inside DoEvents */
                char m[200];
                snprintf(m, sizeof m, "Http: there is no Sub %.100s", name);
                free(name);
                bb_raise(35, m);
            }
            free(*slot);
            *slot = name;
        } else
            *ret = bb_v_str(bb_str_from_c(*slot ? *slot : ""));
        return;
    }
    case P_ERRORNUMBER: *ret = bb_v_long(h->err_number); return;
    case P_ERRORTEXT: *ret = bb_v_str(bb_str_from_c(h->err_text ? h->err_text : "")); return;
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
    case P_BYTESRECEIVED: *ret = bb_v_long(h->have_resp ? (bb_long)h->resp.wire_len : 0); return;
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
    case P_AUTODECOMPRESS:
        if (set) h->decompress = arg_long(argc, argv, argc - 1) != 0;
        else *ret = bb_v_bool(h->decompress);
        return;
    case P_KEEPALIVE:
        if (set) {
            h->session.keep_alive = arg_long(argc, argv, argc - 1) != 0;
            if (!h->session.keep_alive && !h->job) bb_http_session_close(&h->session);
        } else *ret = bb_v_bool(h->session.keep_alive);
        return;
    case P_USECOOKIES:
        if (set) h->session.use_cookies = arg_long(argc, argv, argc - 1) != 0;
        else *ret = bb_v_bool(h->session.use_cookies);
        return;
    case P_REUSED: *ret = bb_v_bool(h->session.reused); return;
    case P_COOKIES:
    case M_GETCOOKIE:
    case M_SETCOOKIE:
    case M_CLEARCOOKIES:
    case P_COOKIECOUNT:
        /* the worker of a running request uses the jar */
        if (h->job) bb_raise(5, "a request of this Http object is still running");
        if (id == P_COOKIES && set) {
            char *t = arg_str(argc, argv, argc - 1, NULL);
            bb_http_cookies_load(&h->session, t);
            free(t);
        } else if (id == P_COOKIES) {
            char *t = bb_http_cookies_text(&h->session);
            *ret = bb_v_str(bb_str_from_c(t));
            free(t);
        } else if (id == M_GETCOOKIE) {      /* GetCookie(name [, host]) */
            char *n = arg_str(argc, argv, 0, NULL);
            char *host = present(argc, argv, 1) ? arg_str(argc, argv, 1, NULL) : NULL;
            const char *v = bb_http_cookie_get(&h->session, n, host);
            *ret = bb_v_str(bb_str_from_c(v ? v : ""));
            free(n);
            free(host);
        } else if (id == M_SETCOOKIE) {      /* SetCookie name, value, domain [, path] */
            char *n = arg_str(argc, argv, 0, NULL), *v = arg_str(argc, argv, 1, NULL);
            char *d = arg_str(argc, argv, 2, NULL);
            char *pa = present(argc, argv, 3) ? arg_str(argc, argv, 3, NULL) : NULL;
            int bad = bb_http_cookie_set(&h->session, n, v, d, pa);
            free(n); free(v); free(d); free(pa);
            if (bad) bb_raise(5, "SetCookie: a cookie needs a name without = ; or spaces, and a domain");
        } else if (id == M_CLEARCOOKIES) {
            bb_http_cookies_clear(&h->session);
        } else {
            *ret = bb_v_long(bb_http_cookie_count(&h->session));
        }
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
    free(h->ondone);
    free(h->onprogress);
    free(h->err_text);
    free(h->headers);
    free(h->ca_file);
    free(h->user_agent);
    if (h->have_resp) bb_http_resp_free(&h->resp);
    bb_http_session_free(&h->session);
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
    h->session.keep_alive = 1;
    h->decompress = 1;
    h->session.use_cookies = 1;
    return &h->hdr;
}
