' jotter.bas - the code-behind of jotter.afg
Option Explicit

Private fileName As String

Private Sub Form_Load()
    mnuFixed.Checked = GetSetting(APPNAME, "Settings", "FixedFont", "0") = "1"
    mnuIcons.Checked = GetSetting(APPNAME, "Settings", "Icons", "1") = "1"
    ed.FixedFont = mnuFixed.Checked
    App.ARexxPort = "JOTTER"                         ' JOTTER.1 if one is running already
    App.HelpFile = App.Path & "/Jotter.guide"        ' the Help key opens it
    If App.ArgCount > 0 Then LoadFile App.Arg(0)     ' a project icon, or "Jotter file" in the Shell
    UpdateTitle
End Sub

' --- the title: the document's name, and * while it has unsaved changes -------------------

Private Sub UpdateTitle()
    Dim name As String
    If fileName = "" Then name = "Untitled" Else name = Mid(fileName, InStrRev(fileName, "/") + 1)
    If InStr(name, ":") > 0 Then name = Mid(name, InStr(name, ":") + 1)
    Me.Caption = APPNAME & ": " & name & IIf(ed.Modified, " *", "")
End Sub

Private Sub ed_Change()
    UpdateTitle
End Sub

Private Sub ed_CursorMove()
    sb.Panel(1) = "Ln " & (ed.CurrentLine + 1)
End Sub

' --- closing: ask before throwing work away -----------------------------------------------

Private Function MayDiscard() As Boolean
    If Not ed.Modified Then MayDiscard = True: Exit Function
    Select Case dlg.ShowMessage("The text has changed." & vbLf & "Save it first?", _
                                "_Save|_Discard|_Cancel", APPNAME, vbQuestion)
    Case 1: MayDiscard = SaveFile(False)
    Case 2: MayDiscard = True
    Case Else: MayDiscard = False
    End Select
End Function

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not MayDiscard() Then Cancel = True
End Sub

Private Sub Form_Unload(Cancel As Integer)
    SaveSetting APPNAME, "Settings", "FixedFont", IIf(mnuFixed.Checked, "1", "0")
    SaveSetting APPNAME, "Settings", "Icons", IIf(mnuIcons.Checked, "1", "0")
End Sub

' --- files ----------------------------------------------------------------------------------

Private Sub LoadFile(ByVal path As String)
    On Error GoTo failed
    ed.LoadFile path
    fileName = path
    ed.Modified = False
    UpdateTitle
    sb.Text = "Loaded"
    Exit Sub
failed:
    MsgBox "Can't open " & path & vbLf & Err.Description, vbExclamation, APPNAME
End Sub

Private Function SaveFile(ByVal askName As Boolean) As Boolean
    If askName Or fileName = "" Then
        dlg.DialogTitle = "Save the text as"
        dlg.Flags = cdlOFNOverwritePrompt
        dlg.FileName = fileName
        dlg.ShowSave
        If dlg.Cancelled Then Exit Function
        fileName = dlg.FileName
    End If
    On Error GoTo failed
    ed.SaveFile fileName
    ed.Modified = False
    If mnuIcons.Checked And Dir(fileName & ".info") = "" Then App.SaveIcon fileName
    UpdateTitle
    sb.Text = "Saved"
    SaveFile = True
    Exit Function
failed:
    MsgBox "Can't save " & fileName & vbLf & Err.Description, vbExclamation, APPNAME
End Function

' --- the Project menu -----------------------------------------------------------------------

Private Sub mnuNew_Click()
    If Not MayDiscard() Then Exit Sub
    ed.Text = ""
    ed.Modified = False
    fileName = ""
    UpdateTitle
End Sub

Private Sub mnuOpen_Click()
    If Not MayDiscard() Then Exit Sub
    dlg.DialogTitle = "Open a text"
    dlg.Flags = cdlOFNFileMustExist
    dlg.ShowOpen
    If Not dlg.Cancelled Then LoadFile dlg.FileName
End Sub

Private Sub mnuSave_Click(): SaveFile False: End Sub
Private Sub mnuSaveAs_Click(): SaveFile True: End Sub
Private Sub mnuHelp_Click(): App.ShowHelp App.HelpFile, "main": End Sub
Private Sub mnuQuit_Click(): Unload Me: End Sub

Private Sub mnuAbout_Click()
    App.Request Mid(VERSTAG, 7) & vbLf & "A small text editor." & vbLf & _
                "ARexx port: " & App.ARexxPortName, "_OK", "About " & APPNAME, vbInformation
End Sub

' --- the Edit menu and the context menu -----------------------------------------------------

Private Sub mnuUndo_Click(): ed.Undo: End Sub
Private Sub mnuRedo_Click(): ed.Redo: End Sub
Private Sub mnuCut_Click(): ed.Cut: End Sub
Private Sub mnuCopy_Click(): ed.Copy: End Sub
Private Sub mnuPaste_Click(): ed.Paste: End Sub
Private Sub mnuSelAll_Click(): ed.SelectAll: End Sub
Private Sub mnuCtxCut_Click(): ed.Cut: End Sub
Private Sub mnuCtxCopy_Click(): ed.Copy: End Sub
Private Sub mnuCtxPaste_Click(): ed.Paste: End Sub

' --- the Settings menu ----------------------------------------------------------------------

Private Sub mnuFixed_Click()
    ed.FixedFont = mnuFixed.Checked
End Sub

' --- the Workbench: files dropped on the window ---------------------------------------------

Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    If Count > 0 And MayDiscard() Then LoadFile App.DropFile(0)
End Sub

' --- the Help key, when there is no guide ---------------------------------------------------

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyHelp Then sb.Text = "Right mouse button: menus"
End Sub

' --- ARexx: OPEN file, SAVE, GETTEXT, QUIT --------------------------------------------------

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "OPEN": LoadFile Args
    Case "SAVE": If Not SaveFile(False) Then App.ARexxRC = 5
    Case "GETTEXT": Result = ed.Text
    Case "QUIT": ed.Modified = False: Unload Me
    Case Else: App.ARexxRC = 10
    End Select
End Sub
