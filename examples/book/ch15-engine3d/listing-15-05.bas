' Hills, fog, shading, a row of pylons, sparks and a wall, drawn into a 3D window in a HUD
Option Explicit

Sub Main()
    Dim cv As Canvas, e As Engine3D, hills As Long, pylon As Long, i As Long
    Dim px(0 To 4) As Long, py(0 To 4) As Long, pz(0 To 4) As Long
    Dim sx(0 To 99) As Long, sy(0 To 99) As Long, sz(0 To 99) As Long, st As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 240
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.ViewOrigin 0, 20                         ' the 3D area starts 20 rows down
    e.View 320, 200, 160, 100, 220
    ' pens: 0 black, 1 white, 2 grey, 3 red, 4 water, 5 grass, 6 rock, 7 snow, 8 sky, 9 yellow
    e.Palette12 Array(&H000, &HFFF, &H888, &HC22, &H36A, &H5A4, &H886, &HEEF, &H9BE, &HFE4)
    e.Fog RGB(150, 180, 220), 600, 2000        ' fade into the haze from 600 to 2000 units
    e.Light 1, 2, -1, 80                       ' light from up and to the right

    hills = e.GridNew(33, 33, 64, -1024, 0)
    e.GridGenerate hills, 7, 120, 200          ' fractal hills
    e.GridColours hills, -20, 4, 5, 6, 140, 7  ' water, grass, rock, snow on top

    pylon = e.ModelNew()
    e.MdlPrism pylon, 2, 2, 6, 6, 0, 80        ' a six-sided post
    e.MdlPyramid pylon, 3, 3, -12, 12, 80, -12, 12, 100
    For i = 0 To 4
        px(i) = -200 + i * 100: pz(i) = 400 + i * 50
        py(i) = e.GridHeight(hills, px(i) * 65536, pz(i) * 65536)   ' stand on the ground
    Next i

    st = 5
    For i = 0 To 99
        sx(i) = (e.Rand(st) Mod 400) - 200
        sy(i) = 150 + e.Rand(st) Mod 100
        sz(i) = 300 + e.Rand(st) Mod 600
    Next i

    cv.Cls vbBlack
    e.CamPos 0, e.GridHeight(hills, 0, 200 * 65536) + 120, 200
    e.CamAngles 0, 1500
    e.Clear 8
    e.Begin 4000
    e.DrawGrid hills, 1800
    e.Shading = True                            ' flat shading for the models
    e.DrawModels 5, pylon, px, py, pz, 0        ' five pylons in one call
    e.Shading = False
    e.QuadW -2, 3, -60, 0, 700, 60, 0, 700, 60, 60, 700, -60, 60, 700
    e.Line3D -200, 200, 500, 200, 200, 500, 9
    e.Points 100, sx, sy, sz, 1, 2
    e.Spot 0, 180, 500, 8, 9
    e.Flush
    e.TextCentre 4, "HILLS", 1, 2
    cv.DrawText 4, 6, "polygons " & e.NPolys & ", dropped " & e.Dropped, vbWhite
    Print "polygons"; e.NPolys; " dropped"; e.Dropped
    Print "hash"; cv.Hash
End Sub
