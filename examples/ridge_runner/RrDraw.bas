' Ridge Runner - the picture (a port of render.c) and the shell's effects (game.c): the sky
' and far ridges, the ground (an Engine3D height grid of the whole valley, made once a
' track, each cell's pen chosen by its slope as the C shades its quads), the track laid over
' it as a ribbon with kerbs, the gates' pylons and banners, the finish, the bikes with their
' shadows and boost flames, and the race's HUD. The camera chases the bike, its heading
' easing after the bike's. Title, help, high scores.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startTrack As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean
Public camYaw As Long, countdown As Long
Public groundRange As Long

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5-10 ground (light to dark), 11-13 the
' track, 14 kerb red, 15 shadow, 16-17 the player's bike, 18-23 the rivals', 24 pylons,
' 25 banner, 26 red, 27 yellow, 28 green, 29 cyan, 30 far ridges, 31 flame
Private Const PEN_SKY As Long = 4
Private Const PEN_GROUND As Long = 5
Private Const PEN_TRACK As Long = 11
Private Const PEN_KERB As Long = 14
Private Const PEN_SHADOW As Long = 15
Private Const PEN_PYLON As Long = 24
Private Const PEN_BANNER As Long = 25
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const PEN_RIDGE As Long = 30
Private Const PEN_FLAME As Long = 31
Private Const CELL As Long = 80
Private Const SEG As Long = 80
Private Const GX0 As Long = -1360            ' the grid: x -1360..1360, z -400..16480
Private Const GZ0 As Long = -400
Private Const GRID_W As Long = 35
Private Const GRID_H As Long = 212

Private cam As A3Cam, bc As A3Cam
Private bikeM As A3Model, pylonM As A3Model
Private rot(0 To 8) As Long
Private themes(0 To 2) As Variant
Private skyTopT(0 To 2) As Long, skyBotT(0 To 2) As Long
Private theme As Long, skyTop As Long, skyBottom As Long
Private grid As Long, gridTrack As Long, gridSeed As Long
Private gHeight(0 To 7419) As Long, gPen(0 To 7173) As Long
Private off5(0 To 4) As Long
Private rx3(0 To 2) As Long, ry3(0 To 2) As Long
Private helpText(1 To 2, 0 To 11) As String
Private placeName(0 To 4) As String

