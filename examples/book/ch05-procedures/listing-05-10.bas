Function Factorial(ByVal n As Long) As Double
    If n <= 1 Then
        Factorial = 1
    Else
        Factorial = n * Factorial(n - 1)
    End If
End Function

Sub Countdown(ByVal n As Integer)
    If n = 0 Then Print "Lift off!": Exit Sub
    Print n;
    Countdown n - 1
End Sub

Print Factorial(10); Factorial(20)
Countdown 5
