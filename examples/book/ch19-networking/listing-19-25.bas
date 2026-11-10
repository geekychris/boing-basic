' what goes wrong, as run-time errors
Option Explicit
Dim s As Socket, l As Socket, addr As String, port As Long, text As String

Set l = CreateObject("Socket")
addr = "127.0.0.1"
On Error Resume Next
l.Listen 0, addr
If Err.Number <> 0 Then addr = l.MachineAddress: Err.Clear: l.Listen 0, addr
port = l.LocalPort
l.Close                               ' nobody listens on port now

Set s = CreateObject("Socket")
s.Timeout = 3000
s.Connect addr, port
Print "connect:"; Err.Number
Err.Clear
s.Send "x"
Print "send:"; Err.Number; " "; Err.Description
Err.Clear
s.Listen 70000
Print "listen:"; Err.Number; " "; Err.Description
Err.Clear
l.Listen 0, addr
Set s = CreateObject("Socket")
s.Connect addr, l.LocalPort
s.Timeout = 300
text = s.ReceiveLine()               ' the server never sends anything
Print "line:"; Err.Number; " "; Err.Description
