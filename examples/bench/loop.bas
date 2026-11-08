' Loop benchmark: integer arithmetic, a Double accumulator and array access
Dim i As Long, j As Long, s As Long, d As Double
Dim a(1000) As Long
Dim t As Single
t = Timer
For i = 1 To 20000
    For j = 0 To 1000
        a(j) = a(j) + i Mod 7
        s = (s + a(j)) And &HFFFF&
    Next
    d = d + i / 3
Next
Print "s ="; s; " d ="; Format(d, "0.00")
