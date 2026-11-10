/* net.h - TCP connections with optional TLS, for the Http class (http.c) and later sockets.
 * One implementation per platform: os4/net_os4.c (bsdsocket.library + AmiSSL, both opened on
 * first use, AmiSSL given the same bsdsocket interface so the TLS layer works on our sockets)
 * and posix/net_posix.c (BSD sockets + OpenSSL loaded with dlopen when present).
 *
 * Errors are the Boing BASIC run-time error numbers below (raised by the BASIC layer with a
 * message in err). */
#ifndef BB_NET_H
#define BB_NET_H

#include <stdint.h>

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


/* --- sockets for the Socket class (socket.c) ------------------------------------------------
 * IPv4. A bb_net made here is non-blocking: reads and writes below never wait unless they take
 * a timeout. bb_net_read/bb_net_write work on connected ones too (with their timeouts). */
enum { BB_NET_RD = 1, BB_NET_WR = 2 };
#define BB_NET_SIG_BREAK 0x1000u      /* Ctrl-C (SIGBREAKF_CTRL_C) in bb_net_wait's *sigs */

/* resolve host (waits for the resolver) and start connecting; finish when writable */
int bb_net_connect_start(const char *host, int port, bb_net **out, char *err, int errlen);
/* after the socket became writable: 0 connected, or an error number */
int bb_net_connect_finish(bb_net *n, char *err, int errlen);
/* TCP server socket on address (NULL or "" = any) and port (0 = any free one) */
int bb_net_listen(const char *addr, int port, int backlog, bb_net **out, char *err, int errlen);
/* take a waiting connection: 0 with *out (NULL when none is waiting), or an error number */
int bb_net_accept(bb_net *l, bb_net **out, char *err, int errlen);
/* UDP socket bound to address/port (port 0 = any free one) */
int bb_net_udp(const char *addr, int port, bb_net **out, char *err, int errlen);
int bb_net_sendto(bb_net *n, const char *host, int port, const void *p, int len, char *err, int errlen);
/* the next datagram: its length (0 is a valid empty datagram), -1 when none is waiting, or
 * -(error number); host/port receive the sender */
int bb_net_recvfrom(bb_net *n, void *p, int len, char *host, int hostlen, int *port, char *err, int errlen);
/* bytes that can be read now without waiting: > 0, 0 none, -1 the peer closed (end of stream)
 * or the connection failed. For UDP the size of the next datagram (0 none waiting). */
int bb_net_pending(bb_net *n);
/* write what fits now: the count (may be 0), or -(error number) */
int bb_net_send_some(bb_net *n, const void *p, int len, char *err, int errlen);
/* the local (peer = 0) or remote address as dotted quad and port */
void bb_net_addr(bb_net *n, int peer, char *host, int hostlen, int *port);
/* wait until one of the sockets is ready (want[i]: BB_NET_RD|BB_NET_WR; got[i] receives what
 * is), at most timeout_ms (-1 = no limit, 0 = just look). On AmigaOS also until one of the
 * signals in *sigs arrives (WaitSelect); *sigs receives the signals that did. sigs may be NULL.
 * Returns the number of ready sockets, 0 (timeout or a signal), or -1 on an error. */
/* this machine's IPv4 address on the network (the interface of the default route); 0 and
   "127.0.0.1" when there is none */
int bb_net_machine_addr(char *host, int hostlen);
int bb_net_wait(bb_net **ns, const int *want, int *got, int count, int timeout_ms, uint32_t *sigs);

#endif
