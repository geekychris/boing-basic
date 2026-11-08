Public Sub Inc(x As Long)
    x = x + 1
End Sub
Public Sub IncV(ByVal x As Long)
    x = x + 1
End Sub
Public Sub SetS(s As String)
    s = s & "!"
End Sub
Public Sub Swap(a As Variant, b As Variant)
    Dim t As Variant
    t = a: a = b: b = t
End Sub
Public Sub Dbl(d As Double)
    d = d * 2
End Sub
Public Sub MakeNew(o As Object)
    Set o = New Collection
    o.Add 42
End Sub
Public Function AddTo(total As Long, ByVal n As Long) As Long
    total = total + n
    AddTo = total
End Function
