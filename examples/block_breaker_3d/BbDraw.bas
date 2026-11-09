' Block Breaker 3D - the picture (a port of render.c) and the shell's effects
' (game.c): the tunnel, striped along its length so its depth reads; the bricks
' (only the faces you can see); the ball with its shadow and a ring round the
' tunnel at its depth; capsules; bits of broken bricks; the paddle's frame; the
' score line, title, help, high scores and the timing overlay. The camera sits
' behind the paddle and leans a little with it.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startLevel As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean
Public partSeed As Long

' pens: 0 black, 1 white, 2 shadow, 3 grey, 4 the back wall, 5-6 the floor's
' stripes, 7-8 the ceiling's, 9-10 the side walls', 11-22 the coloured bricks
' (lit, shaded), 23-24 tough, 25-26 steel, 27 the ball, 28 the paddle,
' 29 capsules and bonus bricks, 30 the depth ring, 31 yellow
Private Const PEN_BACK As Long = 4
Private Const PEN_FLOOR As Long = 5
Private Const PEN_CEIL As Long = 7
Private Const PEN_SIDE As Long = 9
Private Const PEN_BRICK As Long = 11
Private Const PEN_TOUGH As Long = 23
Private Const PEN_STEEL As Long = 25
Private Const PEN_BALL As Long = 27
Private Const PEN_PADDLE As Long = 28
Private Const PEN_CAP As Long = 29
Private Const PEN_RING As Long = 30
Private Const PEN_YELLOW As Long = 31
Private Const PEN_RED As Long = 11
Private Const PEN_GREEN As Long = 17
Private Const PEN_CYAN As Long = 19
Private Const WALL_Z0 As Long = -200
Private Const SEG As Long = 100

Private Const MAX_PARTS As Long = 48
Private partX(0 To 47) As Long, partY(0 To 47) As Long, partZ(0 To 47) As Long
Private partVX(0 To 47) As Long, partVY(0 To 47) As Long, partVZ(0 To 47) As Long
Private partLife(0 To 47) As Long, partCol(0 To 47) As Long

Private cam As A3Cam
Private octX(0 To 7) As Long, octY(0 To 7) As Long
Private helpText(1 To 2, 0 To 11) As String

Public Sub DrawInit()
    Dim h As Variant, i As Long, o As Variant
    GfxPalette Array(&H0, &HFFF, &H102, &H99A, &H214, &H325, &H436, &H213, &H324, &H224, &H335, _
                     &HF33, &HA12, &HF83, &HB52, &HFE4, &HBA2, &H5E4, &H2A3, &H3DF, &H19A, &H56F, &H23B, _
                     &HCCD, &H889, &H99A, &H556, &HFFE, &H4FD, &HF4E, &H6F6, &HFD3)
    o = Array(10, 0, 7, 7, 0, 10, -7, 7, -10, 0, -7, -7, 0, -10, 7, -7)
    For i = 0 To 7
        octX(i) = o(i * 2)
        octY(i) = o(i * 2 + 1)
    Next i
    h = Array("THE BALL FLIES DOWN THE TUNNEL TO THE", "BRICKS AT THE FAR END AND BACK. MOVE THE", _
              "PADDLE ANY WAY TO MEET IT: WHERE IT HITS", "THE PADDLE STEERS IT. THE GREEN RING ON", _
              "THE WALLS SHOWS HOW FAR AWAY IT IS.", "", "SILVER BRICKS TAKE SEVERAL HITS. GREY", _
              "STEEL NEVER BREAKS. PINK BRICKS DROP A", "CAPSULE - CATCH IT WITH THE PADDLE:", _
              " W WIDE PADDLE    S SLOW BALL", " L EXTRA LIFE     P PLOUGH THROUGH", "CLEAR ALL 8 LEVELS TO WIN.", _
              "ARROWS / WASD      MOVE", "SPACE              SERVE", "P                  PAUSE", _
              "B                  AUTOPILOT", "HELP / H           THESE PAGES", "ESC                TITLE / QUIT", _
              "", "BRICKS 10, TOUGH 30, BONUS 50,", "+5 FOR EACH LAYER DEEPER.", _
              "CAPSULE 100. LEVEL CLEAR 250 x LEVEL.", "", "THE BALL SPEEDS UP AS YOU RALLY.")
    For i = 0 To 11
        helpText(1, i) = h(i)
        helpText(2, i) = h(12 + i)
    Next i
    partSeed = 1
