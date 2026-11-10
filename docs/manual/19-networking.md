# Networking and modern libraries

This chapter shows how a Boing BASIC program talks to the internet: fetching web pages,
calling web services that answer in JSON, posting data and downloading files, over HTTP and
HTTPS. It also lists the other modern libraries that are on their way.

## The Http object

`Http` is a built-in object for talking to web servers. It speaks HTTP/1.1 and HTTPS
(encrypted, with the server's certificate checked) on AmigaOS 4, and also on macOS and Linux
when you test a program there. Create one with `CreateObject`:

*Listing 19.1* (`examples/book/ch19-networking/listing-19-01.bas`)

```basic
Option Explicit
Dim web As Http, page As String
Set web = CreateObject("Http")
page = web.Get("https://example.com/")
If web.Status = 200 Then
    Print Len(page); " bytes of "; web.ContentType
Else
    Print "The server said "; web.Status; " "; web.StatusText
End If
```

Declaring the variable `As Http` lets the compiler check the names you use (`web.Gte` is an
error when you compile, not when the program runs), and lets AmiForge complete them.

### What AmigaOS needs

`Http` uses the computer's TCP/IP stack (Roadshow, `bsdsocket.library`) and, for `https://`
addresses, AmiSSL. Both come with AmigaOS 4.1 Final Edition. They are opened when the program
makes its first request, so a program that only uses `Http` sometimes still starts without a
network. `web.TlsAvailable()` tells you whether HTTPS can be used:

*Listing 19.2* (`examples/book/ch19-networking/listing-19-02.bas`)

```basic
Dim web As Http
Set web = CreateObject("Http")
If web.TlsAvailable() Then
    Print "HTTPS works here"
Else
    Print "No AmiSSL: http:// addresses only"
End If
```

## Making requests

Each request method waits until the whole answer has arrived (or something goes wrong) and
returns the body: the page, the JSON text, the file's bytes. A String can hold any bytes, so
binary data is fine.

| Method | What it does | Returns |
|---|---|---|
| `Get(url)` | fetch a page | the body |
| `Post(url, body [, contentType])` | send `body`; the content type is `application/x-www-form-urlencoded` unless you give one | the body |
| `Put(url, body [, contentType])` | upload `body` | the body |
| `Delete(url)` | delete | the body |
| `Head(url)` | fetch only the headers | `""` |
| `Send(method, url [, body [, contentType]])` | any other method, such as `"PATCH"` | the body |
| `GetToFile(url, path)` | download straight into a file, without keeping it in memory | the number of bytes |

Downloading a file:

*Listing 19.3* (`examples/book/ch19-networking/listing-19-03.bas`)

```basic
Dim web As Http, n As Long
Set web = CreateObject("Http")
n = web.GetToFile("https://example.com/", "RAM:example.html")
Print n; " bytes saved"
```

Posting a form:

*Listing 19.4* (`examples/book/ch19-networking/listing-19-04.bas`)

```basic
Dim web As Http, reply As String
Set web = CreateObject("Http")
reply = web.Post("https://httpbin.org/post", "name=Boing&colour=red")
Print web.Status
```

## Request settings

| Property or method | Default | What it does |
|---|---|---|
| `SetHeader name, value` | | adds a header to every later request; `SetHeader name, ""` removes it |
| `ClearHeaders` | | removes all the headers you set |
| `Timeout` | 30000 | milliseconds to wait for a connection, and for each piece of data |
| `FollowRedirects` | True | follow the server's "moved" answers (301, 302, 303, 307, 308) |
| `MaxRedirects` | 10 | how many to follow before giving up with error 31107 |
| `VerifyCertificate` | True | check that an HTTPS server's certificate is valid and is for that host |
| `CACertFile` | `""` | a file of trusted certificates (PEM) to use instead of the system's |
| `UserAgent` | `BoingBASIC/1.0` | how the program introduces itself to the server |

Keep `VerifyCertificate` on: turned off, a program cannot tell the real server from an
impostor. Turn it off only to talk to a test server of your own, and better still give that
server's certificate with `CACertFile`.

## The answer

| Property or method | What it is |
|---|---|
| `Status` | the server's status code: 200 OK, 404 not found, ... (0 before the first request) |
| `StatusText` | its text: `"OK"`, `"Not Found"`, ... |
| `ResponseText` | the body of the last answer again (also what `Print web` prints) |
| `ResponseHeader(name)` | the value of one header, in any case; `""` if there isn't one |
| `ResponseHeaders` | all the headers, one `Name: value` per line |
| `ContentType` | the `Content-Type` header, e.g. `text/html; charset=utf-8` |
| `Url` | the address the answer came from, after any redirects |
| `Redirects` | how many redirects were followed |
| `BytesReceived` | the length of the body |

An error page (404, 500 ...) is still an answer: check `Status` before using the body.

## Errors

Problems that leave no answer at all raise a run-time error, which a program catches with
`On Error` (see [Errors and error handling](08-errors.md)):

| `Err.Number` | Meaning |
|---|---|
| 31101 | the address is not a valid `http://` or `https://` URL |
| 31102 | the host name can't be found |
| 31103 | can't connect (refused, unreachable, no TCP/IP stack running) |
| 31104 | no answer within `Timeout` |
| 31105 | the encrypted connection could not be set up |
| 31106 | the certificate isn't trusted, or is for another host |
| 31107 | too many redirects |
| 31108 | HTTPS isn't available (AmiSSL isn't installed) |
| 31109 | the connection closed early, or the answer isn't HTTP |
| 31110 | `GetToFile` couldn't write the file |
| 18 | the user pressed Ctrl-C |

