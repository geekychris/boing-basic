' Block Breaker 3D - the rules (a port of bb_core.c from amiga_mcp's
' examples/block_breaker_3d). Breakout down a tunnel: the paddle is a frame on the
' near opening (z = 0) moving up, down, left and right; the ball flies to a block of
' bricks at the far end (6 across, 4 high, 3 deep) and back. Integer only, 1/256
' units, exactly as the C: a seed plays the same game and gives the C's hash.
Option Explicit

Public Const BB_COLS As Long = 6
Public Const BB_ROWS As Long = 4
Public Const BB_LAYERS As Long = 3
Public Const BB_CELLS As Long = 72
Public Const BB_W As Long = 168
Public Const BB_H As Long = 120
Public Const BB_D As Long = 800
Public Const BB_CW As Long = 56
Public Const BB_CH As Long = 60
Public Const BB_CD As Long = 60
Public Const BB_Z0 As Long = 620
Public Const BB_R As Long = 10
Public Const BB_PAD_W As Long = 40
Public Const BB_PAD_H As Long = 28
Public Const BB_WIDE_W As Long = 62
Public Const BB_WIDE_H As Long = 42
Public Const BB_PAD_SPEED As Long = 13
Public Const BB_LOST_Z As Long = -60
Public Const BB_LIVES As Long = 3
Public Const BB_LEVELS As Long = 8
Public Const BB_MAX_CAPS As Long = 4
Public Const BB_POWER_TICKS As Long = 375
Public Const BB_BETWEEN As Long = 50
Public Const BB_FX As Long = 256

Public Const BK_EMPTY As Long = 0
Public Const BK_RED As Long = 1
Public Const BK_ORANGE As Long = 2
Public Const BK_YELLOW As Long = 3
Public Const BK_GREEN As Long = 4
Public Const BK_CYAN As Long = 5
Public Const BK_BLUE As Long = 6
Public Const BK_TOUGH As Long = 7
Public Const BK_STEEL As Long = 8
Public Const BK_BONUS As Long = 9

Public Const CAP_WIDE As Long = 0
Public Const CAP_SLOW As Long = 1
Public Const CAP_LIFE As Long = 2
Public Const CAP_PLOUGH As Long = 3

Public Const BB_IN_LEFT As Long = 1
Public Const BB_IN_RIGHT As Long = 2
Public Const BB_IN_UP As Long = 4
Public Const BB_IN_DOWN As Long = 8
Public Const BB_IN_FIRE As Long = 16

Public Const BBE_NONE As Long = 0
Public Const BBE_WALL As Long = 1
Public Const BBE_PADDLE As Long = 2
Public Const BBE_HIT As Long = 3
Public Const BBE_BREAK As Long = 4
Public Const BBE_STEEL As Long = 5
Public Const BBE_LOST As Long = 6
Public Const BBE_SERVE As Long = 7
Public Const BBE_CAPSULE As Long = 8
Public Const BBE_CAP_MISS As Long = 9
Public Const BBE_CLEAR As Long = 10
Public Const BBE_LEVEL As Long = 11
Public Const BBE_OVER As Long = 12
Public Const BBE_WIN As Long = 13
Public Const BB_MAX_EVENTS As Long = 24

Public Type BbCapsule
    x As Long
    y As Long
    z As Long
    ctype As Long
    active As Long
End Type

Public Type BbEvent
    etype As Long
    a As Long
    b As Long
End Type

Public bbSeed As Long, bbRng As Long
Public bbCell(0 To 71) As Long              ' BK_*: (layer * 4 + row) * 6 + col, layer 0 nearest, row 0 lowest
Public bbHits(0 To 71) As Long
Public bbLevel As Long, bbLives As Long, bbOver As Long, bbWon As Long, bbLeft As Long
Public bbScore As Long
Public bbPX As Long, bbPY As Long
Public bbBX As Long, bbBY As Long, bbBZ As Long, bbVX As Long, bbVY As Long, bbVZ As Long
Public bbSpeed As Long
Public bbStuck As Long, bbBetween As Long
Public bbWideT As Long, bbSlowT As Long, bbPloughT As Long
Public bbPaddleHits As Long, bbBroken As Long, bbTicks As Long, bbCapsDropped As Long
Public bbCap(0 To 3) As BbCapsule
Public bbEv(0 To 23) As BbEvent
Public bbNEv As Long

