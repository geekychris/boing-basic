Option Explicit
Dim v As Variant, grid(2, 2) As Long, d As Dictionary
On Error Resume Next
v = JsonParse("{""a"": 1,}")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("{'a': 1}")                 ' JSON strings take double quotes only
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("[1, 2] 3")
Print Err.Number; Err.Description
Err.Clear
Print JsonStringify(grid)
Print Err.Number; Err.Description
Err.Clear
Set d = CreateObject("Dictionary")
Set d("me") = d
Print JsonStringify(d)
Print Err.Number; Err.Description
