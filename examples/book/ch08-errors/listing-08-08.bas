Sub Main()
    On Error GoTo first
    Err.Raise 5
    Exit Sub
first:
    Print "first"; Err.Number
    On Error GoTo -1
    Print "after -1:"; Err.Number
    On Error GoTo second
    Err.Raise 9
    Exit Sub
second:
    Print "second"; Err.Number
End Sub
