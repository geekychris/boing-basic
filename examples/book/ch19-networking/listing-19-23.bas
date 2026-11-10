' the echo server and client again, with events
Option Explicit
Dim WithEvents server As Socket
Dim WithEvents link As Socket
Dim conns As New Collection            ' the accepted connections (keep them!)
Dim done As Boolean

Sub server_ConnectionRequest()
    conns.Add server.Accept()
End Sub

Sub server_ClientDataArrival(ByVal Client As Socket, ByVal Bytes As Long)
    Do While InStr(Client.Peek(), vbLf) > 0
        Client.SendLine UCase(Client.ReceiveLine())
    Loop
End Sub

Sub server_ClientClose(ByVal Client As Socket)
    Client.Close
End Sub

Sub link_Connect()
    Print "connected"
    link.SendLine "hello"
    link.SendLine "bye"
End Sub

Sub link_DataArrival(ByVal Bytes As Long)
    Dim reply As String
    Do While InStr(link.Peek(), vbLf) > 0
        reply = link.ReceiveLine()
        Print "client got: "; reply
        If reply = "BYE" Then link.Close: done = True
    Loop
End Sub

Sub link_Error(ByVal Number As Long, ByVal Description As String)
    Print "can't connect: "; Description
    done = True
End Sub

Sub Main()
    Dim addr As String, t As Double
    Set server = CreateObject("Socket")
    addr = "127.0.0.1"
    On Error Resume Next
    server.Listen 0, addr
    If Err.Number <> 0 Then addr = server.MachineAddress: Err.Clear: server.Listen 0, addr
    On Error GoTo 0
    Set link = CreateObject("Socket")
    link.Connect addr, server.LocalPort        ' returns at once: Connect or Error follows
    t = Timer
    Do Until done Or Timer - t > 10
        server.WaitEvents 100                  ' fires the events of every socket
    Loop
    server.Close
End Sub
