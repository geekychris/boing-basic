Private mValue As Long
Public Step_ As Long
Public Property Get Value() As Long
    Value = mValue
End Property
Public Property Let Value(ByVal v As Long)
    mValue = v
End Property
Public Sub Bump()
    mValue = (mValue + Step_) And &HFFFF&
End Sub
