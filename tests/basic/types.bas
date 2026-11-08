Option Explicit
Dim i As Integer, l As Long, s As Single, d As Double, c As Currency
Dim b As Boolean, y As Byte, st As String, v As Variant, dt As Date
Dim n%, m&, x!, z#, k$, cc@
Print i; l; s; d; c; b; y; "["; st; "]"; v
Print TypeName(i); " "; TypeName(l); " "; TypeName(s); " "; TypeName(d); " "; TypeName(c)
Print TypeName(b); " "; TypeName(y); " "; TypeName(st); " "; TypeName(v); " "; TypeName(dt)
Print TypeName(n); " "; TypeName(m); " "; TypeName(x); " "; TypeName(z); " "; TypeName(k); " "; TypeName(cc)
Print VarType(i); VarType(l); VarType(s); VarType(d); VarType(c); VarType(b); VarType(y); VarType(st); VarType(v)
v = 5
Print TypeName(v); VarType(v)
v = "text"
Print TypeName(v); VarType(v)
v = 2.5
Print TypeName(v)
v = Null
Print TypeName(v); IsNull(v)
v = Empty
Print IsEmpty(v)
y = 255
Print y
c = 1.23456
Print c
c = 10 / 3
Print c
b = 5
Print b
i = True
Print i
Const PI = 3.14159
Const NAME As String = "Boing"
Print PI; NAME
