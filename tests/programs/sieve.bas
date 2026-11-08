' Sieve of Eratosthenes, twin primes and a Goldbach check
Option Explicit
Const N = 10000
Dim composite(2 To N) As Boolean, i As Long, j As Long, count As Long, twins As Long, last As Long
For i = 2 To Int(Sqr(N))
    If Not composite(i) Then
        For j = i * i To N Step i
            composite(j) = True
        Next
    End If
Next
For i = 2 To N
    If Not composite(i) Then
        count = count + 1
        If last > 0 And i - last = 2 Then twins = twins + 1
        last = i
    End If
Next
Print "primes below"; N; ":"; count
Print "twin pairs:"; twins
Print "largest:"; last
Dim e As Long, ok As Boolean
ok = True
For e = 4 To 1000 Step 2
    Dim found As Boolean
    found = False
    For i = 2 To e \ 2
        If Not composite(i) And Not composite(e - i) Then found = True: Exit For
    Next
    If Not found Then ok = False
Next
Print "Goldbach holds up to 1000:"; ok
