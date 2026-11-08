Option Explicit
Private mItems As Collection
Public Event LowStock(ByVal itemName As String, ByVal qty As Long)
Public Threshold As Long

Private Sub Class_Initialize()
    Set mItems = New Collection
    Threshold = 2
End Sub

Public Function Add(ByVal name As String, ByVal price As Currency, ByVal qty As Long) As Item
    Dim it As Item
    Set it = New Item
    it.Name = name
    it.Price = price
    it.Qty = qty
    mItems.Add it, LCase$(name)
    Set Add = it
End Function

Public Property Get Count() As Long
    Count = mItems.Count
End Property

Public Function Find(ByVal name As String) As Item
    On Error Resume Next
    Set Find = mItems(LCase$(name))
End Function

Public Sub Sell(ByVal name As String, ByVal n As Long)
    Dim it As Item
    Set it = Find(name)
    If it Is Nothing Then Err.Raise vbObjectError + 1, "Inventory", "no such item: " & name
    it.Qty = it.Qty - n
    If it.Qty <= Threshold Then RaiseEvent LowStock(it.Name, it.Qty)
End Sub

Public Function TotalValue() As Currency
    Dim it As Variant
    For Each it In mItems
        TotalValue = TotalValue + it.Value
    Next
End Function

Public Function Report() As String
    Dim it As Item, i As Long, s As String
    For i = 1 To mItems.Count
        Set it = mItems(i)
        s = s & Left$(it.Name & Space(10), 10) & Right$(Space(5) & it.Qty, 5) & Right$(Space(10) & Format(it.Value, "0.00"), 10) & vbLf
    Next
    Report = s
End Function
