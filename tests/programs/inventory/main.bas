Option Explicit
Private WithEvents inv As Inventory

Private Sub inv_LowStock(ByVal itemName As String, ByVal qty As Long)
    Print "  low stock: "; itemName; " ("; qty; ")"
End Sub

Sub Main()
    Set inv = New Inventory
    inv.Add "Widget", 2.5, 10
    inv.Add "Gadget", 12.99, 3
    inv.Add("Doohickey", 0.75, 100).Qty = 50
    Print "items:"; inv.Count
    Print inv.Report;
    Print "total: "; Format(inv.TotalValue, "#,##0.00")
    inv.Sell "widget", 4
    inv.Sell "Gadget", 2
    On Error Resume Next
    inv.Sell "sprocket", 1
    Print "error: "; Err.Description; " from "; Err.Source
    Err.Clear
    inv.Sell "gadget", 5
    Print "error: "; Err.Description
    On Error GoTo 0
    Print inv.Report;
    Print "total: "; Format(inv.TotalValue, "#,##0.00")
    Print inv.Find("nothing") Is Nothing
End Sub
