' Rectangle.cls
Option Explicit
Implements IShape

Private mW As Double, mH As Double

Public Sub SetSize(ByVal w As Double, ByVal h As Double)
    mW = w
    mH = h
End Sub

Private Function IShape_Area() As Double
    IShape_Area = mW * mH
End Function

Private Property Get IShape_Name() As String
    IShape_Name = "rectangle"
End Property

Private Sub IShape_Scale(ByVal factor As Double)
    mW = mW * factor
    mH = mH * factor
End Sub
