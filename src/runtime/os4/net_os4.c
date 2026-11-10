/* net.h on AmigaOS 4: bsdsocket.library (Roadshow) for TCP, AmiSSL for TLS.
 *
 * Both are opened on first use, through private interface pointers and explicit IFace calls:
 * the global ISocket/SocketBase would make libauto open bsdsocket at the start of every
 * program, and a program without networking must still run where no TCP/IP stack is up.
 *
 * AmiSSL gets our bsdsocket interface (AmiSSL_ISocket), so the fds we create are the fds its
 * TLS layer reads and writes. That is what CPython's OS4 port lacks (its _ssl and _socket use
 * different socket bases, and the handshake fails with EBADF). Certificates are verified by
 * default against AmiSSL's store (AmiSSL:Certs), with the host name checked too. */
#include "../net.h"
#include "../boing.h"
#include "../platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <exec/exec.h>
#include <dos/dos.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <interfaces/bsdsocket.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/filio.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <libraries/amisslmaster.h>
#include <amissl/tags.h>
#include <interfaces/amisslmaster.h>
#include <interfaces/amissl.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>

/* The bases are per task: a bsdsocket base and its sockets belong to the task that opened it,
 * and AmiSSL is opened per task too. Async Http requests run on worker processes, each with its
 * own context (bb_net_task_done closes it when the worker ends). */
typedef struct netctx {
    struct Task *task;
    struct Library *f_sock_base;
    struct SocketIFace *f_isock;
    struct Library *f_master_base;
    struct AmiSSLMasterIFace *f_imaster;
    struct Library *f_amissl_base, *f_amissl_ext_base;
    struct AmiSSLIFace *f_issl;
    int f_sock_tried, f_ssl_tried, f_ssl_ok;
    char f_ssl_why[200];
    int f_ssl_errno;
} netctx;

#define NCTX 16
static netctx ctxs[NCTX];

static netctx *net_ctx(void)
{
    struct Task *me = IExec->FindTask(NULL);
    netctx *freec = NULL;
    for (int i = 0; i < NCTX; i++) {
        if (ctxs[i].task == me) return &ctxs[i];
        if (!ctxs[i].task && !freec) freec = &ctxs[i];
    }
    IExec->Forbid();
    if (freec && !freec->task) {
        memset(freec, 0, sizeof *freec);
        freec->task = me;
    } else
        freec = NULL;
    IExec->Permit();
    if (!freec) bb_raise(7, "too many tasks using the network");
    return freec;
}

#define sock_base (net_ctx()->f_sock_base)
#define ISock (net_ctx()->f_isock)
#define master_base (net_ctx()->f_master_base)
#define IMaster (net_ctx()->f_imaster)
#define amissl_base (net_ctx()->f_amissl_base)
#define amissl_ext_base (net_ctx()->f_amissl_ext_base)
#define ISSL (net_ctx()->f_issl)
#define sock_tried (net_ctx()->f_sock_tried)
#define ssl_tried (net_ctx()->f_ssl_tried)
#define ssl_ok (net_ctx()->f_ssl_ok)
#define ssl_why (net_ctx()->f_ssl_why)
#define ssl_errno (net_ctx()->f_ssl_errno)
static int cleanup_registered;

/* close the calling task's bases (a worker calls this before it ends; the main task at exit) */
void bb_net_task_done(void)
{
    struct Task *me = IExec->FindTask(NULL);
    for (int i = 0; i < NCTX; i++)
        if (ctxs[i].task == me) {
            netctx *c = &ctxs[i];
            if (c->f_issl && c->f_imaster) c->f_imaster->CloseAmiSSL();
            if (c->f_imaster) IExec->DropInterface((struct Interface *)c->f_imaster);
            if (c->f_master_base) IExec->CloseLibrary(c->f_master_base);
            if (c->f_isock) IExec->DropInterface((struct Interface *)c->f_isock);
            if (c->f_sock_base) IExec->CloseLibrary(c->f_sock_base);
            memset(c, 0, sizeof *c);
        }
}

static void register_cleanup(void)
{
    if (!cleanup_registered) {
        atexit(bb_net_task_done);
        cleanup_registered = 1;
    }
}

