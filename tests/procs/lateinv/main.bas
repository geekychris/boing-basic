' late-bound calls into BASIC class methods (inline frames in the VM)
Sub Main()
    Dim o As Object, v As Variant, n As Long, s As String, a() As Long, i As Long, w As Variant
    Set o = New P
    Print o.Add(1); o.Add(2, 3); o.Add("4"); o.Total
    n = 5
    Print o.Twice(n); n
    w = "ab"
    Print o.TwiceV(w); w
    v = 7
    Print o.Twice(v); v
    Print o.Str2(12, "2.5")
    Print o.Fact(6)
    For i = 1 To 4: o.Item(i) = i * i: Next
    Print o.Item(3); o(2)
    a = o.State()
    Print UBound(a); a(4)
    Print o.Opt(); o.Opt(5)
    o.Bump
    Print o.Total
    Print o.Self().Add(0, 0)
    Print o.Handled(0); o.Handled(4)
    On Error Resume Next
    n = o.Fails(0)
    Print "caught"; Err.Number
    Err.Clear
    n = o.Add("x")
    Print "mismatch"; Err.Number
    Err.Clear
    n = o.NoSuch(1)
    Print "nomember"; Err.Number
    Err.Clear
    n = o.Add(1, 2, 3)
    Print "toomany"; Err.Number
    Err.Clear
    On Error GoTo 0
    ' many calls: the frame stack must stay balanced
    n = 0
    For i = 1 To 20000
        n = o.Add(i, -i) Mod 1000
    Next
    Print n; o.Total
    Call Deep(o, 50)
    Print "done"
End Sub

Sub Deep(ByVal o As Object, ByVal k As Long)
    If k = 0 Then Exit Sub
    If o.Add(0, 0) < 0 Then Print "?"
    Deep o, k - 1
End Sub
