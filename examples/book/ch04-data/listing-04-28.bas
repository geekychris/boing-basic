Dim grid(1 To 3, 1 To 4) As Integer
Dim r As Integer, c As Integer
For r = 1 To 3
    For c = 1 To 4
        grid(r, c) = r * 10 + c
    Next
Next
Print grid(2, 3); UBound(grid, 1); UBound(grid, 2)
