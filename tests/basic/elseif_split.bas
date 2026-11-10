' "Else If" on one line is Else + a nested If (its own End If); vbDecimal
Sub Main()
    Dim x As Long
    x = 2
    If x = 1 Then
        Print "one"
    Else If x = 2 Then
        Print "two"
    Else
        Print "other"
    End If
    End If
    Print vbDecimal
End Sub
