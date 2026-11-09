' BoingPad - a small text editor for AmigaOS 4 in Boing BASIC (docs/ui.md):
' menus with Amiga-key shortcuts and a context menu, a toolbar linked to the menus, a status
' bar, the CommonDialog (asl), the TextEditor's find/replace/undo, settings in ENVARC:, a
' recent-files menu built at run time, project icons for saved files, files dropped on the
' window, and an ARexx port (OPEN file, SAVE, TEXT, GOTO line, QUIT).
Option Explicit

Const APPNAME = "BoingPad"
Private fileName As String
Private recent(3) As String

Private Sub Form_Load()
    Dim i As Integer
    mnuFixed.Checked = GetSetting(APPNAME, "View", "FixedFont", "0") = "1"
    ed.FixedFont = mnuFixed.Checked
    mnuIcons.Checked = GetSetting(APPNAME, "Files", "Icons", "1") = "1"
    For i = 0 To 3
        recent(i) = GetSetting(APPNAME, "Recent", "File" & i, "")
    Next
    BuildRecentMenu
    App.ARexxPort = "BOINGPAD"
    UpdateTitle
    If App.ArgCount > 0 Then LoadFile App.Arg(0)
    If Environ("BOING_SMOKE") <> "" Then smoke.Interval = 1500
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not ConfirmDiscard() Then Cancel = True
End Sub

Private Sub Form_Unload(Cancel As Integer)
    SaveSetting APPNAME, "View", "FixedFont", IIf(mnuFixed.Checked, "1", "0")
    SaveSetting APPNAME, "Files", "Icons", IIf(mnuIcons.Checked, "1", "0")
End Sub

' --- files -------------------------------------------------------------------------------

Private Function ConfirmDiscard() As Boolean
    If Not ed.Modified Then ConfirmDiscard = True: Exit Function
    Select Case dlg.ShowMessage("The text has changed." & vbLf & "Save it first?", "_Save|_Discard|_Cancel", APPNAME, vbQuestion)
    Case 1: ConfirmDiscard = SaveFile(False)
    Case 2: ConfirmDiscard = True
    Case Else: ConfirmDiscard = False
    End Select
End Function

Private Sub LoadFile(path As String)
    On Error GoTo failed
    ed.LoadFile path
    fileName = path
    ed.Modified = False
    AddRecent path
    UpdateTitle
    sb.Text = "Loaded " & path
    Exit Sub
failed:
    MsgBox "Can't open " & path & vbLf & Err.Description, vbExclamation, APPNAME
End Sub

Private Function SaveFile(askName As Boolean) As Boolean
    If askName Or fileName = "" Then
        dlg.DialogTitle = "Save the text"
        dlg.FileName = fileName
        dlg.Flags = cdlOFNOverwritePrompt
        dlg.ShowSave
        If dlg.Cancelled Then Exit Function
        fileName = dlg.FileName
    End If
    On Error GoTo failed
    ed.SaveFile fileName
    If mnuIcons.Checked And Dir(fileName & ".info") = "" Then App.SaveIcon fileName
    AddRecent fileName
    UpdateTitle
    sb.Text = "Saved " & fileName
    SaveFile = True
    Exit Function
failed:
    MsgBox "Can't save " & fileName & vbLf & Err.Description, vbExclamation, APPNAME
End Function

Private Sub UpdateTitle()
    If fileName = "" Then Me.Caption = APPNAME & " - (untitled)" Else Me.Caption = APPNAME & " - " & fileName
End Sub

Private Sub AddRecent(path As String)
    Dim i As Integer, j As Integer
    For i = 0 To 3
        If recent(i) = path Then Exit For
    Next
    If i > 3 Then i = 3
    For j = i To 1 Step -1
        recent(j) = recent(j - 1)
    Next
    recent(0) = path
    For i = 0 To 3
        SaveSetting APPNAME, "Recent", "File" & i, recent(i)
    Next
    BuildRecentMenu
End Sub

' the Recent files sub-menu, rebuilt at run time
Private Sub BuildRecentMenu()
    Dim i As Integer
    On Error Resume Next
    For i = 0 To 3
        Me.RemoveMenu "mnuRecentFile" & i
    Next
    On Error GoTo 0
    mnuRecent0.Visible = recent(0) = ""
    For i = 0 To 3
        If recent(i) <> "" Then Me.AddMenu "mnuRecentFile" & i, recent(i), "mnuRecent", CStr(i + 1)
    Next
End Sub

Private Sub OpenRecent(i As Integer)
    If recent(i) <> "" And ConfirmDiscard() Then LoadFile recent(i)
End Sub

