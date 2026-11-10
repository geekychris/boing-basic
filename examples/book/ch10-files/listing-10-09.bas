Function ReadFirstLine(ByVal path As String) As String
    Dim f As Integer
    On Error GoTo failed
    f = FreeFile
    Open path For Input As #f
    Line Input #f, ReadFirstLine
    Close #f
    Exit Function
failed:
    ReadFirstLine = "(cannot read " & path & ": " & Err.Description & ")"
    Close #f
End Function

Print ReadFirstLine("no-such-file.txt")
