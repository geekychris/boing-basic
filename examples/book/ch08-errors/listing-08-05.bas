Function ParseAge(ByVal text As String) As Integer
    On Error GoTo bad
    ParseAge = CInt(text)
done:
    Exit Function
bad:
    Print "'"; text; "' is not a number"
    ParseAge = -1
    Resume done
End Function

Print ParseAge("42")
Print ParseAge("forty")
