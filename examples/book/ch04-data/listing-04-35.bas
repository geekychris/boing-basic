Type Point
    X As Long
    Y As Long
End Type

Function MakePoint(ByVal x As Long, ByVal y As Long) As Point
    MakePoint.X = x
    MakePoint.Y = y
End Function

Dim a As Point, b As Point, path() As Point, i As Integer
a = MakePoint(3, 4)
b = a                   ' a copy
b.X = 99
Print a.X; b.X
ReDim path(1 To 3)
For i = 1 To 3
    path(i) = MakePoint(i, i * i)
Next
Print path(3).X; path(3).Y
