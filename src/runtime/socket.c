/* socket.c - Boing.Socket, TCP and UDP sockets with events (docs/socket.md):
 *
 *     Dim WithEvents link As Socket
 *     Set link = CreateObject("Socket")
 *     link.Connect "example.com", 7000
 *     Sub link_DataArrival(ByVal Bytes As Long)
 *         Print link.Receive()
 *     End Sub
 *
 * Every socket is non-blocking underneath. The blocking calls (Connect without events, Send,
 * Read, ReceiveLine, Accept) wait at most Timeout. A socket whose events are connected
 * (WithEvents, or an accepted socket whose server has them) is watched: the form event loop
 * waits for it together with the window and timer signals (bb_forms_wait_hook: WaitSelect on
 * AmigaOS, poll on the host), and DoEvents / WaitEvents fire its events in programs without
 * forms. Received data is read into the socket's buffer when it arrives, so DataArrival fires
 * once per arrival and never again for data the program hasn't read yet.
 *
 * Event indices (the order of socket_events, which the compiler reads for WithEvents):
 * 0 Connect, 1 ConnectionRequest, 2 DataArrival(Bytes), 3 Close, 4 Error(Number, Description),
 * 5 ClientDataArrival(Client, Bytes), 6 ClientClose(Client). */
#include "boing.h"
#include "bb_forms.h"
#include "net.h"
#include "platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum { ST_CLOSED = 0, ST_OPEN = 1, ST_LISTENING = 2, ST_CONNECTING = 6, ST_CONNECTED = 7, ST_CLOSING = 8,
       ST_ERROR = 9 };
enum { EV_CONNECT, EV_CONNREQ, EV_DATA, EV_CLOSE, EV_ERROR, EV_CLIENTDATA, EV_CLIENTCLOSE };

const char *const bb_socket_events[] = {
    "Connect", "ConnectionRequest", "DataArrival", "Close", "Error", "ClientDataArrival", "ClientClose", NULL
};

enum {
    M_CONNECT = 1, M_LISTEN, M_ACCEPT, M_BIND, M_SEND, M_SENDLINE, M_SENDTO, M_RECEIVE, M_READ, M_RECEIVELINE,
    M_RECEIVEFROM, M_CLOSE, M_WAITEVENTS, M_PEEK,
    P_STATE, P_REMOTEHOST, P_REMOTEPORT, P_LOCALPORT, P_LOCALHOST, P_TIMEOUT, P_BYTESAVAILABLE, P_ATEND,
    P_CONNECTED, P_TAG, P_PROTOCOL, P_MACHINEADDRESS,
};

static const struct { const char *name; int id; } members[] = {
    {"Connect", M_CONNECT}, {"Listen", M_LISTEN}, {"Accept", M_ACCEPT}, {"Bind", M_BIND}, {"Send", M_SEND},
    {"SendLine", M_SENDLINE}, {"SendTo", M_SENDTO}, {"Receive", M_RECEIVE}, {"Read", M_READ},
    {"ReceiveLine", M_RECEIVELINE}, {"ReceiveFrom", M_RECEIVEFROM}, {"Close", M_CLOSE},
    {"WaitEvents", M_WAITEVENTS}, {"Peek", M_PEEK},
    {"State", P_STATE}, {"RemoteHost", P_REMOTEHOST}, {"RemotePort", P_REMOTEPORT}, {"LocalPort", P_LOCALPORT},
    {"LocalHost", P_LOCALHOST}, {"Timeout", P_TIMEOUT}, {"BytesAvailable", P_BYTESAVAILABLE},
    {"AtEnd", P_ATEND}, {"Connected", P_CONNECTED}, {"Tag", P_TAG}, {"Protocol", P_PROTOCOL},
    {"MachineAddress", P_MACHINEADDRESS},
};

typedef struct dgram { struct dgram *next; int len, port; char host[48]; char data[]; } dgram;

typedef struct sock_obj {
    bb_obj hdr;
    bb_net *n;
    int state, udp, timeout_ms;
    char *in;                   /* received, not yet read by the program */
    int inlen, incap, inoff;
    int eof;                    /* the peer closed (TCP) */
    int fresh;                  /* bytes arrived since the last DataArrival (or read) */
    int close_fired;            /* Close / ClientClose fired for this eof */
    dgram *dq, **dqtail;        /* UDP: received datagrams */
    int ndq;
    char rhost[64];
    int rport;
    struct sock_obj *parent;    /* the listening socket that accepted this one (retained) */
    int accepted;               /* Accept calls on this listener (ConnectionRequest checks it) */
    bb_value tag;
    struct sock_obj *next, *prev;   /* every live socket (not retained) */
} sock_obj;

