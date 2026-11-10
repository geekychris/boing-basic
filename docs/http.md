# Http: HTTP and HTTPS from Boing BASIC

`Http` is a built-in class for talking to web servers: fetch a page, call a REST/JSON API, post
a form, download a file. It speaks HTTP/1.1 and HTTPS (TLS with certificate checking) on
AmigaOS 4 and on the host (macOS/Linux).

```basic
Dim web As Http
Set web = CreateObject("Http")
page = web.Get("https://example.com/")
If web.Status = 200 Then Print Len(page); " bytes of "; web.ContentType
```

![webfetch example](images/webfetch.png)

*`examples/webfetch` on AmigaOS 4: a form that fetches a URL into a text editor.*

## Making requests

| Method | Does | Returns |
|---|---|---|
| `Get(url)` | GET | the body (String) |
| `Post(url, body [, contentType])` | POST `body`; content type defaults to `application/x-www-form-urlencoded` | the body |
| `Put(url, body [, contentType])` | PUT | the body |
| `Delete(url)` | DELETE | the body |
| `Head(url)` | HEAD (headers only) | "" |
| `Send(method, url [, body [, contentType]])` | any method (`"PATCH"`, ...) | the body |
| `GetToFile(url, path)` | GET, the body written to `path` (not kept in memory) | the number of bytes |

Every method waits until the whole answer is in (or an error happens). The body is the bytes
the server sent, in a String; Boing BASIC strings hold any bytes, so binary data is fine.
No character set conversion is done: most web pages are UTF-8, while the Amiga uses Latin-1,
so accented letters in UTF-8 text show as two characters (a UTF-8 conversion function is on
the list of coming libraries).

## Request settings

| Property / method | Default | |
|---|---|---|
| `SetHeader name, value` | | adds a request header for all later requests (`SetHeader name, ""` removes it) |
| `ClearHeaders` | | removes all of them |
| `Timeout` | 30000 | milliseconds for connecting and for each wait for data |
| `FollowRedirects` | True | follow 301/302/303/307/308 answers |
| `MaxRedirects` | 10 | more raises error 31107 |
| `VerifyCertificate` | True | check the server's certificate chain and its host name (HTTPS) |
| `CACertFile` | "" | a PEM file of trusted certificates instead of the system's store |
| `UserAgent` | `BoingBASIC/1.0` | |

A 303 answer (and, as browsers do, a 301/302 after a POST) continues with a GET without body;
307 and 308 repeat the request as it was.

## The answer

| Property / method | |
|---|---|
| `Status` | 200, 404, ... (0 before the first request) |
| `StatusText` | "OK", "Not Found", ... |
| `ResponseText` | the body again (the default member: `Print web`) |
| `ResponseHeader(name)` | one header's value, any case; "" if absent |
| `ResponseHeaders` | all headers, `Name: value` lines |
| `ContentType` | the `Content-Type` header |
| `Url` | the URL the answer came from (after redirects) |
| `Redirects` | how many redirects were followed |
| `BytesReceived` | body length |
| `TlsAvailable()` | True if HTTPS can be used here |

## Errors

An answer with an error status (404, 500, ...) is still an answer: check `Status`. Problems
that leave no answer raise a run-time error, catchable with `On Error`:

| `Err.Number` | |
|---|---|
| 31101 | bad or unsupported URL (only `http://` and `https://`) |
| 31102 | the host name can't be resolved |
| 31103 | can't connect (refused, unreachable, no TCP/IP stack) |
| 31104 | no answer within `Timeout` |
| 31105 | the TLS handshake failed |
| 31106 | the certificate isn't trusted, or is for another host |
| 31107 | too many redirects |
| 31108 | HTTPS isn't available (no AmiSSL / OpenSSL) |
| 31109 | the connection closed early, or the answer isn't HTTP |
| 31110 | `GetToFile` couldn't write the file |
| 18 | interrupted with Ctrl-C (AmigaOS) |

`Err.Description` says what happened ("the certificate of example.com isn't trusted:
certificate has expired").

```basic
On Error GoTo Failed
data = web.Get(url)
...
Failed:
    MsgBox "Can't fetch " & url & ":" & vbLf & Err.Description, vbExclamation
```

## Examples

```basic
' JSON API with a token
web.SetHeader "Authorization", "Bearer " & token
web.SetHeader "Accept", "application/json"
reply = web.Post("https://api.example.com/v1/items", "{""name"":""Boing""}", "application/json")
If web.Status <> 201 Then Print "failed: "; web.Status; " "; reply

' download a file
n = web.GetToFile("https://example.com/files/game.lha", "RAM:game.lha")
Print n; " bytes"

' a local test server with its own certificate authority
web.CACertFile = "PROGDIR:test-ca.pem"
```

## How it works, per platform

**AmigaOS 4.** TCP goes through `bsdsocket.library` (Roadshow), TLS through AmiSSL
(`amisslmaster.library` → `amissl_v3xx.library`). Both are opened on the first request, so a
program that never uses `Http` doesn't need a running TCP/IP stack or AmiSSL. Certificates
are checked against AmiSSL's store, `AmiSSL:Certs` (installed with AmiSSL), plus the host
name. AmiSSL is given the program's own bsdsocket interface, so the TLS layer works on the
program's sockets (the Python 3.12 port's `_ssl` module trips over exactly this and shells out
to `openssl s_client` instead). Host names are resolved with `gethostbyname` (no timeout).

**Host (macOS, Linux).** BSD sockets; TLS through OpenSSL 3, loaded when the first HTTPS
request is made (`libssl.3`, or the directory in `BOING_OPENSSL_DIR`). Where OpenSSL isn't
installed, HTTPS raises error 31108 and HTTP still works. On macOS with Homebrew's OpenSSL the
default certificate store is Homebrew's.

## Tests

- `tests-net/run.sh` (part of `make test`): `tools/http_testserver.py` serves HTTP and HTTPS
  (with a generated test CA) on the host; `tests-net/httptest.bas` checks 38 cases in the VM and
  as a native build: GET/POST/PUT/DELETE/HEAD/PATCH, headers, chunked bodies, redirects
  (relative, 303, loops, the limit), 300 KB binary bodies, `GetToFile`, timeouts, bad URLs,
  unknown hosts, refused connections, HTTPS with the CA, an untrusted certificate,
  `VerifyCertificate = False`.
- `tests-net/os4-run.sh`: the same 38 checks on the AmigaOS 4 guest (QEMU), VM and native,
  through AmiSSL, against the test server on the Mac (reached at the QEMU gateway
  192.168.101.2). 2026-11-10: 38/38 both.

## Not yet

Asynchronous requests with events (so a form stays responsive during a long download),
`Content-Encoding: gzip`, cookies, proxies, keep-alive connections, IPv6 on AmigaOS.
