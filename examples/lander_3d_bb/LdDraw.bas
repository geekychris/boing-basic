' Lander 3D - the picture (render.c of the original) through the Engine3D object
' (docs/engine3d.md, the amiga3d engine in C): the terrain round the craft as a grid,
' each cell shaded by its slope as render.c shades it, the pads, the lander tilted by
' its pitch and roll with its exhaust and shadow, the painted sky, and the HUD.
'
' The game keeps the original's 320 x 256 coordinates; the engine draws them at
' 640 x 512 (Sub 2), as the AmigaOS 4 original does. World units for the engine: 16
' to the metre (the simulation is 16.16 metres; >> 12 turns one into the other).
Option Explicit

Public Const VIEW_H As Long = 216
Public Const PEN_SKY As Long = 4
Public Const PEN_GROUND As Long = 5
Public Const PEN_RING As Long = 11
Public Const PEN_PAD As Long = 14
Public Const PEN_SHADOW As Long = 15
Public Const PEN_GOLD As Long = 16
Public Const PEN_STAGE As Long = 18
Public Const PEN_LEGS As Long = 20
Public Const PEN_FLAME As Long = 21
Public Const PEN_RED As Long = 23
Public Const PEN_AMBER As Long = 24
Public Const PEN_GREEN As Long = 25
Public Const PEN_CYAN As Long = 26
Public Const PEN_STAR As Long = 27
Public Const PEN_HUD As Long = 28

Private Const TITLE_ART_FRAMES As Long = 250      ' 10 s
Private Const TITLE_DEMO_FRAMES As Long = 375
Private Const MARGIN As Long = 32                 ' mirrored cells round the map

Public e As Object                                ' the engine
Public groundWin As Long                          ' terrain cells each side of the centre
Public polyTotal As Double                        ' polygons drawn (bench)
Public showPerf As Boolean
Public entryRank As Long

Private cvw As Object
Private craft As Long, grid As Long, gridWorld As Long, gridSeed As Long, gridN As Long
Private gridCell As Long, gridX0 As Long
Private camBack As Long, camUp As Long
Private camX As Long, camY As Long, camZ As Long
Private padDepth(0 To 2) As Long
Private skyImg(0 To 2) As Long, titleImg As Long, artTried As Boolean
Private skySink(0 To 2) As Long, plainFar(0 To 2) As Long, plainNear(0 To 2) As Long, skyTop(0 To 2) As Long
Private pal(0 To 2) As Variant
Private ox(0 To 7) As Long, oy(0 To 7) As Long, oz(0 To 7) As Long
Private wx(0 To 7) As Long, wy(0 To 7) As Long, wz(0 To 7) As Long
Private helpText(1 To 2) As Variant

' fix metres -> engine units (>> 12)
Private Function U(ByVal f As Long) As Long
    U = (f - (f And 4095)) \ 4096
End Function

Private Function Hex24(ByVal c As Long) As Long        ' &HRRGGBB -> VB colour
    Hex24 = RGB((c \ 65536) And 255, (c \ 256) And 255, c And 255)
End Function

