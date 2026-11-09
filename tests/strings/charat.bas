' Asc(Mid$(s, i, 1)), Mid$(s, i, 1) = "x", Left$(s, 1) = "x" as byte reads; one-character strings shared
Dim s As String, i As Long, n As Long, c As Long, e As String
s = "Hello, World"
For i = 1 To Len(s)
    n = n + Asc(Mid$(s, i, 1))
    If Mid$(s, i, 1) = "o" Then c = c + 1
    If "l" <> Mid$(s, i, 1) Then c = c + 100
Next
Print n; c; Asc(Left$(s, 1)); Left$(s, 1) = "H"; Left$(e, 1) = "H"; Mid$(s, 20, 1) = ""; Mid$(s, 20, 1) = "x"
Print Mid(s, 2, 1) = "e"; Asc(Mid(s, 3, 1)); Chr$(65); Chr$(65) & Chr$(66); Left$("abc", 1); Right$("abc", 1); Mid$("abc", 2, 1)
On Error Resume Next
n = Asc(Mid$(s, 0, 1)): Print "e1"; Err.Number: Err.Clear
n = Asc(Mid$(s, 40, 1)): Print "e2"; Err.Number: Err.Clear
n = Asc(Left$(e, 1)): Print "e3"; Err.Number: Err.Clear
If Mid$(s, 0, 1) = "x" Then Print "?"
Print "e4"; Err.Number: Err.Clear
Dim t As String
t = Chr$(65)
Mid$(t, 1, 1) = "Z"
Print t; Chr$(65)
t = Left$(s, 1)
t = t & "x"
Print t; Left$(s, 1)
