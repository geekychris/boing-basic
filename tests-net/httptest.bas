' httptest.bas - the Http class against tools/http_testserver.py.
'   boing run httptest.bas HTTP_BASE HTTPS_BASE CA_FILE [quick]
' e.g. http://127.0.0.1:8001 https://localhost:8002 build/net-certs/ca.pem
' Prints TAP lines (nothing machine-specific) and PASS/FAIL; the expected output is httptest.out.
Option Explicit

Private n As Integer, fails As Integer

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then
        Print "ok " & n & " - " & what
    Else
        Print "not ok " & n & " - " & what
        fails = fails + 1
    End If
End Sub

Private Function ErrOf(ByVal h As Object, ByVal method As String, ByVal url As String) As Long
    Dim s As String
    On Error Resume Next
    s = h.Send(method, url)
    ErrOf = Err.Number
End Function

Sub Main()
    Dim args() As String, base As String, sbase As String, ca As String
    Dim h As Http, s As String, k As Long, i As Long, ok As Boolean, f As Integer, b As Byte

    args = Split(Command(), " ")
    base = args(0): sbase = args(1): ca = args(2)

    Set h = CreateObject("Http")
    Check TypeName(h) = "Http", "CreateObject(""Http"")"
    Check h.Timeout = 30000 And h.FollowRedirects And h.VerifyCertificate And h.MaxRedirects = 10, "defaults"

    ' --- plain HTTP
    s = h.Get(base & "/hello")
    Check h.Status = 200 And s = "Hello, Boing!", "GET /hello"
    Check h.StatusText = "OK" And h.ContentType = "text/plain", "StatusText and ContentType"
    Check h.ResponseText = s And h.BytesReceived = 13, "ResponseText and BytesReceived"

    h.SetHeader "X-Test", "boing"
    s = h.Post(base & "/echo", "a=1&b=two")
    Check InStr(s, "method=POST") > 0 And InStr(s, "x-test=boing") > 0, "POST with a header"
    Check InStr(s, "body=a=1&b=two") > 0, "POST body"
    Check InStr(s, "content-type=application/x-www-form-urlencoded") > 0, "default POST content type"
    s = h.Put(base & "/echo", "{""x"":1}", "application/json")
    Check InStr(s, "method=PUT") > 0 And InStr(s, "content-type=application/json") > 0, "PUT with a content type"
    s = h.Delete(base & "/echo")
    Check InStr(s, "method=DELETE") > 0, "DELETE"
    s = h.Send("PATCH", base & "/echo", "p")
    Check InStr(s, "method=PATCH") > 0 And InStr(s, "body=p") > 0, "Send with any method"
    h.SetHeader "X-Test", ""
    s = h.Get(base & "/echo")
    Check InStr(s, "x-test=" & vbLf) > 0, "SetHeader name, """" removes the header"

    s = h.Head(base & "/hello")
    Check h.Status = 200 And s = "", "HEAD has no body"

    s = h.Get(base & "/status/404")
    Check h.Status = 404 And s = "status 404", "404 is an answer, not an error"
    s = h.Get(base & "/status/500")
    Check h.Status = 500, "500 is an answer too"

    s = h.Get(base & "/headers")
    Check h.ResponseHeader("x-one") = "1" And h.ResponseHeader("X-Two") = "two words", "ResponseHeader (any case)"
    Check InStr(h.ResponseHeaders, "X-Two: two words") > 0, "ResponseHeaders"
    Check h.ResponseHeader("X-None") = "", "a missing header is """""

    s = h.Get(base & "/chunked")
    Check s = "one two three four five", "chunked body"

    s = h.Get(base & "/redirect/3")
    Check h.Status = 200 And s = "Hello, Boing!" And h.Redirects = 3, "3 redirects followed"
    Check Right(h.Url, 6) = "/hello", "Url after redirects"
    s = h.Get(base & "/relative")
    Check s = "Hello, Boing!", "relative Location"
    s = h.Post(base & "/see-other", "data")
    Check InStr(s, "method=GET") > 0 And InStr(s, "body=" & vbLf) > 0, "303 continues as GET without the body"
    h.FollowRedirects = False
    s = h.Get(base & "/redirect/1")
    Check h.Status = 302 And h.ResponseHeader("Location") = "/hello", "FollowRedirects = False"
    h.FollowRedirects = True
    Check ErrOf(h, "GET", base & "/redirect-loop") = 31107, "a redirect loop: error 31107"
    h.MaxRedirects = 2
    Check ErrOf(h, "GET", base & "/redirect/3") = 31107, "MaxRedirects = 2"
    h.MaxRedirects = 10

    s = h.Get(base & "/big?n=300000")
    ok = Len(s) = 300000
    For i = 1 To 300000 Step 997
        If Asc(Mid(s, i, 1)) <> ((i - 1) Mod 251) Then ok = False
    Next
    Check ok, "300000 bytes into a String, binary safe"
    k = h.GetToFile(base & "/big?n=123457", "http_test_download.bin")
    Check k = 123457 And FileLen("http_test_download.bin") = 123457, "GetToFile"
    f = FreeFile
    Open "http_test_download.bin" For Binary As #f
    Get #f, 1001, b
    Close #f
    Check b = 1000 Mod 251, "the file holds the right bytes"
    Kill "http_test_download.bin"

    h.Timeout = 1000
    Check ErrOf(h, "GET", base & "/slow") = 31104, "Timeout: error 31104"
    h.Timeout = 30000

    Check ErrOf(h, "GET", "ftp://example.com/") = 31101, "an ftp:// URL: error 31101"
    Check ErrOf(h, "GET", "http://no-such-host.invalid/") = 31102, "an unknown host: error 31102"
    Check ErrOf(h, "GET", "http://127.0.0.1:1/") = 31103, "connection refused: error 31103"

    ' --- HTTPS (with the test CA)
    If Not h.TlsAvailable() Then
        Check ErrOf(h, "GET", sbase & "/hello") = 31108, "no TLS here: error 31108"
    Else
        h.CACertFile = ca
        s = h.Get(sbase & "/hello")
        Check h.Status = 200 And s = "Hello, Boing!", "HTTPS GET with the test CA"
        s = h.Post(sbase & "/echo", "secret")
        Check InStr(s, "body=secret") > 0, "HTTPS POST"
        s = h.Get(sbase & "/chunked")
        Check s = "one two three four five", "HTTPS chunked"
        h.CACertFile = ""
        Check ErrOf(h, "GET", sbase & "/hello") = 31106, "an untrusted certificate: error 31106"
        h.VerifyCertificate = False
        s = h.Get(sbase & "/hello")
        Check s = "Hello, Boing!", "VerifyCertificate = False"
        h.VerifyCertificate = True
    End If

    If fails = 0 Then Print "PASS " & n Else Print "FAIL " & (n - fails) & "/" & n
End Sub
