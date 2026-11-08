Option Explicit
Public Name As String
Public Price As Currency
Private mQty As Long

Public Property Get Qty() As Long
    Qty = mQty
End Property
Public Property Let Qty(ByVal n As Long)
    If n < 0 Then Err.Raise vbObjectError + 10, "Item", "quantity cannot be negative"
    mQty = n
End Property
Public Function Value() As Currency
    Value = Price * mQty
End Function
