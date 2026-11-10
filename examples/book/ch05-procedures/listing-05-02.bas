Function Average(ByVal a As Double, ByVal b As Double) As Double
    Average = (a + b) / 2
End Function

Function Sign(ByVal n As Long) As String
    Sign = "zero"
    If n > 0 Then Sign = "positive": Exit Function
    If n < 0 Then Sign = "negative"
End Function

Print Average(3, 4)
Print Sign(5); " "; Sign(-2); " "; Sign(0)
