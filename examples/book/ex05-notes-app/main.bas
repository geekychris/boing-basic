' main.bas - the code-behind of main.afg, the main window of Notes
' (exercise 5 of the Boing BASIC manual).
Option Explicit

Const APPNAME = "Notes"
Private fileName As String        ' the file being edited, "" for a new note

' --- starting and stopping ---------------------------------------------------------------

Private Sub Form_Load()
    ' the settings saved last time (GetSetting gives the default when there are none)
    mnuFixed.Checked = GetSetting(APPNAME, "View", "FixedFont", "0") = "1"
    mnuReopen.Checked = GetSetting(APPNAME, "Files", "Reopen", "1") = "1"
    ed.FixedFont = mnuFixed.Checked
    If mnuReopen.Checked Then
        fileName = GetSetting(APPNAME, "Files", "Last", "")
        If fileName <> "" Then
            If Dir(fileName) <> "" Then LoadFile fileName Else fileName = ""
        End If
    End If
    UpdateTitle
End Sub

' Before the window closes (close gadget, Quit, or Unload from code): may we?
Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not ConfirmDiscard() Then Cancel = True
End Sub

' The window is closing for good: remember the settings, close the Find window too.
Private Sub Form_Unload(Cancel As Integer)
    SaveSetting APPNAME, "View", "FixedFont", IIf(mnuFixed.Checked, "1", "0")
    SaveSetting APPNAME, "Files", "Reopen", IIf(mnuReopen.Checked, "1", "0")
    SaveSetting APPNAME, "Files", "Last", fileName
    Unload finder
End Sub

' --- files -------------------------------------------------------------------------------

' True when it is all right to throw the text away: it is unchanged, or the user saved it
' or said "No".
Private Function ConfirmDiscard() As Boolean
    If Not ed.Modified Then
        ConfirmDiscard = True
        Exit Function
    End If
    Select Case MsgBox("The note has changed." & vbLf & "Save the changes?", vbYesNoCancel + vbQuestion, APPNAME)
    Case vbYes: ConfirmDiscard = SaveFile(False)
    Case vbNo: ConfirmDiscard = True
    Case Else: ConfirmDiscard = False          ' Cancel: stay
    End Select
End Function

Private Sub LoadFile(ByVal path As String)
    On Error GoTo Failed
    ed.LoadFile path
    ed.Modified = False
    fileName = path
    UpdateTitle
    sb.Text = "Opened " & path
    Exit Sub
Failed:
    MsgBox "Can't open " & path & vbLf & Err.Description, vbExclamation, APPNAME
End Sub

' Save the text; askName True (Save as...) or no file name yet: ask for one first.
' Returns True if it was saved.
Private Function SaveFile(ByVal askName As Boolean) As Boolean
    If askName Or fileName = "" Then
        dlg.DialogTitle = "Save the note as"
        dlg.FileName = fileName
        dlg.Flags = cdlOFNOverwritePrompt       ' ask before replacing a file
        dlg.ShowSave
        If dlg.Cancelled Then Exit Function
        fileName = dlg.FileName
    End If
    On Error GoTo Failed
    ed.SaveFile fileName
    ed.Modified = False
    UpdateTitle
    sb.Text = "Saved " & fileName
    SaveFile = True
    Exit Function
Failed:
    MsgBox "Can't save " & fileName & vbLf & Err.Description, vbExclamation, APPNAME
End Function

Private Sub UpdateTitle()
    If fileName = "" Then Me.Caption = APPNAME & " - (untitled)" Else Me.Caption = APPNAME & " - " & fileName
End Sub

' --- the Project menu (the toolbar's tools call these through menu=) ---------------------

Private Sub mnuNew_Click()
    If Not ConfirmDiscard() Then Exit Sub
    ed.Text = ""
    ed.Modified = False
    fileName = ""
    UpdateTitle
    sb.Text = "New note"
End Sub

Private Sub mnuOpen_Click()
    If Not ConfirmDiscard() Then Exit Sub
    dlg.DialogTitle = "Open a note"
    dlg.Flags = cdlOFNFileMustExist
    dlg.ShowOpen
    If Not dlg.Cancelled Then LoadFile dlg.FileName
End Sub

Private Sub mnuSave_Click()
    SaveFile False
End Sub

Private Sub mnuSaveAs_Click()
    SaveFile True
End Sub

Private Sub mnuAbout_Click()
    MsgBox APPNAME & " 1.0" & vbLf & "A small text editor written in Boing BASIC.", vbInformation, "About " & APPNAME
End Sub

Private Sub mnuQuit_Click()
    Unload Me                     ' Form_QueryUnload asks about unsaved changes first
End Sub

' --- the Edit menu ---------------------------------------------------------------------------

Private Sub mnuUndo_Click(): ed.Undo: End Sub
Private Sub mnuCut_Click(): ed.Cut: End Sub
Private Sub mnuCopy_Click(): ed.Copy: End Sub
Private Sub mnuPaste_Click(): ed.Paste: End Sub
Private Sub mnuSelAll_Click(): ed.SelectAll: End Sub

Private Sub mnuFind_Click()
    ' the selected text (if any) is what to look for
    If ed.SelText <> "" Then finder.what.Text = ed.SelText
    finder.Show                   ' a second window; both stay usable
    finder.what.SetFocus
End Sub

' --- the Settings menu ---------------------------------------------------------------------
' Checkable items: when Click runs, Checked is already the new state.

Private Sub mnuFixed_Click()
    ed.FixedFont = mnuFixed.Checked
End Sub

Private Sub mnuReopen_Click()
    sb.Text = IIf(mnuReopen.Checked, "The last note will open at start", "Notes will start empty")
End Sub

' --- the editor -------------------------------------------------------------------------------

Private Sub ed_CursorMove()
    sb.Panel(1) = "Ln " & (ed.CurrentLine + 1) & ", Col " & (ed.CurrentColumn + 1)
End Sub

Private Sub ed_Change()
    If ed.Modified And sb.Text <> "Modified" Then sb.Text = "Modified"
End Sub
