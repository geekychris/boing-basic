Sub Inc(x As Integer)
    x = x + 1
End Sub
Sub IncVal(ByVal x As Integer)
    x = x + 1
End Sub
Function Fact(ByVal n As Long) As Long
    If n <= 1 Then
        Fact = 1
    Else
        Fact = n * Fact(n - 1)
    End If
End Function
Function Greet(Optional name As String = "World", Optional punct As String = "!") As String
    Greet = "Hello, " & name & punct
End Function
Function Total(ParamArray nums() As Variant) As Double
    Dim v As Variant
    For Each v In nums
        Total = Total + v
    Next
End Function
Function Describe(Optional x As Variant) As String
    If IsMissing(x) Then Describe = "missing" Else Describe = "got " & x
End Function
Sub Counter()
    Static count As Integer
    count = count + 1
    Print "called"; count
End Sub
Function Early(ByVal n As Integer) As String
    Early = "start"
    If n > 0 Then Exit Function
    Early = "end"
End Function
Sub Swap(a As Variant, b As Variant)
    Dim t As Variant
    t = a: a = b: b = t
End Sub

Dim a As Integer
a = 5
Inc a
Print a
IncVal a
Print a
Inc (a)
Print a
Call Inc(a)
Print a
Print Fact(10)
Print Greet(); " "; Greet("Amiga"); " "; Greet("Boing", "?")
Print Greet(punct:=".")
Print Total(1, 2, 3.5); Total()
Print Describe(); " "; Describe(5)
Counter
Counter
Counter
Print Early(1); " "; Early(0)
Dim p As Variant, q As Variant
p = "first": q = 2
Swap p, q
Print p; " "; q