Public Sub DrawInit(cv As Object)
    Set cvw = cv
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.Sub = 2
    groundWin = 20
    camBack = 480
    camUp = 160
    gridWorld = -1
    ' 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5-10 ground (light to dark), 11-13 pad
    ' rings x1 x2 x5, 14 pad, 15 shadow, 16-17 gold foil, 18-19 the ascent stage, 20
    ' legs, 21-22 flame, 23 red, 24 amber, 25 green, 26 cyan, 27 stars, 28 HUD grey,
    ' 29 dust, 30 haze, 31 near black
    pal(0) = Array(&H0, &HFFF, &H223, &H99A, &H0, &HCCC, &HAAA, &H999, &H777, &H555, &H333, _
                   &H3E5, &HFE3, &HE3E, &H445, &H111, &HEB3, &H973, &HCCD, &H889, &H444, &HFF8, &HF82, _
                   &HF33, &HFB2, &H4E4, &H3DF, &H888, &H99A, &HBBB, &H334, &H111)
    pal(1) = Array(&H0, &HFFF, &H322, &HA99, &HC85, &HD96, &HC75, &HA64, &H853, &H642, &H431, _
                   &H3E5, &HFE3, &HE3E, &H544, &H211, &HEB3, &H973, &HCCD, &H889, &H444, &HFF8, &HF82, _
                   &HF33, &HFB2, &H4E4, &H3DF, &HA88, &HA99, &HC97, &HB86, &H111)
    pal(2) = Array(&H0, &HFFF, &H223, &H99A, &H0, &HA98, &H987, &H876, &H765, &H543, &H332, _
                   &H3E5, &HFE3, &HE3E, &H444, &H111, &HEB3, &H973, &HCCD, &H889, &H444, &HFF8, &HF82, _
                   &HF33, &HFB2, &H4E4, &H3DF, &H888, &H99A, &HA98, &H333, &H111)
    skySink(0) = 48: skySink(1) = 0: skySink(2) = 16
    plainFar(0) = Hex24(&H3A3A3E): plainFar(1) = Hex24(&HC08458): plainFar(2) = Hex24(&H3C3630)
    plainNear(0) = Hex24(&H8A8A8A): plainNear(1) = Hex24(&H7A4628): plainNear(2) = Hex24(&H6E6252)
    ' the panoramas' top rows (above the picture the top row goes on)
    skyTop(0) = RGB(5, 5, 6): skyTop(1) = RGB(136, 68, 34): skyTop(2) = RGB(13, 9, 36)
    ' the lander: the descent stage in gold foil, the ascent stage on top, four legs
    ' and feet, the engine bell underneath (16 units to the metre)
    craft = e.ModelNew()
    e.MdlBox craft, PEN_GOLD, PEN_GOLD + 1, -24, 24, -14, 8, -24, 24
    e.MdlBox craft, PEN_STAGE, PEN_STAGE + 1, -16, 16, 8, 30, -14, 18
    e.MdlBox craft, PEN_STAGE + 1, PEN_STAGE + 1, -4, 4, 30, 36, -4, 4
    e.MdlBox craft, PEN_LEGS, PEN_LEGS, 30, 34, -32, -6, 30, 34
    e.MdlBox craft, PEN_LEGS, PEN_LEGS, -34, -30, -32, -6, 30, 34
    e.MdlBox craft, PEN_LEGS, PEN_LEGS, 30, 34, -32, -6, -34, -30
    e.MdlBox craft, PEN_LEGS, PEN_LEGS, -34, -30, -32, -6, -34, -30
    e.MdlPyramid craft, PEN_LEGS, PEN_LEGS, -12, 12, -14, -12, 12, -26
    helpText(1) = Array("THE MAIN ENGINE PUSHES ALONG THE", "LANDER'S OWN UP: TIP IT TO MOVE", _
        "SIDEWAYS, LEVEL IT TO STOP, AND KEEP", "ENOUGH THRUST ON TO STOP GRAVITY.", _
        "TOUCH DOWN WITH EVERY LEG ON A PAD:", "SLOW (GREEN V/S), NOT SLIDING (H/S)", _
        "AND NEARLY LEVEL (TILT).", "", "GREEN PAD x1   YELLOW x2   MAGENTA x5", _
        "SCORE (100 + SOFTNESS + FUEL) x PAD", "SAFE OFF A PAD: 25. ELSE: A SHIP LOST.", _
        "MARS HAS WIND. THE ASTEROID: DELICATE.")
    helpText(2) = Array("SPACE / FIRE   FULL THRUST", "Q / E          STEADY THROTTLE - / +", _
        "UP / W         TIP FORWARD", "DOWN / S       TIP BACK", "LEFT / A       TIP LEFT", _
        "RIGHT / D      TIP RIGHT", "P / B          PAUSE / AUTOPILOT", "HELP / H       THESE PAGES", _
        "M / N          MUSIC / SOUND ON, OFF", "ESC            TITLE / QUIT", _
        "THE ARROW AT THE TOP POINTS TO THE", "NEAREST PAD. THE SHADOW SHOWS HEIGHT.")
End Sub

' a picture beside the program: PNG (AmigaOS 4), else the PPM tools/make_art.py makes
Private Function LoadArt(ByVal nm As String) As Long
    Dim p As String
    p = GameDir()
    On Error Resume Next
    LoadArt = cvw.LoadImage(p & "art/" & nm & ".png")
    If Err.Number <> 0 Then
        Err.Clear
        LoadArt = cvw.LoadImage(p & "art/" & nm & ".ppm")
        If Err.Number <> 0 Then LoadArt = 0
    End If
    Err.Clear
    On Error GoTo 0
