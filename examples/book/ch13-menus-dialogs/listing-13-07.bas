Option Explicit
Dim answer As Long, name As String
answer = MsgBox("Save the changes?", vbYesNoCancel + vbQuestion, "Editor")
Select Case answer
Case vbYes: Print "saving"
Case vbNo: Print "not saving"
Case vbCancel: Print "cancelled"
End Select
name = InputBox("Your name?", "Hello", "Amiga")
If name = "" Then Print "no name" Else Print "Hello, "; name
MsgBox "Done", vbInformation
