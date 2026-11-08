Dim s As String
s = "Hello, World"
Print Len(s); Left(s, 5); "|"; Right(s, 5); "|"; Mid(s, 8); "|"; Mid$(s, 1, 4)
Print InStr(s, "o"); InStr(6, s, "o"); InStr(s, "xyz"); InStr(1, s, "WORLD", 1); InStrRev(s, "o")
Print LCase(s); " "; UCase$(s)
Print "["; Trim("  pad  "); "]["; LTrim("  pad  "); "]["; RTrim("  pad  "); "]"
Print "["; Space(3); "]"; String(4, "*"); String(3, 65)
Print Replace("a-b-c-d", "-", "+"); " "; Replace("aaaa", "a", "b", 1, 2); " "; Replace("Hello", "L", "x", 1, -1, vbTextCompare)
Dim parts() As String, i As Integer
parts = Split("one,two,,three", ",")
Print UBound(parts); LBound(parts)
For i = 0 To UBound(parts)
    Print "<"; parts(i); ">";
Next
Print
Print Join(parts, "|")
Print StrComp("abc", "abd"); StrComp("b", "a"); StrComp("A", "a"); StrComp("A", "a", 1)
Print StrReverse("Boing"); " "; Chr(66); Asc("A"); Chr$(97)
Print "abc" Like "a?c"; "abc" Like "a*"; "a1" Like "a#"; "b" Like "[a-c]"; "d" Like "[!a-c]"; "x" Like "[a-c]"
Mid(s, 1, 5) = "HOWDY"
Print s
Mid(s, 8) = "Amiga!!!!!"
Print s
Print "Q" & Chr(34) & "uote" & Chr(34)
Print Len(""); Len(CStr(12345))
Print Format(1234.5678, "0.00"); " "; Format(1234.5, "#,##0.00"); " "; Format(0.256, "0.0%"); " "; Format(5, "000")
Print Format(3.14159, "Fixed"); " "; Format(1234567.891, "Standard"); " "; Format(42, "Currency")
Print Format("hello", ">"); " "; Format(-5.5, "0.0;(0.0)"); " "; Format(0, "0;-0;zero")
Print Format(#1/15/2000#, "yyyy-mm-dd"); " "; Format(#3:04:05 PM#, "hh:nn:ss"); " "; Format(#12/25/1999#, "mmm d, yyyy")
Print Format(True, "Yes/No"); " "; Format(1.5E+10, "Scientific")
Dim t As String * 5
t = "ab"
Print "["; t; "]"; Len(t)
t = "abcdefgh"
Print "["; t; "]"
