Function LoadSettings(ByVal path As String) As String
    Dim f As Integer
    On Error GoTo failed
    f = FreeFile
    Open path For Input As #f
    Line Input #f, LoadSettings
    Close #f
    Exit Function
failed:
    Err.Raise Err.Number, "LoadSettings", "cannot read " & path & ": " & Err.Description
End Function

Sub Main()
    On Error GoTo h
    Print LoadSettings("no-such-settings.txt")
    Exit Sub
h:
    Print "Main caught"; Err.Number; " "; Err.Source
    Print Err.Description
End Sub