Public Sub DrawInit()
    Dim h As Variant, i As Long, a As Long, b As Long, c As Long, d As Long, e As Long, f As Long, g As Long, k As Long
    themes(0) = Array(&H0, &HFFF, &H123, &H99A, &H69D, &H7C5, &H6B4, &H5A3, &H492, &H381, &H260, _
                      &H998, &H887, &H776, &HE33, &H131, &H3CF, &H18A, &HF62, &HA31, &HFD3, &HA81, &HC5E, &H737, _
                      &HF80, &HFFE, &HF33, &HFE4, &H6F6, &H5EF, &H58A, &HFC4)
    themes(1) = Array(&H0, &HFFF, &H211, &HA99, &HE96, &HDA6, &HC95, &HB84, &HA73, &H862, &H641, _
                      &H887, &H776, &H665, &HE33, &H420, &H3CF, &H18A, &H6E4, &H382, &HFD3, &HA81, &HC5E, &H737, _
                      &HF80, &HFFE, &HF33, &HFE4, &H6F6, &H5EF, &HB75, &HFC4)
    themes(2) = Array(&H0, &HFFF, &H123, &H99A, &H8AC, &HEEF, &HDDE, &HBCD, &H9AC, &H89A, &H678, _
                      &H667, &H556, &H445, &HE33, &H567, &HF62, &HA31, &H3CF, &H18A, &HFD3, &HA81, &HC5E, &H737, _
                      &HF80, &HFFE, &HF33, &HFE4, &H6F6, &H5EF, &H9AB, &HFC4)
    skyTopT(0) = &H36B: skyTopT(1) = &HC74: skyTopT(2) = &H68A
    skyBotT(0) = &HBDE: skyBotT(1) = &HFDA: skyBotT(2) = &HDEF
    groundRange = 560
    off5(0) = -RR_TRACK_HW - 8: off5(1) = -RR_TRACK_HW: off5(2) = 0: off5(3) = RR_TRACK_HW: off5(4) = RR_TRACK_HW + 8
    SetTheme 1
    ' a hover bike, nose along +z: the hull, a raised seat, the nose cone, two side pods
    MdlBegin bikeM
    MdlBox bikeM, COL_BODY, COL_BODY + 1, -9, 9, -4, 6, -18, 16
    MdlBox bikeM, COL_BODY + 1, COL_BODY + 1, -6, 6, 6, 12, -14, 2
    a = MdlVtx(bikeM, -9, -4, 16): b = MdlVtx(bikeM, 9, -4, 16): c = MdlVtx(bikeM, 9, 6, 16): d = MdlVtx(bikeM, -9, 6, 16)
    e = MdlVtx(bikeM, -4, -4, 36): f = MdlVtx(bikeM, 4, -4, 36): g = MdlVtx(bikeM, 4, -1, 36): k = MdlVtx(bikeM, -4, -1, 36)
    MdlFace bikeM, COL_BODY, COL_BODY + 1, 4, d, c, g, k, 0, 0, 22
    MdlFace bikeM, COL_BODY, COL_BODY + 1, 4, b, c, g, f, 0, 0, 22
    MdlFace bikeM, COL_BODY, COL_BODY + 1, 4, a, d, k, e, 0, 0, 22
    MdlFace bikeM, COL_BODY, COL_BODY + 1, 4, e, f, g, k, 0, 0, 22
    MdlBox bikeM, 3, 2, -17, -9, -6, 2, -14, 10
    MdlBox bikeM, 3, 2, 9, 17, -6, 2, -14, 10
    MdlBegin pylonM
    MdlPrism pylonM, PEN_PYLON, PEN_PYLON, 6, 9, 0, 90
    MdlBox pylonM, 1, 3, -11, 11, 90, 98, -11, 11
    h = Array("RACE YOUR HOVER BIKE DOWN THE VALLEY", "AGAINST THREE RIVALS. FINISH IN THE", _
              "FIRST THREE TO GO ON TO THE NEXT TRACK.", "", "PASS BETWEEN EACH GATE'S PYLONS: A GATE", _
              "ADDS TIME TO THE CLOCK. MISS ONE AND", "YOU LOSE THREE SECONDS.", "", _
              "OFF THE TRACK THE ROUGH GROUND SLOWS", "YOU. CRESTS THROW YOU INTO THE AIR -", _
              "YOU CAN'T STEER MUCH UNTIL YOU LAND.", "SIX TRACKS, EACH TWISTIER AND HILLIER.", _
              "LEFT / RIGHT     STEER", "UP               THROTTLE", "DOWN             BRAKE", _
              "SPACE            BOOST (THE YELLOW BAR)", "P                PAUSE", "B                AUTOPILOT", _
              "HELP / H         THESE PAGES", "ESC              TITLE / QUIT", "", _
              "GATE 100. FINISH 3000 / 2000 / 1000", "FOR 1ST / 2ND / 3RD, AND 10 FOR EACH", "SECOND LEFT ON THE CLOCK.")
    For i = 0 To 11
        helpText(1, i) = h(i)
        helpText(2, i) = h(12 + i)
    Next i
    placeName(1) = "1ST": placeName(2) = "2ND": placeName(3) = "3RD": placeName(4) = "4TH"
End Sub

' the track's look: its palette and sky
Public Sub SetTheme(ByVal track As Long)
    Dim t As Variant
    t = Array(0, 1, 1, 2, 0, 2)
    theme = t((track - 1) Mod RR_TRACKS)
    GfxPalette themes(theme)
    skyTop = Rgb12(skyTopT(theme))
    skyBottom = Rgb12(skyBotT(theme))
End Sub

