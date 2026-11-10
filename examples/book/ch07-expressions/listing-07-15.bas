Dim v As Variant, o As Object
Print IsEmpty(v); v + 5; "[" & v & "]"
v = Null
Print IsNull(v); IsNull(v + 5); "[" & v & "]"
Print o Is Nothing
v = Empty
Print IsEmpty(v)