End Function

Private Sub LoadAllArt()
    If artTried Then Exit Sub
    artTried = True
    titleImg = LoadArt("lander_title")
    skyImg(0) = LoadArt("sky_moon")
    skyImg(1) = LoadArt("sky_mars")
    skyImg(2) = LoadArt("sky_asteroid")
    If gLog Then Print "art: title " & titleImg & ", skies " & skyImg(0) & " " & skyImg(1) & " " & skyImg(2)
End Sub

' the world's pens (after a new level)
Public Sub DrawPalette(ByVal world As Long)
    e.Palette12 pal(world)
    If world = W_MARS Then
        e.SkyGradient PEN_SKY, Rgb12(&H632), Rgb12(&HC96), 110
    Else
        e.SkyGradient PEN_SKY, 0, 0, 0
    End If
End Sub

Private Function Rgb12(ByVal c As Long) As Long
    Rgb12 = RGB(((c \ 256) And 15) * 17, ((c \ 16) And 15) * 17, (c And 15) * 17)
End Function

' ---------- the ground ----------

Private Function Mirror(ByVal i As Long, ByVal n As Long) As Long
    Dim p As Long
    p = 2 * (n - 1)
    i = i Mod p
    If i < 0 Then i = i + p
    If i > n - 1 Then Mirror = p - i Else Mirror = i
End Function

' the level's terrain as an engine grid, with MARGIN mirrored cells round it (the
' AmigaOS 4 original draws the map's mirror image past its edges, to the horizon);
' each cell gets render.c's slope pen
Private Sub BuildGrid()
    Dim n As Long, g As Long, i As Long, j As Long, k As Long, cell As Long
    Dim ha As Long, hb As Long, hc As Long, hd As Long, slope As Long, p As Long
    Dim mi(0 To 300) As Long
    n = tN
    g = n + 2 * MARGIN
    cell = U(tCell)
    Dim hts() As Long, pens() As Long, hu() As Long
    ReDim hts(0 To g * g - 1)
    ReDim pens(0 To (g - 1) * (g - 1) - 1)
    ReDim hu(0 To n * n - 1)
    For k = 0 To n * n - 1
        hu(k) = U(tH(k))
    Next k
    For i = 0 To g - 1
        mi(i) = Mirror(i - MARGIN, n)
    Next i
    For j = 0 To g - 1
        For i = 0 To g - 1
            hts(j * g + i) = hu(mi(j) * n + mi(i))
        Next i
    Next j
    For j = 0 To g - 2
        For i = 0 To g - 2
            ha = hts(j * g + i)
            hb = hts(j * g + i + 1)
            hc = hts((j + 1) * g + i + 1)
            hd = hts((j + 1) * g + i)
            ' lit from the left and behind: brighter facing -x and -z
            slope = ((ha + hd) - (hb + hc)) + ((ha + hb) - (hc + hd)) \ 2
            p = 2 - slope \ (cell \ 3 + 1)
            If p < 0 Then p = 0
            If p > 5 Then p = 5
            pens(j * (g - 1) + i) = PEN_GROUND + p
        Next i
    Next j
    If grid <> 0 Then e.GridFree grid
    gridX0 = U(-tHalf) - MARGIN * cell
    grid = e.GridNew(g, g, cell, gridX0, gridX0)
    e.GridSet grid, hts, pens
    e.GridShade grid, False                       ' render.c's pens as they are, a quad a cell
    gridN = g
    gridCell = cell
End Sub

Private Sub Ground()
    If gridWorld <> ld.world Or gridSeed <> ld.seed Then
        BuildGrid
        gridWorld = ld.world
        gridSeed = ld.seed
    End If
    ' the cells within groundWin (and half that again ahead) of the craft's cell
    e.DrawGrid grid, (groundWin * 3 \ 2) * gridCell
End Sub