`Err.Description` explains what happened, for example
`the certificate of example.com isn't trusted: certificate has expired`.

*Listing 19.5* (`examples/book/ch19-networking/listing-19-05.bas`)

```basic
Option Explicit
Dim web As Http, page As String
Set web = CreateObject("Http")
On Error GoTo Failed
page = web.Get("https://no-such-host.example/")
Print "Fetched "; Len(page); " bytes"
End
Failed:
Print "Can't fetch the page: "; Err.Description
```

## Text and character sets

Most web pages and web services send text in UTF-8, while AmigaOS uses Latin-1. `Http` gives
you the bytes as they came, so an accented letter in UTF-8 text shows as two characters. Plain
English text and numbers are the same in both. (A conversion function is among the coming
libraries below.)

## Working with JSON

Many web services answer in JSON, a text format of names and values:

```text
{"full_name":"geekychris/amiforge","description":"An IDE for AmigaOS 4.1","stargazers_count":12}
```

Until the JSON library arrives, a small function can pick out values from simple answers like
this one. `JsonText` finds `"key"`, then the string after its colon; `JsonNumber` reads the
number after the colon:

*Listing 19.6* (`examples/book/ch19-networking/listing-19-06.bas`)

<!-- run -->
```basic
Option Explicit

Function JsonText(json As String, key As String) As String
    Dim p As Long, q As Long
    p = InStr(json, """" & key & """")
    If p = 0 Then Exit Function
    p = InStr(p + Len(key) + 2, json, ":")
    p = InStr(p, json, """")
    If p = 0 Then Exit Function
    q = p + 1
    Do While q <= Len(json)
        If Mid(json, q, 1) = "\" Then
            q = q + 2
        ElseIf Mid(json, q, 1) = """" Then
            Exit Do
        Else
            q = q + 1
        End If
    Loop
    JsonText = Replace(Mid(json, p + 1, q - p - 1), "\""", """")
End Function

Function JsonNumber(json As String, key As String) As Double
    Dim p As Long
    p = InStr(json, """" & key & """")
    If p = 0 Then Exit Function
    p = InStr(p + Len(key) + 2, json, ":")
    JsonNumber = Val(LTrim(Mid(json, p + 1, 30)))
End Function

Dim reply As String
reply = "{""full_name"":""geekychris/amiforge"",""description"":""An IDE for AmigaOS 4.1""," & _
        """stargazers_count"":12}"
Print JsonText(reply, "full_name")
Print JsonText(reply, "description")
Print JsonNumber(reply, "stargazers_count"); "stars"
```

```output
geekychris/amiforge
An IDE for AmigaOS 4.1
 12 stars
```

Web services usually want to know what you accept, and many need a key or token. Set those
as headers once, before the requests:

*Listing 19.7* (`examples/book/ch19-networking/listing-19-07.bas`)

```basic
Dim web As Http, reply As String, token As String
Set web = CreateObject("Http")
token = Environ("API_TOKEN")
web.SetHeader "Accept", "application/json"
web.SetHeader "Authorization", "Bearer " & token
reply = web.Post("https://api.example.com/v1/items", "{""name"":""Boing""}", "application/json")
If web.Status <> 201 Then Print "Failed: "; web.Status; " "; reply
```

## A web page in a form

The program below is a small web browser for text: type an address, press **Get**, and the
page (or, with the check box, its headers too) appears in a text editor, with the status,
size and time underneath. Its form has a text field, a button, two check boxes, a text
editor and a label:

![The Web Fetch example on AmigaOS 4](images/webfetch.png)

