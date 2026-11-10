' Socket: TCP and UDP over the loopback interface, blocking calls and events (docs/socket.md)
Option Explicit

Dim WithEvents srv As Socket
Dim WithEvents cli As Socket
Dim WithEvents udp As Socket
Dim conns As New Collection
Dim log As String


Sub Note(s As String)
    log = log & s & ";"
End Sub

Sub srv_ConnectionRequest()
    Dim c As Socket
    Set c = srv.Accept()
    Note "request"
    If Not c Is Nothing Then conns.Add c
End Sub

Sub srv_ClientDataArrival(ByVal Client As Socket, ByVal Bytes As Long)
    Dim line As String
    Do While InStr(Client.Peek(), vbLf) > 0
        line = Client.ReceiveLine()
        Note "server got " & line
        Client.SendLine UCase(line)
    Loop
End Sub

Sub srv_ClientClose(ByVal Client As Socket)
    Note "client closed, state " & Client.State
    Client.Close
End Sub

Sub cli_Connect()
    Note "connected"
    cli.SendLine "hello"
End Sub

Sub cli_DataArrival(ByVal Bytes As Long)
    Note "client got " & Replace(cli.Receive(), vbCrLf, "|")
End Sub

Sub cli_Close()
    Note "server closed"
End Sub

Sub cli_Error(ByVal Number As Long, ByVal Description As String)
    Note "error " & Number
End Sub

Sub udp_DataArrival(ByVal Bytes As Long)
    Dim d As String
    d = udp.ReceiveFrom()
    Note "udp " & Bytes & " " & d & " from " & udp.RemoteHost
End Sub

Function Pump(ms As Long) As Long
    Dim t As Double, n As Long
    t = Timer
    Do While Timer - t < ms / 1000
        If srv.WaitEvents(50) Then n = n + 1
    Loop
    Pump = n
End Function

' pump until the log has text (at most 5 s)
Sub WaitFor(text As String)
    Dim t As Double
    t = Timer
    Do While InStr(log, text) = 0 And Timer - t < 5
        srv.WaitEvents 50
    Loop
    If InStr(log, text) = 0 Then Print "timed out waiting for "; text
End Sub

' the log's entries in alphabetical order (events of different sockets may come in either order)
Function Sorted() As String
    Dim p, i As Long, j As Long, t As String
    p = Split(Left(log, Len(log) - 1), ";")
    For i = 0 To UBound(p)
        For j = i + 1 To UBound(p)
            If p(j) < p(i) Then t = p(i): p(i) = p(j): p(j) = t
        Next
    Next
    Sorted = Join(p, "; ")
    log = ""
End Function

Dim port As Long, a As Socket, b As Socket, l As Socket, s As String, i As Long

' ---- blocking TCP, no events
Set l = CreateObject("Socket")
l.Listen 0, "127.0.0.1"
Print "listening:"; l.State = sockListening; l.LocalPort > 0
Set a = CreateObject("Socket")
a.Timeout = 5000
a.Connect "127.0.0.1", l.LocalPort
Print "connected:"; a.Connected; a.State; a.RemoteHost; a.RemotePort = l.LocalPort
Set b = l.Accept(2000)
Print "accepted:"; Not b Is Nothing; b.RemoteHost; b.RemotePort = a.LocalPort
a.Send "line one" & vbCrLf & "line two" & vbLf & "partial"
b.Timeout = 2000
Print b.ReceiveLine(); "|"; b.ReceiveLine(); "|"
Print "read:"; b.Read(4)
s = String(200000, "x") & "END"
a.Send s
Print "big:"; Len(b.Read(Len(s) - 4 + 4 + 3)) ' "ial" + s
a.Send "abc" & Chr(0) & "def"
s = b.Read(7)
Print "binary:"; Len(s); Asc(Mid(s, 4, 1)); b.Read(0) = ""
On Error Resume Next
b.Timeout = 200
s = b.ReceiveLine()
Print "timeout:"; Err.Number
Err.Clear
On Error GoTo 0
a.Close
Print "closed:"; a.State; b.ReceiveLine() = ""; b.AtEnd; b.State
b.Close
l.Close

' ---- errors
On Error Resume Next
Set a = CreateObject("Socket")
a.Timeout = 3000
a.Connect "127.0.0.1", port       ' port 0: refused
Print "refused:"; Err.Number
Err.Clear
a.Connect "no-such-host.invalid", 80
Print "resolve:"; Err.Number
Err.Clear
a.Send "x"
Print "not open:"; Err.Number
Err.Clear
a.Listen 70000
Print "bad port:"; Err.Number
Err.Clear
On Error GoTo 0

' ---- events: a server and a client in the same program
Set srv = CreateObject("Socket")
srv.Listen 0, "127.0.0.1"
port = srv.LocalPort
Set cli = CreateObject("Socket")
cli.Connect "127.0.0.1", port
Print "state after Connect:"; cli.State = sockConnecting Or cli.State = sockConnected
WaitFor "client got HELLO"
Print Sorted()
cli.SendLine "second"
WaitFor "client got SECOND"
cli.SendLine "third"
WaitFor "client got THIRD"
Print Sorted()
cli.Close
WaitFor "client closed"
Print Sorted()
Print "connections:"; conns.Count

' the server closes its end
Set cli = CreateObject("Socket")
cli.Connect "127.0.0.1", port
WaitFor "client got HELLO"
Print Sorted()
conns(2).Close
WaitFor "server closed"
Print Sorted()

' ---- connect error as an event
srv.Close
Set cli = CreateObject("Socket")
cli.Connect "127.0.0.1", port
Set srv = cli
WaitFor "error"
Print Sorted(); " "; cli.State = sockError

' ---- UDP
log = ""
Set udp = CreateObject("Socket")
udp.Bind 0, "127.0.0.1"
Print "udp:"; udp.Protocol; udp.State = sockOpen; udp.LocalPort > 0
Set a = CreateObject("Socket")
a.SendTo "127.0.0.1", udp.LocalPort, "ping"
a.SendTo "127.0.0.1", udp.LocalPort, "pong!"
Set srv = udp                 ' WaitFor waits through srv
WaitFor "pong"
Print Sorted()
Set b = CreateObject("Socket")
b.Bind 0, "127.0.0.1"
a.SendTo "127.0.0.1", b.LocalPort, "direct"
s = b.ReceiveFrom(1000)
Print "ReceiveFrom:"; s; " "; b.RemotePort = a.LocalPort; " ["; b.ReceiveFrom(); "]"
b.Tag = "keep"
Print TypeName(b); " "; b.Tag
