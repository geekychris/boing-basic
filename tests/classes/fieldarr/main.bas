Dim g As New Grid, h As Grid, i As Long
g.Fill 5
Print g.Total
Set h = New Grid
h.Fill 1000
Print g.Total; h.Total
g.Grow 10: g.Grow 20
Print g.DynSum
g.Mat
Print g.MatAt(3, 2); g.MatAt(4, 5)
g.CellWork
Print g.CellInfo
On Error Resume Next
g.Poke 100, 1
Print "subscript"; Err.Number
Err.Clear
g.Poke 99, 1
Print g.Total; Err.Number
