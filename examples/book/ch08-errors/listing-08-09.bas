Const ERR_EMPTY_NAME = vbObjectError + 1

Sub SetName(ByVal s As String)
    If Len(s) = 0 Then Err.Raise ERR_EMPTY_NAME, "SetName", "the name must not be empty"
    Print "name set to "; s
End Sub

Sub Main()
    On Error GoTo h
    SetName "Ada"
    SetName ""
    Exit Sub
h:
    Print "error"; Err.Number - vbObjectError; "from "; Err.Source; ": "; Err.Description
End Sub
