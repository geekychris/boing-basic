' Boing Rally - the game: the road (generated row by row from a seed), the ball's physics,
' gems, blocks, boosts, ramps, lives and the autopilot. Everything advances one fixed step per
' frame (25 a second), so a seed and the keys pressed decide the game exactly: --bench and the
' tests replay it frame for frame.
Option Explicit

' the road: rows of 5 lanes, each row ROWLEN units long, going away along -z
Public Const LANES As Long = 5
Public Const ROWLEN As Double = 4
Public Const LANEW As Double = 2
Public Const RING As Long = 64             ' rows kept (a ring: row r is slot r And 63)
Public Const BALLR As Double = 0.6

' tiles
Public Const T_GAP As Long = 0
Public Const T_ROAD As Long = 1
Public Const T_BOOST As Long = 2
Public Const T_RAMP As Long = 3
' things on tiles
Public Const O_NONE As Long = 0
Public Const O_BLOCK As Long = 1
Public Const O_GEM As Long = 2

' input bits
Public Const IN_LEFT As Long = 1
Public Const IN_RIGHT As Long = 2
Public Const IN_JUMP As Long = 4

Public Const GRAVITY As Double = 0.025
Public Const JUMPV As Double = 0.32
Public Const RAMPV As Double = 0.42

Public tile(0 To RING * LANES - 1) As Long
Public thing(0 To RING * LANES - 1) As Long
Public genRow As Long                      ' the next row to generate

' the ball
Public bx As Double, by As Double, bz As Double     ' bz <= 0: distance travelled is -bz
Public bvx As Double, bvy As Double
Public speed As Double, boost As Double
Public spin As Double                      ' the roll angle (degrees)
Public onGround As Boolean, falling As Boolean
Public crashT As Long                      ' > 0: crashed, frames until the respawn
Public ghostT As Long                      ' > 0: just respawned, blocks pass through
Public lives As Long, score As Long, gems As Long
Public gameOver As Boolean
Public frameNo As Long
Public crashKind As String                 ' "crash" or "fall": what the last life was lost to
Public lastEvent As String                 ' "jump", "gem", "crash", "fall", "boost", "ramp", "life" (sound, labels)
Public eventX As Double, eventY As Double, eventZ As Double

' floating labels (+100 at a gem)
Public Const NLABELS As Long = 8
Public labX(0 To NLABELS - 1) As Double, labY(0 To NLABELS - 1) As Double, labZ(0 To NLABELS - 1) As Double
Public labT(0 To NLABELS - 1) As Long, labText(0 To NLABELS - 1) As String

' the generator
Private rngS As Double
Private segType As Long, prevType As Long, segLeft As Long, narrowLo As Long, narrowHi As Long
Private lastFull As Long                   ' rows since the last full-width gap
Private nextLife As Long

' ---- random numbers: Park-Miller in Doubles (exact, the same on every platform) ----
Private Sub RngSeed(ByVal s As Long)
    rngS = (Abs(s) Mod 2147483646) + 1
End Sub

