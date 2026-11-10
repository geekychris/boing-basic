' hello.bas - the code-behind of hello.afg
Option Explicit

Private Sub Form_Load()
    answer.Caption = "Type a name and press Greet"
End Sub

Private Sub greet_Click()
    answer.Caption = "Hello, " & who.Text & "!"
End Sub

Private Sub who_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then greet_Click     ' Return in the text field
End Sub

Private Sub quit_Click()
    Unload Me
End Sub
