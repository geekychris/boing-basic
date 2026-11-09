' Canyon Rail - the picture (a port of render.c) and the shell's effects (game.c): the
' sky, the canyon ahead (its floor with the river down the middle, its rock walls in
' sloping slabs with spires along the rim), the turrets, drones, fuel pods, bolts, the
' guardian and its orbiting nodes, explosions, and the HUD: the sight, the tracer, the
' shield, the multiplier and how far to the guardian. Title, help, high scores.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startStage As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public duHurtTimer As Long, duTracer As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean
Public viewAhead As Long

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5-6 banks, 7 the river, 8-11 walls
' (two tones, lit and shaded), 12 spires, 13-14 turrets, 15-16 drones, 17 pods,
' 18 bolts, 19 bolt glow, 20-21 the guardian, 22 nodes, 23 fire, 26 red, 27 yellow,
' 28 green, 29 cyan
Private Const PEN_SKY As Long = 4
Private Const PEN_BANK As Long = 5
Private Const PEN_RIVER As Long = 7
Private Const PEN_WALL As Long = 8
Private Const PEN_SPIRE As Long = 12
Private Const PEN_TURRET As Long = 13
Private Const PEN_DRONE As Long = 15
Private Const PEN_POD As Long = 17
Private Const PEN_BOLT As Long = 18
Private Const PEN_GLOW As Long = 19
Private Const PEN_BOSS As Long = 20
Private Const PEN_NODE As Long = 22
Private Const PEN_FIRE As Long = 23
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const SEG As Long = 100

Private cam As A3Cam
Private mTurret As A3Model, mDrone As A3Model, mCore As A3Model, mNode As A3Model
Private rot(0 To 8) As Long
Private Const MAX_BURSTS As Long = 12
Private bT(0 To 11) As Long, bSize(0 To 11) As Long, bPen(0 To 11) As Long
Private bX(0 To 11) As Long, bY(0 To 11) As Long, bZ(0 To 11) As Long
Private tx3(0 To 2) As Long, ty3(0 To 2) As Long
Private helpText(1 To 2, 0 To 11) As String
Private skyTop As Long, skyBottom As Long
Private segHt(0 To 120) As Long, segSpL(0 To 120) As Boolean, segSpR(0 To 120) As Boolean, segReady(0 To 120) As Long

Public Sub DrawInit()
    Dim h As Variant, i As Long
    GfxPalette Array(&H0, &HFFF, &H123, &H99A, &HE96, &H975, &H864, &H258, &HB64, &H843, &HA75, &H754, &H632, _
                     &H889, &H556, &H6CD, &H38A, &H9F4, &HF44, &HFA8, &H99B, &H667, &HF5E, &HFA3, &H0, &H0, _
                     &HF33, &HFE4, &H6F6, &H5EF, &H0, &H0)
    skyTop = Rgb12(&H58C)
    skyBottom = Rgb12(&HFCA)
    viewAhead = 1300
    MdlBegin mTurret
    MdlBox mTurret, PEN_TURRET, PEN_TURRET + 1, -14, 14, -12, 6, -14, 14
    MdlBox mTurret, PEN_TURRET + 1, PEN_TURRET + 1, -8, 8, 6, 14, -8, 8
    MdlBox mTurret, PEN_RED, PEN_RED, -3, 3, 8, 12, 8, 30
    MdlBegin mDrone
    MdlBox mDrone, PEN_DRONE, PEN_DRONE + 1, -8, 8, -5, 5, -10, 12
    MdlBox mDrone, PEN_DRONE + 1, PEN_DRONE + 1, -24, 24, -1, 2, -6, 4
    MdlBox mDrone, PEN_RED, PEN_RED, -3, 3, -3, 3, 12, 15
    MdlBegin mCore
    MdlBox mCore, PEN_BOSS, PEN_BOSS + 1, -50, 50, -50, 50, -50, 50
    MdlBox mCore, PEN_RED, PEN_RED, -18, 18, -18, 18, -56, -50
    MdlBegin mNode
    MdlPrism mNode, PEN_NODE, PEN_RED, 6, 18, -18, 18
    h = Array("THE RIDE TAKES YOU DOWN THE CANYON:", "MOVE THE SIGHT AND FIRE.", "", _
              " TURRETS  ON THE WALLS, TWO HITS", " DRONES   SWOOP ACROSS, ONE HIT", _
              " BOLTS    THEIR SHOTS: SHOOT THEM DOWN", "          OR YOUR SHIELD TAKES THEM", _
              " PODS     SHOOT THEM: +25 SHIELD", "", "HITS IN A ROW BUILD A MULTIPLIER, UP", _
              "TO x8. AT THE END: THE GUARDIAN - SHOOT", "OUT ITS FOUR NODES. THREE STAGES.", _
              "ARROWS / WASD       MOVE THE SIGHT", "SPACE               FIRE (HOLD: 5 A S)", _
              "P                   PAUSE", "B                   AUTOPILOT", "HELP / H            THESE PAGES", _
              "ESC                 TITLE / QUIT", "", "TURRET 100, DRONE 150, BOLT 25, POD 50,", _
              "NODE 500, GUARDIAN 2000 x STAGE.", "ALL x THE MULTIPLIER.", "", "A MISS OR A HIT TAKEN RESETS IT.")
    For i = 0 To 11
        helpText(1, i) = h(i)
        helpText(2, i) = h(12 + i)
    Next i
