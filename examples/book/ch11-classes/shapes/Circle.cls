' Circle.cls
Option Explicit
Implements IShape

Public Radius As Double

Private Function IShape_Area() As Double
    IShape_Area = 3.14159265 * Radius * Radius
End Function

Private Property Get IShape_Name() As String
    IShape_Name = "circle"
End Property

Private Sub IShape_Scale(ByVal factor As Double)
    Radius = Radius * factor
End Sub
