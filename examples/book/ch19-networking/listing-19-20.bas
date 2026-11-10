Option Explicit
Dim server As Socket, client As Socket
Set server = CreateObject("Socket")
server.Listen 7000
Do
    Set client = server.Accept(60000)        ' Nothing when nobody came within a minute
    If Not client Is Nothing Then
        client.SendLine "Hello from the Amiga, " & client.RemoteHost
        client.Close
    End If
Loop
