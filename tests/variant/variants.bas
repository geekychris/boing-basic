Dim a As Variant, b As Variant, c As Variant
a = 32767: b = 1
c = a + b
Print c; TypeName(c)
a = 2147483647
c = a + b
Print c; TypeName(c)
a = "10": b = 5
Print a + b; a & b; TypeName(a + b)
a = "abc": b = "def"
Print a + b
a = Null
Print IsNull(a + 1); IsNull(a & "x"); a & "x"
a = Empty
Print a + 1; "["; a & ""; "]"; a = 0; a = ""
a = 5: b = "5"
Print a = b
a = 10: b = "9"
Print a > b
a = "10": b = "9"
Print a > b
a = True
Print a + 1; TypeName(a)
a = 1.5
Print a * 2; TypeName(a * 2)
a = CByte(200): b = CByte(100)
c = a + b
Print c; TypeName(c)
Dim v As Variant
v = 3
v = v / 2
Print v; TypeName(v)
v = 7 \ 2
Print v; TypeName(v)
v = #1/2/2000#
Print v; TypeName(v); Year(v)
v = v + 1
Print v
Print VarType(Null); VarType(Empty); VarType("x"); VarType(1&)
