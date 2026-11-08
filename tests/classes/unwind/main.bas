Sub Inner(ByVal depth As Integer)
    Dim r As New Res, s As String
    r.Tag = "inner" & depth
    s = String(1000, "x")
    If depth = 0 Then Err.Raise 77, , "boom" Else Inner depth - 1
End Sub
Sub Outer()
    On Error GoTo h
    Dim keep As New Res
    keep.Tag = "outer"
    Inner 2
    Exit Sub
h:
    Print "caught"; Err.Number; Err.Description
End Sub
Dim i As Integer
For i = 1 To 2
    Outer
Next
Print "done"
