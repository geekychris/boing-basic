Sub Squares()
    Dim v As Integer
    v = 4
    GoSub ShowSquare
    v = 5
    GoSub ShowSquare
    Exit Sub
ShowSquare:
    Print v; "squared is"; v * v
    Return
End Sub

Squares
