Implements IShape
Public Radius As Double
Private Function IShape_Area() As Double
    IShape_Area = 3.14159 * Radius * Radius
End Function
Private Property Get IShape_Name() As String
    IShape_Name = "circle"
End Property
