' Shl / ShrA / ShrL: 32-bit shifts of a Long; Shl wraps, counts outside 0..31 raise error 5
Dim x As Long, n As Long, i As Long, s As Long, k As Integer
Print Shl(1, 0); Shl(1, 4); Shl(3, 30); Shl(1, 31); Shl(-1, 31); Shl(&H12345678, 8)
Print ShrA(256, 4); ShrA(-256, 4); ShrA(-1, 31); ShrA(&H80000000, 31); ShrA(7, 0)
Print ShrL(256, 4); ShrL(-256, 4); ShrL(-1, 31); ShrL(&H80000000, 31); ShrL(-1, 0)
k = 3: Print Shl(k, k); ShrA(k * 100, 2)
x = 123456789
For i = 0 To 31
    s = s Xor ShrL(x, i) Xor Shl(x, i) Xor ShrA(-x, i)
Next
Print s
For i = 1 To 100000
    n = (n + ShrA(i, 3) + Shl(i And 255, 2)) And &HFFFFFF
Next
Print n
On Error Resume Next
x = Shl(1, 32): Print "e"; Err.Number: Err.Clear
x = ShrA(1, -1): Print "e"; Err.Number: Err.Clear
x = ShrL(1, 100): Print "e"; Err.Number: Err.Clear