' the valley as a height grid, its cells' pens by slope (made when the track changes)
Private Sub MakeGround()
    Dim i As Long, j As Long, ha As Long, hb As Long, hc As Long, hd As Long, slope As Long, p As Long
    If grid <> 0 And gridTrack = rrTrack And gridSeed = rrSeed Then Exit Sub
    For j = 0 To GRID_H - 1
        For i = 0 To GRID_W - 1
            gHeight(j * GRID_W + i) = RrHeight(GX0 + i * CELL, GZ0 + j * CELL)
        Next i
    Next j
    For j = 0 To GRID_H - 2
        For i = 0 To GRID_W - 2
            ha = gHeight(j * GRID_W + i): hb = gHeight(j * GRID_W + i + 1): hc = gHeight((j + 1) * GRID_W + i + 1): hd = gHeight((j + 1) * GRID_W + i)
            ' lit from the left and ahead
            slope = ((ha + hd) - (hb + hc)) + ((hc + hd) - (ha + hb)) \ 2
            p = 2 + slope \ 24
            If p < 0 Then p = 0
            If p > 5 Then p = 5
            gPen(j * (GRID_W - 1) + i) = PEN_GROUND + p
        Next i
    Next j
    If grid = 0 Then grid = e3d.GridNew(GRID_W, GRID_H, CELL, GX0, GZ0)
    e3d.GridSet grid, gHeight, gPen
    e3d.GridShade grid, False
    gridTrack = rrTrack
    gridSeed = rrSeed
End Sub

Private Sub Flash(ByVal s As String, ByVal p As Long)
    duFlash = s
    duFlashTimer = 30
    duFlashPen = p
End Sub

Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long
    If loud Then
        For i = 0 To rrNEv - 1
            Select Case rrEv(i).etype
                Case RRE_GATE
                    Sfx SFX_GATE
                    Flash "GATE +" & (9 - rrTrack \ 2) & " S", 28
                Case RRE_MISS
                    Sfx SFX_MISS
                    Flash "MISSED THE GATE -3 S", 26
                Case RRE_JUMP
                    Sfx SFX_LAND
                    If rrEv(i).a > 16 Then Flash "BIG AIR!", 29
                Case RRE_LAND: Sfx SFX_LAND
                Case RRE_BUMP: Sfx SFX_BUMP
                Case RRE_QUALIFY: Sfx SFX_FINISH
                Case RRE_FAIL: Sfx SFX_FAIL
                Case RRE_TIMEOUT: Flash "OUT OF TIME", 26
                Case RRE_OVER: Sfx SFX_OVER
                Case RRE_WIN: Sfx SFX_WIN
            End Select
        Next i
    End If
    rrNEv = 0
End Sub

Public Sub AgeEffects()
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
End Sub

' ---------- the scene ----------
' the track: a ribbon along the course, its halves following the ground across, kerbs
' in alternate colours
Private Sub TrackRibbon()
    Dim z0 As Long, z1 As Long, z As Long, za As Long, zb As Long, ca As Long, cb As Long, k As Long, stripe As Long, p As Long
    Dim ya(0 To 4) As Long, yb(0 To 4) As Long
    z0 = (ShrA(rrZ, 16) \ CELL - 2) * CELL
    z1 = z0 + groundRange + 3 * CELL
    If z0 < -CELL Then z0 = -CELL
    If z1 > RR_LEN + CELL Then z1 = RR_LEN + CELL
    a3QuadBias = 20 * 16
    z = z0
    Do While z < z1
        za = z: zb = z + SEG
        ca = RrCentre(za): cb = RrCentre(zb)
        CamXform cam, cb, RrHeight(cb, zb) + 2, zb
        If oz >= CamNear(cam) Then
            stripe = (z \ SEG) And 1
            For k = 0 To 4
                ya(k) = RrHeight(ca + off5(k) \ 2, za) + 2      ' (measured inside the valley's sides)
                yb(k) = RrHeight(cb + off5(k) \ 2, zb) + 2
            Next k
            For k = 0 To 3
                If k = 0 Or k = 3 Then
                    If stripe Then p = PEN_KERB Else p = 1
                Else
                    p = PEN_TRACK + ((k + stripe) And 1)
                End If
                A3QuadW cam, -1, p, ca + off5(k), ya(k), za, cb + off5(k), yb(k), zb, cb + off5(k + 1), yb(k + 1), zb, _
                        ca + off5(k + 1), ya(k + 1), za
            Next k
        End If
        z = z + SEG
    Loop
    a3QuadBias = 0
End Sub

