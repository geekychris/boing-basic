' Harbour Crane - the picture (a port of render.c) and the shell's effects (game.c): the sky
' and the far shore, the sea, the quay with the containers waiting on it, the gantry crane
' with its trolley, cable and hook, the ship (rolled by her heel and lifted by the swell)
' with what is loaded on her, the container on the hook (swung with the cable) or on its way
' down, and the score line with the list gauge and the wind. Title, help, high scores.
Option Explicit

Public duState As Long, duStateTimer As Long
Public startLevel As Long, duAutoplay As Boolean, duPaused As Boolean, duHelp As Long
Public duFlash As String, duFlashTimer As Long, duFlashPen As Long
Public splashTimer As Long, splashX As Long
Public entryRank As Long
Public polyTotal As Double
Public showPerf As Boolean

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5-6 the sea, 7 the far shore, 8-9 the
' quay, 10-11 the crane, 12-13 the hull, 14 the deck, 15 the bridge, 16 the cable, 17-24
' containers by weight (lit, shaded), 25 windows, 26 red, 27 yellow, 28 green, 29 cyan,
' 30 shadow, 31 foam
Private Const PEN_SKY As Long = 4
Private Const PEN_SEA As Long = 5
Private Const PEN_SHORE As Long = 7
Private Const PEN_QUAY As Long = 8
Private Const PEN_CRANE As Long = 10
Private Const PEN_HULL As Long = 12
Private Const PEN_DECK As Long = 14
Private Const PEN_BRIDGE As Long = 15
Private Const PEN_CABLE As Long = 16
Private Const PEN_BOX As Long = 17
Private Const PEN_WINDOW As Long = 25
Private Const PEN_RED As Long = 26
Private Const PEN_YELLOW As Long = 27
Private Const PEN_GREEN As Long = 28
Private Const PEN_CYAN As Long = 29
Private Const PEN_FOAM As Long = 31
Private Const BOX_Z As Long = 20

Private cam As A3Cam
' how a part of the scene is placed: 0 the world, 1 the ship (rolled about the pivot by heel
' and lifted by bob), 2 swung about (xfPx, xfPy) by th
Private xfMode As Long, xfC As Long, xfS As Long, xfPx As Long, xfPy As Long, xfBob As Long
Private ptX As Long, ptY As Long                  ' Pt's result
Private qx(0 To 3) As Long, qy(0 To 3) As Long
Private helpText(1 To 2, 0 To 11) As String
Private skyTop As Long, skyBottom As Long

Public Sub DrawInit()
    Dim h As Variant, i As Long
    GfxPalette Array(&H0, &HFFF, &H123, &H99A, &H7AD, &H236, &H358, &H576, &HBBA, &H776, _
                     &HFC2, &HA81, &H23A, &H125, &H733, &HEED, &H333, _
                     &H5C5, &H383, &H48E, &H259, &HF93, &HB52, &HE44, &H922, _
                     &H6CE, &HF33, &HFE4, &H6F6, &H5EF, &H112, &HDEF)
    skyTop = Rgb12(&H48C)
    skyBottom = Rgb12(&HBDE)
    h = Array("LIFT EACH CONTAINER OFF THE QUAY AND", "LAND IT ON THE SHIP. WHAT HANGS ON THE", _
              "HOOK SWINGS: START AND STOP SMOOTHLY,", "AND LET THE SWING DIE BEFORE YOU LAND.", _
              "LET GO LOW: DROPPED FROM HIGH IT DENTS.", "LAND SQUARE IN A SLOT; LONG ONES NEED", _
              "TWO STACKS THE SAME HEIGHT. FOUR HIGH.", "", "KEEP HER LEVEL: HEAVY BOXES ON ONE SIDE", _
              "LIST THE SHIP, HIGH STACKS ROLL HER", "MORE. TOO FAR AND SHE CAPSIZES.", _
              "GREEN 1T  BLUE 2T  ORANGE 3T  RED 4T", _
              "LEFT / RIGHT     MOVE THE TROLLEY", "UP / DOWN        WINCH IN / OUT", "SPACE            GRAB / LET GO", _
              "P                PAUSE", "B                AUTOPILOT", "HELP / H         THESE PAGES", _
              "ESC              TITLE / QUIT", "", "50 x WEIGHT A CONTAINER, -40 DENTED,", _
              "-100 LOST (3 LOST ENDS THE GAME).", "BONUS FOR TIME LEFT, AND 200 FOR", "SENDING HER OFF ON AN EVEN KEEL.")
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
    Dim i As Long, e As Long
    For i = 0 To hcNEv - 1
        e = hcEv(i).etype
        If e = HCE_LOST Or (e = HCE_SPLASH And hcEv(i).a = 1) Then
            splashTimer = 20
            splashX = ShrA(hcFX, 16) + 24
        End If
        If loud Then
            Select Case e
                Case HCE_GRAB: Sfx SFX_GRAB
                Case HCE_RELEASE: Sfx SFX_RELEASE
                Case HCE_LAND: Sfx SFX_LAND
                Case HCE_DENT
                    Sfx SFX_DENT
                    Flash "DENTED!", 26
                Case HCE_LOST
                    Sfx SFX_LOST
                    Flash "LOST IN THE HARBOUR", 26
                Case HCE_BUMP: Sfx SFX_BUMP
                Case HCE_SPLASH: Sfx SFX_SPLASH
                Case HCE_CLEAR: Sfx SFX_CLEAR
                Case HCE_CAPSIZE: Flash "SHE'S GOING OVER!", 26
                Case HCE_TIMEOUT: Flash "TIME UP", 26
                Case HCE_OVER: Sfx SFX_OVER
                Case HCE_WIN: Sfx SFX_WIN
                Case HCE_GUST
                    Sfx SFX_GUST
                    Flash "GUST!", 29
            End Select
        End If
    Next i
    hcNEv = 0
