' sessiontest.bas - cookies and keep-alive connections of the Http class, against
' tools/http_testserver.py.   boing run sessiontest.bas HTTP_BASE HTTPS_BASE CA_FILE
Option Explicit

Private n As Integer, fails As Integer

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print "ok " & n & " - " & what Else Print "not ok " & n & " - " & what: fails = fails + 1
End Sub

Sub Main()
    Dim args() As String, base As String, sbase As String, ca As String, host As String
    Dim web As Http, p1 As String, p2 As String, s As String, t As String
    args = Split(Command(), " ")
    base = args(0): sbase = args(1): ca = args(2)
    host = Mid(base, 8): host = Left(host, InStr(host, ":") - 1)

    ' keep-alive: two requests over one connection
    Set web = CreateObject("Http")
    Check web.KeepAlive And web.UseCookies, "KeepAlive and UseCookies are on by default"
    p1 = web.Get(base & "/conn")
    Check Not web.ConnectionReused, "the first request opens a connection"
    p2 = web.Get(base & "/conn")
    Check web.ConnectionReused And p1 = p2, "the second one reuses it"
    s = web.Post(base & "/echo", "kept", "text/plain")
    Check web.ConnectionReused And InStr(s, "body=kept") > 0, "a POST over the kept connection"
    p2 = web.Get(base & "/close")
    Check web.ConnectionReused And p1 = p2, "the server's Connection: close..."
    p2 = web.Get(base & "/conn")
    Check Not web.ConnectionReused And p1 <> p2, "...means a new connection next time"
    web.KeepAlive = False
    p1 = web.Get(base & "/conn")
    p2 = web.Get(base & "/conn")
    Check Not web.ConnectionReused And p1 <> p2, "KeepAlive = False: a connection per request"
    web.KeepAlive = True
    s = web.Get(base & "/big?n=200000")
    s = web.Get(base & "/chunked")
    Check web.ConnectionReused And s = "one two three four five", "a chunked answer after a big one, kept"
    p1 = web.Get(base & "/drop")
    p2 = web.Get(base & "/conn")
    Check Not web.ConnectionReused And p1 <> p2 And web.Status = 200, "a kept connection the server dropped: a new one, silently"
    If web.TlsAvailable() Then
        web.CACertFile = ca
        p1 = web.Get(sbase & "/conn")
        p2 = web.Get(sbase & "/conn")
        Check web.ConnectionReused And p1 = p2, "HTTPS keeps its connection too"
    Else
        Check True, "(no TLS here)"
    End If

    ' cookies
    Set web = CreateObject("Http")
    s = web.Get(base & "/setcookie?c=" & UrlEncode("flavour=ginger; Path=/") & "&c=" & UrlEncode("deep=1; Path=/cookies/deep"))
    Check web.CookieCount = 2 And web.GetCookie("flavour") = "ginger", "Set-Cookie is stored"
    Check web.Get(base & "/cookies") = "flavour=ginger", "and sent back where its Path matches"
    Check web.Get(base & "/cookies/deep/x") = "deep=1; flavour=ginger", "longer paths first"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("flavour=lime; Path=/"))
    Check web.GetCookie("flavour") = "lime" And web.CookieCount = 2, "the same name replaces it"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("flavour=x; Path=/; Max-Age=0"))
    Check web.GetCookie("flavour") = "" And web.CookieCount = 1, "Max-Age=0 deletes it"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("old=1; Path=/; Expires=Thu, 01 Jan 1998 00:00:00 GMT"))
    Check web.GetCookie("old") = "", "an Expires in the past isn't stored"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("later=1; Path=/; Expires=Fri, 01 Jan 2049 00:00:00 GMT"))
    Check web.GetCookie("later") = "1", "an Expires in the future is"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("other=1; Domain=example.com"))
    Check web.GetCookie("other") = "", "a cookie for another domain is refused"
    s = web.Get(base & "/setcookie?c=" & UrlEncode("sec=1; Path=/; Secure"))
    Check InStr(web.Get(base & "/cookies"), "sec=") = 0, "a Secure cookie isn't sent over http"
    web.ClearCookies
    s = web.Get(base & "/login")
    Check web.Url Like "*/cookies/after-login" And s = "session=abc123", "a cookie set by a redirect is sent to its target"
    web.SetCookie "token", "t0k", host
    Check InStr(web.Get(base & "/cookies"), "token=t0k") > 0, "SetCookie"
    t = web.Cookies
    Check InStr(t, host & vbTab & "TRUE" & vbTab & "/" & vbTab & "FALSE" & vbTab & "0" & vbTab & "token" & vbTab & "t0k") > 0, "Cookies as text"
    web.ClearCookies
    Check web.CookieCount = 0 And web.Get(base & "/cookies") = "", "ClearCookies"
    web.Cookies = t
    Check web.GetCookie("token") = "t0k" And web.GetCookie("session") = "abc123", "Cookies = text loads them"
    web.UseCookies = False
    Check web.Get(base & "/cookies") = "", "UseCookies = False: none sent"
    web.SetHeader "Cookie", "mine=1"
    web.UseCookies = True
    Check web.Get(base & "/cookies") = "mine=1", "a Cookie header of your own wins"
    web.ClearHeaders
    On Error Resume Next
    web.SetCookie "bad name", "1", host
    Check Err.Number = 5, "SetCookie with a bad name: error 5"
    On Error GoTo 0

    ' async requests share the jar
    web.ClearCookies
    web.GetAsync base & "/setcookie?c=" & UrlEncode("async=yes; Path=/")
    Check web.Wait() And web.GetCookie("async") = "yes", "an async request stores cookies"
    web.GetAsync base & "/cookies"
    Check web.Wait() And web.ResponseText = "async=yes", "and sends them"
    web.GetAsync base & "/slow"
    On Error Resume Next
    s = web.GetCookie("async")
    Check Err.Number = 5, "the jar is busy while a request runs"
    On Error GoTo 0
    web.Cancel
    s = CStr(web.Wait(20000))
    p1 = web.Get(base & "/conn")
    p2 = web.Get(base & "/conn")
    Check web.ConnectionReused And p1 = p2, "keep-alive after async requests"

    If fails = 0 Then Print "PASS " & n Else Print "FAIL " & (n - fails) & "/" & n
End Sub