Private levelCell(1 To 8, 0 To 71) As Long
Private levelName(1 To 8) As String
Private ovCells(0 To 7) As Long

Private Sub StoreLevel(ByVal n As Long, lv As Variant)
    Dim l As Long, r As Long, c As Long, t As Long, s As String
    For l = 0 To 2
        For r = 0 To 3
            s = lv(l * 4 + r)
            For c = 0 To 5
                Select Case Mid$(s, c + 1, 1)
                    Case "r": t = BK_RED
                    Case "o": t = BK_ORANGE
                    Case "y": t = BK_YELLOW
                    Case "g": t = BK_GREEN
                    Case "c": t = BK_CYAN
                    Case "b": t = BK_BLUE
                    Case "T": t = BK_TOUGH
                    Case "S": t = BK_STEEL
                    Case "*": t = BK_BONUS
                    Case Else: t = BK_EMPTY
                End Select
                levelCell(n, (l * 4 + (3 - r)) * 6 + c) = t
            Next c
        Next r
    Next l
End Sub

Public Sub BbInit()
    Dim lv As Variant, nm As Variant, i As Long
    A3FixInit
    lv = Array("......", "......", "......", "......", ".o..o.", "..**..", _
               "..yy..", ".g..g.", "rrrrrr", "oooooo", "yyyyyy", "gggggg")
    StoreLevel 1, lv
    lv = Array("r.r.r.", ".o.o.o", "y.y.y.", ".g.g.g", ".c.c.c", "b.b.b.", _
               ".c*c.c", "b.b.b.", "TTTTTT", "cccccc", "bbbbbb", "TTTTTT")
    StoreLevel 2, lv
    lv = Array("SS..SS", "S....S", "S....S", "SS..SS", "......", ".*yy*.", _
               ".yyyy.", "......", "rrrrrr", "rTTTTr", "rTTTTr", "rrrrrr")
    StoreLevel 3, lv
    lv = Array("g....g", "g....g", "g....g", "g....g", "..TT..", "..TT..", _
               "..**..", "..TT..", "cbcbcb", "bcbcbc", "cbcbcb", "bcbcbc")
    StoreLevel 4, lv
    lv = Array("......", "......", "......", "oooooo", "......", "......", _
               "yyyyyy", "TT**TT", "......", "gggggg", "cccccc", "bbbbbb")
    StoreLevel 5, lv
    lv = Array("S.SS.S", "......", "......", "S.SS.S", "TTTTTT", "T*..*T", _
               "T....T", "TTTTTT", "yyyyyy", "yrrrry", "yrrrry", "yyyyyy")
    StoreLevel 6, lv
    lv = Array("..rr..", "......", "......", "..rr..", "o....o", ".T**T.", _
               ".T..T.", "o....o", "SbbbbS", "bcTTcb", "bcTTcb", "SbbbbS")
    StoreLevel 7, lv
    lv = Array("TTTTTT", "T....T", "T....T", "TTTTTT", "S.SS.S", ".*..*.", _
               ".*..*.", "S.SS.S", "rrrrrr", "ooTToo", "yyTTyy", "gggggg")
    StoreLevel 8, lv
    nm = Array("FIRST LIGHT", "CHEQUERS", "THE WINDOW", "PILLARS", "STAIRWAY", "THE VAULT", "CROSSFIRE", "THE CORE")
    For i = 1 To 8
        levelName(i) = nm(i - 1)
    Next i
End Sub

Public Function BbLevelName(ByVal n As Long) As String
    BbLevelName = levelName(n)
End Function

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If bbNEv < BB_MAX_EVENTS Then
        bbEv(bbNEv).etype = etype
        bbEv(bbNEv).a = a
        bbEv(bbNEv).b = b
        bbNEv = bbNEv + 1
    End If
End Sub

