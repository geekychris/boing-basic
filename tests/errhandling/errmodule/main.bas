Sub Main()
    On Error Resume Next
    x = 1 / 0
    Print Err.Number; Err
    Helper
End Sub