End Sub

Public Sub AgeEffects()
    If duFlashTimer > 0 Then duFlashTimer = duFlashTimer - 1
    If splashTimer > 0 Then splashTimer = splashTimer - 1
End Sub

' ---------- placing parts ----------
Private Sub XfWorld()
    xfMode = 0
End Sub

Private Sub XfShip()
    Dim a As Long
    a = A3Angle(hcHeel)
    xfMode = 1
    xfC = A3Cos(a): xfS = A3Sin(a)
    xfPx = HC_PIVOT_X: xfPy = HC_PIVOT_Y
    xfBob = ShrA(hcBob, 16)
End Sub

Private Sub XfSwing(ByVal px As Long, ByVal py As Long, ByVal th As Long)
    Dim a As Long
    a = A3Angle(th)
    xfMode = 2
    xfC = A3Cos(a): xfS = A3Sin(a)
    xfPx = px: xfPy = py
    xfBob = 0
End Sub

' a point through the current placing: ptX, ptY
Private Sub Pt(ByVal x As Long, ByVal y As Long)
    Dim dx As Long, dy As Long, t As Long
    If xfMode = 0 Then
        ptX = x: ptY = y
        Exit Sub
    End If
    dx = x - xfPx: dy = y - xfPy
    If xfMode = 1 Then                     ' heel: the right side down
        t = dx * xfC + dy * xfS: ptX = xfPx + (t - (t And 65535)) \ 65536
        t = dy * xfC - dx * xfS: ptY = xfPy + (t - (t And 65535)) \ 65536 + xfBob
    Else                                   ' th: the bottom swings to +x
        t = dx * xfC - dy * xfS: ptX = xfPx + (t - (t And 65535)) \ 65536
        t = dy * xfC + dx * xfS: ptY = xfPy + (t - (t And 65535)) \ 65536
    End If
End Sub

Private Sub Quad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                 ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, _
                 ByVal bias As Long, ByVal col As Long)
    Pt x0, y0: qx(0) = ptX: qy(0) = ptY
    Pt x1, y1: qx(1) = ptX: qy(1) = ptY
    Pt x2, y2: qx(2) = ptX: qy(2) = ptY
    Pt x3, y3: qx(3) = ptX: qy(3) = ptY
    a3QuadBias = bias
    A3QuadW cam, -1, col, qx(0), qy(0), z0, qx(1), qy(1), z1, qx(2), qy(2), z2, qx(3), qy(3), z3
End Sub

