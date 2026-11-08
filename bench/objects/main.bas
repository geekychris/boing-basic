' Early-bound and late-bound method and property calls
Dim c As New Counter, o As Object, i As Long, n As Long, s As Long
n = Val(Command$): If n = 0 Then n = 1
c.Step_ = 3
For i = 1 To 3000000 * n
    c.Bump
    c.Value = c.Value + 1
Next
Set o = c
For i = 1 To 300000 * n
    o.Bump
    s = (s + o.Value) And &HFFFFFF
Next
Print c.Value; s And &HFFFF&
