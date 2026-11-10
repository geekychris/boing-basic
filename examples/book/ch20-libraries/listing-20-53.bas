Option Explicit
Dim table As Csv, a As Variant, r As Long, c As Long
Set table = CreateObject("Csv")
table.LoadText "a,b,c" & vbLf & "1,2" & vbLf & "x,y,z"
a = table.ReadAll()
Print UBound(a, 1) + 1; " records of"; UBound(a, 2) + 1; " fields"
For r = 0 To UBound(a, 1)
    For c = 0 To UBound(a, 2)
        Print "["; a(r, c); "]";
    Next
    Print
Next
