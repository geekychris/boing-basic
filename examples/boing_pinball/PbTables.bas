' PbTables - the three tables (a port of pb_tables.c). They share the cabinet:
' the outer walls and the top arch, the plunger lane, the flippers, the
' slingshots, the inlanes and outlanes and the three top lanes. Comet Tour is the
' browser's table; Deep Dive and Robot Foundry are new upper playfields with the
' same kinds of parts. (The C's flat playfield art, used only without the
' paintings, is left out: this port always has the paintings.)
Option Explicit

Private Const ANG_PI As Long = 32768

Private Function MX(ByVal x As Long) As Long
    MX = 2 * PB_MID - x
End Function

Private Function DEG(ByVal d As Long) As Long
    DEG = (d * 205887) \ 180
End Function

Private Function WallF(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal r As Long, _
                       ByVal e As Long, ByVal kind As Long, ByVal h As Long) As Long
    If tNseg >= PB_MAX_SEG Then
        WallF = -1
        Exit Function
    End If
    SegInit tNseg, ax, ay, bx, by, r, e, kind
    sg(tNseg).h = h
    WallF = tNseg
    tNseg = tNseg + 1
End Function

Private Function Wall(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal r As Long, _
                      ByVal e As Long, ByVal kind As Long, ByVal h As Long) As Long
    Wall = WallF(ax * 65536, ay * 65536, bx * 65536, by * 65536, r, e, kind, h)
End Function

' a chain of walls through the points of p (x, y pairs)
Private Sub Poly(p As Variant, ByVal r As Long, ByVal e As Long, ByVal kind As Long, ByVal h As Long, ByVal mirror As Boolean)
    Dim i As Long, n As Long, ax As Long, bx As Long
    n = (UBound(p) + 1) \ 2
    For i = 0 To n - 2
        ax = p(i * 2): bx = p(i * 2 + 2)
        If mirror Then ax = MX(ax): bx = MX(bx)
        Wall ax, p(i * 2 + 1), bx, p(i * 2 + 3), r, e, kind, h
    Next i
End Sub

' an arc of n walls, centre (cx, cy), from angle a0 to a1 (16-bit angles)
Private Sub Arc(ByVal cx As Long, ByVal cy As Long, ByVal rad As Long, ByVal a0 As Long, ByVal a1 As Long, ByVal n As Long, _
                ByVal r As Long, ByVal e As Long, ByVal kind As Long, ByVal h As Long)
    Dim i As Long, a As Long, px As Long, py As Long, x As Long, y As Long
    For i = 0 To n
        a = a0 + ((a1 - a0) * i) \ n
        x = cx * 65536 + rad * A3Cos(a)
        y = cy * 65536 + rad * A3Sin(a)
        If i Then WallF px, py, x, y, r, e, kind, h
        px = x: py = y
    Next i
End Sub

Private Sub Gate(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal owx As Long, ByVal owy As Long)
    Dim s As Long
    s = Wall(ax, ay, bx, by, 131072, 29491, SK_GATE, 12)
    If s >= 0 Then sg(s).owx = owx: sg(s).owy = owy
End Sub

Private Sub Circ(ByVal x As Long, ByVal y As Long, ByVal r As Long, ByVal e As Long, ByVal bumper As Long, ByVal h As Long)
    Dim c As Long
    If tNcirc >= PB_MAX_CIRC Then Exit Sub
    c = tNcirc
    tNcirc = tNcirc + 1
    cc(c).cx = x * 65536: cc(c).cy = y * 65536: cc(c).r = r * 65536: cc(c).e = e
    cc(c).bumper = bumper: cc(c).h = h
    cc(c).id = c
End Sub

Private Sub Post(ByVal x As Long, ByVal y As Long)
    Circ x, y, 6, 32768, 0, 34
End Sub

Private Sub Bumper(ByVal x As Long, ByVal y As Long)
    Circ x, y, 24, 32768, 1, 40
End Sub