Public Function RndI(ByVal n As Long) As Long
    rngS = rngS * 16807#
    rngS = rngS - Int(rngS / 2147483647#) * 2147483647#
    RndI = Int(rngS / 2147483647# * n)
End Function

' ---- the road ----
Public Function TileAt(ByVal r As Long, ByVal lane As Long) As Long
    If r < 0 Then TileAt = T_ROAD: Exit Function
    If lane < 0 Or lane >= LANES Then TileAt = T_GAP: Exit Function
    TileAt = tile((r And (RING - 1)) * LANES + lane)
End Function

Public Function ThingAt(ByVal r As Long, ByVal lane As Long) As Long
    If r < 0 Or lane < 0 Or lane >= LANES Then ThingAt = O_NONE: Exit Function
    ThingAt = thing((r And (RING - 1)) * LANES + lane)
End Function

Public Sub SetThing(ByVal r As Long, ByVal lane As Long, ByVal v As Long)
    thing((r And (RING - 1)) * LANES + lane) = v
End Sub

Public Function LaneX(ByVal lane As Long) As Double
    LaneX = (lane - 2) * LANEW
End Function

' 0..1: how hard the road is at row r
Public Function Difficulty(ByVal r As Long) As Double
    Difficulty = r / 450
    If Difficulty > 1 Then Difficulty = 1
End Function

Private Sub GenRowNow()
    Dim r As Long, base As Long, l As Long, d As Double, nb As Long, k As Long
    r = genRow
    base = (r And (RING - 1)) * LANES
    d = Difficulty(r)
    For l = 0 To LANES - 1
        tile(base + l) = T_ROAD
        thing(base + l) = O_NONE
    Next l
    genRow = genRow + 1
    lastFull = lastFull + 1
    If r < 8 Then Exit Sub                       ' a calm start
    If segLeft <= 0 Then
        prevType = segType
        ' a new segment: 0 open road, 1 a gap to jump, 2 a narrow path, 3 slalom blocks,
        ' 4 a ramp and a long gap, 5 boost pads
        k = RndI(100)
        If lastFull < 3 Then
            segType = 0                          ' room to land after a gap
        ElseIf k < 30 - d * 10 Then
            segType = 0
        ElseIf k < 48 Then
            segType = 1
        ElseIf k < 66 Then
            segType = 2
        ElseIf k < 80 Then
            segType = 3
        ElseIf k < 90 And d > 0.15 Then
            segType = 4
        Else
            segType = 5
        End If
        Select Case segType
            Case 0: segLeft = 3 + RndI(4)
            Case 1: segLeft = 1 + IIf(d > 0.5 And RndI(2) = 1, 1, 0)
            Case 2
                segLeft = 4 + RndI(5)
                ' after another narrow path it goes on from where that one is (a new random
                ' place could leave no way across)
                If prevType <> 2 Then narrowLo = RndI(LANES - 1)
                narrowHi = narrowLo + IIf(d > 0.6, 0, 1)
                If narrowHi >= LANES Then narrowHi = LANES - 1
            Case 3: segLeft = 4 + RndI(3)
            Case 4: segLeft = 1 + 2 + IIf(d > 0.6, 1, 0)   ' the ramp row, then the gap
            Case 5: segLeft = 2
        End Select
        segLeft = segLeft + 0
        If segType = 4 Then
            ' the ramp row: ramps in every lane
            For l = 0 To LANES - 1: tile(base + l) = T_RAMP: Next l
            segLeft = segLeft - 1
            Exit Sub
        End If
    End If
    segLeft = segLeft - 1
    Select Case segType
        Case 0                                   ' open road: a few gems and blocks
            nb = RndI(2 + Int(d * 2))
            If lastFull <= 2 Then nb = 0             ' nothing where the ball lands after a gap
            For k = 1 To nb
                thing(base + RndI(LANES)) = O_BLOCK
            Next k
            If RndI(3) = 0 Then thing(base + RndI(LANES)) = O_GEM
            ' never all five blocked
            nb = 0
            For l = 0 To LANES - 1: If thing(base + l) = O_BLOCK Then nb = nb + 1
            Next l
            If nb >= LANES - 1 Then thing(base + RndI(LANES)) = O_GEM
        Case 1, 4                                ' a full-width gap
            For l = 0 To LANES - 1: tile(base + l) = T_GAP: Next l
            lastFull = 0
        Case 2                                   ' a narrow path that wanders a lane at a time
            For l = 0 To LANES - 1
                If l < narrowLo Or l > narrowHi Then tile(base + l) = T_GAP
            Next l
            If RndI(2) = 0 Then thing(base + narrowLo + RndI(narrowHi - narrowLo + 1)) = O_GEM
            k = RndI(3) - 1
            If narrowLo + k >= 0 And narrowHi + k < LANES Then
                narrowLo = narrowLo + k
                narrowHi = narrowHi + k
            End If
        Case 3                                   ' slalom: a wall with one door, every other row
            If (segLeft And 1) = 0 Then
                k = RndI(LANES)
                For l = 0 To LANES - 1
                    If l <> k And l <> k + 1 Then thing(base + l) = O_BLOCK
                Next l
                thing(base + k) = O_GEM
            End If
        Case 5                                   ' boost pads across the road
            For l = 0 To LANES - 1: tile(base + l) = T_BOOST: Next l
    End Select
End Sub

Public Sub EnsureRows()
    Dim want As Long
    want = Int(-bz / ROWLEN) + 24
    Do While genRow <= want
        GenRowNow
    Loop
End Sub

' ---- a game ----
Public Sub NewGame(ByVal seed As Long)
    Dim i As Long
    RngSeed seed
    genRow = 0
    segLeft = 0: segType = 0
    lastFull = 10
    bx = 0: by = BALLR: bz = -1
    bvx = 0: bvy = 0
    speed = 0.35: boost = 0: spin = 0
    onGround = True: falling = False
    crashT = 0: ghostT = 0
    lives = 3: score = 0: gems = 0
    nextLife = 5000
    gameOver = False
    frameNo = 0
    For i = 0 To NLABELS - 1: labT(i) = 0: Next i
    EnsureRows
End Sub

Public Function BallRow() As Long
    BallRow = Int(-bz / ROWLEN)
End Function

' the lane under x, -1 between the road's edges and beyond
Public Function LaneOf(ByVal x As Double) As Long
    Dim l As Long
    l = Int((x + 5) / LANEW)
    If x < -5.25 Or x > 5.25 Then l = -1
    If l > LANES - 1 And x <= 5.25 Then l = LANES - 1
    If l < 0 And x >= -5.25 Then l = 0
    LaneOf = l
End Function

Private Sub AddLabel(ByVal x As Double, ByVal y As Double, ByVal z As Double, ByVal t As String)
    Dim i As Long, best As Long
    best = 0
    For i = 0 To NLABELS - 1
        If labT(i) < labT(best) Then best = i
    Next i
    labX(best) = x: labY(best) = y: labZ(best) = z
    labT(best) = 30: labText(best) = t
End Sub

Private Sub AddScore(ByVal n As Long)
    score = score + n
    If score >= nextLife Then
        nextLife = nextLife + 5000
        If lives < 9 Then lives = lives + 1
        lastEvent = "life"
    End If
End Sub

Private Sub Respawn()
    Dim r As Long, l As Long, best As Long, ok As Boolean
    r = BallRow()
    Do
        best = -1
        For l = 2 To 2 + LANES - 1                ' the middle lane first, then the others
            If best < 0 Then
                If TileAt(r, l Mod LANES) <> T_GAP And TileAt(r + 1, l Mod LANES) <> T_GAP And _
                   TileAt(r, l Mod LANES) <> T_RAMP And ThingAt(r, l Mod LANES) <> O_BLOCK Then best = l Mod LANES
            End If
        Next l
        If best >= 0 Then Exit Do
        r = r + 1
        bz = -r * ROWLEN
        EnsureRows
    Loop
    bz = -r * ROWLEN - 0.5
    bx = LaneX(best)
    by = BALLR: bvy = 0: bvx = 0
    onGround = True: falling = False
    boost = 0
    ghostT = 60
    EnsureRows
End Sub

Private Sub LoseLife(ByVal why As String)
    lastEvent = why
    crashKind = why
    eventX = bx: eventY = by: eventZ = bz
    crashT = 36
    lives = lives - 1
End Sub

' one frame of play with the keys in inp
Public Sub GameStep(ByVal inp As Long)
    Dim r As Long, l As Long, t As Long, rz As Double, base As Double, ax As Double, oldz As Double
    Dim i As Long, dz As Double
    lastEvent = ""
    frameNo = frameNo + 1
    For i = 0 To NLABELS - 1
        If labT(i) > 0 Then labT(i) = labT(i) - 1: labY(i) = labY(i) + 0.06: labZ(i) = labZ(i) - speed
    Next i
    If gameOver Then Exit Sub
    If crashT > 0 Then
        crashT = crashT - 1
        If crashT = 0 Then
            If lives <= 0 Then
                gameOver = True
                lastEvent = "over"
            Else
                Respawn
            End If
        End If
        Exit Sub
    End If
    If ghostT > 0 Then ghostT = ghostT - 1

    ' speed: rises with distance, boosts on top fade away
    base = 0.35 + 0.27 * Difficulty(BallRow())
    If boost > 0 Then boost = boost - 0.004
    If boost < 0 Then boost = 0
    speed = base + boost

    ' steering: accelerate sideways, damped; less grip in the air
    ax = 0
    If (inp And IN_LEFT) <> 0 Then ax = ax - 1
    If (inp And IN_RIGHT) <> 0 Then ax = ax + 1
    bvx = bvx + ax * IIf(onGround, 0.045, 0.025)
    bvx = bvx * 0.86
    bx = bx + bvx

    ' forward, and the ball rolls: 360 degrees per 2 pi r travelled
    oldz = bz
    bz = bz - speed
    spin = spin + speed / (2 * 3.14159265 * BALLR) * 360
    If spin >= 360 Then spin = spin - 360
    EnsureRows

    ' jumping and falling
    If onGround And (inp And IN_JUMP) <> 0 Then
        bvy = JUMPV
        onGround = False
        lastEvent = "jump"
    End If
    r = BallRow()
    l = LaneOf(bx)
    t = T_GAP
    If l >= 0 Then t = TileAt(r, l)
    If Not onGround Then
        bvy = bvy - GRAVITY
        by = by + bvy
        If by <= BALLR And bvy < 0 Then
            If t <> T_GAP And Not falling And by > BALLR - 0.5 Then
                by = BALLR: bvy = 0: onGround = True
            ElseIf by < BALLR - 0.5 Then
                falling = True                     ' below the tops: no landing any more
            End If
        End If
    ElseIf t = T_GAP Then
        onGround = False                          ' rolled off an edge
        bvy = 0
    End If
    If onGround Then
        If t = T_BOOST Then
            If boost < 0.2 Then lastEvent = "boost": AddScore 25
            boost = 0.25
        ElseIf t = T_RAMP Then
            rz = -bz - r * ROWLEN                 ' how far along the ramp
            If rz > ROWLEN - speed - 0.05 Then
                bvy = RAMPV
                onGround = False
                lastEvent = "ramp"
            End If
        End If
    End If
    If by < -6 Then LoseLife "fall": Exit Sub

    ' gems and blocks in this row and the next (the ball spans both near a boundary)
    For dz = 0 To 1
        For i = 0 To LANES - 1
            Select Case ThingAt(r + dz, i)
                Case O_GEM
                    If Abs(bx - LaneX(i)) < 1.1 And Abs(-bz - ((r + dz) * ROWLEN + ROWLEN / 2)) < 1.1 And by < 2.6 Then
                        SetThing r + dz, i, O_NONE
                        gems = gems + 1
                        AddScore 100
                        AddLabel LaneX(i), 1.6, -((r + dz) * ROWLEN + ROWLEN / 2), "+100"
                        lastEvent = "gem"
                    End If
                Case O_BLOCK
                    If ghostT = 0 Then
                        If Abs(bx - LaneX(i)) < 0.7 + BALLR And Abs(-bz - ((r + dz) * ROWLEN + ROWLEN / 2)) < 0.7 + BALLR _
                           And by - BALLR < 1.35 Then
                            LoseLife "crash": Exit Sub
                        End If
                    End If
            End Select
        Next i
    Next dz
    ' distance score: a point a unit
    If Int(-bz) > Int(-oldz) Then AddScore Int(-bz) - Int(-oldz)
End Sub

' ---- the autopilot (title screen demo, --bench) ----
Public Function AutoInput() As Long
    Dim r As Long, l As Long, k As Long, best As Long, bestS As Double, s As Double, cur As Long
    Dim hasTile As Boolean, j As Long, dist As Double, lead As Double, aheadR As Long, aheadL As Long, tx As Double, inp As Long
    r = BallRow()
    cur = LaneOf(bx)
    If cur < 0 Then cur = IIf(bx < 0, 0, LANES - 1)
    best = cur: bestS = -1E+30
    For l = 0 To LANES - 1
        s = -Abs(l - cur) * 4
        For k = 0 To 5
            hasTile = False
            For j = 0 To LANES - 1
                If TileAt(r + k, j) <> T_GAP Then hasTile = True
            Next j
            If TileAt(r + k, l) = T_GAP And hasTile Then s = s - 90 / (k + 0.6)
            If ThingAt(r + k, l) = O_BLOCK Then
                If k > 0 Then
                    s = s - 120 / (k * k)
                ElseIf r * ROWLEN + ROWLEN / 2 > -bz - 1.5 Then
                    s = s - 70                         ' a block ahead or beside us in this row
                End If
            End If
            If k > 0 Then
                If ThingAt(r + k, l) = O_GEM Then s = s + 12 / k
            End If
            ' a path we can't steer to in time: lanes further away need more rows
            If Abs(l - cur) > k + 1 Then s = s - 5
        Next k
        If s > bestS Then bestS = s: best = l
    Next l
    tx = LaneX(best)
    If bx < tx - 0.25 Then inp = inp Or IN_RIGHT
    If bx > tx + 0.25 Then inp = inp Or IN_LEFT
    ' jump just before a gap or a block in the lane ahead
    If onGround Then
        lead = speed * 3 + 0.9
        aheadR = Int((-bz + lead) / ROWLEN)
        aheadL = LaneOf(bx)
        If aheadL >= 0 Then
            If aheadR > r And TileAt(aheadR, aheadL) = T_GAP Then
                hasTile = False
                For j = 0 To LANES - 1
                    If TileAt(aheadR, j) <> T_GAP Then hasTile = True
                Next j
                If Not hasTile Then inp = inp Or IN_JUMP
            End If
        End If
        ' a block ahead in this lane that steering can't get round in time (the better lane is
        ' too far, sideways ~0.28 a frame): jump so the top of the arc (12.8 frames after the
        ' jump) is over the block
        If aheadL >= 0 Then
            For k = 0 To 2
                If ThingAt(r + k, aheadL) = O_BLOCK Then
                    dist = (r + k) * ROWLEN + ROWLEN / 2 - (-bz)
                    If dist > 0 And dist <= speed * 12.8 Then
                        If best = aheadL Or Abs(LaneX(best) - bx) > dist / speed * 0.28 - 1.2 Then inp = inp Or IN_JUMP
                    End If
                    Exit For
                End If
            Next k
        End If
    End If
    AutoInput = inp
End Function

' a checksum of the game's state (tests: VM, JIT and native must agree)
Public Function StateHash() As Long
    Dim h As Double
    h = score * 31# + gems * 7# + lives * 1009# + Int(-bz * 100) + Int(bx * 1000) * 3# + genRow * 13# + frameNo
    StateHash = CLng(h - Int(h / 2147483647#) * 2147483647#)
End Function
