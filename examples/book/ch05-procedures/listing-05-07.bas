Sub Box(Optional ByVal w As Long = 1, Optional ByVal h As Long = 1, Optional ByVal fill As String = "#")
    Dim r As Long
    For r = 1 To h
        Print String(w, fill)
    Next
End Sub

Box h:=2, w:=5
Box 3, fill:="*"