End Sub

Public Function BrickPen(ByVal t As Long, ByVal hits As Long) As Long
    If t >= BK_RED And t <= BK_BLUE Then
        BrickPen = PEN_BRICK + 2 * (t - BK_RED)
    ElseIf t = BK_TOUGH Then
        If hits > 1 Then BrickPen = PEN_TOUGH Else BrickPen = PEN_TOUGH + 1
    ElseIf t = BK_STEEL Then
        BrickPen = PEN_STEEL
    Else
        BrickPen = PEN_CAP
    End If
End Function

Private Function BrickShade(ByVal t As Long, ByVal hits As Long) As Long
    If t = BK_TOUGH And hits <= 1 Then
        BrickShade = 3
    ElseIf t = BK_BONUS Then
        BrickShade = PEN_BRICK + 11
    Else
        BrickShade = BrickPen(t, hits) + 1
    End If
End Function

' ---------- effects ----------
Public Sub ClearParts()
    Dim k As Long
    For k = 0 To MAX_PARTS - 1
        partLife(k) = 0
    Next k
    duFlashTimer = 0
End Sub

' bits of a broken brick
Private Sub Burst(ByVal cell As Long, ByVal t As Long)
    Dim x0 As Long, y0 As Long, z0 As Long, k As Long, made As Long
    BbCellBox cell, x0, y0, z0
    k = 0
    Do While k < MAX_PARTS And made < 6
        If partLife(k) <= 0 Then
            partX(k) = (x0 + BB_CW \ 2) * 16
            partY(k) = (y0 + BB_CH \ 2) * 16
            partZ(k) = z0 * 16
            partVX(k) = A3Rand(partSeed) Mod 129 - 64
            partVY(k) = A3Rand(partSeed) Mod 129 - 40
            partVZ(k) = -(A3Rand(partSeed) Mod 64) - 24
            partLife(k) = 14 + made
            If made And 1 Then partCol(k) = BrickPen(t, 1) + 1 Else partCol(k) = BrickPen(t, 1)
            made = made + 1
        End If
        k = k + 1
    Loop
End Sub

Private Sub Flash(ByVal s As String)
    duFlash = s
    duFlashTimer = 30
End Sub

Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long
    For i = 0 To bbNEv - 1
        If bbEv(i).etype = BBE_BREAK Then Burst bbEv(i).a, bbEv(i).b
        If loud Then
            Select Case bbEv(i).etype
                Case BBE_WALL: Sfx SFX_WALL
                Case BBE_PADDLE: Sfx SFX_PADDLE
                Case BBE_BREAK: Sfx SFX_BREAK
                Case BBE_HIT: Sfx SFX_HIT
                Case BBE_STEEL: Sfx SFX_STEEL
                Case BBE_LOST
                    Sfx SFX_LOST
                    If bbLives > 0 Then Flash "BALL LOST"
                Case BBE_SERVE: Sfx SFX_SERVE
                Case BBE_CAPSULE
                    Sfx SFX_CAPSULE
                    Flash Choose(bbEv(i).a + 1, "WIDE PADDLE", "SLOW BALL", "EXTRA LIFE", "PLOUGH!")
                Case BBE_CLEAR: Sfx SFX_CLEAR
                Case BBE_OVER: Sfx SFX_OVER
                Case BBE_WIN: Sfx SFX_WIN
            End Select
        End If
    Next i
    bbNEv = 0
End Sub

Public Sub AgeEffects()
    Dim k As Long
    For k = 0 To MAX_PARTS - 1
        If partLife(k) > 0 Then
            partX(k) = partX(k) + partVX(k)
            partY(k) = partY(k) + partVY(k)
            partZ(k) = partZ(k) + partVZ(k)
            partVY(k) = partVY(k) - 8
            partLife(k) = partLife(k) - 1
        End If
    Next k
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
End Sub

