' UDT field access in an array of records
Type Particle
    X As Double
    Y As Double
    VX As Double
    VY As Double
    Hits As Long
End Type
Dim p(255) As Particle, i As Long, t As Long, n As Long, h As Long
n = Val(Command$): If n = 0 Then n = 1
For i = 0 To 255
    p(i).X = i: p(i).Y = i * 0.5: p(i).VX = 1.5: p(i).VY = -0.75
Next
For t = 1 To 20000 * n
    For i = 0 To 255
        p(i).X = p(i).X + p(i).VX
        p(i).Y = p(i).Y + p(i).VY
        If p(i).X > 500 Then p(i).X = 0: p(i).Hits = p(i).Hits + 1
        If p(i).Y < 0 Then p(i).Y = 300
    Next
Next
For i = 0 To 255: h = h + p(i).Hits: Next
Print h
