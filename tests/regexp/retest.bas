' RegExp: syntax, options, Execute/Matches/SubMatches, Replace, Split, errors (docs/regexp.md)
Option Explicit
Dim re As RegExp, m, ms, s As String, i As Long, parts

Function T(pat As String, text As String) As String
    Dim r As RegExp
    Set r = CreateObject("RegExp")
    r.Pattern = pat
    If r.Test(text) Then T = "[" & r.FirstMatch(text) & "]" Else T = "-"
End Function

Set re = CreateObject("RegExp")
' literals, classes, anchors
Print T("abc", "xxabcxx"); T("a.c", "a-c"); T("a.c", "a" & vbLf & "c"); T("^ab", "cab"); T("ab$", "cab")
Print T("[a-c]+", "xxbcaz"); T("[^a-c]+", "abcxyzabc"); T("[]a]+", "x]a]y"); T("[a-]+", "z-a-z"); T("\d+", "ab123c")
Print T("\w+", "  hi_9 "); T("\s+", "a" & vbTab & " b"); T("\D+", "12ab34"); T("[\d.]+", "v1.25!"); T("\bcat\b", "concat cat")
Print T("\Bcat", "concat"); T("a\.b", "axb a.b"); T("\x41\x42", "zAB"); T("\t", "a" & vbTab); T("[\\]", "a\b")
' quantifiers
Print T("ab*c", "ac"); T("ab+c", "ac"); T("ab?c", "abc"); T("a{3}", "aaaa"); T("a{2,}", "aaaaa"); T("a{1,2}", "aaa")
Print T("<.+>", "<a><b>"); T("<.+?>", "<a><b>"); T("a*?b", "aaab"); T("x{0}y", "xy"); T("(ab){2}", "abababx")
Print T("a{,2}", "a{,2}"); T("{x}", "a{x}"); T("a{2,3}?", "aaaa")
' groups, alternation, backreferences, lookahead
Print T("cat|dog", "hotdog"); T("(a|ab)(c|bcd)", "abcd"); T("(\w)\1", "abccd"); T("(?:ab)+", "ababx")
Print T("\w+(?=!)", "hi there!"); T("\b\w+\b(?!,)", "one, two"); T("(a*)*b", "aaab"); T("(a|b)*c", "ababc")
Print T("^(\d{3})-(\d{4})$", "555-1234"); T("(x)?y\1z", "yz")
' IgnoreCase, MultiLine
re.Pattern = "hello"
Print re.Test("HeLLo"); : re.IgnoreCase = True: Print re.Test("HeLLo"); re.IgnoreCase
re.Pattern = "[a-c]+": Print re.FirstMatch("xxABCaz"); " ";
re.Pattern = "(o)\1": Print re.FirstMatch("fOo"); " ";
re.Pattern = Chr(196) & Chr(214): Print re.Test(Chr(228) & Chr(246)); re.Test(Chr(196) & Chr(246))
re.IgnoreCase = False
re.Pattern = "^\w+$"
s = "one" & vbLf & "two" & vbLf & "three"
re.Global = True
Print re.Execute(s).Count;
re.MultiLine = True
Print re.Execute(s).Count; re.Replace(s, "<$&>") = "<one>" & vbLf & "<two>" & vbLf & "<three>"
re.MultiLine = False
' Execute: Matches, Match, SubMatches
re.Pattern = "(\w+)@(\w+)\.(com|org)"
s = "mail ann@boing.com, bob@amiga.org or x@y.net"
Set ms = re.Execute(s)
Print "matches:"; ms.Count; TypeName(ms)
For Each m In ms
    Print m.Value; m.FirstIndex; m.Length; " user="; m.SubMatches(0); " host="; m.SubMatches(1); " n="; m.SubMatches.Count; " "; TypeName(m)
Next
Print ms(1).Value; " "; ms.Item(0); " "; ms(0).SubMatchIndex(1)
For Each m In ms(0).SubMatches: Print m; ",";: Next: Print
re.Global = False
Print re.Execute(s).Count
re.Pattern = "(a)|(b)"
Set m = re.Execute("b")(0)
Print IsEmpty(m.SubMatches(0)); m.SubMatches(1); m.SubMatchIndex(0)
' Replace
re.Global = True
re.Pattern = "(\w+)@(\w+)"
Print re.Replace("ann@boing bob@amiga", "$2:$1")
Print re.Replace("ann@boing", "[$$][$&][$`][$'][$3][$0]")
re.Global = False: re.Pattern = "\d"
Print re.Replace("a1b2c3", "#")
re.Global = True: re.Pattern = "\d"
Print re.Replace("a1b2c3", "#")
re.Pattern = "x*"
Print re.Replace("abc", "-")
re.Pattern = "^"
Print re.Replace("line", "> ")
re.Pattern = "\s+$"
Print "["; re.Replace("trim me   ", ""); "]"
' Split, Escape
re.Pattern = "\s*[,;]\s*"
parts = re.Split("a, b;c ,d")
Print UBound(parts); Join(parts, "|")
re.Pattern = "(-)"
Print Join(re.Split("1-2-3"), "|")
re.Pattern = "x*"
Print Join(re.Split("abc"), "|")
Print re.Escape("1+1=2? (yes) [a] $5.00 a/b-c")
re.Pattern = re.Escape("1+1=2?"): Print re.Test("is 1+1=2?"); re.Test("11=2")
' binary data and big input
re.Pattern = "\x00+"
Print Len(re.Replace("a" & String(5, Chr(0)) & "b", "0"))
s = String(100000, "a") & "needle" & String(100000, "b")
re.Pattern = "n(e+)dle"
Set m = re.Execute(s)(0)
Print m.FirstIndex; m.SubMatches(0)
re.Pattern = "a+$"
Print re.Test(String(2000, "a") & "b")
' errors
On Error Resume Next
Dim bad
bad = Array("(", "a)", "[a", "*a", "a{3,2}", "\", "(?<x>a)", "\2(a)", "x**")
For i = 0 To UBound(bad)
    re.Pattern = bad(i)
    re.Test "x"
    Print bad(i); " -> "; Err.Number; " "; Err.Description
    Err.Clear
Next
re.Pattern = "(a*)*$"
re.Test String(30, "a") & "!"
Print "backtracking:"; Err.Number
Err.Clear
re.Pattern = "(x+x+)+y"
re.Test String(40, "x")
Print "catastrophic:"; Err.Number; " "; Err.Description
Err.Clear
re.Pattern = "b": Set ms = re.Execute("abc"): Set m = ms(5)
Print "index:"; Err.Number; ms.Count
Err.Clear
ms.Count = 3
Print "read-only:"; Err.Number