static int sock_open(char *err, int errlen)
{
    if (ISock) return 1;
    if (!sock_tried) {
        sock_tried = 1;
        register_cleanup();
        sock_base = IExec->OpenLibrary("bsdsocket.library", 4);
        if (sock_base) ISock = (struct SocketIFace *)IExec->GetInterface(sock_base, "main", 1, NULL);
    }
    if (!ISock) {
        snprintf(err, errlen, "no bsdsocket.library: the TCP/IP stack isn't running");
        return 0;
    }
    return 1;
}

/* a path test without "insert volume" requesters */
static int exists(const char *path)
{
    struct Process *me = (struct Process *)IExec->FindTask(NULL);
    APTR old = me->pr_WindowPtr;
    me->pr_WindowPtr = (APTR)-1;
    BPTR l = IDOS->Lock(path, SHARED_LOCK);
    me->pr_WindowPtr = old;
    if (l) IDOS->UnLock(l);
    return l != 0;
}

static int ssl_open(void)
{
    if (ssl_tried) return ssl_ok;
    ssl_tried = 1;
    char e[100];
    if (!sock_open(e, sizeof e)) {
        snprintf(ssl_why, sizeof ssl_why, "%s", e);
        return 0;
    }
    master_base = IExec->OpenLibrary("amisslmaster.library", AMISSLMASTER_MIN_VERSION);
    if (master_base) IMaster = (struct AmiSSLMasterIFace *)IExec->GetInterface(master_base, "main", 1, NULL);
    if (!IMaster) {
        snprintf(ssl_why, sizeof ssl_why, "HTTPS needs AmiSSL (amisslmaster.library %d or newer)", AMISSLMASTER_MIN_VERSION);
        return 0;
    }
    if (IMaster->OpenAmiSSLTags(AMISSL_CURRENT_VERSION,
                                AmiSSL_UsesOpenSSLStructs, TRUE,
                                AmiSSL_GetIAmiSSL, &ISSL,
                                AmiSSL_GetAmiSSLBase, &amissl_base,
                                AmiSSL_GetAmiSSLExtBase, &amissl_ext_base,
                                AmiSSL_ISocket, ISock,
                                AmiSSL_ErrNoPtr, &ssl_errno,
                                TAG_DONE) != 0 || !ISSL) {
        snprintf(ssl_why, sizeof ssl_why, "AmiSSL couldn't be opened (amissl_v3xx.library in LIBS:AmiSSL?)");
        ISSL = NULL;
        return 0;
    }
    ssl_ok = 1;
    return 1;
}

int bb_net_tls_available(char *why, int whylen)
{
    if (ssl_open()) return 1;
    if (why) snprintf(why, whylen, "%s", ssl_why);
    return 0;
}

struct bb_net {
    int fd;
    SSL_CTX *ctx;
    SSL *ssl;
    int nonblock;               /* made by the socket functions below */
    int udp;
};

static void set_timeouts(int fd, int ms)
{
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    ISock->setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    ISock->setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
}

/* wait until fd is readable (rd) or writable; 1 ready, 0 timeout, -1 Ctrl-C */
static int wait_fd(int fd, int wr, int ms)
{
    fd_set set;
    FD_ZERO(&set);
    FD_SET(fd, &set);
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    ULONG sigs = SIGBREAKF_CTRL_C;
    int r = ISock->WaitSelect(fd + 1, wr ? NULL : &set, wr ? &set : NULL, NULL, &tv, &sigs);
    if (r < 0 || (r == 0 && (sigs & SIGBREAKF_CTRL_C))) return -1;
    return r > 0 ? 1 : 0;
}

