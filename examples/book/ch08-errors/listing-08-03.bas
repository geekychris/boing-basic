Sub Retry()
    Dim divisor As Integer, result As Integer
    On Error GoTo fix
    result = 100 \ divisor
    Print "result"; result; "with divisor"; divisor
    Exit Sub
fix:
    Print "error"; Err.Number; "- trying a divisor of 4"
    divisor = 4
    Resume
End Sub

Retry