' an octagon lying on the ground; returns the depth it was sorted at (-1: not drawn);
' atDepth >= 0 sorts it there instead
Private Function Octagon(ByVal cx As Long, ByVal cz As Long, ByVal r As Long, ByVal lift As Long, _
                         ByVal col As Long, ByVal bias As Long, ByVal atDepth As Long) As Long
    Dim k As Long, a As Long, y As Long, depth As Long
    y = U(LdHeight(cx * 4096, cz * 4096)) + lift
    depth = &H7FFFFFFF
    For k = 0 To 7
        a = k * 8192 + 4096
        wx(k) = cx + ShrA(A3Sin(a) * r, 16)
        wy(k) = y
        wz(k) = cz + ShrA(A3Cos(a) * r, 16)
    Next k
    e.XformMany 8, wx, wy, wz, ox, oy, oz
    For k = 0 To 7
        If oz(k) < depth Then depth = oz(k)
    Next k
    If oz(0) < 12 And oz(4) < 12 Then
        Octagon = -1
        Exit Function
    End If
    ' sorted at its nearest point, half a cell nearer still: lying flat on the ground,
    ' it would otherwise lose its near half to the cells under it
    If atDepth >= 0 Then depth = atDepth Else depth = depth - U(tCell) \ 2 - bias
    If depth < 0 Then depth = 0
    e.Poly depth, col, ox, oy, oz, 8
    Octagon = depth
End Function

Private Sub Pads()
    Dim k As Long, d As Long, dd As Long
    For k = 0 To 2
        d = Octagon(U(padX(k)), U(padZ(k)), U(padR(k)), 2, PEN_RING + k, 4, -1)
        padDepth(k) = d
        If d >= 0 Then
            If d > 0 Then dd = d - 1 Else dd = 0
            Octagon U(padX(k)), U(padZ(k)), (U(padR(k)) * 3) \ 4, 3, PEN_PAD, 0, dd     ' just in front of its ring
        End If
    Next k
End Sub

' ---------- the craft ----------

Private Sub CraftDraw()
    Dim px As Long, py As Long, pz As Long, k As Long, over As Long, bias As Long
    Dim dx As Long, dz As Long, reach As Long, vx As Long, vy As Long, vz As Long, at As Long
    Dim ln As Long, bx As Long, by As Long, bz As Long
    px = U(ld.px): py = U(ld.py): pz = U(ld.pz)
    over = -1
    bias = 30
    ' over a pad? The pad sorts at its nearest point, so the craft and its shadow have
    ' to come in front of that
    For k = 0 To 2
        dx = px - U(padX(k))
        dz = pz - U(padZ(k))
        reach = U(padR(k)) + 48
        If padDepth(k) >= 0 And dx > -reach And dx < reach And dz > -reach And dz < reach Then over = k
    Next k
    If over >= 0 Then
        e.Xform px, py, pz, vx, vy, vz
        If vz - (padDepth(over) - 4) > bias Then bias = vz - (padDepth(over) - 4)
    End If
    ' the shadow, straight down
    at = -1
    If over >= 0 Then
        If padDepth(over) > 2 Then at = padDepth(over) - 2
    End If
    Octagon px, pz, 40, 3, PEN_SHADOW, 8, at
    e.DrawModel craft, px, py, pz, 0, A3Angle(ld.pitch), A3Angle(ld.roll), 0, 0, 0, bias
    ' the exhaust: a flickering cone along -up, as long as the throttle
    If ld.thr > 0 And ld.outcome = 0 Then
        ln = 30 + ShrA(ld.thr * 70, 16) + ((gFrame * 7) Mod 9)
        bx = px: by = py - 24: bz = pz
        LdUp
        wx(0) = bx - 8: wy(0) = by: wz(0) = bz
        wx(1) = bx + 8: wy(1) = by: wz(1) = bz
        wx(2) = bx - ShrA(upX * ln, 16): wy(2) = by - ShrA(upY * ln, 16): wz(2) = bz - ShrA(upZ * ln, 16)
        e.XformMany 3, wx, wy, wz, ox, oy, oz
        e.Poly oz(2) - 40, PEN_FLAME + (1 - (gFrame And 1)), ox, oy, oz, 3
    End If
End Sub

' ---------- the sky: the world's painted panorama, its bottom edge on the horizon,
' drifting as the lander flies across; below it a plain fading into the distance ----------

