Function Total(ParamArray nums() As Variant) As Double
    Dim x As Variant
    For Each x In nums
        Total = Total + x
    Next
End Function

Sub ShowAll(ByVal label As String, ParamArray items())
    Dim i As Long
    Print label; UBound(items) + 1; "item(s):";
    For i = 0 To UBound(items)
        Print " "; items(i);
    Next
    Print
End Sub

Print Total(1, 2, 3.5); Total()
ShowAll "Got", "a", 2, True
ShowAll "Got"
