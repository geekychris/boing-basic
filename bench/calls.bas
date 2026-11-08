' Sub and Function calls: ByVal, ByRef
Function AddV(ByVal a As Long, ByVal b As Long) As Long
    AddV = a + b
End Function
Sub IncR(x As Long, ByVal d As Long)
    x = x + d
End Sub
Function Twice(ByVal d As Double) As Double
    Twice = d * 2
End Function
Dim i As Long, s As Long, n As Long, d As Double
n = Val(Command$): If n = 0 Then n = 1
For i = 1 To 5000000 * n
    s = AddV(s, i) And &HFFFFFF
    IncR s, 3
    d = Twice(d + 1) / 2
Next
Print s; Format(d, "0")
