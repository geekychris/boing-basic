' ApDraw - Ace Pilot 2's picture (amiga_mcp's examples/ace_pilot2/render.c): the sky and the
' earth (tilted with the bank), the fields round the aeroplane in a patchwork, the river, the
' trenches and no-man's-land, the road and the railway, the aerodromes, the hills, the sheds,
' dumps, guns, balloons, the train and the lorries, the aeroplanes with their smoke, tracer,
' shell bursts, explosions and clouds; then the HUD (chase view) or the cockpit, the briefing
' with its map, the results, the title and the help. 320 x 256.
'
' The 3D is Boing.Engine3D: the camera banks (Engine3D's CamBank is render.c's xf), every
' model is drawn by the engine (hills, buildings, and the aeroplanes through DrawModelMF: at
' their 16.16 positions, with render.c's a3_rot_ypr >> 2 matrix for the quarter-unit model). The ground's flat pieces don't move, so they are kept as world quads in
' layers and handed to the engine in one QuadsW call a layer; the lists are made again only
' when the camera moves into another 400-unit cell. render.c makes them every frame.
Option Explicit

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky (gradient), 5 grass, 6-9 fields, 10 river,
' 11 mud and roads, 12 dark (rails, trenches), 13-14 hills, 15-16 timber, 17 roofs, 18-19 the
' Swallow, 20-21 Grauland slate, 22-23 the Falcon's silver, 24 balloon canvas, 25 smoke,
' 26 red, 27 yellow, 28 green, 29 blue, 30 fire, 31 shell smoke
Public Const PEN_PANEL As Long = 2
Public Const PEN_GREY As Long = 3
Public Const PEN_SKY As Long = 4
Public Const PEN_GRASS As Long = 5
Public Const PEN_FIELD As Long = 6
Public Const PEN_RIVER As Long = 10
Public Const PEN_MUD As Long = 11
Public Const PEN_DARK As Long = 12
Public Const PEN_HILL As Long = 13
Public Const PEN_WOOD As Long = 15
Public Const PEN_ROOF As Long = 17
Public Const PEN_SWALLOW As Long = 18
Public Const PEN_SLATE As Long = 20
Public Const PEN_SILVER As Long = 22
Public Const PEN_CANVAS As Long = 24
Public Const PEN_SMOKE As Long = 25
Public Const PEN_RED As Long = 26
Public Const PEN_YELLOW As Long = 27
Public Const PEN_GREEN As Long = 28
Public Const PEN_BLUE As Long = 29
Public Const PEN_FIRE As Long = 30
Public Const PEN_FLAK As Long = 31

' the screens and views (ace.h)
Public Const AS_TITLE As Long = 0
Public Const AS_BRIEF As Long = 1
Public Const AS_PLAY As Long = 2
Public Const AS_RESULT As Long = 3
Public Const AS_OVER As Long = 4
Public Const AS_ENTRY As Long = 5
Public Const AS_SCORES As Long = 6
Public Const VIEW_CHASE As Long = 0
Public Const VIEW_COCKPIT As Long = 1

Private Const CELL As Long = 400                ' the fields
Private Const VIEW_RANGE As Long = 3200
Private Const NEAR_LOD As Long = 900            ' aeroplanes nearer than this get every part
Private Const FAR_LOD As Long = 3000            ' beyond: a dot

