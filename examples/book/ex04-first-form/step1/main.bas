' main.bas - the code behind main.afg.
Option Explicit

Private clicks As Long

Private Sub hello_Click()
    clicks = clicks + 1
    message.Caption = "Hello, Amiga! (" & clicks & ")"
End Sub
