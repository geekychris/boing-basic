Type Box
    W As Long
    H As Long
End Type
Dim b As Box
With b
    .W = 3
    .H = 4
    Print .W * .H
End With
