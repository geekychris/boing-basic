Option Explicit
Dim re As RegExp, m As Variant
Set re = CreateObject("RegExp")
re.Pattern = "(a)|(b)"
Set m = re.Execute("b")(0)
Print IsEmpty(m.SubMatches(0)); " ["; m.SubMatches(1); "]"; m.SubMatchIndex(0); m.SubMatchIndex(1)
