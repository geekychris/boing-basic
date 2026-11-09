' Canvas.Line with ends far outside the target (projected 3D edges) is clipped before it is
' stepped: fast, and lines near the target keep their exact pixels.
Dim c As Object, i As Long
Set c = CreateObject("Boing.Canvas")
For i = 1 To 500
    c.Line -2000000000, 50, 2000000000, 150 + (i Mod 7), RGB(255, 255, 255)
    c.Line 160, -1500000000, 170, 1900000000, RGB(255, 0, 0)
Next
Print c.Hash
c.Cls 0
For i = 0 To 400
    c.Line (i * 37) Mod 900 - 300, (i * 53) Mod 700 - 250, (i * 91) Mod 1100 - 400, (i * 17) Mod 600 - 200, RGB(i Mod 256, 100, 200)
Next
Print c.Hash
