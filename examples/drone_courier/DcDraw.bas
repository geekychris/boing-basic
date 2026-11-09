' Drone Courier - the picture (a port of render.c) and the shell's effects (game.c): the sky
' and the ground, the towers near the drone and ahead of the camera (picked by a cull over
' the city's grid cells), the pads and the beacon over the next one, the drone with its
' rotors and parcel and its shadow, and the HUD: the battery, the clock, an arrow to the
' next pad, height, the wind. Title, help, high scores.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startDay As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean
Public camYaw As Long
Public viewRange As Long, towersDrawn As Long

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5 ground, 6 park, 7-12 towers in three
' tones (lit, shaded), 13 roofs, 14 depot pad, 15 customer pad, 16 beacon, 17-18 the
' drone, 19 rotors, 20 parcel, 21 fragile parcel, 22 shadow, 26 red, 27 yellow, 28 green, 29 cyan
Private Const PEN_SKY As Long = 4
Private Const PEN_GROUND As Long = 5
Private Const PEN_PARK As Long = 6
Private Const PEN_TOWER As Long = 7
Private Const PEN_ROOF As Long = 13
Private Const PEN_DEPOT As Long = 14
Private Const PEN_CUST As Long = 15
Private Const PEN_BEACON As Long = 16
Private Const PEN_DRONE As Long = 17
Private Const PEN_ROTOR As Long = 19
Private Const PEN_PARCEL As Long = 20
Private Const PEN_FRAGILE As Long = 21
Private Const PEN_SHADOW As Long = 22
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29

Private cam As A3Cam
Private skyTop As Long, skyBottom As Long
Private ax3(0 To 2) As Long, ay3(0 To 2) As Long
Private helpText(1 To 2, 0 To 11) As String
' the drone's frame for P(): position, forward and right
Private dX As Long, dZ As Long, dFx As Long, dFz As Long, dRx As Long, dRz As Long

Public Sub DrawInit()
    Dim h As Variant, i As Long
    GfxPalette Array(&H0, &HFFF, &H123, &H99A, &H7AE, &H667, &H5A5, &HCBA, &H987, &H9AB, &H678, &HBA9, &H876, _
                     &H556, &H39F, &H3E6, &HEF8, &HEEE, &H999, &H444, &HB85, &HE44, &H333, &H0, &H0, &H0, _
                     &HF33, &HFE4, &H6F6, &H5EF, &H0, &H0)
    skyTop = Rgb12(&H48C)
    skyBottom = Rgb12(&HCDE)
    viewRange = 560
    h = Array("COLLECT EACH PARCEL FROM THE DEPOT'S", "BLUE PAD AND LAND IT ON THE CUSTOMER'S", _
              "GREEN PAD. THE ARROW AND THE BEACON", "SHOW THE WAY.", "", _
              "TOUCH DOWN GENTLY ON THE PAD. FRAGILE", "PARCELS (RED) BREAK IF YOU LAND HARD", _
              "OR KNOCK A TOWER.", "", "THE BATTERY DRAINS - FASTER CLIMBING -", _
              "AND FILLS AT THE DEPOT. WIND FROM DAY 2.", "3 FAILED JOBS END THE GAME. 5 DAYS.", _
              "UP / DOWN        FORWARD / BACK", "LEFT / RIGHT     TURN", "SPACE            CLIMB (LET GO: SINK)", _
              "P                PAUSE", "B                AUTOPILOT", "HELP / H         THESE PAGES", _
              "ESC              TITLE / QUIT", "", "DELIVERY 200 + 5 A SECOND LEFT,", _
              "+150 FRAGILE. A DAY DONE: 500 x DAY.", "", "")
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
        For i = 0 To dcNEv - 1
            Select Case dcEv(i).etype
                Case DCE_PICKUP
                    Sfx SFX_PICKUP
                    If dcEv(i).a Then Flash "FRAGILE PARCEL - GENTLY!", 26 Else Flash "PARCEL ABOARD", 29
                Case DCE_DELIVER
                    Sfx SFX_DELIVER
                    Flash "DELIVERED", 28
                Case DCE_BUMP: Sfx SFX_BUMP
                Case DCE_HARD
                    Sfx SFX_BUMP
                    Flash "TOO HARD - TRY AGAIN", 27
                Case DCE_BROKEN
                    Sfx SFX_BROKEN
                    Flash "PARCEL BROKEN", 26
                Case DCE_LATE
                    Sfx SFX_LATE
                    Flash "TOO LATE", 26
                Case DCE_GUST: Sfx SFX_GUST
                Case DCE_FLAT: Flash "BATTERY FLAT", 26
                Case DCE_DAY: Sfx SFX_DAY
                Case DCE_OVER: Sfx SFX_OVER
                Case DCE_WIN: Sfx SFX_WIN
            End Select
        Next i
    End If
    dcNEv = 0