static int tcp_connect(const char *host, int port, int timeout_ms, int *out, char *err, int errlen)
{
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof sa);
    sa.sin_len = sizeof sa;             /* Roadshow wants it (bind fails with EADDRNOTAVAIL) */
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = ISock->inet_addr((STRPTR)host);
    if (sa.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *he = ISock->gethostbyname((STRPTR)host);
        if (!he || !he->h_addr_list || !he->h_addr_list[0]) {
            snprintf(err, errlen, "can't resolve the host name %s", host);
            return BB_E_NET_RESOLVE;
        }
        memcpy(&sa.sin_addr, he->h_addr_list[0], sizeof sa.sin_addr);
    }
    int fd = ISock->socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    LONG one = 1, zero = 0;
    ISock->IoctlSocket(fd, FIONBIO, (APTR)&one);
    int r = ISock->connect(fd, (struct sockaddr *)&sa, sizeof sa);
    if (r < 0) {
        LONG e = ISock->Errno();
        if (e == EINPROGRESS) {
            int w = wait_fd(fd, 1, timeout_ms);
            if (w <= 0) {
                ISock->CloseSocket(fd);
                if (w < 0) {
                    snprintf(err, errlen, "interrupted (Ctrl-C)");
                    return 18;
                }
                snprintf(err, errlen, "no answer from %s:%d within %d ms", host, port, timeout_ms);
                return BB_E_NET_TIMEOUT;
            }
            LONG soerr = 0;
            socklen_t sl = sizeof soerr;
            ISock->getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
            r = soerr ? -1 : 0;
        }
    }
    if (r < 0) {
        ISock->CloseSocket(fd);
        snprintf(err, errlen, "can't connect to %s:%d", host, port);
        return BB_E_NET_CONNECT;
    }
    ISock->IoctlSocket(fd, FIONBIO, (APTR)&zero);
    set_timeouts(fd, timeout_ms);
    ISock->setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    *out = fd;
    return 0;
}

static void ssl_errstr(char *buf, int len)
{
    unsigned long e = ISSL->ERR_get_error();
    if (e) ISSL->ERR_error_string_n(e, buf, len);
    else snprintf(buf, len, "the connection closed");
}

