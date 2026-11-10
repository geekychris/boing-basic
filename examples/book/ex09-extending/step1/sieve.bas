' sieve.bas - step 1: counting primes with the sieve of Eratosthenes, all in BASIC
Function CountPrimes(ByVal n As Long) As Long
    Dim composite() As Boolean, i As Long, j As Long, count As Long
    ReDim composite(n)
    For i = 2 To n
        If Not composite(i) Then
            count = count + 1
            If i <= n \ i Then              ' i * i would overflow a Long for big i
                For j = i * i To n Step i
                    composite(j) = True
                Next
            End If
        End If
    Next
    CountPrimes = count
End Function

Sub Main()
    Dim t As Double
    t = TimerMs()
    Print "Primes up to 1000000:"; CountPrimes(1000000)
    If Command() = "--time" Then Print "BASIC took "; Format(TimerMs() - t, "0"); " ms"
End Sub
