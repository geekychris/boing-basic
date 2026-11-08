' assorted language corners
Dim i As Integer, s As String
Static Function Acc(ByVal n As Long) As Long
    Dim total As Long
    total = total + n
    Acc = total
End Function
Print Acc(1); Acc(2); Acc(3)
s = "a" & 1 & True & 2.5 & Null
Print s
Print 5 = 5.0; "abc" < "abd"; 3 > 2 > 1
Print 7 \ 2 * 2; 7 Mod 4 ^ 2; -3 ^ 2; Not 0; Not -1
Print 1 And 3; 1 Or 2; 5 Xor 1; True Imp False; False Eqv False
Print IIf(i = 0, "zero", "nonzero"); Choose(2, "a", "b", "c")
i = 32767
On Error Resume Next
i = i + 1
Print i; Err.Number
On Error GoTo 0
Dim l As Long
l = 32767
l = l + 1
Print l
Print Len(Str$(123)); Len(CStr(123))
Print Asc(LCase(Chr(196))); Asc(UCase(Chr(233))); UCase("mixed Case")
Print "a" < "B"; StrComp("a", "B", vbTextCompare)
Print Int(-0.5); Fix(-0.5); CInt(0.5); CInt(1.5)
Print Rnd(-1); Rnd; Rnd(0)
Randomize 42
Dim r As Single
r = Rnd
Print r >= 0 And r < 1
Print Hex$(&HABCD); Oct$(-1)
Print TypeName(1); TypeName(100000); TypeName(1.5); TypeName("x"); TypeName(True); TypeName(1@); TypeName(Nothing)
