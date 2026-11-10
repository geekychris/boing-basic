Option Explicit
Dim sb As StringBuilder, n As Long
Set sb = CreateObject("StringBuilder")
sb.Append "Amiga"
On Error Resume Next
sb.Insert 0, "x"
Print Err.Number; Err.Description
Err.Clear
sb.Remove 3, 10
Print Err.Number; Err.Description
Err.Clear
n = sb.Replace("", "x")
Print Err.Number; Err.Description
