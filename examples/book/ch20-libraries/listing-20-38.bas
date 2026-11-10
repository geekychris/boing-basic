Option Explicit
Dim sb As StringBuilder, n As Long
Set sb = CreateObject("StringBuilder")
sb.Append "Boing", " ", 2026, " ", True
Print sb
sb.Insert 1, ">> "
Print sb
sb.Remove 1, 3
n = sb.Replace(" ", "_")
Print sb; " ("; n; "replaced)"
sb.Char(1) = "b"
Print sb.Char(1), sb.Length
sb.Length = 5
Print "[" & sb & "]"
sb.Length = 8
Print "[" & sb & "]"
sb.Clear
sb.Append("a").Append("b").AppendLine("c")
Print HexEncode(sb.ToString)
