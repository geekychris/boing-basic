/* net.h on POSIX hosts: BSD sockets; TLS through OpenSSL 3, loaded with dlopen on first use so
 * neither libboing nor programs built by `boing build` link against it (HTTPS just isn't
 * available where it isn't installed). */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "../net.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>

/* --- OpenSSL, by dlopen ------------------------------------------------------------------- */

typedef void SSL_CTX;
typedef void SSL;
typedef void SSL_METHOD;
static struct {
    int tried, ok;
    char why[200];
    const SSL_METHOD *(*TLS_client_method)(void);
    SSL_CTX *(*SSL_CTX_new)(const SSL_METHOD *);
    void (*SSL_CTX_free)(SSL_CTX *);
    int (*SSL_CTX_set_default_verify_paths)(SSL_CTX *);
    int (*SSL_CTX_load_verify_locations)(SSL_CTX *, const char *, const char *);
    void (*SSL_CTX_set_verify)(SSL_CTX *, int, void *);
    SSL *(*SSL_new)(SSL_CTX *);
    void (*SSL_free)(SSL *);
    int (*SSL_set_fd)(SSL *, int);
    long (*SSL_ctrl)(SSL *, int, long, void *);
    int (*SSL_set1_host)(SSL *, const char *);
    int (*SSL_connect)(SSL *);
    long (*SSL_get_verify_result)(const SSL *);
    int (*SSL_read)(SSL *, void *, int);
    int (*SSL_pending)(const SSL *);
    int (*SSL_write)(SSL *, const void *, int);
    int (*SSL_get_error)(const SSL *, int);
    int (*SSL_shutdown)(SSL *);
    const char *(*X509_verify_cert_error_string)(long);
    unsigned long (*ERR_get_error)(void);
    void (*ERR_error_string_n)(unsigned long, char *, size_t);
} ossl;

static void *sym(void *a, void *b, const char *name)
{
    void *p = a ? dlsym(a, name) : NULL;
    if (!p && b) p = dlsym(b, name);
    return p;
}

static int ossl_load(void)
{
    static const char *const ssl_names[] = {
        "libssl.3.dylib", "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
        "/usr/local/opt/openssl@3/lib/libssl.3.dylib", "libssl.so.3", "libssl.so", NULL };
    static const char *const crypto_names[] = {
        "libcrypto.3.dylib", "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib",
        "/usr/local/opt/openssl@3/lib/libcrypto.3.dylib", "libcrypto.so.3", "libcrypto.so", NULL };
    if (ossl.tried) return ossl.ok;
    ossl.tried = 1;
    const char *env = getenv("BOING_OPENSSL_DIR");     /* a directory with libssl/libcrypto */
    void *s = NULL, *c = NULL;
    char buf[1024];
    for (int i = 0; ssl_names[i] && !s; i++) {
        if (env && strchr(ssl_names[i], '/') == NULL) {
            snprintf(buf, sizeof buf, "%s/%s", env, ssl_names[i]);
            s = dlopen(buf, RTLD_NOW | RTLD_GLOBAL);
        }
        if (!s) s = dlopen(ssl_names[i], RTLD_NOW | RTLD_GLOBAL);
        if (s) {
            /* the matching libcrypto, from the same place */
            c = dlopen(crypto_names[i], RTLD_NOW | RTLD_GLOBAL);
        }
    }
    if (!s) {
        snprintf(ossl.why, sizeof ossl.why, "HTTPS needs OpenSSL 3 (libssl), which isn't installed on this system");
        return 0;
    }
#define LOAD(f) if (!(*(void **)&ossl.f = sym(s, c, #f))) { snprintf(ossl.why, sizeof ossl.why, "OpenSSL lacks %s", #f); return 0; }
    LOAD(TLS_client_method) LOAD(SSL_CTX_new) LOAD(SSL_CTX_free) LOAD(SSL_CTX_set_default_verify_paths)
    LOAD(SSL_CTX_load_verify_locations) LOAD(SSL_CTX_set_verify) LOAD(SSL_new) LOAD(SSL_free) LOAD(SSL_set_fd)
    LOAD(SSL_ctrl) LOAD(SSL_set1_host) LOAD(SSL_connect) LOAD(SSL_get_verify_result) LOAD(SSL_read)
    LOAD(SSL_write) LOAD(SSL_get_error) LOAD(SSL_shutdown) LOAD(X509_verify_cert_error_string)
    LOAD(ERR_get_error) LOAD(ERR_error_string_n) LOAD(SSL_pending)
#undef LOAD
    ossl.ok = 1;
    return 1;
}