End Sub

' ---------- effects ----------
Public Sub ClearBursts()
    Dim k As Long
    For k = 0 To MAX_BURSTS - 1
        bT(k) = 0
    Next k
    duFlashTimer = 0: duHurtTimer = 0: duTracer = 0
End Sub

Private Sub AddBurst(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal size As Long, ByVal p As Long)
    Dim k As Long
    For k = 0 To MAX_BURSTS - 1
        If bT(k) <= 0 Then
            bT(k) = 10: bX(k) = x: bY(k) = y: bZ(k) = z: bSize(k) = size: bPen(k) = p
            Exit Sub
        End If
    Next k
End Sub

Private Sub Flash(ByVal s As String, ByVal p As Long)
    duFlash = s
    duFlashTimer = 30
    duFlashPen = p
End Sub

Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long, e As Long, x As Long, y As Long, z As Long
    For i = 0 To crNEv - 1
        e = crEv(i).etype
        Select Case e                ' what is seen happens in the demo too
            Case CRE_SHOT: duTracer = 2
            Case CRE_KILL, CRE_POD
                CrTargetPos crEv(i).a, x, y, z
                AddBurst x, y, z, 30, 23
            Case CRE_HIT
                If crBoss Then CrNodePos crEv(i).a, x, y, z Else CrTargetPos crEv(i).a, x, y, z
                AddBurst x, y, z, 12, 27
            Case CRE_BOLT_DOWN
                CrBoltPos crEv(i).a, x, y, z
                AddBurst x, y, z, 14, 27
            Case CRE_NODE
                CrNodePos crEv(i).a, x, y, z
                AddBurst x, y, z, 50, 23
            Case CRE_HURT
                If loud Then duHurtTimer = 6
        End Select
        If loud Then
            Select Case e
                Case CRE_SHOT: Sfx SFX_SHOT
                Case CRE_KILL, CRE_NODE: Sfx SFX_BOOM
                Case CRE_HIT: Sfx SFX_HIT
                Case CRE_BOLT_DOWN: Sfx SFX_BOLT
                Case CRE_FIRE: Sfx SFX_EFIRE
                Case CRE_HURT: Sfx SFX_HURT
                Case CRE_POD
                    Sfx SFX_POD
                    Flash "SHIELD +25", 28
                Case CRE_BOSS: Sfx SFX_BOSS
                Case CRE_BOSS_DOWN: Sfx SFX_CLEAR
                Case CRE_OVER: Sfx SFX_OVER
                Case CRE_WIN: Sfx SFX_WIN
            End Select
        End If
    Next i
    crNEv = 0
End Sub

Public Sub AgeEffects()
    Dim k As Long
    For k = 0 To MAX_BURSTS - 1
        If bT(k) > 0 Then bT(k) = bT(k) - 1
    Next k
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
    If duHurtTimer > 0 Then duHurtTimer = duHurtTimer - 1
    If duTracer > 0 Then duTracer = duTracer - 1