End Sub

Public Sub AgeEffects()
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
End Sub

' ---------- the scene ----------
Private Sub Quad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                 ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, _
                 ByVal bias As Long, ByVal col As Long)
    a3QuadBias = bias
    A3QuadW cam, -1, col, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3
End Sub

Private Sub Flat(ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal y As Long, ByVal bias As Long, ByVal col As Long)
    Quad x0, y, z0, x1, y, z0, x1, y, z1, x0, y, z1, bias, col
End Sub

' a tower: its roof and the (at most two) walls facing the camera
Private Sub Tower(ByVal cx As Long, ByVal cz As Long, ByVal h As Long, ByVal tone As Long)
    Dim x0 As Long, x1 As Long, z0 As Long, z1 As Long, lit As Long, sh As Long
    x0 = cx - DC_FOOT: x1 = cx + DC_FOOT: z0 = cz - DC_FOOT: z1 = cz + DC_FOOT
    lit = PEN_TOWER + 2 * tone: sh = lit + 1
    Flat x0, x1, z0, z1, h, 0, PEN_ROOF
    If cam.z < z0 Then
        Quad x0, 0, z0, x1, 0, z0, x1, h, z0, x0, h, z0, 0, lit
    ElseIf cam.z > z1 Then
        Quad x0, 0, z1, x1, 0, z1, x1, h, z1, x0, h, z1, 0, lit
    End If
    If cam.x < x0 Then
        Quad x0, 0, z0, x0, 0, z1, x0, h, z1, x0, h, z0, 0, sh
    ElseIf cam.x > x1 Then
        Quad x1, 0, z0, x1, 0, z1, x1, h, z1, x1, h, z0, 0, sh
    End If
End Sub

' culling by grid cell: only the cells round the camera out to the range, ahead of it
Private Sub City()
    Dim fx As Long, fz As Long, c0 As Long, c1 As Long, r0 As Long, r1 As Long, r As Long, c As Long
    Dim cx As Long, cz As Long, dx As Long, dz As Long, h As Long, b As Long, pr As Long, p As Long, t As Long
    fx = A3Sin(cam.yaw): fz = A3Cos(cam.yaw)
    c0 = (cam.x - viewRange + DC_HALF) \ DC_PITCH: c1 = (cam.x + viewRange + DC_HALF) \ DC_PITCH
    r0 = (cam.z - viewRange + DC_HALF) \ DC_PITCH: r1 = (cam.z + viewRange + DC_HALF) \ DC_PITCH
    If c0 < 0 Then c0 = 0
    If r0 < 0 Then r0 = 0
    If c1 >= DC_N Then c1 = DC_N - 1
    If r1 >= DC_N Then r1 = DC_N - 1
    towersDrawn = 0
    For r = r0 To r1
        For c = c0 To c1
            cx = ShrA(DcBlockX(c), 16): cz = ShrA(DcBlockZ(r), 16)
            dx = cx - cam.x: dz = cz - cam.z
            h = dcHeight(r, c)
            b = r * DC_N + c
            t = dx * fx + dz * fz
            If (t - (t And 65535)) \ 65536 >= -DC_PITCH And Abs(dx) <= viewRange And Abs(dz) <= viewRange Then
                If h = 0 Then
                    Flat cx - DC_FOOT, cx + DC_FOOT, cz - DC_FOOT, cz + DC_FOOT, 1, 60, PEN_PARK
                Else
                    Tower cx, cz, h, (r * 7 + c * 3) Mod 3
                    towersDrawn = towersDrawn + 1
                    If b = dcDepot Or b = DcGoal() Then
                        pr = dcPadR
                        If b = dcDepot Then p = PEN_DEPOT Else p = PEN_CUST
                        Flat cx - pr, cx + pr, cz - pr, cz + pr, h + 1, -4, p
                        Flat cx - pr + 6, cx + pr - 6, cz - pr + 6, cz + pr - 6, h + 2, -5, PEN_ROOF
                        Flat cx - pr + 12, cx + pr - 12, cz - pr + 12, cz + pr - 12, h + 3, -6, p
                    End If
                End If
            End If
        Next c
    Next r
