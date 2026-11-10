' UDP: two sockets on this machine send each other datagrams
Option Explicit
Dim a As Socket, b As Socket, addr As String, msg As String

Set b = CreateObject("Socket")
addr = "127.0.0.1"
On Error Resume Next
b.Bind 0, addr                        ' 0: any free port
If Err.Number <> 0 Then addr = b.MachineAddress: Err.Clear: b.Bind 0, addr
On Error GoTo 0
Print "b:"; b.Protocol; " "; b.State = sockOpen

Set a = CreateObject("Socket")
a.SendTo addr, b.LocalPort, "ping"    ' a opens itself on any free port
msg = b.ReceiveFrom(2000)             ' wait up to 2 seconds
Print "b got "; msg; ", from a:"; b.RemotePort = a.LocalPort
b.SendTo b.RemoteHost, b.RemotePort, "pong"
Print "a got "; a.ReceiveFrom(2000)
Print "nothing more: ["; a.ReceiveFrom(); "]"