End Sub

' ---------- the scene ----------
' a quad of world points at the middle of its depth plus bias (the C's quad())
Private Sub Quad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                 ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, _
                 ByVal bias As Long, ByVal col As Long)
    a3QuadBias = bias
    A3QuadW cam, -1, col, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3
End Sub

' the wall's height and the spires at segment s (fixed by s: worked out once and kept)
Private Function SegH(ByVal s As Long) As Long
    Dim i As Long
    i = s \ SEG + 2
    If segReady(i) = 0 Then FillSeg s, i
    SegH = segHt(i)
End Function

Private Function SegSpire(ByVal s As Long, ByVal side As Long) As Boolean
    Dim i As Long
    i = s \ SEG + 2
    If segReady(i) = 0 Then FillSeg s, i
    If side < 0 Then SegSpire = segSpL(i) Else SegSpire = segSpR(i)
End Function

Private Sub FillSeg(ByVal s As Long, ByVal i As Long)
    segHt(i) = 250 + UModL(A3Hash(MulW(s, 7)), 90)
    segSpL(i) = (A3Hash(AddW(MulW(s, 13), -1)) And 3) = 0
    segSpR(i) = (A3Hash(AddW(MulW(s, 13), 1)) And 3) = 0
    segReady(i) = 1
End Sub

Private Sub Canyon()
    Dim s As Long, s0 As Long, s1 As Long, sb As Long, ca As Long, cb As Long, wa As Long, wb As Long
    Dim ha As Long, hb As Long, tone As Long, side As Long, xa As Long, xb As Long, ta As Long, tb As Long, p As Long, k As Long
    s0 = (crCamS \ SEG) * SEG - SEG
    s1 = crCamS + viewAhead
    s = s0
    Do While s < s1
        sb = s + SEG
        ca = CrPathX(s): cb = CrPathX(sb): wa = CrHalfWidth(s): wb = CrHalfWidth(sb)
        ha = SegH(s)
        hb = SegH(sb)
        tone = (s \ SEG) And 1
        ' the floor: the banks and the river
        Quad ca - wa, 0, s, ca - 30, 0, s, cb - 30, 0, sb, cb - wb, 0, sb, 60, PEN_BANK + tone
        Quad ca + 30, 0, s, ca + wa, 0, s, cb + wb, 0, sb, cb + 30, 0, sb, 60, PEN_BANK + tone
        Quad ca - 30, 1, s, ca + 30, 1, s, cb + 30, 1, sb, cb - 30, 1, sb, 59, PEN_RIVER
        ' the walls, sloping out as they rise, and a spire on the rim now and then
        For side = -1 To 1 Step 2
            xa = ca + side * wa: xb = cb + side * wb: ta = xa + side * 70: tb = xb + side * 70
            p = PEN_WALL + 2 * tone
            If side > 0 Then p = p + 1
            Quad xa, 0, s, xb, 0, sb, tb, hb, sb, ta, ha, s, 40, p
            If SegSpire(s, side) Then
                CamXform cam, ta, ha, s: pvx(0) = ox: pvy(0) = oy: pvz(0) = oz
                CamXform cam, tb, hb, sb: pvx(1) = ox: pvy(1) = oy: pvz(1) = oz
                CamXform cam, (ta + tb) \ 2 + side * 20, (ha + hb) \ 2 + 90, s + SEG \ 2: pvx(2) = ox: pvy(2) = oy: pvz(2) = oz
                A3Poly cam, ShrA(pvz(0) + pvz(1), 1) + 38, PEN_SPIRE, 3
            End If
        Next side
        s = s + SEG
    Loop
    a3QuadBias = 0
End Sub

