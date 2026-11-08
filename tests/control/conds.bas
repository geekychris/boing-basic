' And / Or / Not combinations of typed comparisons and Booleans in If, While and loops
Type Box
    x As Single
    ok As Boolean
    n As Long
End Type
Dim i As Long, j As Integer, d As Double, f As Boolean, cnt As Long, s As String
Dim bx(1 To 4) As Box, flags(1 To 4) As Boolean
For i = 1 To 4: bx(i).x = i * 0.75!: bx(i).ok = (i Mod 2 = 0): flags(i) = i > 2: Next
For i = -3 To 12
    j = i * 2: d = i / 4: f = i Mod 3 = 0
    s = ""
    If i < 0 Or i > 9 Then s = s & "a"
    If Not (i < 0 Or i > 9) Then s = s & "b"
    If i > 2 And j < 20 Or d = 0.5 Then s = s & "c"
    If (i > 2 Or f) And Not (j = 8) Then s = s & "d"
    If f Or i = 1 Then s = s & "e"
    If Not f And d > 1 Then s = s & "f"
    If Not Not f Then s = s & "g"
    If (i >= 1 And i <= 4) Then
        If bx(i).ok Or bx(i).x > 2 Then s = s & "h"
        If Not bx(i).ok And Not flags(i) Then s = s & "i"
        If flags(i) And (bx(i).x < 2.5! Or bx(i).n = 0) Then s = s & "j"
    End If
    If i > 0 Xor f Then s = s & "k"
    Print i; s
Next
cnt = 0: i = 0
Do While i < 100 And Not (i > 50 And i Mod 7 = 0)
    i = i + 1
Loop
Print "do"; i
i = 0
While i < 10 Or (i < 20 And i Mod 2 = 1)
    i = i + 1
Wend
Print "while"; i
Do
    i = i + 3
Loop Until i > 40 Or i = 33
Print "until"; i
