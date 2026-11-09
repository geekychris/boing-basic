' Marble Tilt - the picture (a port of render.c) and the shell's effects (game.c):
' the board floating over a dark void, tilted with the stick (shown at twice the
' tilt, so a few degrees read), its floor in runs a row at a time, the walls as
' blocks (runs again), the gates rising and sinking, the bumpers, the exit and
' checkpoints, the marble with its shadow (dropping away through a hole when it
' falls), and the clock, the level and a tilt gauge. Also the title, help pages,
' high scores and the timing overlay.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startLevel As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 the void, 5-6 floor (alternate rows),
' 7 the slab's edge, 8-9 walls (top, side), 10 sand, 11 checkpoint, 12 exit,
' 13-14 gates (shut, open), 15-16 bumpers, 17-18 the marble (body, shine),
' 19 shadow, 20 the start, 26 red, 27 yellow, 28 green, 29 cyan
Private Const PEN_VOID As Long = 4
Private Const PEN_FLOOR As Long = 5
Private Const PEN_EDGE As Long = 7
Private Const PEN_WTOP As Long = 8
Private Const PEN_WSIDE As Long = 9
Private Const PEN_SAND As Long = 10
Private Const PEN_CP As Long = 11
Private Const PEN_EXIT As Long = 12
Private Const PEN_GATE As Long = 13
Private Const PEN_BUMPER As Long = 15
Private Const PEN_MARBLE As Long = 17
Private Const PEN_SHINE As Long = 18
Private Const PEN_SHADOW As Long = 19
Private Const PEN_START As Long = 20
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const WALL_H As Long = 22
Private Const HALF As Long = 240

Private cam As A3Cam
Private cr As Long, sr As Long, cp As Long, sp As Long     ' the board's tilt
Private octX(0 To 7) As Long, octZ(0 To 7) As Long
Private qx(0 To 7) As Long, qy(0 To 7) As Long, qz(0 To 7) As Long
Private tx8(0 To 7) As Long, ty8(0 To 7) As Long, tz8(0 To 7) As Long
Private helpText(1 To 2, 0 To 11) As String
Private voidTop As Long, voidBottom As Long

Public Sub DrawInit()
    Dim h As Variant, i As Long, o As Variant
    GfxPalette Array(&H0, &HFFF, &H123, &H99A, &H113, &H9AB, &H89A, &H445, &H6A8, &H386, &HCA6, &H48E, &H3D5, _
                     &HE44, &H844, &HF53, &HA32, &HDDE, &HFFF, &H334, &HCC8, &H0, &H0, &H0, &H0, &H0, _
                     &HF33, &HFE4, &H6F6, &H5EF, &H0, &H0)
    voidTop = Rgb12(&H225)
    voidBottom = Rgb12(&H1)
    o = Array(9, 0, 6, 6, 0, 9, -6, 6, -9, 0, -6, -6, 0, -9, 6, -6)
    For i = 0 To 7
        octX(i) = o(i * 2)
        octZ(i) = o(i * 2 + 1)
    Next i
    h = Array("TILT THE BOARD TO ROLL THE MARBLE TO", "THE GREEN EXIT BEFORE THE CLOCK RUNS", _
              "OUT. IT KEEPS ROLLING: TILT BACK TO", "SLOW IT DOWN.", "", _
              " HOLES    FALL IN: BACK TO THE LAST", "          CHECKPOINT (BLUE), -3 S", _
              " RED POSTS   BUMPERS: THEY KICK IT", " RED BLOCKS  GATES: OPEN 3 S, SHUT 3 S", _
              " TAN       SAND: IT DRAGS", "", "EIGHT LEVELS. SCORE: 10 A SECOND LEFT.", _
              "ARROWS / WASD    TILT", "UP               ROLLS IT AWAY", "DOWN             ROLLS IT TOWARDS YOU", _
              "P                PAUSE", "B                AUTOPILOT", "HELP / H         THESE PAGES", _
              "ESC              TITLE / QUIT", "", "THE GAUGE AT THE TOP RIGHT SHOWS", _
              "THE TILT. EACH LEVEL DONE SCORES", "100 x THE LEVEL AND 10 FOR EACH", "SECOND LEFT.")
    For i = 0 To 11
        helpText(1, i) = h(i)
        helpText(2, i) = h(12 + i)
    Next i
