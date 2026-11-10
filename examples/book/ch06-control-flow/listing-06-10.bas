Function FindFirst(ByVal text As String, ByVal ch As String) As Long
    Dim i As Long
    For i = 1 To Len(text)
        If Mid$(text, i, 1) = ch Then
            FindFirst = i
            Exit Function
        End If
    Next
    FindFirst = -1
End Function

Print FindFirst("Boing BASIC", "B"); FindFirst("Boing BASIC", "S"); FindFirst("Boing", "z")
