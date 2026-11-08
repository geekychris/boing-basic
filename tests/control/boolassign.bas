' Boolean assignments compiled as compare-and-branch (the value is computed before it is stored)
Type T
    lit As Boolean
    n As Long
End Type
Dim b As Boolean, c As Boolean, i As Long, k As Integer, ts(1 To 3) As T, cnt As Long
For i = 1 To 12
    b = i > 4 And i < 10
    c = Not b Or i = 11
    b = Not b
    If b Then cnt = cnt + 1
    ts((i Mod 3) + 1).lit = i Mod 2 = 0 Or c
    ts((i Mod 3) + 1).n = ts((i Mod 3) + 1).n - ts((i Mod 3) + 1).lit
    Print b; c; ts((i Mod 3) + 1).lit
Next
b = True: c = False
Print cnt; b; c; ts(1).n; ts(2).n; ts(3).n
Select Case cnt
Case Is > 5: Print "many"
Case 1 To 5: Print "some"
End Select
k = 7
Select Case k * 2
Case 14: Print "fourteen"
Case Else: Print "other"
End Select