Private Sub Gates()
    Dim k As Long, gz As Long, c As Long, s As Long, y0 As Long, xa As Long, isLast As Boolean, p As Long
    RotYaw rot, 0
    k = rrGate
    Do While k < RR_GATES And k < rrGate + 3
        gz = (k + 1) * RR_GATE_GAP
        If gz - ShrA(rrZ, 16) > groundRange + 3 * CELL Then Exit Do
        c = RrCentre(gz)
        For s = -1 To 1 Step 2
            A3ModelDraw cam, pylonM, c + s * RR_GATE_HW, RrHeight(c + s * (RR_TRACK_HW - 10), gz), gz, True, rot, 0, 0, 0, 0
        Next s
        If k = rrGate Then                    ' the next gate's banner
            y0 = RrHeight(c, gz) + 70
            isLast = (k = RR_GATES - 1)
            If isLast Then p = 1 Else p = PEN_BANNER
            Poly4 c - RR_GATE_HW, y0, c + RR_GATE_HW, y0 + 16, gz, 4, p
            If isLast Then                     ' the finish: chequered
                For s = 0 To 5
                    xa = c - RR_GATE_HW + s * 30 + 2
                    Poly4 xa, y0 + 2 + (s And 1) * 6, xa + 13, y0 + 8 + (s And 1) * 6, gz, 6, 0
                Next s
            End If
        End If
        k = k + 1
    Loop
End Sub

' a flat rectangle across the course at z (x0..x1, y0..y1), pulled forward by bias
Private Sub Poly4(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z As Long, ByVal bias As Long, ByVal p As Long)
    CamXform cam, x0, y0, z: pvx(0) = ox: pvy(0) = oy: pvz(0) = oz
    If oz <= CamNear(cam) Then Exit Sub
    CamXform cam, x1, y0, z: pvx(1) = ox: pvy(1) = oy: pvz(1) = oz
    CamXform cam, x1, y1, z: pvx(2) = ox: pvy(2) = oy: pvz(2) = oz
    CamXform cam, x0, y1, z: pvx(3) = ox: pvy(3) = oy: pvz(3) = oz
    A3Poly cam, pvz(0) - bias * 16, p, 4
End Sub

' a bike at a 16.16 world position, drawn through a copy of the camera that places it
' exactly (so it glides with the camera)
Private Sub DrawBike(ByVal fx As Long, ByVal fy As Long, ByVal fz As Long, ByVal yaw As Long, ByVal lean As Long, _
                     ByVal colour As Long, ByVal flame As Boolean)
    Dim x As Long, y As Long, z As Long, gy As Long, k As Long, a As Long, sx As Long, sz As Long, ln As Long
    x = ShrA(fx, 16): y = ShrA(fy, 16): z = ShrA(fz, 16)
    gy = RrHeight(x, z) + 1
    CamFor cam, fx, fy, fz, bc
    ' its shadow
    For k = 0 To 5
        a = k * 10923
        CamXform bc, x + ShrA(A3Sin(a) * 16, 16), gy, z + ShrA((A3Cos(a) * 16 * 3) \ 2, 16)
        pvx(k) = ox: pvy(k) = oy: pvz(k) = oz
    Next k
    If pvz(0) > CamNear(bc) And pvz(3) > CamNear(bc) Then A3Poly bc, ShrA(pvz(0) + pvz(3), 1) + 96, PEN_SHADOW, 6
    RotYPR rot, yaw, 0, lean
    A3ModelDraw bc, bikeM, x, y, z, True, rot, 16 + colour * 2, 17 + colour * 2, 0, 0
    If flame Then
        sx = A3Sin(yaw): sz = A3Cos(yaw)
        ln = 26 + (rrTicks Mod 3) * 8
        CamXform bc, x - ShrA(sz * 6, 16) - ShrA(sx * 18, 16), y + 2, z + ShrA(sx * 6, 16) - ShrA(sz * 18, 16)
        pvx(0) = ox: pvy(0) = oy: pvz(0) = oz
        CamXform bc, x + ShrA(sz * 6, 16) - ShrA(sx * 18, 16), y + 2, z - ShrA(sx * 6, 16) - ShrA(sz * 18, 16)
        pvx(1) = ox: pvy(1) = oy: pvz(1) = oz
        CamXform bc, x - ShrA(sx * (18 + ln), 16), y + 3, z - ShrA(sz * (18 + ln), 16)
        pvx(2) = ox: pvy(2) = oy: pvz(2) = oz
        If pvz(2) > CamNear(bc) Then
            If rrTicks And 1 Then A3Poly bc, pvz(2) - 160, PEN_FLAME, 3 Else A3Poly bc, pvz(2) - 160, PEN_YELLOW, 3
        End If
    End If
