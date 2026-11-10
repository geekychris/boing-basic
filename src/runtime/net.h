/* net.h - TCP connections with optional TLS, for the Http class (http.c) and later sockets.
 * One implementation per platform: os4/net_os4.c (bsdsocket.library + AmiSSL, both opened on
 * first use, AmiSSL given the same bsdsocket interface so the TLS layer works on our sockets)
 * and posix/net_posix.c (BSD sockets + OpenSSL loaded with dlopen when present).
 *
 * Errors are the Boing BASIC run-time error numbers below (raised by the BASIC layer with a
 * message in err). */
#ifndef BB_NET_H
#define BB_NET_H

enum {
    BB_E_NET_URL = 31101,       /* bad or unsupported URL */
    BB_E_NET_RESOLVE = 31102,   /* the host name can't be resolved */
    BB_E_NET_CONNECT = 31103,   /* connection refused / unreachable */
    BB_E_NET_TIMEOUT = 31104,   /* no answer within Timeout */
    BB_E_NET_TLS = 31105,       /* the TLS handshake failed */
    BB_E_NET_CERT = 31106,      /* the server's certificate isn't trusted, or is for another host */
    BB_E_NET_REDIRECTS = 31107, /* too many redirects */
    BB_E_NET_NOTLS = 31108,     /* HTTPS isn't available (no AmiSSL / OpenSSL) */
    BB_E_NET_PROTOCOL = 31109,  /* the connection closed early, or the answer isn't HTTP */
    BB_E_NET_IO = 31110,        /* a local file couldn't be written */
};

typedef struct bb_net bb_net;

typedef struct bb_tls_opts {
    int verify;                 /* check the certificate chain and the host name (default 1) */
    const char *ca_file;        /* PEM file with trusted certificates, or NULL for the system's */
} bb_tls_opts;

/* Connect to host:port, with TLS (and SNI, verification as in opts) when tls is nonzero.
 * Returns 0 and *out, or an error number with a message in err. */
int bb_net_open(const char *host, int port, int tls, const bb_tls_opts *opts, int timeout_ms, bb_net **out,
                char *err, int errlen);
/* Send all len bytes: 0 or an error number. */
int bb_net_write(bb_net *n, const void *p, int len, int timeout_ms, char *err, int errlen);
/* Read up to len bytes: the count (> 0), 0 at the end of the stream, or -(error number). */
int bb_net_read(bb_net *n, void *p, int len, int timeout_ms, char *err, int errlen);
void bb_net_close(bb_net *n);

/* Close the calling task's network resources (OS4: its bsdsocket/AmiSSL bases); a worker task
 * calls this before it ends. A no-op on the host. */
void bb_net_task_done(void);

/* Is TLS available? 1, or 0 with the reason in why. */
int bb_net_tls_available(char *why, int whylen);

#endif
