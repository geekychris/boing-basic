Dim v As Variant, parts As Variant
v = Array(10, "two", 3.5)
Print v(1); LBound(v); UBound(v); IsArray(v)
Print TypeName(v)
parts = Split("red,green,blue", ",")
Print parts(2); UBound(parts)
