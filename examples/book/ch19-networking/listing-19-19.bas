' an echo server and its client in one program, with waiting calls
Option Explicit
Dim server As Socket, client As Socket, conn As Socket, addr As String, word As Variant

Set server = CreateObject("Socket")
addr = "127.0.0.1"
On Error Resume Next
server.Listen 0, addr                  ' 0: any free port
If Err.Number <> 0 Then                ' no loopback interface (some Roadshow setups)
    addr = server.MachineAddress
    Err.Clear
    server.Listen 0, addr
End If
On Error GoTo 0

Set client = CreateObject("Socket")
client.Timeout = 5000
client.Connect addr, server.LocalPort
Set conn = server.Accept(2000)         ' the server's end of the connection
conn.Timeout = 5000

For Each word In Array("hello", "Amiga", "bye")
    client.SendLine word               ' the client sends a line
    conn.SendLine UCase(conn.ReceiveLine())     ' the server echoes it in capitals
    Print "client got: "; client.ReceiveLine()
Next

client.Close
Print "server sees the end:"; conn.ReceiveLine() = ""; conn.AtEnd
conn.Close
server.Close
