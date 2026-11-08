Dim g As Long
Dim o As Object, i As Long, k As Integer, s As String, v1 As Variant, v2 As Variant, d As Double, c As Object
Set o = New Ops
i = 5: o.Inc i: Print i
o.Inc (i): Print i
o.IncV i: Print i
g = 10: o.Inc g: Print g
s = "hi": o.SetS s: Print s
v1 = 1: v2 = "two": o.Swap v1, v2: Print v1; " "; v2
k = 7: o.Inc k: Print k; TypeName(k)
d = 1.5: o.Dbl d: Print d
o.MakeNew c: Print c.Count; c(1)
Print o.AddTo(i, 10); i
Dim col As New Collection
i = 1: col.Add i: i = 99: Print col(1)
