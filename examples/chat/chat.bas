' chat.bas - the code-behind of chat.afg: a chat room over TCP with the Socket class.
' One program is both ends: "Host a chat" listens and relays every line to everyone;
' "Join" connects to a host. The protocol is plain text lines ("name: text"), so a telnet or
' netcat client can join too.
Option Explicit

Private WithEvents server As Socket     ' when hosting: the listening socket
Private WithEvents link As Socket       ' when joined: the connection to the host
Private clients As Collection           ' when hosting: the connected clients
Private greeting As String              ' chat join ...: a line to say once connected

Private Sub Form_Load()
    Dim a, i As Long
    log.Locked = True
    ' from a shell:  chat host [PORT]   or   chat join HOST|self PORT NAME [message ...]
    a = Split(Trim(Command()), " ")
    If UBound(a) < 0 Then Exit Sub
    If Left(a(UBound(a)), 1) = "@" Then          ' ... @X,Y places the window
        Dim xy
        xy = Split(Mid(a(UBound(a)), 2), ",")
        If UBound(xy) = 1 Then Me.Move CLng(xy(0)), CLng(xy(1))
        If UBound(a) = 0 Then Exit Sub
        ReDim Preserve a(UBound(a) - 1)
    End If
    Select Case LCase(a(0))
    Case "host"
        If UBound(a) >= 1 Then port.Text = a(1)
        hostbtn_Click
    Case "join"
        If UBound(a) >= 3 Then
            host.Text = IIf(LCase(a(1)) = "self", CreateObject("Socket").MachineAddress, a(1))
            port.Text = a(2)
            nick.Text = a(3)
            For i = 4 To UBound(a): greeting = greeting & IIf(i > 4, " ", "") & a(i): Next
            joinbtn_Click
        End If
    End Select
End Sub

Private Sub Show(ByVal text As String)
    log.Text = log.Text & text & vbLf
    log.SelStart = Len(log.Text)
End Sub

Private Sub SetConnected(ByVal isOn As Boolean, ByVal what As String)
    hostbtn.Enabled = Not isOn
    joinbtn.Enabled = Not isOn
    leavebtn.Enabled = isOn
    sendbtn.Enabled = isOn
    status.Caption = what
End Sub

' ---- hosting ----

Private Sub hostbtn_Click()
    On Error GoTo Failed
    Set clients = New Collection
    Set server = CreateObject("Socket")
    server.Listen CLng(port.Text)
    SetConnected True, "Hosting on " & server.MachineAddress & ":" & server.LocalPort & " - 0 people joined"
    Show "* You are hosting. Others join with Host = " & server.MachineAddress & ", Port = " & server.LocalPort
    Exit Sub
Failed:
    status.Caption = "Can't host: " & Err.Description
    Set server = Nothing
End Sub

Private Sub server_ConnectionRequest()
    Dim c As Socket
    Set c = server.Accept()
    If c Is Nothing Then Exit Sub
    clients.Add c
    Relay Nothing, "* someone joined from " & c.RemoteHost
    status.Caption = "Hosting - " & clients.Count & " people joined"
End Sub

Private Sub server_ClientDataArrival(ByVal conn As Socket, ByVal Bytes As Long)
    Do While InStr(conn.Peek(), vbLf) > 0
        Relay conn, conn.ReceiveLine()
    Loop
End Sub

Private Sub server_ClientClose(ByVal conn As Socket)
    Dim i As Long
    For i = clients.Count To 1 Step -1
        If clients(i) Is conn Then clients.Remove i
    Next
    conn.Close
    Relay Nothing, "* someone left"
    status.Caption = "Hosting - " & clients.Count & " people joined"
End Sub

' a line to everyone but its sender, and to our own window
Private Sub Relay(ByVal from As Socket, ByVal text As String)
    Dim c As Variant
    Show text
    On Error Resume Next            ' a client that just went away
    For Each c In clients
        If Not c Is from Then c.SendLine text
    Next
End Sub

' ---- joining ----

Private Sub joinbtn_Click()
    On Error GoTo Failed
    Set link = CreateObject("Socket")
    link.Timeout = 10000
    status.Caption = "Connecting to " & host.Text & ":" & port.Text & " ..."
    link.Connect host.Text, CLng(port.Text)        ' with events: Connect or Error follows
    hostbtn.Enabled = False
    joinbtn.Enabled = False
    Exit Sub
Failed:
    status.Caption = "Can't connect: " & Err.Description
End Sub

Private Sub link_Connect()
    SetConnected True, "Connected to " & link.RemoteHost & ":" & link.RemotePort
    link.SendLine "* " & nick.Text & " is here"
    If greeting <> "" Then
        link.SendLine nick.Text & ": " & greeting
        Show nick.Text & ": " & greeting
        greeting = ""
    End If
End Sub

Private Sub link_Error(ByVal Number As Long, ByVal Description As String)
    SetConnected False, "Can't connect: " & Description
End Sub

Private Sub link_DataArrival(ByVal Bytes As Long)
    Do While InStr(link.Peek(), vbLf) > 0
        Show link.ReceiveLine()
    Loop
End Sub

Private Sub link_Close()
    Show "* the host closed the chat"
    SetConnected False, "Disconnected"
End Sub

' ---- both ----

Private Sub sendbtn_Click()
    Dim line As String
    If msg.Text = "" Then Exit Sub
    line = nick.Text & ": " & msg.Text
    msg.Text = ""
    If Not server Is Nothing Then
        Relay Nothing, line
    ElseIf Not link Is Nothing Then
        Show line
        link.SendLine line
    End If
    msg.SetFocus
End Sub

Private Sub msg_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then sendbtn_Click
End Sub

Private Sub leavebtn_Click()
    If Not server Is Nothing Then
        Dim c As Variant
        For Each c In clients: c.Close: Next
        server.Close
        Set server = Nothing
        Show "* you closed the chat"
    End If
    If Not link Is Nothing Then
        link.Close
        Set link = Nothing
        Show "* you left"
    End If
    SetConnected False, "Host a chat, or join one at Host:Port"
End Sub

Private Sub Form_Unload(Cancel As Integer)
    If leavebtn.Enabled Then leavebtn_Click
End Sub
