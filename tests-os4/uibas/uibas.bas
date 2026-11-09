' uibas.bas - docs/ui.md from BASIC: menus, toolbar, status bar, CommonDialog object, settings,
' App members, an ARexx round trip through RX, a program icon, clipboard pictures. TAP lines.
Option Explicit

Private n As Integer, fails As Integer, steps As Integer, rexxCmds As Integer, news As Integer
Private savedClip As String

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then
        Print "ok "; n; " - "; what
    Else
        Print "not ok "; n; " - "; what
        fails = fails + 1
    End If
End Sub

Private Sub Form_Load()
    Check mnuNew.Caption = "New", "mnuNew.Caption from the .afg"
    Check mnuNew.Shortcut = "N", "mnuNew.Shortcut"
    Check mnuGrid.Checked, "mnuGrid.Checked"
    mnuGrid.Checked = False
    Check Not mnuGrid.Checked, "mnuGrid.Checked = False"
    Check TypeName(mnuNew) = "Menu", "TypeName(mnuNew) = Menu"
    Check view.ContextMenu = "mnuCtx", "view.ContextMenu"
    Check status.Caption = "Ready", "a $3:Ready text without a catalog is Ready"
    Check tbGrid.Value = 1, "tbGrid.Value = 1"
    Check tb.ButtonCount = 3, "tb.ButtonCount = 3"
    Check sb.Panel(1) = "Ln 1", "sb.Panel(1)"
    sb.Panel(1) = "Ln 7"
    Check sb.Panel(1) = "Ln 7", "sb.Panel(1) = ""Ln 7"""
    Check TypeName(dlg) = "CommonDialog", "TypeName(dlg) = CommonDialog"
    dlg.Filter = "Pictures|#?.(png|iff)"
    Check dlg.Filter = "Pictures|#?.(png|iff)", "dlg.Filter"
End Sub

Private Sub Form_Activate()
    If steps = 0 Then Me.Caption = "Boing BASIC UI test - running"
End Sub

Private Sub mnuNew_Click()
    news = news + 1
End Sub

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    rexxCmds = rexxCmds + 1
    Select Case UCase(Cmd)
    Case "ECHO": Result = "echo:" & Args
    Case Else: App.ARexxRC = 5
    End Select
End Sub

Private Sub tick_Timer()
    Dim d As Object, s As String, f As Integer
    steps = steps + 1
    Select Case steps
    Case 1
        Me.AddMenu "mnuExtra", "Extra", "mnuView", "X"
        Check Me.Controls("mnuExtra").Caption = "Extra", "Me.AddMenu + Me.Controls(""mnuExtra"")"
        Me.RemoveMenu "mnuExtra"
        mnuNew.Enabled = False
        Check Not tbNew.Enabled, "mnuNew.Enabled = False disables tbNew (menu=)"
        mnuNew.Enabled = True
        Set d = CreateObject("Boing.CommonDialog")
        d.DialogTitle = "Object"
        d.Flags = &H200
        Check d.DialogTitle = "Object" And d.Flags = &H200, "CreateObject(""Boing.CommonDialog"")"
        Set d = Nothing
        SaveSetting "BoingUiTest", "Window", "Left", "123"
        Check GetSetting("BoingUiTest", "Window", "Left", "0") = "123", "SaveSetting/GetSetting in ENV:"
        DeleteSetting "BoingUiTest"
        Check GetSetting("BoingUiTest", "Window", "Left", "gone") = "gone", "DeleteSetting"
        Check App.ToolType("NOSUCH", "dflt") = "dflt", "App.ToolType default"
        Check Not App.FromWorkbench, "App.FromWorkbench = False from a shell"
        Check App.Str(99, "Open...") = "Open...", "App.Str without a catalog"
        App.ARexxPort = "BBUITEST"
        Check Left(App.ARexxPortName, 8) = "BBUITEST", "App.ARexxPort opened (" & App.ARexxPortName & ")"
        Check App.SendARexx(App.ARexxPortName, "ECHO self") = "echo:self", "App.SendARexx to the own port"
        ' an ARexx script run by App.RunARexx (asynchronous: Shell would wait for rx, which
        ' waits for this program to answer)
        f = FreeFile
        Open "RAM:bbt/uitest.rexx" For Output As #f
        Print #f, "/* uibas */"
        Print #f, "options results"
        Print #f, "address '" & App.ARexxPortName & "' 'ECHO from rx'"
        Print #f, "r = result"
        Print #f, "call open(out, 'RAM:bbt/rx.out', 'w'); call writeln(out, r); call close(out)"
        Close #f
        App.RunARexx "RAM:bbt/uitest.rexx"
    Case 2 To 20
        If Dir("RAM:bbt/rx.out") <> "" Then
            f = FreeFile
            Open "RAM:bbt/rx.out" For Input As #f
            Line Input #f, s
            Close #f
            Kill "RAM:bbt/rx.out"
            Kill "RAM:bbt/uitest.rexx"
            Check s = "echo:from rx", "an ARexx script's command reached ARexx_Command and got RESULT (" & s & ")"
            steps = 30
        ElseIf steps = 20 Then
            Check False, "the RX script answered within 6 s"
            steps = 30
        End If
    Case 31
        App.SaveIcon "RAM:bbt/uitest_doc"
        Check Dir("RAM:bbt/uitest_doc.info") <> "", "App.SaveIcon wrote a project icon"
        Kill "RAM:bbt/uitest_doc.info"
        ' clipboard picture round trip; the text on the clipboard is put back afterwards
        savedClip = Clipboard.GetText
        view.Cls
        view.Box 0, 0, 64, 32, RGB(200, 40, 40)
        view.Box 10, 5, 31, 16, RGB(20, 200, 90)
        Clipboard.SetPicture view
        Check Clipboard.HasPicture, "Clipboard.HasPicture after SetPicture"
        Dim back As Object
        Set back = CreateObject("Boing.Canvas")
        Check Clipboard.GetPicture(back), "Clipboard.GetPicture into another canvas"
        Check back.Width = 64 And back.Height = 32, "the picture's size came back (" & back.Width & "x" & back.Height & ")"
        Check back.Point(20, 10) = RGB(20, 200, 90) And back.Point(2, 2) = RGB(200, 40, 40), "the pixels came back"
        Clipboard.SetText savedClip
    Case 32
        Check rexxCmds = 2, "two ARexx commands (" & rexxCmds & ")"
        App.ARexxPort = ""
        tick.Enabled = False
        Unload Me
    End Select
End Sub

Private Sub Form_Unload(Cancel As Integer)
    If fails = 0 Then Print "PASS ("; n; "/"; n; ")" Else Print "FAIL ("; n - fails; "/"; n; ")"
End Sub
