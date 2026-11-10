Dim parts() As String, i As Integer
parts = Split("red,green,,blue", ",")
Print "pieces:"; UBound(parts) + 1
For i = 0 To UBound(parts)
    Print i; "["; parts(i); "]"
Next
Print Join(parts, " / ")
parts = Split("name=Boing=Ball", "=", 2)
Print parts(0); " -> "; parts(1)
Print UBound(Split(""))