' a box: its front, its top, and the end facing the camera
Private Sub Box(ByVal x0 As Long, ByVal x1 As Long, ByVal y0 As Long, ByVal y1 As Long, ByVal z0 As Long, ByVal z1 As Long, _
                ByVal lit As Long, ByVal shade As Long, ByVal bias As Long)
    Quad x0, y0, z0, x1, y0, z0, x1, y1, z0, x0, y1, z0, bias, lit
    Quad x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1, bias + 1, shade
    If x1 < cam.x Then
        Quad x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1, bias + 1, shade
    ElseIf x0 > cam.x Then
        Quad x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1, bias + 1, shade
    End If
End Sub

' a container: coloured by weight, a darker band top and bottom so stacked ones read apart
Private Sub Container(ByVal x0 As Long, ByVal y0 As Long, ByVal w As Long, ByVal weight As Long, ByVal bias As Long)
    Dim lit As Long, sh As Long
    lit = PEN_BOX + 2 * (weight - 1): sh = lit + 1
    Box x0, x0 + w, y0, y0 + HC_BOX_H, -BOX_Z, BOX_Z, sh, sh, bias
    Quad x0 + 2, y0 + 3, -BOX_Z - 1, x0 + w - 2, y0 + 3, -BOX_Z - 1, x0 + w - 2, y0 + HC_BOX_H - 3, -BOX_Z - 1, _
         x0 + 2, y0 + HC_BOX_H - 3, -BOX_Z - 1, bias - 1, lit
    Quad x0 + 2, y0 + HC_BOX_H, -BOX_Z, x0 + w - 2, y0 + HC_BOX_H, -BOX_Z, x0 + w - 2, y0 + HC_BOX_H, BOX_Z, _
         x0 + 2, y0 + HC_BOX_H, BOX_Z, bias, lit
End Sub

' ---------- the scene ----------
Private Sub Background()
    Dim k As Long, z As Long, zz As Long, x As Long, h As Long, y As Long, f As Long, r As Long, g As Long, b As Long
    For y = 0 To G_H - 1 Step 8
        f = y
        If f > 140 Then f = 140
        r = (skyTop And 255) + ((skyBottom And 255) - (skyTop And 255)) * f \ 140
        g = ((skyTop \ 256) And 255) + (((skyBottom \ 256) And 255) - ((skyTop \ 256) And 255)) * f \ 140
        b = ((skyTop \ 65536) And 255) + (((skyBottom \ 65536) And 255) - ((skyTop \ 65536) And 255)) * f \ 140
        gcv.Box 0, y, G_W, 8, RGB(r, g, b)
    Next y
    A3Begin 4000
    ' the far shore: low hills and a few buildings
    Quad -2400, HC_WATER_Y, 2600, 2600, HC_WATER_Y, 2600, 2600, 40, 2600, -2400, 40, 2600, 0, PEN_SHORE
    For k = 0 To 8
        x = -1700 + k * 420 + (k * 97) Mod 150
        h = 70 + (k * 53) Mod 110
        Quad x, 30, 2590, x + 140, 30, 2590, x + 140, 30 + h, 2590, x, 30 + h, 2590, 0, PEN_SHORE + 2 * (k And 1)
    Next k
    ' the sea, in bands that drift with the swell
    z = -400
    Do While z < 2600
        zz = z + (ShrA(hcPhase, 12) * 300) \ 102
        Quad -2400, HC_WATER_Y, zz, 2600, HC_WATER_Y, zz, 2600, HC_WATER_Y, zz + 300, -2400, HC_WATER_Y, zz + 300, 0, PEN_SEA + (k And 1)
        z = z + 300
        k = k + 1
    Loop
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

Private Sub Quay()
    Dim k As Long, w As Long, lit As Long, x0 As Long, b As Long
    Box -700, HC_QUAY_X1, HC_WATER_Y - 30, 0, -120, 260, PEN_QUAY + 1, PEN_QUAY + 1, 0
    Quad -700, 0, -120, HC_QUAY_X1, 0, -120, HC_QUAY_X1, 0, 260, -700, 0, 260, 2, PEN_QUAY
    ' the line painted where the next container waits
    Quad HC_PICK_X - 30, 1, -26, HC_PICK_X + 30, 1, -26, HC_PICK_X + 30, 1, 26, HC_PICK_X - 30, 1, 26, -2, PEN_YELLOW
    Quad HC_PICK_X - 27, 1, -23, HC_PICK_X + 27, 1, -23, HC_PICK_X + 27, 1, 23, HC_PICK_X - 27, 1, 23, -3, PEN_QUAY
    ' the next one, and those behind it
    If hcCarrying < 0 And hcFalling < 0 And hcNext < hcNBox Then
        w = HcBoxW(hcNext)
        Container HC_PICK_X - w \ 2, 0, w, hbox(hcNext).weight, 0
    End If
    k = 1
    Do While k <= 4 And hcNext + k < hcNBox
        b = hcNext + k
        w = hbox(b).blen * HC_SLOT_W - 2
        lit = PEN_BOX + 2 * (hbox(b).weight - 1)
        x0 = HC_PICK_X - 60 - k * 70 - w \ 2
        Box x0, x0 + w, 0, HC_BOX_H, 120, 160, lit, lit + 1, 0
        k = k + 1
    Loop
