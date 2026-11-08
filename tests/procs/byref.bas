' ByRef scalar arguments passed as references by the fast call path
Sub Bump(x As Long, ByVal d As Long)
    x = x + d
End Sub
Sub Twice2(a As Long, b As Long)
    a = a * 2
    b = b + a
End Sub
Sub Pass(y As Long)
    Bump y, 100
End Sub
Sub SwapD(p As Double, q As Double)
    Dim t As Double
    t = p: p = q: q = t
End Sub
Function IncI(k As Integer) As Integer
    k = k + 1
    IncI = k * 2
End Function
Sub Shrink(s As Single)
    s = s / 3
End Sub
Dim i As Long, n As Long, m As Long, a As Double, b As Double, k As Integer, f As Single
For i = 1 To 1000
    Bump n, i
Next
Print n
m = 3: Twice2 m, m
Print m
n = 1: Pass n: Pass n
Print n
a = 1.5: b = -2: SwapD a, b
Print a; b
k = 5: Print IncI(k); k
Bump (n), 5
Print n
f = 10: Shrink f
Print f
On Error Resume Next
k = 32766
For i = 1 To 5
    m = IncI(k)
Next
Print "ovf"; Err.Number; k