' mulberry32
Public Function BbRand() As Long
    Dim t As Long
    bbRng = AddW(bbRng, &H6D2B79F5)
    t = bbRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    BbRand = t Xor ShrU(t, 14)
End Function

Public Function BbBreakable(ByVal t As Long) As Boolean
    BbBreakable = (t <> BK_EMPTY And t <> BK_STEEL)
End Function

Public Function BbIndex(ByVal c As Long, ByVal r As Long, ByVal l As Long) As Long
    BbIndex = (l * BB_ROWS + r) * BB_COLS + c
End Function

' a cell's low corner (world units); returns its layer
Public Function BbCellBox(ByVal i As Long, x0 As Long, y0 As Long, z0 As Long) As Long
    Dim l As Long
    l = i \ 24
    x0 = -BB_W + (i Mod 6) * BB_CW
    y0 = -BB_H + ((i \ 6) Mod 4) * BB_CH
    z0 = BB_Z0 + l * BB_CD
    BbCellBox = l
End Function

Public Function BbPadW() As Long
    If bbWideT Then BbPadW = BB_WIDE_W Else BbPadW = BB_PAD_W
End Function

Public Function BbPadH() As Long
    If bbWideT Then BbPadH = BB_WIDE_H Else BbPadH = BB_PAD_H
End Function

Private Function CurSpeed() As Long
    If bbSlowT Then CurSpeed = (bbSpeed * 3) \ 4 Else CurSpeed = bbSpeed
End Function

Private Sub SetSpeed()
    Dim s As Long
    s = (12 + bbLevel) * BB_FX + (bbPaddleHits \ 10) * (BB_FX \ 2)
    If s > 24 * BB_FX Then s = 24 * BB_FX
    bbSpeed = s
End Sub

' the ball's speed back to CurSpeed, keeping its direction across the tunnel
' within limits so it always makes progress along it
Private Sub Renorm()
    Dim s As Long, lim As Long, rest As Long, sgn As Long
    s = CurSpeed()
    lim = (s * 3) \ 5
    If bbVZ < 0 Then sgn = -1 Else sgn = 1
    If bbVX > lim Then bbVX = lim
    If bbVX < -lim Then bbVX = -lim
    If bbVY > lim Then bbVY = lim
    If bbVY < -lim Then bbVY = -lim
    rest = s * s - bbVX * bbVX - bbVY * bbVY
    If rest < 1 Then rest = 1
    bbVZ = sgn * ISqrtD(rest)
End Sub

Public Sub BbLoadLevel(ByVal lvl As Long)
    Dim i As Long, t As Long
    bbLevel = lvl
    bbLeft = 0
    For i = 0 To 71
        t = levelCell(lvl, i)
        bbCell(i) = t
        If t = BK_TOUGH Then
            If lvl >= 5 Then bbHits(i) = 3 Else bbHits(i) = 2
        ElseIf t = BK_EMPTY Then
            bbHits(i) = 0
        Else
            bbHits(i) = 1
        End If
        If BbBreakable(t) Then bbLeft = bbLeft + 1
    Next i
    ClearCaps
    bbWideT = 0: bbSlowT = 0: bbPloughT = 0
    bbPaddleHits = 0
    bbStuck = 1
    bbPX = 0: bbPY = 0
    SetSpeed
End Sub

Private Sub ClearCaps()
    Dim k As Long
    For k = 0 To BB_MAX_CAPS - 1
        bbCap(k).x = 0: bbCap(k).y = 0: bbCap(k).z = 0: bbCap(k).ctype = 0: bbCap(k).active = 0
    Next k
End Sub

Public Sub BbNewGame(ByVal seed As Long, ByVal lvl As Long)
    bbSeed = seed
    bbRng = seed
    bbLives = BB_LIVES
    bbOver = 0: bbWon = 0: bbScore = 0
    bbBX = 0: bbBY = 0: bbBZ = 0: bbVX = 0: bbVY = 0: bbVZ = 0
    bbBetween = 0: bbBroken = 0: bbTicks = 0: bbCapsDropped = 0
    bbNEv = 0
    If lvl < 1 Then lvl = 1
    If lvl > BB_LEVELS Then lvl = BB_LEVELS
    BbLoadLevel lvl
    bbBX = bbPX
    bbBY = bbPY
    bbBZ = (BB_R + 1) * BB_FX
