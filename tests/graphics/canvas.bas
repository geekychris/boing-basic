' The Canvas control's drawing engine, off-screen: every primitive, checked by pixel reads
' and picture hashes (the same in the VM, native builds and on AmigaOS 4)
Option Explicit

Sub Main()
    Dim cv As Object, img As Long, xs(0 To 3) As Long, ys(0 To 3) As Long
    Dim px(0 To 2) As Long, py(0 To 2) As Long, pc(0 To 2) As Long, i As Long

    Set cv = CreateObject("Boing.Canvas")
    Print TypeName(cv); " "; cv.Width; cv.Height
    cv.Resize 64, 48
    Print "size"; cv.Width; cv.Height; " back"; cv.BackColor; " fore "; Hex$(cv.ForeColor)

    cv.Cls RGB(0, 0, 40)
    Print "cls "; Hex$(cv.Point(0, 0)); " "; Hex$(cv.Point(63, 47)); " outside "; cv.Point(64, 0)
    cv.PSet 3, 4, vbRed
    Print "pset "; Hex$(cv.Point(3, 4)); " cur "; cv.CurrentX; cv.CurrentY
    cv.ForeColor = vbYellow
    cv.PSet 5, 5
    Print "fore "; Hex$(cv.Point(5, 5))

    cv.Line 0, 10, 63, 10, vbGreen
    Print "hline "; Hex$(cv.Point(0, 10)); " "; Hex$(cv.Point(63, 10))
    cv.Line 0, 0, 47, 47, vbWhite
    Print "diag "; Hex$(cv.Point(20, 20)); " "; Hex$(cv.Point(21, 20))
    cv.Line 10, 20, 20, 30, vbBlue, "BF"
    Print "BF "; Hex$(cv.Point(15, 25)); " B ";
    cv.Line 30, 20, 40, 30, vbCyan, "B"
    Print Hex$(cv.Point(30, 25)); " "; Hex$(cv.Point(35, 25))
    cv.Box 50, 2, 4, 3, vbMagenta
    Print "box "; Hex$(cv.Point(53, 4)); " "; Hex$(cv.Point(54, 4))
    cv.Circle 32, 38, 6, vbRed
    Print "circle "; Hex$(cv.Point(38, 38)); " "; Hex$(cv.Point(32, 38))
    cv.Circle 32, 38, 3, vbGreen, True
    Print "disc "; Hex$(cv.Point(32, 38))
    xs(0) = 44: ys(0) = 32: xs(1) = 60: ys(1) = 32: xs(2) = 60: ys(2) = 46: xs(3) = 44: ys(3) = 46
    cv.Polygon xs, ys, 4, RGB(10, 20, 30), True
    Print "polygon "; Hex$(cv.Point(50, 40)); " edge "; Hex$(cv.Point(59, 45)); " out "; Hex$(cv.Point(60, 40))
    px(0) = 1: py(0) = 46: px(1) = 2: py(1) = 46: px(2) = 99: py(2) = 99
    pc(0) = RGB(1, 2, 3): pc(1) = RGB(4, 5, 6): pc(2) = vbWhite
    cv.PSetMany px, py, pc, 3
    Print "many "; Hex$(cv.Point(1, 46)); " "; Hex$(cv.Point(2, 46))
    cv.PSetMany px, py, vbWhite, 2, 2
    Print "many2 "; Hex$(cv.Point(2, 47))
    cv.DrawText 2, 12, "Hi!", vbWhite
    Print "text w"; cv.TextWidth("Hi!"); " h"; cv.TextHeight(); " curx"; cv.CurrentX
    Print "hash "; cv.Hash

    ' images: transparent until drawn into, DrawImage skips transparent pixels
    img = cv.CreateImage(4, 4)
    cv.SetTarget img
    Print "image"; img; cv.ImageWidth(img); cv.ImageHeight(img); " transparent "; Hex$(cv.Point(0, 0))
    cv.PSet 1, 1, vbRed
    Print "target"; cv.Target; " img pixel "; Hex$(cv.Point(1, 1))
    cv.SetTarget 0
    cv.Cls vbBlack
    cv.DrawImage img, 10, 10
    Print "sprite "; Hex$(cv.Point(11, 11)); " "; Hex$(cv.Point(10, 10))
    cv.DrawImage img, 20, 10, True
    Print "opaque "; Hex$(cv.Point(20, 10))
    cv.DrawImagePart img, 1, 1, 2, 2, 62, 46
    Print "part "; Hex$(cv.Point(62, 46)); " clip ok"
    cv.SaveImage "canvas_test.ppm"
    i = cv.LoadImage("canvas_test.ppm")
    Print "loaded"; i; cv.ImageWidth(i); cv.ImageHeight(i)
    cv.SetTarget i
    Print "loaded pixel "; Hex$(cv.Point(11, 11))
    cv.SetTarget 0
    Kill "canvas_test.ppm"

    ' keys
    Print "key "; cv.KeyDown(vbKeyLeft);
    cv.InjectKey vbKeyLeft
    Print cv.KeyDown(vbKeyLeft);
    cv.InjectKey vbKeyLeft, False
    Print cv.KeyDown(vbKeyLeft)

    cv.Refresh
    Print "frames"; cv.Frames

    On Error Resume Next
    cv.FreeImage img
    cv.DrawImage img, 0, 0
    Print "freed image: error"; Err.Number
    Err.Clear
    i = cv.LoadImage("no_such_picture.ppm")
    Print "missing picture: error"; Err.Number
    Err.Clear
    cv.Resize 0, 10
    Print "bad size: error"; Err.Number
    Err.Clear
    cv.NoSuchMethod 1
    Print "no member: error"; Err.Number
    Err.Clear
    Set cv = CreateObject("Boing.NoSuchThing")
    Print "unknown class: error"; Err.Number
End Sub
