DefInt I-K
DefLng L, N-O
DefDbl D
DefStr S
DefBool B
Dim i, l, d, s, b, v, n
Function Half(dd)
    Half = dd / 2
End Function
Function Count(nn, kk)
    Count = nn + kk
End Function
i = 7.6: l = 100000: d = 1 / 3: s = 42: b = 5
v = "variant"
Print i; l; d; s; b; v
Print TypeName(i); " "; TypeName(l); " "; TypeName(d); " "; TypeName(s); " "; TypeName(b); " "; TypeName(v); " "; TypeName(n)
Print TypeName(Half(3)); Half(3); " "; TypeName(Count(1, 2)); Count(1, 2)
On Error Resume Next
jj = 40000
Print "implicit"; Err.Number; TypeName(jj)
kk = 3.5: Print kk
