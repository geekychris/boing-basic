Sub Main()
    Dim d As New Dictionary, sb As StringBuilder
    d("a") = 1: d("b") = 2
    Set sb = New StringBuilder
    sb.Append "x": sb.Append "y"
    Print d.Count; d("b"); sb.ToString(); TypeName(d); TypeName(sb)
    Print dictionary.Helper(); stringbuilder.Twice(4)
End Sub
