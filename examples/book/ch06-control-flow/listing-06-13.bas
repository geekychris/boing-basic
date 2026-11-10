Sub Pick(ByVal n As Integer)
    On n GoTo one, two
    Print n; "no match"
    Exit Sub
one:
    Print n; "one"
    Exit Sub
two:
    Print n; "two"
End Sub

Pick 1: Pick 2: Pick 3: Pick 0
