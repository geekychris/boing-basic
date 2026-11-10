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

Don't name your program or one of its modules `http.bas`: the module `http` would take the
class's name, and `boing check` stops with "the module 'http' hides the built-in class Http:
rename the module". Call it `webfetch.bas` or similar.

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
English text and numbers are the same in both. (`Utf8Decode` converts it: see [Text encodings](20-libraries.md#text-encodings).)

## Working with JSON

Many web services answer in JSON, a text format of names and values:

```text
{"full_name":"geekychris/amiforge","description":"An IDE for AmigaOS 4.1","stargazers_count":12}
```

The best way to read such answers is `JsonParse`, which turns the text into Dictionaries and
arrays: see [JSON](20-libraries.md#json) in the next chapter. For a quick look at a simple, flat
answer, a small function can also pick out values with the string functions. `JsonText` finds `"key"`, then the string after its colon; `JsonNumber` reads the
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

## Requests that don't block: GetAsync / SendAsync

`Get`, `Post` and the other request methods wait until the whole answer has arrived. In a
console program that is what you want. In a form it isn't: while the program waits, it doesn't
handle events, so the window doesn't redraw, buttons don't react, and a download of a few
megabytes freezes it for as long as it takes.

The asynchronous calls start the request in the background and return at once. Your program
goes on handling events; the `Http` object tells you how far the request has got, and calls a
Sub of yours when it is done.

| Member | Kind | What it does |
|---|---|---|
| `GetAsync url` | method | starts a GET of `url` and returns at once |
| `SendAsync method, url [, body [, contentType]]` | method | starts any request: `"POST"`, `"PUT"`, `"DELETE"`, `"PATCH"`... with an optional body, as `Send` does |
| `Busy` | property | `True` while the request runs |
| `Wait([ms])` | method | waits until the request has ended, handling events meanwhile; with `ms`, for at most that many milliseconds. Returns `True` if it has ended |
| `Cancel` | method | stops the request; it then ends with `ErrorNumber` 18 |
| `OnDone` | property | the name of a Sub without arguments, called once when the request has ended, however it ended |
| `OnProgress` | property | the name of a `Sub (got As Long, total As Long)`, called as the answer arrives: `got` bytes so far of `total`, or `total` = -1 if the server didn't say how big the answer is |
| `ErrorNumber` | property | how the request ended: 0 if an answer came, otherwise the error number (31101 to 31110, or 18 for cancelled) |
| `ErrorText` | property | the error message, `""` when there was none |

When the request has ended, `Status`, `StatusText`, `ResponseText`, `ResponseHeader(name)`,
`ResponseHeaders`, `ContentType`, `Url`, `Redirects` and `BytesReceived` describe the answer, as
after a `Get`. While it runs, they still describe the previous answer.

The request takes the object's settings (`Timeout`, `SetHeader` headers, `UserAgent`,
`CACertFile`, `VerifyCertificate`, `FollowRedirects`, `MaxRedirects`) at the moment it starts:
changing them later affects only the next request.

### Errors are not raised

A `Get` that can't reach the server raises a run-time error. An asynchronous request has no
statement to raise it in: it was started long ago, and the program is somewhere else now. So
its errors are **not** raised: the request ends, and `ErrorNumber` and `ErrorText` say what went
wrong. Check `ErrorNumber` first, then `Status` (a request that fails halfway can have a
`Status` of 200 and half a body):

*Listing 19.10* (`examples/book/ch19-networking/listing-19-10.bas`)

<!-- run -->
```basic
Option Explicit
Dim web As Http, ended As Boolean
Set web = CreateObject("Http")
web.OnDone = "Finished"

web.GetAsync "ftp://example.com/readme.txt"       ' Http speaks http:// and https:// only
ended = web.Wait()
Print "ended: " & ended & ", error " & web.ErrorNumber & ": " & web.ErrorText

web.GetAsync "http://127.0.0.1:1/"                 ' nothing listens on port 1
ended = web.Wait(10000)
Print "error " & web.ErrorNumber & ": " & web.ErrorText

Sub Finished()
    Print "Finished: Busy is " & web.Busy & ", Status " & web.Status
End Sub
```

```output
Finished: Busy is False, Status 0
ended: True, error 31101: bad URL: ftp://example.com/readme.txt
Finished: Busy is False, Status 0
error 31103: can't connect to 127.0.0.1:1
```

The error numbers are the ones `Get` raises (see "Errors" earlier in this chapter): 31101 a bad
URL, 31102 an unknown host, 31103 no connection, 31104 no answer within `Timeout`, 31105 and
31106 TLS and certificate problems, 31107 too many redirects, 31108 no HTTPS, 31109 a broken
answer; and 18 for a request you cancelled. An answer with an error status such as 404 is still
an answer: `ErrorNumber` is 0 and `Status` is 404.

Some mistakes are still raised at once, in the statement that makes them:

| Error | When |
|---|---|
| 5 | `GetAsync`, `SendAsync`, `Get`, `Post` or another request on an object whose request is still running. One `Http` object runs one request at a time; use another object for a second one |
| 35 | `OnDone` or `OnProgress` names a Sub that doesn't exist (raised when the Sub is to be called: in `DoEvents`, `Wait`, `Busy` or the form's event loop) |
| 7 | the background task for the request can't be started (out of memory) |

### Where OnDone and OnProgress run

The request runs in the background, but your Subs never do. `OnDone` and `OnProgress` are called
on your program's own task, at the moments when it handles events anyway:

- in a form program, from the event loop, between your event Subs, just like a button's `Click`;
- in `DoEvents`;
- in `Wait`, while it waits;
- when you read `Busy`.

So the Subs can do anything an event Sub can: change controls, set variables, start the next
request, show a `MsgBox`. Nothing runs at the same time as your code, and you need no locks.
The other side of this is that a program that doesn't handle events (a long calculation
without `DoEvents`) gets no `OnProgress` calls until it does, even though the download goes on
in the background.