int bb_net_tls_available(char *why, int whylen)
{
    if (ossl_load()) return 1;
    if (why) snprintf(why, whylen, "%s", ossl.why);
    return 0;
}

/* --- connections -------------------------------------------------------------------------- */

static __thread volatile int *cancel_flag;
void bb_net_set_cancel(volatile int *flag) { cancel_flag = flag; }

/* poll that also ends (returning -2) when the calling thread's cancel flag is set */
static int poll_c(struct pollfd *p, nfds_t n, int timeout_ms)
{
    if (!cancel_flag) return poll(p, n, timeout_ms);
    for (int left = timeout_ms;;) {
        if (*cancel_flag) return -2;
        int slice = left < 0 || left > 100 ? 100 : left;
        int r = poll(p, n, slice);
        if (r != 0) return r;
        if (left >= 0 && (left -= slice) <= 0) return 0;
    }
}

struct bb_net {
    int fd;
    SSL_CTX *ctx;
    SSL *ssl;
    int nonblock;               /* made by the socket functions below */
    int udp;
};

#ifdef MSG_NOSIGNAL
#define SEND_FLAGS MSG_NOSIGNAL
#else
#define SEND_FLAGS 0
#endif

static void set_timeouts(int fd, int ms)
{
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
}

static int tcp_connect(const char *host, int port, int timeout_ms, int *out, char *err, int errlen)
{
    struct addrinfo hints, *res = NULL, *ai;
    char ports[16];
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(ports, sizeof ports, "%d", port);
    if (getaddrinfo(host, ports, &hints, &res) || !res) {
        snprintf(err, errlen, "can't resolve the host name %s", host);
        return BB_E_NET_RESOLVE;
    }
    int rc = BB_E_NET_CONNECT;
    snprintf(err, errlen, "can't connect to %s:%d", host, port);
    for (ai = res; ai; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        int r = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (r < 0 && errno == EINPROGRESS) {
            struct pollfd p = { fd, POLLOUT, 0 };
            r = poll_c(&p, 1, timeout_ms);
            if (r == -2) {
                close(fd);
                freeaddrinfo(res);
                snprintf(err, errlen, "cancelled");
                return 18;
            }
            if (r == 0) {
                close(fd);
                rc = BB_E_NET_TIMEOUT;
                snprintf(err, errlen, "no answer from %s:%d within %d ms", host, port, timeout_ms);
                continue;
            }
            int soerr = 0;
            socklen_t sl = sizeof soerr;
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
            r = (r > 0 && soerr == 0) ? 0 : -1;
        }
        if (r == 0) {
            fcntl(fd, F_SETFL, fl & ~O_NONBLOCK);
            set_timeouts(fd, timeout_ms);
            int one = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
            *out = fd;
            freeaddrinfo(res);
            return 0;
        }
        close(fd);
    }
    freeaddrinfo(res);
    return rc;
}

static void ssl_errstr(char *buf, int len)
{
    unsigned long e = ossl.ERR_get_error();
    if (e) ossl.ERR_error_string_n(e, buf, len);
    else snprintf(buf, len, "the connection closed");
}

