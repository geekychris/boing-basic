Dim gCount As Integer
Type Pt
    X As Long
End Type
Sub Bump(v As Variant)
    v = v + 1
End Sub
Sub SetS(v)
    v = v & "!"
End Sub
Function Inc(v) As Long
    v = v + 10
    Inc = v
End Function
Function Name$(v)
    v = UCase$(v)
    Name$ = "<" & v & ">"
End Function
Sub BadType(v)
    v = "abc"
End Sub
Sub Main()
    Dim n As Long, s As String, d As Double, a(2) As Integer, b As Byte, f As Boolean
    Dim c As Currency, dt As Date, p As Pt, o As New Acc, k As Long, vv As Variant
    n = 5: s = "hi": d = 1.5: a(1) = 7: b = 200: c = 2.5: dt = #1/2/2026#
    Bump n: Bump d: Bump a(1): Bump b: Bump c: Bump dt: Bump gCount
    SetS s
    Print n; d; a(1); b; c; dt; gCount; s
    p.X = 1: Bump p.X: Print "udt field"; p.X
    k = Inc(n) + 1: Print "in expr"; k; n
    If Inc(n) > 20 Then Print "if"; n
    Do While Inc(n) < 60: Loop: Print "loop"; n
    Print Name$(s); s
    o.Take n: Print "method"; o.Total; n
    n = 4: Print o.Twice(n); n
    Bump (n): Print "paren byval"; n
    vv = 1: Bump vv: Print "variant"; vv
    On Error Resume Next
    BadType n
    Print "mismatch"; Err.Number; n
End Sub