```text
window name=webfetch title="Web Fetch" width=560 height=360 resizable=1
vlayout id=root
  hlayout weight=0
    string id=url label="URL" text="https://example.com/" maxchars=1024
    button id=go text="_Get" weight=0
  hlayout weight=0
    checkbox id=headers text="Show _headers"
    checkbox id=verify text="_Verify certificate" checked=1
  texteditor id=page
  label id=status text="Type a URL and press Get"
```

and its code:

*Listing 19.8* (`examples/book/ch19-networking/webfetch/webfetch.bbp`)

<!-- project: examples/book/ch19-networking/webfetch/webfetch.bbp -->
```basic
Private web As Http

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.Timeout = 15000
    page.Locked = True
    If Not web.TlsAvailable() Then status.Caption = "HTTPS isn't available here (no AmiSSL): http:// only"
    If Command() <> "" Then              ' webfetch URL: fetch it straight away
        url.Text = Command()
        Fetch
    End If
End Sub

Private Sub go_Click()
    Fetch
End Sub

Private Sub url_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then Fetch
End Sub

Private Sub Fetch()
    Dim body As String, t As Single
    status.Caption = "Fetching " & url.Text & " ..."
    Me.Enabled = False
    DoEvents
    web.VerifyCertificate = (verify.Value = vbChecked)
    t = Timer
    On Error GoTo Failed
    body = web.Get(url.Text)
    Me.Enabled = True
    If headers.Value = vbChecked Then
        page.Text = "HTTP " & web.Status & " " & web.StatusText & vbLf & Replace(web.ResponseHeaders, vbCr, "") & vbLf & body
    Else
        page.Text = body
    End If
    status.Caption = web.Status & " " & web.StatusText & " - " & web.BytesReceived & " bytes, " & _
                     web.ContentType & ", " & Format(Timer - t, "0.00") & " s"
    Exit Sub
Failed:
    Me.Enabled = True
    page.Text = ""
    status.Caption = "Error " & Err.Number & ": " & Err.Description
End Sub
```

Points to notice:

- `Me.Enabled = False` and `DoEvents` before the request: the window shows "Fetching..." and
  doesn't take clicks while the program waits for the answer.
- Errors (no network, unknown host, bad certificate) go to `Failed:` and appear in the
  status line instead of stopping the program.
- `Command()` lets you start it with an address: `boing run webfetch.bbp https://example.com/`.

A second example in the same drawer, `repoinfo`, asks GitHub's JSON API about a repository
and shows its name, description, stars and forks with the `JsonText` and `JsonNumber`
functions above:

*Listing 19.9* (`examples/book/ch19-networking/repoinfo/repoinfo.bbp`)

<!-- project: examples/book/ch19-networking/repoinfo/repoinfo.bbp -->
```basic
Private Sub go_Click()
    Dim reply As String
    status.Caption = "Asking GitHub..."
    DoEvents
    On Error GoTo Failed
    reply = web.Get("https://api.github.com/repos/" & repo.Text)
    If web.Status <> 200 Then
        status.Caption = "GitHub says " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    title.Caption = JsonText(reply, "full_name")
    desc.Caption = JsonText(reply, "description")
    stars.Caption = JsonNumber(reply, "stargazers_count") & " stars, " & _
                    JsonNumber(reply, "forks_count") & " forks"
    status.Caption = "Done"
    Exit Sub
Failed:
    status.Caption = "Error " & Err.Number & ": " & Err.Description
End Sub
```

## Limits

A request blocks the program until it finishes: keep `Timeout` reasonable, and show the user
that something is happening. Not supported yet: requests that run in the background and
report with events, compressed (gzip) answers, cookies, proxies, reusing connections, and
IPv6 on AmigaOS.

## Coming libraries

More modern building blocks are being added to the runtime, in this order: a `Dictionary`
(keys to values), JSON reading and writing, text encodings (UTF-8 to and from Latin-1, Base64,
URL encoding), hashing (MD5, SHA-1, SHA-256, CRC32), and dates and times in UTC. This chapter
will describe each one as it arrives.

## Summary

- `Set web = CreateObject("Http")`, then `web.Get(url)`, `web.Post(url, body)`,
  `web.GetToFile(url, path)` and the others return the answer's body.
- Check `web.Status`; catch errors 31101-31110 with `On Error`.
- Set headers with `SetHeader`; keep certificate checking on.
- Pick values out of simple JSON with a few string functions until the JSON library arrives.

See also: [Forms and controls](12-forms.md), [Errors](08-errors.md),
[Built-in functions](09-builtins.md).
