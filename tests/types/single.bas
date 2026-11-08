' Single arithmetic: rounding to Single after each operation, overflow, division
Type Pt
    x As Single
    y As Single
    n As Long
End Type
Function Half(ByVal v As Single) As Single
    Half = v / 2
End Function
Sub Scale(v As Single, ByVal f As Single)
    v = v * f
End Sub
Dim a As Single, b As Single, c As Single, d As Double, i As Long, k As Integer
Dim ps(1 To 3) As Pt, arr(5) As Single
a = 0.1: b = 0.2
c = a + b
Print c; c = 0.3!; CDbl(c) = 0.3
d = a * 3
Print d; a * 3
i = 16777217
c = i
Print c; CLng(c)
k = 3
c = k / 7
Print c
c = 1
For i = 1 To 30
    c = c * 0.94! + i / 1000
Next
Print c
For i = 1 To 3
    ps(i).x = i * 1.5!
    ps(i).y = ps(i).x * ps(i).x - 0.25!
    ps(i).n = ps(i).n + 1
Next
For i = 1 To 200
    k = (i Mod 3) + 1
    ps(k).x = ps(k).x * 0.99! + ps(k).y / 100
    If ps(k).x > 2.5! And ps(k).y < 3 Then ps(k).n = ps(k).n + 1
Next
Print ps(1).x; ps(2).x; ps(3).x; ps(1).n; ps(2).n; ps(3).n
For i = 0 To 5: arr(i) = Half(i * 1.1!): Next
Print arr(5); arr(3); -arr(2)
a = 3: Scale a, 1.5!
Print a; Half(a) < a; Half(-a) > -a
On Error Resume Next
a = 3E+38: a = a * 10
Print "overflow"; Err.Number; a
Err.Clear
b = 0: a = 1 / b
Print "div"; Err.Number
Err.Clear
a = 0: c = a / b
Print "0/0"; Err.Number
Err.Clear
d = 1E+300: a = d
Print "cvt"; Err.Number