Private Sub Sensor(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal kind As Long, ByVal idx As Long)
    Dim s As Long
    If tNsens >= PB_MAX_SENS Then Exit Sub
    s = tNsens
    tNsens = tNsens + 1
    sn(s).ax = ax * 65536: sn(s).ay = ay * 65536: sn(s).bx = bx * 65536: sn(s).by = by * 65536
    sn(s).kind = kind: sn(s).idx = idx
    If ax < bx Then sn(s).bb0 = ax - 18: sn(s).bb2 = bx + 18 Else sn(s).bb0 = bx - 18: sn(s).bb2 = ax + 18
    If ay < by Then sn(s).bb1 = ay - 18: sn(s).bb3 = by + 18 Else sn(s).bb1 = by - 18: sn(s).bb3 = ay + 18
End Sub

Private Sub Drop(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal bank As Long)
    Dim s As Long
    s = Wall(ax, ay, bx, by, 262144, 22937, SK_DROP, 26)
    If s < 0 Then Exit Sub
    sg(s).id = tNdrop
    sg(s).bank = bank
    dropSeg(tNdrop) = s
    tNdrop = tNdrop + 1
    If bank + 1 > tNbank Then tNbank = bank + 1
End Sub

Private Sub Flipper(ByVal side As Long, ByVal px As Long, ByVal py As Long, ByVal ln As Long, ByVal r1 As Long, ByVal r2 As Long, _
                    ByVal rest As Long, ByVal up As Long)
    Dim f As Long
    f = tNflip
    tNflip = tNflip + 1
    fl(f).side = side
    fl(f).px = px * 65536: fl(f).py = py * 65536: fl(f).ln = ln * 65536: fl(f).r1 = r1: fl(f).r2 = r2
    fl(f).rest = DEG(rest): fl(f).up = DEG(up)
End Sub

Private Sub Spinner(ByVal ax As Long, ByVal y As Long, ByVal bx As Long)
    Dim i As Long
    i = tNspin
    tNspin = tNspin + 1
    Sensor ax, y, bx, y, SN_SPIN, i
    spX(i) = ((ax + bx) \ 2) * 65536
    spY(i) = y * 65536
End Sub

' a ramp's entrance channel (two walls, a cap, posts) and its path (x, y, height triples)
Private Sub Ramp(ByVal x0 As Long, ByVal x1 As Long, ByVal y0 As Long, p As Variant, ByVal exitX As Long, ByVal exitY As Long)
    Dim r As Long, i As Long, n As Long, b As Long
    r = tNramp
    n = (UBound(p) + 1) \ 3
    Wall x0, y0, x0, y0 + 76, 262144, 29491, SK_WALL, 30
    Wall x1, y0, x1, y0 + 76, 262144, 29491, SK_WALL, 30
    ' the cap, peaked (the browser's is flat) so a ball can't sit on top of it
    Wall x0, y0 + 84, (x0 + x1) \ 2, y0 + 96, 196608, 29491, SK_WALL, 30
    Wall (x0 + x1) \ 2, y0 + 96, x1, y0 + 84, 196608, 29491, SK_WALL, 30
    Post x0, y0
    Post x1, y0
    Sensor x0, y0 + 58, x1, y0 + 58, SN_RAMPIN, r
    rampN(r) = n
    b = r * 16
    For i = 0 To n - 1
        rpx(b + i) = p(i * 3): rpy(b + i) = p(i * 3 + 1): rpz(b + i) = p(i * 3 + 2)
    Next i
    rprof(b) = 0
    For i = 1 To n - 1
        rprof(b + i) = rprof(b + i - 1) + FHypot3((rpx(b + i) - rpx(b + i - 1)) * 65536, (rpy(b + i) - rpy(b + i - 1)) * 65536, _
                                                   (rpz(b + i) - rpz(b + i - 1)) * 65536)
    Next i
    rExitX(r) = exitX * 65536: rExitY(r) = exitY * 65536: rExitVy(r) = -24903680
    tNramp = tNramp + 1
End Sub

Private Sub Lamp(ByVal id As Long, ByVal x As Long, ByVal y As Long, ByVal r As Long, ByVal col As Long)
    lampX(id) = x: lampY(id) = y: lampR(id) = r: lampCol(id) = col
End Sub

' ---------------------------------------------------------------- shared

