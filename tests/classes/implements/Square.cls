Implements IShape
Private mSide As Double
Public Sub SetSide(ByVal s As Double)
    mSide = s
End Sub
Private Function IShape_Area() As Double
    IShape_Area = mSide * mSide
End Function
Private Property Get IShape_Name() As String
    IShape_Name = "square"
End Property
