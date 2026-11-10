' an error raised inside a handler reaches the caller's handler with its number; On Error GoTo -1
Sub Inner()
    On Error GoTo h
    Err.Raise 5
    Exit Sub
h:
    Err.Raise 11
End Sub
Sub Main()
    On Error GoTo outer
    Inner
    Print "no"
    Exit Sub
outer:
    Print "outer"; Err.Number; Err.Description
    On Error GoTo -1
    On Error GoTo second
    Err.Raise 9
    Exit Sub
second:
    Print "second"; Err.Number
End Sub
