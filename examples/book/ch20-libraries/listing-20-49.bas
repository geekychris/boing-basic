Option Explicit
Dim re As RegExp, bad As Variant, ok As Boolean
Set re = CreateObject("RegExp")
On Error Resume Next
For Each bad In Array("(", "[a", "*a", "a{3,2}", "\2(a)")
    re.Pattern = bad
    ok = re.Test("x")
    Print bad; " -> "; Err.Number; " "; Err.Description
    Err.Clear
Next
re.Pattern = "(x+x+)+y"
ok = re.Test(String(40, "x"))
Print "(x+x+)+y -> "; Err.Number; " "; Err.Description