' ---------- the scene ----------
Private Sub Quad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                 ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, _
                 ByVal depth As Long, ByVal col As Long)
    A3QuadW cam, depth - cam.z, col, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3
End Sub

' a flat rectangle facing the camera at depth z
Private Sub Card(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z As Long, ByVal depth As Long, ByVal col As Long)
    A3QuadW cam, depth - cam.z, col, x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z
End Sub

Private Sub Tunnel()
    Dim z As Long, z1 As Long, d As Long, s As Long, k As Long
    A3Begin 1400
    z = WALL_Z0
    Do While z < BB_D
        z1 = z + SEG
        If z1 > BB_D Then z1 = BB_D
        d = z + SEG \ 2
        s = k And 1
        Quad -BB_W, -BB_H, z, BB_W, -BB_H, z, BB_W, -BB_H, z1, -BB_W, -BB_H, z1, d, PEN_FLOOR + s
        Quad -BB_W, BB_H, z, BB_W, BB_H, z, BB_W, BB_H, z1, -BB_W, BB_H, z1, d, PEN_CEIL + s
        Quad -BB_W, -BB_H, z, -BB_W, BB_H, z, -BB_W, BB_H, z1, -BB_W, -BB_H, z1, d, PEN_SIDE + s
        Quad BB_W, -BB_H, z, BB_W, BB_H, z, BB_W, BB_H, z1, BB_W, -BB_H, z1, d, PEN_SIDE + s
        z = z + SEG
        k = k + 1
    Loop
    Card -BB_W, -BB_H, BB_W, BB_H, BB_D, BB_D + 50, PEN_BACK
    polyTotal = polyTotal + a3NPolys
    A3Flush
End Sub

Private Function EmptyAt(ByVal c As Long, ByVal r As Long, ByVal l As Long) As Boolean
    If c < 0 Or c >= BB_COLS Or r < 0 Or r >= BB_ROWS Or l < 0 Or l >= BB_LAYERS Then
        EmptyAt = True
    Else
        EmptyAt = (bbCell((l * BB_ROWS + r) * BB_COLS + c) = BK_EMPTY)
    End If
End Function

Private Sub Bricks()
    Dim i As Long, t As Long, c As Long, r As Long, l As Long, lit As Long, sh As Long
    Dim x0 As Long, y0 As Long, z0 As Long, x1 As Long, y1 As Long, z1 As Long, mz As Long
    For i = 0 To BB_CELLS - 1
        t = bbCell(i)
        If t <> BK_EMPTY Then
            c = i Mod 6
            r = (i \ 6) Mod 4
            l = BbCellBox(i, x0, y0, z0)
            x1 = x0 + BB_CW: y1 = y0 + BB_CH: z1 = z0 + BB_CD: mz = z0 + BB_CD \ 2
            lit = BrickPen(t, bbHits(i))
            sh = BrickShade(t, bbHits(i))
            If EmptyAt(c, r, l - 1) Then
                Card x0, y0, x1, y1, z0, z0, sh                        ' the front: a rim
                Card x0 + 5, y0 + 5, x1 - 5, y1 - 5, z0 - 1, z0 - 1, lit    ' and its face
            End If
            If x0 > cam.x Then
                If EmptyAt(c - 1, r, l) Then Quad x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1, mz, sh
            End If
            If x1 < cam.x Then
                If EmptyAt(c + 1, r, l) Then Quad x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1, mz, sh
            End If
            If y1 < cam.y Then
                If EmptyAt(c, r + 1, l) Then Quad x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1, mz, lit
            End If
            If y0 > cam.y Then
                If EmptyAt(c, r - 1, l) Then Quad x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1, mz, sh
            End If
        End If
    Next i
End Sub

