' main.bas - one loop works on every kind of shape
Option Explicit

Dim shapes(1 To 3) As IShape
Dim c As Circle, r As Rectangle, i As Integer, total As Double

Set c = New Circle
c.Radius = 1
Set shapes(1) = c               ' a Circle is an IShape
Set r = New Rectangle
r.SetSize 2, 3
Set shapes(2) = r
Set c = New Circle
c.Radius = 2
Set shapes(3) = c

For i = 1 To 3
    shapes(i).Scale 2
    Print shapes(i).Name; " "; Format(shapes(i).Area, "0.00")
    total = total + shapes(i).Area
Next
Print "total "; Format(total, "0.00")

Print TypeOf shapes(2) Is Rectangle; TypeOf shapes(2) Is IShape; TypeOf shapes(2) Is Circle
Print TypeName(shapes(1)); " "; TypeName(shapes(2))

Dim s As Variant
For Each s In shapes
    If TypeOf s Is Circle Then Print "a circle of radius"; s.Radius
Next