End Sub

' the beacon over the next pad: seen from anywhere ahead
Private Sub Beacon()
    Dim b As Long, cx As Long, cz As Long, h As Long, w As Long, p As Long
    b = DcGoal()
    cx = ShrA(DcBlockX(b Mod DC_N), 16): cz = ShrA(DcBlockZ(b \ DC_N), 16)
    h = dcHeight(b \ DC_N, b Mod DC_N)
    w = 3 + (dcTicks And 2)
    If dcCarrying Then p = PEN_CUST Else p = PEN_DEPOT
    Quad cx - w, h, cz, cx + w, h, cz, cx + w, h + 260, cz, cx - w, h + 260, cz, -20, p
    Quad cx, h, cz - w, cx, h, cz + w, cx, h + 260, cz + w, cx, h + 260, cz - w, -20, PEN_BEACON
End Sub

' a point a along and b across the drone's heading (the C's P macro): x and z
Private Function PX(ByVal a As Long, ByVal b As Long) As Long
    Dim t As Long
    t = dFx * a + dRx * b
    PX = dX + (t - (t And 65535)) \ 65536
End Function

Private Function PZ(ByVal a As Long, ByVal b As Long) As Long
    Dim t As Long
    t = dFz * a + dRz * b
    PZ = dZ + (t - (t And 65535)) \ 65536
End Function

' a flat quad in the drone's frame at height y (corners (a0, b0) .. (a1, b1))
Private Sub DQuadFlat(ByVal a0 As Long, ByVal b0 As Long, ByVal a1 As Long, ByVal b1 As Long, ByVal y As Long, ByVal bias As Long, ByVal col As Long)
    Quad PX(a0, b0), y, PZ(a0, b0), PX(a0, b1), y, PZ(a0, b1), PX(a1, b1), y, PZ(a1, b1), PX(a1, b0), y, PZ(a1, b0), bias, col
End Sub

' an upright quad in the drone's frame along the line a = a0 (b0..b1, heights y0..y1)
Private Sub DQuadSide(ByVal a0 As Long, ByVal b0 As Long, ByVal b1 As Long, ByVal y0 As Long, ByVal y1 As Long, ByVal bias As Long, ByVal col As Long)
    Quad PX(a0, b0), y0, PZ(a0, b0), PX(a0, b1), y0, PZ(a0, b1), PX(a0, b1), y1, PZ(a0, b1), PX(a0, b0), y1, PZ(a0, b0), bias, col
End Sub

Private Sub Drone()
    Dim y As Long, gy As Long, k As Long, a As Long, bb As Long, s As Long, col As Long
    dX = ShrA(dcX, 16): y = ShrA(dcY, 16): dZ = ShrA(dcZ, 16)
    gy = DcRoof(DcBlockAt(dcX, dcZ))
    dFx = A3Sin(dcYaw): dFz = A3Cos(dcYaw): dRx = dFz: dRz = -dFx
    ' the shadow, straight down
    Flat dX - 14, dX + 14, dZ - 14, dZ + 14, gy + 1, 30, PEN_SHADOW
    ' the body, its four rotors, the parcel
    DQuadFlat -10, -8, 10, 8, y + 4, -2, PEN_DRONE
    DQuadSide 10, -8, 8, y, y + 4, -1, PEN_DRONE + 1
    DQuadSide -10, -8, 8, y, y + 4, -1, PEN_DRONE + 1
    For k = 0 To 3
        If k And 1 Then a = 16 Else a = -16
        If k And 2 Then bb = 16 Else bb = -16
        s = 7 + ((dcTicks + k) And 1)
        DQuadFlat a - s, bb - s, a + s, bb + s, y + 6, -3, PEN_ROTOR
    Next k
    If dcCarrying Then
        If dcFragile Then col = PEN_FRAGILE Else col = PEN_PARCEL
        DQuadFlat -6, -6, 6, 6, y - 9, -1, col
        DQuadSide -6, -6, 6, y - 9, y, 0, col
        DQuadSide 6, -6, 6, y - 9, y, 0, col
    End If
End Sub

Private Sub Scene()
    Dim fx As Long, fz As Long, gy As Long, hz As Long, y As Long, f As Long, r As Long, g As Long, b As Long, hh As Long
    fx = A3Sin(camYaw): fz = A3Cos(camYaw)
    cam.x = ShrA(dcX, 16) - ShrA(fx * 170, 16)
    cam.z = ShrA(dcZ, 16) - ShrA(fz * 170, 16)
    cam.y = ShrA(dcY, 16) + 70
    gy = DcRoof(DcBlockAt(cam.x * 65536, cam.z * 65536)) + 20
    If cam.y < gy Then cam.y = gy
    cam.yaw = camYaw
    ' looking down at the ground under the drone (a little beyond it)
    cam.pitch = A3Atan2(cam.y - DcRoof(DcBlockAt(dcX, dcZ)), 300)
    If cam.pitch < 1200 Then cam.pitch = 1200
    If cam.pitch > 9000 Then cam.pitch = 9000
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, 110, 200
    CamSetup cam
    hz = CamHorizon(cam)
    If hz < 1 Then hz = 1
    If hz > G_H - 1 Then hz = G_H - 1
    For y = 0 To hz - 1 Step 8
        f = y
        If f > 120 Then f = 120
        r = (skyTop And 255) + ((skyBottom And 255) - (skyTop And 255)) * f \ 120
        g = ((skyTop \ 256) And 255) + (((skyBottom \ 256) And 255) - ((skyTop \ 256) And 255)) * f \ 120
        b = ((skyTop \ 65536) And 255) + (((skyBottom \ 65536) And 255) - ((skyTop \ 65536) And 255)) * f \ 120
        hh = 8
        If y + hh > hz Then hh = hz - y
        gcv.Box 0, y, G_W, hh, RGB(r, g, b)
    Next y
    gcv.Box 0, hz, G_W, G_H - hz, pen(PEN_GROUND)
    A3Begin 4000
    City
    Beacon
    Drone
    a3QuadBias = 0
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

' ---------- the HUD ----------
Private Sub Hud()
    Dim k As Long, w As Long, b As Long, rel As Long, dx As Long, dz As Long, s As String, p As Long
    Dim cx As Long, cy As Long, wx As Long, wz As Long
    b = DcGoal()
    dx = DcBlockX(b Mod DC_N) - dcX: dz = DcBlockZ(b \ DC_N) - dcZ
    GTextShadow 4, 10, PEN_YELLOW, "DAY " & dcDay & "  " & dcJobsDone & "/" & dcJobs
    For k = 0 To dcFails - 1
        GTextShadow 4 + k * 9, 22, PEN_RED, "X"
    Next k
    If dcJobTime < 250 And (dcTicks And 8) <> 0 Then p = PEN_RED Else p = 1
    GTextBig 4, 26, p, CStr(dcJobTime \ 25), 2
    s = CStr(dcScore)
    GTextShadow G_W - 8 - GTextWidth(s), 10, 3, s
    ' the arrow to the next pad, turned with the view
    rel = A3Atan2(ShrA(dx, 8), ShrA(dz, 8)) - camYaw
    cx = G_W \ 2: cy = 22
    ax3(0) = cx + ShrA(A3Sin(rel) * 14, 16): ay3(0) = cy - ShrA(A3Cos(rel) * 14, 16)
    ax3(1) = cx + ShrA(A3Sin(rel + 26000) * 9, 16): ay3(1) = cy - ShrA(A3Cos(rel + 26000) * 9, 16)
    ax3(2) = cx + ShrA(A3Sin(rel - 26000) * 9, 16): ay3(2) = cy - ShrA(A3Cos(rel - 26000) * 9, 16)
    If dcCarrying Then p = PEN_CUST Else p = PEN_DEPOT
    gcv.Polygon ax3, ay3, 3, pen(p), True
    s = CStr(ShrA(FHypot(dx, dz), 16))
    GTextShadow cx - GTextWidth(s) \ 2, cy + 22, 1, s
    If dcCarrying = 0 Then
        s = "COLLECT"
    ElseIf dcFragile Then
        s = "FRAGILE: DELIVER"
    Else
        s = "DELIVER"
    End If
    GTextShadow (G_W - GTextWidth(s)) \ 2, 58, p, s
    ' the battery
    GTextShadow 4, G_H - 4, 3, "BATT"
    GBox 40, G_H - 12, 122, G_H - 4, 0, 3
    w = (ShrA(dcBattery, 16) * 80) \ 100
    If w > 20 Then p = PEN_GREEN Else p = PEN_RED
    If w > 0 Then GRect 41, G_H - 11, 41 + w, G_H - 5, p
    GTextShadow 140, G_H - 4, 3, "ALT " & ShrA(dcY, 16)
    If dcWindX <> 0 Or dcWindZ <> 0 Or dcGustX <> 0 Then
        wx = ShrA(dcWindX + dcGustX, 9): wz = ShrA(dcWindZ + dcGustZ, 9)
        GTextShadow 230, G_H - 4, 3, "WIND"
        GRect 290, G_H - 9, 290, G_H - 9, 1
        If wx > 0 Then GRect 290, G_H - 9, 290 + wx, G_H - 8, PEN_CYAN Else GRect 290 + wx, G_H - 9, 290, G_H - 8, PEN_CYAN
        If wz > 0 Then GRect 289, G_H - 9 - wz, 290, G_H - 9, PEN_CYAN Else GRect 289, G_H - 9, 290, G_H - 9 - wz, PEN_CYAN
    End If
    If duAutoplay Then GTextShadow G_W - 40, 22, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim p As Long
    Scene
    Hud
    If dcBetween Then
        GTextBigCentre 80, PEN_GREEN, "DAY'S DONE", 2
        If dcDay < DC_DAYS Then GTextCentre 110, 1, "DAY " & (dcDay + 1) & " NEXT"
    End If
    If isOver Then
        If dcWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 50, 80, 270, 160, 2, p
        If dcWon Then GTextBigCentre 88, p, "WEEK'S DONE", 2 Else GTextBigCentre 88, p, "GAME OVER", 2
        If dcBattery = 0 Then GTextCentre 122, PEN_YELLOW, "THE BATTERY WENT FLAT" Else GTextCentre 122, PEN_YELLOW, "DAY " & dcDay & "  " & dcFails & " FAILED"
        GTextCentre 136, 1, "SCORE " & dcScore
        If duStateTimer = 0 Then GTextCentre 152, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 180, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 76, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                                ' the autopilot works behind the title
    GTextBig 68, 26, 0, "DRONE", 6
    GTextBig 66, 24, PEN_YELLOW, "DRONE", 6
    GTextBig 36, 82, 0, "COURIER", 6
    GTextBig 34, 80, PEN_CUST, "COURIER", 6
    GBox 40, 196, 280, 252, 2, 3
    GTextCentre 210, PEN_GREEN, "START ON DAY " & startDay & " (UP/DOWN)"
    If (dcTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 226, p, "PRESS SPACE TO FLY"
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
    GTextCentre 110, 1, "PLACE " & (HsRank(dcScore) + 1) & "   " & Format$(dcScore, "0000000")
    If (dcTicks And 8) = 0 Then cur = "_" Else cur = " "
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
    gcv.Box 0, 64, G_W, 11, pen(0)
    GText 2, 73, PEN_GREEN, PerfText()
End Sub