End Sub

Private Sub Crane()
    Dim tx As Long, hx As Long, hy As Long, top As Long, k As Long, lg As Long
    tx = ShrA(hcTX, 16): hx = ShrA(HcHookX(), 16): hy = ShrA(HcHookY(), 16): top = HC_GANTRY_Y
    XfWorld
    For k = 0 To 1
        If k = 0 Then lg = -300 Else lg = -40
        Box lg - 8, lg + 8, 0, top + 25, -52, -40, PEN_CRANE, PEN_CRANE + 1, 0
        Box lg - 8, lg + 8, 0, top + 25, 40, 52, PEN_CRANE, PEN_CRANE + 1, 0
        Box lg - 8, lg + 8, top + 25, top + 37, -52, 52, PEN_CRANE, PEN_CRANE + 1, 0
    Next k
    Box -320, 460, top + 10, top + 25, -52, -40, PEN_CRANE, PEN_CRANE + 1, 0       ' the rails
    Box -320, 460, top + 10, top + 25, 40, 52, PEN_CRANE, PEN_CRANE + 1, 0
    Box -300, -40, 160, 172, -52, -40, PEN_CRANE, PEN_CRANE + 1, 0                 ' a brace
    Box -330, -280, top + 25, top + 70, -30, 30, PEN_CRANE + 1, PEN_CRANE + 1, 0   ' the machinery house
    Box tx - 18, tx + 18, top, top + 14, -48, 48, PEN_CRANE + 1, PEN_CRANE + 1, -2 ' the trolley
    ' the cable, from the trolley to the hook
    Quad tx - 2, top, -2, tx + 2, top, -2, hx + 2, hy, -2, hx - 2, hy, -2, -25, PEN_CABLE
    If hcCarrying < 0 Then Box hx - 6, hx + 6, hy - 4, hy + 4, -6, 6, PEN_CABLE, PEN_CABLE, -26
End Sub

Private Sub DrawShip()
    Dim k As Long, x As Long, b As Long
    XfShip
    ' the hull: its side, with a bow, and the deck
    Pt HC_HULL_X0 - 25, HC_DECK_Y + 6: CamXform cam, ptX, ptY, -60: pvx(0) = ox: pvy(0) = oy: pvz(0) = oz
    Pt HC_HULL_X1 + 10, HC_DECK_Y + 6: CamXform cam, ptX, ptY, -60: pvx(1) = ox: pvy(1) = oy: pvz(1) = oz
    Pt HC_HULL_X1 - 5, HC_WATER_Y - 30: CamXform cam, ptX, ptY, -60: pvx(2) = ox: pvy(2) = oy: pvz(2) = oz
    Pt HC_HULL_X0 + 15, HC_WATER_Y - 30: CamXform cam, ptX, ptY, -60: pvx(3) = ox: pvy(3) = oy: pvz(3) = oz
    Pt HC_HULL_X0 - 10, HC_WATER_Y + 10: CamXform cam, ptX, ptY, -60: pvx(4) = ox: pvy(4) = oy: pvz(4) = oz
    A3Poly cam, pvz(0) + 20, PEN_HULL, 5
    Quad HC_HULL_X0 - 25, HC_DECK_Y + 6, -60, HC_HULL_X1 + 10, HC_DECK_Y + 6, -60, HC_HULL_X1 + 10, HC_DECK_Y, -60, _
         HC_HULL_X0 - 25, HC_DECK_Y, -60, 18, PEN_FOAM
    Quad HC_HULL_X0 - 25, HC_DECK_Y, -60, HC_HULL_X1 + 10, HC_DECK_Y, -60, HC_HULL_X1 + 10, HC_DECK_Y, 60, _
         HC_HULL_X0 - 25, HC_DECK_Y, 60, 40, PEN_DECK
    ' the slots' edges on the deck
    For k = 0 To HC_SLOTS
        x = HC_SHIP_X0 + k * HC_SLOT_W
        Quad x - 1, HC_DECK_Y + 1, -30, x + 1, HC_DECK_Y + 1, -30, x + 1, HC_DECK_Y + 1, 30, x - 1, HC_DECK_Y + 1, 30, 38, PEN_YELLOW
    Next k
    ' the bridge at the stern
    x = HC_SHIP_X0 + HC_SLOTS * HC_SLOT_W
    Box x + 6, HC_HULL_X1 + 2, HC_DECK_Y, HC_DECK_Y + 80, -40, 40, PEN_BRIDGE, PEN_BRIDGE - 12, 0
    Box x + 10, HC_HULL_X1 - 2, HC_DECK_Y + 58, HC_DECK_Y + 70, -41, -40, PEN_WINDOW, PEN_WINDOW, -1
    Box x + 4, HC_HULL_X1 + 6, HC_DECK_Y + 80, HC_DECK_Y + 86, -44, 44, PEN_HULL, PEN_HULL + 1, 0
    ' the load
    For k = 0 To hcNPlaced - 1
        b = placed(k).box
        Container HC_SHIP_X0 + placed(k).slot * HC_SLOT_W + 1, HC_DECK_Y + placed(k).tier * HC_BOX_H, HcBoxW(b), hbox(b).weight, -placed(k).tier
    Next k
    XfWorld
