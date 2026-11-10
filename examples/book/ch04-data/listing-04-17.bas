Dim v As Variant
Print IsEmpty(v); v + 1; "[" & v & "]"
v = Null
Print IsNull(v); IsNull(v + 1); "[" & v & "]"
