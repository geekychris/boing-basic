Sub Main()
    On Error Resume Next
    Kill "no-such-file.tmp"          ' fine if it is not there
    Print "after Kill:"; Err.Number
    Err.Clear
    On Error GoTo 0
    Print "errors stop the program again from here"
End Sub
