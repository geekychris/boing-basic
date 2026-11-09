' Sphere Siege - the picture (a port of render.c) and the shell's effects (game.c).
' The camera sits just behind and above the ship and looks through the centre of
' the sphere, so it turns with the ship's frame: camera space is worked out here
' from the frame, in quarter units, and A3Scene projects and sorts it. Behind
' everything a starfield; the shell as a dotted grid of latitude rings and
' meridians, brighter near the camera; the line of fire; the vortex at the centre;
' enemies as spinning shapes facing the camera; shots, bullets and bursts; the ship.
' HUD: score, best, wave, ships left and the radar.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startWave As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public duHurtTimer As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean
Public gridDetail As Long          ' 0 no grid, 1 every other dot, 2 every dot (the original; the default)

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 space, 5-6 stars, 7-9 the grid far to
' near, 10-11 the vortex, 12-14 the ship, 15 its engine, 16-17 darts, 18-19 weavers,
' 20-21 orbiters, 22 wardens, 23 fire, 24 shots, 25 bullets, 26 red, 27 yellow,
' 28 green, 29 cyan, 30 a hurt warden, 31 the line of fire
Private Const PEN_SPACE As Long = 4
Private Const PEN_STAR As Long = 5
Private Const PEN_GRID As Long = 7
Private Const PEN_CORE As Long = 10
Private Const PEN_SHIP As Long = 12
Private Const PEN_ENGINE As Long = 15
Private Const PEN_DART As Long = 16
Private Const PEN_WEAVER As Long = 18
Private Const PEN_ORB As Long = 20
Private Const PEN_WARDEN As Long = 22
Private Const PEN_FIRE As Long = 23
Private Const PEN_SHOT As Long = 24
Private Const PEN_BUL As Long = 25
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const PEN_WHURT As Long = 30
Private Const PEN_SIGHT As Long = 31

Private Const CAM_BACK As Long = 190
Private Const CAM_LIFT As Long = 80
Private Const FOV As Long = 190
Private Const NGRID As Long = 2688       ' 11 rings x 120 + 24 meridians x 57
Private Const NSTARS As Long = 140

Private cam As A3Cam
Private cR As FV, cU As FV, cF As FV
Private cpx As Long, cpy As Long, cpz As Long
Private cpfx As Long, cpfy As Long, cpfz As Long
Private gX(0 To 2687) As Long, gY(0 To 2687) As Long, gZ(0 To 2687) As Long
Private sX(0 To 139) As Long, sY(0 To 139) As Long, sZ(0 To 139) As Long, sPen(0 To 139) As Long
Private dotX(0 To 2799) As Long, dotY(0 To 2799) As Long, dotC(0 To 2799) As Long
Private nDots As Long
Private nearX(0 To 2799) As Long, nearY(0 To 2799) As Long, nearC(0 To 2799) As Long, nNear As Long
Private qx As Long, qy As Long, qz As Long          ' xf's result
Private px As Long, py As Long                      ' Proj's result

Private Const MAX_BURSTS As Long = 16
Private bT(0 To 15) As Long, bSize(0 To 15) As Long, bX(0 To 15) As Long, bY(0 To 15) As Long, bZ(0 To 15) As Long

Private shipV(0 To 23) As Long, shipF(0 To 31) As Long
Private shX(0 To 7) As Long, shY(0 To 7) As Long, shZ(0 To 7) As Long
Private helpText(1 To 2, 0 To 11) As String
Private spaceTop As Long, spaceBottom As Long