End Sub

Private Sub Load()
    Dim hx As Long, hy As Long, w As Long
    If hcCarrying >= 0 Then
        hx = ShrA(HcHookX(), 16): hy = ShrA(HcHookY(), 16)
        w = HcBoxW(hcCarrying)
        XfSwing hx, hy, hcTh
        Box hx - w \ 2 - 4, hx + w \ 2 + 4, hy, hy + 5, -24, 24, PEN_CABLE, PEN_CABLE, -30     ' the spreader
        Container hx - w \ 2, hy - HC_BOX_H, w, hbox(hcCarrying).weight, -30
        XfWorld
    End If
    If hcFalling >= 0 Then Container ShrA(hcFX, 16), ShrA(hcFY, 16), HcBoxW(hcFalling), hbox(hcFalling).weight, -30
End Sub

Private Sub Scene()
    Dim x As Long, r As Long
    cam.x = 60 + (ShrA(hcTX, 16) - 100) \ 6
    cam.y = 150: cam.z = -760
    cam.yaw = 0: cam.pitch = 1100
    cam.precise = 0
    CamView cam, G_W, G_H, G_W \ 2, G_H \ 2 + 8, 290
    CamSetup cam
    XfWorld
    Background
    A3Begin 2000
    Quay
    DrawShip
    Crane
    Load
    If splashTimer > 0 Then
        x = splashX: r = 6 + (20 - splashTimer) * 3
        Quad x - r, HC_WATER_Y + 1, -r \ 2, x + r, HC_WATER_Y + 1, -r \ 2, x + r, HC_WATER_Y + 1, r \ 2, x - r, HC_WATER_Y + 1, r \ 2, -40, PEN_FOAM
    End If
    a3QuadBias = 0
    A3Flush
    polyTotal = polyTotal + a3NPolys
End Sub

' ---------- the HUD ----------
' the list gauge: the heel against the capsize marks
Private Sub Gauge(ByVal x As Long, ByVal y As Long)
    Dim w As Long, n As Long, l As Long
    w = 100
    n = Fix(CDbl(hcHeel) * (w \ 2) / HC_CAPSIZE)
    l = Fix(CDbl(hcList) * (w \ 2) / HC_CAPSIZE)
    GBox x, y, x + w, y + 8, 0, 3
    GRect x + 1, y + 1, x + 12, y + 7, PEN_RED
    GRect x + w - 12, y + 1, x + w - 1, y + 7, PEN_RED
    If n < -w \ 2 + 1 Then n = -w \ 2 + 1
    If n > w \ 2 - 1 Then n = w \ 2 - 1
    If l < -w \ 2 + 1 Then l = -w \ 2 + 1
    If l > w \ 2 - 1 Then l = w \ 2 - 1
    GRect x + w \ 2 + l - 1, y + 2, x + w \ 2 + l + 1, y + 6, PEN_YELLOW
    GRect x + w \ 2 + n, y - 1, x + w \ 2 + n, y + 9, 1
