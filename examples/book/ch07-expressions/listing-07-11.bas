Function Check(ByVal name As String, ByVal result As Boolean) As Boolean
    Print "checking "; name
    Check = result
End Function

If Check("first", False) And Check("second", True) Then Print "both"