Private Sub Ball()
    Dim x As Long, y As Long, z As Long, k As Long, p As Long
    x = bbBX \ BB_FX
    y = bbBY \ BB_FX
    z = bbBZ \ BB_FX
    ' where it is along the tunnel: a ring round the walls, and its shadow
    Quad -BB_W, -BB_H + 1, z - 3, BB_W, -BB_H + 1, z - 3, BB_W, -BB_H + 1, z + 3, -BB_W, -BB_H + 1, z + 3, z + 40, PEN_RING
    Quad -BB_W, BB_H - 1, z - 3, BB_W, BB_H - 1, z - 3, BB_W, BB_H - 1, z + 3, -BB_W, BB_H - 1, z + 3, z + 40, PEN_RING
    Quad -BB_W + 1, -BB_H, z - 3, -BB_W + 1, BB_H, z - 3, -BB_W + 1, BB_H, z + 3, -BB_W + 1, -BB_H, z + 3, z + 40, PEN_RING
    Quad BB_W - 1, -BB_H, z - 3, BB_W - 1, BB_H, z - 3, BB_W - 1, BB_H, z + 3, BB_W - 1, -BB_H, z + 3, z + 40, PEN_RING
    Quad x - 9, -BB_H + 2, z - 9, x + 9, -BB_H + 2, z - 9, x + 9, -BB_H + 2, z + 9, x - 9, -BB_H + 2, z + 9, z + 30, 2
    For k = 0 To 7
        CamXform cam, x + octX(k), y + octY(k), z
        pvx(k) = ox: pvy(k) = oy: pvz(k) = oz
    Next k
    If bbPloughT Then p = PEN_RED Else p = PEN_BALL
    A3Poly cam, z - cam.z - 2, p, 8
    For k = 0 To 7
        CamXform cam, x - 3 + octX(k) \ 3, y + 3 + octY(k) \ 3, z - 1
        pvx(k) = ox: pvy(k) = oy: pvz(k) = oz
    Next k
    A3Poly cam, z - cam.z - 3, 1, 8
End Sub

Private Sub Capsules()
    Dim k As Long, x As Long, y As Long, z As Long, p As Long
    For k = 0 To BB_MAX_CAPS - 1
        If bbCap(k).active Then
            x = bbCap(k).x \ BB_FX: y = bbCap(k).y \ BB_FX: z = bbCap(k).z \ BB_FX
            Card x - 16, y - 10, x + 16, y + 10, z, z, PEN_CAP
            Select Case bbCap(k).ctype
                Case CAP_LIFE: p = PEN_GREEN
                Case CAP_PLOUGH: p = PEN_RED
                Case CAP_SLOW: p = PEN_CYAN
                Case Else: p = PEN_YELLOW
            End Select
            Card x - 11, y - 5, x + 11, y + 5, z - 1, z - 1, p
        End If
    Next k
End Sub

Private Sub Parts()
    Dim k As Long, x As Long, y As Long, z As Long
    For k = 0 To MAX_PARTS - 1
        If partLife(k) > 0 Then
            x = ShrA(partX(k), 4): y = ShrA(partY(k), 4): z = ShrA(partZ(k), 4)
            Card x - 4, y - 4, x + 4, y + 4, z, z - 2, partCol(k)
        End If
    Next k
End Sub

Private Sub Paddle()
    Dim x As Long, y As Long, w As Long, h As Long, t As Long, col As Long
    x = bbPX \ BB_FX: y = bbPY \ BB_FX: w = BbPadW(): h = BbPadH(): t = 5
    If bbPloughT <> 0 And (bbTicks And 2) <> 0 Then col = PEN_RED Else col = PEN_PADDLE
    Card x - w, y + h - t, x + w, y + h, 0, -10, col
    Card x - w, y - h, x + w, y - h + t, 0, -10, col
    Card x - w, y - h, x - w + t, y + h, 0, -10, col
    Card x + w - t, y - h, x + w, y + h, 0, -10, col
    Card x - 6, y - 1, x + 6, y + 1, 0, -10, col
    Card x - 1, y - 6, x + 1, y + 6, 0, -10, col
End Sub

