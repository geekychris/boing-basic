' Recursive calls
Function Fib(ByVal n As Long) As Long
    If n < 2 Then Fib = n Else Fib = Fib(n - 1) + Fib(n - 2)
End Function
Print Fib(32)
