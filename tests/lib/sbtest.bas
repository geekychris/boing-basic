' sbtest.bas - Boing.StringBuilder
Option Explicit
Dim sb As StringBuilder, s As String, i As Long, n As Long, t As Single

Set sb = CreateObject("StringBuilder")
Print TypeName(sb), sb.Length, "[" & sb.ToString & "]"
sb.Append "Hello"
sb.Append ", ", "Boing", "!"
Print sb.ToString, sb.Length, sb                 ' ToString is the default member
sb.AppendLine
sb.AppendLine "second line"
Print Replace(sb.ToString, vbLf, "|")
sb.Clear
sb.Append("a").Append("b").Append("c")           ' chained
Print sb.ToString
sb.Insert 1, ">>"
sb.Insert sb.Length + 1, "<<"
sb.Insert 4, "-"
Print sb.ToString
sb.Remove 1, 2
Print sb.ToString
sb.Clear
sb.Append "one two one three one"
n = sb.Replace("one", "1")
Print n, sb.ToString
n = sb.Replace("1", "eleven")
Print n, sb.ToString
Print sb.Char(1), sb.Char(sb.Length)
sb.Char(1) = "E"
Print sb.ToString
sb.Length = 6
Print "[" & sb.ToString & "]"
sb.Length = 9
Print "[" & sb.ToString & "]"
sb.Append 42: sb.Append 1.5: sb.Append True
Print sb.ToString
' binary safe
sb.Clear
sb.Append Chr(0) & "x" & Chr(0)
Print sb.Length, Asc(sb.Char(2))
' big: 100000 pieces
sb.Clear
For i = 1 To 100000: sb.Append "x": Next
Print sb.Length, sb.Capacity >= 100000
s = sb.ToString
Print Len(s), Left(s, 3)
' errors
On Error Resume Next
sb.Insert 0, "x"
Print Err.Number
Err.Clear
sb.Remove 1, 999999
Print Err.Number
Err.Clear
sb.Replace "", "x"
Print Err.Number
Err.Clear
Print sb.Char(0)
Print Err.Number
