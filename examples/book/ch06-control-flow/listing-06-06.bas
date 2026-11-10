Dim row As Integer, col As Integer
For row = 1 To 3
    For col = 1 To 4
        Print row * col;
    Next col
    Print
Next row
For row = 1 To 2
    For col = 1 To 2
        Print row * 10 + col;
Next col, row
Print
