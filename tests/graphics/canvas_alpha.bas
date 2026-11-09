' Canvas.Alpha: see-through drawing (spans and pixels), the 50% and black fast paths,
' DrawImageBlend with per-pixel alpha; the same in the VM, JIT, native and on OS4
Option Explicit

Sub Main()
    Dim cv As Object, img As Long, xs(0 To 2) As Long, ys(0 To 2) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    cv.Cls RGB(200, 100, 50)
    Print "alpha"; cv.Alpha
    cv.Alpha = 128
    cv.Box 0, 0, 10, 10, RGB(0, 0, 255)
    Print "50% "; Hex$(cv.Point(5, 5))
    cv.Alpha = 64
    cv.Box 10, 0, 10, 10, RGB(255, 255, 255)
    Print "25% "; Hex$(cv.Point(15, 5))
    cv.Alpha = 192
    cv.Circle 30, 20, 6, 0, True
    Print "shadow "; Hex$(cv.Point(30, 20)); " outside "; Hex$(cv.Point(40, 20))
    cv.Alpha = 100
    xs(0) = 0: ys(0) = 20: xs(1) = 20: ys(1) = 20: xs(2) = 10: ys(2) = 40
    cv.Polygon xs, ys, 3, RGB(0, 255, 0), True
    cv.PSet 50, 40, RGB(255, 0, 255)
    cv.Line 40, 44, 63, 44, RGB(0, 255, 255)
    Print "poly "; Hex$(cv.Point(10, 25)); " pset "; Hex$(cv.Point(50, 40)); " line "; Hex$(cv.Point(50, 44))
    cv.Alpha = 0
    cv.Box 0, 0, 64, 48, 0
    Print "zero "; Hex$(cv.Point(60, 2))
    cv.Alpha = 999
    Print "clamped"; cv.Alpha
    img = cv.CreateImage(8, 8)
    cv.SetTarget img
    cv.Alpha = 128
    cv.Box 0, 0, 8, 8, RGB(255, 0, 0)
    cv.SetTarget 0
    cv.Alpha = 255
    cv.DrawImageBlend img, 56, 0, 255
    cv.DrawImageBlend img, 56, 10, 77
    Print "image "; Hex$(cv.Point(58, 2)); " "; Hex$(cv.Point(58, 12))
    Print "hash "; Hex$(cv.Hash)
End Sub
