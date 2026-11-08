' String concatenation and functions
Dim i As Long, n As Long, s As String, t As String, c As Long
n = Val(Command$): If n = 0 Then n = 1
For i = 1 To 1000000 * n
    s = s & Chr$(65 + i Mod 26)
    If Len(s) > 200 Then s = Mid$(s, 101)
    t = Left$(s, 10) & Right$(s, 5)
    c = c + InStr(s, "XYZ") + Len(t)
    If Len(s) > 3 Then c = c + Asc(Mid$(s, 3, 1))
Next
Print c