Private Sub Cabinet()
    Dim i As Long, s As Long, sl As Variant
    ' the outer shell: the left wall with its kink into the outlane, the top arch, the right wall
    Poly Array(20, -60, 20, 380, 0, 470, 0, 780), 196608, 26214, SK_OUTER, 45, False
    Arc 260, 780, 260, ANG_PI, 0, 44, 196608, 26214, SK_OUTER, 45
    Wall 520, 780, 520, -60, 196608, 26214, SK_OUTER, 45
    ' the plunger lane: its inner wall and floor; the right outlane's outer wall
    Wall 478, -60, 478, 776, 262144, 29491, SK_WALL, 30
    Wall 478, 30, 520, 30, 196608, 13107, SK_FLOOR, 8
    Poly Array(458, -60, 458, 380, 478, 470), 196608, 26214, SK_OUTER, 45, False
    Gate 478, 780, 520, 796, 0, 1
    ' the inlane / outlane separators leading into the flipper pivots
    Poly Array(58, 360, 58, 190, 150, 132), 262144, 29491, SK_WALL, 30, False
    Poly Array(58, 360, 58, 190, 150, 132), 262144, 29491, SK_WALL, 30, True
    ' slingshots: the kicking face towards the middle, rubber-backed walls behind
    sl = Array(100, 345, 100, 225, 150, 192)
    Wall sl(0), sl(1), sl(2), sl(3), 327680, 29491, SK_WALL, 30
    Wall sl(2), sl(3), sl(4), sl(5), 327680, 29491, SK_WALL, 30
    s = Wall(sl(0), sl(1), sl(4), sl(5), 327680, 39321, SK_SLING, 30)
    If s >= 0 Then sg(s).id = 0
    Wall MX(sl(0)), sl(1), MX(sl(2)), sl(3), 327680, 29491, SK_WALL, 30
    Wall MX(sl(2)), sl(3), MX(sl(4)), sl(5), 327680, 29491, SK_WALL, 30
    s = Wall(MX(sl(4)), sl(5), MX(sl(0)), sl(1), 327680, 39321, SK_SLING, 30)
    If s >= 0 Then sg(s).id = 1
    ' the top lanes
    For i = 0 To 3
        Wall 150 + 60 * i, 800, 150 + 60 * i, 862, 262144, 29491, SK_WALL, 30
    Next i
    For i = 0 To 2
        Sensor 150 + 60 * i, 832, 210 + 60 * i, 832, SN_LANE, i
    Next i
    Post 58, 360
    Post MX(58), 360
    Sensor 58, 282, 100, 282, SN_IN, 0
    Sensor 20, 262, 58, 262, SN_OUT, 0
    Sensor 378, 282, 420, 282, SN_IN, 1
    Sensor 420, 262, 458, 262, SN_OUT, 1
    Sensor 478, 760, 520, 760, SN_LANEOUT, 0
    Flipper 0, 150, 126, 76, 720896, 425984, -30, 28
    Flipper 1, MX(150), 126, 76, 720896, 425984, 210, 152
    plungerX = 499 * 65536
    plungerRest = 30 * 65536 + PB_R
    ' the lamps every table has: the top lanes, the bonus multiplier, the ball save
    For i = 0 To 2
        Lamp L_LANE0 + i, 180 + 60 * i, 812, 11, LC_BLUE
    Next i
    For i = 0 To 3
        Lamp L_X2 + i, 194 + 30 * i, 360, 8, LC_YELLOW
    Next i
    Lamp L_SAVE, 239, 210, 10, LC_GREEN
End Sub

' the left orbit: up-only past a spinner, round the top arch
Private Sub LeftOrbit()
    Gate 0, 780, 50, 766, 0, 1
    Wall 50, 470, 50, 760, 262144, 29491, SK_WALL, 30
    Post 50, 470
    Spinner 0, 640, 50
    Lamp L_SPIN0, 25, 590, 8, LC_YELLOW
End Sub

