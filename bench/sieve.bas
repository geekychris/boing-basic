' Sieve of Eratosthenes, repeated
Dim flags(8192) As Boolean, i As Long, k As Long, r As Long, count As Long, n As Long
n = Val(Command$): If n = 0 Then n = 1
For r = 1 To 1000 * n
    count = 0
    For i = 2 To 8192: flags(i) = True: Next
    For i = 2 To 8192
        If flags(i) Then
            For k = i + i To 8192 Step i
                flags(k) = False
            Next
            count = count + 1
        End If
    Next
Next
Print count
