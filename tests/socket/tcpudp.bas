' Socket: TCP and UDP over the loopback interface, blocking calls and events (docs/socket.md)
Option Explicit

Dim WithEvents srv As Socket
Dim WithEvents cli As Socket
Dim WithEvents udp As Socket
Dim conns As New Collection
Dim log As String, addr As String


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
    Note "udp " & Bytes & " " & d & " from " & IIf(udp.RemoteHost = addr, "us", udp.RemoteHost)
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

' the loopback address, or this machine's address where there is no loopback interface
' (Roadshow on some AmigaOS setups)
addr = "127.0.0.1"
Set l = CreateObject("Socket")
On Error Resume Next
l.Listen 0, addr
If Err.Number Then addr = l.MachineAddress
On Error GoTo 0
Print "machine address:"; Len(l.MachineAddress) >= 7

' ---- blocking TCP, no events
Set l = CreateObject("Socket")
l.Listen 0, addr
Print "listening:"; l.State = sockListening; l.LocalPort > 0
Set a = CreateObject("Socket")
a.Timeout = 5000
a.Connect addr, l.LocalPort
Print "connected:"; a.Connected; a.State; a.RemoteHost = addr; a.RemotePort = l.LocalPort
Set b = l.Accept(2000)
Print "accepted:"; Not b Is Nothing; b.RemoteHost = addr; b.RemotePort = a.LocalPort
a.Send "line one" & vbCrLf & "line two" & vbLf & "partial"
b.Timeout = 2000
Print b.ReceiveLine(); "|"; b.ReceiveLine(); "|"
Print "read:"; b.Read(4)
' 200 KB in 4 KB pieces, read as they come (one program can't send more than the network
' buffers hold to a socket it isn't reading yet; those are small on AmigaOS)
Dim got As String, piece As String
piece = String(4096, "x")
got = b.Receive()                       ' "ial" left from above
For i = 1 To 50
    a.Send piece
    got = got & b.Read(4096)
Next
a.Send "END"
got = got & b.Read(3)
Print "big:"; Len(got); " "; Left(got, 4); " "; Right(got, 4)
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
a.Connect addr, port       ' port 0: refused
Print "refused:"; Err.Number
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
srv.Listen 0, addr
port = srv.LocalPort
Set cli = CreateObject("Socket")
cli.Connect addr, port
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
cli.Connect addr, port
WaitFor "client got HELLO"
Print Sorted()
conns(2).Close
WaitFor "server closed"
Print Sorted()

' ---- connect error as an event
srv.Close
Set cli = CreateObject("Socket")
cli.Connect addr, port
Set srv = cli
WaitFor "error"
Print Sorted(); " "; cli.State = sockError

' ---- UDP
log = ""
Set udp = CreateObject("Socket")
udp.Bind 0, addr
Print "udp:"; udp.Protocol; udp.State = sockOpen; udp.LocalPort > 0
Set a = CreateObject("Socket")
a.SendTo addr, udp.LocalPort, "ping"
a.SendTo addr, udp.LocalPort, "pong!"
Set srv = udp                 ' WaitFor waits through srv
WaitFor "pong"
Print Sorted()
Set b = CreateObject("Socket")
b.Bind 0, addr
a.SendTo addr, b.LocalPort, "direct"
s = b.ReceiveFrom(1000)
Print "ReceiveFrom:"; s; " "; b.RemotePort = a.LocalPort; " ["; b.ReceiveFrom(); "]"
b.Tag = "keep"
Print TypeName(b); " "; b.Tag
