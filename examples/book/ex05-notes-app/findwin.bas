' findwin.bas - the code-behind of findwin.afg, the Find window of Notes.
' It works on the main form's controls through the form's name: notes.ed, notes.sb.
Option Explicit

Private Sub findNext_Click()
    Dim caseToo As Boolean
    If what.Text = "" Then Exit Sub
    caseToo = matchCase.Value = vbChecked
    ' look on from the cursor; if it isn't found, start again at the top
    If notes.ed.Find(what.Text, caseToo) Then
        notes.sb.Text = "Found " & what.Text
    ElseIf notes.ed.Find(what.Text, caseToo, True) Then
        notes.sb.Text = "Found " & what.Text & " (from the top)"
    Else
        notes.sb.Text = "Not found: " & what.Text
        Beep
    End If
End Sub

' Return in the text field is the same as Find next.
Private Sub what_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then findNext_Click
End Sub

Private Sub closeIt_Click()
    Me.Hide                       ' keep the form (and what was typed) for next time
End Sub

' The close gadget hides the window too, instead of unloading it.
Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If UnloadMode = 0 Then
        Cancel = True
        Me.Hide
    End If
End Sub