Private Sub Sky()
    Dim hz As Long, im As Long, w As Long, h As Long, top As Long, y0 As Long, y1 As Long
    Dim sx As Long, sy As Long, rows As Long, x As Long, n As Long, py As Long, p1 As Long, t As Long
    Dim cf As Long, cn As Long, rr As Long, gg As Long, bb As Long
    hz = e.Horizon
    If hz < 0 Then hz = 0
    If hz > VIEW_H Then hz = VIEW_H
    im = skyImg(ld.world)
    If im <> 0 And hz > 0 Then
        w = cvw.ImageWidth(im)
        h = cvw.ImageHeight(im)
        top = hz * 2 + skySink(ld.world) - h
        y1 = hz * 2 - 1
        y0 = 0
        If top > 0 Then
            cvw.Box 0, 0, 640, top, skyTop(ld.world)
            y0 = top
        End If
        sy = y0 - top
        rows = y1 - y0 + 1
        If sy + rows > h Then rows = h - sy
        sx = (camX \ 6) Mod w
        If sx < 0 Then sx = sx + w
        x = 0
        Do While x < 640 And rows > 0
            n = w - sx
            If n > 640 - x Then n = 640 - x
            cvw.DrawImagePart im, sx, sy, n, rows, x, y0, True
            x = x + n
            sx = 0
        Loop
    ElseIf hz > 0 Then
        e.FillRect 0, 0, 319, hz - 1, IIf(ld.world = W_MARS, PEN_SKY, 0)
    End If
    ' beyond the terrain drawn: a plain to the horizon (g_fill_grad, two rows a band)
    cf = plainFar(ld.world)
    cn = plainNear(ld.world)
    p1 = VIEW_H * 2 - 1
    n = p1 - hz * 2
    For py = hz * 2 To p1 Step 2
        If n > 0 Then t = ((py - hz * 2) * 256) \ n Else t = 0
        rr = (cf And 255) + (((cn And 255) - (cf And 255)) * t) \ 256
        gg = ((cf \ 256) And 255) + ((((cn \ 256) And 255) - ((cf \ 256) And 255)) * t) \ 256
        bb = ((cf \ 65536) And 255) + ((((cn \ 65536) And 255) - ((cf \ 65536) And 255)) * t) \ 256
        cvw.Box 0, py, 640, 2, RGB(rr, gg, bb)
    Next py
End Sub

Private Sub Camera()
    Dim agl As Long, back As Long, up As Long, g As Long, pitch As Long
    agl = LdAgl()
    ' closer in as the ground comes up
    If agl > FromI(40) Then
        back = 480
        up = 160
    Else
        back = 224 + FInt(agl) * 6
        up = 72 + FInt(agl) * 2
    End If
    If ld.outcome <> 0 Then
        back = 300
        up = 110
    End If
    camBack = camBack + (back - camBack) \ 8
    camUp = camUp + (up - camUp) \ 8
    camX = U(ld.px)
    camY = U(ld.py) + camUp
    camZ = U(ld.pz) - camBack
    ' don't go into a hill
    g = U(LdHeight(camX * 4096, camZ * 4096)) + 40
    If camY < g Then camY = g
    pitch = A3Atan2(camY - U(ld.py) + 40, camBack)      ' looking down at the craft
    If pitch < 600 Then pitch = 600
    e.View 320, VIEW_H, 160, 116, 200                    ' the craft a little low: more sky
    e.CamPos camX, camY, camZ
    e.CamAngles 0, pitch
End Sub

' ---------- the HUD ----------

Private Function LimitPen(ByVal v As Long, ByVal lim As Long) As Long
    If v <= MulShr(lim, 45875, 16) Then
        LimitPen = PEN_GREEN
    ElseIf v <= lim Then
        LimitPen = PEN_AMBER
    Else
        LimitPen = PEN_RED
    End If
End Function

Private Sub Txt(ByVal x As Long, ByVal y As Long, ByVal p As Long, ByVal s As String)
    e.Text x, y - 7, s, p                  ' y: the baseline, as g_text
End Sub

Private Sub TxtShadow(ByVal x As Long, ByVal y As Long, ByVal p As Long, ByVal s As String)
    e.TextShadow x, y - 7, s, p
End Sub

Private Sub TxtCentre(ByVal y As Long, ByVal p As Long, ByVal s As String)
    e.TextCentre y - 7, s, p
End Sub

