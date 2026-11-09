' Engine3D demo scene: a terrain flyover with spinning models, a point cloud and an fps
' counter. All the 3D work is in the engine (C): a frame is about 20 calls.
Option Explicit

Public e As Object
Public frames As Long
Private ship As Long, tower As Long, gem As Long
Private ground As Long
Private sx(0 To 199) As Long, sy(0 To 199) As Long, sz(0 To 199) As Long, sc(0 To 199) As Long
Private fpsShown As Double, fpsT0 As Double, fpsN As Long

Public Const GRID_N As Long = 65
Public Const CELL As Long = 64

Public Sub SceneInit(cv As Object)
    Dim i As Long, st As Long
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.View cv.Width, cv.Height, cv.Width \ 2, cv.Height \ 2 - 20, cv.Width * 4 \ 5
    ' pens: 0 black 1 white 2..7 the ship, 8 sea 9 grass 10 rock 11 snow 12 sky 13 gold 14 stars
    e.Palette12 Array(&H000, &HFFF, &HC33, &H822, &HDDE, &H99A, &H3CF, &HF80, _
                      &H37B, &H5A4, &H886, &HEEF, &H58A, &HFC3, &HFFC)
    e.SkyGradient 12, RGB(20, 40, 90), RGB(170, 190, 230), cv.Height \ 2
    e.Light -1, 3, 1, 70
    e.Fog RGB(170, 190, 230), 900, 2400

    ship = e.ModelNew()
    e.MdlBox ship, 4, 5, -10, 10, -6, 6, -30, 20          ' body
    e.MdlPyramid ship, 2, 3, -10, 10, -6, 20, 50, 0       ' nose (apex at y 0 ... a wedge)
    e.MdlBox ship, 6, 6, -40, 40, -2, 2, -10, 10          ' wings
    e.MdlBox ship, 2, 3, -3, 3, 6, 22, -30, -18           ' fin
    tower = e.ModelNew()
    e.MdlPrism tower, 10, 3, 8, 30, 0, 160
    e.MdlPyramid tower, 2, 3, -30, 30, 160, -30, 30, 220
    gem = e.ModelNew()
    e.MdlPyramid gem, 13, 7, -20, 20, 0, -20, 20, 40
    e.MdlPyramid gem, 7, 13, -20, 20, 0, -20, 20, -40

    ground = e.GridNew(GRID_N, GRID_N, CELL, -(GRID_N \ 2) * CELL, 0)
    e.GridGenerate ground, 1234, 150, 260
    e.GridColours ground, -30, 8, 9, 10, 150, 11

    st = 99
    For i = 0 To 199
        sx(i) = (e.Rand(st) Mod 2400) - 1200
        sy(i) = 300 + (e.Rand(st) Mod 400)
        sz(i) = e.Rand(st) Mod (GRID_N * CELL)
        sc(i) = 14 - (i And 1) * 13
    Next i
    fpsT0 = Timer
End Sub

' draw frame t (any Long; the scene is a function of t, so the same t gives the same picture)
Public Sub SceneFrame(cv As Object, ByVal t As Long)
    Dim z As Long, h As Long, cx As Long, k As Long, now As Double
    z = (t * 6) Mod ((GRID_N - 20) * CELL) + 4 * CELL
    cx = e.Sin(t * 150) \ 512                       ' sway
    ' fly above the highest ground just ahead
    h = e.GridHeight(ground, cx * 65536, z * 65536)
    For k = 1 To 3
        If e.GridHeight(ground, cx * 65536, (z + k * 150) * 65536) > h Then h = e.GridHeight(ground, cx * 65536, (z + k * 150) * 65536)
    Next k
    If h < -30 Then h = -30
    e.CamPos cx, h + 200, z
    e.CamAngles e.Sin(t * 150) \ 64, 1400 + e.Sin(t * 97) \ 128, e.Cos(t * 150) \ 32
    e.Clear 12
    e.Begin 3000
    e.Shading = False
    e.DrawGrid ground, 1500
    e.Shading = True
    For k = 0 To 3
        e.DrawModel tower, (k - 2) * 400 + 200, e.GridHeight(ground, ((k - 2) * 400 + 200) * 65536, (z + 900 + k * 300) * 65536), _
                    ((z + 900 + k * 300) \ 1200) * 1200 + k * 300 - 300
    Next k
    e.DrawModel ship, cx + e.Sin(t * 300) \ 1024, h + 170, z + 300, t * 400, e.Sin(t * 200) \ 16, e.Sin(t * 250) \ 8
    e.DrawModel gem, -cx + 60, h + 230, z + 520, t * 900
    e.Shading = False
    e.Points 200, sx, sy, sz, sc, 2
    e.Flush
    frames = frames + 1
    fpsN = fpsN + 1
    now = Timer
    If now - fpsT0 >= 1 Or now < fpsT0 Then
        If now > fpsT0 Then fpsShown = fpsN / (now - fpsT0)
        fpsT0 = now
        fpsN = 0
    End If
    e.TextShadow 4, 4, "ENGINE3D  " & Format$(fpsShown, "0.0") & " FPS", 1
    e.TextShadow 4, 16, e.NPolys & " POLYS", 14
End Sub
