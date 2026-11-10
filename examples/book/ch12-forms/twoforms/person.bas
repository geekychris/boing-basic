' person.bas - the dialog's code-behind; its Public variables are what it answers
Option Explicit

Public Accepted As Boolean
Public Answer As String

Private Sub Form_Load()
    Accepted = False
End Sub

Private Sub Form_Activate()
    nameField.SetFocus
End Sub

Private Sub nameField_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then ok_Click
End Sub

Private Sub ok_Click()
    If Trim(nameField.Text) = "" Then Beep: Exit Sub
    Answer = Trim(nameField.Text)
    Accepted = True
    Me.Hide                             ' ends Show vbModal
End Sub

Private Sub cancel_Click()
    Me.Hide
End Sub