End Sub

Private Sub Flash(ByVal s As String, ByVal p As Long)
    duFlash = s
    duFlashTimer = 30
    duFlashPen = p
End Sub

Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long
    If loud Then
        For i = 0 To mtNEv - 1
            Select Case mtEv(i).etype
                Case MTE_WALL: Sfx SFX_WALL
                Case MTE_BUMP: Sfx SFX_BUMP
                Case MTE_FALL
                    Sfx SFX_FALL
                    Flash "FELL THROUGH -3 S", 26
                Case MTE_RESPAWN: Sfx SFX_RESPAWN
                Case MTE_CHECKPOINT
                    Sfx SFX_CP
                    Flash "CHECKPOINT", 29
                Case MTE_GATE: Sfx SFX_GATE
                Case MTE_EXIT: Sfx SFX_EXIT
                Case MTE_TIMEOUT: Flash "TIME UP", 26
                Case MTE_OVER: Sfx SFX_OVER
                Case MTE_WIN: Sfx SFX_WIN
            End Select
        Next i
    End If
    mtNEv = 0
End Sub

Public Sub AgeEffects()
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
End Sub

' ---------- the board ----------
' a point on the board to camera space (ox, oy, oz): rolled, then pitched
Private Sub Bpt(ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Dim x1 As Long, y1 As Long, z2 As Long, y2 As Long, t As Long
    ' (t - (t And 65535)) \ 65536 is t >> 16 rounding down, in integers
    t = x * cr + y * sr: x1 = (t - (t And 65535)) \ 65536
    t = y * cr - x * sr: y1 = (t - (t And 65535)) \ 65536
    t = z * cp + y1 * sp: z2 = (t - (t And 65535)) \ 65536
    t = y1 * cp - z * sp: y2 = (t - (t And 65535)) \ 65536
    CamXform cam, x1, y2, z2
End Sub

Private Sub BQuad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                  ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, _
                  ByVal bias As Long, ByVal col As Long)
    Dim ax As Long, ay As Long, az As Long, bx As Long, by As Long, bz As Long, cx As Long, cy As Long, cz As Long
    Bpt x0, y0, z0: ax = ox: ay = oy: az = oz
    Bpt x1, y1, z1: bx = ox: by = oy: bz = oz
    Bpt x2, y2, z2: cx = ox: cy = oy: cz = oz
    Bpt x3, y3, z3
    A3Quad cam, (az + bz + cz + oz) \ 4 + bias, col, ax, ay, az, bx, by, bz, cx, cy, cz, ox, oy, oz
End Sub

' a flat rectangle on the board at height y
Private Sub Tile(ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal y As Long, ByVal col As Long, ByVal bias As Long)
    BQuad x0, y, z0, x1, y, z0, x1, y, z1, x0, y, z1, bias, col
End Sub

' a block: its top, its near side (-z), and the end facing the camera
Private Sub Block(ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal h As Long, _
                  ByVal top As Long, ByVal side As Long, ByVal nearSide As Boolean)
    Tile x0, x1, z0, z1, h, top, -2
    If nearSide Then BQuad x0, 0, z0, x1, 0, z0, x1, h, z0, x0, h, z0, -1, side
    If x1 < 0 Then BQuad x1, 0, z0, x1, 0, z1, x1, h, z1, x1, h, z0, -1, side
    If x0 > 0 Then BQuad x0, 0, z0, x0, 0, z1, x0, h, z1, x0, h, z0, -1, side
End Sub