Private Sub CapsuleLetters()
    Dim k As Long, sx As Long, sy As Long
    For k = 0 To BB_MAX_CAPS - 1
        If bbCap(k).active Then
            CamXform cam, bbCap(k).x \ BB_FX, bbCap(k).y \ BB_FX, bbCap(k).z \ BB_FX
            If oz >= 60 Then
                CamProject cam, ox, oy, oz, sx, sy
                GText sx - 2, sy + 3, 0, Mid$("WSLP", bbCap(k).ctype + 1, 1)
            End If
        End If
    Next k
End Sub

Private Sub Scene()
    cam.x = bbPX \ BB_FX \ 5
    cam.y = bbPY \ BB_FX \ 5
    cam.z = -320
    cam.yaw = 0
    cam.pitch = 0
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, G_H \ 2, 270
    CamSetup cam
    gcv.Cls pen(0)
    Tunnel
    A3Begin 1400
    Bricks
    Capsules
    Parts
    If Not (bbBetween <> 0 And bbStuck <> 0) Then Ball
    Paddle
    polyTotal = polyTotal + a3NPolys
    A3Flush
    CapsuleLetters
End Sub

Private Sub Hud()
    Dim k As Long, x As Long
    GTextShadow 4, 10, 1, "SCORE " & bbScore
    GTextShadow 128, 10, PEN_YELLOW, "LEVEL " & bbLevel
    x = 210
    For k = 0 To bbLives - 1
        If k >= 8 Then Exit For
        gcv.Circle x + 4, 6, 4, pen(PEN_BALL), True
        x = x + 13
    Next k
    x = 4
    If bbWideT Then
        GTextShadow x, 250, PEN_YELLOW, "WIDE"
        x = x + 44
    End If
    If bbSlowT Then
        GTextShadow x, 250, PEN_CYAN, "SLOW"
        x = x + 44
    End If
    If bbPloughT Then GTextShadow x, 250, PEN_RED, "PLOUGH"
    If duAutoplay Then GTextShadow 250, 250, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim p As Long
    Scene
    Hud
    If bbStuck <> 0 And bbBetween = 0 And isPlay Then
        GTextCentre 92, PEN_YELLOW, "LEVEL " & bbLevel & ": " & BbLevelName(bbLevel)
        GTextCentre 172, 1, "SPACE TO SERVE"
    End If
    If bbBetween Then GTextBigCentre 100, PEN_GREEN, "CLEARED!", 3
    If isOver Then
        If bbWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 60, 90, 260, 170, 2, p
        If bbWon Then GTextBigCentre 98, p, "YOU WIN", 2 Else GTextBigCentre 98, p, "GAME OVER", 2
        GTextCentre 140, 1, "SCORE " & bbScore
        If duStateTimer = 0 Then GTextCentre 158, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 128, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 40, PEN_YELLOW, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                             ' the autopilot plays behind the title
    GTextBigCentre 28, 0, "BLOCK BREAKER", 3
    GTextBig (G_W - GTextBigWidth("BLOCK BREAKER", 3)) \ 2 - 2, 26, PEN_YELLOW, "BLOCK BREAKER", 3
    GTextBig 126, 66, 0, "3D", 6
    GTextBig 124, 64, PEN_CYAN, "3D", 6
    GTextCentre 186, PEN_GREEN, "START AT LEVEL " & startLevel & "  (UP/DOWN)"
    If (bbTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 204, p, "PRESS SPACE TO PLAY"
    GTextCentre 222, 3, "BEST " & hsScore(0) & "     HELP: HOW TO PLAY"
End Sub

Public Sub DrawHelp(ByVal page As Long)
    Dim k As Long
    gcv.Cls pen(0)
    If page = 1 Then GTextBigCentre 14, PEN_CYAN, "HOW TO PLAY", 2 Else GTextBigCentre 14, PEN_CYAN, "CONTROLS", 2
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
    GTextCentre 110, 1, "PLACE " & (HsRank(bbScore) + 1) & "   " & Format$(bbScore, "0000000")
    If (bbTicks And 8) = 0 Then cur = "_" Else cur = " "
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