Public Sub DrawInit()
    Dim i As Long, j As Long, n As Long, s As Long, lat As Long, lon As Long, cl As Long, sl As Long
    Dim x As Long, y As Long, z As Long, l As Long, h As Variant, v As Variant
    GfxPalette Array(&H0, &HFFF, &H123, &H99A, &H13, &H557, &HCCE, &H47C, &H6AE, &HAEF, &H82C, &HD7F, _
                     &HDDE, &H99B, &H557, &H4CF, &HF92, &HFE6, &H3E8, &HBFD, &HE4C, &HFBE, &HC33, &HFA3, _
                     &H9FF, &HF65, &HF33, &HFE4, &H6F6, &H5EF, &H822, &H58A)
    spaceTop = Rgb12(&H13)
    spaceBottom = Rgb12(&H103)
    If gridDetail = 0 Then gridDetail = 2
    For i = 0 To 10
        lat = ((i - 5) * 65536) \ 24
        cl = A3Cos(lat): sl = A3Sin(lat)
        For j = 0 To 119
            lon = (j * 65536) \ 120
            gX(n) = ShrA(ShrA(cl * SS_R, 16) * A3Cos(lon), 16)
            gY(n) = ShrA(sl * SS_R, 16)
            gZ(n) = ShrA(ShrA(cl * SS_R, 16) * A3Sin(lon), 16)
            n = n + 1
        Next j
    Next i
    For i = 0 To 23
        lon = (i * 65536) \ 24
        For j = 0 To 56
            lat = ((j - 28) * 65536) \ 120
            cl = A3Cos(lat): sl = A3Sin(lat)
            gX(n) = ShrA(ShrA(cl * SS_R, 16) * A3Cos(lon), 16)
            gY(n) = ShrA(sl * SS_R, 16)
            gZ(n) = ShrA(ShrA(cl * SS_R, 16) * A3Sin(lon), 16)
            n = n + 1
        Next j
    Next i
    s = 4242
    For i = 0 To NSTARS - 1
        Do
            x = A3Rand(s) - 16384: y = A3Rand(s) - 16384: z = A3Rand(s) - 16384
            l = ISqrtD(CDbl(x) * x + CDbl(y) * y + CDbl(z) * z)
        Loop While l < 4000 Or l > 16384
        sX(i) = (x * 16384) \ l: sY(i) = (y * 16384) \ l: sZ(i) = (z * 16384) \ l
        If A3Rand(s) Mod 5 = 0 Then sPen(i) = PEN_STAR + 1 Else sPen(i) = PEN_STAR
    Next i
    v = Array(0, 4, 60, -48, -2, -12, 48, -2, -12, 0, 0, -20, 0, 17, -2, -50, 12, -16, 50, 12, -16, 0, -6, 0)
    For i = 0 To 23
        shipV(i) = v(i)
    Next i
    v = Array(0, 1, 4, PEN_SHIP, 0, 4, 2, PEN_SHIP + 1, 1, 3, 4, PEN_SHIP + 2, 4, 3, 2, PEN_SHIP + 1, _
              1, 5, 3, PEN_RED, 2, 3, 6, PEN_RED, 0, 7, 1, PEN_SHIP + 2, 0, 2, 7, PEN_SHIP + 2)
    For i = 0 To 31
        shipF(i) = v(i)
    Next i
    h = Array("YOUR SHIP RIDES THE INSIDE OF A HOLLOW", "SPHERE, ALWAYS FACING ITS CENTRE.", _
              "SHOTS CROSS THE CENTRE: THEY HIT WHAT", "IS ON THE LINE ON EITHER SIDE OF IT.", "", _
              " DARTS     SPIRAL OUT AND SWOOP AT YOU", " WEAVERS   SWOOP AND SHOOT", _
              " ORBITERS  RUN ALONG THE SHELL", " WARDENS   EVERY 4TH WAVE: 3 HITS", "", _
              "THE RADAR SHOWS ENEMIES ON YOUR SIDE", "OF THE CENTRE IN RED.", _
              "ARROWS / WASD     SLIDE OVER THE SHELL", "SPACE             FIRE (HOLD)", _
              "P                 PAUSE", "B                 AUTOPILOT", "G                 THE GRID: DOTS", _
              "HELP / H          THESE PAGES", "ESC               TITLE / QUIT", _
              "DART 100, WEAVER 150, ORBITER 200,", "WARDEN 400, +10 A WAVE. WAVE CLEAR:", _
              "500 x THE WAVE. A SHIP EVERY 25000.", "", "LEAD THE ONES ON THE FAR SIDE.")
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
    duFlashTimer = 0
    duHurtTimer = 0
End Sub

Private Sub AddBurst(p As FV, ByVal size As Long)
    Dim k As Long
    For k = 0 To MAX_BURSTS - 1
        If bT(k) <= 0 Then
            bT(k) = 12
            bX(k) = ShrA(p.x, 16): bY(k) = ShrA(p.y, 16): bZ(k) = ShrA(p.z, 16)
            bSize(k) = size
            Exit Sub
        End If
    Next k
