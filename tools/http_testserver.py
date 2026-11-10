#!/usr/bin/env python3
"""http_testserver.py - the local HTTP + HTTPS server the Http class tests talk to.

    tools/http_testserver.py [--bind 127.0.0.1] [--certs DIR] [--ports-file FILE]

Serves plain HTTP and HTTPS (a certificate for localhost, 127.0.0.1 and the QEMU guest's
gateway addresses 192.168.100.2/192.168.101.2, signed by a test CA it generates in --certs
with the openssl command) on free ports, and writes "http_port https_port ca_file" to
--ports-file once it listens. Endpoints:

  /hello                 text "Hello, Boing!"
  /json                  a small JSON document
  /page                  a small HTML page (for screenshots of the examples)
  /echo                  method, path, X-Test header, Content-Type and the body, one per line
  /status/N              status N, body "status N"
  /redirect/N            N redirects (302) ending at /hello;  /redirect-loop redirects forever
  /relative              302 with a relative Location (hello)
  /see-other             303 to /echo (a POST continues as GET without body)
  /chunked               a chunked body (5 chunks)
  /drip                  5000 bytes in 50 chunks over 5 s (progress and Cancel tests)
  /slow                  waits 5 s before answering
  /big?n=BYTES           BYTES bytes of a known pattern (byte i = i mod 251)
  /headers               sets X-One and X-Two response headers
"""
import argparse
import http.server
import os
import socket
import ssl
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse, parse_qs


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, status, body, ctype="text/plain", extra=None):
        if isinstance(body, str):
            body = body.encode("latin-1")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def handle_any(self):
        u = urlparse(self.path)
        p = u.path
        if p == "/page":
            return self.send(200, "<!DOCTYPE html>\n<html>\n<head><title>Boing BASIC test page</title></head>\n"
                                  "<body>\n<h1>Hello from the Mac</h1>\n<p>This page came over the network\n"
                                  "fetched by a Boing BASIC program\nwith its Http class.</p>\n</body>\n</html>\n",
                             "text/html; charset=iso-8859-1")
        if p == "/json":
            return self.send(200, '{"name": "Boing BASIC", "platform": {"os": "AmigaOS 4.1", "cpu": "PowerPC"}, '
                                  '"libraries": ["Http", "Dictionary", "JSON"], "year": 2026, "stable": false, '
                                  '"maintainer": null}', "application/json")
        if p == "/hello":
            return self.send(200, "Hello, Boing!")
        if p == "/echo":
            b = self.body().decode("latin-1")
            return self.send(200, "method=%s\npath=%s\nx-test=%s\ncontent-type=%s\nbody=%s\n" % (
                self.command, self.path, self.headers.get("X-Test", ""), self.headers.get("Content-Type", ""), b))
        if p.startswith("/status/"):
            n = int(p.split("/")[2])
            return self.send(n, "status %d" % n)
        if p.startswith("/redirect/"):
            n = int(p.split("/")[2])
            return self.send(302, "", extra={"Location": "/hello" if n <= 1 else "/redirect/%d" % (n - 1)})
        if p == "/redirect-loop":
            return self.send(302, "", extra={"Location": "/redirect-loop"})
        if p == "/relative":
            return self.send(302, "", extra={"Location": "hello"})
        if p == "/see-other":
            self.body()
            return self.send(303, "", extra={"Location": "/echo"})
        if p == "/headers":
            return self.send(200, "ok", extra={"X-One": "1", "X-Two": "two words"})
        if p == "/slow":
            time.sleep(5)
            return self.send(200, "slow")
        if p == "/big":
            n = int(parse_qs(u.query).get("n", ["100000"])[0])
            data = bytes(i % 251 for i in range(n))
            return self.send(200, data, "application/octet-stream")
        if p == "/drip":
            # 50 chunks of 100 bytes, one every 100 ms (5 s in all): for progress and Cancel
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                for i in range(50):
                    self.wfile.write(b"64\r\n" + b"d" * 100 + b"\r\n")
                    self.wfile.flush()
                    time.sleep(0.1)
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if p == "/chunked":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.end_headers()
            for part in ["one ", "two ", "three ", "four ", "five"]:
                d = part.encode()
                self.wfile.write(b"%x\r\n%s\r\n" % (len(d), d))
            self.wfile.write(b"0\r\n\r\n")
            return
        self.send(404, "not found")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = handle_any


def make_certs(d):
    ca, key = os.path.join(d, "ca.pem"), os.path.join(d, "server.key")
    crt = os.path.join(d, "server.pem")
    if all(os.path.exists(f) for f in (ca, key, crt)):
        return ca, key, crt
    os.makedirs(d, exist_ok=True)
    run = lambda *a: subprocess.run(a, check=True, capture_output=True, cwd=d)
    run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650", "-subj", "/CN=Boing Test CA",
        "-keyout", "ca.key", "-out", "ca.pem")
    run("openssl", "req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost", "-keyout", "server.key",
        "-out", "server.csr")
    open(os.path.join(d, "san.ext"), "w").write(
        "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:192.168.100.2,IP:192.168.101.2\n"
        "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
    run("openssl", "x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
        "-days", "3650", "-extfile", "san.ext", "-out", "server.pem")
    return ca, key, crt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--certs", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "net-certs"))
    ap.add_argument("--ports-file")
    ap.add_argument("--http-port", type=int, default=0)
    ap.add_argument("--https-port", type=int, default=0)
    a = ap.parse_args()
    ca, key, crt = make_certs(os.path.abspath(a.certs))
    plain = http.server.ThreadingHTTPServer((a.bind, a.http_port), H)
    tls = http.server.ThreadingHTTPServer((a.bind, a.https_port), H)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(crt, key)
    tls.socket = ctx.wrap_socket(tls.socket, server_side=True)
    for s in (plain, tls):
        threading.Thread(target=s.serve_forever, daemon=True).start()
    line = "%d %d %s\n" % (plain.server_address[1], tls.server_address[1], ca)
    if a.ports_file:
        tmp = a.ports_file + ".tmp"
        open(tmp, "w").write(line)
        os.replace(tmp, a.ports_file)
    else:
        sys.stdout.write(line)
        sys.stdout.flush()
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