End Sub

Private Sub Bikes()
    Dim k As Long, x As Long, z As Long, dz As Long, yaw As Long
    For k = 0 To RR_RIVALS - 1
        If rv(k).finished = 0 Then
            x = ShrA(rv(k).x, 16): z = ShrA(rv(k).z, 16): dz = z - ShrA(rrZ, 16)
            If dz >= -300 And dz <= groundRange + 2 * CELL Then
                yaw = A3Atan2(RrCentre(z + 60) - RrCentre(z), 60)
                DrawBike rv(k).x, (RrHeight(x, z) + RR_HOVER) * 65536, rv(k).z, yaw, 0, k + 1, False
            End If
        End If
    Next k
    DrawBike rrX, rrY, rrZ, rrYaw, -rrSteer * 2200, 0, rrBoosting <> 0
End Sub

Private Sub Camera()
    Dim fx As Long, fz As Long, x As Long, z As Long, y As Long, gy As Long
    fx = A3Sin(camYaw): fz = A3Cos(camYaw)
    x = rrX - fx * 150: z = rrZ - fz * 150: y = rrY + 62 * 65536
    ' placed to a sixteenth of a unit (a camera on whole units judders)
    gy = RrHeight(ShrA(x, 16), ShrA(z, 16)) + 30
    If ShrA(y, 16) < gy Then y = gy * 65536
    CamPlace cam, x, y, z
    cam.yaw = camYaw
    cam.pitch = 1500
    CamView cam, G_W, G_H, G_W \ 2, 104, 210
    CamSetup cam
End Sub

Private Sub Sky()
    Dim hz As Long, k As Long, w As Long, h As Long, x As Long, y As Long, f As Long, r As Long, g As Long, b As Long, hh As Long
    hz = CamHorizon(cam)
    If hz < 4 Then hz = 4
    If hz > G_H - 1 Then hz = G_H - 1
    For y = 0 To hz - 1 Step 8
        f = y
        If f > 150 Then f = 150
        r = (skyTop And 255) + ((skyBottom And 255) - (skyTop And 255)) * f \ 150
        g = ((skyTop \ 256) And 255) + (((skyBottom \ 256) And 255) - ((skyTop \ 256) And 255)) * f \ 150
        b = ((skyTop \ 65536) And 255) + (((skyBottom \ 65536) And 255) - ((skyTop \ 65536) And 255)) * f \ 150
        hh = 8
        If y + hh > hz Then hh = hz - y
        gcv.Box 0, y, G_W, hh, RGB(r, g, b)
    Next y
    gcv.Box 0, hz, G_W, G_H - hz, pen(PEN_GROUND + 5)
    ' far ridges, drifting as the camera turns
    For k = 0 To 11
        w = 40 + UModL(A3Hash(k * 31), 40)
        h = 6 + UModL(A3Hash(k * 77), 18)
        x = ((k * 61 - camYaw \ 64) Mod 360 + 360) Mod 360 - 30
        rx3(0) = x - w \ 2: rx3(1) = x: rx3(2) = x + w \ 2
        ry3(0) = hz: ry3(1) = hz - h: ry3(2) = hz
        gcv.Polygon rx3, ry3, 3, pen(PEN_RIDGE), True
    Next k
End Sub

Private Sub Scene()
    Camera
    Sky
    A3Begin 3000
    MakeGround
    UseCamera
    e3d.DrawGrid grid, groundRange, -40
    TrackRibbon
    Gates
    Bikes
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

