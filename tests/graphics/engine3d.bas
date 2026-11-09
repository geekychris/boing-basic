' Boing.Engine3D (docs/engine3d.md): maths, camera, draw list, models, grids, shading, fog,
' text, checked by values and picture hashes (the same in the VM, the JIT, native and on OS4)
Option Explicit

Dim cv As Object, e As Object

Sub Shot(ByVal what As String)
    Print what; " polys"; e.NPolys; " dropped"; e.Dropped; " hash "; Hex$(cv.Hash)
End Sub

Sub Main()
    Dim m As Long, m2 As Long, m3 As Long, g As Long, i As Long, k As Long
    Dim ox As Long, oy As Long, oz As Long, sx As Long, sy As Long, st As Long
    Dim xs(0 To 4) As Long, ys(0 To 4) As Long, zs(0 To 4) As Long
    Dim rot(0 To 8) As Long, r2(0 To 8) As Long, r3(0 To 8) As Long, tbl(0 To 255) As Long
    Dim co(0 To 23) As Long, pens(0 To 1) As Long, lc(0 To 11) As Long
    Dim px(0 To 99) As Long, py(0 To 99) As Long, pz(0 To 99) As Long, pc(0 To 99) As Long
    Dim vx(0 To 3) As Long, vy(0 To 3) As Long, vz(0 To 3) As Long, fn(0 To 1) As Long, fi(0 To 7) As Long, fc(0 To 1) As Long
    Dim hx(0 To 15) As Long, ids(0 To 2) As Long, yw(0 To 2) As Long

    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 256
    Set e = CreateObject("Boing.Engine3D")
    Print TypeName(e)

    ' ---- maths (amiga3d's values)
    Print "sin"; e.Sin(0); e.Sin(16384); e.Sin(8192); e.Sin(100); e.Cos(32768); e.Sin(-16384)
    Print "atan2"; e.Atan2(1, 1); e.Atan2(-5, 0); e.Atan2(0, -3); e.Atan2(100, 7)
    Print "isqrt"; e.ISqrt(1000000); e.ISqrt(-1); e.Hypot(3000, 4000); e.Hypot(-70000, 240000)
    Print "hash "; Hex$(e.Hash(12345)); " fix"; e.FMul(3 * 65536, 98304); e.FDiv(65536, 3 * 65536); e.FSqrt(4 * 65536)
    st = 42
    Print "rand"; e.Rand(st); e.Rand(st); st
    e.RotYPR rot, 8192, 1000, -3000
    e.RotYaw r2, 16384
    e.MatMul r3, rot, r2
    Print "rot"; rot(0); rot(4); rot(8); " yaw"; r2(0); r2(2); r2(6); " mul"; r3(0); r3(5)
    e.MatApply r2, 10, 20, 30, ox, oy, oz
    Print "apply"; ox; oy; oz
    e.SinTable tbl
    Print "table"; tbl(0); tbl(64); tbl(200)

    ' ---- camera
    e.Attach cv
    e.View 320, 256, 160, 128, 256
    e.CamPos 0, 60, -300
    e.CamAngles 0, 2000
    Print "cam"; e.CamX; e.CamY; e.CamZ; e.CamYaw; e.CamPitch; " u"; e.CamU; " near"; e.CamNear; " horizon"; e.Horizon
    e.Xform 100, 0, 0, ox, oy, oz
    Print "xform"; ox; oy; oz
    Print "project "; e.Project(100, 0, 0, sx, sy); sx; sy; " behind "; e.Project(0, 0, -400, sx, sy)
    Print "visible "; e.Visible(0, 0, 0, 50); " "; e.Visible(5000, 0, 0, 50); " "; e.Visible(0, 0, -900, 50)
    e.CamPlace 10 * 65536 + 40000, 60 * 65536, -300 * 65536 + 12345
    Print "placed"; e.CamX; e.CamY; e.CamZ; " u"; e.CamU; " near"; e.CamNear
    e.Xform 100, 0, 0, ox, oy, oz
    Print "xform16"; ox; oy; oz
    e.CamSave 1
    e.CamPos 0, 0, 0
    e.CamLoad 1
    Print "saved"; e.CamX; e.CamU

    ' ---- models
    m = e.ModelNew()
    e.MdlBox m, 8, 9, -40, 40, 0, 80, -40, 40
    e.MdlShadow m, 15, -50, 50, -50, 50
    m2 = e.ModelNew()
    e.MdlPyramid m2, 11, 12, -30, 30, 0, -30, 30, 70
    k = e.MdlVtx(m2, 0, 100, 0)
    m3 = e.ModelNew()
    e.MdlPrism m3, 13, 10, 8, 26, 0, 130
    Print "models"; m; m2; m3; " verts"; e.ModelVerts(m); e.ModelVerts(m2); e.ModelVerts(m3); " faces"; e.ModelFaces(m); e.ModelFaces(m3); " vtx"; k; " r"; e.ModelRadius(m)
    e.CamPos 0, 60, -300
    e.CamAngles 0, 2000
    cv.Cls 0
    e.Begin 3000
    e.DrawModel m, 0, 0, 0, 6000
    e.DrawModel m2, -120, 0, 100
    e.DrawModel m3, 130, 0, 150, 0, 0, 0
    e.Flush
    Shot "models"
    cv.Cls 0
    e.Begin 3000
    e.DrawModel m, 0, 0, 0, 6000, 3000, 1000, 1, 2, 3, 0
    e.DrawModelF m2, -120 * 65536 + 30000, 0, 100 * 65536, 20000
    e.RotYPR rot, 1000, 2000, 3000
    e.DrawModelM m3, 130, 0, 150, rot
    e.Flush
    Shot "rotated"

    ' arrays and a file
    vx(0) = -50: vy(0) = 0: vz(0) = 0
    vx(1) = 0: vy(1) = 90: vz(1) = 0
    vx(2) = 50: vy(2) = 0: vz(2) = 0
    vx(3) = 0: vy(3) = 0: vz(3) = 60
    fn(0) = 3: fi(0) = 0: fi(1) = 1: fi(2) = 2: fc(0) = 4
    fn(1) = 3: fi(4) = 2: fi(5) = 1: fi(6) = 3: fc(1) = Not RGB(255, 128, 0)
    k = e.ModelFromArrays(vx, vy, vz, 4, fn, fi, fc, 2)
    ' a model file (written here, so the test needs no other files)
    Open "e3crate.mdl" For Output As #1
    Print #1, "# a crate with a lid, for engine3d.bas"
    Print #1, "box body shade -20 20 0 30 -20 20"
    Print #1, "v -10 30 -10      # 8"
    Print #1, "v  10 30 -10"
    Print #1, "v  10 40 -10"
    Print #1, "v -10 40 -10"
    Print #1, "f 5 8 11 10 9     # a fin, as given"
    Close #1
    i = e.ModelLoad("e3crate.mdl")
    Kill "e3crate.mdl"
    Print "arrays"; k; e.ModelFaces(k); " file"; i; e.ModelVerts(i); e.ModelFaces(i)
    cv.Cls 0
    e.Begin 3000
    e.DrawModel k, -60, 0, 0, 1000
    e.DrawModel i, 80, 0, 0, 5000, 0, 0, 13, 14
    e.Flush
    Shot "arrays+file"
    ids(0) = m: ids(1) = m2: ids(2) = m3
    For i = 0 To 2
        px(i) = (i - 1) * 140 * 65536: py(i) = 0: pz(i) = 200 * 65536: yw(i) = i * 9000
    Next i
    cv.Cls 0
    e.Begin 3000
    e.DrawModels 3, ids, px, py, pz, yw, True
    e.Flush
    Shot "batch"

    ' ---- quads, polygons, spots, lines, points
    e.Palette12 Array(&H000, &HFFF, &H122, &H99A, &H58A, &H353, &H575, &H887, &H554)
    e.SkyGradient 4, RGB(30, 60, 90), RGB(180, 200, 220), 100
    cv.Cls 0
    e.Clear 4
    e.Begin 3000
    For k = -1000 To 1000 Step 200
        e.QuadW 32000, 6, k - 3, 0, -1000, k + 3, 0, -1000, k + 3, 0, 1000, k - 3, 0, 1000
    Next k
    e.QuadW -1, 7, -200, 0, 400, 200, 0, 400, 200, 70, 400, -200, 70, 400
    xs(0) = -20: ys(0) = 0: zs(0) = 500
    xs(1) = 20: ys(1) = 0: zs(1) = 500
    xs(2) = 0: ys(2) = 40: zs(2) = 500
    e.Poly 450, 8, xs, ys, zs, 3
    e.PolyW -4, 5, xs, ys, zs, 3
    e.Quad 300, 3, -10, -10, 100, 10, -10, 100, 10, 10, 100, -10, 10, 100
    For i = 0 To 1
        For k = 0 To 11
            co(i * 12 + k) = Choose(k + 1, -300, 0, 600, -250, 0, 600, -250, 90, 600, -300, 90, 600) + i * 400 * (1 - (k Mod 3 <> 0))
        Next k
    Next i
    pens(0) = 2: pens(1) = 3
    e.QuadsW 2, -1, pens, co
    e.Spot 0, 40, 200, 6, 1, -4
    e.Star 40, 40, 250, 12, 8, 4, 1500
    e.Line3D -100, 5, 100, 100, 5, 300, 1
    For k = 0 To 11: lc(k) = Choose(k + 1, -50, 100, 200, 50, 100, 200, 50, 100, 200, 50, 0, 200): Next k
    e.Lines3D 2, lc, 3
    For i = 0 To 99
        px(i) = (i * 37) Mod 600 - 300: py(i) = 30 + (i * 13) Mod 80: pz(i) = 100 + (i * 71) Mod 900: pc(i) = 1 + (i And 3)
    Next i
    e.Points 100, px, py, pz, pc, 2
    e.Points 50, px, py, pz, 1, -3
    e.Flush
    Shot "scene"
    Print "horizon"; e.Horizon; " pen4 "; Hex$(e.Pen(4)); " "; Hex$(e.PenColor(-1 - RGB(1, 2, 3)))

    ' ---- CamSet, QuadBias, ModelMargin, DrawLine3D
    e.CamSet 0, 60, -300, 0, 2000
    Print "camset"; e.CamX; e.CamU; e.CamPitch;
    e.CamSet 10, 60, -300, 0, 2000, 9, 0, 3
    Print e.CamU; e.CamNear
    e.Xform 100, 0, 0, ox, oy, oz
    Print "xform"; ox; oy; oz
    e.CamSet 0, 60, -300, 0, 2000
    e.QuadBias = 100
    e.ModelMargin = 50
    Print "bias"; e.QuadBias; e.ModelMargin
    cv.Cls 0
    e.Begin 3000
    e.QuadW -1, 7, -200, 0, 400, 200, 0, 400, 200, 70, 400, -200, 70, 400
    e.QuadW -2, 5, -50, 0, 300, 50, 0, 300, 50, 60, 500, -50, 60, 500
    e.QuadW -3, 6, -50, 0, 200, 50, 0, 200, 50, 60, 200, -50, 60, 200
    e.DrawModel m, 900, 0, 0
    e.DrawModel m, 0, 0, 100
    e.Flush
    e.DrawLine3D -300, 0, -500, 300, 0, 900, 1
    e.DrawLine3D -30000, 10, 100, 30000, 10, 100, 2
    Shot "bias"
    e.QuadBias = 0
    e.ModelMargin = 800

    ' ---- terrain
    g = e.GridNew(33, 33, 40, -640, 0)
    e.GridGenerate g, 7, 140, 120
    e.GridColours g, -20, 4, 5, 6, 60, 1
    Print "grid"; g; " h"; e.GridHeight(g, 0, 300 * 65536); e.GridHeightF(g, 5 * 65536, 300 * 65536); e.GridHeight(g, -9999 * 65536, 0)
    e.CamPos 0, 160, -100
    e.CamAngles 0, 4000
    cv.Cls 0
    e.Begin 3000
    e.DrawGrid g
    e.Flush
    Shot "terrain"
    cv.Cls 0
    e.Begin 3000
    e.DrawGrid g, 400
    e.Flush
    Shot "window"
    For i = 0 To 15: hx(i) = (i Mod 4) * 10: Next i
    k = e.GridNew(4, 4, 50, -100, 100)
    e.GridSet k, hx
    e.GridPenSet k, 1, 1, 8
    e.GridShade k, False
    cv.Cls 0
    e.Begin 3000
    e.DrawGrid k
    e.Flush
    Shot "flat grid"
    Print "gh"; e.GridHeight(k, -75 * 65536, 150 * 65536)

    ' ---- shading, fog, roll, Sub 2
    e.Shading = True
    e.Light 1, 2, -1, 40
    e.CamPos 0, 60, -300
    e.CamAngles 0, 2000
    cv.Cls 0
    e.Begin 3000
    e.DrawModel m, 0, 0, 0, 6000
    e.DrawModel m3, 130, 0, 150
    e.Flush
    Shot "shaded"
    e.Fog RGB(100, 100, 120), 100, 700
    cv.Cls 0
    e.Begin 3000
    e.DrawGrid g
    e.Flush
    Shot "fog"
    e.Fog -1
    e.Shading = False
    e.CamAngles 0, 2000, 5000
    Print "roll"; e.CamRoll
    cv.Cls 0
    e.Begin 3000
    e.DrawModel m, 0, 0, 0, 6000
    e.Flush
    Shot "roll"
    e.CamAngles 0, 2000
    cv.Resize 640, 512
    e.Sub = 2
    cv.Cls 0
    e.Begin 3000
    e.DrawModel m, 0, 0, 0, 6000
    e.Flush
    e.Text 4, 4, "SUB 2", 1
    Shot "sub2"
    e.Sub = 1
    cv.Resize 320, 256

    ' ---- text and 2D
    cv.Cls 0
    e.Text 2, 2, "Hello 3D!", 1
    e.TextShadow 2, 20, "Big", 3, 2
    e.TextCentre 60, "centre", 1
    e.Span 100, 10, 50, 3
    e.FillRect 10, 110, 30, 120, 5
    xs(0) = 100: ys(0) = 100: xs(1) = 150: ys(1) = 110: xs(2) = 120: ys(2) = 150
    e.PolyFill xs, ys, 3, 6
    e.Blend 100, 0, 319, 1, 128
    e.ViewOrigin 50, 50
    e.Text 0, 0, "origin", 1
    e.ViewOrigin 0, 0
    Shot "text"
    Print "width"; e.TextWidth("abc"); e.TextWidth("abc", 3); " pixel "; Hex$(cv.Point(2 + 1, 2 + 5))

    ' ---- errors
    On Error Resume Next
    e.DrawModel 99, 0, 0, 0
    Print "bad model"; Err.Number: Err.Clear
    e.Poly 0, 1, xs, ys, zs, 2
    Print "bad n"; Err.Number: Err.Clear
    e.Poly 0, 1, xs, ys, zs, 8
    Print "short array"; Err.Number: Err.Clear
    e.Attach 5
    Print "attach"; Err.Number: Err.Clear
    i = e.ModelLoad("missing.mdl")
    Print "missing"; Err.Number: Err.Clear
    e.Frob
    Print "member"; Err.Number: Err.Clear
    Dim e2 As Object
    Set e2 = CreateObject("Boing.Engine3D")
    e2.Flush
    Print "no canvas"; Err.Number: Err.Clear
End Sub
