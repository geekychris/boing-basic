' fannkuch-redux: permutations and pancake flips
Function Fannkuch(ByVal n As Long, checksum As Long) As Long
    Dim perm() As Long, perm1() As Long, count() As Long
    Dim maxFlips As Long, permCount As Long, r As Long, i As Long, k As Long, t As Long, flips As Long, p0 As Long, j As Long
    ReDim perm(n - 1): ReDim perm1(n - 1): ReDim count(n - 1)
    For i = 0 To n - 1: perm1(i) = i: Next
    r = n
    Do
        Do While r <> 1
            count(r - 1) = r
            r = r - 1
        Loop
        For i = 0 To n - 1: perm(i) = perm1(i): Next
        flips = 0
        k = perm(0)
        Do While k <> 0
            i = 0: j = k
            Do While i < j
                t = perm(i): perm(i) = perm(j): perm(j) = t
                i = i + 1: j = j - 1
            Loop
            flips = flips + 1
            k = perm(0)
        Loop
        If flips > maxFlips Then maxFlips = flips
        If permCount Mod 2 = 0 Then checksum = checksum + flips Else checksum = checksum - flips
        Do
            If r = n Then Fannkuch = maxFlips: Exit Function
            p0 = perm1(0)
            For i = 0 To r - 1: perm1(i) = perm1(i + 1): Next
            perm1(r) = p0
            count(r) = count(r) - 1
            If count(r) > 0 Then Exit Do
            r = r + 1
        Loop
        permCount = permCount + 1
    Loop
End Function
Dim n As Long, cs As Long, m As Long
n = Val(Command$): If n = 0 Then n = 1
m = Fannkuch(8 + n, cs)
Print cs; m
