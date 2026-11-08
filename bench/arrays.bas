' Fixed and dynamic arrays, 1-D and 2-D
Dim a(1000) As Long, d() As Long, m(99, 99) As Double, i As Long, j As Long, r As Long, n As Long, s As Double
n = Val(Command$): If n = 0 Then n = 1
ReDim d(1000)
For r = 1 To 20000 * n
    For i = 1 To 1000
        a(i) = a(i - 1) + i
        d(i) = a(i) - d(i - 1)
    Next
Next
For r = 1 To 200 * n
    For i = 0 To 99
        For j = 0 To 99
            m(i, j) = m(i, j) + i * j
            s = s + m(j, i)
        Next
    Next
Next
Print a(1000) + d(999); Format(s, "0")