' the engine's camera set to ours (A3Engine does it on the first A3 call; DrawGrid is the engine's own)
Private Sub UseCamera()
    A3QuadW cam, 0, 0, cam.x, cam.y, cam.z, cam.x, cam.y, cam.z, cam.x, cam.y, cam.z, cam.x, cam.y, cam.z
End Sub

' ---------- the HUD ----------
Private Sub Hud()
    Dim k As Long, p As Long, w As Long, s As String, x As Long
    p = RrPlaceNow()
    If p <= 3 Then GTextBig 4, 4, PEN_GREEN, placeName(p), 2 Else GTextBig 4, 4, PEN_RED, placeName(p), 2
    s = CStr(rrTimeLeft \ 25)
    If rrTimeLeft < 250 And (rrTicks And 8) <> 0 Then k = PEN_RED Else k = PEN_YELLOW
    GTextBig (G_W - GTextBigWidth(s, 2)) \ 2, 4, k, s, 2
    If rrGate < RR_GATES Then k = rrGate + 1 Else k = RR_GATES
    GTextShadow 236, 12, 1, "GATE " & k & "/" & RR_GATES
    GTextShadow 236, 24, 3, CStr(rrScore)
    ' speed and boost
    w = ShrA(rrV, 16) * 4
    If w > 78 Then w = 78
    GBox 4, 238, 84, 244, 0, 3
    If rrV > RR_VMAX Then GRect 5, 239, 5 + w, 243, PEN_FLAME Else GRect 5, 239, 5 + w, 243, PEN_CYAN
    w = (ShrA(rrEnergy, 16) * 78) \ 100
    GBox 4, 247, 84, 253, 0, 3
    If w > 0 Then
        If rrEnergy >= RR_ENERGY \ 5 Then GRect 5, 248, 5 + w, 252, PEN_YELLOW Else GRect 5, 248, 5 + w, 252, PEN_RED
    End If
    ' the course: everyone's progress
    GRect 100, 248, 300, 249, 3
    For k = 0 To RR_RIVALS - 1
        x = 100 + (ShrA(rv(k).z, 16) * 200) \ RR_LEN
        If x < 100 Then x = 100
        If x > 300 Then x = 300
        GRect x - 1, 245, x + 1, 252, 18 + k * 2
    Next k
    x = 100 + (ShrA(rrZ, 16) * 200) \ RR_LEN
    If x > 300 Then x = 300
    GRect x - 2, 244, x + 2, 253, 1
    If rrOfftrack <> 0 And (rrTicks And 4) <> 0 Then GTextCentre 220, PEN_RED, "OFF THE TRACK"
    If duAutoplay Then GTextShadow 4, 232, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim p As Long, s As String
    Scene
    Hud
    If countdown > 0 Then
        GTextBigCentre 90, PEN_YELLOW, CStr(1 + (countdown - 1) \ 25), 6
        GTextCentre 150, 1, "TRACK " & rrTrack & ": " & RrTrackName(rrTrack)
    End If
    If rrFinished <> 0 And rrBetween <> 0 Then
        If rrQualified Then p = PEN_GREEN Else p = PEN_RED
        GTextBigCentre 70, p, placeName(rrPlace), 6
        If rrQualified = 0 Then
            s = "NOT QUALIFIED"
        ElseIf rrTrack < RR_TRACKS Then
            s = "QUALIFIED - NEXT TRACK"
        Else
            s = "CHAMPION!"
        End If
        GTextCentre 130, 1, s
    End If
    If isOver Then
        If rrWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 50, 70, 270, 150, 2, p
        If rrWon Then GTextBigCentre 78, p, "CHAMPION", 2 Else GTextBigCentre 78, p, "GAME OVER", 2
        If rrWon Then
            s = "ALL SIX TRACKS"
        ElseIf rrFinished Then
            s = "FINISHED 4TH"
        Else
            s = "OUT OF TIME"
        End If
        GTextCentre 112, PEN_YELLOW, s
        GTextCentre 126, 1, "SCORE " & rrScore
        If duStateTimer = 0 Then GTextCentre 142, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 128, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 60, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                                   ' the autopilot races behind the title
    GTextBig 68, 26, 0, "RIDGE", 6
    GTextBig 66, 24, PEN_YELLOW, "RIDGE", 6
    GTextBig 52, 82, 0, "RUNNER", 6
    GTextBig 50, 80, PEN_FLAME, "RUNNER", 6
    GBox 40, 196, 280, 252, 2, 3
    GTextCentre 210, PEN_GREEN, "TRACK " & startTrack & ": " & RrTrackName(startTrack)
    If (rrTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 226, p, "PRESS SPACE TO RACE"
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
    GTextCentre 110, 1, "PLACE " & (HsRank(rrScore) + 1) & "   " & Format$(rrScore, "0000000")
    If (rrTicks And 8) = 0 Then cur = "_" Else cur = " "
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
    gcv.Box 0, 36, G_W, 11, pen(0)
    GText 2, 45, PEN_GREEN, PerfText()
End Sub
