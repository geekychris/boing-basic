' sieve.bas - exercise 9: counting primes three ways. BASIC, a C function (primes.c, with
' Declare ... Lib "C"), and BASIC driving a BitSet class from an extension in C (bits.c).
Declare Function CountPrimesC Lib "C" Alias "count_primes" (ByVal n As Long) As Long

Function CountPrimesBasic(ByVal n As Long) As Long
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
    CountPrimesBasic = count
End Function

Function CountPrimesBits(ByVal n As Long) As Long
    ' one call per number: correct, but slower than plain BASIC (a call costs more than an array read)
    Dim composite As BitSet, i As Long, count As Long
    Set composite = New BitSet
    composite.Resize n + 1
    For i = 2 To n
        If Not composite.TestBit(i) Then
            count = count + 1
            If i <= n \ i Then composite.SetEvery i * i, i     ' the inner loop runs in C
        End If
    Next
    CountPrimesBits = count
End Function

Function CountPrimesBits2(ByVal n As Long) As Long
    ' one call per prime: NextClear does the searching in C
    Dim composite As BitSet, i As Long, count As Long
    Set composite = New BitSet
    composite.Resize n + 1
    i = composite.NextClear(2)
    Do While i <> -1
        count = count + 1
        If i <= n \ i Then composite.SetEvery i * i, i
        i = composite.NextClear(i + 1)
    Loop
    CountPrimesBits2 = count
End Function

Sub Main()
    Dim n As Long, t As Double
    n = 1000000
    t = TimerMs()
    Print "BASIC:     "; CountPrimesBasic(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "C:         "; CountPrimesC(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "BitSet:    "; CountPrimesBits(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "NextClear: "; CountPrimesBits2(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
End Sub
