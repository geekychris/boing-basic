' Recursive calls
Function Fib(ByVal n As Long) As Long
    If n < 2 Then Fib = n Else Fib = Fib(n - 1) + Fib(n - 2)
End Function
Dim n As Long
n = Val(Command$): If n = 0 Then n = 1
Print Fib(30 + n * 2)