Private Sub Targets()
    Dim k As Long, ahead As Long, x As Long, y As Long, z As Long
    For k = 0 To crNTg - 1
        ahead = tg(k).s - crCamS
        If tg(k).alive <> 0 And ahead >= 20 And ahead <= viewAhead Then
            CrTargetPos k, x, y, z
            If tg(k).ttype = TG_POD Then
                e3d.Spot x, y, z, 12, PEN_POD, 0
                e3d.Spot x, y, z - 1, 6, 1, -1
            Else
                RotYaw rot, A3Atan2(cam.x - x, cam.z - z)          ' facing the camera
                If tg(k).ttype = TG_TURRET Then
                    A3ModelDraw cam, mTurret, x, y, z, True, rot, 0, 0, 0, 0
                Else
                    A3ModelDraw cam, mDrone, x, y, z, True, rot, 0, 0, 0, 0
                End If
            End If
        End If
    Next k
    For k = 0 To CR_MAX_BOLTS - 1
        If bolt(k).alive Then
            CrBoltPos k, x, y, z
            e3d.Spot x, y, z, 9, PEN_GLOW, 0
            e3d.Spot x, y, z, 5, PEN_BOLT, -1
        End If
    Next k
End Sub

Private Sub Guardian()
    Dim k As Long, bs As Long, x As Long, y As Long, z As Long
    bs = CR_LEN + 450
    RotYPR rot, crBossAngle \ 3, 0, 0
    A3ModelDraw cam, mCore, CrPathX(bs), CrPathY(bs) + 90, bs, True, rot, 0, 0, 0, 0
    For k = 0 To CR_NODES - 1
        If crNodeHp(k) > 0 Then
            CrNodePos k, x, y, z
            RotYPR rot, crBossAngle, 16384, 0
            A3ModelDraw cam, mNode, x, y, z, True, rot, 0, 0, 0, -30
        End If
    Next k
End Sub

Private Sub SkyBands(ByVal hz As Long)
    Dim y As Long, f As Long, r As Long, g As Long, b As Long, h As Long
    For y = 0 To hz - 1 Step 8
        f = y
        If f > 130 Then f = 130
        r = (skyTop And 255) + ((skyBottom And 255) - (skyTop And 255)) * f \ 130
        g = ((skyTop \ 256) And 255) + (((skyBottom \ 256) And 255) - ((skyTop \ 256) And 255)) * f \ 130
        b = ((skyTop \ 65536) And 255) + (((skyBottom \ 65536) And 255) - ((skyTop \ 65536) And 255)) * f \ 130
        h = 8
        If y + h > hz Then h = hz - y
        gcv.Box 0, y, G_W, h, RGB(r, g, b)
    Next y
End Sub

Private Sub Scene()
    Dim hz As Long, k As Long, p As Long
    CrCamera
    cam.x = rcX: cam.y = rcY: cam.z = rcZ
    cam.yaw = rcYaw: cam.pitch = 300
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, G_H \ 2, CR_FOV
    CamSetup cam
    hz = CamHorizon(cam)
    If hz < 1 Then hz = 1
    If hz > G_H - 1 Then hz = G_H - 1
    SkyBands hz
    gcv.Box 0, hz, G_W, G_H - hz, pen(PEN_WALL + 1)
    A3Begin 3000
    Canyon
    If crCamS + viewAhead > CR_LEN Then Guardian
    Targets
    For k = 0 To MAX_BURSTS - 1
        If bT(k) > 0 Then
            If bT(k) > 7 Then
                p = PEN_YELLOW
            ElseIf bT(k) > 3 Then
                p = PEN_FIRE
            Else
                p = PEN_RED
            End If
            e3d.Star bX(k), bY(k), bZ(k), (bSize(k) * (4 + bT(k))) \ 14, p, 4, bT(k) * 1700, -6
        End If
    Next k
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

