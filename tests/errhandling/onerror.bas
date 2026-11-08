Sub Risky(ByVal n As Integer)
    Dim x As Integer
    x = 100 \ n
    Print "result"; x
End Sub
Sub Safe(ByVal n As Integer)
    On Error GoTo handler
    Risky n
    Print "no error"
    Exit Sub
handler:
    Print "caught"; Err.Number; Err.Description
End Sub
Safe 5
Safe 0
On Error Resume Next
Dim i As Integer
i = 40000
Print "after overflow"; Err.Number
Err.Clear
Print Err.Number
Err.Raise 1000, "MyApp", "custom error"
Print Err.Number; Err.Source; " "; Err.Description
On Error GoTo 0
Function Divide(ByVal a As Double, ByVal b As Double) As Variant
    On Error GoTo fail
    Divide = a / b
    Exit Function
fail:
    Divide = "div error " & Err.Number
End Function
Print Divide(1, 4); " "; Divide(1, 0)
Sub RetryDemo()
    Dim divisor As Integer, x As Integer
    On Error GoTo h
    x = 100 \ divisor
    Print "done"; x
    Exit Sub
h:
    Print "retry"; divisor
    divisor = divisor + 5
    Resume
End Sub
RetryDemo
Sub NextDemo()
    On Error GoTo h
    Print "a"
    Err.Raise 7
    Print "b"
    Exit Sub
h:
    Print "handler"; Err.Number
    Resume Next
End Sub
NextDemo
Sub Nested()
    On Error GoTo h
    Inner
    Exit Sub
h:
    Print "outer caught"; Err.Number; Err.Description
End Sub
Sub Inner()
    Err.Raise vbObjectError + 1, , "from inner"
End Sub
Nested
Dim arr(3) As Integer
On Error Resume Next
arr(10) = 1
Print "subscript"; Err.Number
x = 1 / 0
Print "div"; Err.Number
Err.Clear
Dim o As Object
o.Foo
Print "nothing"; Err.Number
