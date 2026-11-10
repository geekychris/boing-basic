Public Type Box
    W As Long
    H As Long
End Type

Public Function Area(b As Box) As Long
    Area = b.W * b.H
End Function

Public Function Twice(ByVal x As Long) As Long
    Twice = x * 3   ' a different Twice: qualify to pick one
End Function