Private Sub CometTour()
    Dim i As Long
    tName = "COMET TOUR"
    tBlurb = "THE ORIGINAL: RAMP, ORBIT, SAUCER"
    tMission(0) = "VENUS FOG": tMission(1) = "MARS ROCKS": tMission(2) = "MERCURY DASH"
    tMission(3) = "JUPITER STORM": tMission(4) = "SATURN RINGS"
    tTheme = TB_COMET
    Cabinet
    LeftOrbit
    Ramp 330, 378, 520, Array(354, 590, 0, 356, 680, 28, 350, 770, 58, 318, 870, 82, 250, 915, 92, 170, 905, 90, _
                              105, 850, 80, 72, 760, 64, 66, 640, 46, 72, 520, 30, 78, 420, 16, 79, 372, 8), 79, 362
    Bumper 188, 700
    Bumper 292, 700
    Bumper 240, 618
    For i = 0 To 2
        Drop 462, 480 + i * 36, 462, 508 + i * 36, 0
    Next i
    saucerX = 112 * 65536: saucerY = 560 * 65536: saucerR = 15 * 65536
    For i = 0 To 2
        Lamp L_LOCK0 + i, 354, 492 - i * 34, 9, LC_BLUE
    Next i
    Lamp L_JACKPOT, 354, 392, 12, LC_YELLOW
    For i = 0 To 4
        Lamp L_M0 + i, 160 + i * 40, 440, 10, LC_RED
    Next i
    Lamp L_MISSION, 112, 604, 10, LC_RED
    For i = 0 To 2
        Lamp L_DROP0 + i, 432, 494 + i * 36, 6, LC_ORANGE
    Next i
    Lamp L_SUPER, 239, 520, 16, LC_MAGENTA
End Sub

Private Sub DeepDive()
    Dim i As Long
    tName = "DEEP DIVE"
    tBlurb = "FOUR JELLYFISH, AN UPPER FLIPPER"
    tMission(0) = "CORAL REEF": tMission(1) = "SHIPWRECK": tMission(2) = "WHIRLPOOL"
    tMission(3) = "SEA SERPENT": tMission(4) = "PEARL DIVER"
    tTheme = TB_DEEP
    Cabinet
    ' the right orbit: up-only past a spinner, beside the plunger lane
    Wall 436, 480, 436, 740, 262144, 29491, SK_WALL, 30
    Post 436, 480
    Gate 436, 742, 478, 754, 0, 1
    Spinner 436, 640, 478
    Lamp L_SPIN0, 457, 600, 8, LC_YELLOW
    ' the ramp on the left, over the top and down to the right inlane
    Ramp 116, 164, 520, Array(140, 590, 0, 138, 680, 28, 144, 770, 58, 176, 860, 82, 240, 908, 92, 310, 898, 90, _
                              372, 846, 80, 404, 760, 64, 412, 640, 46, 406, 520, 30, 400, 420, 16, 399, 372, 8), 399, 362
    ' jellyfish: four bumpers
    Bumper 232, 760
    Bumper 170, 690
    Bumper 300, 700
    Bumper 250, 640
    ' the wreck: a bank of three targets across the middle
    For i = 0 To 2
        Drop 214 + i * 36, 560, 242 + i * 36, 560, 0
    Next i
    ' an upper flipper on the left wall, fed by a guide that ends at its pivot
    Wall 0, 566, 40, 506, 262144, 29491, SK_WALL, 30
    Flipper 0, 40, 500, 60, 589824, 360448, -25, 25
    saucerX = 380 * 65536: saucerY = 620 * 65536: saucerR = 15 * 65536
    For i = 0 To 2
        Lamp L_LOCK0 + i, 140, 492 - i * 34, 9, LC_BLUE
    Next i
    Lamp L_JACKPOT, 140, 392, 12, LC_YELLOW
    For i = 0 To 4
        Lamp L_M0 + i, 180 + i * 30, 470, 9, LC_RED
    Next i
    Lamp L_MISSION, 380, 660, 10, LC_RED
    For i = 0 To 2
        Lamp L_DROP0 + i, 228 + i * 36, 530, 6, LC_ORANGE
    Next i
    Lamp L_SUPER, 239, 420, 16, LC_MAGENTA
End Sub

