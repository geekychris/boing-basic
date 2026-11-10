Public Total As Long
Public Sub Take(v As Variant)
    Total = Total + v
    v = 0
End Sub
Public Function Twice(v) As String
    v = v * 2
    Twice = "t" & v
End Function
