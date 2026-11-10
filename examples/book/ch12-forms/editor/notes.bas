' notes.bas
Option Explicit

Private Sub Form_Load()
    ed.Text = "Notes" & vbLf & "Type here."
    ed.TabSize = 4
    ed.Modified = False
End Sub

Private Sub Form_Activate()
    ed.SetFocus                         ' the cursor starts in the editor
End Sub

Private Sub pick_Change()               ' a file was chosen in the requester
    LoadText pick.FileName
End Sub

Private Sub btnLoad_Click()
    If pick.FileName = "" Then pick.ShowOpen
    If pick.FileName <> "" Then LoadText pick.FileName
End Sub

Private Sub LoadText(ByVal path As String)
    On Error GoTo failed
    ed.LoadFile path
    ed.Modified = False
    status.Caption = "Loaded " & path & ", " & ed.LineCount & " lines"
    Exit Sub
failed:
    status.Caption = "Can't load " & path & ": " & Err.Description
End Sub

Private Sub btnSave_Click()
    If pick.FileName = "" Then status.Caption = "Choose a file name first": Exit Sub
    ed.SaveFile pick.FileName
    ed.Modified = False
    status.Caption = "Saved " & pick.FileName
End Sub

Private Sub ed_CursorMove()
    status.Caption = "Ln " & (ed.CurrentLine + 1) & ", Col " & (ed.CurrentColumn + 1)
End Sub

Private Sub ed_Change()
    If ed.Modified Then Me.Caption = "Notes (changed)"
End Sub

Private Sub findText_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then findNext_Click        ' Return in the Find field
End Sub

Private Sub findNext_Click()
    If findText.Text = "" Then findText.SetFocus: Exit Sub
    If Not ed.Find(findText.Text, matchCase.Value = vbChecked) Then
        ' not found below the cursor: try again from the top
        If Not ed.Find(findText.Text, matchCase.Value = vbChecked, True) Then status.Caption = "Not found"
    End If
End Sub

Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    pick.FileName = App.DropFile(0)     ' an icon dropped on the window
    LoadText pick.FileName
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If ed.Modified Then
        If MsgBox("Discard the changes?", vbYesNo + vbQuestion) = vbNo Then Cancel = True
    End If
End Sub