' ---------- the HUD ----------
Private Sub Hud()
    Dim w As Long, k As Long, m As Long, p As Long
    m = CrMult()
    If duTracer > 0 Then           ' the tracer, from the gun to the sight
        tx3(0) = G_W \ 2 - 3: tx3(1) = G_W \ 2 + 3: tx3(2) = crSX
        ty3(0) = G_H - 1: ty3(1) = G_H - 1: ty3(2) = crSY
        If crLastShotHit Then p = PEN_YELLOW Else p = 3
        gcv.Polygon tx3, ty3, 3, pen(p), True
    End If
    GRect crSX - 9, crSY, crSX - 4, crSY, PEN_GREEN
    GRect crSX + 4, crSY, crSX + 9, crSY, PEN_GREEN
    GRect crSX, crSY - 9, crSX, crSY - 4, PEN_GREEN
    GRect crSX, crSY + 4, crSX, crSY + 9, PEN_GREEN
    GTextShadow 4, 10, 1, CStr(crScore)
    If m > 1 Then GTextBig 4, 14, PEN_YELLOW, "x" & m, 2
    GTextShadow G_W - 76, 10, PEN_YELLOW, "STAGE " & crStage
    If crBoss = 0 Then               ' how far to the guardian, or its nodes
        w = (crCamS * 100) \ CR_LEN
        GBox G_W - 106, 14, G_W - 4, 19, 0, 3
        GRect G_W - 105, 15, G_W - 105 + w, 18, PEN_CYAN
    Else
        For k = 0 To CR_NODES - 1
            If crNodeHp(k) > 0 Then p = PEN_NODE Else p = 2
            GRect G_W - 50 + k * 11, 14, G_W - 42 + k * 11, 20, p
        Next k
    End If
    GTextShadow 4, G_H - 4, 3, "SHIELD"
    GBox 56, G_H - 12, 138, G_H - 4, 0, 3
    w = (crShield * 80) \ CR_SHIELD
    If crShield > 30 Then p = PEN_GREEN Else p = PEN_RED
    If w > 0 Then GRect 57, G_H - 11, 57 + w, G_H - 5, p
    If duAutoplay Then GTextShadow G_W - 40, G_H - 4, PEN_GREEN, "AUTO"
    If duHurtTimer > 0 Then
        GRect 0, 0, G_W - 1, 3, PEN_RED
        GRect 0, G_H - 4, G_W - 1, G_H - 1, PEN_RED
        GRect 0, 0, 3, G_H - 1, PEN_RED
        GRect G_W - 4, 0, G_W - 1, G_H - 1, PEN_RED
    End If
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim pct As Long, p As Long
    Scene
    Hud
    If crBetween Then
        GTextBigCentre 80, PEN_GREEN, "STAGE CLEAR", 2
        If crStage < CR_STAGES Then GTextCentre 110, 1, "STAGE " & (crStage + 1) & " NEXT"
    ElseIf crBoss <> 0 And crTicks Mod 50 < 30 And crNodeHp(0) + crNodeHp(1) + crNodeHp(2) + crNodeHp(3) = 4 * (3 + crStage) Then
        GTextCentre 60, PEN_RED, "GUARDIAN: SHOOT ITS NODES"
    End If
    If isOver Then
        If crWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 50, 80, 270, 160, 2, p
        If crWon Then GTextBigCentre 88, p, "VICTORY", 2 Else GTextBigCentre 88, p, "GAME OVER", 2
        If crShots Then pct = (crHits * 100) \ crShots
        GTextCentre 122, PEN_YELLOW, pct & "% HITS  BEST CHAIN " & crBestCombo
        GTextCentre 136, 1, "SCORE " & crScore
        If duStateTimer = 0 Then GTextCentre 152, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 180, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 44, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                                 ' the autopilot rides behind the title
    GTextBig 52, 26, 0, "CANYON", 6
    GTextBig 50, 24, PEN_YELLOW, "CANYON", 6
    GTextBig 98, 82, 0, "RAIL", 6
    GTextBig 96, 80, PEN_FIRE, "RAIL", 6
    GBox 40, 196, 280, 252, 2, 3
    GTextCentre 210, PEN_GREEN, "START AT STAGE " & startStage & " (UP/DOWN)"
    If (crTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 226, p, "PRESS SPACE TO RIDE"
    GTextCentre 242, 3, "BEST " & hsScore(0) & "   HELP: HOW TO PLAY"
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
    GTextCentre 110, 1, "PLACE " & (HsRank(crScore) + 1) & "   " & Format$(crScore, "0000000")
    If (crTicks And 8) = 0 Then cur = "_" Else cur = " "
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
    gcv.Box 0, 22, G_W, 11, pen(0)
    GText 2, 31, PEN_GREEN, PerfText()
End Sub