Private Sub Compass()
    Dim k As Long, a As Long, cx As Long, cy As Long, d As Long, wa As Long, s As Long, c As Long
    Dim xs(0 To 2) As Long, ys(0 To 2) As Long
    k = LdNearestPad(False)
    cx = 160: cy = 18
    d = FHypot(padX(k) - ld.px, padZ(k) - ld.pz)
    a = A3Atan2(ShrA(padX(k) - ld.px, 4), ShrA(padZ(k) - ld.pz, 4))
    xs(0) = cx + ShrA(A3Sin(a) * 12, 16): ys(0) = cy - ShrA(A3Cos(a) * 12, 16)
    xs(1) = cx + ShrA(A3Sin(a + 26000) * 7, 16): ys(1) = cy - ShrA(A3Cos(a + 26000) * 7, 16)
    xs(2) = cx + ShrA(A3Sin(a - 26000) * 7, 16): ys(2) = cy - ShrA(A3Cos(a - 26000) * 7, 16)
    e.PolyFill xs, ys, 3, PEN_RING + k
    TxtShadow cx + 16, cy + 4, PEN_RING + k, FInt(d) & "M"
    If ld.pWind <> 0 Then
        wa = A3Atan2(ShrA(ld.wind0, 4), ShrA(ld.wind1, 4))
        s = ShrA(A3Sin(wa) * 10, 16)
        c = ShrA(A3Cos(wa) * 10, 16)
        If s >= 0 Then e.FillRect 290 - s, 18, 290 + s, 18, PEN_HUD Else e.FillRect 290 + s, 18, 290 - s, 18, PEN_HUD
        e.FillRect 290 + s, 18 - c, 290 + s, 18, PEN_HUD
        TxtShadow 278, 32, PEN_HUD, "WIND"
    End If
End Sub

Private Sub Hud()
    Dim w As Long, vs As Long, hs As Long, tilt As Long, agl As Long, fuel As Long, fm As Long, a As Long
    w = ld.world
    vs = -ld.vy
    hs = FHypot(ld.vx, ld.vz)
    tilt = LdTilt()
    agl = LdAgl()
    If ld.fuelMax <> 0 Then fm = ld.fuelMax Else fm = 1
    fuel = ShrA(MulDiv(ld.fuel, 65536, fm) * 100, 16)
    e.FillRect 0, VIEW_H, 319, 255, 2
    If agl < 0 Then a = 0 Else a = FInt(agl)
    Txt 4, VIEW_H + 12, 1, "ALT " & Right$("   " & a, 4)
    Txt 4, VIEW_H + 24, IIf(vs > 0, LimitPen(vs, wLimVs(w)), PEN_GREEN), "V/S " & Dec1(vs)
    Txt 4, VIEW_H + 36, LimitPen(hs, wLimHs(w)), "H/S " & Dec1(hs)
    Txt 100, VIEW_H + 12, LimitPen(tilt, wLimTilt(w)), "TILT " & Right$(" " & FInt(MulShr(tilt, 3754936, 16)), 2)
    Txt 100, VIEW_H + 24, PEN_HUD, "THR " & Right$("  " & ShrA(ld.thr * 100, 16), 3) & "%"
    Txt 100, VIEW_H + 36, PEN_HUD, "FUEL"
    e.FillRect 140, VIEW_H + 30, 190, VIEW_H + 35, 0
    If fuel > 0 Then e.FillRect 140, VIEW_H + 30, 140 + fuel \ 2, VIEW_H + 35, IIf(fuel < 20, PEN_RED, PEN_AMBER)
    Txt 200, VIEW_H + 12, 1, "SCORE " & gScore
    Txt 200, VIEW_H + 24, PEN_CYAN, wName(w) & " " & ld.lvl
    Txt 200, VIEW_H + 36, PEN_HUD, "SHIPS " & gShips
End Sub

Private Sub Scene()
    Camera
    Sky
    e.Begin 8000
    Ground
    Pads
    CraftDraw
    e.Flush
    polyTotal = polyTotal + e.NPolys
    e.View 320, 256, 160, 116, 200                       ' 2D: the whole picture
    Compass
End Sub

Private Sub Box2(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal fill As Long, ByVal edge As Long)
    e.FillRect x0, y0, x1, y1, fill
    e.FillRect x0, y0, x1, y0, edge
    e.FillRect x0, y1, x1, y1, edge
    e.FillRect x0, y0, x0, y1, edge
    e.FillRect x1, y0, x1, y1, edge
End Sub

