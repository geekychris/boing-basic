Dim squares(5) As Long            ' 6 elements, 0 to 5
Dim days(1 To 7) As String        ' 7 elements, 1 to 7
Dim i As Integer
For i = 0 To 5
    squares(i) = i * i
Next
days(1) = "Monday"
Print squares(4); LBound(squares); UBound(squares)
Print days(1); LBound(days); UBound(days)
