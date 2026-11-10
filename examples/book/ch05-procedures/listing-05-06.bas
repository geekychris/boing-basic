Function Area(ByVal w As Double, Optional ByVal h As Double = -1) As Double
    If h < 0 Then h = w          ' a square if no height is given
    Area = w * h
End Function

Sub Report(ByVal title As String, Optional detail As Variant)
    If IsMissing(detail) Then
        Print title
    Else
        Print title; ": "; detail
    End If
End Sub

Print Area(3); Area(3, 4)
Report "Done"
Report "Done", "3 files"
