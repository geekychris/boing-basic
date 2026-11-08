Dim shapes(1 To 3) As IShape, i As Integer
Dim c As Circle, s As Square
Set c = New Circle
c.Radius = 2
Set shapes(1) = c
Set s = New Square
s.SetSide 3
Set shapes(2) = s
Set c = New Circle
c.Radius = 1
Set shapes(3) = c
Dim total As Double
For i = 1 To 3
    Print shapes(i).Name; " "; Format(shapes(i).Area, "0.00")
    total = total + shapes(i).Area
Next
Print Format(total, "0.000")
Print TypeOf shapes(2) Is Square; TypeOf shapes(2) Is IShape; TypeOf shapes(2) Is Circle
Dim sh As IShape
Set sh = s
Print sh.Name
