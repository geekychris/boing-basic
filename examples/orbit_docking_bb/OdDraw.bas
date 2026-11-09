' OdDraw - Orbit Docking's picture (amiga_mcp's examples/orbit_docking/render.c), from the
' cockpit: the stars, the spinning station (hub, the docking slot with its lights, four arms,
' the ring, solar panels), the approach markers along its axis, debris, and the instruments:
' range, closing rate, where the axis is, the roll against the slot and the fuel. Then the
' title, help, game-over and high-score screens. 320 x 256.
'
' The 3D is Boing.Engine3D: the camera rolls with the craft (Engine3D's roll is render.c's
' cam_roll, the other way round), the station is one model built once and turned about its
' axis by DrawModel's roll, the markers are world quads and the debris camera-space polygons.
Option Explicit

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 space, 5 stars, 6-7 the hub, 8 its face,
' 9 the slot, 10 green lights, 11 red lights, 12-13 arms, 14-15 the ring, 16 markers,
' 17 debris, 18-19 solar panels, 26 red, 27 yellow, 28 green, 29 cyan
Public Const PEN_SPACE As Long = 4
Public Const PEN_STAR As Long = 5
Public Const PEN_HUB As Long = 6
Public Const PEN_FACE As Long = 8
Public Const PEN_SLOT As Long = 9
Public Const PEN_LIGHT As Long = 10
Public Const PEN_RLIGHT As Long = 11
Public Const PEN_ARM As Long = 12
Public Const PEN_RING As Long = 14
Public Const PEN_MARK As Long = 16
Public Const PEN_DEBRIS As Long = 17
Public Const PEN_PANEL As Long = 18
Public Const PEN_RED As Long = 26
Public Const PEN_YELLOW As Long = 27
Public Const PEN_GREEN As Long = 28
Public Const PEN_CYAN As Long = 29

' the screens
Public Const DS_TITLE As Long = 0
Public Const DS_PLAY As Long = 1
Public Const DS_OVER As Long = 2
Public Const DS_ENTRY As Long = 3
Public Const DS_SCORES As Long = 4

' the shell's state the picture shows (dock.h's Dock)
Public dkState As Long, dkStateTimer As Long, dkStartLevel As Long, dkAutoplay As Boolean
Public dkPaused As Long, dkHelp As Long, dkFlash As String, dkFlashTimer As Long, dkFlashPen As Long
Public dkBest As Long, dkEntryRank As Long, dkEntryName As String, dkTicks As Long
Public showPerf As Boolean
Public polyTotal As Double

Public e3 As Object
Private mStation As Long
Private starX(0 To 59) As Long, starY(0 To 59) As Long, starC(0 To 59) As Long
Private px(0 To 59) As Long, py(0 To 59) As Long, pc(0 To 59) As Long
Private dxs(0 To 5) As Long, dys(0 To 5) As Long, dzs(0 To 5) As Long
Private nxs(0 To 2) As Long, nys(0 To 2) As Long
Private helpText(1 To 2, 0 To 11) As String

Public Sub DrawInit(cv As Object)
    Dim v As Variant, i As Long, h As Long
    OdInit
    v = Array(&H0, &HFFF, &H123, &H99A, &H2, &HCCD, &H99A, &H667, &HBBC, &H111, &H3F5, &HF33, _
              &H889, &H556, &HAAB, &H778, &HA8, &H986, &H35A, &H238, &H0, &H0, &H0, &H0, _
              &H0, &H0, &HF33, &HFE4, &H6F6, &H5EF, &H0, &H0)
    GfxPalette v
    Set e3 = CreateObject("Boing.Engine3D")
    e3.Attach cv
    e3.View G_W, G_H, G_W \ 2, G_H \ 2, 230
    e3.Palette12 v
    BuildStation
    ' the stars: fixed points round the view's middle, turned with the roll
    For i = 0 To 59
        h = A3Hash(MulW(i, &H9E3779B1))
        starX(i) = UModL(h, 640) - 320
        starY(i) = UModL(ShrU(h, 10), 640) - 320
        If (i And 3) <> 0 Then starC(i) = pen(PEN_STAR) Else starC(i) = pen(1)
    Next i
    v = Array("DOCK WITH THE SLOT IN THE STATION'S HUB.", "IT SPINS: ROLL TO MATCH IT. WHEN YOU", _
              "TURN WITH IT, THE STATION STANDS STILL.", "", "COME IN ALONG THE AXIS (THE BOX AT THE", _
              "TOP RIGHT), SLOWLY: UNDER 1.6 AT CONTACT.", "THE DIAL: THE SLOT'S ROLL. GREEN IS GOOD.", "", _
              "NO FRICTION IN SPACE: A PUSH LASTS UNTIL", "YOU PUSH BACK. FUEL IS LIMITED.", _
              "FROM STATION 4, DEBRIS DRIFTS ACROSS.", "THREE CRASHES AND IT'S OVER.")
    For i = 0 To 11: helpText(1, i) = v(i): Next i
    v = Array("ARROWS             MOVE ACROSS", "W / SPACE + UP     FORWARD (IN)", _
              "S / SPACE + DOWN   BACK (OUT)", "A / D              ROLL", "SPACE + LEFT/RIGHT ROLL", _
              "P                  PAUSE", "B                  AUTOPILOT", "HELP / H           THESE PAGES", _
              "ESC                TITLE / QUIT", "", "DOCKING: 1000 + 500 x STATION, 2 FOR", _
              "EACH UNIT OF FUEL LEFT, LESS TIME.")
    For i = 0 To 11: helpText(2, i) = v(i): Next i
End Sub

' ---------- the station: one model, built once ----------

Private Function SV(ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    SV = e3.MdlVtx(mStation, x, y, z)
End Function

' a quad of the station (render.c's squad): corners 0, 1 at z0, 2, 3 at z1; it faces away
' from the interior point (ix, iy, iz)
Private Sub SQuad(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long, _
                  ByVal x3 As Long, ByVal y3 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal p As Long, _
                  ByVal ix As Long, ByVal iy As Long, ByVal iz As Long)
    Dim a As Long, b As Long, c As Long, d As Long
    a = SV(x0, y0, z0): b = SV(x1, y1, z0): c = SV(x2, y2, z1): d = SV(x3, y3, z1)
    e3.MdlFace mStation, p, p, 4, a, b, c, d, ix, iy, iz
End Sub

Private Function CS(ByVal a As Long, ByVal r As Long) As Long        ' (cos a * r) >> 16
    CS = ShrA(A3Cos(a) * r, 16)
End Function

Private Function SN(ByVal a As Long, ByVal r As Long) As Long        ' (sin a * r) >> 16
    SN = ShrA(A3Sin(a) * r, 16)
End Function

Private Sub BuildStation()
    Dim k As Long, a0 As Long, a1 As Long, f(0 To 7) As Long, c As Long, s As Long
    Dim ax As Long, ay As Long, bx As Long, by As Long, qx As Long, qy As Long, sg As Long
    mStation = e3.ModelNew()
    ' the hub: eight sides and its face
    For k = 0 To 7
        a0 = k * 8192 + 4096: a1 = a0 + 8192
        SQuad CS(a0, OD_HUB_R), SN(a0, OD_HUB_R), CS(a1, OD_HUB_R), SN(a1, OD_HUB_R), _
              CS(a1, OD_HUB_R), SN(a1, OD_HUB_R), CS(a0, OD_HUB_R), SN(a0, OD_HUB_R), OD_PORT_Z, -300, PEN_HUB + (k And 1), 0, 0, -120
        f(k) = SV(CS(a0, OD_HUB_R), SN(a0, OD_HUB_R), OD_PORT_Z)
    Next k
    e3.MdlFace mStation, PEN_FACE, PEN_FACE, 4, f(0), f(1), f(2), f(3), 0, 0, -120
    e3.MdlFace mStation, PEN_FACE, PEN_FACE, 4, f(0), f(3), f(4), f(7), 0, 0, -120
    e3.MdlFace mStation, PEN_FACE, PEN_FACE, 4, f(4), f(5), f(6), f(7), 0, 0, -120
    ' the slot and its lights
    SQuad -24, -7, 24, -7, 24, 7, -24, 7, OD_PORT_Z + 1, OD_PORT_Z + 1, PEN_SLOT, 0, 0, -120
    SQuad -34, -4, -28, -4, -28, 4, -34, 4, OD_PORT_Z + 1, OD_PORT_Z + 1, PEN_LIGHT, 0, 0, -120
    SQuad 28, -4, 34, -4, 34, 4, 28, 4, OD_PORT_Z + 1, OD_PORT_Z + 1, PEN_LIGHT, 0, 0, -120
    SQuad -3, 30, 3, 30, 3, 36, -3, 36, OD_PORT_Z + 1, OD_PORT_Z + 1, PEN_RLIGHT, 0, 0, -120
    ' four arms, out to the ring
    For k = 0 To 3
        c = A3Cos(k * 16384): s = A3Sin(k * 16384)
        ax = ShrA(c * 60, 16): ay = ShrA(s * 60, 16): bx = ShrA(c * 260, 16): by = ShrA(s * 260, 16)
        qx = ShrA(-s * 10, 16): qy = ShrA(c * 10, 16)
        SQuad ax + qx, ay + qy, bx + qx, by + qy, bx - qx, by - qy, ax - qx, ay - qy, -60, -60, PEN_ARM, 0, 0, -200
        SQuad ax + qx, ay + qy, bx + qx, by + qy, bx + qx, by + qy, ax + qx, ay + qy, -60, -100, PEN_ARM + 1, _
              (ax + bx) \ 2 - qx, (ay + by) \ 2 - qy, -80
    Next k
    ' the ring
    For k = 0 To 15
        a0 = k * 4096: a1 = a0 + 4096
        SQuad CS(a0, 260), SN(a0, 260), CS(a1, 260), SN(a1, 260), CS(a1, 300), SN(a1, 300), CS(a0, 300), SN(a0, 300), _
              -60, -60, PEN_RING + (k And 1), 0, 0, -200
        SQuad CS(a0, 300), SN(a0, 300), CS(a1, 300), SN(a1, 300), CS(a1, 300), SN(a1, 300), CS(a0, 300), SN(a0, 300), _
              -60, -120, PEN_RING + 1, 0, 0, -90
    Next k
    ' solar panels beyond the ring
    For k = 0 To 1
        If k = 0 Then sg = 1 Else sg = -1
        SQuad sg * 310, -40, sg * 470, -40, sg * 470, 40, sg * 310, 40, -90, -90, PEN_PANEL + k, sg * 390, 0, -200
    Next k
End Sub

' ---------- the scene ----------

Private Sub Stars(cv As Object, ByVal rc As Long, ByVal rs As Long)
    Dim k As Long, n As Long, x As Long, y As Long, t As Long
    For k = 0 To 59
        t = starX(k) * rc - starY(k) * rs
        x = G_W \ 2 + (t - (t And 65535)) \ 65536
        t = starX(k) * rs + starY(k) * rc
        y = G_H \ 2 - (t - (t And 65535)) \ 65536
        If x >= 0 And y >= 0 And x < G_W And y < G_H Then
            px(n) = x: py(n) = y: pc(n) = starC(k)
            n = n + 1
        End If
    Next k
    If n > 0 Then cv.PSetMany px, py, pc, n
End Sub

' the approach markers: squares round the axis, standing still
Private Sub Markers()
    Dim k As Long, s As Long, z As Long, h As Long, t As Long, x0 As Long, x1 As Long, y0 As Long, y1 As Long
    h = 34: t = 2
    For k = 0 To 2
        z = Choose(k + 1, 420, 260, 150)
        If z * 65536 < odZ - 20 * 65536 Then
            For s = 0 To 3
                If s = 1 Then x0 = h - t Else x0 = -h
                If s = 3 Then x1 = -h + t Else x1 = h
                If s = 0 Then y0 = h - t Else y0 = -h
                If s = 2 Then y1 = -h + t Else y1 = h
                e3.QuadW -1, PEN_MARK, x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z
            Next s
        End If
    Next k
End Sub

' debris: six-point stars turning in the view, round their middles
Private Sub Debris()
    Dim k As Long, j As Long, x As Long, ang As Long, cx As Long, cy As Long, cz As Long, a As Long, r As Long
    For k = 0 To odNDebris - 1
        x = ShrA(OdDebrisX(k), 16)
        ang = odLevelTicks * 900 + k * 9000
        e3.Xform x, dbY(k), dbZ(k), cx, cy, cz
        If cz >= 12 + 30 Then
            For j = 0 To 5
                a = (ang + j * 10923) And &HFFFF&
                If j And 1 Then r = 14 Else r = 24
                dxs(j) = cx + ShrA(A3Cos(a) * r, 16)
                dys(j) = cy + ShrA(A3Sin(a) * r, 16)
                dzs(j) = cz
            Next j
            e3.Poly cz, PEN_DEBRIS, dxs, dys, dzs, 6
        End If
    Next k
End Sub

Public Sub Scene(cv As Object)
    Dim ra As Long, sa As Long
    ra = ShrA(odRoll, 8) And &HFFFF&
    sa = ShrA(odStAngle, 8) And &HFFFF&
    cv.Cls pen(PEN_SPACE)
    Stars cv, A3Cos(ra), A3Sin(ra)
    e3.CamPos ShrA(odX, 16), ShrA(odY, 16), ShrA(odZ, 16)
    e3.CamAngles &H8000&, 0, (-ra) And &HFFFF&        ' looking back down the axis at the station
    e3.Begin 2500
    e3.DrawModel mStation, 0, 0, 0, 0, 0, sa
    Markers
    Debris
    e3.Flush
    polyTotal = polyTotal + e3.NPolys
End Sub

' ---------- the instruments ----------

Private Function FixedText(ByVal v As Long) As String
    Dim t As Long
    t = ShrA(v * 10, 16)
    If t < 0 Then t = -t
    FixedText = IIf(v < 0, "-", "") & (t \ 10) & "." & (t Mod 10)
End Function

Private Sub Hud(cv As Object)
    Dim k As Long, er As Long, x As Long, y As Long, ok As Boolean, rng As Long, spin As Long, p As Long
    Dim cx As Long, cy As Long, r As Long, a As Long, s As String
    er = OdRollError()
    rng = ShrA(odZ, 16) - (OD_PORT_Z + OD_NOSE)
    spin = ShrA(odRollRate - odStSpin, 8)
    GTextShadow cv, 4, 10, PEN_YELLOW, "STATION " & odLevel
    For k = 0 To odLives - 1
        GRect cv, 4 + k * 10, 15, 10 + k * 10, 19, PEN_CYAN
    Next k
    GTextShadow cv, 4, 34, 1, "RANGE " & rng
    If rng < 150 And -odVZ > OD_TOL_CLOSE Then
        p = PEN_RED
    ElseIf rng < 150 Then
        p = PEN_GREEN
    Else
        p = 1
    End If
    GTextShadow cv, 4, 46, p, "CLOSE " & FixedText(-odVZ)
    GTextShadow cv, 4, 58, 3, CStr(odScore)
    ' where the axis is: the craft's offset from it
    GBox cv, G_W - 52, 4, G_W - 4, 52, 2, 3
    GRect cv, G_W - 28, 6, G_W - 28, 50, 3
    GRect cv, G_W - 50, 28, G_W - 6, 28, 3
    x = G_W - 28 + ShrA(odX, 16) \ 6
    y = 28 - ShrA(odY, 16) \ 6
    ok = FHypot(odX, odY) < OD_TOL_AXIS * 65536
    If x > G_W - 50 And x < G_W - 6 And y > 6 And y < 50 Then GRect cv, x - 2, y - 2, x + 2, y + 2, IIf(ok, PEN_GREEN, PEN_RED)
    GTextShadow cv, G_W - 50, 64, 3, "AXIS"
    ' the roll against the slot: a needle, and how the turn matches
    cx = G_W \ 2: cy = G_H - 30: r = 22
    a = (er * 2) And &HFFFF&             ' the slot repeats every half turn: show it a full turn
    cv.Circle cx, cy, r + 2, pen(3), True
    cv.Circle cx, cy, r, pen(2), True
    GRect cv, cx - 1, cy - r, cx + 1, cy - r + 5, PEN_GREEN
    nxs(0) = cx + ShrA(A3Sin(a) * r, 16): nys(0) = cy - ShrA(A3Cos(a) * r, 16)
    nxs(1) = cx + ShrA(A3Sin((a + 16384) And &HFFFF&) * 3, 16): nys(1) = cy - ShrA(A3Cos((a + 16384) And &HFFFF&) * 3, 16)
    nxs(2) = cx - ShrA(A3Sin((a + 16384) And &HFFFF&) * 3, 16): nys(2) = cy + ShrA(A3Cos((a + 16384) And &HFFFF&) * 3, 16)
    If er < OD_TOL_ROLL And er > -OD_TOL_ROLL Then p = PEN_GREEN Else p = PEN_YELLOW
    cv.Polygon nxs, nys, 3, pen(p), True
    If spin < -20 Then
        s = "<< TURN"
    ElseIf spin > 20 Then
        s = "TURN >>"
    Else
        s = "MATCHED"
    End If
    GTextShadow cv, cx + 30, cy + 4, IIf(spin < 20 And spin > -20, PEN_GREEN, PEN_RED), s
    ' fuel
    GTextShadow cv, 4, G_H - 4, 3, "FUEL"
    GBox cv, 40, G_H - 12, 120, G_H - 4, 0, 3
    If odFuelMax > 0 Then k = Int(CDbl(odFuel) * 78 / odFuelMax) Else k = 0
    If k > 0 Then GRect cv, 41, G_H - 11, 41 + k, G_H - 5, IIf(k > 20, PEN_CYAN, PEN_RED)
    ' the sight
    GRect cv, G_W \ 2 - 12, G_H \ 2, G_W \ 2 - 5, G_H \ 2, PEN_YELLOW
    GRect cv, G_W \ 2 + 5, G_H \ 2, G_W \ 2 + 12, G_H \ 2, PEN_YELLOW
    GRect cv, G_W \ 2, G_H \ 2 - 12, G_W \ 2, G_H \ 2 - 5, PEN_YELLOW
    If dkAutoplay Then GTextShadow cv, G_W - 40, G_H - 4, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(cv As Object)
    Scene cv
    Hud cv
    If odBetween > 0 Then
        GTextBig cv, 96, 80, PEN_GREEN, "DOCKED", 3
        If odLevel < OD_LEVELS Then GTextCentre cv, 120, 1, "STATION " & (odLevel + 1) & " NEXT"
    End If
    If dkState = DS_PLAY And odLevelTicks < 60 And odBetween = 0 Then
        GTextCentre cv, 80, PEN_YELLOW, "STATION " & odLevel & ": DOCK WITH THE SLOT"
    End If
    If dkState = DS_OVER Then
        GBox cv, 50, 80, 270, 160, 2, IIf(odWon <> 0, PEN_GREEN, PEN_RED)
        If odWon <> 0 Then
            GTextBig cv, (G_W - GTextBigWidth(cv, "ALL DOCKED", 2)) \ 2, 88, PEN_GREEN, "ALL DOCKED", 2
        Else
            GTextBig cv, (G_W - GTextBigWidth(cv, "GAME OVER", 2)) \ 2, 88, PEN_RED, "GAME OVER", 2
        End If
        GTextCentre cv, 122, PEN_YELLOW, odDocks & " DOCKED  " & odCrashes & " CRASHED"
        GTextCentre cv, 136, 1, "SCORE " & odScore
        If dkStateTimer = 0 Then GTextCentre cv, 152, PEN_YELLOW, "PRESS FIRE"
    End If
    If dkPaused = 1 Then GTextCentre cv, 160, 1, "PAUSED"
    If dkFlashTimer > 0 And Len(dkFlash) > 0 Then GTextCentre cv, 100, dkFlashPen, dkFlash
End Sub

Public Sub DrawTitle(cv As Object)
    Dim p As Long
    Scene cv                             ' the autopilot docks behind the title
    GTextBig cv, (G_W - GTextBigWidth(cv, "ORBIT", 4)) \ 2 + 2, 18, 0, "ORBIT", 4
    GTextBig cv, (G_W - GTextBigWidth(cv, "ORBIT", 4)) \ 2, 16, PEN_YELLOW, "ORBIT", 4
    GTextBig cv, (G_W - GTextBigWidth(cv, "DOCKING", 4)) \ 2 + 2, 54, 0, "DOCKING", 4
    GTextBig cv, (G_W - GTextBigWidth(cv, "DOCKING", 4)) \ 2, 52, PEN_CYAN, "DOCKING", 4
    GBox cv, 40, 196, 280, 252, 2, 3
    GTextCentre cv, 210, PEN_GREEN, "START AT STATION " & dkStartLevel & " (UP/DOWN)"
    If (odTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre cv, 226, p, "PRESS FIRE TO FLY"
    GTextCentre cv, 242, 3, "BEST " & dkBest & "   HELP: HOW TO PLAY"
End Sub

Public Sub DrawHelp(cv As Object, ByVal page As Long)
    Dim k As Long
    cv.Cls pen(2)
    If page = 1 Then
        GTextBig cv, (G_W - GTextBigWidth(cv, "HOW TO PLAY", 2)) \ 2, 14, PEN_YELLOW, "HOW TO PLAY", 2
    Else
        GTextBig cv, (G_W - GTextBigWidth(cv, "CONTROLS", 2)) \ 2, 14, PEN_YELLOW, "CONTROLS", 2
    End If
    For k = 0 To 11
        GText cv, 8, 58 + k * 14, 1, helpText(page, k)
    Next k
    GText cv, 8, 242, 3, "PAGE " & page & " OF 2"
    GText cv, 156, 242, PEN_YELLOW, "HELP: NEXT  FIRE: PLAY"
End Sub

Public Sub DrawEntry(cv As Object)
    Dim cur As String
    DrawGame cv
    GBox cv, 40, 70, 280, 180, 2, PEN_YELLOW
    GTextCentre cv, 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre cv, 110, 1, "PLACE " & (HsRank(odScore) + 1) & "   " & odScore
    If (dkTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre cv, 140, PEN_GREEN, "YOUR NAME: " & dkEntryName & cur
    GTextCentre cv, 166, 3, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores(cv As Object)
    Dim i As Long, p As Long
    Scene cv
    GBox cv, 50, 36, 270, 200, 2, 3
    GTextBig cv, (G_W - GTextBigWidth(cv, "HIGH SCORES", 2)) \ 2, 44, PEN_YELLOW, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = dkEntryRank Then p = PEN_GREEN Else p = 1
        GTextCentre cv, 86 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf(cv As Object)
    cv.Box 0, 226, G_W, 11, pen(0)
    GText cv, 2, 235, PEN_GREEN, PerfText()
End Sub
