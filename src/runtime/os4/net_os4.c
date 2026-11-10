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

static struct Library *sock_base;
static struct SocketIFace *ISock;
static struct Library *master_base;
static struct AmiSSLMasterIFace *IMaster;
static struct Library *amissl_base, *amissl_ext_base;
static struct AmiSSLIFace *ISSL;
static int sock_tried, ssl_tried, ssl_ok;
static char ssl_why[200];
static int ssl_errno;
static int cleanup_registered;

static void net_cleanup(void)
{
    if (ISSL && IMaster) IMaster->CloseAmiSSL();
    ISSL = NULL;
    if (IMaster) IExec->DropInterface((struct Interface *)IMaster);
    if (master_base) IExec->CloseLibrary(master_base);
    IMaster = NULL;
    master_base = NULL;
    if (ISock) IExec->DropInterface((struct Interface *)ISock);
    if (sock_base) IExec->CloseLibrary(sock_base);
    ISock = NULL;
    sock_base = NULL;
}

static void register_cleanup(void)
{
    if (!cleanup_registered) {
        atexit(net_cleanup);
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
    set_timeouts(n->fd, timeout_ms);
    while (len > 0) {
        int w = n->ssl ? ISSL->SSL_write(n->ssl, c, len) : (int)ISock->send(n->fd, (APTR)c, len, 0);
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
    if (n->ssl) {
        ISSL->SSL_shutdown(n->ssl);
        ISSL->SSL_free(n->ssl);
    }
    if (n->ctx) ISSL->SSL_CTX_free(n->ctx);
    if (n->fd >= 0) ISock->CloseSocket(n->fd);
    free(n);
}