' the shell's state the picture shows (ace.h's Ace)
Public acState As Long, acStateTimer As Long, acStartMission As Long, acAutoplay As Boolean, acPaused As Long
Public acHelp As Long, acView As Long, acInvert As Boolean, acFlash As String, acFlashTimer As Long, acFlashPen As Long
Public acHurtTimer As Long, acBest As Long, acResult As Long
Public acMScore As Long, acMKills As Long, acMGKills As Long, acMShots As Long, acMHits As Long
Public acCamYaw As Long, acEntryName As String, acEntryRank As Long, acTicks As Long
' explosions and smoke: world units
Public blT(0 To 11) As Long, blSize(0 To 11) As Long, blX(0 To 11) As Long, blY(0 To 11) As Long, blZ(0 To 11) As Long
Public puT(0 To 39) As Long, puSize(0 To 39) As Long, puX(0 To 39) As Long, puY(0 To 39) As Long, puZ(0 To 39) As Long
Public showPerf As Boolean
Public polyTotal As Double

Public e3 As Object
Private mPlane As Long, mPlaneLo As Long, mHill(0 To 15) As Long, mGt(0 To 6) As Long, mWreck As Long
Private planeLit(0 To 5) As Long, planeShade(0 To 5) As Long
Private camX As Long, camY As Long, camZ As Long, camYawV As Long, camRollV As Long   ' this frame's camera (whole units)
Private rc As Long, rs As Long, cfx As Long, cfz As Long
Private camCy As Long, camFov As Long, curView As Long

' the ground's layers: world quads (12 values each) for QuadsW
Private Const L_FIELDS As Long = 0
Private Const L_MUD As Long = 1
Private Const L_RIVER As Long = 2
Private Const L_RAIL As Long = 3
Private Const L_LOW As Long = 4                 ' trenches, the strips, the depot's yard
Private Const L_MARKS As Long = 5               ' the runway's ends
Private Const L_CLOUDS As Long = 6
Private qn(0 To 6) As Long
Private q0(0 To 3599) As Long, p0(0 To 299) As Long
Private q1(0 To 959) As Long, q2(0 To 959) As Long, q3(0 To 1199) As Long, q4(0 To 959) As Long
Private q5(0 To 47) As Long, q6(0 To 1199) As Long
Private keyCellX As Long, keyCellZ As Long, keyMission As Long, groundReady As Boolean
' the scenery that isn't a target this time, for DrawModels
Private scN As Long, scId(0 To 15) As Long, scX(0 To 15) As Long, scY(0 To 15) As Long, scZ(0 To 15) As Long, scYaw(0 To 15) As Long
Private hlId(0 To 15) As Long, hlXs(0 To 15) As Long, hlYs(0 To 15) As Long, hlZs(0 To 15) As Long
Private gnId(0 To 23) As Long, gnX(0 To 23) As Long, gnY(0 To 23) As Long, gnZ(0 To 23) As Long, gnYaw(0 To 23) As Long
Private bxs(0 To 47) As Long, bys(0 To 47) As Long, bzs(0 To 47) As Long, bps(0 To 47) As Long
Private rot(0 To 8) As Long, nx(0 To 3) As Long, ny(0 To 3) As Long
Private helpText(1 To 2, 0 To 12) As String

Public Sub DrawInit(cv As Object)
    Dim v As Variant, i As Long
    ApInit
    v = Array(&H0, &HFFF, &H221, &H998, &H69C, &H5A3, &H7B4, &HBB5, &H483, &HA86, &H48B, &H864, _
              &H433, &H7A5, &H584, &HA97, &H765, &H943, &H9A5, &H673, &H89A, &H567, &HDDE, &H99A, _
              &HDC9, &H888, &HE33, &HFE4, &H6E6, &H5AF, &HF93, &H333)
    GfxPalette v
    Set e3 = CreateObject("Boing.Engine3D")
    e3.Attach cv
    e3.Palette12 v
    e3.SkyGradient PEN_SKY, Rgb12(&H38B), Rgb12(&HBDE), 150
    curView = -1
    acStartMission = 1
    v = Array(PEN_SWALLOW, PEN_CANVAS, PEN_SLATE, 9, PEN_WOOD, PEN_SILVER)
    For i = 0 To 5: planeLit(i) = v(i): Next i
    v = Array(PEN_SWALLOW + 1, PEN_GREY, PEN_SLATE + 1, PEN_DARK, PEN_WOOD + 1, PEN_SILVER + 1)
    For i = 0 To 5: planeShade(i) = v(i): Next i
    mPlane = BuildPlane(True)
    mPlaneLo = BuildPlane(False)
    For i = 0 To AP_HILLS - 1
        mHill(i) = BuildHill(i)
        hlId(i) = mHill(i): hlXs(i) = hlX(i): hlYs(i) = 0: hlZs(i) = hlZ(i)
    Next i
    BuildGroundModels
    v = Array("FLY YOUR SWALLOW AGAINST GRAULAND.", "BANK TO TURN; PULL BACK IN A BANK TO", _
              "TURN HARDER. CLIMBING COSTS SPEED AND", "DIVING BUYS IT: TOO SLOW AND YOU STALL.", "", _
              "THE TWIN GUNS HEAT UP: FIRE IN BURSTS", "OR THEY JAM. LAND GENTLY ON YOUR OWN", _
              "FIELD AND STOP TO REARM AND REPAIR.", "", "LOW DOWN THE AA GUNS FIND IT HARD TO", _
              "AIM. WASPS ARE LIGHT, HORNETS TOUGH,", "OX BOMBERS HAVE A REAR GUNNER.", "EIGHT MISSIONS; THREE AEROPLANES.")
    For i = 0 To 12: helpText(1, i) = v(i): Next i
    v = Array("LEFT / RIGHT     BANK", "UP / DOWN        NOSE DOWN / UP", "SPACE            GUNS", _
              "A / Z            THROTTLE UP / DOWN", "V / C            CHASE / COCKPIT", "I                INVERT UP / DOWN", _
              "P                PAUSE", "B                AUTOPILOT", "HELP / H         THESE PAGES", _
              "ESC              TITLE / QUIT", "", "THE RADAR: AHEAD IS UP. RED: ENEMY,", "BLUE: OURS, YELLOW: THE TARGET.")
    For i = 0 To 12: helpText(2, i) = v(i): Next i
End Sub

' ---------- the models ----------

Private Function Vx(ByVal m As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    Vx = e3.MdlVtx(m, x, y, z)
End Function

' a biplane, nose along +z, in quarter units (drawn through a matrix a quarter the size): the
' fuselage tapering to the tail, the cowling, two wings, the tailplane and fin, the propeller
Private Function BuildPlane(ByVal full As Boolean) As Long
    Dim m As Long, a As Long, b As Long, c As Long, d As Long, e As Long, f As Long, h As Long, i As Long
    Const CB As Long = 200, CS As Long = 201, CF As Long = 210
    m = e3.ModelNew()
    a = Vx(m, -6, -5, 20): b = Vx(m, 6, -5, 20): c = Vx(m, 6, 7, 20): d = Vx(m, -6, 7, 20)
    e = Vx(m, -2, 0, -34): f = Vx(m, 2, 0, -34): h = Vx(m, 2, 4, -34): i = Vx(m, -2, 4, -34)
    e3.MdlFace m, CB, CS, 4, a, b, f, e, 0, 1, -6         ' belly
    e3.MdlFace m, CB, CS, 4, d, c, h, i, 0, 1, -6         ' back
    e3.MdlFace m, CB, CS, 4, a, d, i, e, 0, 1, -6         ' sides
    e3.MdlFace m, CB, CS, 4, b, c, h, f, 0, 1, -6
    e3.MdlFace m, CB, CS, 4, e, f, h, i, 0, 1, -6         ' tail end
    e3.MdlBox m, PEN_GREY, PEN_DARK, -7, 7, -6, 8, 20, 27             ' cowling
    e3.MdlBox m, CB, CS, -40, 40, 17, 20, -6, 10                      ' upper wing
    If full Then
        e3.MdlBox m, CB, CS, -36, 36, -7, -4, -4, 10                   ' lower wing
        e3.MdlBox m, PEN_DARK, PEN_DARK, -25, -23, -4, 17, 0, 3        ' struts
        e3.MdlBox m, PEN_DARK, PEN_DARK, 23, 25, -4, 17, 0, 3
    End If
    e3.MdlBox m, CB, CS, -15, 15, 1, 3, -34, -24                      ' tailplane
    e3.MdlBox m, CS, CS, -1, 1, 3, 16, -34, -26                       ' fin
    If full Then                         ' the propeller's disc, seen from either side
        a = Vx(m, -10, -9, 29): b = Vx(m, 10, -9, 29): c = Vx(m, 10, 11, 29): d = Vx(m, -10, 11, 29)
        e3.MdlFace m, CF, CF, 4, a, b, c, d, 0, 1, 20
        e3.MdlFace m, CF, CF, 4, a, b, c, d, 0, 1, 40
    End If
    BuildPlane = m
End Function

Private Function BuildHill(ByVal k As Long) As Long
    Dim m As Long, i As Long, top As Long, ring(0 To 5) As Long, a As Long
    m = e3.ModelNew()
    top = Vx(m, 0, hlH(k), 0)
    For i = 0 To 5
        a = (i * 65536) \ 6 + 3000
        ring(i) = Vx(m, ShrA(A3Sin(a) * hlR(k), 16), 0, ShrA(A3Cos(a) * hlR(k), 16))
    Next i
    For i = 0 To 5
        e3.MdlFace m, PEN_HILL, PEN_HILL + 1, 3, ring(i), ring((i + 1) Mod 6), top, 0, 0, hlH(k) \ 3, 0
    Next i
    BuildHill = m
End Function

Private Sub BuildGroundModels()
    Dim m As Long, a As Long, b As Long, c As Long, d As Long, e As Long, f As Long
    m = e3.ModelNew(): mGt(GT_HANGAR) = m          ' timber walls, a pitched roof
    e3.MdlBox m, PEN_WOOD, PEN_WOOD + 1, -30, 30, 0, 20, -24, 24
    a = Vx(m, -31, 20, -26): b = Vx(m, 31, 20, -26): c = Vx(m, 31, 34, 0): d = Vx(m, -31, 34, 0)
    e = Vx(m, -31, 20, 26): f = Vx(m, 31, 20, 26)
    e3.MdlFace m, PEN_ROOF, PEN_DARK, 4, a, b, c, d, 0, 22, 0
    e3.MdlFace m, PEN_ROOF, PEN_DARK, 4, e, f, c, d, 0, 22, 0
    e3.MdlFace m, PEN_WOOD, PEN_WOOD + 1, 3, a, e, d, 0, 0, 22, 0
    e3.MdlFace m, PEN_WOOD, PEN_WOOD + 1, 3, b, f, c, 0, 0, 22, 0
    m = e3.ModelNew(): mGt(GT_DEPOT) = m           ' crates under a tarpaulin
    e3.MdlBox m, PEN_WOOD, PEN_WOOD + 1, -16, 16, 0, 10, -12, 12
    e3.MdlBox m, 9, PEN_DARK, -12, 12, 10, 18, -9, 9
    m = e3.ModelNew(): mGt(GT_AA) = m              ' sandbags round a gun pointing up
    e3.MdlBox m, 9, PEN_MUD, -8, 8, 0, 4, -8, 8
    e3.MdlBox m, PEN_GREY, PEN_DARK, -3, 3, 4, 8, -3, 3
    e3.MdlBox m, PEN_DARK, PEN_DARK, -1, 1, 8, 20, 0, 2
    m = e3.ModelNew(): mGt(GT_BALLOON) = m         ' a sausage, nose and tail, its fins
    a = Vx(m, 0, 0, 26): b = Vx(m, 0, 0, -24)
    c = Vx(m, 12, 0, 2): d = Vx(m, 0, 12, 2): e = Vx(m, -12, 0, 2): f = Vx(m, 0, -12, 2)
    e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, a, c, d, 0, 0, 0, 2: e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, a, d, e, 0, 0, 0, 2
    e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, a, e, f, 0, 0, 0, 2: e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, a, f, c, 0, 0, 0, 2
    e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, b, c, d, 0, 0, 0, 2: e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, b, d, e, 0, 0, 0, 2
    e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, b, e, f, 0, 0, 0, 2: e3.MdlFace m, PEN_CANVAS, PEN_GREY, 3, b, f, c, 0, 0, 0, 2
    e3.MdlBox m, PEN_GREY, PEN_GREY, -1, 1, 0, 14, -24, -14
    m = e3.ModelNew(): mGt(GT_LOCO) = m            ' boiler, cab, chimney
    e3.MdlBox m, PEN_FLAK, 0, -6, 6, 0, 10, -8, 14
    e3.MdlBox m, PEN_FLAK, 0, -6, 6, 0, 16, -16, -8
    e3.MdlBox m, PEN_RED, PEN_DARK, -2, 2, 10, 16, 8, 12
    m = e3.ModelNew(): mGt(GT_WAGON) = m
    e3.MdlBox m, PEN_WOOD + 1, PEN_DARK, -6, 6, 1, 12, -16, 16
    m = e3.ModelNew(): mGt(GT_TRUCK) = m           ' the load under canvas, the cab
    e3.MdlBox m, PEN_SLATE, PEN_SLATE + 1, -4, 4, 1, 8, -9, 2
    e3.MdlBox m, PEN_SLATE + 1, PEN_DARK, -4, 4, 1, 6, 2, 7
    mWreck = e3.ModelNew()                         ' what's left: a blackened heap
    e3.MdlPyramid mWreck, PEN_FLAK, 0, -14, 14, 0, -12, 12, 6
End Sub

' ---------- the ground's layers ----------

Private Function FloorDiv(ByVal a As Long, ByVal b As Long) As Long
    If a >= 0 Then FloorDiv = a \ b Else FloorDiv = -((-a + b - 1) \ b)
End Function

Private Sub AddQ(ByVal l As Long, ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                 ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long)
    Dim i As Long
    i = qn(l) * 12
    Select Case l
        Case L_FIELDS
            If qn(l) >= 300 Then Exit Sub
            q0(i) = x0: q0(i + 1) = y0: q0(i + 2) = z0: q0(i + 3) = x1: q0(i + 4) = y1: q0(i + 5) = z1
            q0(i + 6) = x2: q0(i + 7) = y2: q0(i + 8) = z2: q0(i + 9) = x3: q0(i + 10) = y3: q0(i + 11) = z3
        Case L_MUD
            If qn(l) >= 80 Then Exit Sub
            q1(i) = x0: q1(i + 1) = y0: q1(i + 2) = z0: q1(i + 3) = x1: q1(i + 4) = y1: q1(i + 5) = z1
            q1(i + 6) = x2: q1(i + 7) = y2: q1(i + 8) = z2: q1(i + 9) = x3: q1(i + 10) = y3: q1(i + 11) = z3
        Case L_RIVER
            If qn(l) >= 80 Then Exit Sub
            q2(i) = x0: q2(i + 1) = y0: q2(i + 2) = z0: q2(i + 3) = x1: q2(i + 4) = y1: q2(i + 5) = z1
            q2(i + 6) = x2: q2(i + 7) = y2: q2(i + 8) = z2: q2(i + 9) = x3: q2(i + 10) = y3: q2(i + 11) = z3
        Case L_RAIL
            If qn(l) >= 100 Then Exit Sub
            q3(i) = x0: q3(i + 1) = y0: q3(i + 2) = z0: q3(i + 3) = x1: q3(i + 4) = y1: q3(i + 5) = z1
            q3(i + 6) = x2: q3(i + 7) = y2: q3(i + 8) = z2: q3(i + 9) = x3: q3(i + 10) = y3: q3(i + 11) = z3
        Case L_LOW
            If qn(l) >= 80 Then Exit Sub
            q4(i) = x0: q4(i + 1) = y0: q4(i + 2) = z0: q4(i + 3) = x1: q4(i + 4) = y1: q4(i + 5) = z1
            q4(i + 6) = x2: q4(i + 7) = y2: q4(i + 8) = z2: q4(i + 9) = x3: q4(i + 10) = y3: q4(i + 11) = z3
        Case L_MARKS
            If qn(l) >= 4 Then Exit Sub
            q5(i) = x0: q5(i + 1) = y0: q5(i + 2) = z0: q5(i + 3) = x1: q5(i + 4) = y1: q5(i + 5) = z1
            q5(i + 6) = x2: q5(i + 7) = y2: q5(i + 8) = z2: q5(i + 9) = x3: q5(i + 10) = y3: q5(i + 11) = z3
        Case Else
            If qn(l) >= 100 Then Exit Sub
            q6(i) = x0: q6(i + 1) = y0: q6(i + 2) = z0: q6(i + 3) = x1: q6(i + 4) = y1: q6(i + 5) = z1
            q6(i + 6) = x2: q6(i + 7) = y2: q6(i + 8) = z2: q6(i + 9) = x3: q6(i + 10) = y3: q6(i + 11) = z3
    End Select
    qn(l) = qn(l) + 1
End Sub

Private Sub Flat(ByVal l As Long, ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal y As Long)
    AddQ l, x0, y, z0, x1, y, z0, x1, y, z1, x0, y, z1
End Sub

Private Sub Ribbon(ByVal l As Long, ByVal x0 As Long, ByVal za As Long, ByVal x1 As Long, ByVal zb As Long, ByVal w As Long)
    AddQ l, x0, 0, za - w, x1, 0, zb - w, x1, 0, zb + w, x0, 0, za + w
End Sub

' within range of the camera's cell (render.c's ahead() without the behind test: the engine
' drops what is behind)
Private Function Near(ByVal x As Long, ByVal z As Long, ByVal r As Long, ByVal cx As Long, ByVal cz As Long) As Boolean
    Near = x - cx <= r And cx - x <= r And z - cz <= r And cz - z <= r
End Function

' the layers for the camera at (cx, cz) (the middle of its cell); r: how far to keep
Private Sub BuildGround(ByVal cx As Long, ByVal cz As Long)
    Dim r As Long, i As Long, j As Long, i0 As Long, i1 As Long, j0 As Long, j1 As Long, x0 As Long, z0 As Long, dx As Long, dz As Long
    Dim h As Long, x As Long, zr As Long, zr1 As Long, zl As Long, zl1 As Long, k As Long, a As Long, b As Long, r2 As Long
    Dim ax As Long, az As Long, bx As Long, bz As Long, ccx As Long, ccz As Long, w As Long, y As Long
    For k = 0 To 6: qn(k) = 0: Next k
    r = VIEW_RANGE + CELL
    ' the patchwork of fields, hedges of grass between
    i0 = FloorDiv(cx - r, CELL): i1 = FloorDiv(cx + r, CELL)
    j0 = FloorDiv(cz - r, CELL): j1 = FloorDiv(cz + r, CELL)
    For j = j0 To j1
        For i = i0 To i1
            x0 = i * CELL: z0 = j * CELL
            dx = x0 + CELL \ 2 - cx: dz = z0 + CELL \ 2 - cz
            h = A3Hash(i * 7919 + j * 104729 + 77)
            If UModL(h, 7) >= 2 And dx * dx + dz * dz <= r * r Then     ' (else meadow: the grass itself)
                p0(qn(L_FIELDS)) = PEN_FIELD + (ShrU(h, 8) And 3)
                Flat L_FIELDS, x0 + 14, x0 + CELL - 14, z0 + 14, z0 + CELL - 14, 0
            End If
        Next i
    Next j
    ' the river, the railway, no-man's-land: east-west lines, in pieces near the camera
    For x = FloorDiv(cx - r, 200) * 200 To cx + r - 1 Step 200
        zr = ApRiverZ(x): zr1 = ApRiverZ(x + 200): zl = ApRailZ(x): zl1 = ApRailZ(x + 200)
        If Near(x + 100, zr, r, cx, cz) Then Ribbon L_RIVER, x, zr, x + 200, zr1, 40
        If Near(x + 100, zl, r, cx, cz) Then Ribbon L_RAIL, x, zl, x + 200, zl1, 5
        If Near(x + 100, 0, r, cx, cz) Then Ribbon L_MUD, x, 0, x + 200, 0, 55
    Next x
    ' the trenches' zigzags, close by
    If cz > -1500 - CELL And cz < 1500 + CELL Then
        r2 = 800 + CELL
        For x = FloorDiv(cx - r2, 80) * 80 To cx + r2 - 1 Step 80
            a = ApTrenchZ(x): b = ApTrenchZ(x + 80)
            Ribbon L_LOW, x, a - 70, x + 80, b - 70, 4
            Ribbon L_LOW, x, a + 70, x + 80, b + 70, 4
        Next x
    End If
    ' the road from Orme to the front
    For k = 0 To 9
        ApRoadPos (AP_ROAD_LEN \ 10) * k, ax, az
        ApRoadPos (AP_ROAD_LEN \ 10) * (k + 1), bx, bz
        If Near(ShrA(ax + bx, 17), ShrA(az + bz, 17), r + 400, cx, cz) Then
            AddQ L_RAIL, ShrA(ax, 16) - 7, 0, ShrA(az, 16), ShrA(ax, 16) + 7, 0, ShrA(az, 16), _
                 ShrA(bx, 16) + 7, 0, ShrA(bz, 16), ShrA(bx, 16) - 7, 0, ShrA(bz, 16)
        End If
    Next k
    ' the aerodromes' strips, the depot's yard
    If Near(AP_HOME_X, AP_HOME_Z, r + AP_RUNWAY_L, cx, cz) Then
        Flat L_LOW, AP_HOME_X - AP_RUNWAY_W, AP_HOME_X + AP_RUNWAY_W, AP_HOME_Z - AP_RUNWAY_L, AP_HOME_Z + AP_RUNWAY_L, 0
        Flat L_MARKS, AP_HOME_X - 8, AP_HOME_X + 8, AP_HOME_Z + AP_RUNWAY_L - 30, AP_HOME_Z + AP_RUNWAY_L - 10, 0
        Flat L_MARKS, AP_HOME_X - 8, AP_HOME_X + 8, AP_HOME_Z - AP_RUNWAY_L + 10, AP_HOME_Z - AP_RUNWAY_L + 30, 0
    End If
    If Near(AP_ENEMY_X, AP_ENEMY_Z, r + 400, cx, cz) Then Flat L_LOW, AP_ENEMY_X - 300, AP_ENEMY_X + 300, AP_ENEMY_Z - 60, AP_ENEMY_Z + 30, 0
    If Near(AP_DEPOT_X, AP_DEPOT_Z, r + 300, cx, cz) Then Flat L_LOW, AP_DEPOT_X - 200, AP_DEPOT_X + 200, AP_DEPOT_Z - 120, AP_DEPOT_Z + 120, 0
    ' the clouds
    r2 = VIEW_RANGE * 2 + CELL
    i0 = FloorDiv(cx - r2, 1500): i1 = FloorDiv(cx + r2, 1500)
    j0 = FloorDiv(cz - r2, 1500): j1 = FloorDiv(cz + r2, 1500)
    For j = j0 To j1
        For i = i0 To i1
            h = A3Hash(i * 31 + j * 1009 + 5)
            ccx = i * 1500 + UModL(h, 900): ccz = j * 1500 + UModL(ShrU(h, 10), 900)
            w = 150 + UModL(ShrU(h, 20), 200): y = 900 + UModL(ShrU(h, 4), 200)
            If UModL(h, 3) <> 0 Then
                If Near(ccx, ccz, r2, cx, cz) Then Flat L_CLOUDS, ccx - w, ccx + w, ccz - w \ 2, ccz + w \ 2, y
            End If
        Next i
    Next j
End Sub

' the scenery that isn't a target this time: our aerodrome and reserve depot, and theirs
' unless they are the mission
Private Sub BuildScenery()
    Dim k As Long
    scN = 0
    For k = 0 To 2
        AddScenery Choose(k + 1, GT_HANGAR, GT_HANGAR, GT_DEPOT), AP_HOME_X + 170, AP_HOME_Z + Choose(k + 1, -220, -80, 60), 16384
    Next k
    For k = 0 To 3
        AddScenery GT_DEPOT, Choose(k + 1, -300, -240, -360, -300), Choose(k + 1, -1200, -1160, -1150, -1100), 0
    Next k
    If apMission <> 7 Then
        For k = 0 To 2
            AddScenery GT_HANGAR, AP_ENEMY_X - 130 + k * 130, AP_ENEMY_Z + 90, 0
        Next k
    End If
    If apMission <> 6 Then
        For k = 0 To 1
            AddScenery GT_DEPOT, AP_DEPOT_X - 60 + k * 120, AP_DEPOT_Z, 0
        Next k
    End If
End Sub

Private Sub AddScenery(ByVal typ As Long, ByVal x As Long, ByVal z As Long, ByVal yaw As Long)
    scId(scN) = mGt(typ): scX(scN) = x: scY(scN) = 0: scZ(scN) = z: scYaw(scN) = yaw
    scN = scN + 1
End Sub

' ---------- the view ----------

Private Sub SetCamera()
    Dim roll As Long, pitch As Long, yaw As Long, x As Long, y As Long, z As Long, back As Long, cp As Long, gy As Long, v As Long
    If acView = VIEW_COCKPIT And acState <> AS_TITLE And plState(0) <> PS_DEAD Then
        yaw = plYaw(0): pitch = -plPitch(0): roll = plRoll(0)
        x = plX(0) + 4 * A3Sin(plYaw(0)): z = plZ(0) + 4 * A3Cos(plYaw(0)): y = plY(0) + 196608
        v = VIEW_COCKPIT
    Else
        ' behind and a little above, swinging round after the plane
        back = 64
        yaw = acCamYaw
        pitch = (-plPitch(0) * 3) \ 4 + 700
        roll = plRoll(0) \ 2
        cp = A3Cos(plPitch(0))
        x = plX(0) - back * FMul(cp, A3Sin(yaw))
        z = plZ(0) - back * FMul(cp, A3Cos(yaw))
        y = plY(0) - back * A3Sin(plPitch(0)) + 16 * 65536
        If plState(0) = PS_DEAD Then y = y + 40 * 65536
        gy = ApGroundY(x, z) + 6 * 65536
        If y < gy Then y = gy
        v = VIEW_CHASE
    End If
    If v <> curView Then
        If v = VIEW_COCKPIT Then
            e3.View G_W, G_H, G_W \ 2, 112, 190
            camCy = 112: camFov = 190
        Else
            e3.View G_W, G_H, G_W \ 2, 120, 200
            camCy = 120: camFov = 200
        End If
        curView = v
    End If
    e3.CamPlace x, y, z
    e3.CamAngles yaw And &HFFFF&, pitch And &HFFFF&
    If roll <> 0 Then e3.CamBank A3Cos(roll), A3Sin(roll)      ' render.c's xf, exactly
    camX = ShrA(x, 16): camY = ShrA(y, 16): camZ = ShrA(z, 16)
    camYawV = yaw And &HFFFF&
    rc = A3Cos(roll): rs = A3Sin(roll)
    If roll = 0 Then rs = 0
    cfx = A3Sin(camYawV): cfz = A3Cos(camYawV)
End Sub

' the earth below the horizon, tilted with the bank
Private Sub Earth()
    Dim h0 As Long, k As Long, u As Long, v As Long, uu As Long, vv As Long
    h0 = e3.Horizon - camCy
    If h0 > 3000 Then Exit Sub
    If h0 < -3000 Then h0 = -3000
    For k = 0 To 3
        u = Choose(k + 1, -4000, 4000, 4000, -4000)
        v = Choose(k + 1, h0, h0, h0 + 6000, h0 + 6000)
        uu = ShrA(u * (rc \ 16) + v * (rs \ 16), 12)
        vv = ShrA(-u * (rs \ 16) + v * (rc \ 16), 12)
        nx(k) = G_W \ 2 + uu
        ny(k) = camCy + vv
    Next k
    e3.PolyFill nx, ny, 4, PEN_GRASS
End Sub

' is a point within range and not behind the camera?
Private Function Ahead(ByVal x As Long, ByVal z As Long, ByVal range As Long, ByVal slack As Long) As Boolean
    Dim dx As Long, dz As Long
    dx = x - camX: dz = z - camZ
    If dx > range Or dx < -range Or dz > range Or dz < -range Then Exit Function
    Ahead = ShrA(dx * (cfx \ 16) + dz * (cfz \ 16), 12) > -slack
End Function

Private Sub Layer(ByVal l As Long)
    If qn(l) = 0 Then Exit Sub
    Select Case l
        Case L_FIELDS: e3.QuadsW qn(l), -4, p0, q0
        Case L_MUD: e3.QuadsW qn(l), -4, PEN_MUD, q1
        Case L_RIVER: e3.QuadsW qn(l), -4, PEN_RIVER, q2
        Case L_RAIL: e3.QuadsW qn(l), -4, PEN_DARK, q3
        Case L_LOW: e3.QuadsW qn(l), -4, PEN_FIELD, q4
        Case L_MARKS: e3.QuadsW qn(l), -4, 1, q5
        Case Else: e3.QuadsW qn(l), -4, 1, q6
    End Select
End Sub

Private Sub GroundThings()
    Dim k As Long, n As Long, x As Long, z As Long, cableTop As Long
    For k = 0 To apNGr - 1
        x = ShrA(grX(k), 16): z = ShrA(grZ(k), 16)
        If Ahead(x, z, VIEW_RANGE + 200, 100) Then
            If grAlive(k) = 0 Then
                If grType(k) <> GT_BALLOON Then
                    gnId(n) = mWreck: gnX(n) = grX(k): gnY(n) = 0: gnZ(n) = grZ(k): gnYaw(n) = 0
                    n = n + 1
                End If
            Else
                gnId(n) = mGt(grType(k)): gnX(n) = grX(k): gnY(n) = grY(k): gnZ(n) = grZ(k): gnYaw(n) = grYaw(k)
                n = n + 1
                If grType(k) = GT_BALLOON And Ahead(x, z, 1200, 100) Then     ' its cable
                    cableTop = ShrA(grY(k), 16) - 10
                    e3.QuadW -4, PEN_DARK, x - 1, 0, z, x + 1, 0, z, x + 1, cableTop, z, x - 1, cableTop, z
                End If
            End If
        End If
    Next k
    If n > 0 Then e3.DrawModels n, gnId, gnX, gnY, gnZ, gnYaw, True
End Sub

Private Sub Planes()
    Dim k As Long, dx As Long, dy As Long, dz As Long, d As Long, j As Long, flash As Long, t As Long
    If (apTicks And 1) <> 0 Then flash = PEN_GREY Else flash = PEN_SMOKE
    For k = 0 To apNP - 1
        If plState(k) <> PS_DEAD And Not (k = 0 And acView = VIEW_COCKPIT And acState <> AS_TITLE) Then
            dx = ShrA(plX(k), 16) - camX: dy = ShrA(plY(k), 16) - camY: dz = ShrA(plZ(k), 16) - camZ
            If dx <= 8000 And dx >= -8000 And dz <= 8000 And dz >= -8000 Then
                d = FHypot(FHypot(dx, dz), dy)
                If d > FAR_LOD Then
                    If d < VIEW_RANGE * 3 Then e3.Spot ShrA(plX(k), 16), ShrA(plY(k), 16), ShrA(plZ(k), 16), 4, planeShade(plType(k)), 0
                Else
                    e3.RotYPR rot, plYaw(k), (-plPitch(k)) And &HFFFF&, (-plRoll(k)) And &HFFFF&
                    For j = 0 To 8: rot(j) = ShrA(rot(j), 2): Next j      ' the model is in quarter units
                    e3.DrawModelMF IIf(d < NEAR_LOD, mPlane, mPlaneLo), plX(k), plY(k), plZ(k), rot, _
                                   planeLit(plType(k)), planeShade(plType(k)), flash, 0
                    If plHitT(k) < 3 And d < 1200 Then e3.Spot ShrA(plX(k), 16), ShrA(plY(k), 16) + 2, ShrA(plZ(k), 16), 3, PEN_FIRE, -10
                End If
            End If
        End If
    Next k
End Sub

Private Sub Shots()
    Dim k As Long, n As Long, dx As Long, dy As Long, dz As Long, age As Long, p As Long
    For k = 0 To AP_MAX_BULLETS - 1
        If buAlive(k) <> 0 Then
            dx = ShrA(buX(k), 16) - camX: dy = ShrA(buY(k), 16) - camY: dz = ShrA(buZ(k), 16) - camZ
            If Not (dx < 30 And dx > -30 And dy < 30 And dy > -30 And dz < 30 And dz > -30) Then   ' (past your ear)
                bxs(n) = ShrA(buX(k), 16): bys(n) = ShrA(buY(k), 16): bzs(n) = ShrA(buZ(k), 16)
                If plSide(buOwner(k)) = SIDE_HOME Then bps(n) = PEN_YELLOW Else bps(n) = PEN_FIRE
                n = n + 1
            End If
        End If
    Next k
    If n > 0 Then e3.Points n, bxs, bys, bzs, bps, -3, -2
    For k = 0 To AP_MAX_FLAK - 1
        If fkAlive(k) <> 0 Then
            age = fkT(k) - fkFuse(k)
            If age >= 0 Then
                If age < 3 Then
                    e3.Star ShrA(fkX(k), 16), ShrA(fkY(k), 16), ShrA(fkZ(k), 16), 14, PEN_FIRE, 4, age * 1500, -8
                Else
                    e3.Spot ShrA(fkX(k), 16), ShrA(fkY(k), 16), ShrA(fkZ(k), 16), 8 + age \ 2, PEN_FLAK, 0
                End If
            End If
        End If
    Next k
    For k = 0 To 39
        If puT(k) > 0 Then
            dx = puX(k) - camX: dy = puY(k) - camY: dz = puZ(k) - camZ
            If Not (dx < 40 And dx > -40 And dy < 40 And dy > -40 And dz < 40 And dz > -40) Then    ' (flying through it)
                e3.Spot puX(k), puY(k) + (40 - puT(k)) \ 3, puZ(k), puSize(k) + (40 - puT(k)) \ 8, PEN_SMOKE, 0
            End If
        End If
    Next k
    For k = 0 To 11
        If blT(k) > 0 Then
            If blT(k) > 8 Then
                p = PEN_YELLOW
            ElseIf blT(k) > 4 Then
                p = PEN_FIRE
            Else
                p = PEN_RED
            End If
            e3.Star blX(k), blY(k) + (12 - blT(k)) * 2, blZ(k), (blSize(k) * (4 + blT(k))) \ 14, p, 4, blT(k) * 1500, -8
        End If
    Next k
End Sub

' the patrol marker: a flare's smoke going up
Private Sub Marker()
    Dim x As Long, z As Long, top As Long, s As Long, p As Long
    If apPhase = PH_OUT And apWpNext < apNWp Then
        x = ShrA(wpX(apWpNext), 16): z = ShrA(wpZ(apWpNext), 16): top = wpAlt(apWpNext) + 80
        s = 6 + (apTicks And 4)
        If (apTicks And 8) <> 0 Then p = PEN_GREEN Else p = PEN_YELLOW
        e3.QuadW -4, p, x - s, 0, z, x + s, 0, z, x + s, top, z, x - s, top, z
        e3.QuadW -4, p, x, 0, z - s, x, 0, z + s, x, top, z + s, x, top, z - s
    End If
End Sub

Public Sub Scene(cv As Object)
    Dim cx As Long, cz As Long, px As Long, pz As Long, gy As Long, alt As Long
    SetCamera
    cx = FloorDiv(camX, CELL): cz = FloorDiv(camZ, CELL)
    If Not groundReady Or cx <> keyCellX Or cz <> keyCellZ Then
        BuildGround cx * CELL + CELL \ 2, cz * CELL + CELL \ 2
        keyCellX = cx: keyCellZ = cz: groundReady = True
    End If
    If apMission <> keyMission Then
        BuildScenery
        keyMission = apMission
    End If
    e3.Clear PEN_SKY
    Earth
    e3.Begin VIEW_RANGE + 400
    Layer L_FIELDS
    e3.Flush
    polyTotal = polyTotal + e3.NPolys
    e3.Begin VIEW_RANGE + 400
    Layer L_MUD
    e3.Flush
    e3.Begin VIEW_RANGE + 400
    Layer L_RIVER
    e3.Flush
    e3.Begin VIEW_RANGE + 400
    Layer L_RAIL
    e3.Flush
    e3.Begin VIEW_RANGE + 400
    Layer L_LOW
    Layer L_MARKS
    ' your shadow, low down
    gy = ShrA(ApGroundY(plX(0), plZ(0)), 16)
    alt = ShrA(plY(0), 16) - gy: px = ShrA(plX(0), 16): pz = ShrA(plZ(0), 16)
    If plState(0) <> PS_DEAD And alt < 400 And gy = 0 Then e3.QuadW -4, PEN_DARK, px - 9, 0, pz - 9, px + 9, 0, pz - 9, px + 9, 0, pz + 9, px - 9, 0, pz + 9
    e3.Flush
    polyTotal = polyTotal + e3.NPolys
    e3.Begin VIEW_RANGE * 3
    e3.DrawModels AP_HILLS, hlId, hlXs, hlYs, hlZs, 0
    e3.DrawModels scN, scId, scX, scY, scZ, scYaw
    GroundThings
    Marker
    Layer L_CLOUDS
    Planes
    Shots
    e3.Flush
    polyTotal = polyTotal + e3.NPolys
End Sub

' ---------- the HUD ----------

Private Sub Bar(cv As Object, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal v As Long, ByVal mx As Long, ByVal p As Long)
    Dim f As Long
    If mx > 0 Then f = (v * (w - 2)) \ mx
    If f < 0 Then f = 0
    If f > w - 2 Then f = w - 2
    GBox cv, x, y, x + w, y + 6, 0, PEN_GREY
    If f > 0 Then GRect cv, x + 1, y + 1, x + f, y + 5, p
End Sub

Private Sub Blip(cv As Object, ByVal wx As Long, ByVal wz As Long, ByVal p As Long, ByVal sz As Long, ByVal cx As Long, ByVal cy As Long, _
                 ByVal r As Long, ByVal c As Long, ByVal s As Long)
    Dim dx As Long, dz As Long, rx As Long, rz As Long, bx As Long, by As Long
    dx = ShrA(wx - plX(0), 16): dz = ShrA(wz - plZ(0), 16)
    rx = ShrA(dx * (c \ 16) - dz * (s \ 16), 12): rz = ShrA(dx * (s \ 16) + dz * (c \ 16), 12)
    bx = cx + rx \ 70: by = cy - rz \ 70
    If (bx - cx) * (bx - cx) + (by - cy) * (by - cy) < r * r Then GRect cv, bx - sz, by - sz, bx + sz, by + sz, p
End Sub

Private Sub Radar(cv As Object, ByVal cx As Long, ByVal cy As Long, ByVal r As Long)
    Dim c As Long, s As Long, k As Long, ox As Long, oz As Long
    c = A3Cos(plYaw(0)): s = A3Sin(plYaw(0))
    cv.Circle cx, cy, r + 1, pen(PEN_GREY), True
    cv.Circle cx, cy, r, pen(PEN_PANEL), True
    Blip cv, AP_HOME_X * 65536, AP_HOME_Z * 65536, PEN_GREEN, 1, cx, cy, r, c, s
    For k = 0 To apNGr - 1
        If grAlive(k) <> 0 And grObj(k) <> 0 Then Blip cv, grX(k), grZ(k), PEN_YELLOW, 0, cx, cy, r, c, s
    Next k
    If ApObjectivePos(ox, oz) Then Blip cv, ox, oz, IIf((apTicks And 4) <> 0, PEN_YELLOW, 1), 1, cx, cy, r, c, s
    For k = 1 To apNP - 1
        If plState(k) = PS_FLY Then Blip cv, plX(k), plZ(k), IIf(plSide(k) = SIDE_HOME, PEN_BLUE, PEN_RED), 1, cx, cy, r, c, s
    Next k
    GRect cv, cx, cy - 2, cx, cy + 1, 1
End Sub

' where the guns point: a cross 300 units off the nose
Private Sub Gunsight(cv As Object)
    Dim cp As Long, sx As Long, sy As Long, x As Long, y As Long, z As Long
    If plState(0) <> PS_FLY Then Exit Sub
    cp = A3Cos(plPitch(0))
    x = ShrA(plX(0), 16) + ShrA(300 * FMul(cp, A3Sin(plYaw(0))), 16)
    y = ShrA(plY(0), 16) + ShrA(300 * A3Sin(plPitch(0)), 16)
    z = ShrA(plZ(0), 16) + ShrA(300 * FMul(cp, A3Cos(plYaw(0))), 16)
    If Not e3.Project(x, y, z, sx, sy) Then Exit Sub
    If sx < 8 Or sx > G_W - 8 Or sy < 8 Or sy > G_H - 30 Then Exit Sub
    GRect cv, sx - 6, sy, sx - 3, sy, PEN_GREEN
    GRect cv, sx + 3, sy, sx + 6, sy, PEN_GREEN
    GRect cv, sx, sy - 6, sx, sy - 3, PEN_GREEN
    GRect cv, sx, sy + 3, sx, sy + 6, PEN_GREEN
End Sub

' an arrow to the objective, turned with the view
Private Sub Pointer(cv As Object, ByVal cx As Long, ByVal cy As Long)
    Dim ox As Long, oz As Long, rl As Long, s As String
    If Not ApObjectivePos(ox, oz) Then Exit Sub
    rl = ApAngleTo(ox - plX(0), oz - plZ(0)) - camYawV
    nx(0) = cx + ShrA(A3Sin(rl) * 12, 16): ny(0) = cy - ShrA(A3Cos(rl) * 12, 16)
    nx(1) = cx + ShrA(A3Sin(rl + 26000) * 8, 16): ny(1) = cy - ShrA(A3Cos(rl + 26000) * 8, 16)
    nx(2) = cx + ShrA(A3Sin(rl - 26000) * 8, 16): ny(2) = cy - ShrA(A3Cos(rl - 26000) * 8, 16)
    cv.Polygon nx, ny, 3, pen(IIf(apPhase = PH_HOME, PEN_GREEN, PEN_YELLOW)), True
    s = CStr(ShrA(FHypot(ox - plX(0), oz - plZ(0)), 16))
    GTextShadow cv, cx - cv.TextWidth(s) \ 2, cy + 22, 1, s
End Sub

Private Sub Warnings(cv As Object)
    If plStalled(0) <> 0 And (apTicks And 8) <> 0 Then GTextCentre cv, 150, PEN_RED, "STALL"
    If plJam(0) <> 0 Then
        GTextCentre cv, 162, PEN_FIRE, "GUNS JAMMED"
    ElseIf plHeat(0) > 75 And (apTicks And 4) <> 0 Then
        GTextCentre cv, 162, PEN_FIRE, "GUNS HOT"
    End If
    If plAmmo(0) = 0 And plState(0) = PS_FLY Then GTextCentre cv, 174, PEN_RED, "OUT OF AMMUNITION: LAND AT HOME"
    If plOnGround(0) <> 0 Then GTextCentre cv, 186, PEN_GREEN, IIf(plGroundT(0) > 0, "REARMING", "ON THE GROUND")
    If acHurtTimer > 0 Then
        GRect cv, 0, 0, G_W - 1, 2, PEN_RED
        GRect cv, 0, 0, 2, G_H - 1, PEN_RED
        GRect cv, G_W - 3, 0, G_W - 1, G_H - 1, PEN_RED
    End If
End Sub

Private Sub Hud(cv As Object)
    Dim k As Long, p As Long
    GTextShadow cv, 4, 10, PEN_YELLOW, ApObjectiveText()
    GTextShadow cv, 4, 22, 1, CStr(apScore)
    For k = 0 To apLives - 1
        GRect cv, 4 + k * 10, 28, 11 + k * 10, 30, PEN_SWALLOW
    Next k
    Radar cv, G_W - 32, 32, 27
    Pointer cv, G_W \ 2, 18
    Gunsight cv
    GRect cv, 0, 232, G_W - 1, G_H - 1, PEN_PANEL
    GText cv, 4, 242, 1, "SPD " & Right$("  " & ShrA(plV(0) * 25, 16), 3)
    GText cv, 4, 252, 1, "ALT " & Right$("   " & ShrA(plY(0) - ApGroundY(plX(0), plZ(0)), 16), 4)
    GText cv, 76, 242, PEN_GREY, "THR"
    Bar cv, 102, 236, 52, plThr(0), 100, PEN_GREEN
    GText cv, 76, 252, PEN_GREY, "GUN"
    If plJam(0) <> 0 Then
        p = PEN_RED
    ElseIf plHeat(0) > 75 Then
        p = PEN_FIRE
    Else
        p = PEN_YELLOW
    End If
    Bar cv, 102, 246, 52, plHeat(0), AP_JAM_HEAT, p
    GText cv, 162, 242, IIf(plAmmo(0) < 60, PEN_RED, 1), "AMMO " & Right$("  " & plAmmo(0), 3)
    GText cv, 162, 252, PEN_GREY, "DAMAGE"
    Bar cv, 214, 246, 50, AP_HP - plHp(0), AP_HP, PEN_RED
    GText cv, 276, 242, PEN_YELLOW, "M" & apMission
    If acAutoplay Then
        GText cv, 276, 252, PEN_GREEN, "AUTO"
    ElseIf acInvert Then
        GText cv, 276, 252, PEN_GREY, "INV"
    End If
End Sub

' the cockpit: the upper wing overhead, its struts, the guns and their ring sight, the panel
Private Sub Dial(cv As Object, ByVal cx As Long, ByVal cy As Long, ByVal r As Long, ByVal angle As Long, ByVal label As String)
    cv.Circle cx, cy, r + 1, pen(PEN_GREY), True
    cv.Circle cx, cy, r, pen(0), True
    nx(0) = cx + ShrA(A3Sin(angle) * (r - 2), 16): ny(0) = cy - ShrA(A3Cos(angle) * (r - 2), 16)
    nx(1) = cx + ShrA(A3Sin(angle + 16384) * 2, 16): ny(1) = cy - ShrA(A3Cos(angle + 16384) * 2, 16)
    nx(2) = cx - ShrA(A3Sin(angle + 16384) * 2, 16): ny(2) = cy + ShrA(A3Cos(angle + 16384) * 2, 16)
    cv.Polygon nx, ny, 3, pen(1), True
    GText cv, cx - cv.TextWidth(label) \ 2, cy + r + 10, PEN_GREY, label
End Sub

Private Sub Cockpit(cv As Object)
    Dim k As Long, x As Long, y As Long, a As Long
    GRect cv, 0, 0, G_W - 1, 14, PEN_SWALLOW + 1          ' the wing and its trailing edge, a cut-out
    GRect cv, 0, 15, G_W - 1, 17, PEN_DARK
    GRect cv, 130, 12, 190, 17, PEN_SKY
    nx(0) = 54: ny(0) = 17: nx(1) = 60: ny(1) = 17: nx(2) = 26: ny(2) = 206: nx(3) = 20: ny(3) = 206   ' struts, leaning in
    cv.Polygon nx, ny, 4, pen(PEN_WOOD + 1), True
    nx(0) = 260: nx(1) = 266: nx(2) = 300: nx(3) = 294
    cv.Polygon nx, ny, 4, pen(PEN_WOOD + 1), True
    For k = 0 To 15                                       ' the ring sight
        a = k * 4096
        x = 160 + ShrA(A3Sin(a) * 22, 16): y = 112 - ShrA(A3Cos(a) * 22, 16)
        GRect cv, x, y, x + 1, y + 1, PEN_FLAK
    Next k
    GRect cv, 159, 111, 160, 112, PEN_RED
    If plGunCd(0) = 2 Then k = 3 Else k = 0               ' the guns, kicking when they fire
    GRect cv, 138, 186 + k, 148, 206, PEN_FLAK
    GRect cv, 172, 186 + k, 182, 206, PEN_FLAK
    GRect cv, 141, 186 + k, 145, 190 + k, 0
    GRect cv, 175, 186 + k, 179, 190 + k, 0
    GRect cv, 0, 206, G_W - 1, G_H - 1, PEN_WOOD + 1      ' the panel
    GRect cv, 0, 206, G_W - 1, 207, PEN_DARK
    Dial cv, 36, 226, 15, (ShrA(plV(0) * 25, 16) * 300) And &HFFFF&, "SPEED"
    Dial cv, 90, 226, 15, (((ShrA(plY(0), 16) Mod 1000) * 65) And &HFFFF&), "ALT"
    GText cv, 72, 214, PEN_YELLOW, Right$("   " & ShrA(plY(0) - ApGroundY(plX(0), plZ(0)), 16), 4)
    GText cv, 147, 222, PEN_YELLOW, Format$(ShrA(plYaw(0) * 360, 16), "000")
    GText cv, 143, 236, PEN_GREY, "HDG"
    GText cv, 196, 216, 1, "THR"
    Bar cv, 226, 210, 40, plThr(0), 100, PEN_GREEN
    GText cv, 196, 228, 1, "GUN"
    Bar cv, 226, 222, 40, plHeat(0), AP_JAM_HEAT, IIf(plJam(0) <> 0, PEN_RED, PEN_YELLOW)
    GText cv, 196, 240, 1, "DMG"
    Bar cv, 226, 234, 40, AP_HP - plHp(0), AP_HP, PEN_RED
    GText cv, 274, 228, IIf(plAmmo(0) < 60, PEN_RED, 1), Right$("  " & plAmmo(0), 3)
    GText cv, 270, 240, PEN_GREY, "RDS"
    GTextShadow cv, 4, 30, PEN_YELLOW, ApObjectiveText()
    Pointer cv, G_W \ 2, 44
    Radar cv, G_W - 30, 44, 22
    If acAutoplay Then GTextShadow cv, 4, 42, PEN_GREEN, "AUTO"
End Sub

Private Sub BigCentre(cv As Object, ByVal y As Long, ByVal p As Long, ByVal s As String, ByVal sc As Long)
    GTextBig cv, (G_W - GTextBigWidth(cv, s, sc)) \ 2, y, p, s, sc
End Sub

Private Sub ResultBox(cv As Object)
    Dim ok As Boolean, shots As Long, hits As Long, pc As Long, s As String
    ok = acResult = PH_DONE
    shots = apShots - acMShots: hits = apHits - acMHits
    GBox cv, 40, 54, 280, 176, PEN_PANEL, IIf(ok, PEN_GREEN, PEN_RED)
    If ok Then
        s = "MISSION DONE"
    ElseIf plState(0) = PS_FLY Then
        s = "MISSION LOST"
    Else
        s = "SHOT DOWN"
    End If
    BigCentre cv, 62, IIf(ok, PEN_GREEN, PEN_RED), s, 2
    If Not ok And plState(0) <> PS_FLY Then GTextCentre cv, 92, PEN_GREY, IIf(plHp(0) > 0, "INTO THE GROUND", "BY ENEMY FIRE")
    GTextCentre cv, 108, 1, "AEROPLANES " & (apKills - acMKills) & "  GROUND " & (apGKills - acMGKills)
    If shots <> 0 Then pc = (hits * 100) \ shots
    GTextCentre cv, 122, 1, "HITS " & pc & "%   SCORE " & (apScore - acMScore)
    GTextCentre cv, 140, PEN_YELLOW, apRankName(ApRank(apScore)) & "  " & apScore
    If acStateTimer = 0 Then GTextCentre cv, 162, IIf(((apTicks \ 10) And 1) <> 0, PEN_YELLOW, 1), "PRESS FIRE"
End Sub

Private Sub OverBox(cv As Object)
    GBox cv, 30, 54, 290, 190, PEN_PANEL, IIf(apWon <> 0, PEN_GREEN, PEN_RED)
    BigCentre cv, 62, IIf(apWon <> 0, PEN_GREEN, PEN_RED), IIf(apWon <> 0, "THE WAR IS WON", "GROUNDED"), 2
    GTextCentre cv, 92, PEN_GREY, IIf(apWon <> 0, "THE GREY FALCON FLIES NO MORE", "THE SQUADRON HAS NO AEROPLANES LEFT")
    GTextCentre cv, 112, 1, apMissionsFlown & " MISSIONS FLOWN"
    GTextCentre cv, 126, 1, apKills & " AEROPLANES, " & apGKills & " ON THE GROUND"
    GTextCentre cv, 140, 1, "SCORE " & apScore
    GTextCentre cv, 156, PEN_YELLOW, apRankName(ApRank(apScore))
    If acStateTimer = 0 Then GTextCentre cv, 178, IIf(((apTicks \ 10) And 1) <> 0, PEN_YELLOW, 1), "PRESS FIRE"
End Sub

Public Sub DrawGame(cv As Object)
    Scene cv
    If acView = VIEW_COCKPIT And plState(0) <> PS_DEAD Then Cockpit cv Else Hud cv
    Warnings cv
    If acState = AS_PLAY And apMTick < 75 Then GTextCentre cv, 70, PEN_YELLOW, apMissionName(apMission)
    If acState = AS_RESULT Then ResultBox cv
    If acState = AS_OVER Then OverBox cv
    If acPaused = 1 Then GTextCentre cv, 128, 1, "PAUSED"
    If acFlashTimer > 0 And Len(acFlash) > 0 Then GTextCentre cv, 60, acFlashPen, acFlash
End Sub

Public Sub DrawTitle(cv As Object)
    Scene cv                             ' the autopilot flies behind the title
    GTextBig cv, (G_W - GTextBigWidth(cv, "ACE PILOT", 4)) \ 2 + 2, 22, 0, "ACE PILOT", 4
    GTextBig cv, (G_W - GTextBigWidth(cv, "ACE PILOT", 4)) \ 2, 20, PEN_YELLOW, "ACE PILOT", 4
    GTextBig cv, (G_W - GTextBigWidth(cv, "2", 5)) \ 2 + 2, 58, 0, "2", 5
    GTextBig cv, (G_W - GTextBigWidth(cv, "2", 5)) \ 2, 56, PEN_RED, "2", 5
    GTextCentre cv, 112, 1, "LARKSPUR SQUADRON OVER THE SELLEN"
    GBox cv, 24, 190, 296, 252, PEN_PANEL, PEN_GREY
    GTextCentre cv, 204, PEN_GREEN, "MISSION " & acStartMission & ": " & apMissionName(acStartMission)
    GTextCentre cv, 218, PEN_GREY, "UP / DOWN: CHOOSE THE MISSION"
    GTextCentre cv, 232, IIf(((apTicks \ 12) And 1) <> 0, PEN_YELLOW, 1), "PRESS FIRE TO FLY"
    GTextCentre cv, 246, PEN_GREY, "BEST " & acBest & "   HELP: HOW TO FLY"
End Sub

' ---------- the briefing, with a map of the sector ----------
Private Function MapX(ByVal x As Long) As Long
    MapX = 200 + ((x + AP_WORLD) * 108) \ (2 * AP_WORLD)
End Function

Private Function MapY(ByVal z As Long) As Long
    MapY = 114 + 108 - ((z + AP_WORLD) * 108) \ (2 * AP_WORLD)
End Function

Private Sub DrawMap(cv As Object)
    Dim x As Long, k As Long
    GRect cv, 200, 114, 308, 222, PEN_GRASS
    For x = -AP_WORLD To AP_WORLD - 1 Step 120
        GRect cv, MapX(x), MapY(ApRiverZ(x)), MapX(x) + 1, MapY(ApRiverZ(x)), PEN_RIVER
        GRect cv, MapX(x), MapY(ApRailZ(x)), MapX(x), MapY(ApRailZ(x)), PEN_DARK
        If ((x \ 120) And 1) <> 0 Then GRect cv, MapX(x), MapY(0), MapX(x) + 1, MapY(0), PEN_RED
    Next x
    For k = 0 To AP_HILLS - 1
        GRect cv, MapX(hlX(k)) - 1, MapY(hlZ(k)) - 1, MapX(hlX(k)) + 1, MapY(hlZ(k)) + 1, PEN_HILL + 1
    Next k
    GRect cv, MapX(AP_HOME_X) - 1, MapY(AP_HOME_Z) - 2, MapX(AP_HOME_X) + 1, MapY(AP_HOME_Z) + 2, PEN_GREEN
    GRect cv, MapX(AP_ENEMY_X) - 2, MapY(AP_ENEMY_Z) - 1, MapX(AP_ENEMY_X) + 2, MapY(AP_ENEMY_Z) + 1, PEN_SLATE
    GRect cv, MapX(AP_DEPOT_X) - 1, MapY(AP_DEPOT_Z) - 1, MapX(AP_DEPOT_X) + 1, MapY(AP_DEPOT_Z) + 1, PEN_MUD
    For k = 0 To apNWp - 1
        GRect cv, MapX(ShrA(wpX(k), 16)) - 1, MapY(ShrA(wpZ(k), 16)) - 1, MapX(ShrA(wpX(k), 16)) + 1, MapY(ShrA(wpZ(k), 16)) + 1, PEN_YELLOW
    Next k
    For k = 0 To apNGr - 1
        If grObj(k) <> 0 Then GRect cv, MapX(ShrA(grX(k), 16)) - 1, MapY(ShrA(grZ(k), 16)) - 1, MapX(ShrA(grX(k), 16)) + 1, MapY(ShrA(grZ(k), 16)) + 1, PEN_YELLOW
    Next k
    For k = 1 To apNP - 1
        GRect cv, MapX(ShrA(plX(k), 16)), MapY(ShrA(plZ(k), 16)), MapX(ShrA(plX(k), 16)) + 1, MapY(ShrA(plZ(k), 16)) + 1, _
              IIf(plSide(k) = SIDE_HOME, PEN_BLUE, PEN_RED)
    Next k
    cv.Rect 199, 113, 111, 111, pen(PEN_GREY)
    GText cv, 200 + 54 - 3, 110, PEN_GREY, "N"
End Sub

Public Sub DrawBrief(cv As Object)
    Dim k As Long
    cv.Cls pen(PEN_PANEL)
    GText cv, 8, 14, PEN_GREY, "MISSION " & apMission & " OF " & AP_MISSIONS
    GTextBig cv, 8, 22, PEN_YELLOW, apMissionName(apMission), 2
    GText cv, 8, 50, 1, apMissionPlace(apMission)
    For k = 0 To 3
        GText cv, 8, 68 + k * 12, 1, apBrief(apMission, k)
    Next k
    GBox cv, 6, 122, 188, 218, 0, PEN_GREY
    GText cv, 12, 136, PEN_YELLOW, "PILOT'S RECORD"
    GText cv, 12, 150, 1, apRankName(ApRank(apScore))
    GText cv, 12, 164, 1, "SCORE " & apScore
    GText cv, 12, 178, 1, "VICTORIES " & apKills
    GText cv, 12, 192, 1, "MISSIONS FLOWN " & apMissionsFlown
    GText cv, 12, 206, IIf(apLives > 1, 1, PEN_RED), "AEROPLANES LEFT " & apLives
    DrawMap cv
    GTextCentre cv, 236, IIf(((acTicks \ 10) And 1) <> 0, PEN_YELLOW, 1), "PRESS FIRE TO TAKE OFF"
    GTextCentre cv, 250, PEN_GREY, "ESC: BACK TO THE TITLE"
End Sub

Public Sub DrawHelp(cv As Object, ByVal page As Long)
    Dim k As Long
    cv.Cls pen(PEN_PANEL)
    BigCentre cv, 12, PEN_YELLOW, IIf(page = 1, "HOW TO FLY", "CONTROLS"), 2
    For k = 0 To 12
        GText cv, 8, 52 + k * 14, 1, helpText(page, k)
    Next k
    GText cv, 8, 248, PEN_GREY, "PAGE " & page & " OF 2"
    GText cv, 156, 248, PEN_YELLOW, "HELP: NEXT  FIRE: BACK"
End Sub

Public Sub DrawEntry(cv As Object)
    Dim cur As String
    DrawGame cv
    GBox cv, 40, 70, 280, 180, PEN_PANEL, PEN_YELLOW
    GTextCentre cv, 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre cv, 110, 1, apRankName(ApRank(apScore)) & "   " & apScore
    If (acTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre cv, 140, PEN_GREEN, "YOUR NAME: " & acEntryName & cur
    GTextCentre cv, 166, PEN_GREY, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores(cv As Object)
    Dim i As Long, p As Long
    Scene cv
    GBox cv, 50, 36, 270, 200, PEN_PANEL, PEN_GREY
    BigCentre cv, 44, PEN_YELLOW, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = acEntryRank Then p = PEN_GREEN Else p = 1
        GTextCentre cv, 86 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf(cv As Object)
    cv.Box 0, 0, G_W, 11, pen(0)
    GText cv, 2, 9, PEN_GREEN, PerfText()
End Sub
