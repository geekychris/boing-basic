' Variant arithmetic (late typing)
Dim a As Variant, b As Variant, s As Variant, i As Long, n As Long
n = Val(Command$): If n = 0 Then n = 1
s = 0
For i = 1 To 3000000 * n
    a = i
    b = a * 2 + 1
    s = s + b Mod 7
    If s > 100000 Then s = s - 100000
Next
Print s
