Function Sum(values() As Long) As Long
    Dim i As Long
    For i = LBound(values) To UBound(values)
        Sum = Sum + values(i)
    Next
End Function

Sub Grow(values() As Long, ByVal extra As Long)
    ReDim Preserve values(UBound(values) + extra)
End Sub

Dim fixed(1 To 3) As Long, dyn() As Long
fixed(1) = 10: fixed(2) = 20: fixed(3) = 30
Print Sum(fixed)
ReDim dyn(1)
Grow dyn, 4
Print UBound(dyn)
