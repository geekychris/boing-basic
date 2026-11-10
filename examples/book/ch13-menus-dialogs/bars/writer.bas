' writer.bas
Option Explicit

Private Sub Form_Load()
    findText.Visible = False
    sb.Text = "Ready: " & tb.ButtonCount & " tools"
End Sub

' the tools with menu= call these too, and follow their Enabled
Private Sub mnuNew_Click()
    ed.Text = ""
    ed.Modified = False
    mnuSave.Enabled = False             ' also greys out tbSave
    sb.Text = "New text"
End Sub

Private Sub mnuOpen_Click()
    sb.Text = "Open: see chapter 13's CommonDialog"
End Sub

Private Sub mnuSave_Click()
    ed.Modified = False
    mnuSave.Enabled = False
    sb.Text = "Saved"
End Sub

Private Sub mnuQuit_Click()
    Unload Me
End Sub

Private Sub tbFind_Click()              ' a toggle tool has its own Click; Value is 0 or 1
    findText.Visible = tbFind.Value = 1
    If tbFind.Value = 1 Then findText.SetFocus: sb.Panel(2) = "Find" Else sb.Panel(2) = ""
End Sub

Private Sub findText_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then
        If Not ed.Find(findText.Text) Then sb.Text = "Not found"
    End If
End Sub

Private Sub ed_Change()
    If ed.Modified And Not mnuSave.Enabled Then
        mnuSave.Enabled = True
        sb.Text = "Changed"
    End If
End Sub

Private Sub ed_CursorMove()
    sb.Panel(1) = "Ln " & (ed.CurrentLine + 1)
End Sub