End Sub

Private Sub Flash(ByVal s As String, ByVal pp As Long)
    duFlash = s
    duFlashTimer = 35
    duFlashPen = pp
End Sub

Public Sub HandleEvents(ByVal loud As Boolean)
    Dim i As Long, p As FV
    For i = 0 To ssNEv - 1
        Select Case ssEv(i).etype
            Case SSE_KILL
                SsEnemyPos ssEv(i).a, p
                If ssEv(i).b = EN_WARDEN Then AddBurst p, 70 Else AddBurst p, 45
            Case SSE_HIT
                SsEnemyPos ssEv(i).a, p
                AddBurst p, 25
            Case SSE_HURT
                SsShipPos p
                AddBurst p, 60
                If loud Then duHurtTimer = 8
        End Select
        If loud Then
            Select Case ssEv(i).etype
                Case SSE_SHOT: Sfx SFX_SHOT
                Case SSE_KILL: Sfx SFX_BOOM
                Case SSE_HIT: Sfx SFX_HIT
                Case SSE_EFIRE: Sfx SFX_EFIRE
                Case SSE_SWOOP: Sfx SFX_SWOOP
                Case SSE_HURT: Sfx SFX_HURT
                Case SSE_WAVE: Sfx SFX_WAVE
                Case SSE_CLEAR: Sfx SFX_CLEAR
                Case SSE_OVER: Sfx SFX_OVER
                Case SSE_LIFE
                    Sfx SFX_LIFE
                    Flash "EXTRA SHIP", 28
            End Select
        End If
    Next i
    ssNEv = 0
End Sub

Public Sub AgeEffects()
    Dim k As Long
    For k = 0 To MAX_BURSTS - 1
        If bT(k) > 0 Then bT(k) = bT(k) - 1
    Next k
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
    If duHurtTimer > 0 Then duHurtTimer = duHurtTimer - 1
End Sub

' ---------- the camera ----------
Private Sub Camera()
    Dim ship As FV
    SsShipPos ship
    cpfx = ship.x - ssF.x * CAM_BACK + ssU.x * CAM_LIFT
    cpfy = ship.y - ssF.y * CAM_BACK + ssU.y * CAM_LIFT
    cpfz = ship.z - ssF.z * CAM_BACK + ssU.z * CAM_LIFT
    cpx = ShrA(cpfx, 16): cpy = ShrA(cpfy, 16): cpz = ShrA(cpfz, 16)
    cF.x = -cpfx: cF.y = -cpfy: cF.z = -cpfz
    FvNorm cF
    cR = ssR
    FvCross cF, cR, cU
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, G_H \ 2, FOV
End Sub

