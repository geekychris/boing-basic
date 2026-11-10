Dim nums(3) As Integer, v As Variant, c As New Collection
Print TypeName(nums); VarType(nums); VarType(nums) - vbArray
v = Array(1, 2)
Print TypeName(v); VarType(v)
v = 1.5@
Print TypeName(v); VarType(v)
Print TypeName(c); VarType(c); " "; TypeName(Nothing)
Print TypeName(CByte(1)); VarType(CByte(1)); " "; TypeName(#1/1/2026#); VarType(#1/1/2026#)
