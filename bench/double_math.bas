' Double arithmetic: a series and a polynomial
Dim i As Long, n As Long, x As Double, s As Double, p As Double
n = Val(Command$): If n = 0 Then n = 1
For i = 1 To 10000000 * n
    x = i * 0.000001
    s = s + 1 / (x + 1)
    p = ((x * 1.5 - 2.25) * x + 0.75) * x - 0.125
    s = s + p * 0.001
Next
Print Format(s, "0.000000")