Private Function FloorPen(ByVal ch As Long, ByVal row As Long) As Long
    Select Case ch
        Case CH_SAND: FloorPen = PEN_SAND
        Case CH_CHECK: FloorPen = PEN_CP
        Case CH_EXIT: FloorPen = PEN_EXIT
        Case CH_START: FloorPen = PEN_START
        Case CH_HOLE, CH_WALL: FloorPen = -1
        Case Else: FloorPen = PEN_FLOOR + (row And 1)
    End Select
End Function

Private Sub Board()
    Dim r As Long, c As Long, e As Long, p As Long, z0 As Long, z1 As Long
    ' the floor, in runs along each row; then the slab's front edge
    A3Begin 2000
    For r = 0 To MT_N - 1
        z1 = (6 - r) * MT_CELL
        z0 = z1 - MT_CELL
        c = 0
        Do While c < MT_N
            p = FloorPen(mtCell(r, c), r)
            If p < 0 Then
                c = c + 1
            Else
                e = c + 1
                Do While e < MT_N
                    If FloorPen(mtCell(r, e), r) <> p Then Exit Do
                    e = e + 1
                Loop
                Tile -HALF + c * MT_CELL, -HALF + e * MT_CELL, z0, z1, 0, p, 40
                c = e
            End If
        Loop
    Next r
    BQuad -HALF, 0, -HALF, HALF, 0, -HALF, HALF, -16, -HALF, -HALF, -16, -HALF, 30, PEN_EDGE
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

Private Sub Blocks()
    Dim r As Long, c As Long, e As Long, k As Long, j As Long, x0 As Long, z0 As Long, z1 As Long
    Dim ch As Long, nearSide As Boolean, a As Long, px As Long, pz As Long, cx As Long, cz As Long
    For r = 0 To MT_N - 1
        z1 = (6 - r) * MT_CELL
        z0 = z1 - MT_CELL
        c = 0
        Do While c < MT_N
            x0 = -HALF + c * MT_CELL
            ch = mtCell(r, c)
            If ch = CH_GATE Then
                If mtGatesOpen Then
                    Block x0, x0 + MT_CELL, z0, z1, 4, PEN_GATE + 1, PEN_GATE + 1, True
                Else
                    Block x0, x0 + MT_CELL, z0, z1, WALL_H, PEN_GATE, PEN_GATE + 1, True
                End If
                c = c + 1
            ElseIf ch = CH_BUMPER Then
                cx = x0 + MT_CELL \ 2
                cz = z0 + MT_CELL \ 2
                For k = 0 To 7
                    a = k * 8192 + 4096
                    px = cx + ShrA(A3Sin(a) * 13, 16)
                    pz = cz + ShrA(A3Cos(a) * 13, 16)
                    Bpt px, 18, pz: tx8(k) = ox: ty8(k) = oy: tz8(k) = oz
                    Bpt px, 0, pz: qx(k) = ox: qy(k) = oy: qz(k) = oz
                Next k
                For k = 0 To 7                ' its sides (the top, drawn last, covers the far ones)
                    j = (k + 1) And 7
                    pvx(0) = qx(k): pvy(0) = qy(k): pvz(0) = qz(k)
                    pvx(1) = qx(j): pvy(1) = qy(j): pvz(1) = qz(j)
                    pvx(2) = tx8(j): pvy(2) = ty8(j): pvz(2) = tz8(j)
                    pvx(3) = tx8(k): pvy(3) = ty8(k): pvz(3) = tz8(k)
                    A3Poly cam, (qz(k) + qz(j)) \ 2, PEN_BUMPER + 1, 4
                Next k
                For k = 0 To 7
                    pvx(k) = tx8(k): pvy(k) = ty8(k): pvz(k) = tz8(k)
                Next k
                A3Poly cam, (tz8(0) + tz8(4)) \ 2 - 6, PEN_BUMPER, 8
                c = c + 1
            ElseIf ch <> CH_WALL Then
                c = c + 1
            Else
                e = c + 1
                Do While e < MT_N
                    If mtCell(r, e) <> CH_WALL Then Exit Do
                    e = e + 1
                Loop
                ' its near side shows unless a wall is in front of all of it
                nearSide = (r = MT_N - 1)
                k = c
                Do While k < e And Not nearSide
                    If mtCell(r + 1, k) <> CH_WALL Then nearSide = True
                    k = k + 1
                Loop
                Block x0, -HALF + e * MT_CELL, z0, z1, WALL_H, PEN_WTOP, PEN_WSIDE, nearSide
                c = e
            End If
        Loop
    Next r
