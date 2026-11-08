Private items() As String, n As Long
Public Sub Add(ByVal s As String)
    ReDim Preserve items(n)
    items(n) = s
    n = n + 1
End Sub
Public Property Get Item(ByVal i As Long) As String
    Item = items(i)
End Property
Public Property Let Item(ByVal i As Long, ByVal s As String)
    items(i) = s
End Property
Public Property Get Count() As Long
    Count = n
End Property