int bb_net_open(const char *host, int port, int tls, const bb_tls_opts *opts, int timeout_ms, bb_net **out,
                char *err, int errlen)
{
    *out = NULL;
    if (tls && !ossl_load()) {
        snprintf(err, errlen, "%s", ossl.why);
        return BB_E_NET_NOTLS;
    }
    int fd;
    int rc = tcp_connect(host, port, timeout_ms, &fd, err, errlen);
    if (rc) return rc;
    bb_net *n = calloc(1, sizeof *n);
    n->fd = fd;
    if (tls) {
        int verify = !opts || opts->verify;
        n->ctx = ossl.SSL_CTX_new(ossl.TLS_client_method());
        if (!n->ctx) {
            snprintf(err, errlen, "can't create a TLS context");
            bb_net_close(n);
            return BB_E_NET_TLS;
        }
        if (opts && opts->ca_file && *opts->ca_file) {
            if (ossl.SSL_CTX_load_verify_locations(n->ctx, opts->ca_file, NULL) != 1) {
                snprintf(err, errlen, "can't read the certificates in %s", opts->ca_file);
                bb_net_close(n);
                return BB_E_NET_CERT;
            }
        } else
            ossl.SSL_CTX_set_default_verify_paths(n->ctx);
        ossl.SSL_CTX_set_verify(n->ctx, verify ? 1 /* SSL_VERIFY_PEER */ : 0, NULL);
        n->ssl = ossl.SSL_new(n->ctx);
        ossl.SSL_set_fd(n->ssl, fd);
        ossl.SSL_ctrl(n->ssl, 55 /* SSL_CTRL_SET_TLSEXT_HOSTNAME */, 0, (void *)host);   /* SNI */
        if (verify) ossl.SSL_set1_host(n->ssl, host);
        if (ossl.SSL_connect(n->ssl) != 1) {
            long v = ossl.SSL_get_verify_result(n->ssl);
            if (verify && v != 0) {
                snprintf(err, errlen, "the certificate of %s isn't trusted: %s", host, ossl.X509_verify_cert_error_string(v));
                rc = BB_E_NET_CERT;
            } else {
                char e[200];
                ssl_errstr(e, sizeof e);
                snprintf(err, errlen, "TLS handshake with %s failed: %s", host, e);
                rc = BB_E_NET_TLS;
            }
            bb_net_close(n);
            return rc;
        }
    }
    *out = n;
    return 0;
}

int bb_net_write(bb_net *n, const void *p, int len, int timeout_ms, char *err, int errlen)
{
    const char *c = p;
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    set_timeouts(n->fd, timeout_ms);
    while (len > 0) {
        int w = n->ssl ? ossl.SSL_write(n->ssl, c, len) : (int)send(n->fd, c, len, SEND_FLAGS);
        if (w < 0 && !n->ssl && errno == EINTR) continue;
        if (w < 0 && !n->ssl && n->nonblock && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd pf = { n->fd, POLLOUT, 0 };
            long used;
            gettimeofday(&t1, NULL);
            used = (t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L;
            if (used < timeout_ms && poll(&pf, 1, (int)(timeout_ms - used)) > 0) continue;
            snprintf(err, errlen, "sending timed out");
            return BB_E_NET_TIMEOUT;
        }
        if (w <= 0) {
            if (!n->ssl && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                snprintf(err, errlen, "sending timed out");
                return BB_E_NET_TIMEOUT;
            }
            snprintf(err, errlen, "the connection closed while sending");
            return BB_E_NET_PROTOCOL;
        }
        c += w;
        len -= w;
    }
    return 0;
}

int bb_net_read(bb_net *n, void *p, int len, int timeout_ms, char *err, int errlen)
{
    set_timeouts(n->fd, timeout_ms);
    for (;;) {
        int r;
        if (cancel_flag && !(n->ssl && ossl.SSL_pending && ossl.SSL_pending(n->ssl))) {
            struct pollfd pf = { n->fd, POLLIN, 0 };
            int pr = poll_c(&pf, 1, timeout_ms);
            if (pr == -2) {
                snprintf(err, errlen, "cancelled");
                return -18;
            }
            if (pr == 0) {
                snprintf(err, errlen, "no data within %d ms", timeout_ms);
                return -BB_E_NET_TIMEOUT;
            }
        }
        if (n->ssl) {
            r = ossl.SSL_read(n->ssl, p, len);
            if (r > 0) return r;
            int e = ossl.SSL_get_error(n->ssl, r);
            if (e == 6 /* SSL_ERROR_ZERO_RETURN */) return 0;
            if (e == 5 /* SSL_ERROR_SYSCALL */ && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                snprintf(err, errlen, "no data within %d ms", timeout_ms);
                return -BB_E_NET_TIMEOUT;
            }
            if (e == 5 && r == 0) return 0;      /* EOF without close_notify: treat as the end */
            char es[200];
            ssl_errstr(es, sizeof es);
            snprintf(err, errlen, "TLS read failed: %s", es);
            return -BB_E_NET_PROTOCOL;
        }
        if (n->nonblock) {
            struct pollfd pf = { n->fd, POLLIN, 0 };
            int pr = poll(&pf, 1, timeout_ms);
            if (pr < 0 && errno == EINTR) continue;
            if (pr == 0) {
                snprintf(err, errlen, "no data within %d ms", timeout_ms);
                return -BB_E_NET_TIMEOUT;
            }
        }
        r = (int)recv(n->fd, p, len, 0);
        if (r >= 0) return r;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            snprintf(err, errlen, "no data within %d ms", timeout_ms);
            return -BB_E_NET_TIMEOUT;
        }
        snprintf(err, errlen, "reading failed: %s", strerror(errno));
        return -BB_E_NET_PROTOCOL;
    }
}

