' String benchmark: concatenation, Mid, InStr
Dim i As Long, s As String, n As Long, k As Long
For i = 1 To 200000
    s = s & Chr(65 + i Mod 26)
    If Len(s) > 100 Then s = Mid(s, 50)
    n = n + InStr(s, "XYZ")
Next
Print n; Len(s)
