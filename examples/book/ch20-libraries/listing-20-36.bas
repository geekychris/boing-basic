Option Explicit
Dim sb As StringBuilder, i As Long
Set sb = CreateObject("StringBuilder")
For i = 1 To 5
    sb.Append "line "
    sb.AppendLine CStr(i)
Next
Print sb.ToString;
Print sb.Length; "characters"