void bb_net_close(bb_net *n)
{
    if (!n) return;
    if (n->ssl) {
        ossl.SSL_shutdown(n->ssl);
        ossl.SSL_free(n->ssl);
    }
    if (n->ctx) ossl.SSL_CTX_free(n->ctx);
    if (n->fd >= 0) close(n->fd);
    free(n);
}

void bb_net_task_done(void) {}
/* --- sockets for the Socket class --------------------------------------------------------- */

static bb_net *wrap(int fd, int udp)
{
    bb_net *n = calloc(1, sizeof *n);
    int one = 1;
    n->fd = fd;
    n->nonblock = 1;
    n->udp = udp;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
    if (!udp) setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    (void)one;
    return n;
}

static int resolve4(const char *host, struct in_addr *a, char *err, int errlen)
{
    struct addrinfo hints, *res = NULL;
    if (!host || !*host) {
        a->s_addr = htonl(INADDR_ANY);
        return 0;
    }
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    if (getaddrinfo(host, NULL, &hints, &res) || !res) {
        snprintf(err, errlen, "can't resolve the host name %s", host);
        return BB_E_NET_RESOLVE;
    }
    *a = ((struct sockaddr_in *)res->ai_addr)->sin_addr;
    freeaddrinfo(res);
    return 0;
}

int bb_net_connect_start(const char *host, int port, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd;
    *out = NULL;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);
    if ((rc = resolve4(host, &sa.sin_addr, err, errlen))) return rc;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0 && errno != EINPROGRESS) {
        snprintf(err, errlen, "can't connect to %s:%d", host, port);
        bb_net_close(*out);
        *out = NULL;
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_connect_finish(bb_net *n, char *err, int errlen)
{
    int soerr = 0;
    socklen_t sl = sizeof soerr;
    getsockopt(n->fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
    if (soerr) {
        snprintf(err, errlen, "can't connect: %s", strerror(soerr));
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_listen(const char *addr, int port, int backlog, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd, one = 1;
    *out = NULL;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);
    if ((rc = resolve4(addr, &sa.sin_addr, err, errlen))) return rc;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0 || listen(fd, backlog > 0 ? backlog : 8) < 0) {
        snprintf(err, errlen, "can't listen on port %d: %s", port, strerror(errno));
        close(fd);
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    return 0;
}

int bb_net_accept(bb_net *l, bb_net **out, char *err, int errlen)
{
    int fd = accept(l->fd, NULL, NULL);
    *out = NULL;
    if (fd < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR || errno == ECONNABORTED) return 0;
        snprintf(err, errlen, "accept failed: %s", strerror(errno));
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    return 0;
}

int bb_net_udp(const char *addr, int port, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd, one = 1;
    *out = NULL;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);
    if ((rc = resolve4(addr, &sa.sin_addr, err, errlen))) return rc;
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof one);
    if (port) setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
        snprintf(err, errlen, "can't bind port %d: %s", port, strerror(errno));
        close(fd);
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 1);
    return 0;
}

int bb_net_sendto(bb_net *n, const char *host, int port, const void *p, int len, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);
    if ((rc = resolve4(host, &sa.sin_addr, err, errlen))) return rc;
    if (!host || !*host) sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (sendto(n->fd, p, (size_t)len, SEND_FLAGS, (struct sockaddr *)&sa, sizeof sa) < 0) {
        snprintf(err, errlen, "sending to %s:%d failed: %s", host, port, strerror(errno));
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_recvfrom(bb_net *n, void *p, int len, char *host, int hostlen, int *port, char *err, int errlen)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    int r = (int)recvfrom(n->fd, p, (size_t)len, 0, (struct sockaddr *)&sa, &sl);
    if (r < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return -1;
        snprintf(err, errlen, "receiving failed: %s", strerror(errno));
        return -BB_E_NET_PROTOCOL;
    }
    if (host) snprintf(host, hostlen, "%s", inet_ntoa(sa.sin_addr));
    if (port) *port = ntohs(sa.sin_port);
    return r;
}