Public Sub DrawGame()
    Dim col As Long
    LoadAllArt
    Scene
    Hud
    If gState = LS_RESULT Or gState = LS_OVER Then
        If ld.outcome = OUT_LANDED Then
            col = PEN_GREEN
        ElseIf ld.outcome = OUT_OFFPAD Then
            col = PEN_AMBER
        Else
            col = PEN_RED
        End If
        Box2 24, 60, 296, 140, 2, col
        e.Text (320 - Len(gMsg) * 16) \ 2, 70, gMsg, col, 2
        TxtCentre 104, 1, gMsg2
        If gState = LS_OVER Then
            TxtCentre 124, PEN_RED, "GAME OVER"
        ElseIf ld.outcome = OUT_LANDED Or ld.outcome = OUT_OFFPAD Then
            TxtCentre 124, PEN_AMBER, "+" & gLastScore
        End If
    End If
    If gPaused Then TxtCentre 100, 1, "PAUSED"
End Sub

Private Function MenuName() As String
    MenuName = "<  " & Choose(gMenu + 1, "MOON", "MARS", "ASTEROID", "TOUR") & "  >"
End Function

' the painted title in turn with the autopilot's demo
Public Sub DrawTitle()
    LoadAllArt
    If titleImg <> 0 And (gFrame - gTitleFrame0) Mod (TITLE_ART_FRAMES + TITLE_DEMO_FRAMES) < TITLE_ART_FRAMES Then
        cvw.DrawImage titleImg, 0, 0, True
        e.View 320, 256, 160, 116, 200
        TxtCentre 214, PEN_AMBER, MenuName()
        TxtCentre 230, IIf((gFrame And 16) <> 0, PEN_GREEN, 1), "PRESS FIRE TO START"
        TxtCentre 246, PEN_HUD, "BEST " & gBest & "    HELP: HOW TO FLY"
        Exit Sub
    End If
    Scene
    e.Text 42, 30, "LANDER 3D", 0, 3
    e.Text 40, 28, "LANDER 3D", 1, 3
    TxtCentre 150, PEN_AMBER, MenuName()
    TxtCentre 170, IIf((gFrame And 16) <> 0, PEN_GREEN, 1), "PRESS FIRE TO START"
    TxtCentre 184, PEN_HUD, "HELP: HOW TO FLY   F2: HIGH SCORES"
    e.FillRect 0, VIEW_H, 319, 255, 2
    Txt 8, VIEW_H + 16, PEN_AMBER, "BEST " & gBest
    Txt 8, VIEW_H + 32, PEN_HUD, "THE AUTOPILOT IS FLYING THE DEMO"
End Sub

Public Sub DrawHelp(ByVal page As Long)
    Dim k As Long, lines As Variant
    e.View 320, 256, 160, 116, 200
    e.FillRect 0, 0, 319, 255, 0
    If page = 1 Then e.Text 80, 14, "HOW TO FLY", PEN_AMBER, 2 Else e.Text 96, 14, "CONTROLS", PEN_AMBER, 2
    lines = helpText(page)
    For k = 0 To 11
        Txt 8, 56 + k * 14, 1, lines(k)
    Next k
    Txt 8, 244, PEN_HUD, IIf(page = 1, "PAGE 1 OF 2", "PAGE 2 OF 2")
    Txt 156, 244, PEN_GREEN, "HELP: NEXT  FIRE: FLY"
End Sub

' (new) a name for the high scores, over the demo
Public Sub DrawEntry(ByVal nm As String)
    Scene
    e.View 320, 256, 160, 116, 200
    Box2 40, 70, 280, 180, 2, PEN_AMBER
    TxtCentre 92, PEN_AMBER, "A NEW HIGH SCORE"
    TxtCentre 112, 1, CStr(gScore)
    TxtCentre 136, PEN_HUD, "TYPE YOUR NAME"
    TxtCentre 156, PEN_GREEN, nm & IIf((gFrame And 8) <> 0, "_", " ")
    TxtCentre 174, PEN_HUD, "RETURN: DONE"
End Sub

Public Sub DrawScores()
    Dim i As Long, p As Long
    Scene
    e.View 320, 256, 160, 116, 200
    Box2 50, 36, 270, 200, 2, 3
    e.Text 64, 46, "HIGH SCORES", PEN_AMBER, 2
    For i = 0 To HS_COUNT - 1
        If i = entryRank Then p = PEN_GREEN Else p = 1
        TxtCentre 86 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf()
    e.View 320, 256, 160, 116, 200
    e.FillRect 0, 46, 319, 56, 0
    Txt 2, 55, PEN_GREEN, PerfText()
End Sub
