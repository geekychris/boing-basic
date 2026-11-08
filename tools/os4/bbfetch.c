/* bbfetch URL OUTFILE [CRC32HEX] - fetch a file over plain HTTP/1.0 onto the AmigaOS 4 guest
 * (the fast deploy path of tools/os4guest.py: the Mac serves files, the guest fetches them
 * through QEMU's user-mode network, whose gateway 192.168.101.2 / 192.168.100.2 is the Mac's
 * localhost). Writes to OUTFILE.part, checks the length (Content-Length) and the CRC-32 if
 * given, then renames to OUTFILE. Prints "OK <bytes> <crc32>" or "FAIL <reason>".
 * Built on the guest with the SDK's GCC: gcc -mcrt=newlib -mcpu=powerpc -O2 -o bbfetch bbfetch.c -lauto */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/bsdsocket.h>
#include <netinet/in.h>
#include <sys/socket.h>

static const char __attribute__((used)) stack_cookie[] = "$STACK:65536";

struct Library *SocketBase;
struct SocketIFace *ISocket;

static unsigned long crc_table[256];

static void crc_init(void)
{
    for (unsigned long n = 0; n < 256; n++) {
        unsigned long c = n;
        for (int k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320UL ^ (c >> 1) : c >> 1;
        crc_table[n] = c;
    }
}

static unsigned long crc_update(unsigned long crc, const unsigned char *p, long n)
{
    crc ^= 0xFFFFFFFFUL;
    while (n--) crc = crc_table[(crc ^ *p++) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFUL;
}

static int fail(const char *why)
{
    printf("FAIL %s\n", why);
    return 10;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        printf("usage: bbfetch http://host:port/path OUTFILE [CRC32HEX]\n");
        return 5;
    }
    const char *url = argv[1], *out = argv[2];
    unsigned long want = argc > 3 ? strtoul(argv[3], NULL, 16) : 0;
    int check = argc > 3;
    if (strncmp(url, "http://", 7)) return fail("only http:// URLs");
    char host[64], path[512];
    int port = 80;
    const char *h = url + 7, *slash = strchr(h, '/'), *colon = strchr(h, ':');
    if (!slash) slash = h + strlen(h);
    if (colon && colon < slash) {
        snprintf(host, sizeof host, "%.*s", (int)(colon - h), h);
        port = atoi(colon + 1);
    } else
        snprintf(host, sizeof host, "%.*s", (int)(slash - h), h);
    snprintf(path, sizeof path, "%s", *slash ? slash : "/");

    SocketBase = IExec->OpenLibrary("bsdsocket.library", 4);
    if (!SocketBase) return fail("no bsdsocket.library (TCP/IP stack not running?)");
    ISocket = (struct SocketIFace *)IExec->GetInterface(SocketBase, "main", 1, NULL);
    if (!ISocket) return fail("no bsdsocket interface");

    int rc = 10;
    int s = ISocket->socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = ISocket->inet_addr(host);
    if (s < 0 || ISocket->connect(s, (struct sockaddr *)&sa, sizeof sa) < 0) {
        fail("connect");
        goto done;
    }
    char req[700];
    int rl = snprintf(req, sizeof req, "GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", path, host);
    if (ISocket->send(s, req, rl, 0) != rl) {
        fail("send");
        goto done;
    }

    char part[600];
    snprintf(part, sizeof part, "%s.part", out);
    BPTR fh = IDOS->Open(part, MODE_NEWFILE);
    if (!fh) {
        fail("can't create the output file");
        goto done;
    }
    crc_init();
    static unsigned char buf[65536];
    long have = 0, body = 0, total = 0, clen = -1;
    unsigned long crc = 0;
    int in_body = 0, status = 0;
    for (;;) {
        long n = ISocket->recv(s, buf + have, sizeof buf - have, 0);
        if (n <= 0) break;
        have += n;
        long start = 0;
        if (!in_body) {
            /* headers end at the blank line */
            unsigned char *e = NULL;
            for (long i = 0; i + 3 < have; i++)
                if (!memcmp(buf + i, "\r\n\r\n", 4)) { e = buf + i; break; }
            if (!e) {
                if (have == (long)sizeof buf) break;
                continue;
            }
            *e = 0;
            status = atoi((char *)buf + 9);
            char *cl = strstr((char *)buf, "Content-Length:");
            if (!cl) cl = strstr((char *)buf, "content-length:");
            if (cl) clen = atol(cl + 15);
            in_body = 1;
            start = (e - buf) + 4;
            if (status != 200) break;
        }
        body = have - start;
        if (body > 0) {
            if (IDOS->Write(fh, buf + start, body) != body) {
                status = -1;
                break;
            }
            crc = crc_update(crc, buf + start, body);
            total += body;
        }
        have = 0;
    }
    IDOS->Close(fh);
    if (status != 200) {
        char why[40];
        snprintf(why, sizeof why, "HTTP status %d", status);
        fail(why);
        IDOS->Delete(part);
    } else if (clen >= 0 && total != clen) {
        fail("short read");
        IDOS->Delete(part);
    } else if (check && crc != want) {
        fail("CRC mismatch");
        IDOS->Delete(part);
    } else {
        IDOS->Delete(out);
        if (!IDOS->Rename(part, out)) fail("rename");
        else {
            printf("OK %ld %08lx\n", total, crc);
            rc = 0;
        }
    }
done:
    if (s >= 0) ISocket->CloseSocket(s);
    IExec->DropInterface((struct Interface *)ISocket);
    IExec->CloseLibrary(SocketBase);
    return rc;
}
