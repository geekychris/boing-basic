' Typed Int / Fix of a Double, Double -> Long / Integer rounding, MulShr and MulDiv
' (register ops in the VM and JIT, inside loops so the JIT compiles them)
Dim i As Long, x As Long, n As Integer, d As Double, s As Single, k As Long, r As Long
Dim v(1 To 12) As Double
v(1) = 2.5: v(2) = -2.5: v(3) = 3.5: v(4) = -0.5: v(5) = 0.49: v(6) = -7.999
v(7) = 1E+15 + 0.5: v(8) = -1E+15 - 0.5: v(9) = 4.6E+15: v(10) = 0: v(11) = -3: v(12) = 123456.75
For i = 1 To 12
    d = v(i)
    Print Int(d); Fix(d); Int(d * 2#); Fix(d / 3#)
Next
For i = 1 To 6
    d = v(i)
    x = d
    n = d * 3#
    Print x; n; CLng(d * 10#); Int(CDbl(i) * 54321# * 1.52587890625E-05)
Next
' typed results
d = -2.5
Print TypeName(Int(d)); TypeName(Fix(d)); TypeName(Int(i)); TypeName(Int(s)); Int(-3.7!); Fix(-3.7!)
x = 7
Print Int(x); Fix(x)
' Double -> Long / Integer overflow, in a loop
On Error Resume Next
x = 0: n = 0
d = 2147483647#
For i = 1 To 3
    x = d
    d = d + 0.25
Next
Print "long"; Err.Number; x
Err.Clear
d = 32766#
For i = 1 To 4
    n = d
    d = d + 1#
Next
Print "integer"; Err.Number; n
Err.Clear
On Error GoTo 0
' MulShr: 16.16 fixed point and the shift count
r = 0
For i = -3 To 3
    x = MulShr(i * 98304, 163840, 16)
    r = r + x
    Print x; MulShr(i * 98304, 163840, 0 + 16); MulShr(i, -5, 0); MulShr(i * 1000003, 1999999, 31)
Next
Print "sum"; r
k = 4
Print MulShr(-1, 1, 0); MulShr(-1, 1, 1); MulShr(-1, 1, 31); MulShr(-17, 1, k); MulShr(2147483647, 2147483647, 31)
' MulDiv: truncating, 64-bit product
For i = -3 To 3
    Print MulDiv(i * 98304, 65536, 163840); MulDiv(i, 7, 2); MulDiv(2147483647, 2147483644 - i, 2147483647); MulDiv(i, -2147483647, -2147483647)
Next
' errors
On Error Resume Next
x = 0
For i = 1 To 3
    x = MulShr(65536 * i, 65536, 1)
Next
Print "mulshr overflow"; Err.Number; x
Err.Clear
x = MulShr(1, 1, 32)
Print "mulshr count"; Err.Number
Err.Clear
k = -1
x = MulShr(1, 1, k)
Print "mulshr count"; Err.Number
Err.Clear
x = 0
For i = 2 To 0 Step -1
    x = x + MulDiv(10, 10, i)
Next
Print "muldiv zero"; Err.Number; x
Err.Clear
x = 0
For i = 1 To 3
    x = MulDiv(2147483647, i, 1)
Next
Print "muldiv overflow"; Err.Number; x
Err.Clear
On Error GoTo 0
' the same ops as statements (register forms, compiled by the JIT), printed afterwards
Dim fl(1 To 12) As Double, fx(1 To 12) As Double, cl(1 To 12) As Long, ci(1 To 12) As Integer
Dim ms(1 To 12) As Long, md(1 To 12) As Long
For i = 1 To 12
    d = v(i) / 1000000#
    If i >= 7 And i <= 9 Then d = v(i)
    fl(i) = Int(d)
    fx(i) = Fix(d * 3#)
    If i <= 6 Or i >= 10 Then cl(i) = d * 7# + 0.5: ci(i) = d * 2#
    ms(i) = MulShr(i * 40000 - 300000, i * 7919 - 50000, 12)
    md(i) = MulDiv(i * 400000 - 3000000, i * 7919 - 50000, i * 30000 - 200000) + MulDiv(2000000000 - i, 2000000000 + i * 3, 2000000000 + i) \ 1000
Next
For i = 1 To 12
    Print fl(i); fx(i); cl(i); ci(i); ms(i); md(i)
Next