End Sub

Private Sub DropCapsule(ByVal i As Long)
    Dim k As Long, x0 As Long, y0 As Long, z0 As Long, r As Long
    r = UModL(BbRand(), 8)
    For k = 0 To BB_MAX_CAPS - 1
        If bbCap(k).active = 0 Then Exit For
    Next k
    If k = BB_MAX_CAPS Then Exit Sub
    BbCellBox i, x0, y0, z0
    bbCap(k).active = 1
    If r < 3 Then
        bbCap(k).ctype = CAP_WIDE
    ElseIf r < 5 Then
        bbCap(k).ctype = CAP_SLOW
    ElseIf r < 6 Then
        bbCap(k).ctype = CAP_LIFE
    Else
        bbCap(k).ctype = CAP_PLOUGH
    End If
    bbCap(k).x = (x0 + BB_CW \ 2) * BB_FX
    bbCap(k).y = (y0 + BB_CH \ 2) * BB_FX
    bbCap(k).z = z0 * BB_FX
    bbCapsDropped = bbCapsDropped + 1
End Sub

Private Sub BreakBrick(ByVal i As Long)
    Dim t As Long, l As Long
    t = bbCell(i)
    l = i \ 24
    bbCell(i) = BK_EMPTY
    bbHits(i) = 0
    bbLeft = bbLeft - 1
    bbBroken = bbBroken + 1
    If t = BK_TOUGH Then
        bbScore = bbScore + 30 + l * 5
    ElseIf t = BK_BONUS Then
        bbScore = bbScore + 50 + l * 5
    Else
        bbScore = bbScore + 10 + l * 5
    End If
    Ev BBE_BREAK, i, t
    If t = BK_BONUS Then DropCapsule i
End Sub

' a hit on brick i; True if the ball bounces off it
Private Function HitBrick(ByVal i As Long) As Boolean
    Dim t As Long
    t = bbCell(i)
    HitBrick = True
    If t = BK_STEEL Then
        Ev BBE_STEEL, i, t
        Exit Function
    End If
    If bbPloughT Then
        BreakBrick i
        HitBrick = False
        Exit Function
    End If
    bbHits(i) = bbHits(i) - 1
    If bbHits(i) = 0 Then
        BreakBrick i
    Else
        bbScore = bbScore + 5
        Ev BBE_HIT, i, bbHits(i)
    End If
End Function