Private Sub RobotFoundry()
    Dim i As Long
    tName = "ROBOT FOUNDRY"
    tBlurb = "TWO TARGET BANKS, A CENTRE RAMP"
    tMission(0) = "POWER UP": tMission(1) = "ASSEMBLY": tMission(2) = "TURBINE"
    tMission(3) = "CONVEYOR": tMission(4) = "CIRCUIT"
    tTheme = TB_FOUNDRY
    Cabinet
    LeftOrbit
    ' the centre ramp, round the top right and down to the right inlane
    Ramp 215, 263, 600, Array(239, 670, 0, 239, 750, 26, 252, 840, 56, 300, 905, 80, 370, 890, 88, 410, 820, 78, _
                              420, 720, 62, 416, 620, 46, 408, 520, 30, 402, 430, 16, 399, 372, 8), 399, 362
    ' three bumpers at the top left
    Bumper 110, 700
    Bumper 160, 760
    Bumper 165, 650
    ' bank 1: three targets on the right wall, as on Comet Tour; bank 2: three across the left
    For i = 0 To 2
        Drop 462, 480 + i * 36, 462, 508 + i * 36, 0
    Next i
    For i = 0 To 2
        Drop 86 + i * 36, 520, 114 + i * 36, 520, 1
    Next i
    ' an upper flipper on the right wall, fed by a guide that ends at its pivot
    Wall 478, 706, 462, 646, 262144, 29491, SK_WALL, 30
    Flipper 1, 462, 640, 58, 589824, 360448, 205, 155
    saucerX = 360 * 65536: saucerY = 590 * 65536: saucerR = 15 * 65536
    For i = 0 To 2
        Lamp L_LOCK0 + i, 239, 572 - i * 34, 9, LC_BLUE
    Next i
    Lamp L_JACKPOT, 239, 470, 12, LC_YELLOW
    For i = 0 To 4
        Lamp L_M0 + i, 300 + i * 26, 470 - i * 14, 9, LC_RED
    Next i
    Lamp L_MISSION, 360, 550, 10, LC_RED
    For i = 0 To 2
        Lamp L_DROP0 + i, 432, 494 + i * 36, 6, LC_ORANGE
    Next i
    For i = 0 To 2
        Lamp L_DROP0 + 3 + i, 100 + i * 36, 494, 6, LC_ORANGE
    Next i
    Lamp L_SUPER, 239, 400, 16, LC_MAGENTA
End Sub

' ---------------------------------------------------------------- the grid

Private Sub GridAdd(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal ref As Long)
    Dim gx As Long, gy As Long, gx0 As Long, gx1 As Long, gy0 As Long, gy1 As Long, c As Long
    gx0 = ShrA(x0, 6): gx1 = ShrA(x1, 6): gy0 = ShrA(y0 + 64, 6): gy1 = ShrA(y1 + 64, 6)
    If gx0 < 0 Then gx0 = 0
    If gy0 < 0 Then gy0 = 0
    If gx1 >= PB_GX Then gx1 = PB_GX - 1
    If gy1 >= PB_GY Then gy1 = PB_GY - 1
    For gy = gy0 To gy1
        For gx = gx0 To gx1
            c = gy * PB_GX + gx
            If ngrid(c) < PB_GMAX Then
                grid(c * PB_GMAX + ngrid(c)) = ref
                ngrid(c) = ngrid(c) + 1
            Else
                ngrid(c) = PB_GMAX + 1                ' overflowed: the tests look for this
            End If
        Next gx
    Next gy
End Sub

Private Sub BuildGrid()
    Dim i As Long, g As Long, x As Long, y As Long
    For i = 0 To tNseg - 1
        GridAdd sg(i).bb0, sg(i).bb1, sg(i).bb2, sg(i).bb3, i
    Next i
    For i = 0 To tNcirc - 1
        g = FInt(cc(i).r + PB_R) + 4
        x = FInt(cc(i).cx)
        y = FInt(cc(i).cy)
        GridAdd x - g, y - g, x + g, y + g, 4096 + i
    Next i
    For i = 0 To tNsens - 1
        GridAdd sn(i).bb0, sn(i).bb1, sn(i).bb2, sn(i).bb3, 8192 + i
    Next i
End Sub

Public Sub PbBuildTable(ByVal which As Long)
    Dim i As Long
    PbCoreInit
    tNseg = 0: tNcirc = 0: tNsens = 0: tNflip = 0: tNramp = 0: tNspin = 0: tNdrop = 0: tNbank = 0
    For i = 0 To L_COUNT - 1
        lampX(i) = 0: lampY(i) = 0: lampR(i) = 0: lampCol(i) = 0
    Next i
    For i = 0 To PB_GY * PB_GX - 1
        ngrid(i) = 0
    Next i
    For i = 0 To 1
        rampN(i) = 0
    Next i
    saucerX = 0: saucerY = 0: saucerR = 0
    Select Case which
        Case TB_DEEP: DeepDive
        Case TB_FOUNDRY: RobotFoundry
        Case Else: CometTour
    End Select
    BuildGrid
End Sub
