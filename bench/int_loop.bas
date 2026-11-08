' Integer and Long arithmetic in nested loops
Dim s As Long, i As Long, j As Integer, k As Integer, n As Long
n = Val(Command$): If n = 0 Then n = 1
For i = 1 To 200000 * n
    For j = 1 To 100
        k = (j * 3 + 7) \ 2
        s = (s + k Mod 13 + i) And &HFFFFF
    Next
Next
Print s
