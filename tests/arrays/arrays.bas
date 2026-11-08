Dim a(5) As Integer, i As Integer
For i = 0 To 5: a(i) = i * i: Next
Print LBound(a); UBound(a); a(3); a(5)
Dim b(1 To 3, 1 To 2) As String
b(1, 1) = "x": b(3, 2) = "y"
Print UBound(b, 1); UBound(b, 2); b(1, 1); b(3, 2); "["; b(2, 2); "]"
Dim d() As Long
ReDim d(2)
d(0) = 10: d(1) = 20: d(2) = 30
ReDim Preserve d(4)
d(4) = 50
For i = 0 To 4: Print d(i);: Next: Print
ReDim d(1)
Print d(0); UBound(d)
Dim e() As Long
e = d
e(0) = 99
Print d(0); e(0)
Dim v As Variant
v = Array(1, "two", 3.5)
Print UBound(v); v(1); TypeName(v); IsArray(v)
v(1) = "zwei"
Print v(1)
Erase a
Print a(3)
Dim s() As String
s = Split("a b c")
Print Join(s, "-")
Function SumArr(arr() As Integer) As Long
    Dim k As Integer
    For k = LBound(arr) To UBound(arr)
        SumArr = SumArr + arr(k)
    Next
End Function
Sub Fill(arr() As Integer, ByVal n As Integer)
    ReDim arr(1 To n)
    Dim k As Integer
    For k = 1 To n: arr(k) = k: Next
End Sub
Dim f() As Integer
Fill f, 4
Print SumArr(f); LBound(f); UBound(f)
Dim g(2, 2) As Double
g(1, 1) = 1.5
g(2, 2) = g(1, 1) * 2
Print g(2, 2)
Dim w As Variant
w = f
w(1) = 100
Print f(1); w(1)
Dim cnt As Integer
For Each x In f
    cnt = cnt + x
Next
Print cnt
