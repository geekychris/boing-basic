' A first 3D scene: a ground grid, a spinning crate, a sky, on an off-screen canvas
Option Explicit

Sub Main()
    Dim cv As Canvas, e As Engine3D, crate As Long, ground As Long, f As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 256

    ' 1. the engine, the canvas it draws into, and the 3D area
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.View 320, 256, 160, 128, 256        ' area 320 x 256, centre (160, 128), scale 256

    ' 2. the palette: pens 0..4
    e.Palette Array(vbBlack, vbWhite, RGB(200, 120, 40), RGB(120, 70, 20), RGB(60, 140, 60))
    e.SkyGradient 5, RGB(20, 40, 100), RGB(160, 190, 230), 128    ' pen 5 is a sky

    ' 3. a model: a crate 60 units wide and high, faces in pens 2 (lit) and 3 (shaded)
    crate = e.ModelNew()
    e.MdlBox crate, 2, 3, -30, 30, 0, 60, -30, 30

    ' 4. flat ground: a 9 x 9 grid of heights, 100 units apart, round the origin
    ground = e.GridNew(9, 9, 100, -400, -400)
    e.GridColours ground, -100, 4, 4, 4, 1000, 1

    For f = 0 To 49
        ' 5. the camera: 120 units up, 250 back, looking a little down
        e.CamPos 0, 120, -250
        e.CamAngles 0, 2500
        ' 6. a frame: clear, fill the draw list, draw it, add text on top
        e.Clear 5
        e.Begin 3000
        e.DrawGrid ground
        e.DrawModel crate, 0, 0, 100, f * 600          ' turning by 600/65536 of a turn a frame
        e.Flush
        e.TextShadow 4, 4, "FRAME " & f, 1
        cv.Refresh
    Next f
    Print "polygons in the last frame:"; e.NPolys
    Print "picture hash:"; cv.Hash
End Sub
