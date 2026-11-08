Dim c As Object, v As Variant
Set c = CreateObject("Boing.Canvas")
Print TypeName(c); c.Width; c.Height
c.PSet 10, 10, RGB(255, 0, 0)
Print c.Point(10, 10) = RGB(255, 0, 0)
Set v = CreateObject("Canvas")
Print TypeName(v)
On Error Resume Next
Set c = CreateObject("No.Such")
Print "err"; Err.Number