' a 16.16 world point to camera space (quarter units): qx, qy, qz
Private Sub Xf(ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Dim v As FV
    v.x = x - cpfx: v.y = y - cpfy: v.z = z - cpfz
    qx = ShrA(FvDot(v, cR), 14)
    qy = ShrA(FvDot(v, cU), 14)
    qz = ShrA(FvDot(v, cF), 14)
End Sub

' whole units, fast (the grid)
Private Sub Xfi(ByVal x As Long, ByVal y As Long, ByVal z As Long)
    x = x - cpx: y = y - cpy: z = z - cpz
    qx = ShrA(x * cR.x + y * cR.y + z * cR.z, 14)
    qy = ShrA(x * cU.x + y * cU.y + z * cU.z, 14)
    qz = ShrA(x * cF.x + y * cF.y + z * cF.z, 14)
End Sub

' qx, qy, qz to the screen (px, py); False when behind or off the picture
Private Function Proj() As Boolean
    If qz < NEAR_Z * 4 Then Exit Function
    px = G_W \ 2 + (qx * FOV) \ qz
    py = G_H \ 2 - (qy * FOV) \ qz
    Proj = px >= 0 And px < G_W And py >= 0 And py < G_H
End Function

Private Sub AddDot(ByVal c As Long)
    dotX(nDots) = px: dotY(nDots) = py: dotC(nDots) = c
    nDots = nDots + 1
End Sub

' ---------- the backdrop: stars and the shell ----------
Private Sub StarsAndShell()
    Dim i As Long, x As Long, y As Long, z As Long, stp As Long, c7 As Long, c8 As Long, c9 As Long
    Dim rx As Long, ry As Long, rz As Long, ux As Long, uy As Long, uz As Long, fx As Long, fy As Long, fz As Long
    Dim t As Long, scx As Long, scy As Long
    nDots = 0
    For i = 0 To NSTARS - 1
        x = sX(i): y = sY(i): z = sZ(i)
        qz = Int((CDbl(x) * cF.x + CDbl(y) * cF.y + CDbl(z) * cF.z) / 65536#)
        If qz >= 2000 Then
            qx = Int((CDbl(x) * cR.x + CDbl(y) * cR.y + CDbl(z) * cR.z) / 65536#)
            qy = Int((CDbl(x) * cU.x + CDbl(y) * cU.y + CDbl(z) * cU.z) / 65536#)
            If Proj() Then AddDot pen(sPen(i))
        End If
    Next i
    If nDots > 0 Then gcv.PSetMany dotX, dotY, dotC, nDots
    If gridDetail = 0 Then Exit Sub
    ' far dots 1 pixel (from the start of the arrays), nearer ones 2 x 2 (from the end)
    nDots = 0
    nNear = 0
    stp = 3 - gridDetail
    c7 = pen(PEN_GRID): c8 = pen(PEN_GRID + 1): c9 = pen(PEN_GRID + 2)
    rx = cR.x: ry = cR.y: rz = cR.z: ux = cU.x: uy = cU.y: uz = cU.z: fx = cF.x: fy = cF.y: fz = cF.z
    For i = 0 To NGRID - 1 Step stp
        ' Xfi and Proj written out (calls cost in the VM)
        x = gX(i) - cpx: y = gY(i) - cpy: z = gZ(i) - cpz
        t = x * fx + y * fy + z * fz
        qz = (t - (t And 16383)) \ 16384
        If qz >= 300 Then
            t = x * rx + y * ry + z * rz
            scx = G_W \ 2 + (((t - (t And 16383)) \ 16384) * FOV) \ qz
            If scx >= 0 And scx < G_W Then
                t = x * ux + y * uy + z * uz
                scy = G_H \ 2 - (((t - (t And 16383)) \ 16384) * FOV) \ qz
                If scy >= 0 And scy < G_H Then
                    If qz > 6400 Then
                        dotX(nDots) = scx: dotY(nDots) = scy: dotC(nDots) = c7
                        nDots = nDots + 1
                    Else
                        nearX(nNear) = scx: nearY(nNear) = scy
                        If qz > 3600 Then nearC(nNear) = c8 Else nearC(nNear) = c9
                        nNear = nNear + 1
                    End If
                End If
            End If
        End If
    Next i
    If nDots > 0 Then gcv.PSetMany dotX, dotY, dotC, nDots
    If nNear > 0 Then gcv.PSetMany nearX, nearY, nearC, nNear, 2
End Sub

' the line of fire: from the ship through the centre
Private Sub FireLine()
    Dim t As Long, s As FV
    SsShipPos s
    For t = 160 To 2 * SS_R - 61 Step 90
        If Not (t > SS_R - 70 And t < SS_R + 70) Then
            Xf s.x + ssF.x * t, s.y + ssF.y * t, s.z + ssF.z * t
            If Proj() Then gcv.PSet px, py, pen(PEN_SIGHT)
        End If
    Next t
End Sub

' ---------- 3D ----------
' a flat shape facing the camera: n points round (cx, cy, cz), radius r (quarter
' units) at angle a + k * 65536 / n, alternate points at r * inner / 256
Private Sub Shape(ByVal cx As Long, ByVal cy As Long, ByVal cz As Long, ByVal n As Long, ByVal r As Long, _
                  ByVal inner As Long, ByVal a As Long, ByVal pp As Long, ByVal bias As Long)
    Dim k As Long, ang As Long, rr As Long
    If cz < NEAR_Z * 4 + r \ 2 Then Exit Sub
    If n > 8 Then n = 8
    For k = 0 To n - 1
        ang = a + (k * 65536) \ n
        If k And 1 Then rr = (r * inner) \ 256 Else rr = r
        pvx(k) = cx + ShrA(A3Sin(ang) * rr, 16)
        pvy(k) = cy + ShrA(A3Cos(ang) * rr, 16)
        pvz(k) = cz
    Next k
    A3Poly cam, cz + bias, pp, n
End Sub

Private Sub Vortex()
    Dim r As Long
    r = (55 + ShrA(A3Sin(ssTicks * 2600) * 15, 16)) * 4
    Xf 0, 0, 0
    Shape qx, qy, qz, 8, r, 140, ssTicks * 900, PEN_CORE, 40
    Shape qx, qy, qz, 8, r \ 2, 120, -ssTicks * 1500, PEN_CORE + 1, 39
End Sub

Private Sub Enemies()
    Dim k As Long, p As FV, spin As Long, r As Long, pp As Long
    For k = 0 To ssNEn - 1
        If en(k).phase <> PH_WAIT And en(k).phase <> PH_DEAD Then
            spin = ssTicks * 1400 + k * 5000
            SsEnemyPos k, p
            Xf p.x, p.y, p.z
            If qz >= 200 Then
                If en(k).r < SS_SAFE_R * FONE Then            ' still warping in
                    r = (ShrA(en(k).r, 16) * 4) \ 3 + 30
                    If (ssTicks + k) And 2 Then pp = 1 Else pp = PEN_CYAN
                    Shape qx, qy, qz, 8, r, 70, spin, pp, 0
                Else
                    Select Case en(k).etype
                        Case EN_DART
                            Shape qx, qy, qz, 4, 150, 140, spin, PEN_DART, 0
                            Shape qx, qy, qz, 4, 60, 256, -spin, PEN_DART + 1, -2
                        Case EN_WEAVER
                            Shape qx, qy, qz, 6, 140, 256, spin \ 2, PEN_WEAVER, 0
                            Shape qx, qy, qz, 6, 120, 90, spin, PEN_WEAVER + 1, -2
                        Case EN_ORBITER
                            Shape qx, qy, qz, 8, 150, 170, spin \ 3, PEN_ORB, 0
                            Shape qx, qy, qz, 4, 70, 256, -spin, PEN_ORB + 1, -2
                        Case Else
                            If en(k).hp >= 3 Then pp = PEN_WARDEN Else pp = PEN_WHURT
                            Shape qx, qy, qz, 8, 200, 256, spin \ 4, pp, 0
                            Shape qx, qy, qz, 4, 150, 60, -spin \ 2, PEN_FIRE, -2
                            If en(k).hp >= 2 Then pp = PEN_YELLOW Else pp = PEN_RED
                            Shape qx, qy, qz, 4, 60, 256, spin, pp, -4
                    End Select
                End If
            End If
        End If
    Next k
End Sub

Private Sub Movers()
    Dim k As Long, pp As Long
    For k = 0 To SS_MAX_SHOTS - 1
        If shot(k).alive Then
            Xf shot(k).p.x, shot(k).p.y, shot(k).p.z
            Shape qx, qy, qz, 4, 64, 120, 0, PEN_SHOT, 0
            Xf shot(k).p.x - shot(k).v.x \ 2, shot(k).p.y - shot(k).v.y \ 2, shot(k).p.z - shot(k).v.z \ 2
            Shape qx, qy, qz, 4, 36, 120, 0, PEN_CYAN, 1
        End If
    Next k
    For k = 0 To SS_MAX_BUL - 1
        If bul(k).alive Then
            Xf bul(k).p.x, bul(k).p.y, bul(k).p.z
            Shape qx, qy, qz, 6, 64, 256, ssTicks * 3000, PEN_BUL, 0
            Shape qx, qy, qz, 4, 28, 256, 0, PEN_YELLOW, -1
        End If
    Next k
    For k = 0 To MAX_BURSTS - 1
        If bT(k) > 0 Then
            Xfi bX(k), bY(k), bZ(k)
            If bT(k) > 7 Then
                pp = PEN_YELLOW
            ElseIf bT(k) > 3 Then
                pp = PEN_FIRE
            Else
                pp = PEN_RED
            End If
            Shape qx, qy, qz, 8, (bSize(k) * 4 * (14 - bT(k))) \ 10, 110, bT(k) * 1700, pp, -6
        End If
    Next k
End Sub

' the ship: a delta in its own frame (x along R, y along U, z along F)
Private Sub ShipPt(s As FV, ByVal x As Long, ByVal y As Long, ByVal z As Long)
    x = (x * 3) \ 4: y = (y * 3) \ 4: z = (z * 3) \ 4
    Xf s.x + ssR.x * x + ssU.x * y + ssF.x * z, s.y + ssR.y * x + ssU.y * y + ssF.y * z, s.z + ssR.z * x + ssU.z * y + ssF.z * z
End Sub

Private Sub DrawShip()
    Dim s As FV, k As Long, i As Long, j As Long
    If ssInvuln > 0 And (ssInvuln And 4) <> 0 Then Exit Sub
    SsShipPos s
    For k = 0 To 7
        ShipPt s, shipV(k * 3), shipV(k * 3 + 1), shipV(k * 3 + 2)
        shX(k) = qx: shY(k) = qy: shZ(k) = qz
    Next k
    For k = 0 To 7
        For j = 0 To 2
            i = shipF(k * 4 + j)
            pvx(j) = shX(i): pvy(j) = shY(i): pvz(j) = shZ(i)
        Next j
        A3Poly cam, (pvz(0) + pvz(1) + pvz(2)) \ 3 - 200, shipF(k * 4 + 3), 3
    Next k
    ShipPt s, 0, 2, -24
    Shape qx, qy, qz, 6, 14 + (ssTicks And 3) * 4, 160, ssTicks * 4000, PEN_ENGINE, -240
End Sub

Private Sub SpaceBands()
    Dim y As Long, r As Long, g As Long, b As Long
    For y = 0 To G_H - 1 Step 16
        r = (spaceTop And 255) + ((spaceBottom And 255) - (spaceTop And 255)) * y \ G_H
        g = ((spaceTop \ 256) And 255) + (((spaceBottom \ 256) And 255) - ((spaceTop \ 256) And 255)) * y \ G_H
        b = ((spaceTop \ 65536) And 255) + (((spaceBottom \ 65536) And 255) - ((spaceTop \ 65536) And 255)) * y \ G_H
        gcv.Box 0, y, G_W, 16, RGB(r, g, b)
    Next y
End Sub

Private Sub Scene(ByVal showLine As Boolean)
    Camera
    SpaceBands
    StarsAndShell
    If showLine Then FireLine
    A3Begin 12000
    Vortex
    Enemies
    Movers
    If ssOver = 0 Then DrawShip
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

' ---------- the HUD ----------
Private Sub Radar()
    Dim k As Long, x As Long, y As Long, z As Long, rx As Long, ry As Long, pp As Long
    Const RX0 As Long = 286
    Const RY0 As Long = 222
    Const RR As Long = 28
    gcv.Circle RX0, RY0, RR + 2, pen(3), True
    gcv.Circle RX0, RY0, RR, pen(2), True
    GRect RX0 - RR + 3, RY0, RX0 + RR - 3, RY0, PEN_GRID + 1
    GRect RX0, RY0 - RR + 3, RX0, RY0 + RR - 3, PEN_GRID + 1
    For k = 0 To ssNEn - 1
        If en(k).phase <> PH_WAIT And en(k).phase <> PH_DEAD Then
            SsLocal en(k).d, x, y, z
            rx = RX0 + ShrA(x * (RR - 2), 16)
            ry = RY0 - ShrA(y * (RR - 2), 16)
            If z < 0 Then
                If en(k).phase = PH_SWOOP Then pp = PEN_YELLOW Else pp = PEN_RED
                GRect rx - 1, ry - 1, rx + 1, ry + 1, pp
            Else
                GRect rx, ry, rx, ry, PEN_GREEN
            End If
        End If
    Next k
    GRect RX0 - 1, RY0 - 1, RX0 + 1, RY0 + 1, 1
End Sub

Private Sub Hud()
    Dim k As Long, best As Long, s As String, pp As Long
    Static lx(0 To 2) As Long, ly(0 To 2) As Long
    GTextShadow 4, 10, 1, CStr(ssScore)
    best = hsScore(0)
    If ssScore > best Then best = ssScore
    GTextCentre 10, 3, "HI " & best
    s = "WAVE " & ssWave
    If ssSiege Then pp = PEN_RED Else pp = PEN_YELLOW
    GTextShadow G_W - 4 - GTextWidth(s), 10, pp, s
    For k = 0 To ssLives - 2
        If k >= 8 Then Exit For
        lx(0) = 8 + k * 14: lx(1) = 14 + k * 14: lx(2) = 20 + k * 14
        ly(0) = G_H - 6: ly(1) = G_H - 16: ly(2) = G_H - 6
        gcv.Polygon lx, ly, 3, pen(PEN_SHIP), True
    Next k
    Radar
    If duAutoplay Then GTextShadow G_W - 104, G_H - 4, PEN_GREEN, "AUTO"
    If duHurtTimer > 0 Then
        GRect 0, 0, G_W - 1, 3, PEN_RED
        GRect 0, G_H - 4, G_W - 1, G_H - 1, PEN_RED
        GRect 0, 0, 3, G_H - 1, PEN_RED
        GRect G_W - 4, 0, G_W - 1, G_H - 1, PEN_RED
    End If
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim pct As Long, pp As Long, s As String
    Scene True
    Hud
    If ssBetween > 0 And ssBetween < SS_BETWEEN - 10 And ssOver = 0 Then
        GTextBigCentre 70, PEN_GREEN, "WAVE CLEAR", 2
        GTextCentre 104, 1, "BONUS " & (500 * ssWave)
        If (ssWave + 1) Mod SS_SIEGE = 0 Then GTextCentre 120, PEN_RED, "NEXT: A SIEGE WAVE"
    ElseIf ssWaveTick < 50 And ssBetween = 0 Then
        If ssSiege Then
            s = "SIEGE WAVE " & ssWave
            pp = PEN_RED
        Else
            s = "WAVE " & ssWave
            pp = PEN_YELLOW
        End If
        GTextBigCentre 70, pp, s, 2
        If ssSiege Then GTextCentre 104, 1, "WARDENS TAKE THREE HITS"
    End If
    If isOver Then
        GBox 50, 80, 270, 168, 2, PEN_RED
        GTextBigCentre 88, PEN_RED, "GAME OVER", 2
        If ssShots Then pct = (ssHits * 100) \ ssShots
        GTextCentre 122, PEN_YELLOW, "WAVE " & ssWave & "   " & pct & "% HITS"
        GTextCentre 136, 1, "SCORE " & ssScore
        If duStateTimer = 0 Then GTextCentre 158, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 180, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 44, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim pp As Long
    Scene False                       ' the autopilot plays behind the title
    GTextBigCentre 26, 0, "SPHERE", 6
    GTextBig (G_W - GTextBigWidth("SPHERE", 6)) \ 2 - 2, 24, PEN_CYAN, "SPHERE", 6
    GTextBigCentre 86, 0, "SIEGE", 6
    GTextBig (G_W - GTextBigWidth("SIEGE", 6)) \ 2 - 2, 84, PEN_CORE + 1, "SIEGE", 6
    GBox 40, 186, 280, 252, 2, 3
    GTextCentre 200, PEN_GREEN, "START AT WAVE " & startWave & " (UP/DOWN)"
    If (ssTicks \ 12) And 1 Then pp = PEN_YELLOW Else pp = 1
    GTextCentre 216, pp, "PRESS SPACE TO PLAY"
    GTextCentre 232, 1, "HIGH SCORE " & hsScore(0)
    GTextCentre 246, 3, "HELP: HOW TO PLAY"
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
    Scene False
    GBox 40, 70, 280, 180, 2, PEN_YELLOW
    GTextCentre 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre 110, 1, "PLACE " & (HsRank(ssScore) + 1) & "   " & Format$(ssScore, "0000000")
    If (ssTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre 140, PEN_GREEN, "YOUR NAME: " & nm & cur
    GTextCentre 166, 3, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores()
    Dim i As Long, pp As Long
    Scene False
    GBox 50, 36, 270, 200, 2, 3
    GTextBigCentre 44, PEN_YELLOW, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = entryRank Then pp = PEN_GREEN Else pp = 1
        GTextCentre 86 + i * 14, pp, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf()
    gcv.Box 0, 22, G_W, 11, pen(0)
    GText 2, 31, PEN_GREEN, PerfText()
End Sub
