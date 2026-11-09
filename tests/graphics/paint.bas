' The Canvas's paint-program members, off-screen: fills, brushes, scaled and blended blits,
' image transforms, palettes, and the PNG / IFF ILBM codecs (round trips)
Option Explicit

Sub Main()
    Dim cv As Object, a As Long, b As Long, n As Long, i As Long
    Dim pal() As Long, bnd As Variant

    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    cv.Cls vbBlack
    cv.Rect 10, 10, 20, 20, vbWhite
    n = cv.FloodFill(15, 15, vbRed)
    Print "fill"; n; " "; Hex$(cv.Point(15, 15)); " "; Hex$(cv.Point(10, 10)); " "; Hex$(cv.Point(5, 5))
    n = cv.FloodFill(0, 0, vbBlue)
    Print "outside"; n; " "; Hex$(cv.Point(63, 47))
    Print "same"; cv.FloodFill(0, 0, vbBlue)
    cv.Cls vbBlack
    cv.PSet 5, 5, RGB(10, 10, 10)
    Print "tol"; cv.FloodFill(0, 0, vbGreen, 16); " "; Hex$(cv.Point(5, 5))

    cv.Cls vbBlack
    cv.Ellipse 32, 24, 20, 10, vbYellow, True
    Print "ellipse "; Hex$(cv.Point(32, 24)); " "; Hex$(cv.Point(12, 24)); " "; Hex$(cv.Point(11, 24)); " "; Hex$(cv.Point(32, 14)); " "; Hex$(cv.Point(32, 13))
    cv.Cls vbBlack
    cv.Ellipse 32, 24, 20, 10, vbYellow
    Print "outline "; Hex$(cv.Point(52, 24)); " "; Hex$(cv.Point(32, 34)); " "; Hex$(cv.Point(32, 24)); " hash"; cv.Hash

    cv.Cls vbBlack
    cv.BrushLine 10, 10, 50, 10, 7, vbWhite
    Print "brush "; Hex$(cv.Point(30, 7)); " "; Hex$(cv.Point(30, 13)); " "; Hex$(cv.Point(30, 14)); " "; Hex$(cv.Point(30, 6)); " "; Hex$(cv.Point(54, 10))
    cv.BrushLine 10, 30, 30, 40, 4, vbRed, 1
    Print "square "; Hex$(cv.Point(10, 30)); " hash"; cv.Hash

    ' images: copy, erase, bounds, flip, rotate, scale
    a = cv.CreateImage(8, 4)
    cv.SetTarget a
    cv.Cls vbRed
    cv.PSet 0, 0, vbGreen
    cv.ClearRect 4, 0, 4, 4
    Print "img "; cv.ImagePoint(a, 0, 0); cv.ImagePoint(a, 5, 0); " bounds ";: bnd = cv.ImageBounds(a): Print bnd(0); bnd(1); bnd(2); bnd(3)
    cv.SetTarget 0
    b = cv.RotateImage(a, 1)
    Print "rot"; cv.ImageWidth(b); cv.ImageHeight(b); " "; Hex$(cv.ImagePoint(b, 3, 0)); " "; cv.ImagePoint(b, 0, 7)
    cv.FlipImage a
    Print "flip "; Hex$(cv.ImagePoint(a, 7, 0)); " "; cv.ImagePoint(a, 0, 0)
    b = cv.ScaleImage(a, 16, 8)
    Print "scale"; cv.ImageWidth(b); " "; Hex$(cv.ImagePoint(b, 15, 0)); " "; Hex$(cv.ImagePoint(b, 14, 1))
    b = cv.CopyImage(0, 8, 8, 10, 10)
    Print "copy"; cv.ImageWidth(b); cv.ImageHeight(b); " "; Hex$(cv.ImagePoint(b, 2, 2))

    ' scaled blit: 4x zoom of a 2x2 checker
    a = cv.CreateImage(2, 2)
    cv.SetTarget a
    cv.PSet 0, 0, vbWhite: cv.PSet 1, 1, vbWhite
    cv.PSet 1, 0, vbBlue: cv.PSet 0, 1, vbBlue
    cv.SetTarget 0
    cv.Cls vbBlack
    cv.DrawImageScaled a, 0, 0, 2, 2, 10, 10, 8, 8, True
    Print "zoom "; Hex$(cv.Point(10, 10)); " "; Hex$(cv.Point(13, 13)); " "; Hex$(cv.Point(14, 13)); " "; Hex$(cv.Point(17, 17)); " "; Hex$(cv.Point(18, 18))
    ' blend 50%
    cv.Cls vbBlack
    cv.DrawImageBlend a, 0, 0, 128
    Print "blend "; Hex$(cv.Point(0, 0)); " "; Hex$(cv.Point(1, 0))

    ' stamps and erasing
    cv.Cls vbBlack
    cv.StampLine a, 10, 10, 20, 10, vbGreen, 3
    Print "stamp "; Hex$(cv.Point(10, 10)); " "; Hex$(cv.Point(9, 9)); " hash"; cv.Hash
    cv.ReplaceColor vbGreen, vbRed
    Print "replace "; Hex$(cv.Point(10, 10))

    ' palettes
    cv.Cls vbBlack
    cv.Box 0, 0, 32, 48, vbRed
    cv.Box 32, 0, 32, 24, vbWhite
    pal = cv.GetPalette(0, 16)
    Print "palette"; UBound(pal) + 1; " "; Hex$(pal(0)); " "; Hex$(pal(1)); " "; Hex$(pal(2)); " over "; IsEmpty(cv.GetPalette(0, 2))
    For i = 0 To 63
        cv.Line i, 30, i, 47, RGB(i * 4, 255 - i * 4, 128)
    Next
    pal = cv.Quantize(0, 8)
    n = UBound(pal) + 1
    Print "quantize"; n
    a = cv.CopyImage(0)
    cv.RemapImage a, pal, n, True
    Print "remap"; UBound(cv.GetPalette(a, 256)) + 1 <= 8

    ' PNG and ILBM round trips
    cv.Cls RGB(1, 2, 3)
    cv.Ellipse 32, 24, 25, 15, RGB(200, 100, 50), True
    cv.Spray 20, 20, 8, 200, vbWhite, 7
    a = cv.CopyImage(0)
    cv.SavePNG "t.png"
    b = cv.LoadImage("t.png")
    Print "png "; cv.ImageHash(a) = cv.ImageHash(b); cv.ImageWidth(b); cv.ImageHeight(b); FileLen("t.png") < 64 * 48 * 3
    cv.SaveILBM "t.iff"
    b = cv.LoadImage("t.iff")
    Print "ilbm24 "; cv.ImageHash(a) = cv.ImageHash(b)
    pal = cv.GetPalette(0, 16)
    n = UBound(pal) + 1
    cv.SaveILBM "t8.iff", 0, pal, n
    b = cv.LoadImage("t8.iff")
    Print "ilbm8 "; cv.ImageHash(a) = cv.ImageHash(b); UBound(cv.LastPalette()) + 1; " "; FileLen("t8.iff") < 2000
    cv.SavePNG "t8.png", 0, pal, n
    b = cv.LoadImage("t8.png")
    Print "png8 "; cv.ImageHash(a) = cv.ImageHash(b); UBound(cv.LastPalette()) + 1
    ' alpha survives PNG
    a = cv.CreateImage(5, 5)
    cv.SetTarget a
    cv.PSet 2, 2, vbRed
    cv.SetTarget 0
    cv.SavePNG "ta.png", a
    b = cv.LoadImage("ta.png")
    Print "pnga "; cv.ImageHash(a) = cv.ImageHash(b); cv.ImagePoint(b, 0, 0); Hex$(cv.ImagePoint(b, 2, 2))
    Kill "t.png": Kill "t.iff": Kill "t8.iff": Kill "t8.png": Kill "ta.png"
End Sub