End Sub

Private Sub Marble()
    Dim x As Long, z As Long, y As Long, r As Long, k As Long, t As Long, cx As Long, cy As Long, cz As Long
    x = ShrA(mtX, 16)
    z = ShrA(mtZ, 16)
    y = MT_R
    r = 9
    If mtFalling Then                    ' dropping away below the board
        t = MT_FALL_T - mtFalling
        y = MT_R - t * t
        r = 9 - t \ 4
        If r < 2 Then r = 2
    Else
        For k = 0 To 7
            Bpt x + octX(k) + 3, 1, z + octZ(k) - 3
            pvx(k) = ox: pvy(k) = oy: pvz(k) = oz
        Next k
        A3Poly cam, pvz(0) + 30, PEN_SHADOW, 8
    End If
    Bpt x, y, z
    If oz < NEAR_Z + 10 Then Exit Sub
    cx = ox: cy = oy: cz = oz
    For k = 0 To 7
        pvx(k) = cx + (octX(k) * r) \ 9: pvy(k) = cy + (octZ(k) * r) \ 9: pvz(k) = cz
    Next k
    A3Poly cam, cz - 10, PEN_MARBLE, 8
    For k = 0 To 7
        pvx(k) = cx - 3 + (octX(k) * r) \ 30: pvy(k) = cy + 3 + (octZ(k) * r) \ 30: pvz(k) = cz
    Next k
    A3Poly cam, cz - 11, PEN_SHINE, 8
End Sub

Private Sub VoidBands()
    Dim y As Long, r As Long, g As Long, b As Long
    For y = 0 To G_H - 1 Step 8
        r = (voidTop And 255) + ((voidBottom And 255) - (voidTop And 255)) * y \ G_H
        g = ((voidTop \ 256) And 255) + (((voidBottom \ 256) And 255) - ((voidTop \ 256) And 255)) * y \ G_H
        b = ((voidTop \ 65536) And 255) + (((voidBottom \ 65536) And 255) - ((voidTop \ 65536) And 255)) * y \ G_H
        gcv.Box 0, y, G_W, 8, RGB(r, g, b)
    Next y
End Sub

Private Sub Scene()
    Dim ar As Long, ap As Long
    ar = A3Angle(mtRoll * 2)
    ap = A3Angle(mtPitch * 2)
    cr = A3Cos(ar): sr = A3Sin(ar)
    cp = A3Cos(ap): sp = A3Sin(ap)
    cam.x = 0: cam.y = 470: cam.z = -430
    cam.yaw = 0
    cam.pitch = 7600
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, G_H \ 2 + 6, 266
    CamSetup cam
    VoidBands
    Board
    A3Begin 2000
    Blocks
    Marble
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