The names are looked up when the Sub is called, among the Subs of all the modules and forms
of the program, without regard to case. Use a Sub of a module or of a form, not a method of a
class module (those can't be found by name), and give each Sub a name no other module uses.
Set the property to `""` to stop the calls.

`OnDone` is called once per request, after `Busy` has become `False`, so inside it the answer is
complete and the object is ready for the next request.

### Polling from a console program

A program without forms can start a request, do other work, and look at `Busy` now and then.
`Busy` handles the events (and calls `OnProgress` and `OnDone`) each time you read it:

*Listing 19.11* (`examples/book/ch19-networking/listing-19-11.bas`)

```basic
Option Explicit
Dim web As Http, ticks As Long
Set web = CreateObject("Http")
web.OnProgress = "Progress"
web.GetAsync "https://example.com/files/game.lha"
Do While web.Busy
    ticks = ticks + 1          ' here the program could do something useful
    DoEvents
Loop
If web.ErrorNumber <> 0 Then
    Print "Failed: "; web.ErrorText
ElseIf web.Status = 200 Then
    Print web.BytesReceived; " bytes"
Else
    Print "The server said"; web.Status; " "; web.StatusText
End If

Sub Progress(got As Long, total As Long)
    If total > 0 Then Print (got * 100# \ total); "%" Else Print got; " bytes"
End Sub
```

`Wait` does the same loop for you. `web.Wait()` waits as long as it takes; `web.Wait(500)` waits
at most half a second and tells you whether the request ended in that time:

*Listing 19.12* (`examples/book/ch19-networking/listing-19-12.bas`)

```basic
Option Explicit
Dim web As Http
Set web = CreateObject("Http")
web.GetAsync "https://example.com/slow-report"
Do Until web.Wait(1000)
    Print "still waiting ..."
Loop
Print web.Status
```

### Several requests at once

Each `Http` object runs one request at a time, but several objects can run theirs together.
They end in their own order: a quick one started after a slow one ends first.

*Listing 19.13* (`examples/book/ch19-networking/listing-19-13.bas`)

```basic
Option Explicit
Dim news As Http, weather As Http
Set news = CreateObject("Http")
Set weather = CreateObject("Http")
news.OnDone = "NewsDone"
weather.OnDone = "WeatherDone"
news.GetAsync "https://example.com/news.json"
weather.GetAsync "https://example.com/weather.json"
Do While news.Busy Or weather.Busy
    DoEvents
Loop

Sub NewsDone()
    Print "news:"; news.Status; news.BytesReceived
End Sub

Sub WeatherDone()
    Print "weather:"; weather.Status; weather.BytesReceived
End Sub
```

### Cancelling

`Cancel` asks the request to stop. It ends soon after with `ErrorNumber` 18 (and `OnDone` is
called as for any other end). What had arrived until then stays in `ResponseText`, and
`Status` is the status the server had sent: that is why you check `ErrorNumber` before
`Status`. Calling `Cancel` when no request runs does nothing.

`Cancel` takes effect when the next piece of the answer arrives. A request that is still
looking up the host name, connecting, or waiting for the server's first reply ends when that
step is over, or when `Timeout` runs out. Keep `Timeout` moderate (10 to 30 seconds) in programs
with a Cancel button.

A program that ends while a request still runs simply stops it. In a form, cancel a running
request in `Form_Unload`, and clear `OnDone` first so that it isn't called while the window
goes away:

*Listing 19.14* (`examples/book/ch19-networking/asyncfetch/asyncfetch.bbp`)

<!-- project: examples/book/ch19-networking/asyncfetch/asyncfetch.bbp -->
```basic
Private Sub Form_Unload(Cancel As Integer)
    web.OnDone = ""
    web.OnProgress = ""
    If web.Busy Then
        web.Cancel
        web.Wait 5000
    End If
End Sub
```

### A downloader with a progress bar

The book example `asyncfetch` downloads a file in the background. While it runs, a progress
bar fills up, the status line counts the kilobytes, the window can be moved and resized, and a
**Cancel** button stops the download. When it is done, the file is saved. The form:

```text
window name=asyncfetch title="Download" width=480 height=0
vlayout id=root
  string id=url label="URL" text="https://example.com/" maxchars=1024
  string id=target label="Save as" text="RAM:download" maxchars=256
  fuelgauge id=meter min=0 max=100 level=0
  label id=status text="Type a URL and press Download"
  hlayout even=1
    button id=download text="_Download"
    button id=abort text="_Cancel" disabled=1
```

(The Cancel button is called `abort`, since `Stop` is a statement of the language and can't
name a control.)

`Form_Load` creates the `Http` object once and names the two Subs. **Download** starts the
request and returns at once; **Cancel** asks it to stop:

*Listing 19.15* (`examples/book/ch19-networking/asyncfetch/asyncfetch.bbp`)

<!-- project: examples/book/ch19-networking/asyncfetch/asyncfetch.bbp -->
```basic
Private web As Http
Private started As Single

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.Timeout = 20000
    web.OnProgress = "Fetching"           ' Sub Fetching(got As Long, total As Long)
    web.OnDone = "Fetched"                ' Sub Fetched()
End Sub

Private Sub download_Click()
    meter.Value = 0
    meter.Text = ""
    status.Caption = "Connecting to " & url.Text & " ..."
    started = Timer
    web.GetAsync url.Text                 ' returns at once
    download.Enabled = False
    abort.Enabled = True
End Sub

Private Sub abort_Click()
    web.Cancel                            ' Fetched is called soon, with ErrorNumber 18
    status.Caption = "Cancelling ..."
End Sub
```

`Fetching` moves the progress bar. When the server didn't send the size (`total` is -1), it
can't show a percentage, so it shows the kilobytes in the bar instead:

*Listing 19.16* (`examples/book/ch19-networking/asyncfetch/asyncfetch.bbp`)

<!-- project: examples/book/ch19-networking/asyncfetch/asyncfetch.bbp -->
```basic
' called (on the program's own task) each time more of the answer has arrived
Sub Fetching(got As Long, total As Long)
    If total > 0 Then
        meter.Max = 100
        meter.Value = got * 100# / total
        meter.Text = ""
        status.Caption = Format(got / 1024, "0") & " of " & Format(total / 1024, "0") & " KB"
    Else                                  ' the server didn't say how big it is
        meter.Text = Format(got / 1024, "0") & " KB"
        status.Caption = Format(got / 1024, "0") & " KB so far"
    End If
End Sub
```

`Fetched` runs once at the end. It puts the buttons back, then looks at how the request ended:
cancelled, failed, an error status from the server, or a whole answer to save:

*Listing 19.17* (`examples/book/ch19-networking/asyncfetch/asyncfetch.bbp`)

<!-- project: examples/book/ch19-networking/asyncfetch/asyncfetch.bbp -->
```basic
' called once when the request has ended, however it ended
Sub Fetched()
    Dim f As Integer, data As String
    download.Enabled = True
    abort.Enabled = False
    If web.ErrorNumber = 18 Then
        status.Caption = "Cancelled"
        meter.Value = 0
        Exit Sub
    ElseIf web.ErrorNumber <> 0 Then
        status.Caption = "Error " & web.ErrorNumber & ": " & web.ErrorText
        meter.Value = 0
        Exit Sub
    ElseIf web.Status <> 200 Then
        status.Caption = "The server said " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    data = web.ResponseText
    On Error GoTo CantSave
    f = FreeFile
    Open target.Text For Binary Access Write As #f
    Put #f, , data
    Close #f
    meter.Value = meter.Max
    meter.Text = ""
    status.Caption = "Saved " & Len(data) & " bytes in " & target.Text & " (" & _
                     Format(Timer - started, "0.0") & " s)"
    Exit Sub
CantSave:
    status.Caption = "Can't save " & target.Text & ": " & Err.Description
End Sub
```

Points to notice:

- No `DoEvents` anywhere: the form's own event loop calls `Fetching` and `Fetched`.
- The buttons are the only state: **Download** is disabled while a request runs, so the
  program never starts a second request on the same object (which would be error 5).
- The answer is kept in memory until it is complete, then written in one go. For files larger
  than the free memory, use the blocking `GetToFile`, which writes as it receives.

### How it works

On AmigaOS 4 each request runs in a child process of its own, called "Boing BASIC worker", with
its own `bsdsocket.library` and AmiSSL bases (both libraries require one per process). The
worker signals your program's task as data arrives, and the event loop, `DoEvents`, `Wait` and
`Busy` pick up the news. On macOS and Linux the request runs in a thread.

### Summary

- `web.GetAsync url` or `web.SendAsync method, url, body, type` start a request and return at
  once; one request per object at a time.
- `web.OnDone = "SubName"` and `web.OnProgress = "SubName"` name Subs that run on your own
  task, from the event loop, `DoEvents`, `Wait` and `Busy`: they can update the form.
- `Busy`, `Wait([ms])` and `Cancel` follow and control the request.
- Errors are not raised: check `ErrorNumber` (0, 31101 to 31110, or 18) and `ErrorText`, then
  `Status`.

## Limits

Not supported yet: compressed (gzip) answers, cookies, proxies, reusing connections between
requests, and IPv6 on AmigaOS.

## Summary

- `Set web = CreateObject("Http")`, then `web.Get(url)`, `web.Post(url, body)`,
  `web.GetToFile(url, path)` and the others return the answer's body.
- Check `web.Status`; catch errors 31101-31110 with `On Error`.
- Set headers with `SetHeader`; keep certificate checking on.
- Read JSON answers with `JsonParse` ([chapter 20](20-libraries.md#json)).
- `GetAsync` and `SendAsync` fetch in the background, so a window stays responsive.

See also: [Forms and controls](12-forms.md), [Errors](08-errors.md),
[Built-in functions](09-builtins.md).