' the occupied cells the ball's box at (x, y, z) overlaps (into ovCells); how many
Private Function Overlap(ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    Dim r As Long, zl As Long, c0 As Long, c1 As Long, r0 As Long, r1 As Long, l0 As Long, l1 As Long
    Dim c As Long, rr As Long, l As Long, n As Long, i As Long
    r = BB_R * BB_FX
    zl = z - r - BB_Z0 * BB_FX
    If z + r <= BB_Z0 * BB_FX Then Exit Function
    c0 = (x - r + BB_W * BB_FX) \ (BB_CW * BB_FX)
    c1 = (x + r - 1 + BB_W * BB_FX) \ (BB_CW * BB_FX)
    r0 = (y - r + BB_H * BB_FX) \ (BB_CH * BB_FX)
    r1 = (y + r - 1 + BB_H * BB_FX) \ (BB_CH * BB_FX)
    If zl < 0 Then l0 = 0 Else l0 = zl \ (BB_CD * BB_FX)
    l1 = (z + r - 1 - BB_Z0 * BB_FX) \ (BB_CD * BB_FX)
    If c0 < 0 Then c0 = 0
    If r0 < 0 Then r0 = 0
    If c1 >= BB_COLS Then c1 = BB_COLS - 1
    If r1 >= BB_ROWS Then r1 = BB_ROWS - 1
    If l1 >= BB_LAYERS Then l1 = BB_LAYERS - 1
    For l = l0 To l1
        For rr = r0 To r1
            For c = c0 To c1
                i = (l * BB_ROWS + rr) * BB_COLS + c
                If bbCell(i) <> BK_EMPTY Then
                    ovCells(n) = i
                    n = n + 1
                End If
            Next c
        Next rr
    Next l
    Overlap = n
End Function

Private Sub PaddleBounce()
    Dim s As Long, pw As Long, ph As Long
    s = CurSpeed()
    pw = BbPadW() * BB_FX
    ph = BbPadH() * BB_FX
    bbBZ = 2 * BB_R * BB_FX - bbBZ
    bbVZ = -bbVZ
    bbVX = bbVX + ((bbBX - bbPX) * (s \ 2)) \ pw
    bbVY = bbVY + ((bbBY - bbPY) * (s \ 2)) \ ph
    bbPaddleHits = bbPaddleHits + 1
    SetSpeed
    Renorm
    Ev BBE_PADDLE, (bbBX - bbPX) \ BB_FX, (bbBY - bbPY) \ BB_FX
End Sub

Private Sub MoveAxis(ByVal axis As Long, ByVal d As Long)
    Dim p As Long, v As Long, before As Long, lim As Long, n As Long, k As Long, solid As Boolean
    Dim dx As Long, dy As Long
    Select Case axis
        Case 0: p = bbBX: v = bbVX: lim = (BB_W - BB_R) * BB_FX
        Case 1: p = bbBY: v = bbVY: lim = (BB_H - BB_R) * BB_FX
        Case Else: p = bbBZ: v = bbVZ: lim = (BB_D - BB_R) * BB_FX
    End Select
    before = p
    p = p + d
    If p > lim Then
        p = 2 * lim - p
        v = -v
        Ev BBE_WALL, axis, 1
    ElseIf axis < 2 And p < -lim Then
        p = -2 * lim - p
        v = -v
        Ev BBE_WALL, axis, -1
    End If
    Select Case axis
        Case 0: bbBX = p
        Case 1: bbBY = p
        Case Else: bbBZ = p
    End Select
    n = Overlap(bbBX, bbBY, bbBZ)
    For k = 0 To n - 1
        If HitBrick(ovCells(k)) Then solid = True
    Next k
    If solid Then
        p = before
        v = -v
    End If
    Select Case axis
        Case 0: bbBX = p: bbVX = v
        Case 1: bbBY = p: bbVY = v
        Case Else: bbBZ = p: bbVZ = v
    End Select
    ' the paddle, crossing its plane on the way back
    If axis = 2 And bbVZ < 0 And before > BB_R * BB_FX And bbBZ <= BB_R * BB_FX Then
        dx = Abs(bbBX - bbPX)
        dy = Abs(bbBY - bbPY)
        If dx <= (BbPadW() + BB_R) * BB_FX And dy <= (BbPadH() + BB_R) * BB_FX Then PaddleBounce
    End If
End Sub

Private Sub Serve(ByVal dx As Long, ByVal dy As Long)
    Dim s As Long
    bbStuck = 0
    s = CurSpeed()
    bbVX = (dx * s) \ 4 + (UModL(BbRand(), 61) * s) \ 300 - s \ 10
    bbVY = (dy * s) \ 4 + (UModL(BbRand(), 61) * s) \ 300 - s \ 10
    bbVZ = 1
    Renorm
    Ev BBE_SERVE, 0, 0
End Sub

Private Sub LoseBall()
    bbLives = bbLives - 1
    Ev BBE_LOST, bbLives, 0
    bbWideT = 0: bbSlowT = 0: bbPloughT = 0
    If bbLives <= 0 Then
        bbOver = 1
        Ev BBE_OVER, bbScore, 0
        Exit Sub
    End If
    bbStuck = 1
    SetSpeed
End Sub

Private Sub Capsules()
    Dim k As Long, before As Long, dx As Long, dy As Long, caught As Boolean
    For k = 0 To BB_MAX_CAPS - 1
        If bbCap(k).active Then
            caught = False
            before = bbCap(k).z
            bbCap(k).z = bbCap(k).z - 7 * BB_FX
            If before > 0 And bbCap(k).z <= 0 Then
                dx = Abs(bbCap(k).x - bbPX)
                dy = Abs(bbCap(k).y - bbPY)
                If dx <= (BbPadW() + 14) * BB_FX And dy <= (BbPadH() + 10) * BB_FX Then
                    bbCap(k).active = 0
                    bbScore = bbScore + 100
                    Select Case bbCap(k).ctype
                        Case CAP_WIDE: bbWideT = BB_POWER_TICKS
                        Case CAP_SLOW
                            bbSlowT = BB_POWER_TICKS
                            If bbStuck = 0 Then Renorm
                        Case CAP_LIFE
                            If bbLives < 9 Then bbLives = bbLives + 1
                        Case CAP_PLOUGH: bbPloughT = BB_POWER_TICKS \ 2
                    End Select
                    Ev BBE_CAPSULE, bbCap(k).ctype, 0
                    caught = True
                End If
            End If
            If Not caught Then
                If bbCap(k).z < BB_LOST_Z * BB_FX Then
                    bbCap(k).active = 0
                    Ev BBE_CAP_MISS, bbCap(k).ctype, 0
                End If
            End If
        End If
    Next k
End Sub

Public Sub BbTick(ByVal inp As Long)
    Dim dx As Long, dy As Long, lim As Long, k As Long
    If inp And BB_IN_RIGHT Then dx = dx + 1
    If inp And BB_IN_LEFT Then dx = dx - 1
    If inp And BB_IN_UP Then dy = dy + 1
    If inp And BB_IN_DOWN Then dy = dy - 1
    If bbOver <> 0 Or bbWon <> 0 Then Exit Sub
    bbTicks = bbTicks + 1
    If bbBetween > 0 Then
        bbBetween = bbBetween - 1
        If bbBetween = 0 Then
            If bbLevel >= BB_LEVELS Then
                bbWon = 1
                Ev BBE_WIN, bbScore, 0
                Exit Sub
            End If
            BbLoadLevel bbLevel + 1
            Ev BBE_LEVEL, bbLevel, 0
        End If
        Exit Sub
    End If
    ' the paddle
    bbPX = bbPX + dx * BB_PAD_SPEED * BB_FX
    bbPY = bbPY + dy * BB_PAD_SPEED * BB_FX
    lim = (BB_W - BbPadW()) * BB_FX
    If bbPX > lim Then bbPX = lim
    If bbPX < -lim Then bbPX = -lim
    lim = (BB_H - BbPadH()) * BB_FX
    If bbPY > lim Then bbPY = lim
    If bbPY < -lim Then bbPY = -lim
    If bbWideT Then bbWideT = bbWideT - 1
    If bbPloughT Then bbPloughT = bbPloughT - 1
    If bbSlowT Then
        bbSlowT = bbSlowT - 1
        If bbSlowT = 0 And bbStuck = 0 Then Renorm
    End If

    If bbStuck Then
        bbBX = bbPX
        bbBY = bbPY
        bbBZ = (BB_R + 1) * BB_FX
        If inp And BB_IN_FIRE Then Serve dx, dy
    Else
        For k = 0 To 3
            MoveAxis 0, bbVX \ 4
            MoveAxis 1, bbVY \ 4
            MoveAxis 2, bbVZ \ 4
        Next k
        If bbBZ < BB_LOST_Z * BB_FX Then LoseBall
    End If
    Capsules
    If bbLeft = 0 And bbOver = 0 Then
        bbScore = bbScore + 250 * bbLevel
        bbBetween = BB_BETWEEN
        bbStuck = 1
        ClearCaps
        Ev BBE_CLEAR, bbLevel, 0
    End If
End Sub

Public Sub BbClearAll()
    Dim i As Long
    For i = 0 To BB_CELLS - 1
        If BbBreakable(bbCell(i)) Then BreakBrick i
    Next i
End Sub

' ---------- the autopilot ----------

' p reflected back and forth within -lim..lim
Private Function Fold(ByVal p As Long, ByVal lim As Long) As Long
    Dim period As Long, q As Long
    period = 4 * lim
    q = AddW(p, lim) Mod period
    If q < 0 Then q = q + period
    If q > 2 * lim Then q = period - q
    Fold = q - lim
End Function

Public Function BbBot() As Long
    Dim tx As Long, ty As Long, pw As Long, ph As Long, dead As Long, limx As Long, limy As Long
    Dim inp As Long, k As Long, h As Long, t As Long, offX As Long, offY As Long
    pw = BbPadW() * BB_FX
    ph = BbPadH() * BB_FX
    dead = (BB_PAD_SPEED * BB_FX) \ 2
    limx = (BB_W - BB_R) * BB_FX
    limy = (BB_H - BB_R) * BB_FX
    If bbOver <> 0 Or bbWon <> 0 Or bbBetween <> 0 Then Exit Function
    If bbStuck Then
        h = A3Hash(AddW(AddW(AddW(MulW(bbSeed, 31), bbLives * 7), bbLevel * 131), bbBroken))
        tx = ((UModL(h, 201) - 100) * (BB_W - BB_PAD_W) * BB_FX) \ 100
        ty = (((ShrU(h, 8) Mod 201) - 100) * (BB_H - BB_PAD_H) * BB_FX) \ 100
        If bbPX - tx < dead And tx - bbPX < dead And bbPY - ty < dead And ty - bbPY < dead Then
            BbBot = BB_IN_FIRE
            Exit Function
        End If
    Else
        h = A3Hash(AddW(bbSeed, MulW(bbPaddleHits, &H9E3779B1)))
        If bbVZ < 0 Then
            t = (bbBZ - BB_R * BB_FX) \ (-bbVZ)
        Else
            t = ((BB_D - BB_R) * BB_FX - bbBZ + (BB_D - 2 * BB_R) * BB_FX) \ bbVZ
        End If
        tx = Fold(WrapD(CDbl(bbBX) + CDbl(bbVX) * t), limx)
        ty = Fold(WrapD(CDbl(bbBY) + CDbl(bbVY) * t), limy)
        ' where on the paddle to take it: varied, so the ball goes everywhere
        offX = ((UModL(h, 121) - 60) * pw) \ 100
        offY = (((ShrU(h, 10) Mod 121) - 60) * ph) \ 100
        tx = tx - offX
        ty = ty - offY
        ' a capsule about to arrive, while the ball is far: fetch it
        If bbBZ > 350 * BB_FX And bbVZ > 0 Then
            For k = 0 To BB_MAX_CAPS - 1
                If bbCap(k).active <> 0 And bbCap(k).z < 150 * BB_FX Then
                    tx = bbCap(k).x
                    ty = bbCap(k).y
                    Exit For
                End If
            Next k
        End If
    End If
    If tx > bbPX + dead Then inp = inp Or BB_IN_RIGHT
    If tx < bbPX - dead Then inp = inp Or BB_IN_LEFT
    If ty > bbPY + dead Then inp = inp Or BB_IN_UP
    If ty < bbPY - dead Then inp = inp Or BB_IN_DOWN
    BbBot = inp
End Function

Public Function BbStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To BB_CELLS - 1
        h = Fnv(h, bbCell(i) * 16 + bbHits(i))
    Next i
    h = Fnv(h, bbScore): h = Fnv(h, bbLevel): h = Fnv(h, bbLives): h = Fnv(h, bbLeft)
    h = Fnv(h, bbPX): h = Fnv(h, bbPY): h = Fnv(h, bbBX): h = Fnv(h, bbBY): h = Fnv(h, bbBZ)
    h = Fnv(h, bbVX): h = Fnv(h, bbVY): h = Fnv(h, bbVZ): h = Fnv(h, bbPaddleHits)
    h = Fnv(h, bbBroken): h = Fnv(h, bbTicks): h = Fnv(h, bbOver): h = Fnv(h, bbWon)
    BbStateHash = h
End Function

' the autopilot plays from a level: ticks played
Public Function BbAutoGame(ByVal seed As Long, ByVal lvl As Long, ByVal maxTicks As Long) As Long
    Dim t As Long
    BbNewGame seed, lvl
    Do While t < maxTicks And bbOver = 0 And bbWon = 0
        BbTick BbBot()
        bbNEv = 0
        t = t + 1
    Loop
    BbAutoGame = t
End Function
