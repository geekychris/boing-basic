' Tank Duel - the picture (a port of render.c) and the shell's effects (game.c):
' from the turret, the sky and the arena's floor with its grid, the walls, cover
' (pillars, pyramids, crates), the enemy tanks as models, shells, mortar rounds on
' their arcs with the red rings where they land, explosions, and the HUD (the gun,
' the sight, armour and gun bars, a radar turned with the tank). Also the title,
' help pages, high scores and the timing overlay.
Option Explicit

' the shell's state (C's Duel)
Public duState As Long, duStateTimer As Long
Public startRound As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public duHurtTimer As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean

Private Const MAX_BLASTS As Long = 12
Private bT(0 To 11) As Long, bSize(0 To 11) As Long, bPen(0 To 11) As Long
Private bX(0 To 11) As Long, bY(0 To 11) As Long, bZ(0 To 11) As Long

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5 floor, 6 grid, 7-8 walls,
' 9-10 pillars, 11-12 pyramids, 13-14 crates, 15 a cracked crate, 16-21 scouts,
' mortars, bulwarks (lit, shaded), 22 the shield, 23 your shells, 24 theirs,
' 25 the mortar ring, 26 red, 27 yellow, 28 green, 29 cyan, 30 fire, 31 radar
Private Const PEN_SKY As Long = 4
Private Const PEN_FLOOR As Long = 5
Private Const PEN_GRID As Long = 6
Private Const PEN_WALL As Long = 7
Private Const PEN_SHIELD As Long = 22
Private Const PEN_SHELL As Long = 23
Private Const PEN_ESHELL As Long = 24
Private Const PEN_RING As Long = 25
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const PEN_FIRE As Long = 30
Private Const PEN_RADAR As Long = 31
Private Const EYE_Y As Long = 34

Private cam As A3Cam, tc As A3Cam
Private mPillar As A3Model, mPyramid As A3Model, mCrate As A3Model
Private mTank(0 To 3) As A3Model
Private rot(0 To 8) As Long
Private skyTop As Long, skyBottom As Long
Private gunX(0 To 3) As Long, gunY(0 To 3) As Long
Private helpText(1 To 2, 0 To 11) As String

Public Sub DrawInit()
    Dim h As Variant, i As Long
    GfxPalette Array(&H0, &HFFF, &H122, &H99A, &H58A, &H353, &H575, &H887, &H554, &HAAB, &H667, &HCA6, &H864, _
                     &HB83, &H751, &H642, &H6D4, &H372, &HE92, &H952, &H98B, &H546, &H6EF, &HFF6, &HF73, &HE22, _
                     &HF33, &HFE4, &H6F6, &H5EF, &HFA3, &H21)
    skyTop = Rgb12(&H369)
    skyBottom = Rgb12(&HBCD)
    a3ModelMargin = 200                 ' the biggest model (a pyramid) is 70 across
    MdlBegin mPillar
    MdlPrism mPillar, 9, 10, 8, 26, 0, 130
    MdlBegin mPyramid
    MdlPyramid mPyramid, 11, 12, -50, 50, 0, -50, 50, 110
    MdlBegin mCrate
    MdlBox mCrate, COL_BODY, COL_BODY + 1, -34, 34, 0, 56, -34, 34
    ' the scout: a low hull, a little turret and a long barrel
    MdlBegin mTank(TK_SCOUT)
    MdlBox mTank(TK_SCOUT), 16, 17, -18, 18, 2, 16, -26, 24
    MdlBox mTank(TK_SCOUT), 17, 17, -22, 22, 0, 8, -24, 22
    MdlBox mTank(TK_SCOUT), 16, 17, -9, 9, 16, 26, -10, 8
    MdlBox mTank(TK_SCOUT), 3, 3, -2, 2, 19, 23, 8, 40
    ' the mortar: a box with a short tube pointing up
    MdlBegin mTank(TK_MORTAR)
    MdlBox mTank(TK_MORTAR), 18, 19, -22, 22, 0, 22, -26, 26
    MdlBox mTank(TK_MORTAR), 19, 19, -12, 12, 22, 30, -14, 10
    MdlBox mTank(TK_MORTAR), 3, 2, -6, 6, 30, 58, -8, 4
    ' the bulwark: a heavy hull and the shield across its front
    MdlBegin mTank(TK_BULWARK)
    MdlBox mTank(TK_BULWARK), 20, 21, -26, 26, 0, 26, -28, 22
    MdlBox mTank(TK_BULWARK), 20, 21, -13, 13, 26, 38, -14, 10
    MdlBox mTank(TK_BULWARK), 3, 3, -3, 3, 30, 34, 10, 38
    MdlBox mTank(TK_BULWARK), PEN_SHIELD, 29, -32, 32, 2, 40, 26, 32
    h = Array("DESTROY EVERY ENEMY TANK IN THE ARENA.", "SHELLS BOUNCE ONCE OFF THE WALLS: BANK", _
              "A SHOT ROUND COVER. CRATES BREAK.", "", " SCOUT    QUICK, CIRCLES AND SNIPES", _
              " MORTAR   LOBS SHELLS AT WHERE YOU ARE", "          - GET OUT OF THE RED RING", _
              " BULWARK  SHIELDED IN FRONT: SHOTS", "          GLANCE OFF. IT TURNS SLOWLY,", _
              "          SO GET ROUND TO ITS SIDE.", "", "8 ROUNDS. +30 ARMOUR BETWEEN THEM.", _
              "UP / DOWN        FORWARD / BACK", "LEFT / RIGHT     TURN", "SPACE            FIRE", _
              "P                PAUSE", "B                AUTOPILOT", "HELP / H         THESE PAGES", _
              "ESC              TITLE / QUIT", "", "SCOUT 100, MORTAR 200, BULWARK 300,", _
              "CRATE 20. ROUND 500 x ROUND, AND 5", "FOR EACH POINT OF ARMOUR LEFT.", "THE RADAR: AHEAD IS UP.")
    For i = 0 To 11
        helpText(1, i) = h(i)
        helpText(2, i) = h(12 + i)
    Next i
End Sub

' ---------- effects ----------
Public Sub ClearBlasts()
    Dim k As Long
    For k = 0 To MAX_BLASTS - 1
        bT(k) = 0
    Next k
    duFlashTimer = 0
    duHurtTimer = 0
End Sub

Private Sub Blast(ByVal x As Long, ByVal z As Long, ByVal y As Long, ByVal size As Long, ByVal p As Long)
    Dim k As Long
    For k = 0 To MAX_BLASTS - 1
        If bT(k) <= 0 Then
            bT(k) = 10
            bX(k) = ShrA(x, 16)
            bZ(k) = ShrA(z, 16)
            bY(k) = y
            bSize(k) = size
            bPen(k) = p
            Exit Sub
        End If
    Next k
End Sub

Private Sub Flash(ByVal s As String, ByVal p As Long)
    duFlash = s
    duFlashTimer = 30
    duFlashPen = p
End Sub

' the tick's events: explosions (in the title's fight too), sound and messages
Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long, e As Long, a As Long, b As Long
    For i = 0 To tdNEv - 1
        e = tdEv(i).etype
        a = tdEv(i).a
        b = tdEv(i).b
        Select Case e
            Case TDE_KILL: Blast tdEv(i).x, tdEv(i).z, 20, 26, 30
            Case TDE_HIT, TDE_GLANCE, TDE_CRATE_HIT: Blast tdEv(i).x, tdEv(i).z, 20, 8, 27
            Case TDE_CRATE_BREAK: Blast tdEv(i).x, tdEv(i).z, 26, 22, 14
            Case TDE_SPLASH
                If a = 2 Then Blast tdEv(i).x, tdEv(i).z, 10, 30, 30 Else Blast tdEv(i).x, tdEv(i).z, 20, 8, 30
            Case TDE_HURT
                If loud Then duHurtTimer = 6
        End Select
        If loud Then
            Select Case e
                Case TDE_FIRE: Sfx SFX_FIRE
                Case TDE_EFIRE: Sfx SFX_EFIRE
                Case TDE_LOB
                    Sfx SFX_LOB
                    Flash "INCOMING MORTAR", 26
                Case TDE_KILL
                    Sfx SFX_BOOM
                    Flash Choose(b, "SCOUT DOWN", "MORTAR DOWN", "BULWARK DOWN"), 28
                Case TDE_HIT: Sfx SFX_HIT
                Case TDE_GLANCE
                    Sfx SFX_GLANCE
                    Flash "GLANCED OFF THE SHIELD", 29
                Case TDE_BOUNCE: Sfx SFX_BOUNCE
                Case TDE_HURT: Sfx SFX_HURT
                Case TDE_SPLASH
                    If a = 2 Then Sfx SFX_BOOM
                Case TDE_CRATE_HIT, TDE_CRATE_BREAK: Sfx SFX_CRATE
                Case TDE_ROUND_CLEAR: Sfx SFX_CLEAR
                Case TDE_DEAD: Sfx SFX_OVER
                Case TDE_WIN: Sfx SFX_WIN
            End Select
        End If
    Next i
    tdNEv = 0
End Sub

Public Sub AgeEffects()
    Dim k As Long
    For k = 0 To MAX_BLASTS - 1
        If bT(k) > 0 Then bT(k) = bT(k) - 1
    Next k
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
    If duHurtTimer > 0 Then duHurtTimer = duHurtTimer - 1
End Sub

' ---------- the scene ----------
' a square facing the camera, half size r, at world (x, y, z)
Private Sub Spot(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal r As Long, ByVal col As Long, ByVal bias As Long)
    Dim cxx As Long, cyy As Long, czz As Long
    CamXform cam, x, y, z
    r = r * 16
    If oz < 192 + r Then Exit Sub
    cxx = ox: cyy = oy: czz = oz
    pvx(0) = cxx - r: pvy(0) = cyy - r: pvz(0) = czz
    pvx(1) = cxx + r: pvy(1) = cyy - r: pvz(1) = czz
    pvx(2) = cxx + r: pvy(2) = cyy + r: pvz(2) = czz
    pvx(3) = cxx - r: pvy(3) = cyy + r: pvz(3) = czz
    A3Poly cam, czz + bias * 16, col, 4
End Sub

' an explosion: a ragged star facing the camera, turning as it fades
Private Sub Burst(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal r As Long, ByVal col As Long, ByVal t As Long)
    Dim k As Long, a As Long, rr As Long, cxx As Long, cyy As Long, czz As Long
    CamXform cam, x, y, z
    r = r * 16
    If oz < 192 + r Then Exit Sub
    cxx = ox: cyy = oy: czz = oz
    For k = 0 To 7
        a = k * 8192 + t * 1500
        If k And 1 Then rr = r \ 2 Else rr = r
        pvx(k) = cxx + Int(CDbl(A3Sin(a)) * rr / 65536#)
        pvy(k) = cyy + Int(CDbl(A3Cos(a)) * rr / 65536#)
        pvz(k) = czz
    Next k
    A3Poly cam, czz - 128, col, 8
End Sub

Private Sub RingAt(ByVal x As Long, ByVal z As Long, ByVal r As Long, ByVal col As Long)
    Dim k As Long, a0 As Long, a1 As Long, s0 As Long, c0 As Long, s1 As Long, c1 As Long
    For k = 0 To 11
        a0 = k * 5461
        a1 = a0 + 5461
        s0 = A3Sin(a0): c0 = A3Cos(a0): s1 = A3Sin(a1): c1 = A3Cos(a1)
        A3QuadW cam, -2, col, x + ShrA(s0 * r, 16), 1, z + ShrA(c0 * r, 16), x + ShrA(s1 * r, 16), 1, z + ShrA(c1 * r, 16), _
                x + ShrA(s1 * (r - 8), 16), 1, z + ShrA(c1 * (r - 8), 16), x + ShrA(s0 * (r - 8), 16), 1, z + ShrA(c0 * (r - 8), 16)
    Next k
End Sub

' the floor's grid: lines every 200 units (the original draws them as thin quads)
Private Sub FloorGrid(cv As Object)
    Dim k As Long, c As Long
    c = pen(PEN_GRID)
    For k = -TD_ARENA To TD_ARENA Step 200
        A3LineW cv, cam, k, 0, -TD_ARENA, k, 0, TD_ARENA, c
        A3LineW cv, cam, -TD_ARENA, 0, k, TD_ARENA, 0, k, c
    Next k
End Sub

Private Sub Walls()
    Dim side As Long, k As Long, u0 As Long, u1 As Long, s As Long
    For side = 0 To 3
        If side < 2 Then s = TD_ARENA Else s = -TD_ARENA
        For k = 0 To 4
            u0 = -TD_ARENA + k * 400
            u1 = u0 + 400
            If side And 1 Then
                A3QuadW cam, -1, PEN_WALL + (k And 1), s, 0, u0, s, 0, u1, s, 70, u1, s, 70, u0
            Else
                A3QuadW cam, -1, PEN_WALL + (k And 1), u0, 0, s, u1, 0, s, u1, 70, s, u0, 70, s
            End If
        Next k
    Next side
End Sub

Private Sub Obstacles()
    Dim k As Long
    For k = 0 To tdNObs - 1
        Select Case ob(k).kind
            Case OB_PILLAR: A3ModelDraw cam, mPillar, ShrA(ob(k).x, 16), 0, ShrA(ob(k).z, 16), False, rot, 0, 0, 0, 0
            Case OB_PYRAMID: A3ModelDraw cam, mPyramid, ShrA(ob(k).x, 16), 0, ShrA(ob(k).z, 16), False, rot, 0, 0, 0, 0
            Case Else
                If ob(k).hp >= 2 Then
                    A3ModelDraw cam, mCrate, ShrA(ob(k).x, 16), 0, ShrA(ob(k).z, 16), False, rot, 13, 14, 0, 0
                ElseIf ob(k).hp > 0 Then
                    A3ModelDraw cam, mCrate, ShrA(ob(k).x, 16), 0, ShrA(ob(k).z, 16), False, rot, 15, 14, 0, 0
                End If
        End Select
    Next k
End Sub

Private Sub Tanks()
    Dim k As Long
    For k = 1 To tdNTanks - 1
        If tk(k).alive Then
            CamFor cam, tk(k).x, 0, tk(k).z, tc        ' drawn where it is, not on whole units
            RotYaw rot, tk(k).yaw
            A3ModelDraw tc, mTank(tk(k).ttype), ShrA(tk(k).x, 16), 0, ShrA(tk(k).z, 16), True, rot, 0, 0, 0, 0
        End If
    Next k
End Sub

Private Sub Missiles()
    Dim k As Long, f As Long, x As Long, z As Long, y As Long, p As Long
    For k = 0 To TD_MAX_SHELLS - 1
        If sh(k).alive Then
            If sh(k).owner Then p = PEN_ESHELL Else p = PEN_SHELL
            Spot ShrA(sh(k).x, 16), 20, ShrA(sh(k).z, 16), 5, p, -4
        End If
    Next k
    For k = 0 To TD_MAX_MORTARS - 1
        If mo(k).alive Then
            f = (mo(k).t * 256) \ mo(k).flight
            x = ShrA(mo(k).x0, 16) + ShrA(ShrA(mo(k).tx - mo(k).x0, 16) * f, 8)
            z = ShrA(mo(k).z0, 16) + ShrA(ShrA(mo(k).tz - mo(k).z0, 16) * f, 8)
            y = 20 + (4 * 280 * f * (256 - f)) \ 65536
            Spot x, y, z, 7, PEN_ESHELL, -4
            If tdTicks And 4 Then p = PEN_RING Else p = PEN_RED
            RingAt ShrA(mo(k).tx, 16), ShrA(mo(k).tz, 16), TD_SPLASH_R, p
        End If
    Next k
    For k = 0 To MAX_BLASTS - 1
        If bT(k) > 0 Then
            If bT(k) > 7 Then
                p = PEN_YELLOW
            ElseIf bT(k) > 3 Then
                p = PEN_FIRE
            Else
                p = PEN_RED
            End If
            Burst bX(k), bY(k) + (10 - bT(k)) * 2, bZ(k), (bSize(k) * (4 + bT(k))) \ 14, p, bT(k)
        End If
    Next k
End Sub

Private Sub Scene(cv As Object)
    Dim hz As Long
    ' placed to a sixteenth of a unit: a camera on whole units steps unevenly as
    ' the tank drives, which shows as judder
    CamPlace cam, tk(0).x, EYE_Y * 65536, tk(0).z
    cam.yaw = tk(0).yaw
    cam.pitch = 300
    CamView cam, G_W, G_H, G_W \ 2, 118, 220
    CamSetup cam
    hz = CamHorizon(cam)
    If hz < 1 Then hz = 1
    If hz > G_H - 1 Then hz = G_H - 1
    ' the sky: a gradient in bands, the floor plain
    SkyBands cv, hz
    cv.Box 0, hz, G_W, G_H - hz, pen(PEN_FLOOR)
    FloorGrid cv
    A3Begin 3000
    Walls
    Obstacles
    Tanks
    Missiles
    polyTotal = polyTotal + a3NPolys
    A3Flush cv
End Sub

' the sky from skyTop down to skyBottom over 120 rows, in 8-row bands
Private Sub SkyBands(cv As Object, ByVal hz As Long)
    Dim y As Long, f As Long, r As Long, g As Long, b As Long, h As Long
    For y = 0 To hz - 1 Step 8
        f = y
        If f > 120 Then f = 120
        r = (skyTop And 255) + ((skyBottom And 255) - (skyTop And 255)) * f \ 120
        g = ((skyTop \ 256) And 255) + (((skyBottom \ 256) And 255) - ((skyTop \ 256) And 255)) * f \ 120
        b = ((skyTop \ 65536) And 255) + (((skyBottom \ 65536) And 255) - ((skyTop \ 65536) And 255)) * f \ 120
        h = 8
        If y + h > hz Then h = hz - y
        cv.Box 0, y, G_W, h, RGB(r, g, b)
    Next y
End Sub

' ---------- the HUD ----------
Private Sub Radar(cv As Object)
    Dim cx As Long, cy As Long, k As Long, c As Long, s As Long, p As Long
    cx = G_W - 36
    cy = 36
    c = A3Cos(tk(0).yaw)
    s = A3Sin(tk(0).yaw)
    cv.Circle cx, cy, 32, pen(3), True
    cv.Circle cx, cy, 30, pen(PEN_RADAR), True
    ' everything turned so ahead is up; 1 pixel = 40 units
    For k = 0 To tdNObs - 1
        If ob(k).kind <> OB_CRATE Or ob(k).hp > 0 Then Blip cv, ob(k).x, ob(k).z, 3, 0, c, s, cx, cy
    Next k
    For k = 0 To TD_MAX_MORTARS - 1
        If mo(k).alive Then Blip cv, mo(k).tx, mo(k).tz, PEN_RED, 1, c, s, cx, cy
    Next k
    For k = 1 To tdNTanks - 1
        If tk(k).alive Then
            Select Case tk(k).ttype
                Case TK_SCOUT: p = PEN_GREEN
                Case TK_MORTAR: p = PEN_FIRE
                Case Else: p = PEN_CYAN
            End Select
            Blip cv, tk(k).x, tk(k).z, p, 1, c, s, cx, cy
        End If
    Next k
    GRect cv, cx - 1, cy - 1, cx + 1, cy + 1, 1
    GRect cv, cx, cy - 5, cx, cy - 2, 1
End Sub

Private Sub Blip(cv As Object, ByVal wx As Long, ByVal wz As Long, ByVal p As Long, ByVal sz As Long, _
                 ByVal c As Long, ByVal s As Long, ByVal cx As Long, ByVal cy As Long)
    Dim dx As Long, dz As Long, rx As Long, rz As Long, bx As Long, by As Long
    dx = ShrA(wx - tk(0).x, 16)
    dz = ShrA(wz - tk(0).z, 16)
    rx = Int((CDbl(dx) * c - CDbl(dz) * s) / 65536#)
    rz = Int((CDbl(dx) * s + CDbl(dz) * c) / 65536#)
    bx = cx + rx \ 40
    by = cy - rz \ 40
    If (bx - cx) * (bx - cx) + (by - cy) * (by - cy) < 900 Then GRect cv, bx - sz, by - sz, bx + sz, by + sz, p
End Sub

Private Sub Gun(cv As Object)
    Dim kick As Long
    If tk(0).reload > TD_RELOAD - 4 Then kick = 6
    gunX(0) = 146: gunX(1) = 174: gunX(2) = 186: gunX(3) = 134
    gunY(0) = 206 + kick: gunY(1) = 206 + kick: gunY(2) = G_H - 1: gunY(3) = G_H - 1
    cv.Polygon gunX, gunY, 4, pen(3), True
    GRect cv, 154, 206 + kick, 166, 210 + kick, 0
    ' the sight
    GRect cv, 159, 108, 160, 113, PEN_GREEN
    GRect cv, 159, 123, 160, 128, PEN_GREEN
    GRect cv, 148, 117, 153, 118, PEN_GREEN
    GRect cv, 166, 117, 171, 118, PEN_GREEN
End Sub

Private Sub Hud(cv As Object)
    Dim w As Long, p As Long
    Gun cv
    Radar cv
    GTextShadow cv, 4, 10, PEN_YELLOW, "ROUND " & tdRound
    GTextShadow cv, 4, 22, 1, "ENEMIES " & TdEnemiesLeft()
    GTextShadow cv, 4, 34, 3, CStr(tdScore)
    GTextShadow cv, 4, 242, 3, "ARMOUR"
    GBox cv, 56, 235, 138, 243, 0, 3
    w = (tk(0).hp * 80) \ TD_HP
    If tk(0).hp > 40 Then p = PEN_GREEN Else p = PEN_RED
    If w > 0 Then GRect cv, 57, 236, 57 + w, 242, p
    GTextShadow cv, 202, 242, 3, "GUN"
    w = ((TD_RELOAD - tk(0).reload) * 80) \ TD_RELOAD
    GBox cv, 228, 235, 310, 243, 0, 3
    If tk(0).reload Then p = PEN_FIRE Else p = PEN_YELLOW
    GRect cv, 229, 236, 229 + w, 242, p
    If duAutoplay Then GTextShadow cv, 4, 228, PEN_GREEN, "AUTO"
    If duHurtTimer > 0 Then
        GRect cv, 0, 0, G_W - 1, 3, PEN_RED
        GRect cv, 0, G_H - 4, G_W - 1, G_H - 1, PEN_RED
        GRect cv, 0, 0, 3, G_H - 1, PEN_RED
        GRect cv, G_W - 4, 0, G_W - 1, G_H - 1, PEN_RED
    End If
End Sub

Public Sub DrawFight(cv As Object, ByVal isOver As Boolean)
    Dim pct As Long, p As Long
    Scene cv
    Hud cv
    If tdBetween Then
        GTextBigCentre cv, 70, PEN_GREEN, "ROUND CLEAR", 2
        If tdRound < TD_ROUNDS Then GTextCentre cv, 100, 1, "ROUND " & (tdRound + 1) & " NEXT"
    End If
    If Not isOver And tdTicks < 50 And tdBetween = 0 Then
        GTextCentre cv, 70, PEN_YELLOW, "ROUND " & tdRound & ": " & TdEnemiesLeft() & " ENEMIES"
    End If
    If isOver Then
        If tdWon Then p = PEN_GREEN Else p = PEN_RED
        GBox cv, 50, 70, 270, 150, 2, p
        If tdWon Then GTextBigCentre cv, 78, p, "VICTORY", 2 Else GTextBigCentre cv, 78, p, "GAME OVER", 2
        If tdShots Then pct = (tdHits * 100) \ tdShots
        GTextCentre cv, 112, PEN_YELLOW, tdKills & " KILLS  " & pct & "% HITS"
        GTextCentre cv, 126, 1, "SCORE " & tdScore
        If duStateTimer = 0 Then GTextCentre cv, 142, PEN_YELLOW, "PRESS FIRE"
    End If
    If duPaused Then GTextCentre cv, 160, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre cv, 60, duFlashPen, duFlash
End Sub

Public Sub DrawTitle(cv As Object)
    Dim p As Long
    Scene cv                              ' the autopilot fights behind the title
    GTextBig cv, 58, 26, 0, "TANK", 6
    GTextBig cv, 56, 24, PEN_YELLOW, "TANK", 6
    GTextBig cv, 94, 82, 0, "DUEL", 6
    GTextBig cv, 92, 80, PEN_FIRE, "DUEL", 6
    GBox cv, 40, 196, 280, 252, 2, 3
    GTextCentre cv, 210, PEN_GREEN, "START AT ROUND " & startRound & " (UP/DOWN)"
    If (tdTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre cv, 226, p, "PRESS SPACE TO FIGHT"
    GTextCentre cv, 242, 3, "BEST " & hsScore(0) & "   HELP: HOW TO PLAY"
End Sub

Public Sub DrawHelp(cv As Object, ByVal page As Long)
    Dim k As Long
    cv.Box 0, 0, G_W, G_H, pen(2)
    If page = 1 Then GTextBigCentre cv, 14, PEN_YELLOW, "HOW TO PLAY", 2 Else GTextBigCentre cv, 14, PEN_YELLOW, "CONTROLS", 2
    For k = 0 To 11
        GText cv, 12, 58 + k * 14, 1, helpText(page, k)
    Next k
    GText cv, 8, 248, 3, "PAGE " & page & " OF 2"
    GText cv, 156, 248, PEN_YELLOW, "HELP: NEXT  SPACE: BACK"
End Sub

Public Sub DrawEntry(cv As Object, ByVal nm As String)
    Dim cur As String
    Scene cv
    GBox cv, 40, 70, 280, 180, 2, PEN_YELLOW
    GTextCentre cv, 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre cv, 110, 1, "PLACE " & (HsRank(tdScore) + 1) & "   " & Format$(tdScore, "0000000")
    If (tdTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre cv, 140, PEN_GREEN, "YOUR NAME: " & nm & cur
    GTextCentre cv, 166, 3, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores(cv As Object)
    Dim i As Long, p As Long
    Scene cv
    GBox cv, 50, 36, 270, 200, 2, 3
    GTextBigCentre cv, 44, PEN_YELLOW, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = entryRank Then p = PEN_GREEN Else p = 1
        GTextCentre cv, 86 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf(cv As Object)
    cv.Box 0, 46, G_W, 11, pen(0)
    GText cv, 2, 55, PEN_GREEN, PerfText()
End Sub