End Sub

Private Sub Hud()
    Dim k As Long, wind As Long, x0 As Long, ln As Long, p As Long
    wind = (hcWind + hcGust) \ 64
    gcv.Box 0, 0, G_W, 12, pen(2)
    GText 4, 9, 1, "SCORE " & hcScore
    GText 110, 9, PEN_YELLOW, "LEVEL " & hcLevel
    GText 186, 9, PEN_GREEN, hcLoaded & "/" & hcNBox
    If hcTimeLeft < 750 And (hcTicks And 8) <> 0 Then p = PEN_RED Else p = 1
    GText 276, 9, p, (hcTimeLeft \ 1500) & ":" & Format$((hcTimeLeft \ 25) Mod 60, "00")
    For k = 0 To hcLost - 1
        GText 240 + k * 9, 9, PEN_RED, "X"
    Next k
    GTextShadow 4, 250, 3, "LIST"
    Gauge 40, 243
    If wind Then
        x0 = 220
        ln = Abs(wind)
        If ln > 40 Then ln = 40
        GTextShadow 160, 250, 3, "WIND"
        GRect x0, 246, x0 + ln, 247, PEN_CYAN
        If wind > 0 Then GRect x0 + ln - 2, 244, x0 + ln, 249, PEN_CYAN Else GRect x0, 244, x0 + 2, 249, PEN_CYAN
    End If
    If duAutoplay Then GTextShadow 276, 250, PEN_GREEN, "AUTO"
End Sub

Public Sub DrawGame(ByVal isOver As Boolean, ByVal isPlay As Boolean)
    Dim p As Long, why As String
    Scene
    Hud
    If hcBetween Then
        GTextBigCentre 60, PEN_GREEN, "SHIP LOADED", 2
        If hcLevel < HC_LEVELS Then GTextCentre 96, 1, "LEVEL " & (hcLevel + 1) & " NEXT"
    End If
    If isPlay And hcTicks < 75 And hcBetween = 0 Then GTextCentre 60, PEN_YELLOW, "LEVEL " & hcLevel & ": LOAD " & hcNBox & " CONTAINERS"
    If isOver Then
        If hcWon Then
            why = "ALL SHIPS LOADED"
        ElseIf hcCapsized Then
            why = "SHE CAPSIZED"
        ElseIf hcLost >= HC_MAX_LOST Then
            why = "THREE LOST"
        Else
            why = "TIME UP"
        End If
        If hcWon Then p = PEN_GREEN Else p = PEN_RED
        GBox 50, 70, 270, 150, 2, p
        If hcWon Then GTextBigCentre 78, p, "YOU WIN", 2 Else GTextBigCentre 78, p, "GAME OVER", 2
        GTextCentre 112, PEN_YELLOW, why
        GTextCentre 126, 1, "SCORE " & hcScore
        If duStateTimer = 0 Then GTextCentre 142, PEN_YELLOW, "PRESS SPACE"
    End If
    If duPaused Then GTextCentre 128, 1, "PAUSED"
    If duFlashTimer > 0 And Len(duFlash) > 0 Then GTextCentre 30, duFlashPen, duFlash
End Sub

Public Sub DrawTitle()
    Dim p As Long
    Scene                                 ' the autopilot works behind the title
    GTextBig 36, 22, 0, "HARBOUR", 5
    GTextBig 34, 20, PEN_YELLOW, "HARBOUR", 5
    GTextBig 86, 72, 0, "CRANE", 5
    GTextBig 84, 70, PEN_CRANE, "CRANE", 5
    GBox 40, 196, 280, 252, 2, 3
    GTextCentre 210, PEN_GREEN, "START AT LEVEL " & startLevel & " (UP/DOWN)"
    If (hcTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    GTextCentre 226, p, "PRESS SPACE TO PLAY"
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
    GTextCentre 110, 1, "PLACE " & (HsRank(hcScore) + 1) & "   " & Format$(hcScore, "0000000")
    If (hcTicks And 8) = 0 Then cur = "_" Else cur = " "
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
    gcv.Box 0, 12, G_W, 11, pen(0)
    GText 2, 21, PEN_GREEN, PerfText()
End Sub
