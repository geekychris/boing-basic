' asynctest.bas - asynchronous Http requests (SendAsync/GetAsync, Busy, Wait, Cancel, OnDone,
' OnProgress) against tools/http_testserver.py.
'   boing run asynctest.bas HTTP_BASE HTTPS_BASE CA_FILE
Option Explicit

Private n As Integer, fails As Integer
Private WithEvents ev As Http
Private evLog As String, evProgress As Long
Private h1 As Http, h2 As Http, order As String, progressCalls As Long, lastGot As Long, doneCount As Long

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print "ok " & n & " - " & what Else Print "not ok " & n & " - " & what: fails = fails + 1
End Sub

Sub H1Done()
    order = order & "h1 "
    doneCount = doneCount + 1
End Sub

Sub H2Done()
    order = order & "h2 "
End Sub

Sub H1Progress(got As Long, total As Long)
    progressCalls = progressCalls + 1
    lastGot = got
End Sub

Private Sub ev_Done()
    evLog = evLog & "done " & ev.Status & " "
End Sub

Private Sub ev_Failed(number As Long, text As String)
    evLog = evLog & "failed " & number & " "
End Sub

Private Sub ev_Progress(got As Long, total As Long)
    evProgress = evProgress + 1
End Sub

Sub Main()
    Dim args() As String, base As String, sbase As String, ca As String, s As String, ok As Boolean
    args = Split(Command(), " ")
    base = args(0): sbase = args(1): ca = args(2)
    Set h1 = CreateObject("Http")
    Set h2 = CreateObject("Http")

    ' a simple request, polled with Busy and DoEvents
    h1.OnDone = "H1Done"
    h1.GetAsync base & "/hello"
    Do While h1.Busy: DoEvents: Loop
    Check h1.Status = 200 And h1.ResponseText = "Hello, Boing!" And h1.ErrorNumber = 0, "GetAsync, Busy, DoEvents"
    Check doneCount = 1 And order = "h1 ", "OnDone called once"

    ' two at once: the slow one finishes last
    order = ""
    h2.OnDone = "H2Done"
    h1.GetAsync base & "/slow"
    h2.GetAsync base & "/hello"
    Check h1.Busy And h2.Wait() And h1.Busy, "a quick request finishes while a slow one runs"
    Check h1.Wait(), "Wait without a limit"
    Check order = "h2 h1 " And h1.ResponseText = "slow", "they finish in their own order"

    ' progress
    h1.OnProgress = "H1Progress"
    progressCalls = 0
    h1.GetAsync base & "/big?n=300000"
    Check h1.Wait(), "a 300000-byte download"
    Check Len(h1.ResponseText) = 300000 And progressCalls > 0 And lastGot = 300000, "OnProgress reports the bytes"
    h1.OnProgress = ""

    ' Wait with a time limit, Cancel
    h1.GetAsync base & "/drip"
    Check Not h1.Wait(500), "Wait(500) on a 5 s request returns False"
    h1.Cancel
    Check h1.Wait(10000), "Cancel ends it"
    Check h1.ErrorNumber = 18, "a cancelled request: ErrorNumber 18"

    ' a synchronous call while a request runs is refused
    h1.GetAsync base & "/slow"
    On Error Resume Next
    s = h1.Get(base & "/hello")
    Check Err.Number = 5, "Get while SendAsync runs: error 5"
    Err.Clear
    h1.GetAsync base & "/hello"
    Check Err.Number = 5, "a second async request on the same object: error 5"
    On Error GoTo 0
    h1.Cancel
    ok = h1.Wait(20000)

    ' errors come back in ErrorNumber/ErrorText, not raised
    h1.GetAsync "http://no-such-host.invalid/"
    Check h1.Wait(30000) And h1.ErrorNumber = 31102 And h1.ErrorText <> "", "an unknown host: ErrorNumber 31102"

    ' POST with SendAsync
    h1.SendAsync "POST", base & "/echo", "async body", "text/plain"
    Check h1.Wait() And InStr(h1.ResponseText, "body=async body") > 0 And InStr(h1.ResponseText, "content-type=text/plain") > 0, "SendAsync POST"

    ' HTTPS on the worker (its own TLS context)
    If h1.TlsAvailable() Then
        h1.CACertFile = ca
        h1.GetAsync sbase & "/hello"
        Check h1.Wait() And h1.Status = 200 And h1.ResponseText = "Hello, Boing!", "HTTPS asynchronously"
        h2.CACertFile = ca
        h1.GetAsync sbase & "/chunked"
        h2.GetAsync sbase & "/hello"
        Check h1.Wait() And h2.Wait() And h1.ResponseText = "one two three four five" And h2.Status = 200, "two HTTPS requests at once"
    Else
        Check True, "(no TLS here)"
        Check True, "(no TLS here)"
    End If

    ' Cancel ends a request at once, also before any data came
    Dim t0 As Double
    h1.GetAsync base & "/slow"
    t0 = Timer
    h1.Cancel
    Check h1.Wait(3000) And Timer - t0 < 3, "Cancel while waiting for the answer's headers is immediate"
    Check h1.ErrorNumber = 18 And h1.Status = 0 And h1.ResponseText = "", "a cancelled request leaves no half answer"
    h1.Timeout = 20000
    h1.GetAsync "http://10.255.255.1/"
    t0 = Timer
    h1.Cancel
    Check h1.Wait(3000) And Timer - t0 < 3 And h1.ErrorNumber <> 0, "Cancel while connecting is immediate"
    h1.Timeout = 30000
    h1.GetAsync base & "/hello"
    Check h1.ErrorText = "" And h1.ErrorNumber = 0, "a new request clears ErrorText"
    ok = h1.Wait()
    On Error Resume Next
    h1.OnDone = "NoSuchSub"
    Check Err.Number = 35, "OnDone naming a missing Sub: error 35 at once"
    On Error GoTo 0

    ' events: Dim WithEvents ev As Http
    Set ev = CreateObject("Http")
    ev.GetAsync base & "/big?n=100000"
    Check ev.Wait() And evLog = "done 200 " And evProgress > 0, "WithEvents: Done and Progress"
    evLog = ""
    ev.GetAsync "http://no-such-host.invalid/"
    Check ev.Wait(30000) And evLog = "failed 31102 ", "WithEvents: Failed(number, text)"
    evLog = ""
    ev.GetAsync base & "/drip"
    ev.Cancel
    Check ev.Wait(10000) And evLog = "failed 18 ", "WithEvents: Failed after Cancel"

    If fails = 0 Then Print "PASS " & n Else Print "FAIL " & (n - fails) & "/" & n
End Sub
