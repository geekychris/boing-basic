' PbCore - Boing Pinball's simulation: the three tables, the fixed-step physics
' and the rules, a port of pb_core.c and pb_tables.c from amiga_mcp's
' examples/boing_pinball (itself the browser game's boing-pinball-core.js).
'
' Units are millimetres and seconds in the plane of the playfield, 16.16 fixed
' point in Longs, computed exactly as the C (A3Fix.bas): the bot's games give the
' C's state hashes (tools/trace.sh against Trace.bbp). x runs across (0 = the left
' wall), y up the table (0 = just below the flippers). Each 1/120 s step is split
' into substeps short enough that nothing tunnels; the ball tests only what is in
' its 64 mm grid cell.
Option Explicit

Public Const PB_HZ As Long = 120
Public Const PB_STEP As Long = 546              ' FONE / 120
Public Const PB_R As Long = 884736              ' FX(13.5), the ball's radius
Public Const PB_GRAVITY As Long = 1500
Public Const PB_MAX_SPEED As Long = 458752000   ' FROMI(7000)
Public Const PB_MID As Long = 239
Public Const PB_WIDTH As Long = 520
Public Const PB_TOP As Long = 1040

Public Const PB_MAX_SEG As Long = 200
Public Const PB_MAX_CIRC As Long = 16
Public Const PB_MAX_SENS As Long = 24
Public Const PB_MAX_FLIP As Long = 3
Public Const PB_MAX_RAMP As Long = 2
Public Const PB_MAX_RPTS As Long = 16
Public Const PB_MAX_SPIN As Long = 2
Public Const PB_MAX_BALLS As Long = 4
Public Const PB_MAX_EV As Long = 64
Public Const PB_MAX_MSG As Long = 6
Public Const PB_MAX_TIMER As Long = 8

Public Const PB_GX As Long = 9
Public Const PB_GY As Long = 19
Public Const PB_GMAX As Long = 40

' segment kinds
Public Const SK_WALL As Long = 0
Public Const SK_OUTER As Long = 1
Public Const SK_SLING As Long = 2
Public Const SK_GATE As Long = 3
Public Const SK_FLOOR As Long = 4
Public Const SK_DROP As Long = 5
Public Const SK_GUIDE As Long = 6
' sensor kinds
Public Const SN_LANE As Long = 0
Public Const SN_IN As Long = 1
Public Const SN_OUT As Long = 2
Public Const SN_SPIN As Long = 3
Public Const SN_RAMPIN As Long = 4
Public Const SN_LANEOUT As Long = 5

' lamps
Public Const L_LANE0 As Long = 0
Public Const L_LOCK0 As Long = 3
Public Const L_JACKPOT As Long = 6
Public Const L_M0 As Long = 7
Public Const L_MISSION As Long = 12
Public Const L_X2 As Long = 13
Public Const L_SAVE As Long = 17
Public Const L_SPIN0 As Long = 18
Public Const L_SUPER As Long = 20
Public Const L_DROP0 As Long = 21
Public Const L_COUNT As Long = 29
Public Const LC_BLUE As Long = 0
Public Const LC_YELLOW As Long = 1
Public Const LC_RED As Long = 2
Public Const LC_GREEN As Long = 3
Public Const LC_MAGENTA As Long = 4
Public Const LC_ORANGE As Long = 5

Public Const TB_COMET As Long = 0
Public Const TB_DEEP As Long = 1
Public Const TB_FOUNDRY As Long = 2
Public Const TB_COUNT As Long = 3

' ball states
Public Const BS_PLAY As Long = 0
Public Const BS_LANE As Long = 1
Public Const BS_RAMP As Long = 2
Public Const BS_SAUCER As Long = 3
Public Const BS_DRAINED As Long = 4

' events
Public Const EV_WALL As Long = 0
Public Const EV_SLING As Long = 1
Public Const EV_DROP As Long = 2
Public Const EV_BUMPER As Long = 3
Public Const EV_FLIPHIT As Long = 4
Public Const EV_FLIPSTOP As Long = 5
Public Const EV_SPINHIT As Long = 6
Public Const EV_SPIN As Long = 7
Public Const EV_SENSOR As Long = 8
Public Const EV_RAMPENTER As Long = 9
Public Const EV_RAMP As Long = 10
Public Const EV_RAMPFAIL As Long = 11
Public Const EV_SAUCER As Long = 12
Public Const EV_KICK As Long = 13
Public Const EV_LANEREST As Long = 14
Public Const EV_DRAIN As Long = 15
Public Const EV_PLUNGE As Long = 16
Public Const EV_SCORE As Long = 17
Public Const EV_SKILL As Long = 18
Public Const EV_LANESDONE As Long = 19
Public Const EV_BANK As Long = 20
Public Const EV_BANKRESET As Long = 21
Public Const EV_LOCK As Long = 22
Public Const EV_MULTIBALL As Long = 23
Public Const EV_JACKPOT As Long = 24
Public Const EV_MISSIONSTART As Long = 25
Public Const EV_MISSIONDONE As Long = 26
Public Const EV_MISSIONFAIL As Long = 27
Public Const EV_SUPERNOVA As Long = 28
Public Const EV_SAVE As Long = 29
Public Const EV_ENDBALL As Long = 30
Public Const EV_GAMEOVER As Long = 31
Public Const EV_TILTWARN As Long = 32
Public Const EV_TILT As Long = 33
Public Const EV_NUDGE As Long = 34
Public Const EV_OUTLANE As Long = 35
Public Const EV_COUNT As Long = 36

' game states
Public Const GS_ATTRACT As Long = 0
Public Const GS_PLAY As Long = 1
Public Const GS_BONUS As Long = 2
Public Const GS_OVER As Long = 3

Private Const MI_BUMPER As Long = 0
Private Const MI_BANK As Long = 1
Private Const MI_SPIN As Long = 2
Private Const MI_RAMP As Long = 3
Private Const MI_LANES As Long = 4
Private Const TM_BANK_RESET As Long = 0
Private Const TM_SERVE As Long = 1

Private Const FONE_ As Long = 65536
Private Const FPI As Long = 205887
Private Const SLOW As Long = 3932160            ' FROMI(60)
Private Const MISSION_TIME As Long = 4800
Private Const SAVE_TIME As Long = 1200
Private Const NOXY As Long = -9999

Public Type PbSeg
    ax As Long
    ay As Long
    bx As Long
    by As Long
    ux As Long
    uy As Long
    ln As Long
    r As Long
    e As Long
    kind As Long
    id As Long
    owx As Long
    owy As Long
    up As Long
    bank As Long
    h As Long
    bb0 As Long
    bb1 As Long
    bb2 As Long
    bb3 As Long
End Type

Public Type PbCirc
    cx As Long
    cy As Long
    r As Long
    e As Long
    bumper As Long
    id As Long
    h As Long
End Type

Public Type PbSens
    ax As Long
    ay As Long
    bx As Long
    by As Long
    kind As Long
    idx As Long
    bb0 As Long
    bb1 As Long
    bb2 As Long
    bb3 As Long
End Type

' a flipper: the table's definition and the world's state
Public Type PbFlip
    side As Long
    px As Long
    py As Long
    ln As Long
    r1 As Long
    r2 As Long
    rest As Long
    up As Long
    ang As Long
    w As Long
    held As Long
End Type

Public Type PbBall
    id As Long
    st As Long
    ramp As Long
    x As Long
    y As Long
    vx As Long
    vy As Long
    z As Long
    rs As Long
    rv As Long
    hold As Long
    nocatch As Long
    autol As Long
End Type

Public Type PbEvent
    etype As Long
    id As Long
    kind As Long
    up As Long
    x As Long
    y As Long
    ball As Long
    val As Long
End Type

' ---------------------------------------------------------------- the table
Public tName As String
Public tBlurb As String
Public tMission(0 To 4) As String
Public tTheme As Long
Public sg(0 To 199) As PbSeg
Public tNseg As Long
Public cc(0 To 15) As PbCirc
Public tNcirc As Long
Public sn(0 To 23) As PbSens
Public tNsens As Long
Public fl(0 To 2) As PbFlip
Public tNflip As Long
Public tNramp As Long
Public rampN(0 To 1) As Long
Public rpx(0 To 31) As Long                     ' ramp * 16 + point: x, y, height (mm)
Public rpy(0 To 31) As Long
Public rpz(0 To 31) As Long
Public rprof(0 To 31) As Long                   ' arc length to each point
Public rExitX(0 To 1) As Long
Public rExitY(0 To 1) As Long
Public rExitVy(0 To 1) As Long
Public tNspin As Long
Public spX(0 To 1) As Long
Public spY(0 To 1) As Long
Public tNdrop As Long
Public tNbank As Long
Public dropSeg(0 To 15) As Long
Public saucerX As Long
Public saucerY As Long
Public saucerR As Long
Public plungerX As Long
Public plungerRest As Long
Public lampX(0 To 28) As Long
Public lampY(0 To 28) As Long
Public lampR(0 To 28) As Long
Public lampCol(0 To 28) As Long
Public grid(0 To 6839) As Long                  ' ((gy * 9 + gx) * 40 + k): (type << 12) | index
Public ngrid(0 To 170) As Long

Public missionGoal(0 To 4) As String
Public missionNeed(0 To 4) As Long
Public missionAward(0 To 4) As Long

' ---------------------------------------------------------------- the world
Public bl(0 To 3) As PbBall
Public wNballs As Long
Public spAng(0 To 1) As Long
Public spW(0 To 1) As Long
Public wev(0 To 63) As PbEvent
Public wNev As Long
Public wNextId As Long
Public wPower As Long
Public wActive As Long
Public wSubsteps As Long
Public wTests As Long

' ---------------------------------------------------------------- the game
Public gState As Long
Public gBallsPerGame As Long
Public gExtraBalls As Long
Public gScore As Long
Public gTime As Long
Public gBallNo As Long
Public gLanes(0 To 2) As Long
Public gSkillLane As Long
Public gSkillArmed As Long
Public gBonusX As Long
Public gBanks As Long
Public gRamps As Long
Public gLocks As Long
Public gMissionsDone As Long
Public gMission As Long
Public gMissionN As Long
Public gMissionUntil As Long
Public gMissionLit As Long
Public gMultiball As Long
Public gJackpot As Long
Public gSupernova As Long
Public gSaveUntil As Long
Public gPlungeAt As Long
Public gJackpotLit As Long
Public gBonusRamps As Long
Public gBonusTargets As Long
Public gBonusLanes As Long
Public gBonusSpins As Long
Public gBonusPts As Long
Public gBonusT As Long
Public gTiltMeter As Long
Public gTiltWarnings As Long
Public gTilted As Long
Public gPull As Long
Public gPullHeld As Long
Public msgUntil(0 To 5) As Long
Public msgAt(0 To 5) As Long
Public msgBig(0 To 5) As String
Public msgSmall(0 To 5) As String
Public gNmsg As Long
Private tmAt(0 To 7) As Long
Private tmKind(0 To 7) As Long
Private tmArg(0 To 7) As Long
Public gNtimers As Long
Public gev(0 To 63) As PbEvent
Public gNev As Long
Public gRng As Long

' the input of a step
Public inLeft As Long
Public inRight As Long
Public inPlunger As Long
Public inPullTo As Long
Public inNudgeX As Long
Public inNudgeY As Long

' the bot
Public botRng As Long
Public botHold(0 To 1) As Long
Public botLaunch As Long

' the dot-matrix display's text (PbDmd)
Public dmdBig As String
Public dmdSmall As String
Public dmdFlash As Long
Public lampOn(0 To 28) As Long

Private cev As PbEvent                          ' the event being handled
Private coreReady As Boolean

' ================================================================ fixed point (inlined)

Private Function FM(ByVal a As Long, ByVal b As Long) As Long
    FM = Int(CDbl(a) * b / 65536#)
End Function

Private Function FD(ByVal a As Long, ByVal b As Long) As Long
    FD = Fix(CDbl(a) * 65536# / b)
End Function

Private Function FI(ByVal a As Long) As Long
    FI = (a - (a And 65535)) \ 65536
End Function

Private Function FAbs(ByVal a As Long) As Long
    If a < 0 Then FAbs = -a Else FAbs = a
End Function

Private Function FSign(ByVal v As Long) As Long
    If v > 0 Then
        FSign = 1
    ElseIf v < 0 Then
        FSign = -1
    Else
        FSign = 0
    End If
End Function

Private Function FClamp(ByVal v As Long, ByVal lo As Long, ByVal hi As Long) As Long
    If v < lo Then
        FClamp = lo
    ElseIf v > hi Then
        FClamp = hi
    Else
        FClamp = v
    End If
End Function

' fhypot: scaled down until the squares fit 32 bits, as the C
Private Function Hyp(ByVal a As Long, ByVal b As Long) As Long
    Dim x As Long, y As Long, sh As Long, v As Double, r As Long
    If a < 0 Then x = -a Else x = a
    If b < 0 Then y = -b Else y = b
    sh = 1
    Do While (x Or y) >= 46000
        x = x \ 2
        y = y \ 2
        sh = sh + sh
    Loop
    v = CDbl(x) * x + CDbl(y) * y
    r = Int(Sqr(v))
    If CDbl(r) * r > v Then r = r - 1
    If CDbl(r + 1) * (r + 1) <= v Then r = r + 1
    Hyp = r * sh
End Function

' ================================================================ set-up

Public Sub PbCoreInit()
    If coreReady Then Exit Sub
    A3FixInit
    missionGoal(0) = "POP BUMPERS": missionNeed(0) = 25: missionAward(0) = 40000
    missionGoal(1) = "TARGET BANKS": missionNeed(1) = 2: missionAward(1) = 50000
    missionGoal(2) = "SPINS": missionNeed(2) = 40: missionAward(2) = 45000
    missionGoal(3) = "RAMP SHOTS": missionNeed(3) = 3: missionAward(3) = 60000
    missionGoal(4) = "LANE SETS": missionNeed(4) = 2: missionAward(4) = 55000
    coreReady = True
End Sub

Public Function PbTableName(ByVal which As Long) As String
    Select Case which
        Case TB_DEEP: PbTableName = "DEEP DIVE"
        Case TB_FOUNDRY: PbTableName = "ROBOT FOUNDRY"
        Case Else: PbTableName = "COMET TOUR"
    End Select
End Function

' ================================================================ collisions

Public Sub SegInit(ByVal i As Long, ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, _
                   ByVal r As Long, ByVal e As Long, ByVal kind As Long)
    Dim ex As Long, ey As Long, grow As Long, mn As Long, mx As Long
    ex = bx - ax
    ey = by - ay
    grow = r + PB_R + 262144
    sg(i).ax = ax: sg(i).ay = ay: sg(i).bx = bx: sg(i).by = by
    sg(i).r = r: sg(i).e = e: sg(i).kind = kind
    sg(i).id = 0: sg(i).owx = 0: sg(i).owy = 0: sg(i).bank = 0: sg(i).h = 0
    sg(i).ln = FHypot(ex, ey)
    sg(i).ux = 0: sg(i).uy = 0
    If sg(i).ln > 0 Then
        sg(i).ux = FD(ex, sg(i).ln)
        sg(i).uy = FD(ey, sg(i).ln)
    End If
    If ax < bx Then mn = ax: mx = bx Else mn = bx: mx = ax
    sg(i).bb0 = FI(mn - grow)
    sg(i).bb2 = FI(mx + grow) + 1
    If ay < by Then mn = ay: mx = by Else mn = by: mx = ay
    sg(i).bb1 = FI(mn - grow)
    sg(i).bb3 = FI(mx + grow) + 1
    sg(i).up = 1
End Sub

Private Sub Bounce(ByVal bi As Long, ByVal nx As Long, ByVal ny As Long, ByVal vn As Long, ByVal e As Long, ByVal fric As Long)
    Dim tx As Long, ty As Long, ee As Long, k As Long, en As Long
    tx = bl(bi).vx - FM(vn, nx)
    ty = bl(bi).vy - FM(vn, ny)
    If -vn < SLOW Then
        ee = 0: k = FONE_
    Else
        ee = e: k = FONE_ - fric
    End If
    en = FM(ee, vn)
    bl(bi).vx = FM(tx, k) - FM(en, nx)
    bl(bi).vy = FM(ty, k) - FM(en, ny)
End Sub

' the ball against a capsule segment: resolves the overlap, returns the approach speed or -1
Public Function HitSegment(ByVal bi As Long, ByVal si As Long) As Long
    Dim dx As Long, dy As Long, t As Long, qx As Long, qy As Long, rr As Long, d2 As Long, d As Long
    Dim nx As Long, ny As Long, vn As Long
    dx = bl(bi).x - sg(si).ax
    dy = bl(bi).y - sg(si).ay
    rr = PB_R + sg(si).r
    t = FClamp(FM(dx, sg(si).ux) + FM(dy, sg(si).uy), 0, sg(si).ln)
    qx = sg(si).ax + FM(sg(si).ux, t)
    qy = sg(si).ay + FM(sg(si).uy, t)
    dx = bl(bi).x - qx
    dy = bl(bi).y - qy
    If dx >= rr Or -dx >= rr Or dy >= rr Or -dy >= rr Then
        HitSegment = -1
        Exit Function
    End If
    d2 = FM(dx, dx) + FM(dy, dy)
    If d2 >= FM(rr, rr) Then
        HitSegment = -1
        Exit Function
    End If
    d = FSqrt(d2)
    If d < 4 Then
        nx = -sg(si).uy
        ny = sg(si).ux
        If FM(nx, bl(bi).vx) + FM(ny, bl(bi).vy) > 0 Then nx = -nx: ny = -ny
    Else
        nx = FD(dx, d)
        ny = FD(dy, d)
    End If
    vn = FM(bl(bi).vx, nx) + FM(bl(bi).vy, ny)
    If sg(si).owx <> 0 Or sg(si).owy <> 0 Then
        If CDbl(nx) * sg(si).owx + CDbl(ny) * sg(si).owy <= 0 Or vn >= 0 Then
            HitSegment = -1
            Exit Function
        End If
    End If
    bl(bi).x = qx + FM(nx, rr)
    bl(bi).y = qy + FM(ny, rr)
    If vn < 0 Then
        Bounce bi, nx, ny, vn, sg(si).e, 1966
        HitSegment = -vn
    Else
        HitSegment = 0
    End If
End Function

Private hcNx As Long, hcNy As Long              ' HitCircle's normal

Public Function HitCircle(ByVal bi As Long, ByVal ci As Long) As Long
    Dim dx As Long, dy As Long, rr As Long, d2 As Long, d As Long, nx As Long, ny As Long, vn As Long
    dx = bl(bi).x - cc(ci).cx
    dy = bl(bi).y - cc(ci).cy
    rr = PB_R + cc(ci).r
    If dx >= rr Or -dx >= rr Or dy >= rr Or -dy >= rr Then
        HitCircle = -1
        Exit Function
    End If
    d2 = FM(dx, dx) + FM(dy, dy)
    If d2 >= FM(rr, rr) Then
        HitCircle = -1
        Exit Function
    End If
    d = FSqrt(d2)
    If d < 4 Then
        nx = 0: ny = FONE_
    Else
        nx = FD(dx, d)
        ny = FD(dy, d)
    End If
    bl(bi).x = cc(ci).cx + FM(nx, rr)
    bl(bi).y = cc(ci).cy + FM(ny, rr)
    vn = FM(bl(bi).vx, nx) + FM(bl(bi).vy, ny)
    If vn < 0 Then Bounce bi, nx, ny, vn, cc(ci).e, 1310
    hcNx = nx
    hcNy = ny
    If vn < 0 Then HitCircle = -vn Else HitCircle = 0
End Function

Public tipX As Long, tipY As Long               ' FlipperTip's result

Public Sub FlipperTip(ByVal fi As Long)
    tipX = fl(fi).px + FM(fl(fi).ln, FCosR(fl(fi).ang))
    tipY = fl(fi).py + FM(fl(fi).ln, FSinR(fl(fi).ang))
End Sub

' the ball against a (moving) flipper, a tapered capsule; the contact's velocity is w x r
Public Function HitFlipper(ByVal bi As Long, ByVal fi As Long) As Long
    Dim ex As Long, ey As Long, t As Long, qx As Long, qy As Long, rad As Long, dx As Long, dy As Long
    Dim rr As Long, d2 As Long, d As Long, nx As Long, ny As Long, cx As Long, cy As Long
    Dim vcx As Long, vcy As Long, rvx As Long, rvy As Long, vn As Long, e As Long, ee As Long, k As Long
    Dim en As Long, sx As Long, sy As Long
    FlipperTip fi
    ex = tipX - fl(fi).px
    ey = tipY - fl(fi).py
    t = FD(FM(bl(bi).x - fl(fi).px, ex) + FM(bl(bi).y - fl(fi).py, ey), FM(fl(fi).ln, fl(fi).ln))
    t = FClamp(t, 0, FONE_)
    qx = fl(fi).px + FM(t, ex)
    qy = fl(fi).py + FM(t, ey)
    rad = fl(fi).r1 + FM(fl(fi).r2 - fl(fi).r1, t)
    dx = bl(bi).x - qx
    dy = bl(bi).y - qy
    rr = PB_R + rad
    If dx >= rr Or -dx >= rr Or dy >= rr Or -dy >= rr Then
        HitFlipper = -1
        Exit Function
    End If
    d2 = FM(dx, dx) + FM(dy, dy)
    If d2 >= FM(rr, rr) Then
        HitFlipper = -1
        Exit Function
    End If
    d = FSqrt(d2)
    If d < 4 Then
        nx = -FD(ey, fl(fi).ln)
        ny = FD(ex, fl(fi).ln)
        If fl(fi).w < 0 Then nx = -nx: ny = -ny
    Else
        nx = FD(dx, d)
        ny = FD(dy, d)
    End If
    cx = qx + FM(nx, rad)
    cy = qy + FM(ny, rad)
    vcx = -FM(fl(fi).w, cy - fl(fi).py)
    vcy = FM(fl(fi).w, cx - fl(fi).px)
    bl(bi).x = qx + FM(nx, rr)
    bl(bi).y = qy + FM(ny, rr)
    rvx = bl(bi).vx - vcx
    rvy = bl(bi).vy - vcy
    vn = FM(rvx, nx) + FM(rvy, ny)
    If vn < 0 Then
        If FAbs(fl(fi).w) > FONE_ Then e = 36044 Else e = 19660
        If -vn < SLOW Then
            ee = 0: k = FONE_
        Else
            ee = e: k = 63569
        End If
        en = FM(ee, vn)
        sx = rvx - FM(vn, nx)
        sy = rvy - FM(vn, ny)
        bl(bi).vx = vcx + FM(sx, k) - FM(en, nx)
        bl(bi).vy = vcy + FM(sy, k) - FM(en, ny)
        HitFlipper = -vn
    Else
        HitFlipper = 0
    End If
End Function

Public Function HitBalls(ByVal ai As Long, ByVal bi As Long) As Long
    Dim dx As Long, dy As Long, rr As Long, d2 As Long, d As Long, nx As Long, ny As Long, pen As Long
    Dim rel As Long, j As Long
    dx = bl(bi).x - bl(ai).x
    dy = bl(bi).y - bl(ai).y
    rr = 2 * PB_R
    If FAbs(dx) >= rr Or FAbs(dy) >= rr Then Exit Function
    d2 = FM(dx, dx) + FM(dy, dy)
    If d2 >= FM(rr, rr) Or d2 = 0 Then Exit Function
    d = FSqrt(d2)
    If d < 4 Then Exit Function
    nx = FD(dx, d)
    ny = FD(dy, d)
    pen = (rr - d) \ 2
    bl(ai).x = bl(ai).x - FM(nx, pen): bl(ai).y = bl(ai).y - FM(ny, pen)
    bl(bi).x = bl(bi).x + FM(nx, pen): bl(bi).y = bl(bi).y + FM(ny, pen)
    rel = FM(bl(bi).vx - bl(ai).vx, nx) + FM(bl(bi).vy - bl(ai).vy, ny)
    If rel < 0 Then
        j = FM(rel, 62259)
        bl(ai).vx = bl(ai).vx + FM(j, nx): bl(ai).vy = bl(ai).vy + FM(j, ny)
        bl(bi).vx = bl(bi).vx - FM(j, nx): bl(bi).vy = bl(bi).vy - FM(j, ny)
    End If
    HitBalls = 1
End Function

' did the move p0 -> p1 cross the sensor line? +1 / -1 (the side crossed to), or 0
Public Function Crossed(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal si As Long) As Long
    Dim ex As Long, ey As Long, d0 As Long, d1 As Long, t As Long, px As Long, py As Long, u As Long, l2 As Long
    ex = sn(si).bx - sn(si).ax
    ey = sn(si).by - sn(si).ay
    d0 = FM(ex, y0 - sn(si).ay) - FM(ey, x0 - sn(si).ax)
    d1 = FM(ex, y1 - sn(si).ay) - FM(ey, x1 - sn(si).ax)
    If (d0 > 0) = (d1 > 0) Or d0 = d1 Then Exit Function
    t = FD(d0, d0 - d1)
    px = x0 + FM(x1 - x0, t)
    py = y0 + FM(y1 - y0, t)
    l2 = FM(ex, ex) + FM(ey, ey)
    u = FD(FM(px - sn(si).ax, ex) + FM(py - sn(si).ay, ey), l2)
    If u < 0 Or u > FONE_ Then Exit Function
    If d1 > 0 Then Crossed = 1 Else Crossed = -1
End Function

' ================================================================ the ramps

Public raX As Long, raY As Long, raZ As Long, raSlope As Long, raDx As Long, raDy As Long

Public Sub RampAt(ByVal ri As Long, ByVal s As Long)
    Dim L As Long, t As Long, seglen As Long, i As Long, a As Long, b As Long, n As Long
    n = rampN(ri)
    L = rprof(ri * 16 + n - 1)
    s = FClamp(s, 0, L)
    i = 1
    Do While i < n - 1
        If rprof(ri * 16 + i) >= s Then Exit Do
        i = i + 1
    Loop
    a = ri * 16 + i - 1
    b = a + 1
    seglen = rprof(b) - rprof(a)
    If seglen <= 0 Then seglen = FONE_
    t = FD(s - rprof(a), seglen)
    raX = rpx(a) * 65536 + FM((rpx(b) - rpx(a)) * 65536, t)
    raY = rpy(a) * 65536 + FM((rpy(b) - rpy(a)) * 65536, t)
    raZ = rpz(a) * 65536 + FM((rpz(b) - rpz(a)) * 65536, t)
    raSlope = FD((rpz(b) - rpz(a)) * 65536, seglen)
    raDx = FD((rpx(b) - rpx(a)) * 65536, seglen)
    raDy = FD((rpy(b) - rpy(a)) * 65536, seglen)
End Sub

' ================================================================ the world

Private Sub Emit(ByVal etype As Long, ByVal x As Long, ByVal y As Long, ByVal id As Long, ByVal up As Long, _
                 ByVal v As Long, ByVal ball As Long)
    If wNev >= PB_MAX_EV Then Exit Sub
    wev(wNev).etype = etype: wev(wNev).id = id: wev(wNev).kind = 0: wev(wNev).up = up
    wev(wNev).x = FI(x): wev(wNev).y = FI(y): wev(wNev).val = v: wev(wNev).ball = ball
    wNev = wNev + 1
End Sub

Public Sub WorldInit()
    Dim i As Long
    wNballs = 0: wNev = 0: wTests = 0
    For i = 0 To tNflip - 1
        fl(i).ang = fl(i).rest
        fl(i).w = 0
        fl(i).held = 0
    Next i
    For i = 0 To 1
        spAng(i) = 0: spW(i) = 0
    Next i
    For i = 0 To tNseg - 1
        If sg(i).kind = SK_DROP Then sg(i).up = 1
    Next i
    wNextId = 1
    wPower = 1: wActive = 1
    wSubsteps = 1
End Sub

' a new ball; returns its index or -1
Public Function AddBall(ByVal x As Long, ByVal y As Long, ByVal vx As Long, ByVal vy As Long, ByVal st As Long) As Long
    Dim i As Long
    If wNballs >= PB_MAX_BALLS Then
        AddBall = -1
        Exit Function
    End If
    i = wNballs
    wNballs = wNballs + 1
    bl(i).id = wNextId
    wNextId = wNextId + 1
    bl(i).x = x: bl(i).y = y: bl(i).vx = vx: bl(i).vy = vy: bl(i).st = st
    bl(i).ramp = 0: bl(i).z = 0: bl(i).rs = 0: bl(i).rv = 0: bl(i).hold = 0: bl(i).nocatch = 0
    bl(i).autol = -1
    AddBall = i
End Function

Public Sub RemoveDrained()
    Dim i As Long, n As Long
    For i = 0 To wNballs - 1
        If bl(i).st <> BS_DRAINED Then
            If n <> i Then bl(n) = bl(i)
            n = n + 1
        End If
    Next i
    wNballs = n
End Sub

Private Sub FlipperStep(ByVal fi As Long, ByVal h As Long)
    Dim want As Long, lo As Long, hi As Long, target As Long, sgn As Long, wmax As Long, acc As Long, m As Long
    If fl(fi).held <> 0 And wPower <> 0 Then want = 1
    If fl(fi).rest < fl(fi).up Then
        lo = fl(fi).rest: hi = fl(fi).up
    Else
        lo = fl(fi).up: hi = fl(fi).rest
    End If
    If want Then
        target = fl(fi).up: wmax = 2752512: acc = 9000
    Else
        target = fl(fi).rest: wmax = 1703936: acc = 5000
    End If
    sgn = FSign(target - fl(fi).ang)
    If sgn = 0 Then
        fl(fi).w = 0
    Else
        fl(fi).w = fl(fi).w + sgn * acc * h
        If FAbs(fl(fi).w) > wmax Then fl(fi).w = sgn * wmax
        If FSign(fl(fi).w) <> sgn Then
            m = acc * h
            If FAbs(fl(fi).w) < m Then fl(fi).w = sgn * FAbs(fl(fi).w) Else fl(fi).w = sgn * m
        End If
    End If
    fl(fi).ang = fl(fi).ang + FM(fl(fi).w, h)
    If fl(fi).ang <= lo Then
        fl(fi).ang = lo
        If fl(fi).w < 0 Then
            If FAbs(fl(fi).w) > 524288 Then Emit EV_FLIPSTOP, fl(fi).px, fl(fi).py, fl(fi).side, -(fl(fi).ang = fl(fi).up), 0, 0
            fl(fi).w = 0
        End If
    End If
    If fl(fi).ang >= hi Then
        fl(fi).ang = hi
        If fl(fi).w > 0 Then
            If FAbs(fl(fi).w) > 524288 Then Emit EV_FLIPSTOP, fl(fi).px, fl(fi).py, fl(fi).side, -(fl(fi).ang = fl(fi).up), 0, 0
            fl(fi).w = 0
        End If
    End If
End Sub

Private Function FlipperMoving(ByVal fi As Long) As Boolean
    Dim target As Long
    If fl(fi).held <> 0 And wPower <> 0 Then target = fl(fi).up Else target = fl(fi).rest
    FlipperMoving = fl(fi).w <> 0 Or fl(fi).ang <> target
End Function

Private Sub MoveBall(ByVal bi As Long, ByVal dt As Long)
    Dim x0 As Long, y0 As Long, sp As Long, s As Long, gx As Long, gy As Long, k As Long, i As Long
    Dim bx As Long, by As Long, n As Long, base As Long, ref As Long, typ As Long, idx As Long, hitv As Long
    Dim nx As Long, ny As Long, c As Long, add As Long, reach As Long, outv As Long
    x0 = bl(bi).x
    y0 = bl(bi).y
    bl(bi).vy = bl(bi).vy - PB_GRAVITY * dt
    sp = Hyp(bl(bi).vx, bl(bi).vy)
    If sp > PB_MAX_SPEED Then
        s = FD(PB_MAX_SPEED, sp)
        bl(bi).vx = FM(bl(bi).vx, s)
        bl(bi).vy = FM(bl(bi).vy, s)
    End If
    bl(bi).x = bl(bi).x + FM(bl(bi).vx, dt)
    bl(bi).y = bl(bi).y + FM(bl(bi).vy, dt)

    bx = FI(bl(bi).x)
    by = FI(bl(bi).y)
    gx = bx \ 64
    gy = (by + 64) \ 64
    If gx < 0 Then gx = 0
    If gx >= PB_GX Then gx = PB_GX - 1
    If gy < 0 Then gy = 0
    If gy >= PB_GY Then gy = PB_GY - 1
    base = (gy * PB_GX + gx) * PB_GMAX
    n = ngrid(gy * PB_GX + gx)
    For k = 0 To n - 1
        ref = grid(base + k)
        If ref < 4096 Then                                  ' a wall, gate, sling or drop target
            idx = ref
            If bx >= sg(idx).bb0 And bx <= sg(idx).bb2 And by >= sg(idx).bb1 And by <= sg(idx).bb3 Then
                If sg(idx).kind <> SK_DROP Or sg(idx).up <> 0 Then
                    wTests = wTests + 1
                    hitv = HitSegment(bi, idx)
                    If hitv > 0 Then
                        If sg(idx).kind = SK_DROP Then
                            If hitv > 5898240 Then
                                sg(idx).up = 0
                                Emit EV_DROP, bl(bi).x, bl(bi).y, sg(idx).id, 0, FI(hitv), bl(bi).id
                            End If
                        ElseIf sg(idx).kind = SK_SLING Then
                            If hitv > 9175040 And wActive <> 0 Then
                                nx = -sg(idx).uy
                                ny = sg(idx).ux
                                If FM(bl(bi).x - sg(idx).ax, nx) + FM(bl(bi).y - sg(idx).ay, ny) < 0 Then nx = -nx: ny = -ny
                                bl(bi).vx = bl(bi).vx + 950 * nx
                                bl(bi).vy = bl(bi).vy + 950 * ny
                                Emit EV_SLING, bl(bi).x, bl(bi).y, sg(idx).id, 0, 0, bl(bi).id
                            End If
                        ElseIf hitv > 16384000 Then
                            Emit EV_WALL, bl(bi).x, bl(bi).y, 0, 0, FI(hitv), bl(bi).id
                        End If
                    End If
                End If
            End If
        ElseIf ref < 8192 Then                              ' a post or a pop bumper
            idx = ref - 4096
            wTests = wTests + 1
            hitv = HitCircle(bi, idx)
            If hitv >= 0 Then
                If cc(idx).bumper Then
                    If wActive Then
                        outv = FM(bl(bi).vx, hcNx) + FM(bl(bi).vy, hcNy)
                        If outv < 68812800 Then
                            add = 68812800 - outv
                            bl(bi).vx = bl(bi).vx + FM(hcNx, add)
                            bl(bi).vy = bl(bi).vy + FM(hcNy, add)
                        End If
                        Emit EV_BUMPER, cc(idx).cx, cc(idx).cy, cc(idx).id, 0, 0, bl(bi).id
                    End If
                ElseIf hitv > 16384000 Then
                    Emit EV_WALL, bl(bi).x, bl(bi).y, 0, 0, FI(hitv), bl(bi).id
                End If
            End If
        Else                                                ' a sensor
            idx = ref - 8192
            If bx >= sn(idx).bb0 And bx <= sn(idx).bb2 And by >= sn(idx).bb1 And by <= sn(idx).bb3 Then
                c = Crossed(x0, y0, bl(bi).x, bl(bi).y, idx)
                If c <> 0 Then
                    If sn(idx).kind = SN_SPIN Then
                        add = FAbs(bl(bi).vy) \ 28
                        If add < 4587520 Then spW(sn(idx).idx) = spW(sn(idx).idx) + add Else spW(sn(idx).idx) = spW(sn(idx).idx) + 4587520
                        Emit EV_SPINHIT, bl(bi).x, bl(bi).y, sn(idx).idx, -(bl(bi).vy > 0), 0, bl(bi).id
                    ElseIf sn(idx).kind = SN_RAMPIN Then
                        If bl(bi).vy > 0 Then
                            bl(bi).st = BS_RAMP
                            bl(bi).ramp = sn(idx).idx
                            bl(bi).rs = 0
                            bl(bi).rv = FM(Hyp(bl(bi).vx, bl(bi).vy), 60293)
                            Emit EV_RAMPENTER, bl(bi).x, bl(bi).y, sn(idx).idx, 1, 0, bl(bi).id
                            Exit Sub
                        End If
                    ElseIf wNev < PB_MAX_EV Then
                        Emit EV_SENSOR, bl(bi).x, bl(bi).y, sn(idx).idx, -(bl(bi).vy > 0), 0, bl(bi).id
                        wev(wNev - 1).kind = sn(idx).kind
                    End If
                End If
            End If
        End If
    Next k
    ' the flippers
    For i = 0 To tNflip - 1
        reach = fl(i).ln + fl(i).r1 + PB_R
        If FAbs(bl(bi).x - fl(i).px) <= reach And FAbs(bl(bi).y - fl(i).py) <= reach Then
            wTests = wTests + 1
            hitv = HitFlipper(bi, i)
            If hitv > 19660800 Then Emit EV_FLIPHIT, bl(bi).x, bl(bi).y, fl(i).side, 0, FI(hitv), bl(bi).id
        End If
    Next i
    ' the saucer catches a ball that isn't moving too fast
    If bl(bi).nocatch > 0 Then
        bl(bi).nocatch = bl(bi).nocatch - dt
    ElseIf FAbs(bl(bi).x - saucerX) < saucerR And FAbs(bl(bi).y - saucerY) < saucerR Then
        If Hyp(bl(bi).x - saucerX, bl(bi).y - saucerY) < saucerR And Hyp(bl(bi).vx, bl(bi).vy) < 85196800 Then
            bl(bi).st = BS_SAUCER
            bl(bi).x = saucerX: bl(bi).y = saucerY: bl(bi).vx = 0: bl(bi).vy = 0
            bl(bi).hold = 144
            Emit EV_SAUCER, bl(bi).x, bl(bi).y, 0, 0, 0, bl(bi).id
            Exit Sub
        End If
    End If
    ' resting on the plunger
    If bl(bi).x > 31326208 And bl(bi).y < plungerRest + 262144 Then
        If Hyp(bl(bi).vx, bl(bi).vy) < 5242880 Then
            bl(bi).st = BS_LANE
            bl(bi).x = plungerX: bl(bi).y = plungerRest: bl(bi).vx = 0: bl(bi).vy = 0
            Emit EV_LANEREST, bl(bi).x, bl(bi).y, 0, 0, 0, bl(bi).id
        End If
    End If
    If bl(bi).y < -2621440 Then
        bl(bi).st = BS_DRAINED
        Emit EV_DRAIN, bl(bi).x, bl(bi).y, 0, 0, 0, bl(bi).id
    End If
End Sub

' a ball on a ramp: one-dimensional motion along the rail, pulled by the slope
Private Sub RampStep(ByVal bi As Long, ByVal h As Long)
    Dim ri As Long, L As Long, v As Long, slope As Long
    ri = bl(bi).ramp
    L = rprof(ri * 16 + rampN(ri) - 1)
    RampAt ri, bl(bi).rs
    slope = raSlope
    bl(bi).rv = bl(bi).rv + FM(-3200 * slope - 7864320 * FSign(bl(bi).rv), h)
    bl(bi).rs = bl(bi).rs + FM(bl(bi).rv, h)
    RampAt ri, bl(bi).rs
    bl(bi).x = raX: bl(bi).y = raY: bl(bi).z = raZ
    bl(bi).vx = FM(raDx, bl(bi).rv)
    bl(bi).vy = FM(raDy, bl(bi).rv)
    If bl(bi).rs <= 0 And bl(bi).rv <= 0 Then          ' didn't make it: rolls back out of the entrance
        bl(bi).st = BS_PLAY: bl(bi).z = 0
        bl(bi).x = rpx(ri * 16) * 65536
        bl(bi).y = (rpy(ri * 16) - 4) * 65536
        bl(bi).vx = 0
        If bl(bi).rv < -7864320 Then bl(bi).vy = bl(bi).rv Else bl(bi).vy = -7864320
        Emit EV_RAMPFAIL, bl(bi).x, bl(bi).y, bl(bi).ramp, 0, 0, bl(bi).id
    ElseIf bl(bi).rs >= L Then
        v = -FM(FAbs(bl(bi).rv), 32768)
        bl(bi).st = BS_PLAY: bl(bi).z = 0
        bl(bi).x = rExitX(ri): bl(bi).y = rExitY(ri)
        bl(bi).vx = 0
        If rExitVy(ri) < v Then bl(bi).vy = rExitVy(ri) Else bl(bi).vy = v
        Emit EV_RAMP, bl(bi).x, bl(bi).y, bl(bi).ramp, 0, 0, bl(bi).id
    End If
End Sub

' one fixed step (h, normally PB_STEP), split into substeps
Public Sub WorldStep(ByVal h As Long)
    Dim fast As Long, tip As Long, dist As Long, n As Long, k As Long, i As Long, j As Long
    Dim done As Long, live As Long, roll As Long, s As Long, tp As Long, upto As Long, dt As Long
    roll = FONE_ - FM(2621, h)
    For i = 0 To wNballs - 1
        If bl(i).st = BS_PLAY Then
            live = live + 1
            bl(i).vx = FM(bl(i).vx, roll)
            bl(i).vy = FM(bl(i).vy, roll)
            s = Hyp(bl(i).vx, bl(i).vy) + PB_GRAVITY * h
            If s > fast Then fast = s
        End If
    Next i
    For i = 0 To tNflip - 1
        If FlipperMoving(i) Then
            tp = 42 * (fl(i).ln + fl(i).r2)
            If tp > tip Then tip = tp
        End If
    Next i
    dist = FM(fast + tip, h)
    If live Then n = (dist + PB_R \ 4 - 1) \ (PB_R \ 4) Else n = 1
    If n < 1 Then n = 1
    If n > 160 Then n = 160
    wSubsteps = n
    For k = 0 To n - 1
        upto = (h * (k + 1)) \ n
        dt = upto - done
        done = upto
        For i = 0 To tNflip - 1
            FlipperStep i, dt
        Next i
        For i = 0 To wNballs - 1
            If bl(i).st = BS_PLAY Then MoveBall i, dt
        Next i
        For i = 0 To wNballs - 2
            For j = i + 1 To wNballs - 1
                If bl(i).st = BS_PLAY And bl(j).st = BS_PLAY Then HitBalls i, j
            Next j
        Next i
    Next k
    For i = 0 To wNballs - 1
        Select Case bl(i).st
            Case BS_RAMP: RampStep i, h
            Case BS_SAUCER: bl(i).hold = bl(i).hold - 1: bl(i).vx = 0: bl(i).vy = 0
            Case BS_LANE: bl(i).vx = 0: bl(i).vy = 0
        End Select
    Next i
    ' the spinners keep turning on their own and slow down
    For i = 0 To tNspin - 1
        If spW(i) > 0 Then
            spW(i) = spW(i) - FM(327680 + FM(spW(i), 58982), h)
            If spW(i) < 0 Then spW(i) = 0
            spAng(i) = spAng(i) + FM(spW(i), h)
            Do While spAng(i) >= FPI
                spAng(i) = spAng(i) - FPI
                Emit EV_SPIN, spX(i), spY(i), i, 0, 0, 0
            Loop
        End If
    Next i
End Sub

Public Sub KickSaucer(ByVal bi As Long, ByVal jitter As Long)
    Dim rgt As Boolean
    rgt = saucerX > PB_MID * 65536
    bl(bi).st = BS_PLAY
    If rgt Then bl(bi).x = saucerX - 262144 Else bl(bi).x = saucerX + 262144
    bl(bi).y = saucerY - 262144
    bl(bi).vx = 34078720 + jitter
    bl(bi).vy = -53739520
    If rgt Then bl(bi).vx = -bl(bi).vx
    bl(bi).nocatch = 32768
    Emit EV_KICK, bl(bi).x, bl(bi).y, 0, 0, 0, bl(bi).id
End Sub

Public Sub Plunge(ByVal bi As Long, ByVal pull As Long)
    pull = FClamp(pull, 0, FONE_)
    bl(bi).st = BS_PLAY
    bl(bi).vx = 0
    bl(bi).vy = 45875200 + 4300 * pull
    bl(bi).y = plungerRest + FONE_
    Emit EV_PLUNGE, bl(bi).x, bl(bi).y, 0, 0, (pull * 1000) \ 65536, bl(bi).id
End Sub

Public Sub WorldNudge(ByVal dx As Long, ByVal dy As Long)
    Dim i As Long
    For i = 0 To wNballs - 1
        If bl(i).st = BS_PLAY Then bl(i).vx = bl(i).vx + dx: bl(i).vy = bl(i).vy + dy
    Next i
End Sub

' ================================================================ the rules

Private Sub GEvent(ByVal etype As Long, ByVal x As Long, ByVal y As Long, ByVal id As Long, ByVal v As Long)
    If gNev >= PB_MAX_EV Then Exit Sub
    gev(gNev).etype = etype: gev(gNev).x = x: gev(gNev).y = y: gev(gNev).id = id: gev(gNev).val = v
    gev(gNev).kind = 0: gev(gNev).up = 0: gev(gNev).ball = 0
    gNev = gNev + 1
End Sub

' 1234560 -> "1,234,560"
Public Function PbFmt(ByVal n As Long) As String
    Dim s As String, r As String, i As Long, l As Long
    s = CStr(Abs(CDbl(n)))
    l = Len(s)
    For i = 1 To l
        r = r & Mid$(s, i, 1)
        If (l - i) Mod 3 = 0 And i < l Then r = r & ","
    Next i
    If n < 0 Then r = "-" & r
    PbFmt = r
End Function

Public Sub PbSay(ByVal big As String, ByVal small As String, ByVal steps As Long)
    Dim i As Long
    If gNmsg >= PB_MAX_MSG Then
        For i = 0 To PB_MAX_MSG - 2
            msgUntil(i) = msgUntil(i + 1): msgAt(i) = msgAt(i + 1)
            msgBig(i) = msgBig(i + 1): msgSmall(i) = msgSmall(i + 1)
        Next i
        gNmsg = gNmsg - 1
    End If
    msgBig(gNmsg) = Left$(big, 23)
    msgSmall(gNmsg) = Left$(small, 35)
    msgUntil(gNmsg) = gTime + steps
    msgAt(gNmsg) = gTime
    gNmsg = gNmsg + 1
End Sub

Public Sub PbAward(ByVal pts As Long, ByVal x As Long, ByVal y As Long)
    Dim p As Long
    If gSupernova > gTime Then p = pts * 3 Else p = pts
    gScore = gScore + p
    If x <> NOXY Then GEvent EV_SCORE, x, y, 0, p
End Sub

Private Sub AddTimer(ByVal steps As Long, ByVal kind As Long, ByVal arg As Long)
    If gNtimers >= PB_MAX_TIMER Then Exit Sub
    tmAt(gNtimers) = gTime + steps
    tmKind(gNtimers) = kind
    tmArg(gNtimers) = arg
    gNtimers = gNtimers + 1
End Sub

Private Sub ResetRules()
    Dim i As Long
    gLanes(0) = 0: gLanes(1) = 0: gLanes(2) = 0
    gSkillLane = 1
    gBonusX = 1
    gBanks = 0: gRamps = 0: gLocks = 0
    gMissionsDone = 0
    gMission = -1: gMissionLit = 1
    gMultiball = 0: gJackpot = 0
    gSupernova = 0: gJackpotLit = 0
    gBonusRamps = 0: gBonusTargets = 0: gBonusLanes = 0: gBonusSpins = 0
    gTiltMeter = 0: gTiltWarnings = 0: gTilted = 0
    gSaveUntil = 0: gSkillArmed = 0: gPlungeAt = -1
    gPull = 0: gPullHeld = 0
    gNtimers = 0
    For i = 0 To tNseg - 1
        If sg(i).kind = SK_DROP Then sg(i).up = 1
    Next i
End Sub

Public Sub GameInit(ByVal seed As Long)
    gScore = 0: gTime = 0: gBallNo = 0: gExtraBalls = 0: gMissionN = 0: gMissionUntil = 0
    gBonusPts = 0: gBonusT = 0: gNmsg = 0: gNev = 0
    WorldInit
    gState = GS_ATTRACT
    gBallsPerGame = 3
    If seed <> 0 Then gRng = seed Else gRng = 1
    ResetRules
End Sub

' a new ball (or a multiball / saved ball) in the plunger lane; its index or -1
Private Function Serve(ByVal autol As Long) As Long
    Dim b As Long
    If autol = 0 Then
        gBallNo = gBallNo + 1
        gTiltMeter = 0: gTiltWarnings = 0: gTilted = 0
        wPower = 1: wActive = 1
        gSkillLane = (gSkillLane + 1) Mod 3
        gSkillArmed = 1
        gBonusRamps = 0: gBonusTargets = 0: gBonusLanes = 0: gBonusSpins = 0
        gBonusX = 1
    End If
    b = AddBall(plungerX, plungerRest, 0, 0, BS_LANE)
    If b >= 0 And autol <> 0 Then bl(b).autol = 72
    Serve = b
End Function

Public Sub GameStart()
    gScore = 0: gBallNo = 0: gState = GS_PLAY: gTime = 0
    wNballs = 0
    gNmsg = 0: gNev = 0
    ResetRules
    Serve 0
    PbSay tName, "BALL 1", 300
End Sub

Public Function LiveBalls() As Long
    Dim i As Long, n As Long
    For i = 0 To wNballs - 1
        If bl(i).st <> BS_DRAINED Then n = n + 1
    Next i
    LiveBalls = n
End Function

Private Sub FirePlunger(ByVal bi As Long, ByVal pull As Long, ByVal autol As Long)
    Plunge bi, pull
    If autol = 0 Then
        If gPlungeAt < 0 Or gSaveUntil < gTime Then gSaveUntil = gTime + SAVE_TIME
        gPlungeAt = gTime
    End If
End Sub

Private Sub LaneChange(ByVal dir As Long)
    Dim a As Long, b As Long, c As Long
    a = gLanes(0): b = gLanes(1): c = gLanes(2)
    If (a <> 0 Or b <> 0 Or c <> 0) And Not (a <> 0 And b <> 0 And c <> 0) Then
        If dir < 0 Then
            gLanes(0) = b: gLanes(1) = c: gLanes(2) = a
        Else
            gLanes(0) = c: gLanes(1) = a: gLanes(2) = b
        End If
    End If
    If gSkillArmed Then
        If dir < 0 Then gSkillLane = (gSkillLane + 2) Mod 3 Else gSkillLane = (gSkillLane + 1) Mod 3
    End If
End Sub

Public Sub DoTilt()
    Dim i As Long
    gTilted = 1
    wPower = 0: wActive = 0
    For i = 0 To tNflip - 1
        fl(i).held = 0
    Next i
    gSaveUntil = 0
    gMission = -1
    PbSay "TILT", "NO BONUS", 11880
    GEvent EV_TILT, 0, 0, 0, 0
End Sub

Private Sub DoNudge(ByVal nx As Long, ByVal ny As Long)
    Dim mag As Long
    mag = FHypot(nx * 65536, ny * 65536)
    If mag <= 0 Then Exit Sub
    WorldNudge FD(nx * 240 * 65536, mag), FD(ny * 240 * 65536, mag) + 2621440
    GEvent EV_NUDGE, nx, ny, 0, 0
    gTiltMeter = gTiltMeter + FONE_
    If gTiltMeter > 111411 Then
        gTiltMeter = 19660
        gTiltWarnings = gTiltWarnings + 1
        If gTiltWarnings >= 3 Then
            DoTilt
        Else
            If gTiltWarnings = 1 Then PbSay "DANGER", "WARNING 1 OF 2", 192 Else PbSay "DANGER", "LAST WARNING", 192
            GEvent EV_TILTWARN, 0, 0, 0, gTiltWarnings
        End If
    End If
End Sub

Private Sub StartMultiball(ByVal extra As Long)
    Dim i As Long
    gMultiball = 1: gJackpot = 0
    For i = 0 To extra - 1
        AddTimer 48 + i * 132, TM_SERVE, 0
    Next i
    gSaveUntil = gTime + 1440
    PbSay "MULTIBALL", "RAMP FOR JACKPOT", 312
    GEvent EV_MULTIBALL, 0, 0, 0, 0
End Sub

Private Sub MissionHit(ByVal ev As Long)
    If gMission < 0 Then Exit Sub
    If gMission <> ev Then Exit Sub                 ' (each mission's event is its own index)
    gMissionN = gMissionN + 1
    If gMissionN >= missionNeed(gMission) Then
        PbAward missionAward(gMission), NOXY, 0
        gMissionsDone = gMissionsDone Or (2 ^ gMission)
        PbSay "MISSION DONE", PbFmt(missionAward(gMission)), 288
        GEvent EV_MISSIONDONE, 0, 0, gMission, 0
        gMission = -1
        gMissionLit = 1
    End If
End Sub

Private Sub SensorEv()
    Dim i As Long
    If cev.kind = SN_LANE Then
        i = cev.id
        If cev.up Then Exit Sub                     ' lanes count on the way down
        If gSkillArmed <> 0 And gTime - gPlungeAt < 720 Then
            gSkillArmed = 0
            If i = gSkillLane Then
                PbAward 10000, cev.x, cev.y
                PbSay "SKILL SHOT", "10,000", 240
                GEvent EV_SKILL, 0, 0, 0, 0
            End If
        Else
            gSkillArmed = 0
        End If
        PbAward 500, cev.x, cev.y
        gBonusLanes = gBonusLanes + 1
        If gLanes(i) = 0 Then
            gLanes(i) = 1
            If gLanes(0) <> 0 And gLanes(1) <> 0 And gLanes(2) <> 0 Then
                gLanes(0) = 0: gLanes(1) = 0: gLanes(2) = 0
                If gBonusX < 5 Then gBonusX = gBonusX + 1
                PbAward 2000, NOXY, 0
                If gMissionLit <> 0 Or gMission < 0 Then gMissionLit = 1 Else gMissionLit = 0
                PbSay "BONUS " & gBonusX & "X", "LANES COMPLETE", 216
                GEvent EV_LANESDONE, 0, 0, 0, 0
                MissionHit MI_LANES
            End If
        End If
        Exit Sub
    End If
    If cev.kind = SN_IN Then
        If cev.up = 0 Then PbAward 1000, cev.x, cev.y
        Exit Sub
    End If
    If cev.kind = SN_OUT Then
        If cev.up = 0 Then
            PbAward 2500, cev.x, cev.y
            GEvent EV_OUTLANE, cev.x, cev.y, 0, 0
        End If
    End If
End Sub

Private Sub DropHit()
    Dim i As Long, bank As Long, all As Long
    bank = sg(dropSeg(cev.id)).bank
    all = 1
    PbAward 750, cev.x, cev.y
    gBonusTargets = gBonusTargets + 1
    For i = 0 To tNdrop - 1
        If sg(dropSeg(i)).bank = bank And sg(dropSeg(i)).up <> 0 Then all = 0
    Next i
    If all Then
        gBanks = gBanks + 1
        PbAward 5000, NOXY, 0
        PbSay "BANK COMPLETE", "5,000", 180
        GEvent EV_BANK, 0, 0, bank, 0
        MissionHit MI_BANK
        AddTimer 144, TM_BANK_RESET, bank
    End If
End Sub

Private Sub RampMade()
    Dim pts As Long, before As Long
    gRamps = gRamps + 1: gBonusRamps = gBonusRamps + 1
    PbAward 2500, cev.x, cev.y
    MissionHit MI_RAMP
    If gMultiball Then
        pts = 50000 + 10000 * gJackpot
        gJackpot = gJackpot + 1
        before = gScore
        PbAward pts, NOXY, 0
        PbSay "JACKPOT", PbFmt(gScore - before), 264
        GEvent EV_JACKPOT, 0, 0, 0, 0
        Exit Sub
    End If
    gLocks = gLocks + 1
    If gLocks >= 3 Then
        gLocks = 0
        StartMultiball 2
    Else
        PbSay "BALL " & gLocks & " LOCKED", (3 - gLocks) & " MORE FOR MULTIBALL", 216
        GEvent EV_LOCK, 0, 0, gLocks, 0
    End If
End Sub

Private Function FindBall(ByVal id As Long) As Long
    Dim i As Long
    For i = 0 To wNballs - 1
        If bl(i).id = id Then
            FindBall = i
            Exit Function
        End If
    Next i
    FindBall = -1
End Function

Private Sub SaucerEv()
    Dim b As Long, lft(0 To 4) As Long, nl As Long, i As Long, done As Long, m As Long
    b = FindBall(cev.ball)
    PbAward 1000, cev.x, cev.y
    If gMission < 0 And gMissionLit <> 0 Then
        For i = 0 To 4
            If (gMissionsDone And (2 ^ i)) <> 0 Then
                done = done + 1
            Else
                lft(nl) = i
                nl = nl + 1
            End If
        Next i
        If nl = 0 Then                              ' every mission done: the wizard mode
            gMissionsDone = 0
            gSupernova = gTime + 3600
            PbSay "SUPERNOVA", "EVERYTHING SCORES 3X", 360
            GEvent EV_SUPERNOVA, 0, 0, 0, 0
            If gMultiball = 0 Then StartMultiball 2
            If b >= 0 Then bl(b).hold = 300
            Exit Sub
        End If
        m = lft((done + gBallNo) Mod nl)
        gMission = m: gMissionN = 0
        gMissionUntil = gTime + MISSION_TIME + 240
        gMissionLit = 0
        PbSay tMission(m), Left$(PbFmt(missionNeed(m)) & " " & missionGoal(m), 31), 288
        GEvent EV_MISSIONSTART, 0, 0, m, 0
        If b >= 0 Then bl(b).hold = 264
    End If
End Sub

Private Sub DrainEv()
    Dim lft As Long, base As Long
    RemoveDrained
    lft = LiveBalls()
    If gTilted = 0 And gTime < gSaveUntil Then
        PbSay "BALL SAVED", "", 192
        GEvent EV_SAVE, 0, 0, 0, 0
        Serve 1
        Exit Sub
    End If
    If lft Then
        If gMultiball <> 0 And lft = 1 Then
            gMultiball = 0
            PbSay "MULTIBALL OVER", "", 180
        End If
        Exit Sub
    End If
    If gNtimers <> 0 And gMultiball <> 0 Then Exit Sub
    gMultiball = 0
    gMission = -1: gMissionLit = 1
    base = gBonusRamps * 1000 + gBonusTargets * 250 + gBonusLanes * 200 + gBonusSpins * 20 + 1000
    If gTilted Then gBonusPts = 0 Else gBonusPts = base * gBonusX
    gScore = gScore + gBonusPts
    gState = GS_BONUS: gBonusT = 264
    If gTilted Then PbSay "TILT", PbFmt(gBonusPts), 264 Else PbSay "BONUS " & gBonusX & "X", PbFmt(gBonusPts), 264
    GEvent EV_ENDBALL, 0, 0, 0, 0
End Sub

Private Sub AfterBonus()
    wPower = 1: wActive = 1
    If gBallNo >= gBallsPerGame + gExtraBalls Then
        gState = GS_OVER
        PbSay "GAME OVER", PbFmt(gScore), 11880
        GEvent EV_GAMEOVER, 0, 0, 0, 0
        Exit Sub
    End If
    gState = GS_PLAY
    Serve 0
    PbSay "BALL " & (gBallNo Mod 10), PbFmt(gScore), 240
End Sub

' the rules' reaction to the world event in cev
Private Sub GameHandle()
    If gNev < PB_MAX_EV Then
        gev(gNev) = cev
        gNev = gNev + 1
    End If
    If gTilted <> 0 And cev.etype <> EV_DRAIN And cev.etype <> EV_LANEREST Then Exit Sub
    Select Case cev.etype
        Case EV_BUMPER: PbAward 100, cev.x, cev.y: MissionHit MI_BUMPER
        Case EV_SLING: PbAward 10, NOXY, 0
        Case EV_SPIN: PbAward 100, NOXY, 0: gBonusSpins = gBonusSpins + 1: MissionHit MI_SPIN
        Case EV_DROP: DropHit
        Case EV_SENSOR: SensorEv
        Case EV_RAMP: RampMade
        Case EV_SAUCER: SaucerEv
        Case EV_DRAIN: DrainEv
    End Select
End Sub

Private Sub RunTimers()
    Dim i As Long, n As Long, nd As Long, k As Long
    Dim dKind(0 To 7) As Long, dArg(0 To 7) As Long
    For i = 0 To gNtimers - 1
        If tmAt(i) <= gTime Then
            dKind(nd) = tmKind(i): dArg(nd) = tmArg(i)
            nd = nd + 1
        Else
            tmAt(n) = tmAt(i): tmKind(n) = tmKind(i): tmArg(n) = tmArg(i)
            n = n + 1
        End If
    Next i
    gNtimers = n
    For i = 0 To nd - 1
        If dKind(i) = TM_BANK_RESET Then
            For k = 0 To tNdrop - 1
                If sg(dropSeg(k)).bank = dArg(i) Then sg(dropSeg(k)).up = 1
            Next k
            GEvent EV_BANKRESET, 0, 0, dArg(i), 0
        ElseIf dKind(i) = TM_SERVE Then
            Serve 1
        End If
    Next i
End Sub

' one 1/120 s step with the input in in*
Public Sub GameTick()
    Dim i As Long, L As Long, R As Long, nev As Long, heldL As Long, heldR As Long, inLane As Long
    gTime = gTime + 1
    If gState = GS_BONUS Then
        gBonusT = gBonusT - 1
        If gBonusT <= 0 Then AfterBonus
        RunTimers
        Exit Sub
    End If
    ' the flippers (dead while tilted); pressing one also moves the lit lanes along
    If inLeft <> 0 And gTilted = 0 Then L = 1
    If inRight <> 0 And gTilted = 0 Then R = 1
    For i = 0 To tNflip - 1
        If fl(i).side = 0 Then heldL = heldL Or fl(i).held Else heldR = heldR Or fl(i).held
    Next i
    If L <> 0 And heldL = 0 Then LaneChange -1
    If R <> 0 And heldR = 0 Then LaneChange 1
    For i = 0 To tNflip - 1
        If fl(i).side = 0 Then fl(i).held = L Else fl(i).held = R
    Next i
    ' the plunger: hold to pull back (one second to full), release to fire
    inLane = -1
    For i = 0 To wNballs - 1
        If bl(i).st = BS_LANE And bl(i).autol < 0 Then inLane = i: Exit For
    Next i
    If inLane < 0 Then
        For i = 0 To wNballs - 1
            If bl(i).st = BS_LANE Then inLane = i: Exit For
        Next i
    End If
    If inPullTo >= 0 Then
        gPull = FClamp((inPullTo * 65536) \ 1000, 0, FONE_)
        gPullHeld = 1
    ElseIf inPlunger Then
        gPull = gPull + PB_STEP
        If gPull > FONE_ Then gPull = FONE_
        gPullHeld = 1
    ElseIf gPullHeld Then
        gPullHeld = 0
        If inLane >= 0 Then FirePlunger inLane, gPull, 0
        gPull = 0
    End If
    ' automatic launches, for multiball and saved balls
    For i = 0 To wNballs - 1
        If bl(i).st = BS_LANE And bl(i).autol >= 0 Then
            bl(i).autol = bl(i).autol - 1
            If bl(i).autol < 0 Then FirePlunger i, 53739 + (A3Rand(gRng) Mod 6554), 1
        End If
    Next i
    ' nudging and the tilt bob
    If (inNudgeX <> 0 Or inNudgeY <> 0) And gState = GS_PLAY And gTilted = 0 Then DoNudge inNudgeX, inNudgeY
    gTiltMeter = gTiltMeter - FM(58982, PB_STEP)
    If gTiltMeter < 0 Then gTiltMeter = 0
    WorldStep PB_STEP
    ' the saucer holds the ball, then kicks it out (with a little variation)
    For i = 0 To wNballs - 1
        If bl(i).st = BS_SAUCER And bl(i).hold <= 0 Then KickSaucer i, ((A3Rand(gRng) Mod 161) - 80) * 65536
    Next i
    nev = wNev
    wNev = 0
    For i = 0 To nev - 1
        cev = wev(i)
        GameHandle
    Next i
    ' missions time out
    If gMission >= 0 And gTime > gMissionUntil Then
        PbSay "MISSION OVER", tMission(gMission), 240
        GEvent EV_MISSIONFAIL, 0, 0, gMission, 0
        gMission = -1: gMissionLit = 1
    End If
    RunTimers
End Sub

' what the dot-matrix display shows now: dmdBig, dmdSmall, dmdFlash
Public Sub PbDmd()
    Dim m As Long, i As Long, lane As Long, lft As Long
    Do While gNmsg > 1
        If msgUntil(0) >= gTime Then Exit Do
        For i = 0 To gNmsg - 2
            msgUntil(i) = msgUntil(i + 1): msgAt(i) = msgAt(i + 1)
            msgBig(i) = msgBig(i + 1): msgSmall(i) = msgSmall(i + 1)
        Next i
        gNmsg = gNmsg - 1
    Loop
    m = -1
    For i = 0 To gNmsg - 1
        If msgUntil(i) >= gTime Then m = i
    Next i
    dmdFlash = 0
    If gState = GS_ATTRACT Then
        dmdBig = tName: dmdSmall = "PRESS FIRE"
        Exit Sub
    End If
    If m >= 0 Then
        dmdBig = msgBig(m): dmdSmall = msgSmall(m)
        If gTime - msgAt(m) < 72 Then dmdFlash = 1
        Exit Sub
    End If
    dmdBig = PbFmt(gScore)
    If gMission >= 0 Then
        lft = (gMissionUntil - gTime + PB_HZ - 1) \ PB_HZ
        If lft < 0 Then lft = 0
        i = InStr(tMission(gMission), " ")
        If i > 0 Then dmdSmall = Left$(tMission(gMission), i - 1) Else dmdSmall = tMission(gMission)
        dmdSmall = dmdSmall & " " & PbFmt(gMissionN) & "/" & PbFmt(missionNeed(gMission)) & " " & PbFmt(lft) & "S"
    ElseIf gMultiball Then
        dmdSmall = "MULTIBALL  JACKPOT " & PbFmt(50 + 10 * gJackpot) & "K"
    Else
        For i = 0 To wNballs - 1
            If bl(i).st = BS_LANE Then lane = 1
        Next i
        dmdSmall = "BALL " & (gBallNo Mod 10)
        If lane Then
            dmdSmall = dmdSmall & "  SKILL SHOT " & Chr$(65 + gSkillLane)
        ElseIf gBonusX > 1 Then
            dmdSmall = dmdSmall & "  BONUS " & gBonusX & "X"
        End If
    End If
End Sub

' which lamps are lit (lampOn); blink toggles at 2.5 Hz, chase counts up in the attract mode
Public Sub PbLamps(ByVal blink As Long, ByVal chase As Long)
    Dim i As Long, lane As Long, skill As Long
    For i = 0 To L_COUNT - 1
        lampOn(i) = 0
    Next i
    If gState = GS_ATTRACT Or gState = GS_OVER Then
        For i = 0 To L_COUNT - 1
            If (i + chase) Mod 5 = 0 Then lampOn(i) = 1
        Next i
        Exit Sub
    End If
    For i = 0 To wNballs - 1
        If bl(i).st = BS_LANE Then lane = 1
    Next i
    skill = -1
    If gSkillArmed <> 0 And (gTime - gPlungeAt < 720 Or lane <> 0) Then skill = gSkillLane
    For i = 0 To 2
        If gLanes(i) <> 0 Or (skill = i And blink <> 0) Then lampOn(L_LANE0 + i) = 1
    Next i
    For i = 0 To 2
        If gMultiball Then
            lampOn(L_LOCK0 + i) = blink
        ElseIf i < gLocks Or (i = gLocks And blink <> 0 And gState = GS_PLAY) Then
            lampOn(L_LOCK0 + i) = 1
        End If
    Next i
    If gMultiball <> 0 And blink <> 0 Then lampOn(L_JACKPOT) = 1
    For i = 0 To 4
        If (gMissionsDone And (2 ^ i)) <> 0 Or (gMission = i And blink <> 0) Then lampOn(L_M0 + i) = 1
    Next i
    If gMissionLit <> 0 And gMission < 0 And blink <> 0 Then lampOn(L_MISSION) = 1
    For i = 0 To 3
        If gBonusX >= i + 2 Then lampOn(L_X2 + i) = 1
    Next i
    If gTime < gSaveUntil Then lampOn(L_SAVE) = 1
    For i = 0 To tNspin - 1
        If spW(i) > 131072 Then lampOn(L_SPIN0 + i) = 1
    Next i
    For i = 0 To tNdrop - 1
        If i < 8 Then lampOn(L_DROP0 + i) = sg(dropSeg(i)).up
    Next i
    If gSupernova > gTime And blink <> 0 Then lampOn(L_SUPER) = 1
End Sub

' the attract mode's (and the tests') player: launches, holds a flipper up while a
' ball comes down towards it and lets go a moment after; sets in*
Public Sub PbBot()
    Dim i As Long, k As Long, dx As Long, dy As Long
    inLeft = 0: inRight = 0: inPlunger = 0: inNudgeX = 0: inNudgeY = 0
    inPullTo = -1
    For k = 0 To 1
        If botHold(k) > 0 Then
            botHold(k) = botHold(k) - 1
            If k Then inRight = 1 Else inLeft = 1
        End If
    Next k
    For i = 0 To wNballs - 1
        If bl(i).st = BS_LANE Then
            botLaunch = botLaunch + 1
            If botLaunch > 96 Then
                inPullTo = 800 + (A3Rand(botRng) Mod 200)
                botLaunch = 0
            End If
        ElseIf bl(i).st = BS_PLAY Then
            For k = 0 To tNflip - 1
                FlipperTip k
                dx = bl(i).x - (fl(k).px + tipX) \ 2
                dy = bl(i).y - (fl(k).py + tipY) \ 2
                ' coming down within reach: flip, with a little randomness in the timing
                If bl(i).vy < -3932160 And FAbs(dx) < (fl(k).ln * 3) \ 4 + PB_R And dy > 0 Then
                    If dy < 2621440 + FAbs(bl(i).vy) \ 20 Then
                        If (A3Rand(botRng) Mod 4) <> 0 Then botHold(fl(k).side) = 30
                    End If
                End If
            Next k
        End If
    Next i
    For k = 0 To 1
        If botHold(k) > 0 Then
            If k Then inRight = 1 Else inLeft = 1
        End If
    Next k
End Sub

Public Sub BotReset(ByVal seed As Long)
    botRng = seed: botHold(0) = 0: botHold(1) = 0: botLaunch = 0
End Sub

' ================================================================ hashes

Private Function Fv(ByVal h As Long, ByVal v As Long) As Long
    Fv = MulW(h Xor v, 16777619)
End Function

Public Function StateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    h = Fv(h, gScore): h = Fv(h, gTime): h = Fv(h, gState): h = Fv(h, gBallNo): h = Fv(h, gRng)
    For i = 0 To 2
        h = Fv(h, gLanes(i))
    Next i
    h = Fv(h, gSkillLane): h = Fv(h, gBonusX): h = Fv(h, gLocks): h = Fv(h, gMissionsDone)
    h = Fv(h, gMission): h = Fv(h, gMissionN): h = Fv(h, gMultiball): h = Fv(h, gJackpot)
    h = Fv(h, gTiltMeter): h = Fv(h, gTiltWarnings): h = Fv(h, gPull): h = Fv(h, gNtimers): h = Fv(h, gNmsg)
    h = Fv(h, wNballs)
    For i = 0 To wNballs - 1
        h = Fv(h, bl(i).id): h = Fv(h, bl(i).st): h = Fv(h, bl(i).x): h = Fv(h, bl(i).y)
        h = Fv(h, bl(i).vx): h = Fv(h, bl(i).vy): h = Fv(h, bl(i).z): h = Fv(h, bl(i).rs)
        h = Fv(h, bl(i).rv): h = Fv(h, bl(i).hold): h = Fv(h, bl(i).nocatch): h = Fv(h, bl(i).autol)
    Next i
    For i = 0 To tNflip - 1
        h = Fv(h, fl(i).ang): h = Fv(h, fl(i).w)
    Next i
    For i = 0 To tNspin - 1
        h = Fv(h, spAng(i)): h = Fv(h, spW(i))
    Next i
    For i = 0 To tNdrop - 1
        h = Fv(h, sg(dropSeg(i)).up)
    Next i
    StateHash = h
End Function

Public Function TableHash() As Long
    Dim h As Long, i As Long, k As Long, c As Long
    h = FNV_START
    For i = 0 To tNseg - 1
        h = Fv(h, sg(i).ax): h = Fv(h, sg(i).ay): h = Fv(h, sg(i).bx): h = Fv(h, sg(i).by)
        h = Fv(h, sg(i).ux): h = Fv(h, sg(i).uy): h = Fv(h, sg(i).ln): h = Fv(h, sg(i).r)
        h = Fv(h, sg(i).e): h = Fv(h, sg(i).kind): h = Fv(h, sg(i).bb0): h = Fv(h, sg(i).bb3)
    Next i
    For i = 0 To tNramp - 1
        For k = 0 To rampN(i) - 1
            h = Fv(h, rprof(i * 16 + k))
        Next k
    Next i
    For c = 0 To PB_GY * PB_GX - 1
        h = Fv(h, ngrid(c))
        For k = 0 To ngrid(c) - 1
            If k < PB_GMAX Then h = Fv(h, grid(c * PB_GMAX + k))
        Next k
    Next c
    TableHash = h
End Function
