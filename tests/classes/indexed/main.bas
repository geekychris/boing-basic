Dim a As New Matrix, b As New Matrix, c As Matrix
a.Init 2, 2: b.Init 2, 2
a.Cell(1, 1) = 1: a.Cell(1, 2) = 2: a.Cell(2, 1) = 3: a.Cell(2, 2) = 4
b.Cell(1, 1) = 5: b.Cell(1, 2) = 6: b.Cell(2, 1) = 7: b.Cell(2, 2) = 8
Set c = a.Times(b)
Print c.Cell(1, 1); c.Cell(1, 2); c.Cell(2, 1); c.Cell(2, 2)
Dim l As New StrList
l.Add "x": l.Add "y"
l.Item(1) = "Y"
Print l.Item(0); l.Item(1); l.Count
Dim v As Variant
Set v = l
Print v(0); v.Item(1); v.Count
v(0) = "changed"
Print l.Item(0)
Dim o As Object
Set o = a
o.Cell(1, 1) = 10
Print a.Cell(1, 1); o.Cell(2, 2)
