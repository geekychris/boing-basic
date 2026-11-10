' A server and a client socket on one form: Connect, ConnectionRequest, DataArrival and Close
' all come in through the form's event loop while a Timer runs too
Dim WithEvents srv As Socket
Dim WithEvents cli As Socket
Dim peer As Socket
Dim ticks As Long, sendTwo As Boolean, addr As String

Private Sub Form_Load()
    Set srv = CreateObject("Socket")
    addr = "127.0.0.1"
    On Error Resume Next
    srv.Listen 0, addr
    If Err.Number Then addr = srv.MachineAddress: Err.Clear: srv.Listen 0, addr     ' no loopback
    On Error GoTo 0
    Set cli = CreateObject("Socket")
    cli.Connect addr, srv.LocalPort
End Sub

Private Sub srv_ConnectionRequest()
    Set peer = srv.Accept()
    Print "server: connection from us: "; peer.RemoteHost = addr
End Sub

Private Sub srv_ClientDataArrival(ByVal Client As Socket, ByVal Bytes As Long)
    Dim l As String
    Do While InStr(Client.Peek(), vbLf) > 0
        l = Client.ReceiveLine()
        Client.SendLine "echo " & l
        If l = "bye" Then Client.Close
    Loop
End Sub

Private Sub cli_Connect()
    Print "client: connected"
    cli.SendLine "one"
End Sub

Private Sub cli_DataArrival(ByVal Bytes As Long)
    Dim l As String
    Do While InStr(cli.Peek(), vbLf) > 0
        l = cli.ReceiveLine()
        Print "client: "; l
        status.Text = l
        If l = "echo one" Then sendTwo = True     ' the Timer sends it
        If l = "echo two" Then cli.SendLine "bye"
    Loop
End Sub

Private Sub cli_Close()
    Print "client: server closed; status "; status.Text; "; timer ran: "; ticks > 0
    End
End Sub

Private Sub tick_Timer()
    ticks = ticks + 1
    If sendTwo Then
        sendTwo = False
        cli.SendLine "two"
    End If
End Sub

Private Sub watchdog_Timer()
    Print "timed out"
    End
End Sub
