Option Explicit

Sub Main()
    Dim cv As Canvas, ship As Long, big As Long, back As Long
    Dim xs(0 To 2) As Long, ys(0 To 2) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 64

    ' draw a ship once, into an image
    ship = cv.CreateImage(16, 16)
    cv.SetTarget ship
    xs(0) = 8: ys(0) = 0
    xs(1) = 15: ys(1) = 15
    xs(2) = 0: ys(2) = 15
    cv.Polygon xs, ys, 3, vbWhite, True
    cv.SetTarget 0
    Print "ship is image"; ship; "size"; cv.ImageWidth(ship); "x"; cv.ImageHeight(ship)
    Print "corner of the image:"; cv.ImagePoint(ship, 0, 0); "(transparent)"

    ' use it as a sprite
    cv.Cls vbBlue
    cv.DrawImage ship, 24, 24
    Print "sprite pixel &H"; Hex$(cv.Point(32, 36)); ", around it &H"; Hex$(cv.Point(24, 24))

    ' a scaled copy, and the whole picture saved and loaded again
    big = cv.ScaleImage(ship, 32, 32)
    Print "scaled:"; cv.ImageWidth(big); "x"; cv.ImageHeight(big)
    cv.SavePNG "frame.png"
    back = cv.LoadImage("frame.png")
    Print "loaded"; cv.ImageWidth(back); "x"; cv.ImageHeight(back); " same pixel: "; cv.ImagePoint(back, 32, 36) = cv.Point(32, 36)
    Kill "frame.png"
End Sub
