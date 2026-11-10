Dim v As Variant, n As Long, a(1 To 5) As String
Print IsEmpty(v); IsNumeric("12.5"); IsNumeric("12 apples"); IsNumeric("")
Print TypeName(v); " "; TypeName(n); " "; TypeName(a); " "; TypeName(Array(1, 2)); " "; TypeName(Nothing)
v = "text"
Print TypeName(v); VarType(v); IsArray(a); LBound(a); UBound(a)
v = Null
Print IsNull(v); TypeName(v)
