Sub ShowRatio(ByVal a As Long, ByVal b As Long)
    Dim q As Long
    On Error GoTo failed
    q = a \ b
    Print a; "/"; b; "="; q
    Exit Sub
failed:
    Print "cannot divide"; a; "by"; b; "- error"; Err.Number; Err.Description
End Sub

ShowRatio 10, 3
ShowRatio 7, 0
Print "the program goes on"