Private Sub Hud()
    Dim gx As Long, gy As Long, p As Long
    gx = G_W - 26
    gy = 26
    GTextShadow 4, 10, PEN_YELLOW, mtLevel & " " & MtLevelName(mtLevel)
    If mtTimeLeft < 250 And (mtTicks And 8) <> 0 Then p = PEN_RED Else p = 1
    GTextBig 4, 16, p, CStr(mtTimeLeft \ 25), 2
    GTextShadow 4, 250, 3, "SCORE " & mtScore
    If mtFalls Then GTextShadow 120, 250, 3, "FALLS " & mtFalls
    ' the tilt gauge
    gcv.Circle gx, gy, 18, pen(2), True
    GRect gx - 18, gy, gx + 18, gy, 3
    GRect gx, gy - 18, gx, gy + 18, 3
    gcv.Circle gx + (mtRoll * 15) \ MT_TILT_MAX, gy - (mtPitch * 15) \ MT_TILT_MAX, 3, pen(PEN_YELLOW), True
    If mtGatesOpen = 0 Then GTextShadow 230, 250, PEN_RED, "GATES SHUT"
    If duAutoplay Then GTextShadow 230, 238, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim p As Long
    Scene
    Hud
    If mtBetween Then
        GTextBigCentre 90, PEN_GREEN, "THROUGH!", 2
        If mtLevel < MT_LEVELS Then GTextCentre 120, 1, "NEXT: " & MtLevelName(mtLevel + 1)
    End If
    If isPlay And mtLevelTicks < 50 And mtBetween = 0 Then
        GTextCentre 120, PEN_YELLOW, "LEVEL " & mtLevel & ": " & MtLevelName(mtLevel)
    End If
    If isOver Then
        If mtWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 50, 80, 270, 160, 2, p
        If mtWon Then GTextBigCentre 88, p, "ALL THROUGH", 2 Else GTextBigCentre 88, p, "TIME UP", 2
        GTextCentre 122, PEN_YELLOW, "LEVEL " & mtLevel & "  FALLS " & mtFalls
        GTextCentre 136, 1, "SCORE " & mtScore
        If duStateTimer = 0 Then GTextCentre 152, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 128, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 60, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                             ' the autopilot rolls behind the title
    GTextBig 52, 14, 0, "MARBLE", 6
    GTextBig 50, 12, PEN_YELLOW, "MARBLE", 6
    GTextBig 98, 70, 0, "TILT", 6
    GTextBig 96, 68, PEN_CYAN, "TILT", 6
    GBox 40, 200, 280, 254, 2, 3
    GTextCentre 214, PEN_GREEN, "LEVEL " & startLevel & ": " & MtLevelName(startLevel)
    If (mtTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 230, p, "PRESS SPACE TO PLAY"
    GTextCentre 246, 3, "BEST " & hsScore(0) & "   HELP: HOW TO PLAY"
End Sub

Public Sub DrawHelp(ByVal page As Long)
    Dim k As Long
    gcv.Box 0, 0, G_W, G_H, pen(2)
    If page = 1 Then GTextBigCentre 14, PEN_YELLOW, "HOW TO PLAY", 2 Else GTextBigCentre 14, PEN_YELLOW, "CONTROLS", 2
    For k = 0 To 11
        GText 12, 58 + k * 14, 1, helpText(page, k)
    Next k
    GText 8, 248, 3, "PAGE " & page & " OF 2"
    GText 156, 248, PEN_YELLOW, "HELP: NEXT  SPACE: BACK"
End Sub

Public Sub DrawEntry(ByVal nm As String)
    Dim cur As String
    Scene
    GBox 40, 70, 280, 180, 2, PEN_YELLOW
    GTextCentre 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre 110, 1, "PLACE " & (HsRank(mtScore) + 1) & "   " & Format$(mtScore, "0000000")
    If (mtTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre 140, PEN_GREEN, "YOUR NAME: " & nm & cur
    GTextCentre 166, 3, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores()
    Dim i As Long, p As Long
    Scene
    GBox 50, 36, 270, 200, 2, 3
    GTextBigCentre 44, PEN_YELLOW, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = entryRank Then p = PEN_GREEN Else p = 1
        GTextCentre 86 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf()
    gcv.Box 0, 226, G_W, 11, pen(0)
    GText 2, 235, PEN_GREEN, PerfText()
End Sub
