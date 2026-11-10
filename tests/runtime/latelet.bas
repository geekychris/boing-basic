' assigning into a Variant array held by a default member: d("a")(1) = x, deeper chains, objects
Dim d As New Dictionary, c As New Collection, v
d("a") = Array(1, 2, 3)
Print d("a")(1)
d("a")(1) = 20
Print d("a")(1)
v = d("a"): Print v(1)
Dim inner As New Dictionary, m(1), r
inner("y") = 1
Set d("x") = inner
d("x")("y") = 5
Print inner("y"); d("x")("y"); TypeName(d("x"))
r = Array(10, 20)
m(0) = r: m(1) = r
d("m") = m
d("m")(1)(0) = 99
Print d("m")(1)(0); d("m")(0)(0)
