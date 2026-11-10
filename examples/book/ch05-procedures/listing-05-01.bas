Sub Greet(ByVal who As String, ByVal times As Integer)
    Dim i As Integer
    For i = 1 To times
        Print "Hello, "; who
    Next
End Sub

Greet "Ann", 2
Call Greet("Bob", 1)