Private Sub mnuRecentFile0_Click(): OpenRecent 0: End Sub
Private Sub mnuRecentFile1_Click(): OpenRecent 1: End Sub
Private Sub mnuRecentFile2_Click(): OpenRecent 2: End Sub
Private Sub mnuRecentFile3_Click(): OpenRecent 3: End Sub

' --- menus (the toolbar's tools call these through menu=) ---------------------------------

Private Sub mnuNew_Click()
    If Not ConfirmDiscard() Then Exit Sub
    ed.Text = ""
    ed.Modified = False
    fileName = ""
    UpdateTitle
End Sub

Private Sub mnuOpen_Click()
    If Not ConfirmDiscard() Then Exit Sub
    dlg.DialogTitle = "Open a text"
    dlg.Flags = cdlOFNFileMustExist
    dlg.ShowOpen
    If Not dlg.Cancelled Then LoadFile dlg.FileName
End Sub

Private Sub mnuSave_Click(): SaveFile False: End Sub
Private Sub mnuSaveAs_Click(): SaveFile True: End Sub
Private Sub mnuQuit_Click(): Unload Me: End Sub

Private Sub mnuAbout_Click()
    App.Request APPNAME & vbLf & "A text editor written in Boing BASIC." & vbLf & "ARexx port: " & App.ARexxPortName, "_OK", "About " & APPNAME, vbInformation
End Sub

Private Sub mnuUndo_Click(): ed.Undo: End Sub
Private Sub mnuRedo_Click(): ed.Redo: End Sub
Private Sub mnuCut_Click(): ed.Cut: End Sub
Private Sub mnuCopy_Click(): ed.Copy: End Sub
Private Sub mnuPaste_Click(): ed.Paste: End Sub
Private Sub mnuSelAll_Click(): ed.SelectAll: End Sub
Private Sub mnuCtxCut_Click(): ed.Cut: End Sub
Private Sub mnuCtxCopy_Click(): ed.Copy: End Sub
Private Sub mnuCtxPaste_Click(): ed.Paste: End Sub
Private Sub mnuCtxSelAll_Click(): ed.SelectAll: End Sub

Private Sub mnuFind_Click()
    If findText.Text = "" Then findText.SetFocus: Exit Sub
    If Not ed.Find(findText.Text, matchCase.Value = vbChecked) Then
        If Not ed.Find(findText.Text, matchCase.Value = vbChecked, True) Then sb.Text = "Not found: " & findText.Text
    End If
End Sub

Private Sub findNext_Click(): mnuFind_Click: End Sub

Private Sub findText_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then mnuFind_Click
End Sub

Private Sub replAll_Click()
    Dim n As Long
    If findText.Text = "" Then Exit Sub
    n = ed.Replace(findText.Text, replText.Text, True, matchCase.Value = vbChecked)
    sb.Text = n & " replaced"
End Sub

Private Sub mnuFixed_Click()
    ed.FixedFont = mnuFixed.Checked
End Sub

Private Sub mnuFont_Click()
    dlg.ShowFont
    If Not dlg.Cancelled Then sb.Text = "Font: " & dlg.FontName & " " & dlg.FontSize & " (the editor uses the screen's fonts)"
End Sub

Private Sub mnuIcons_Click()
End Sub

' --- the editor and the status bar ---------------------------------------------------------

Private Sub ed_CursorMove()
    sb.Panel(1) = "Ln " & (ed.CurrentLine + 1) & ", Col " & (ed.CurrentColumn + 1)
End Sub

Private Sub ed_Change()
    If sb.Text <> "Modified" And ed.Modified Then sb.Text = "Modified"
End Sub

' --- files dropped on the window -----------------------------------------------------------

Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    If Count > 0 And ConfirmDiscard() Then LoadFile App.DropFile(0)
End Sub

' --- ARexx: OPEN file, SAVE, TEXT (returns the text), GOTO line, QUIT ----------------------

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "OPEN": LoadFile Args
    Case "SAVE": If Not SaveFile(False) Then App.ARexxRC = 5
    Case "TEXT": Result = ed.Text
    Case "GOTO": ed.CurrentLine = Val(Args) - 1
    Case "QUIT": ed.Modified = False: Unload Me
    Case Else: App.ARexxRC = 10
    End Select
End Sub

' --- BOING_SMOKE=1: open, check a few things, close (tools/os4guest.py bas) -----------------

Private Sub smoke_Timer()
    smoke.Enabled = False
    ed.Text = "smoke test" & vbLf & "line two"
    Print IIf(ed.LineCount = 2 And tb.ButtonCount = 9 And mnuNew.Shortcut = "N", "PASS", "FAIL")
    ed.Modified = False
    Unload Me
End Sub
