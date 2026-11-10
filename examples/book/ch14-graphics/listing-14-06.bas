Option Explicit

Sub Main()
    Dim cv As Canvas, n As Long, b As Variant, pal As Variant, img As Long, rot As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    cv.Cls vbWhite
    cv.Rect 10, 10, 20, 20, vbBlack          ' an outline...
    n = cv.FloodFill(15, 15, vbRed)          ' ...filled inside
    b = cv.FillBounds()
    Print "filled"; n; "pixels at"; b(0); b(1); "size"; b(2); "x"; b(3)
    n = cv.ReplaceColor(vbRed, vbGreen)
    Print "recoloured"; n
    pal = cv.GetPalette(0, 16)
    Print "colours in the picture:"; UBound(pal) + 1

    img = cv.CopyImage(0, 10, 10, 20, 10)    ' a 20 x 10 piece of the picture
    rot = cv.RotateImage(img, 1)             ' turned a quarter
    Print "copy"; cv.ImageWidth(img); "x"; cv.ImageHeight(img); _
          ", rotated"; cv.ImageWidth(rot); "x"; cv.ImageHeight(rot)

    cv.SetTarget img
    cv.ClearRect 0, 0, 20, 5                 ' the top half transparent
    cv.SetTarget 0
    b = cv.ImageBounds(img)
    Print "opaque part of the copy:"; b(0); b(1); b(2); b(3)

    cv.Gradient 0, 40, 64, 8, vbBlack, vbBlue
    Print "gradient ends: &H"; Hex$(cv.Point(0, 40)); " &H"; Hex$(cv.Point(63, 40))
End Sub