int bb_net_pending(bb_net *n)
{
    int avail = 0;
    char c;
    struct pollfd pf = { n->fd, POLLIN, 0 };
    if (n->ssl) {
        /* not used by the Socket class (no TLS sockets yet) */
        return 0;
    }
    if (poll(&pf, 1, 0) <= 0) return 0;
    if (ioctl(n->fd, FIONREAD, &avail) < 0) return -1;
    if (avail > 0) return avail;
    if (n->udp) {
        /* an empty datagram, or an ICMP error: read it so it doesn't wake us forever */
        return recv(n->fd, &c, 1, MSG_PEEK) >= 0 ? 0 : 0;
    }
    /* readable with nothing in it: end of stream or an error */
    return recv(n->fd, &c, 1, MSG_PEEK) > 0 ? 1 : -1;
}

int bb_net_send_some(bb_net *n, const void *p, int len, char *err, int errlen)
{
    int w = (int)send(n->fd, p, (size_t)len, SEND_FLAGS);
    if (w >= 0) return w;
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
    snprintf(err, errlen, "the connection closed while sending");
    return -BB_E_NET_PROTOCOL;
}

void bb_net_addr(bb_net *n, int peer, char *host, int hostlen, int *port)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    memset(&sa, 0, sizeof sa);
    if ((peer ? getpeername(n->fd, (struct sockaddr *)&sa, &sl) : getsockname(n->fd, (struct sockaddr *)&sa, &sl)) < 0 ||
        sa.sin_family != AF_INET) {
        if (host) snprintf(host, hostlen, "%s", "");
        if (port) *port = 0;
        return;
    }
    if (host) snprintf(host, hostlen, "%s", inet_ntoa(sa.sin_addr));
    if (port) *port = ntohs(sa.sin_port);
}

int bb_net_wait(bb_net **ns, const int *want, int *got, int count, int timeout_ms, uint32_t *sigs)
{
    struct pollfd fixed[16], *pf = count <= 16 ? fixed : malloc(sizeof *pf * (size_t)count);
    int i, r, nready = 0;
    if (sigs) *sigs = 0;
    for (i = 0; i < count; i++) {
        pf[i].fd = ns[i]->fd;
        pf[i].events = (short)(((want[i] & BB_NET_RD) ? POLLIN : 0) | ((want[i] & BB_NET_WR) ? POLLOUT : 0));
        pf[i].revents = 0;
    }
    do r = poll(pf, (nfds_t)count, timeout_ms);
    while (r < 0 && errno == EINTR);
    for (i = 0; i < count; i++) {
        int g = 0;
        if (r > 0) {
            if (pf[i].revents & (POLLIN | POLLHUP | POLLERR)) g |= want[i] & BB_NET_RD ? BB_NET_RD : 0;
            if (pf[i].revents & (POLLOUT | POLLHUP | POLLERR)) g |= want[i] & BB_NET_WR ? BB_NET_WR : 0;
        }
        got[i] = g;
        if (g) nready++;
    }
    if (pf != fixed) free(pf);
    return r < 0 ? -1 : nready;
}

int bb_net_machine_addr(char *host, int hostlen)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    int fd = socket(AF_INET, SOCK_DGRAM, 0), ok = 0;
    snprintf(host, hostlen, "127.0.0.1");
    if (fd < 0) return 0;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons(53);
    sa.sin_addr.s_addr = htonl(0x08080808);         /* any outside address: no packet is sent */
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) == 0 && getsockname(fd, (struct sockaddr *)&sa, &sl) == 0 &&
        sa.sin_addr.s_addr) {
        snprintf(host, hostlen, "%s", inet_ntoa(sa.sin_addr));
        ok = 1;
    }
    close(fd);
    return ok;
}

int bb_net_owned(bb_net *n) { return n != NULL; }   /* threads share sockets */
