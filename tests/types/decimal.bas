Dim a, b, c
a = CDec("0.1"): b = CDec("0.2")
Print a + b; a + b = CDec("0.3"); TypeName(a + b); VarType(a)
Print CDec(1) / CDec(3)
Print CDec(2) / CDec(3)
Print CDec(1) / 4
Print CDec("79228162514264337593543950335")
Print CDec("-79228162514264337593543950335") + 0
c = CDec("12345678901234567890.123456789")
Print c * 10; c / 7
Print CDec(1.1) * 3; 1.1 * 3
Print CDec("1.50"); CDec(0.5) * 2; CDec("2.675") * 1
Print Fix(CDec("-2.7")); Int(CDec("-2.7")); Abs(CDec("-3.25")); Sgn(CDec("-0.1"))
Print CDec(10) - CDec("0.0000000001")
Print CLng(CDec("2.5")); CLng(CDec("3.5")); CDbl(CDec("1.25"))
Print CDec(5) > 4.9; CDec("0.1") = 0.1; CDec(3) < CDec("3.0000000000000000000000000001")
Print CStr(CDec("-0.000123")); Str(CDec("42.5"))
Print CDec(1) / CDec("7")
On Error Resume Next
c = CDec("79228162514264337593543950335") + 1
Print "ovf"; Err.Number
Err.Clear
c = CDec(1) / CDec(0)
Print "div0"; Err.Number
Err.Clear
c = CDec("abc")
Print "mismatch"; Err.Number
