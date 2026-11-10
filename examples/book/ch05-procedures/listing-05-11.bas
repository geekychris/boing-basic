Private mVolume As Integer

Property Get Volume() As Integer
    Volume = mVolume
End Property

Property Let Volume(ByVal v As Integer)
    If v < 0 Then v = 0
    If v > 64 Then v = 64          ' keep it in range
    mVolume = v
End Property

Property Get Cell(ByVal row As Long, ByVal col As Long) As Long
    Cell = row * 10 + col
End Property

Volume = 100
Print Volume
Volume = Volume - 70
Print Volume
Print Cell(2, 3)