static sock_obj *all;
static const bb_class socket_class;
#define MAXBUF (1 << 20)        /* stop reading a socket whose program doesn't read */
#define MAXDGRAMS 256

static void install_hook(void);

/* ---- arguments ---- */

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static bb_str *arg_bstr(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static char *arg_cstr(int argc, bb_value *argv, int i)
{
    bb_str *s = arg_bstr(argc, argv, i);
    long n = bb_str_len(s);
    char *o = malloc((size_t)n + 1);
    memcpy(o, bb_str_ptr(s), (size_t)n);
    o[n] = 0;
    bb_str_release(s);
    return o;
}

static int32_t arg_long(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return (int32_t)bb_v_to_long(bb_v_deref(&argv[i], &t));
}

static int arg_port(int argc, bb_value *argv, int i)
{
    int32_t p = arg_long(argc, argv, i);
    if (p < 0 || p > 65535) bb_raise(380, "a port is 0 to 65535");
    return (int)p;
}

/* ---- buffers ---- */

static void in_compact(sock_obj *s)
{
    if (s->inoff && s->inoff == s->inlen) s->inoff = s->inlen = 0;
    else if (s->inoff > 65536 && s->inoff * 2 > s->inlen) {
        memmove(s->in, s->in + s->inoff, (size_t)(s->inlen - s->inoff));
        s->inlen -= s->inoff;
        s->inoff = 0;
    }
}

static int buffered(sock_obj *s) { return s->inlen - s->inoff; }

/* read what the kernel has into the buffer: the number of new bytes, 0 none; sets eof */
static int fill(sock_obj *s)
{
    char err[200];
    int got = 0;
    if (!s->n || s->eof || s->udp) return 0;
    for (;;) {
        int p = bb_net_pending(s->n), r;
        if (p == 0) break;
        if (p < 0) {
            s->eof = 1;
            break;
        }
        if (buffered(s) >= MAXBUF) break;
        if (p > 65536) p = 65536;
        in_compact(s);
        if (s->inlen + p > s->incap) {
            s->incap = (s->inlen + p) * 2;
            s->in = realloc(s->in, (size_t)s->incap);
        }
        r = bb_net_read(s->n, s->in + s->inlen, p, 1000, err, sizeof err);
        if (r <= 0) {
            s->eof = 1;
            break;
        }
        s->inlen += r;
        s->fresh += r;
        got += r;
    }
    if (s->eof && s->state == ST_CONNECTED) s->state = ST_CLOSING;
    return got;
}

/* UDP: queue the waiting datagrams; the number queued */
static int fill_udp(sock_obj *s)
{
    char err[200], host[48];
    static char buf[65536];
    int got = 0;
    if (!s->n || !s->udp) return 0;
    while (s->ndq < MAXDGRAMS) {
        int port = 0, r = bb_net_recvfrom(s->n, buf, sizeof buf, host, sizeof host, &port, err, sizeof err);
        dgram *d;
        if (r < 0) break;
        d = malloc(sizeof *d + (size_t)r);
        d->next = NULL;
        d->len = r;
        d->port = port;
        snprintf(d->host, sizeof d->host, "%s", host);
        memcpy(d->data, buf, (size_t)r);
        *s->dqtail = d;
        s->dqtail = &d->next;
        s->ndq++;
        got++;
    }
    return got;
}

static void close_sock(sock_obj *s)
{
    if (s->n) bb_net_close(s->n);
    s->n = NULL;
    s->state = ST_CLOSED;
    while (s->dq) {
        dgram *d = s->dq;
        s->dq = d->next;
        free(d);
    }
    s->dqtail = &s->dq;
    s->ndq = 0;
    if (s->parent) {
        sock_obj *p = s->parent;
        s->parent = NULL;
        bb_obj_release(&p->hdr);
    }
}

static void reset(sock_obj *s)
{
    close_sock(s);
    s->inlen = s->inoff = 0;
    s->eof = 0;
    s->fresh = 0;
    s->close_fired = 0;
    s->udp = 0;
    s->rhost[0] = 0;
    s->rport = 0;
}

static void raise_net(int rc, const char *err)
{
    bb_raise(rc, err);
}

/* ---- objects ---- */

static sock_obj *new_sock(void)
{
    sock_obj *s = (sock_obj *)bb_obj_new(&socket_class);
    s->timeout_ms = 30000;
    s->dqtail = &s->dq;
    s->next = all;
    if (all) all->prev = s;
    all = s;
    install_hook();
    return s;
}

bb_obj *bb_socket_new(void) { return &new_sock()->hdr; }

static void s_terminate(bb_obj *self)
{
    sock_obj *s = (sock_obj *)self;
    close_sock(s);
    free(s->in);
    bb_v_release(&s->tag);
    if (s->prev) s->prev->next = s->next;
    else all = s->next;
    if (s->next) s->next->prev = s->prev;
}

/* wait until the socket is readable/writable, at most ms: 1 ready, 0 timeout */
static int wait_one(sock_obj *s, int want, int ms)
{
    int got = 0;
    uint32_t sigs = BB_NET_SIG_BREAK;
    int r = bb_net_wait(&s->n, &want, &got, 1, ms, &sigs);
    if (r < 0 || (sigs & BB_NET_SIG_BREAK) || bb_plat_break()) bb_raise(18, NULL);
    return r > 0;
}

static void need_open(sock_obj *s)
{
    if (!s->n) bb_raise(BB_E_NET_PROTOCOL, "the socket isn't open");
}

/* wait for a connection in progress (Connect with events, then Send right away) */
static void finish_connecting(sock_obj *s)
{
    char err[300];
    int rc;
    if (s->state != ST_CONNECTING) return;
    if (!wait_one(s, BB_NET_WR, s->timeout_ms)) {
        snprintf(err, sizeof err, "no answer from %s:%d within %d ms", s->rhost, s->rport, s->timeout_ms);
        reset(s);
        s->state = ST_ERROR;
        raise_net(BB_E_NET_TIMEOUT, err);
    }
    rc = bb_net_connect_finish(s->n, err, sizeof err);
    if (rc) {
        close_sock(s);
        s->state = ST_ERROR;
        raise_net(rc, err);
    }
    s->state = ST_CONNECTED;
}

static void do_connect(sock_obj *s, const char *host, int port)
{
    char err[300];
    int rc;
    reset(s);
    rc = bb_net_connect_start(host, port, &s->n, err, sizeof err);
    if (rc) {
        s->state = ST_ERROR;
        raise_net(rc, err);
    }
    snprintf(s->rhost, sizeof s->rhost, "%s", host);
    s->rport = port;
    s->state = ST_CONNECTING;
    if (!s->hdr.sinks) finish_connecting(s);      /* without events: wait here */
}

static void do_send(sock_obj *s, const char *p, int len)
{
    char err[300];
    int rc;
    need_open(s);
    if (s->udp || s->state == ST_LISTENING) bb_raise(5, "Send needs a connected TCP socket (UDP: SendTo)");
    finish_connecting(s);
    rc = bb_net_write(s->n, p, len, s->timeout_ms, err, sizeof err);
    if (rc) raise_net(rc, err);
}

static bb_str *take(sock_obj *s, int n)
{
    bb_str *r;
    if (n > buffered(s)) n = buffered(s);
    r = bb_str_new(s->in + s->inoff, n);
    s->inoff += n;
    if (!buffered(s)) s->fresh = 0;
    in_compact(s);
    return r;
}

static bb_obj *do_accept(sock_obj *s, int wait_ms)
{
    char err[300];
    bb_net *c = NULL;
    sock_obj *o;
    int rc;
    if (s->state != ST_LISTENING) bb_raise(5, "Accept needs a listening socket (Listen)");
    rc = bb_net_accept(s->n, &c, err, sizeof err);
    if (!rc && !c && wait_ms > 0 && wait_one(s, BB_NET_RD, wait_ms)) rc = bb_net_accept(s->n, &c, err, sizeof err);
    if (rc) raise_net(rc, err);
    s->accepted++;
    if (!c) return NULL;
    o = new_sock();
    o->n = c;
    o->state = ST_CONNECTED;
    o->timeout_ms = s->timeout_ms;
    bb_net_addr(c, 1, o->rhost, sizeof o->rhost, &o->rport);
    o->parent = (sock_obj *)bb_obj_retain(&s->hdr);
    return &o->hdr;
}

static int pump(int timeout_ms, uint32_t *sigs, int fatal);

static void s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    sock_obj *s = (sock_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    char err[300];
    int rc;
    switch (id) {
    case M_CONNECT: {
        char *h = arg_cstr(argc, argv, 0);
        int port = arg_port(argc, argv, 1);
        bb_cleanup cl;
        cl.prev = bb_cleanups;
        cl.fn = free;
        cl.ctx = h;
        bb_cleanups = &cl;
        do_connect(s, h, port);
        bb_cleanups = cl.prev;
        free(h);
        return;
    }
    case M_LISTEN:
    case M_BIND: {
        int port = arg_port(argc, argv, 0);
        char *a = present(argc, argv, 1) ? arg_cstr(argc, argv, 1) : NULL;
        reset(s);
        rc = id == M_LISTEN ? bb_net_listen(a, port, 16, &s->n, err, sizeof err) : bb_net_udp(a, port, &s->n, err, sizeof err);
        free(a);
        if (rc) {
            s->state = ST_ERROR;
            raise_net(rc, err);
        }
        s->udp = id == M_BIND;
        s->state = id == M_LISTEN ? ST_LISTENING : ST_OPEN;
        return;
    }
    case M_ACCEPT: {
        bb_obj *o = do_accept(s, present(argc, argv, 0) ? (int)arg_long(argc, argv, 0) : s->timeout_ms);
        *ret = bb_v_obj(o);
        return;
    }
    case M_SEND:
    case M_SENDLINE: {
        bb_str *d = arg_bstr(argc, argv, 0);
        long n = bb_str_len(d);
        char *p = malloc((size_t)n + 2);
        bb_cleanup cl;
        memcpy(p, bb_str_ptr(d), (size_t)n);
        bb_str_release(d);
        if (id == M_SENDLINE) {
            p[n++] = '\r';
            p[n++] = '\n';
        }
        cl.prev = bb_cleanups;
        cl.fn = free;
        cl.ctx = p;
        bb_cleanups = &cl;
        do_send(s, p, (int)n);
        bb_cleanups = cl.prev;
        free(p);
        return;
    }
    case M_SENDTO: {
        char *h = arg_cstr(argc, argv, 0);
        int port = arg_port(argc, argv, 1);
        bb_str *d = arg_bstr(argc, argv, 2);
        if (!s->n) {                    /* SendTo on a fresh socket: a UDP socket on any port */
            rc = bb_net_udp(NULL, 0, &s->n, err, sizeof err);
            if (rc) {
                free(h);
                bb_str_release(d);
                raise_net(rc, err);
            }
            s->udp = 1;
            s->state = ST_OPEN;
        }
        if (!s->udp) {
            free(h);
            bb_str_release(d);
            bb_raise(5, "SendTo needs a UDP socket (Bind)");
        }
        rc = bb_net_sendto(s->n, h, port, bb_str_ptr(d), (int)bb_str_len(d), err, sizeof err);
        free(h);
        bb_str_release(d);
        if (rc) raise_net(rc, err);
        return;
    }
    case M_RECEIVE:
    case M_PEEK: {
        int max = present(argc, argv, 0) ? (int)arg_long(argc, argv, 0) : 0x7fffffff;
        if (s->udp) bb_raise(5, "Receive needs a TCP socket (UDP: ReceiveFrom)");
        if (max < 0) bb_raise(5, NULL);
        fill(s);
        if (id == M_PEEK) {
            int n = max < buffered(s) ? max : buffered(s);
            *ret = bb_v_str(bb_str_new(s->in + s->inoff, n));
        } else
            *ret = bb_v_str(take(s, max));
        return;
    }
    case M_READ: {
        int count = (int)arg_long(argc, argv, 0);
        double end = bb_plat_seconds() + s->timeout_ms / 1000.0;
        if (count < 0) bb_raise(5, NULL);
        need_open(s);
        finish_connecting(s);
        for (;;) {
            double left;
            fill(s);
            if (buffered(s) >= count || s->eof || !s->n) break;
            left = end - bb_plat_seconds();
            if (left <= 0 || !wait_one(s, BB_NET_RD, (int)(left * 1000) + 1)) {
                if (buffered(s) >= count || s->eof) break;
                snprintf(err, sizeof err, "no data within %d ms", s->timeout_ms);
                raise_net(BB_E_NET_TIMEOUT, err);
            }
        }
        *ret = bb_v_str(take(s, count));
        return;
    }
    case M_RECEIVELINE: {
        double end = bb_plat_seconds() + s->timeout_ms / 1000.0;
        if (s->udp) bb_raise(5, "ReceiveLine needs a TCP socket");
        if (s->n) finish_connecting(s);
        for (;;) {
            char *nl;
            double left;
            fill(s);
            nl = buffered(s) ? memchr(s->in + s->inoff, '\n', (size_t)buffered(s)) : NULL;
            if (nl) {
                int n = (int)(nl - (s->in + s->inoff));
                bb_str *line = bb_str_new(s->in + s->inoff, n > 0 && nl[-1] == '\r' ? n - 1 : n);
                s->inoff += n + 1;
                if (!buffered(s)) s->fresh = 0;
                in_compact(s);
                *ret = bb_v_str(line);
                return;
            }
            if (s->eof || !s->n) {          /* the rest, then "" */
                *ret = bb_v_str(take(s, buffered(s)));
                return;
            }
            left = end - bb_plat_seconds();
            if (left <= 0 || !wait_one(s, BB_NET_RD, (int)(left * 1000) + 1)) {
                fill(s);
                if (s->eof || (buffered(s) && memchr(s->in + s->inoff, '\n', (size_t)buffered(s)))) continue;
                snprintf(err, sizeof err, "no line within %d ms", s->timeout_ms);
                raise_net(BB_E_NET_TIMEOUT, err);
            }
        }
    }
    case M_RECEIVEFROM: {
        int wait_ms = present(argc, argv, 0) ? (int)arg_long(argc, argv, 0) : 0;
        dgram *d;
        if (!s->udp || !s->n) bb_raise(5, "ReceiveFrom needs a UDP socket (Bind)");
        fill_udp(s);
        if (!s->dq && wait_ms > 0 && wait_one(s, BB_NET_RD, wait_ms)) fill_udp(s);
        d = s->dq;
        if (!d) {
            *ret = bb_v_str(bb_str_from_c(""));
            return;
        }
        s->dq = d->next;
        if (!s->dq) s->dqtail = &s->dq;
        s->ndq--;
        snprintf(s->rhost, sizeof s->rhost, "%s", d->host);
        s->rport = d->port;
        *ret = bb_v_str(bb_str_new(d->data, d->len));
        free(d);
        return;
    }
    case M_CLOSE:
        close_sock(s);
        s->eof = 0;
        return;
    case M_WAITEVENTS: {
        int ms = present(argc, argv, 0) ? (int)arg_long(argc, argv, 0) : s->timeout_ms;
        double end = bb_plat_seconds() + ms / 1000.0;
        int fired = 0;
        for (;;) {
            double left = end - bb_plat_seconds();
            int l = left > 0 ? (int)(left * 1000) + 1 : 0;
            uint32_t sigs = 0;
            fired += pump(l, &sigs, 0);
            if (fired || left <= 0) break;
            if (bb_plat_break()) bb_raise(18, NULL);
        }
        *ret = bb_v_bool(fired > 0);
        return;
    }
    case P_STATE:
        if (s->state == ST_CONNECTED && s->n) fill(s);
        *ret = bb_v_long(s->state);
        return;
    case P_CONNECTED:
        if (s->state == ST_CONNECTED && s->n) fill(s);
        *ret = bb_v_bool(s->state == ST_CONNECTED);
        return;
    case P_REMOTEHOST:
        *ret = bb_v_str(bb_str_from_c(s->rhost));
        return;
    case P_REMOTEPORT:
        *ret = bb_v_long(s->rport);
        return;
    case P_LOCALPORT:
    case P_LOCALHOST: {
        char h[64] = "";
        int port = 0;
        if (s->n) bb_net_addr(s->n, 0, h, sizeof h, &port);
        *ret = id == P_LOCALPORT ? bb_v_long(port) : bb_v_str(bb_str_from_c(h));
        return;
    }
    case P_TIMEOUT:
        if (set) {
            int32_t t = arg_long(argc, argv, argc - 1);
            if (t < 0) bb_raise(380, NULL);
            s->timeout_ms = (int)t;
        } else
            *ret = bb_v_long(s->timeout_ms);
        return;
    case P_BYTESAVAILABLE:
        if (s->udp) {
            fill_udp(s);
            *ret = bb_v_long(s->dq ? s->dq->len : 0);
        } else {
            fill(s);
            *ret = bb_v_long(buffered(s));
        }
        return;
    case P_ATEND:
        if (!s->udp) fill(s);
        *ret = bb_v_bool(!s->udp && buffered(s) == 0 && (s->eof || (!s->n && s->state != ST_CONNECTING)));
        return;
    case P_TAG:
        if (set) {
            bb_value t;
            bb_v_assign(&s->tag, bb_v_deref(&argv[argc - 1], &t));
        } else
            bb_v_copy(ret, &s->tag);
        return;
    case P_MACHINEADDRESS: {
        char h[64];
        bb_net_machine_addr(h, sizeof h);
        *ret = bb_v_str(bb_str_from_c(h));
        return;
    }
    case P_PROTOCOL:
        *ret = bb_v_str(bb_str_from_c(s->udp ? "UDP" : "TCP"));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t s_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static const bb_class socket_class = {
    "Socket", sizeof(sock_obj), s_find, s_invoke, s_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_socket_class(void) { return &socket_class; }

/* ---- events ---- */

/* the object whose events this socket's arrive at: itself, or its server (Client... events) */
static int watched(sock_obj *s)
{
    if (!s->n) return 0;
    if (s->hdr.sinks) return 1;
    return s->parent && s->parent->hdr.sinks;
}

static void fire(sock_obj *s, int ev, int argc, bb_value *argv)
{
    static const char *const names[] = {"Connect", "ConnectionRequest", "DataArrival", "Close", "Error",
                                        "ClientDataArrival", "ClientClose"};
    bb_event_raise(&s->hdr, ev, names[ev], argc, argv);
}

/* data arrived (bytes buffered now) or the peer closed, on s: its own events or its server's */
static void fire_data(sock_obj *s, int closed)
{
    if (s->hdr.sinks) {
        if (closed) fire(s, EV_CLOSE, 0, NULL);
        else {
            bb_value a = bb_v_long(buffered(s));
            fire(s, EV_DATA, 1, &a);
        }
    } else if (s->parent && s->parent->hdr.sinks) {
        bb_value a[2];
        a[0] = bb_v_obj(&s->hdr);           /* borrowed: the handler gets a reference */
        if (closed) fire(s->parent, EV_CLIENTCLOSE, 1, a);
        else {
            a[1] = bb_v_long(buffered(s));
            fire(s->parent, EV_CLIENTDATA, 2, a);
        }
    }
}

typedef struct { sock_obj **s; int n; } readyset;

static void release_all(void *ctx)
{
    readyset *r = ctx;
    int i;
    for (i = 0; i < r->n; i++) if (r->s[i]) bb_obj_release(&r->s[i]->hdr);
    free(r->s);
    r->s = NULL;
    r->n = 0;
}

/* one round: wait for the watched sockets (and the signals in *sigs on AmigaOS) at most
   timeout_ms, then fire their events. Returns the number of events fired. fatal: called from
   the form event loop, where an error in a handler ends the program (as in any event). */
static int pump(int timeout_ms, uint32_t *sigs, int fatal)
{
    sock_obj *s, **list = NULL;
    bb_net **nets = NULL;
    int *want = NULL, *got = NULL;
    int n = 0, cap = 0, i, r, nimm = 0;
    volatile int fired = 0;
    readyset rs;
    bb_cleanup cl;
    bb_errframe f;
    for (s = all; s; s = s->next) {
        int w = 0, imm = 0;
        if (!watched(s)) continue;
        if (!s->udp && (s->state == ST_CONNECTED || s->state == ST_CLOSING) &&
            (s->fresh > 0 || (s->eof && !s->close_fired)))
            imm = 1;                    /* data read in by Peek/State..., or an end not reported yet */
        if (s->state == ST_CONNECTING) w = BB_NET_WR;
        else if (s->state == ST_LISTENING) w = BB_NET_RD;
        else if (s->udp) w = s->ndq < MAXDGRAMS ? BB_NET_RD : 0;
        else if (s->state == ST_CONNECTED && !s->eof && buffered(s) < MAXBUF) w = BB_NET_RD;
        if (!w && !imm) continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 8;
            list = realloc(list, sizeof *list * (size_t)cap);
            nets = realloc(nets, sizeof *nets * (size_t)cap);
            want = realloc(want, sizeof *want * (size_t)cap);
            got = realloc(got, sizeof *got * (size_t)cap);
        }
        list[n] = s;
        nets[n] = s->n;
        want[n] = w;
        if (imm) nimm++;
        n++;
    }
    /* sockets with nothing to wait for are left out of the wait (want 0 there) */
    r = bb_net_wait(nets, want, got, n, nimm ? 0 : timeout_ms, sigs);
    free(nets);
    if (r >= 0 && nimm) {
        for (i = 0; i < n; i++)
            if (!want[i] || (!list[i]->udp && (list[i]->fresh > 0 || (list[i]->eof && !list[i]->close_fired))))
                got[i] |= BB_NET_RD;
        r = 1;
    }
    free(want);
    if (r <= 0) {
        free(list);
        free(got);
        return 0;
    }
    /* keep the ready ones alive while their handlers run */
    rs.s = malloc(sizeof *rs.s * (size_t)n);
    rs.n = 0;
    for (i = 0; i < n; i++)
        if (got[i]) rs.s[rs.n++] = (sock_obj *)bb_obj_retain(&list[i]->hdr);
    free(list);
    free(got);
    cl.prev = bb_cleanups;
    cl.fn = release_all;
    cl.ctx = &rs;
    bb_cleanups = &cl;
    if (fatal) bb_frame_push(&f);
    if (!fatal || BB_SETJMP(f.jb) == 0) {
        for (i = 0; i < rs.n; i++) {
            char err[300];
            s = rs.s[i];
            if (!s->n || !watched(s)) continue;
            if (s->state == ST_CONNECTING) {
                int rc = bb_net_connect_finish(s->n, err, sizeof err);
                if (rc) {
                    bb_value a[2];
                    close_sock(s);
                    s->state = ST_ERROR;
                    a[0] = bb_v_long(rc);
                    a[1] = bb_v_str(bb_str_from_c(err));
                    if (s->hdr.sinks) fire(s, EV_ERROR, 2, a);
                    bb_v_release(&a[1]);
                } else {
                    s->state = ST_CONNECTED;
                    if (s->hdr.sinks) fire(s, EV_CONNECT, 0, NULL);
                }
                fired++;
            } else if (s->state == ST_LISTENING) {
                int before = s->accepted;
                fire(s, EV_CONNREQ, 0, NULL);
                fired++;
                if (s->accepted == before && s->n) {
                    /* not accepted: refuse it, so it doesn't wake the loop again */
                    bb_net *c = NULL;
                    if (!bb_net_accept(s->n, &c, err, sizeof err) && c) bb_net_close(c);
                }
            } else if (s->udp) {
                int k = fill_udp(s);
                while (k-- > 0 && s->n && watched(s)) {
                    bb_value a = bb_v_long(s->dq ? s->dq->len : 0);
                    if (s->hdr.sinks) fire(s, EV_DATA, 1, &a);
                    fired++;
                }
            } else if (s->state == ST_CONNECTED || s->state == ST_CLOSING) {
                fill(s);
                if (s->fresh > 0) {
                    s->fresh = 0;
                    fire_data(s, 0);
                    fired++;
                }
                if (s->eof && s->n && !s->close_fired && watched(s)) {
                    s->close_fired = 1;
                    fire_data(s, 1);
                    fired++;
                }
            }
        }
        if (fatal) bb_frame_pop(&f);
    } else {
        bb_frame_pop(&f);
        bb_fatal_error();
    }
    bb_cleanups = cl.prev;
    release_all(&rs);
    return fired;
}

/* the form event loop's wait (bb_forms.h) */
static uint32_t wait_hook(uint32_t sigmask, int timeout_ms)
{
    uint32_t sigs = sigmask;
    pump(timeout_ms, &sigs, 1);
    return sigs;
}

/* DoEvents in a program without forms */
static bb_int sock_doevents(void)
{
    uint32_t sigs = 0;
    pump(0, &sigs, 0);
    return 0;
}

static void install_hook(void)
{
    if (!bb_forms_wait_hook) bb_forms_wait_hook = wait_hook;
    bb_set_net_doevents(sock_doevents);
}