int bb_net_open(const char *host, int port, int tls, const bb_tls_opts *opts, int timeout_ms, bb_net **out,
                char *err, int errlen)
{
    *out = NULL;
    if (!sock_open(err, errlen)) return BB_E_NET_CONNECT;
    if (tls && !ssl_open()) {
        snprintf(err, errlen, "%s", ssl_why);
        return BB_E_NET_NOTLS;
    }
    int fd;
    int rc = tcp_connect(host, port, timeout_ms, &fd, err, errlen);
    if (rc) return rc;
    bb_net *n = calloc(1, sizeof *n);
    n->fd = fd;
    if (tls) {
        int verify = !opts || opts->verify;
        n->ctx = ISSL->SSL_CTX_new(ISSL->TLS_client_method());
        if (!n->ctx) {
            snprintf(err, errlen, "can't create a TLS context");
            bb_net_close(n);
            return BB_E_NET_TLS;
        }
        if (opts && opts->ca_file && *opts->ca_file) {
            if (ISSL->SSL_CTX_load_verify_locations(n->ctx, opts->ca_file, NULL) != 1) {
                snprintf(err, errlen, "can't read the certificates in %s", opts->ca_file);
                bb_net_close(n);
                return BB_E_NET_CERT;
            }
        } else if (exists("AmiSSL:Certs"))
            ISSL->SSL_CTX_set_default_verify_paths(n->ctx);
        else if (verify) {
            snprintf(err, errlen, "no certificate store: AmiSSL:Certs isn't there (set CACertFile)");
            bb_net_close(n);
            return BB_E_NET_CERT;
        }
        ISSL->SSL_CTX_set_verify(n->ctx, verify ? SSL_VERIFY_PEER : SSL_VERIFY_NONE, NULL);
        n->ssl = ISSL->SSL_new(n->ctx);
        ISSL->SSL_set_fd(n->ssl, fd);
        ISSL->SSL_ctrl(n->ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, (void *)host);  /* SNI */
        if (verify) ISSL->SSL_set1_host(n->ssl, host);
        if (ISSL->SSL_connect(n->ssl) != 1) {
            long v = ISSL->SSL_get_verify_result(n->ssl);
            if (verify && v != X509_V_OK) {
                snprintf(err, errlen, "the certificate of %s isn't trusted: %s", host,
                         ISSL->X509_verify_cert_error_string(v));
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
    double deadline = bb_plat_seconds() + timeout_ms / 1000.0;
    set_timeouts(n->fd, timeout_ms);
    while (len > 0) {
        int w = n->ssl ? ISSL->SSL_write(n->ssl, c, len) : (int)ISock->send(n->fd, (APTR)c, len, 0);
        if (w < 0 && !n->ssl && n->nonblock && ISock->Errno() == EWOULDBLOCK) {
            double left = deadline - bb_plat_seconds();
            int r = left > 0 ? wait_fd(n->fd, 1, (int)(left * 1000) + 1) : 0;
            if (r > 0) continue;
            if (r < 0) {
                snprintf(err, errlen, "interrupted (Ctrl-C)");
                return 18;
            }
            snprintf(err, errlen, "sending timed out");
            return BB_E_NET_TIMEOUT;
        }
        if (w <= 0) {
            if (!n->ssl && ISock->Errno() == EWOULDBLOCK) {
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
    if (n->ssl) {
        set_timeouts(n->fd, timeout_ms);
        int r = ISSL->SSL_read(n->ssl, p, len);
        if (r > 0) return r;
        int e = ISSL->SSL_get_error(n->ssl, r);
        if (e == SSL_ERROR_ZERO_RETURN) return 0;
        if (e == SSL_ERROR_SYSCALL && r == 0) return 0;
        if (e == SSL_ERROR_SYSCALL && (ssl_errno == EWOULDBLOCK || ssl_errno == EAGAIN)) {
            snprintf(err, errlen, "no data within %d ms", timeout_ms);
            return -BB_E_NET_TIMEOUT;
        }
        char es[200];
        ssl_errstr(es, sizeof es);
        snprintf(err, errlen, "TLS read failed: %s", es);
        return -BB_E_NET_PROTOCOL;
    }
    int w = wait_fd(n->fd, 0, timeout_ms);
    if (w < 0) {
        snprintf(err, errlen, "interrupted (Ctrl-C)");
        return -18;
    }
    if (w == 0) {
        snprintf(err, errlen, "no data within %d ms", timeout_ms);
        return -BB_E_NET_TIMEOUT;
    }
    int r = (int)ISock->recv(n->fd, p, len, 0);
    if (r >= 0) return r;
    snprintf(err, errlen, "reading failed (errno %ld)", (long)ISock->Errno());
    return -BB_E_NET_PROTOCOL;
}

void bb_net_close(bb_net *n)
{
    if (!n) return;
    if (n->ssl && ISSL) {
        ISSL->SSL_shutdown(n->ssl);
        ISSL->SSL_free(n->ssl);
    }
    if (n->ctx && ISSL) ISSL->SSL_CTX_free(n->ctx);
    /* at program end net_cleanup (atexit) may have closed bsdsocket.library before the runtime
       releases the last Socket objects: closing the library closed the sockets already */
    if (n->fd >= 0 && ISock) ISock->CloseSocket(n->fd);
    free(n);
}

/* --- sockets for the Socket class --------------------------------------------------------- */

static bb_net *wrap(int fd, int udp)
{
    bb_net *n = calloc(1, sizeof *n);
    LONG one = 1;
    n->fd = fd;
    n->nonblock = 1;
    n->udp = udp;
    ISock->IoctlSocket(fd, FIONBIO, (APTR)&one);
    if (!udp) ISock->setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return n;
}

static int resolve4(const char *host, struct in_addr *a, char *err, int errlen)
{
    if (!host || !*host) {
        a->s_addr = htonl(INADDR_ANY);
        return 0;
    }
    a->s_addr = ISock->inet_addr((STRPTR)host);
    if (a->s_addr == INADDR_NONE) {
        struct hostent *he = ISock->gethostbyname((STRPTR)host);
        if (!he || !he->h_addr_list || !he->h_addr_list[0]) {
            snprintf(err, errlen, "can't resolve the host name %s", host);
            return BB_E_NET_RESOLVE;
        }
        memcpy(a, he->h_addr_list[0], sizeof *a);
    }
    return 0;
}

static void ntoa(struct in_addr a, char *host, int hostlen)
{
    uint32_t x = ntohl(a.s_addr);
    snprintf(host, hostlen, "%lu.%lu.%lu.%lu", (unsigned long)(x >> 24), (unsigned long)((x >> 16) & 255),
             (unsigned long)((x >> 8) & 255), (unsigned long)(x & 255));
}

int bb_net_connect_start(const char *host, int port, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd;
    *out = NULL;
    if (!sock_open(err, errlen)) return BB_E_NET_CONNECT;
    memset(&sa, 0, sizeof sa);
    sa.sin_len = sizeof sa;             /* Roadshow wants it (bind fails with EADDRNOTAVAIL) */
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if ((rc = resolve4(host, &sa.sin_addr, err, errlen))) return rc;
    fd = ISock->socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    if (ISock->connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0 && ISock->Errno() != EINPROGRESS) {
        snprintf(err, errlen, "can't connect to %s:%d", host, port);
        bb_net_close(*out);
        *out = NULL;
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_connect_finish(bb_net *n, char *err, int errlen)
{
    LONG soerr = 0;
    socklen_t sl = sizeof soerr;
    ISock->getsockopt(n->fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
    if (soerr) {
        snprintf(err, errlen, soerr == ECONNREFUSED ? "can't connect: the connection was refused"
                                                    : "can't connect (error %ld)", (long)soerr);
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_listen(const char *addr, int port, int backlog, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd;
    LONG one = 1;
    *out = NULL;
    if (!sock_open(err, errlen)) return BB_E_NET_CONNECT;
    memset(&sa, 0, sizeof sa);
    sa.sin_len = sizeof sa;             /* Roadshow wants it (bind fails with EADDRNOTAVAIL) */
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if ((rc = resolve4(addr, &sa.sin_addr, err, errlen))) return rc;
    fd = ISock->socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    ISock->setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (ISock->bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0 || ISock->listen(fd, backlog > 0 ? backlog : 8) < 0) {
        snprintf(err, errlen, "can't listen on port %d (error %ld)", port, (long)ISock->Errno());
        ISock->CloseSocket(fd);
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    return 0;
}

int bb_net_accept(bb_net *l, bb_net **out, char *err, int errlen)
{
    int fd = ISock->accept(l->fd, NULL, NULL);
    *out = NULL;
    if (fd < 0) {
        LONG e = ISock->Errno();
        if (e == EWOULDBLOCK || e == EINTR || e == ECONNABORTED) return 0;
        snprintf(err, errlen, "accept failed (error %ld)", (long)e);
        return BB_E_NET_CONNECT;
    }
    *out = wrap(fd, 0);
    return 0;
}

int bb_net_udp(const char *addr, int port, bb_net **out, char *err, int errlen)
{
    struct sockaddr_in sa;
    int rc, fd;
    LONG one = 1;
    *out = NULL;
    if (!sock_open(err, errlen)) return BB_E_NET_CONNECT;
    memset(&sa, 0, sizeof sa);
    sa.sin_len = sizeof sa;             /* Roadshow wants it (bind fails with EADDRNOTAVAIL) */
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if ((rc = resolve4(addr, &sa.sin_addr, err, errlen))) return rc;
    fd = ISock->socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        snprintf(err, errlen, "can't create a socket");
        return BB_E_NET_CONNECT;
    }
    ISock->setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof one);
    if (port) ISock->setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (ISock->bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
        snprintf(err, errlen, "can't bind port %d (error %ld)", port, (long)ISock->Errno());
        ISock->CloseSocket(fd);
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
    sa.sin_len = sizeof sa;             /* Roadshow wants it (bind fails with EADDRNOTAVAIL) */
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if ((rc = resolve4(host, &sa.sin_addr, err, errlen))) return rc;
    if (!host || !*host) sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (ISock->sendto(n->fd, (APTR)p, len, 0, (struct sockaddr *)&sa, sizeof sa) < 0) {
        snprintf(err, errlen, "sending to %s:%d failed (error %ld)", host, port, (long)ISock->Errno());
        return BB_E_NET_CONNECT;
    }
    return 0;
}

int bb_net_recvfrom(bb_net *n, void *p, int len, char *host, int hostlen, int *port, char *err, int errlen)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    int r = (int)ISock->recvfrom(n->fd, p, len, 0, (struct sockaddr *)&sa, &sl);
    if (r < 0) {
        LONG e = ISock->Errno();
        if (e == EWOULDBLOCK || e == EINTR) return -1;
        snprintf(err, errlen, "receiving failed (error %ld)", (long)e);
        return -BB_E_NET_PROTOCOL;
    }
    if (host) ntoa(sa.sin_addr, host, hostlen);
    if (port) *port = ntohs(sa.sin_port);
    return r;
}

int bb_net_pending(bb_net *n)
{
    LONG avail = 0;
    char c;
    fd_set set;
    struct timeval tv0 = { 0, 0 };
    if (n->ssl) return 0;
    FD_ZERO(&set);
    FD_SET(n->fd, &set);
    if (ISock->WaitSelect(n->fd + 1, &set, NULL, NULL, &tv0, NULL) <= 0) return 0;   /* (no signals: keeps a Ctrl-C) */
    if (ISock->IoctlSocket(n->fd, FIONREAD, (APTR)&avail) < 0) return -1;
    if (avail > 0) return (int)avail;
    if (n->udp) return 0;
    return ISock->recv(n->fd, &c, 1, MSG_PEEK) > 0 ? 1 : -1;
}

int bb_net_send_some(bb_net *n, const void *p, int len, char *err, int errlen)
{
    int w = (int)ISock->send(n->fd, (APTR)p, len, 0);
    if (w >= 0) return w;
    if (ISock->Errno() == EWOULDBLOCK) return 0;
    snprintf(err, errlen, "the connection closed while sending");
    return -BB_E_NET_PROTOCOL;
}

void bb_net_addr(bb_net *n, int peer, char *host, int hostlen, int *port)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    memset(&sa, 0, sizeof sa);
    if ((peer ? ISock->getpeername(n->fd, (struct sockaddr *)&sa, &sl)
              : ISock->getsockname(n->fd, (struct sockaddr *)&sa, &sl)) < 0) {
        if (host && hostlen) host[0] = 0;
        if (port) *port = 0;
        return;
    }
    if (host) ntoa(sa.sin_addr, host, hostlen);
    if (port) *port = ntohs(sa.sin_port);
}

int bb_net_wait(bb_net **ns, const int *want, int *got, int count, int timeout_ms, uint32_t *sigs)
{
    fd_set rd, wr;
    struct timeval tv, *tp = NULL;
    ULONG mask = sigs ? *sigs : 0;
    int i, maxfd = -1, r, nready = 0;
    FD_ZERO(&rd);
    FD_ZERO(&wr);
    for (i = 0; i < count; i++) {
        if (want[i] & BB_NET_RD) FD_SET(ns[i]->fd, &rd);
        if (want[i] & BB_NET_WR) FD_SET(ns[i]->fd, &wr);
        if (want[i] && ns[i]->fd > maxfd) maxfd = ns[i]->fd;
    }
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        tp = &tv;
    }
    if (!ISock) {
        /* no socket was ever opened (count is 0): a plain wait for the signals */
        ULONG got_sigs;
        if (timeout_ms < 0) got_sigs = mask ? IExec->Wait(mask) : 0;
        else {
            if (timeout_ms > 0) bb_plat_sleep_ms(timeout_ms);
            got_sigs = IExec->SetSignal(0, mask) & mask;
        }
        if (sigs) *sigs = got_sigs;
        return 0;
    }
    {
        ULONG orig = mask;
        r = ISock->WaitSelect(maxfd + 1, &rd, &wr, NULL, tp, orig ? &mask : NULL);
        if (sigs) {
            ULONG g = r < 0 ? 0 : mask & orig;
            /* a zero timeout is a look: signals that were already set count too */
            if (orig && (timeout_ms == 0 || r < 0)) g |= IExec->SetSignal(0, orig) & orig;
            *sigs = g;
        }
    }
    for (i = 0; i < count; i++) {
        int g = 0;
        if (r > 0) {
            if ((want[i] & BB_NET_RD) && FD_ISSET(ns[i]->fd, &rd)) g |= BB_NET_RD;
            if ((want[i] & BB_NET_WR) && FD_ISSET(ns[i]->fd, &wr)) g |= BB_NET_WR;
        }
        got[i] = g;
        if (g) nready++;
    }
    return r < 0 ? -1 : nready;
}

int bb_net_machine_addr(char *host, int hostlen)
{
    struct sockaddr_in sa;
    socklen_t sl = sizeof sa;
    char e[100];
    int fd, ok = 0;
    snprintf(host, hostlen, "127.0.0.1");
    if (!sock_open(e, sizeof e)) return 0;
    fd = ISock->socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return 0;
    memset(&sa, 0, sizeof sa);
    sa.sin_len = sizeof sa;
    sa.sin_family = AF_INET;
    sa.sin_port = htons(53);
    sa.sin_addr.s_addr = htonl(0x08080808);         /* any outside address: no packet is sent */
    if (ISock->connect(fd, (struct sockaddr *)&sa, sizeof sa) == 0 &&
        ISock->getsockname(fd, (struct sockaddr *)&sa, &sl) == 0 && sa.sin_addr.s_addr) {
        ntoa(sa.sin_addr, host, hostlen);
        ok = 1;
    }
    ISock->CloseSocket(fd);
    return ok;
}
