Sub Main()
    On Error GoTo outer
    Inner
    Print "not here"
    Exit Sub
outer:
    Print "outer caught"; Err.Number
End Sub
Sub Inner()
    Dim i As Long
    On Error Resume Next
    Print "running"
    Do
        i = (i + 1) Mod 1000
    Loop
End Sub
