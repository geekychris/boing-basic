Option Explicit
Dim d As Dictionary
Set d = CreateObject("Dictionary")
d("plum") = 1
On Error Resume Next
d.Add "plum", 2
Print Err.Number; Err.Description
Err.Clear
d.Remove "kiwi"
Print Err.Number; Err.Description
Err.Clear
d.CompareMode = 1
Print Err.Number; Err.Description
