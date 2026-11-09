' ApCore - Ace Pilot 2's simulation, line for line from amiga_mcp's examples/ace_pilot2/ap_core.c:
' the flight model, the guns and their heat, bullets and hits, the anti-aircraft guns' shells,
' the computer's pilots, the train and the lorries, the eight missions and the campaign, and
' the autopilot. Integers only, with A3Fix.bas's C arithmetic, so a seed flies exactly the war
' the C flies (tools/trace.sh and Trace.bbp compare the state hashes).
'
' x across (east), y up, z ahead (north), 16.16 world units; angles 16-bit (yaw 0 = +z,
' a quarter turn = +x; pitch > 0 nose up; roll > 0 right wing down); a tick is 40 ms.
' The C's structs are arrays here: pl* the aeroplanes (0 is you), bu* bullets, fk* shells,
' gr* ground things.
'
' Where C's && and || skip a call with a side effect (the random generator), the BASIC
' nests Ifs: VB's And and Or evaluate both sides.
Option Explicit

Public Const AP_WORLD As Long = 7000
Public Const AP_MAX_PLANES As Long = 10
Public Const AP_MAX_BULLETS As Long = 48
Public Const AP_MAX_FLAK As Long = 10
Public Const AP_MAX_GROUND As Long = 24
Public Const AP_MISSIONS As Long = 8
Public Const AP_LIVES As Long = 3
Public Const AP_HP As Long = 30
Public Const AP_AMMO As Long = 600
Public Const AP_JAM_HEAT As Long = 100
Public Const AP_JAM_TICKS As Long = 75
Public Const AP_BANK_MAX As Long = 12743
Public Const AP_PITCH_MAX As Long = 10923
Public Const AP_V_STALL As Long = 111411       ' FX(1.7)
Public Const AP_V_CRUISE As Long = 235929      ' FX(3.6)
Public Const AP_V_MAX As Long = 425984         ' FX(6.5)
Public Const AP_BULLET_V As Long = 917504      ' FX(14)
Public Const AP_BULLET_LIFE As Long = 28
Public Const AP_CEILING As Long = 104857600    ' FX(1600)
Public Const AP_END_TICKS As Long = 75
Public Const AP_HOME_R As Long = 700
Public Const AP_HOME_X As Long = -600
Public Const AP_HOME_Z As Long = -2400
Public Const AP_RUNWAY_W As Long = 60
Public Const AP_RUNWAY_L As Long = 420
Public Const AP_ENEMY_X As Long = 1800
Public Const AP_ENEMY_Z As Long = 3800
Public Const AP_DEPOT_X As Long = -2500
Public Const AP_DEPOT_Z As Long = 2000
Public Const AP_RAIL_Z As Long = 2700
Public Const AP_ROAD_LEN As Long = 150732800   ' FX(2300)
Public Const AP_HILLS As Long = 16

Public Const AP_IN_LEFT As Long = 1
Public Const AP_IN_RIGHT As Long = 2
Public Const AP_IN_NOSEDN As Long = 4
Public Const AP_IN_NOSEUP As Long = 8
Public Const AP_IN_FIRE As Long = 16
Public Const AP_IN_THR_UP As Long = 32
Public Const AP_IN_THR_DN As Long = 64

Public Const SIDE_HOME As Long = 0
Public Const SIDE_ENEMY As Long = 1
Public Const PT_SWALLOW As Long = 0
Public Const PT_HERON As Long = 1
Public Const PT_WASP As Long = 2
Public Const PT_HORNET As Long = 3
Public Const PT_OX As Long = 4
Public Const PT_FALCON As Long = 5
Public Const PS_FLY As Long = 0
Public Const PS_FALL As Long = 1
Public Const PS_DEAD As Long = 2
Public Const AI_NONE As Long = 0
Public Const AI_PATROL As Long = 1
Public Const AI_PURSUE As Long = 2
Public Const AI_BREAK As Long = 3
Public Const AI_CLIMB As Long = 4
Public Const AI_FLEE As Long = 5
Public Const AI_ROUTE As Long = 6
Public Const AI_HELD As Long = 7
Public Const GT_HANGAR As Long = 0
Public Const GT_DEPOT As Long = 1
Public Const GT_AA As Long = 2
Public Const GT_BALLOON As Long = 3
Public Const GT_LOCO As Long = 4
Public Const GT_WAGON As Long = 5
Public Const GT_TRUCK As Long = 6
Public Const PH_OUT As Long = 0
Public Const PH_HOME As Long = 1
Public Const PH_DONE As Long = 2
Public Const PH_FAILED As Long = 3

Public Const APE_NONE As Long = 0
Public Const APE_FIRE As Long = 1
Public Const APE_HIT As Long = 2
Public Const APE_KILL As Long = 3
Public Const APE_GKILL As Long = 4
Public Const APE_HURT As Long = 5
Public Const APE_JAM As Long = 6
Public Const APE_UNJAM As Long = 7
Public Const APE_STALL As Long = 8
Public Const APE_FLAK As Long = 9
Public Const APE_WAYPOINT As Long = 10
Public Const APE_OBJECTIVE As Long = 11
Public Const APE_HOMEWARD As Long = 12
Public Const APE_DONE As Long = 13
Public Const APE_FAILED As Long = 14
Public Const APE_DOWN As Long = 15
Public Const APE_CRASH As Long = 16
Public Const APE_LANDED As Long = 17
Public Const APE_REARMED As Long = 18
Public Const APE_ARRIVE As Long = 19
Public Const APE_BOMBS As Long = 20
Public Const APE_ALLY_LOST As Long = 21
Public Const APE_EDGE As Long = 22

' the flight model, per tick
Private Const T_MAX As Long = 3407             ' FX(0.052)
Private Const DRAG As Long = 262               ' FX(0.004)
Private Const GRAV As Long = 3932              ' FX(0.06)
Private Const ROLL_RATE As Long = 700
Private Const LEVEL_RATE As Long = 140
Private Const PITCH_RATE As Long = 300
Private Const TURN_RATE As Long = 360
Private Const BANK_DROOP As Long = 60
Private Const V_LIFT As Long = 170393          ' FX(2.6)

' ---- the game ----
Public apSeed As Long, apRng As Long
Public apMission As Long, apPhase As Long, apEndT As Long, apOver As Long, apWon As Long, apLives As Long
Public apNP As Long, apNGr As Long
Public apNWp As Long, apWpNext As Long, apNRoute As Long, apLoiter As Long
Public apNeed As Long, apDone As Long, apLost As Long, apLostMax As Long, apWaveT As Long, apWaveN As Long
Public apScore As Long, apTicks As Long, apMTick As Long
Public apKills As Long, apGKills As Long, apShots As Long, apHits As Long, apMissionsFlown As Long, apLanded As Long
Public apBotMode As Long, apBotT As Long

' the aeroplanes
Public plType(0 To 9) As Long, plSide(0 To 9) As Long, plState(0 To 9) As Long, plHp(0 To 9) As Long, plMaxHp(0 To 9) As Long
Public plX(0 To 9) As Long, plY(0 To 9) As Long, plZ(0 To 9) As Long, plV(0 To 9) As Long
Public plYaw(0 To 9) As Long, plPitch(0 To 9) As Long, plRoll(0 To 9) As Long
Public plThr(0 To 9) As Long, plStalled(0 To 9) As Long, plOnGround(0 To 9) As Long, plGroundT(0 To 9) As Long
Public plHeat(0 To 9) As Long, plJam(0 To 9) As Long, plAmmo(0 To 9) As Long, plGunCd(0 To 9) As Long, plGunSide(0 To 9) As Long
Public plBurst(0 To 9) As Long, plRest(0 To 9) As Long
Public plAi(0 To 9) As Long, plAiT(0 To 9) As Long, plTarget(0 To 9) As Long, plWp(0 To 9) As Long, plHeld(0 To 9) As Long
Public plObj(0 To 9) As Long, plHome(0 To 9) As Long, plRearCd(0 To 9) As Long
Public plTx(0 To 9) As Long, plTz(0 To 9) As Long, plTalt(0 To 9) As Long, plHitT(0 To 9) As Long, plIn(0 To 9) As Long
' bullets
Public buAlive(0 To 47) As Long, buOwner(0 To 47) As Long, buLife(0 To 47) As Long
Public buX(0 To 47) As Long, buY(0 To 47) As Long, buZ(0 To 47) As Long, buDX(0 To 47) As Long, buDY(0 To 47) As Long, buDZ(0 To 47) As Long
' shells: in flight (fuse ticks), then the burst's puff
Public fkAlive(0 To 9) As Long, fkT(0 To 9) As Long, fkFuse(0 To 9) As Long, fkX(0 To 9) As Long, fkY(0 To 9) As Long, fkZ(0 To 9) As Long
' ground things
Public grType(0 To 23) As Long, grAlive(0 To 23) As Long, grHp(0 To 23) As Long, grObj(0 To 23) As Long
Public grX(0 To 23) As Long, grY(0 To 23) As Long, grZ(0 To 23) As Long, grYaw(0 To 23) As Long, grCd(0 To 23) As Long
Public grLine(0 To 23) As Long, grS(0 To 23) As Long, grDS(0 To 23) As Long
' the patrol line, and the escorted's or the bombers' route
Public wpX(0 To 3) As Long, wpZ(0 To 3) As Long, wpAlt(0 To 3) As Long
Public rtX(0 To 3) As Long, rtZ(0 To 3) As Long, rtAlt(0 To 3) As Long
' events
Public evType(0 To 31) As Long, evA(0 To 31) As Long, evB(0 To 31) As Long
Public evX(0 To 31) As Long, evY(0 To 31) As Long, evZ(0 To 31) As Long, apNEv As Long

' the tables
Public ptThrust(0 To 5) As Long, ptTurn(0 To 5) As Long, ptHp(0 To 5) As Long, ptR(0 To 5) As Long
Public ptGun(0 To 5) As Long, ptRear(0 To 5) As Long, ptScore(0 To 5) As Long, ptScatter(0 To 5) As Long
Public gtHp(0 To 6) As Long, gtR(0 To 6) As Long, gtCy(0 To 6) As Long, gtScore(0 To 6) As Long
Public hlX(0 To 15) As Long, hlZ(0 To 15) As Long, hlR(0 To 15) As Long, hlH(0 To 15) As Long
Public apPlaneName(0 To 5) As String, apGroundName(0 To 6) As String, apRankName(0 To 4) As String
Public apMissionName(1 To 8) As String, apMissionPlace(1 To 8) As String, apBrief(1 To 8, 0 To 3) As String
Public apEventName(0 To 22) As String
Private coreReady As Boolean

Private Sub SetRow(dst() As Long, v As Variant, ByVal n As Long)
    Dim i As Long
    For i = 0 To n - 1: dst(i) = v(i): Next i
End Sub

Public Sub ApInit()
    Dim v As Variant, i As Long, m As Long
    If coreReady Then Exit Sub
    A3FixInit
    ' per type: thrust and turn (percent), hit points, size, a forward gun, a rear gunner, score, the aim's scatter
    SetRow ptThrust, Array(100, 86, 96, 103, 82, 110), 6
    SetRow ptTurn, Array(110, 70, 96, 100, 62, 108), 6
    SetRow ptHp, Array(AP_HP, 16, 10, 14, 22, 26), 6
    SetRow ptR, Array(10, 12, 10, 10, 14, 10), 6
    SetRow ptGun, Array(2, 0, 1, 1, 0, 2), 6
    SetRow ptRear, Array(0, 1, 0, 0, 1, 0), 6
    SetRow ptScore, Array(0, 0, 100, 150, 200, 600), 6
    SetRow ptScatter, Array(0, 500, 760, 640, 800, 560), 6
    ' ground things: hit points, radius, the middle's height, score
    SetRow gtHp, Array(16, 10, 6, 8, 12, 8, 5), 7
    SetRow gtR, Array(32, 22, 14, 20, 16, 16, 10), 7
    SetRow gtCy, Array(14, 10, 6, 0, 10, 10, 6), 7
    SetRow gtScore, Array(150, 120, 80, 250, 200, 60, 50), 7
    ' hills, clear of the river, the railway, the roads and the aerodromes
    SetRow hlX, Array(-3200, 2200, -2000, 900, 3800, -4200, 400, -400, 3000, -4000, 500, -1800, 4200, 3600, -5200, 5200), 16
    SetRow hlZ, Array(-1800, -2600, -3800, -1200, -900, -600, -4300, 1800, 2000, 1700, 3600, 4300, 4000, -3600, 3600, 1500), 16
    SetRow hlR, Array(600, 700, 500, 450, 600, 550, 650, 480, 480, 600, 450, 700, 600, 500, 700, 480), 16
    SetRow hlH, Array(170, 200, 140, 110, 180, 150, 190, 150, 170, 160, 130, 220, 200, 150, 230, 160), 16
    v = Array("Swallow", "Heron", "Wasp", "Hornet", "Ox", "Grey Falcon")
    For i = 0 To 5: apPlaneName(i) = v(i): Next i
    v = Array("hangar", "supply dump", "AA gun", "balloon", "locomotive", "wagon", "lorry")
    For i = 0 To 6: apGroundName(i) = v(i): Next i
    v = Array("SECOND LIEUTENANT", "LIEUTENANT", "CAPTAIN", "MAJOR", "WING COMMANDER")
    For i = 0 To 4: apRankName(i) = v(i): Next i
    v = Array("none", "fire", "hit", "kill", "gkill", "hurt", "jam", "unjam", "stall", "flak", "waypoint", "objective", _
              "homeward", "done", "failed", "down", "crash", "landed", "rearmed", "arrive", "bombs", "ally_lost", "edge")
    For i = 0 To 22: apEventName(i) = v(i): Next i
    v = Array("DAWN PATROL", "THE SELLEN FRONT", _
              "FLY THE PATROL LINE OVER THE TRENCHES:", "THREE MARKERS, WEST TO EAST.", _
              "GRAULAND WASPS ARE ABOUT.", "THEN HOME TO LARKSPUR FIELD.", _
              "EYES IN THE SKY", "THE SELLEN BEND", _
              "TWO OBSERVATION BALLOONS ARE SPOTTING", "FOR THEIR GUNS BEHIND THE RIVER.", _
              "BURN THEM BOTH. THEIR ANTI-AIRCRAFT", "GUNS STAND ROUND THEM.", _
              "SHEPHERD", "ORME DEPOT", _
              "TWO HERON TWO-SEATERS WILL PHOTOGRAPH", "THE SUPPLY DEPOT AT ORME.", _
              "KEEP THE WASPS OFF THEM AND BRING", "AT LEAST ONE HERON HOME.", _
              "IRON ROAD", "THE KESSIN LINE", _
              "A SUPPLY TRAIN IS RUNNING EAST ON THE", "KESSIN RAILWAY. STOP IT: DESTROY THE", _
              "ENGINE AND WAGONS - THREE IN ALL -", "BEFORE IT REACHES THE EAST.", _
              "HOLD THE LINE", "OUR RESERVE DEPOT", _
              "OX BOMBERS ARE COMING FOR OUR RESERVE", "DEPOT BEHIND THE TRENCHES, A HORNET", _
              "WITH THEM. SHOOT DOWN ALL FOUR. IF TWO", "GET THROUGH, THE DEPOT IS LOST.", _
              "SUPPLY LINES", "ORME DEPOT", _
              "THE ENEMY'S SHELLS AND FUEL ARE", "STACKED AT ORME. DESTROY THE FOUR", _
              "SUPPLY DUMPS. LORRIES ON THE ROAD", "ARE WORTH A BURST TOO.", _
              "HORNETS' NEST", "KESSIN AERODROME", _
              "RAID THE ENEMY AERODROME AT KESSIN,", "FAR BEHIND THE LINES: DESTROY ITS", _
              "THREE HANGARS. EXPECT HEAVY GUNS AND", "HORNETS TAKING OFF.", _
              "THE GREY FALCON", "OVER THE FRONT", _
              "THEIR ACE, THE GREY FALCON, IS UP", "WITH TWO WINGMEN. HE HAS SHOT DOWN", _
              "NINE OF OURS THIS MONTH.", "BRING HIM DOWN.")
    For m = 1 To 8
        apMissionName(m) = v((m - 1) * 6)
        apMissionPlace(m) = v((m - 1) * 6 + 1)
        For i = 0 To 3: apBrief(m, i) = v((m - 1) * 6 + 2 + i): Next i
    Next m
    coreReady = True
End Sub

' a3_rand: a 15-bit LCG output
Public Function ApRand() As Long
    ApRand = A3Rand(apRng)
End Function

' an angle difference, signed (C's int16_t)
Private Function SAng(ByVal a As Long) As Long
    SAng = ((a + 32768) And &HFFFF&) - 32768
End Function

Private Sub PushEv(ByVal t As Long, ByVal a As Long, ByVal b As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Dim i As Long
    If apNEv >= 32 Then Exit Sub
    i = apNEv
    evType(i) = t: evA(i) = a: evB(i) = b: evX(i) = x: evY(i) = y: evZ(i) = z
    apNEv = i + 1
End Sub

' the oldest event into its parts; False when there is none
Public Function ApPopEvent(t As Long, a As Long, b As Long, x As Long, y As Long, z As Long) As Boolean
    Dim i As Long
    If apNEv <= 0 Then Exit Function
    t = evType(0): a = evA(0): b = evB(0): x = evX(0): y = evY(0): z = evZ(0)
    apNEv = apNEv - 1
    For i = 0 To apNEv - 1
        evType(i) = evType(i + 1): evA(i) = evA(i + 1): evB(i) = evB(i + 1)
        evX(i) = evX(i + 1): evY(i) = evY(i + 1): evZ(i) = evZ(i + 1)
    Next i
    ApPopEvent = True
End Function

' ---------- the map ----------
Public Function ApAngleTo(ByVal dx As Long, ByVal dz As Long) As Long
    ApAngleTo = A3Atan2(ShrA(dx, 4), ShrA(dz, 4))
End Function

Public Function ApRiverZ(ByVal x As Long) As Long
    ApRiverZ = 900 + ShrA(350 * A3Sin(x * 7), 16)
End Function

Public Function ApRailZ(ByVal x As Long) As Long
    ApRailZ = AP_RAIL_Z + ShrA(150 * A3Sin(x * 9), 16)
End Function

Public Function ApTrenchZ(ByVal x As Long) As Long
    Dim t As Long
    t = (x + 70000) Mod 160              ' a zigzag: 160 units a tooth
    If t < 80 Then ApTrenchZ = t \ 2 - 20 Else ApTrenchZ = (160 - t) \ 2 - 20
End Function

' the road from the depot to the front, s 0..AP_ROAD_LEN
Public Sub ApRoadPos(ByVal s As Long, x As Long, z As Long)
    Dim f As Long
    f = (ShrA(s, 8) * 256) \ 2300        ' 0..65536
    x = AP_DEPOT_X * FONE + 1300 * f
    z = AP_DEPOT_Z * FONE - 1900 * f
End Sub

Public Function ApGroundY(ByVal x As Long, ByVal z As Long) As Long
    Dim wx As Long, wz As Long, best As Long, k As Long, dx As Long, dz As Long, d As Long, y As Long
    wx = ShrA(x, 16): wz = ShrA(z, 16)
    For k = 0 To AP_HILLS - 1
        dx = wx - hlX(k): dz = wz - hlZ(k)
        If dx <= hlR(k) And dx >= -hlR(k) And dz <= hlR(k) And dz >= -hlR(k) Then
            d = FHypot(dx, dz)
            If d < hlR(k) Then
                y = ((hlH(k) * FONE) \ hlR(k)) * (hlR(k) - d)
                If y > best Then best = y
            End If
        End If
    Next k
    ApGroundY = best
End Function

Public Function ApOnRunway(ByVal x As Long, ByVal z As Long) As Boolean
    Dim dx As Long, dz As Long
    dx = ShrA(x, 16) - AP_HOME_X: dz = ShrA(z, 16) - AP_HOME_Z
    ApOnRunway = dx > -AP_RUNWAY_W And dx < AP_RUNWAY_W And dz > -AP_RUNWAY_L And dz < AP_RUNWAY_L
End Function

Private Function HomeDist(ByVal x As Long, ByVal z As Long) As Long
    HomeDist = FHypot(ShrA(x, 16) - AP_HOME_X, ShrA(z, 16) - AP_HOME_Z)
End Function

Public Function ApRank(ByVal sc As Long) As Long
    If sc >= 16000 Then
        ApRank = 4
    ElseIf sc >= 10000 Then
        ApRank = 3
    ElseIf sc >= 5500 Then
        ApRank = 2
    ElseIf sc >= 2200 Then
        ApRank = 1
    Else
        ApRank = 0
    End If
End Function

' ---------- setting up ----------
Private Sub ClearPlane(ByVal k As Long)
    plType(k) = 0: plSide(k) = 0: plState(k) = 0: plHp(k) = 0: plMaxHp(k) = 0
    plX(k) = 0: plY(k) = 0: plZ(k) = 0: plV(k) = 0: plYaw(k) = 0: plPitch(k) = 0: plRoll(k) = 0
    plThr(k) = 0: plStalled(k) = 0: plOnGround(k) = 0: plGroundT(k) = 0
    plHeat(k) = 0: plJam(k) = 0: plAmmo(k) = 0: plGunCd(k) = 0: plGunSide(k) = 0: plBurst(k) = 0: plRest(k) = 0
    plAi(k) = 0: plAiT(k) = 0: plTarget(k) = 0: plWp(k) = 0: plHeld(k) = 0: plObj(k) = 0: plHome(k) = 0: plRearCd(k) = 0
    plTx(k) = 0: plTz(k) = 0: plTalt(k) = 0: plHitT(k) = 0: plIn(k) = 0
End Sub

Public Function ApAddPlane(ByVal typ As Long, ByVal side As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal yaw As Long) As Long
    Dim k As Long
    For k = 1 To AP_MAX_PLANES - 1
        If k >= apNP Then Exit For
        If plState(k) = PS_DEAD Then Exit For
    Next k
    If k >= AP_MAX_PLANES Then
        ApAddPlane = -1
        Exit Function
    End If
    If k >= apNP Then apNP = k + 1
    ClearPlane k
    plType(k) = typ: plSide(k) = side: plState(k) = PS_FLY
    plHp(k) = ptHp(typ): plMaxHp(k) = ptHp(typ)
    plX(k) = x: plY(k) = y: plZ(k) = z: plYaw(k) = yaw And &HFFFF&
    plV(k) = (AP_V_CRUISE * 9) \ 10
    plThr(k) = 100
    plAmmo(k) = 9999
    If typ = PT_HERON Or typ = PT_OX Then plAi(k) = AI_ROUTE Else plAi(k) = AI_PATROL
    plTx(k) = x: plTz(k) = z: plTalt(k) = ShrA(y, 16)
    plTarget(k) = -1
    plHitT(k) = 999
    ApAddPlane = k
End Function

Public Function ApAddGround(ByVal typ As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal yaw As Long, ByVal objective As Long) As Long
    Dim k As Long
    If apNGr >= AP_MAX_GROUND Then
        ApAddGround = -1
        Exit Function
    End If
    k = apNGr
    grType(k) = typ: grAlive(k) = 1: grHp(k) = gtHp(typ): grObj(k) = objective
    grX(k) = x: grY(k) = y: grZ(k) = z: grYaw(k) = yaw And &HFFFF&
    grCd(k) = 30 + apNGr * 7
    grLine(k) = 0: grS(k) = 0: grDS(k) = 0
    apNGr = apNGr + 1
    ApAddGround = k
End Function

Private Function AddOnRail(ByVal typ As Long, ByVal x As Long, ByVal ds As Long, ByVal objective As Long) As Long
    Dim k As Long
    k = ApAddGround(typ, x * FONE, 0, ApRailZ(x) * FONE, 16384, objective)
    If k >= 0 Then
        grLine(k) = 1: grS(k) = x * FONE: grDS(k) = ds
    End If
    AddOnRail = k
End Function

Private Function AddOnRoad(ByVal s As Long, ByVal ds As Long) As Long
    Dim x As Long, z As Long, k As Long
    ApRoadPos s * FONE, x, z
    k = ApAddGround(GT_TRUCK, x, 0, z, 0, 0)
    If k >= 0 Then
        grLine(k) = 2: grS(k) = s * FONE: grDS(k) = ds
    End If
    AddOnRoad = k
End Function

Private Sub SetWp(ByVal i As Long, ByVal x As Long, ByVal z As Long, ByVal alt As Long)
    wpX(i) = x * FONE: wpZ(i) = z * FONE: wpAlt(i) = alt
End Sub

Private Sub SetRoute(ByVal i As Long, ByVal x As Long, ByVal z As Long, ByVal alt As Long)
    rtX(i) = x * FONE: rtZ(i) = z * FONE: rtAlt(i) = alt
End Sub

Private Function Enemy(ByVal typ As Long, ByVal x As Long, ByVal alt As Long, ByVal z As Long, ByVal yaw As Long, _
                       ByVal px As Long, ByVal pz As Long) As Long
    Dim k As Long
    k = ApAddPlane(typ, SIDE_ENEMY, x * FONE, alt * FONE, z * FONE, yaw)
    If k > 0 Then
        plTx(k) = px * FONE: plTz(k) = pz * FONE: plTalt(k) = alt
    End If
    Enemy = k
End Function

Public Sub ApLoadMission(ByVal mission As Long)
    Dim k As Long, h As Long, o As Long, f As Long
    If mission < 1 Then mission = 1
    If mission > AP_MISSIONS Then mission = AP_MISSIONS
    apMission = mission
    apPhase = PH_OUT
    apEndT = 0: apMTick = 0
    apNP = 1: apNGr = 0
    apNWp = 0: apWpNext = 0: apNRoute = 0: apLoiter = 0
    apNeed = 0: apDone = 0: apLost = 0: apLostMax = 99
    apWaveT = 0: apWaveN = 0
    apBotMode = 0: apBotT = 0
    For k = 0 To AP_MAX_BULLETS - 1
        buAlive(k) = 0: buOwner(k) = 0: buLife(k) = 0
        buX(k) = 0: buY(k) = 0: buZ(k) = 0: buDX(k) = 0: buDY(k) = 0: buDZ(k) = 0
    Next k
    For k = 0 To AP_MAX_FLAK - 1
        fkAlive(k) = 0: fkT(k) = 0: fkFuse(k) = 0: fkX(k) = 0: fkY(k) = 0: fkZ(k) = 0
    Next k
    ClearPlane 0
    plType(0) = PT_SWALLOW: plSide(0) = SIDE_HOME: plState(0) = PS_FLY
    plHp(0) = AP_HP: plMaxHp(0) = AP_HP
    plX(0) = AP_HOME_X * FONE: plY(0) = 300 * FONE: plZ(0) = (AP_HOME_Z + 500) * FONE
    plYaw(0) = 0
    plV(0) = AP_V_CRUISE
    plThr(0) = 100
    plAmmo(0) = AP_AMMO
    plTarget(0) = -1
    plHitT(0) = 999
    Select Case mission
        Case 1                              ' the patrol line; Wasps after the first marker
            SetWp 0, -1800, 150, 320: SetWp 1, 0, 650, 320: SetWp 2, 1800, 150, 320
            apNWp = 3
            apWaveN = 2
        Case 2                              ' two balloons, their guns, a Wasp
            ApAddGround GT_BALLOON, -1400 * FONE, 230 * FONE, 800 * FONE, 0, 1
            ApAddGround GT_BALLOON, 1300 * FONE, 230 * FONE, 700 * FONE, 0, 1
            ApAddGround GT_AA, -1280 * FONE, 0, 960 * FONE, 0, 0
            ApAddGround GT_AA, -1560 * FONE, 0, 640 * FONE, 0, 0
            ApAddGround GT_AA, 1180 * FONE, 0, 860 * FONE, 0, 0
            ApAddGround GT_AA, 1460 * FONE, 0, 580 * FONE, 0, 0
            Enemy PT_WASP, 0, 380, 1400, &H8000&, 0, 900
            apNeed = 2
        Case 3                              ' the Herons to Orme and back
            For k = 0 To 1
                h = ApAddPlane(PT_HERON, SIDE_HOME, plX(0) + IIf(k <> 0, 90, -90) * FONE, 280 * FONE, plZ(0) + 60 * FONE, 0)
                plTalt(h) = 280
            Next k
            SetRoute 0, -1500, 300, 300
            SetRoute 1, AP_DEPOT_X, AP_DEPOT_Z, 300
            apNRoute = 2
            apLoiter = 180
            ApAddGround GT_AA, (AP_DEPOT_X + 120) * FONE, 0, (AP_DEPOT_Z - 80) * FONE, 0, 0
            ApAddGround GT_AA, (AP_DEPOT_X - 110) * FONE, 0, (AP_DEPOT_Z + 90) * FONE, 0, 0
            apLostMax = 2
            apWaveN = 2                     ' two waves of two Wasps
            apNeed = 1
        Case 4                              ' the train: an engine, four wagons, one of them guns
            AddOnRail GT_LOCO, -4300, 85196, 1
            AddOnRail GT_WAGON, -4340, 85196, 1
            AddOnRail GT_WAGON, -4380, 85196, 1
            AddOnRail GT_AA, -4420, 85196, 0
            AddOnRail GT_WAGON, -4460, 85196, 1
            Enemy PT_HORNET, -2600, 420, 2900, &H8000&, -2600, 2700
            Enemy PT_HORNET, -2400, 460, 3000, &H8000&, -2600, 2700
            apNeed = 3
        Case 5                              ' the bombers, in two waves
            SetRoute 0, -300, -1200, 260
            apNRoute = 1
            For k = 0 To 1
                o = Enemy(PT_OX, -800 + k * 140, 340, 5000 + k * 80, &H8000&, -300, -1200)
                plObj(o) = 1
            Next k
            Enemy PT_HORNET, -700, 420, 5200, &H8000&, -300, 1200   ' their escort
            apWaveN = 1
            apNeed = 4
            apLostMax = 2
        Case 6                              ' Orme: four dumps, guns, lorries, Wasps
            ApAddGround GT_DEPOT, (AP_DEPOT_X - 60) * FONE, 0, (AP_DEPOT_Z - 40) * FONE, 0, 1
            ApAddGround GT_DEPOT, (AP_DEPOT_X + 60) * FONE, 0, (AP_DEPOT_Z - 40) * FONE, 0, 1
            ApAddGround GT_DEPOT, (AP_DEPOT_X - 60) * FONE, 0, (AP_DEPOT_Z + 50) * FONE, 0, 1
            ApAddGround GT_DEPOT, (AP_DEPOT_X + 60) * FONE, 0, (AP_DEPOT_Z + 50) * FONE, 0, 1
            ApAddGround GT_AA, (AP_DEPOT_X + 170) * FONE, 0, AP_DEPOT_Z * FONE, 0, 0
            ApAddGround GT_AA, (AP_DEPOT_X - 170) * FONE, 0, (AP_DEPOT_Z + 20) * FONE, 0, 0
            AddOnRoad 300, 58982
            AddOnRoad 900, 58982
            AddOnRoad 1600, -58982
            Enemy PT_WASP, -2300, 400, 2600, &H8000&, AP_DEPOT_X, AP_DEPOT_Z
            Enemy PT_WASP, -2700, 430, 2700, &H8000&, AP_DEPOT_X, AP_DEPOT_Z
            apNeed = 4
        Case 7                              ' Kessin: three hangars, three guns, Hornets
            For k = 0 To 2
                ApAddGround GT_HANGAR, (AP_ENEMY_X - 130 + k * 130) * FONE, 0, (AP_ENEMY_Z + 90) * FONE, 0, 1
            Next k
            ApAddGround GT_AA, (AP_ENEMY_X - 260) * FONE, 0, (AP_ENEMY_Z - 60) * FONE, 0, 0
            ApAddGround GT_AA, (AP_ENEMY_X + 260) * FONE, 0, (AP_ENEMY_Z - 40) * FONE, 0, 0
            ApAddGround GT_AA, AP_ENEMY_X * FONE, 0, (AP_ENEMY_Z - 250) * FONE, 0, 0
            Enemy PT_HORNET, AP_ENEMY_X - 300, 420, AP_ENEMY_Z - 900, &H8000&, AP_ENEMY_X, AP_ENEMY_Z - 600
            Enemy PT_HORNET, AP_ENEMY_X + 300, 460, AP_ENEMY_Z - 1000, &H8000&, AP_ENEMY_X, AP_ENEMY_Z - 600
            apWaveN = 1                     ' one more takes off when a hangar burns
            apNeed = 3
        Case Else                           ' the ace and his wingmen, who wait above
            f = Enemy(PT_FALCON, 0, 480, 2600, &H8000&, 0, 600)
            plObj(f) = 1
            k = Enemy(PT_HORNET, -160, 640, 2700, &H8000&, -300, 900)
            plObj(k) = 2
            k = Enemy(PT_HORNET, 160, 660, 2700, &H8000&, 300, 900)
            plObj(k) = 2
            apNeed = 1
    End Select
End Sub

Public Sub ApNewGame(ByVal seed As Long, ByVal mission As Long)
    Dim k As Long
    ApInit
    apSeed = seed
    apRng = AddW(MulW(seed, &H9E3779B1), 1)
    apOver = 0: apWon = 0: apLives = AP_LIVES
    apScore = 0: apTicks = 0: apMTick = 0
    apKills = 0: apGKills = 0: apShots = 0: apHits = 0: apMissionsFlown = 0: apLanded = 0
    apNEv = 0
    For k = 0 To AP_MAX_PLANES - 1: ClearPlane k: Next k
    For k = 0 To AP_MAX_GROUND - 1
        grType(k) = 0: grAlive(k) = 0: grHp(k) = 0: grObj(k) = 0: grX(k) = 0: grY(k) = 0: grZ(k) = 0
        grYaw(k) = 0: grCd(k) = 0: grLine(k) = 0: grS(k) = 0: grDS(k) = 0
    Next k
    For k = 0 To 3
        wpX(k) = 0: wpZ(k) = 0: wpAlt(k) = 0: rtX(k) = 0: rtZ(k) = 0: rtAlt(k) = 0
    Next k
    ApLoadMission mission
End Sub

' after a mission ends: the next (or the same again); False: the campaign is over
Public Function ApNext() As Boolean
    If apOver <> 0 Or apWon <> 0 Then Exit Function
    If apPhase = PH_DONE Then
        If apMission >= AP_MISSIONS Then
            apWon = 1
            Exit Function
        End If
        ApLoadMission apMission + 1
    ElseIf apPhase = PH_FAILED Then
        apLives = apLives - 1
        If apLives <= 0 Then
            apOver = 1
            Exit Function
        End If
        ApLoadMission apMission
    End If
    ApNext = True
End Function

' ---------- flying ----------
Private Sub CrashPlane(ByVal idx As Long)
    plState(idx) = PS_DEAD
    plV(idx) = 0
    PushEv APE_CRASH, idx, plType(idx), plX(idx), plY(idx), plZ(idx)
End Sub

Public Sub ApFly(ByVal idx As Long, ByVal inp As Long)
    Dim tt As Long, pull As Long, rollin As Long, eff As Long, cr As Long, sr As Long, k As Long
    Dim thrust As Long, h As Long, gy As Long, gentle As Boolean, vmin As Long
    tt = ptTurn(plType(idx))
    If inp And AP_IN_NOSEUP Then pull = 1
    If inp And AP_IN_NOSEDN Then pull = pull - 1
    If inp And AP_IN_RIGHT Then rollin = 1
    If inp And AP_IN_LEFT Then rollin = rollin - 1

    plIn(idx) = inp
    If inp And AP_IN_THR_UP Then plThr(idx) = plThr(idx) + 5
    If inp And AP_IN_THR_DN Then plThr(idx) = plThr(idx) - 5
    If plThr(idx) > 100 Then plThr(idx) = 100
    If plThr(idx) < 0 Then plThr(idx) = 0

    eff = FDiv(plV(idx), AP_V_CRUISE)
    If eff > FONE Then eff = FONE
    If eff < 19660 Then eff = 19660               ' FX(0.3)
    If plStalled(idx) <> 0 Then eff = 16384       ' FX(0.25)

    If plState(idx) = PS_FALL Then                ' shot down: a burning spiral
        rollin = 1: pull = 0
        plRoll(idx) = plRoll(idx) + 900
        plYaw(idx) = (plYaw(idx) + 300) And &HFFFF&
        If plPitch(idx) > -9000 Then plPitch(idx) = plPitch(idx) - 260
        plThr(idx) = 30
    End If

    If plOnGround(idx) <> 0 Then
        plRoll(idx) = 0
        plYaw(idx) = (plYaw(idx) + rollin * 200) And &HFFFF&
        If plPitch(idx) < 0 Then plPitch(idx) = 0
        If pull > 0 And plV(idx) > V_LIFT Then
            plOnGround(idx) = 0
            plPitch(idx) = 1400
            plY(idx) = plY(idx) + 98304           ' FX(1.5)
            plGroundT(idx) = 0
        Else
            plPitch(idx) = 0
        End If
    ElseIf plState(idx) = PS_FLY Then
        k = (ROLL_RATE * tt) \ 100
        If rollin <> 0 Then
            plRoll(idx) = plRoll(idx) + ShrA(rollin * k * eff, 16)
        ElseIf plRoll(idx) > 0 Then
            If plRoll(idx) > LEVEL_RATE Then plRoll(idx) = plRoll(idx) - LEVEL_RATE Else plRoll(idx) = 0
        ElseIf plRoll(idx) < 0 Then
            If -plRoll(idx) > LEVEL_RATE Then plRoll(idx) = plRoll(idx) + LEVEL_RATE Else plRoll(idx) = 0
        End If
        If plRoll(idx) > AP_BANK_MAX Then plRoll(idx) = AP_BANK_MAX
        If plRoll(idx) < -AP_BANK_MAX Then plRoll(idx) = -AP_BANK_MAX
        cr = A3Cos(plRoll(idx)): sr = A3Sin(plRoll(idx))
        k = ShrA(((PITCH_RATE * tt) \ 100) * eff, 16)
        plPitch(idx) = plPitch(idx) + ShrA(pull * k * cr, 16)
        plYaw(idx) = plYaw(idx) + ShrA(pull * k * sr, 16)
        k = ShrA(((TURN_RATE * tt) \ 100) * eff, 16)
        plYaw(idx) = (plYaw(idx) + ShrA(k * sr, 16)) And &HFFFF&
        If pull <= 0 Then plPitch(idx) = plPitch(idx) - ShrA(BANK_DROOP * (FONE - cr), 16)
        ' the stall: below flying speed the nose drops and the wings rock
        If plStalled(idx) = 0 And plV(idx) < AP_V_STALL Then
            plStalled(idx) = 1
            If idx = 0 Then PushEv APE_STALL, 0, 0, plX(idx), plY(idx), plZ(idx)
        ElseIf plStalled(idx) <> 0 And plV(idx) > AP_V_STALL + 26214 Then
            plStalled(idx) = 0
        End If
        If plStalled(idx) <> 0 Then
            If plPitch(idx) > -6000 Then plPitch(idx) = plPitch(idx) - 400
            If (apTicks And 8) <> 0 Then plRoll(idx) = plRoll(idx) + 160 Else plRoll(idx) = plRoll(idx) - 160
        End If
    End If
    If plPitch(idx) > AP_PITCH_MAX Then plPitch(idx) = AP_PITCH_MAX
    If plPitch(idx) < -AP_PITCH_MAX Then plPitch(idx) = -AP_PITCH_MAX
    If plRoll(idx) > 32767 Then plRoll(idx) = plRoll(idx) - 65536
    If plRoll(idx) < -32768 Then plRoll(idx) = plRoll(idx) + 65536

    ' speed: thrust against drag and gravity along the flight path
    thrust = ((((T_MAX \ 100) * plThr(idx)) \ 100) * ptThrust(plType(idx)))
    plV(idx) = plV(idx) + thrust - FMul(FMul(plV(idx), plV(idx)), DRAG) - FMul(GRAV, A3Sin(plPitch(idx)))
    If plOnGround(idx) <> 0 Then
        If plThr(idx) < 30 Then plV(idx) = plV(idx) - 3276 Else plV(idx) = plV(idx) - 655
    End If
    If plV(idx) > AP_V_MAX Then plV(idx) = AP_V_MAX
    If plOnGround(idx) <> 0 Then vmin = 0 Else vmin = 39321
    If plV(idx) < vmin Then plV(idx) = vmin

    h = FMul(plV(idx), A3Cos(plPitch(idx)))
    plX(idx) = plX(idx) + FMul(h, A3Sin(plYaw(idx)))
    plZ(idx) = plZ(idx) + FMul(h, A3Cos(plYaw(idx)))
    plY(idx) = plY(idx) + FMul(plV(idx), A3Sin(plPitch(idx)))
    If plStalled(idx) <> 0 Then
        plY(idx) = plY(idx) - 39321
    ElseIf plOnGround(idx) = 0 And plV(idx) < V_LIFT Then
        plY(idx) = plY(idx) - FMul(V_LIFT - plV(idx), 32768)      ' slow: the wings hold less
    End If
    If plY(idx) > AP_CEILING Then
        plY(idx) = AP_CEILING
        If plPitch(idx) > 0 Then plPitch(idx) = plPitch(idx) - 120
    End If

    ' the edge of the map turns you back
    If plX(idx) > AP_WORLD * FONE Or plX(idx) < -AP_WORLD * FONE Or plZ(idx) > AP_WORLD * FONE Or plZ(idx) < -AP_WORLD * FONE Then
        If plX(idx) > AP_WORLD * FONE Then plX(idx) = AP_WORLD * FONE
        If plX(idx) < -AP_WORLD * FONE Then plX(idx) = -AP_WORLD * FONE
        If plZ(idx) > AP_WORLD * FONE Then plZ(idx) = AP_WORLD * FONE
        If plZ(idx) < -AP_WORLD * FONE Then plZ(idx) = -AP_WORLD * FONE
        plYaw(idx) = ApAngleTo(-plX(idx), -plZ(idx)) And &HFFFF&
        If idx = 0 Then PushEv APE_EDGE, 0, 0, plX(idx), plY(idx), plZ(idx)
    End If

    ' the ground
    gy = ApGroundY(plX(idx), plZ(idx))
    If plOnGround(idx) <> 0 Then
        plY(idx) = gy
        If gy > 131072 Then CrashPlane idx       ' taxied into a hill
    ElseIf plY(idx) <= gy + FONE Then
        gentle = plPitch(idx) > -1500 And plPitch(idx) < 2400 And Abs(plRoll(idx)) < 2700 And plV(idx) < 216268
        If plState(idx) = PS_FLY And gy = 0 And gentle Then
            plOnGround(idx) = 1
            plY(idx) = 0
            plRoll(idx) = 0
            plPitch(idx) = 0
            plStalled(idx) = 0
            If idx = 0 Then
                apLanded = apLanded + 1
                PushEv APE_LANDED, 0, 0, plX(idx), plY(idx), plZ(idx)
            End If
        Else
            plY(idx) = gy
            CrashPlane idx
        End If
    End If
End Sub

' ---------- guns ----------
Private Sub SpawnBullet(ByVal owner As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal yaw As Long, _
                        ByVal pitch As Long, ByVal speed As Long)
    Dim k As Long, cp As Long
    For k = 0 To AP_MAX_BULLETS - 1
        If buAlive(k) = 0 Then
            cp = A3Cos(pitch)
            buAlive(k) = 1: buOwner(k) = owner: buLife(k) = AP_BULLET_LIFE
            buDX(k) = FMul(speed, FMul(cp, A3Sin(yaw)))
            buDY(k) = FMul(speed, A3Sin(pitch))
            buDZ(k) = FMul(speed, FMul(cp, A3Cos(yaw)))
            buX(k) = x: buY(k) = y: buZ(k) = z
            Exit Sub
        End If
    Next k
End Sub

Private Sub Guns(ByVal idx As Long, ByVal firing As Boolean)
    Dim sc As Long, yaw As Long, pitch As Long, fx As Long, fy As Long, fz As Long, side As Long, n As Long, cp As Long
    If plGunCd(idx) > 0 Then plGunCd(idx) = plGunCd(idx) - 1
    If plHeat(idx) > 0 Then plHeat(idx) = plHeat(idx) - 2
    If plHeat(idx) < 0 Then plHeat(idx) = 0
    If plJam(idx) > 0 Then
        plJam(idx) = plJam(idx) - 1
        If plJam(idx) = 0 And idx = 0 Then PushEv APE_UNJAM, 0, 0, plX(idx), plY(idx), plZ(idx)
        Exit Sub
    End If
    If Not firing Or plGunCd(idx) > 0 Or plAmmo(idx) <= 0 Or ptGun(plType(idx)) = 0 Or plState(idx) <> PS_FLY Or plOnGround(idx) <> 0 Then Exit Sub
    sc = ptScatter(plType(idx)): yaw = plYaw(idx): pitch = plPitch(idx)
    If plGunSide(idx) <> 0 Then side = 262144 Else side = -262144     ' FX(4)
    If sc <> 0 Then
        yaw = yaw + (ApRand() Mod (2 * sc)) - sc
        pitch = pitch + (ApRand() Mod (2 * sc)) - sc
    End If
    n = ptGun(plType(idx))
    cp = A3Cos(plPitch(idx))
    fx = FMul(cp, A3Sin(plYaw(idx))): fy = A3Sin(plPitch(idx)): fz = FMul(cp, A3Cos(plYaw(idx)))
    Do While n > 0 And plAmmo(idx) > 0       ' one gun, or both of a twin at once
        n = n - 1
        SpawnBullet idx, plX(idx) + 10 * fx + FMul(side, A3Cos(plYaw(idx))), plY(idx) + 10 * fy, _
                    plZ(idx) + 10 * fz - FMul(side, A3Sin(plYaw(idx))), yaw, pitch, plV(idx) + AP_BULLET_V
        side = -side
        plAmmo(idx) = plAmmo(idx) - 1
        If idx = 0 Then apShots = apShots + 1
    Loop
    plGunSide(idx) = plGunSide(idx) Xor 1
    plGunCd(idx) = 2
    If idx = 0 Then
        plHeat(idx) = plHeat(idx) + 7
        PushEv APE_FIRE, 0, 0, plX(idx), plY(idx), plZ(idx)
        If plHeat(idx) >= AP_JAM_HEAT Then
            plJam(idx) = AP_JAM_TICKS
            PushEv APE_JAM, 0, 0, plX(idx), plY(idx), plZ(idx)
        End If
    End If
End Sub

' the closest the segment from a (moving d in one tick) comes to c, against radius r: in
' sixteenths of a unit
Private Function SweepHit(ByVal ax As Long, ByVal ay As Long, ByVal az As Long, ByVal dx As Long, ByVal dy As Long, ByVal dz As Long, _
                          ByVal cx As Long, ByVal cy As Long, ByVal cz As Long, ByVal r As Long) As Boolean
    Dim wx As Long, wy As Long, wz As Long, ux As Long, uy As Long, uz As Long, wd As Long, dd As Long
    Dim qx As Long, qy As Long, qz As Long, lim As Long
    wx = ShrA(cx - ax, 12): wy = ShrA(cy - ay, 12): wz = ShrA(cz - az, 12)
    ux = ShrA(dx, 12): uy = ShrA(dy, 12): uz = ShrA(dz, 12)
    lim = (40 + r) * 16
    If wx > lim Or wx < -lim Or wy > lim Or wy < -lim Or wz > lim Or wz < -lim Then Exit Function
    dd = ux * ux + uy * uy + uz * uz
    wd = wx * ux + wy * uy + wz * uz
    If wd < 0 Then wd = 0
    If wd > dd Then wd = dd
    If dd > 0 Then
        qx = wx - (wd * ux) \ dd
        qy = wy - (wd * uy) \ dd
        qz = wz - (wd * uz) \ dd
    Else
        qx = wx: qy = wy: qz = wz
    End If
    SweepHit = qx * qx + qy * qy + qz * qz < r * r * 256
End Function

Private Sub ObjectiveGone()
    apDone = apDone + 1
    PushEv APE_OBJECTIVE, apDone, apNeed, 0, 0, 0
End Sub

Private Sub PlaneHit(ByVal t As Long, ByVal owner As Long, ByVal dmg As Long)
    If plState(t) <> PS_FLY Then Exit Sub
    plHp(t) = plHp(t) - dmg
    plHitT(t) = 0
    If owner = 0 Then
        apHits = apHits + 1
        PushEv APE_HIT, t, plType(t), plX(t), plY(t), plZ(t)
    End If
    If t = 0 Then PushEv APE_HURT, owner, dmg, plX(t), plY(t), plZ(t)
    If plHp(t) > 0 Then
        If t <> 0 And plAi(t) <> AI_ROUTE And plAi(t) <> AI_HELD And plAi(t) <> AI_FLEE And owner >= 0 And plAi(t) <> AI_BREAK Then
            plTarget(t) = owner               ' turn on whoever shot
            plAi(t) = AI_PURSUE
        End If
        Exit Sub
    End If
    plHp(t) = 0
    plState(t) = PS_FALL
    plOnGround(t) = 0
    If t = 0 Then
        PushEv APE_DOWN, owner, 0, plX(t), plY(t), plZ(t)
        Exit Sub
    End If
    If plSide(t) = SIDE_ENEMY Then
        If owner = 0 Then
            apKills = apKills + 1
            apScore = apScore + ptScore(plType(t))
        End If
        PushEv APE_KILL, t, plType(t), plX(t), plY(t), plZ(t)
        If plObj(t) = 1 Then ObjectiveGone
    Else
        apLost = apLost + 1
        PushEv APE_ALLY_LOST, t, plType(t), plX(t), plY(t), plZ(t)
    End If
End Sub

Private Sub GroundHit(ByVal k As Long, ByVal owner As Long)
    Dim j As Long
    grHp(k) = grHp(k) - 1
    If owner = 0 Then
        apHits = apHits + 1
        PushEv APE_HIT, -1 - k, grType(k), grX(k), grY(k), grZ(k)
    End If
    If grHp(k) > 0 Then Exit Sub
    grAlive(k) = 0
    If owner = 0 Then
        apGKills = apGKills + 1
        apScore = apScore + gtScore(grType(k))
    End If
    PushEv APE_GKILL, k, grType(k), grX(k), grY(k) + gtCy(grType(k)) * FONE, grZ(k)
    If grType(k) = GT_LOCO Then              ' the train stops
        For j = 0 To apNGr - 1
            If grLine(j) = 1 Then grDS(j) = 0
        Next j
    End If
    If grObj(k) <> 0 Then ObjectiveGone
End Sub

Private Sub Bullets()
    Dim k As Long, t As Long, side As Long
    For k = 0 To AP_MAX_BULLETS - 1
        If buAlive(k) <> 0 Then
            side = plSide(buOwner(k))
            For t = 0 To apNP - 1
                If buAlive(k) = 0 Then Exit For
                If plState(t) = PS_FLY And plSide(t) <> side Then
                    If SweepHit(buX(k), buY(k), buZ(k), buDX(k), buDY(k), buDZ(k), plX(t), plY(t), plZ(t), ptR(plType(t))) Then
                        PlaneHit t, buOwner(k), 1
                        buAlive(k) = 0
                    End If
                End If
            Next t
            If side = SIDE_HOME Then
                For t = 0 To apNGr - 1
                    If buAlive(k) = 0 Then Exit For
                    If grAlive(t) <> 0 Then
                        If SweepHit(buX(k), buY(k), buZ(k), buDX(k), buDY(k), buDZ(k), grX(t), grY(t) + gtCy(grType(t)) * FONE, grZ(t), gtR(grType(t))) Then
                            GroundHit t, buOwner(k)
                            buAlive(k) = 0
                        End If
                    End If
                Next t
            End If
            If buAlive(k) <> 0 Then
                buX(k) = buX(k) + buDX(k): buY(k) = buY(k) + buDY(k): buZ(k) = buZ(k) + buDZ(k)
                buLife(k) = buLife(k) - 1
                If buLife(k) <= 0 Then
                    buAlive(k) = 0
                ElseIf buY(k) < ApGroundY(buX(k), buZ(k)) Then
                    buAlive(k) = 0
                End If
            End If
        End If
    Next k
End Sub

' ---------- anti-aircraft guns ----------
Private Sub Flak()
    Dim k As Long, j As Long, dx As Long, dz As Long, d As Long, alt As Long, fuse As Long, er As Long, h As Long
    For k = 0 To apNGr - 1
        If grType(k) = GT_AA And grAlive(k) <> 0 Then
            If grCd(k) > 0 Then
                grCd(k) = grCd(k) - 1
            ElseIf plState(0) = PS_FLY And plOnGround(0) = 0 And apPhase < PH_DONE Then
                dx = ShrA(plX(0) - grX(k), 16): dz = ShrA(plZ(0) - grZ(k), 16): alt = ShrA(plY(0), 16)
                d = FHypot(dx, dz)
                If d <= 1400 And alt >= 50 Then
                    fuse = 18 + FHypot(d, alt) \ 90
                    er = 36 + d \ 9
                    If alt < 200 Then er = er + (200 - alt) \ 2     ' hard to lay on a low aeroplane
                    h = FMul(plV(0), A3Cos(plPitch(0)))
                    For j = 0 To AP_MAX_FLAK - 1
                        If fkAlive(j) = 0 Then
                            fkAlive(j) = 1: fkT(j) = 0: fkFuse(j) = fuse
                            fkX(j) = plX(0) + FMul(h, A3Sin(plYaw(0))) * fuse + ((ApRand() Mod (2 * er)) - er) * FONE
                            fkY(j) = plY(0) + FMul(plV(0), A3Sin(plPitch(0))) * fuse + ((ApRand() Mod er) - er \ 2) * FONE
                            fkZ(j) = plZ(0) + FMul(h, A3Cos(plYaw(0))) * fuse + ((ApRand() Mod (2 * er)) - er) * FONE
                            Exit For
                        End If
                    Next j
                    grCd(k) = 60 + (ApRand() Mod 40)
                End If
            End If
        End If
    Next k
    For k = 0 To AP_MAX_FLAK - 1
        If fkAlive(k) <> 0 Then
            fkT(k) = fkT(k) + 1
            If fkT(k) = fkFuse(k) Then
                d = ShrA(FHypot3(plX(0) - fkX(k), plY(0) - fkY(k), plZ(0) - fkZ(k)), 16)
                PushEv APE_FLAK, k, 0, fkX(k), fkY(k), fkZ(k)
                If plState(0) = PS_FLY And d < 42 Then
                    If d < 20 Then PlaneHit 0, -1, 3 Else PlaneHit 0, -1, 1
                End If
            End If
            If fkT(k) > fkFuse(k) + 30 Then fkAlive(k) = 0
        End If
    Next k
End Sub

' ---------- steering: the computer's pilots and the autopilot ----------
Public Function ApSteer(ByVal idx As Long, ByVal tx As Long, ByVal ty As Long, ByVal tz As Long, ByVal hard As Boolean) As Long
    Dim dx As Long, dy As Long, dz As Long, hd As Long, dyaw As Long, wantPitch As Long, lim As Long, wantRoll As Long
    Dim bank As Long, alt As Long, inp As Long, dp As Long
    dx = tx - plX(idx): dy = ty - plY(idx): dz = tz - plZ(idx)
    hd = FHypot(dx, dz)
    dyaw = SAng(ApAngleTo(dx, dz) - plYaw(idx))
    wantPitch = SAng(A3Atan2(ShrA(dy, 4), ShrA(hd, 4)))
    If hard Then
        lim = 6400: bank = AP_BANK_MAX
    Else
        lim = 4500: bank = 10000
    End If
    alt = ShrA(plY(idx) - ApGroundY(plX(idx), plZ(idx)), 16)
    inp = AP_IN_THR_UP
    If wantPitch > lim Then wantPitch = lim
    If wantPitch < -lim Then wantPitch = -lim
    wantRoll = dyaw * 4
    If wantRoll > bank Then wantRoll = bank
    If wantRoll < -bank Then wantRoll = -bank
    ' the ground first
    If alt < 130 And wantPitch < 1800 Then wantPitch = 1800
    If alt < 70 Then
        wantPitch = 3500
        If wantRoll > 4000 Then wantRoll = 4000
        If wantRoll < -4000 Then wantRoll = -4000
    End If
    If plV(idx) < AP_V_STALL + 32768 And wantPitch > 0 Then wantPitch = 0     ' too slow to climb
    If wantRoll > plRoll(idx) + 350 Then
        inp = inp Or AP_IN_RIGHT
    ElseIf wantRoll < plRoll(idx) - 350 Then
        inp = inp Or AP_IN_LEFT
    ElseIf wantRoll > 1500 And (apTicks And 1) <> 0 Then
        inp = inp Or AP_IN_RIGHT                  ' hold the bank against its easing off
    ElseIf wantRoll < -1500 And (apTicks And 1) <> 0 Then
        inp = inp Or AP_IN_LEFT
    End If
    dp = SAng(wantPitch - plPitch(idx))
    If Abs(dyaw) > 2500 And Abs(plRoll(idx)) > 4000 And dp > -1500 And alt > 70 Then
        inp = inp Or AP_IN_NOSEUP
    ElseIf dp > 250 Then
        inp = inp Or AP_IN_NOSEUP
    ElseIf dp < -250 Then
        inp = inp Or AP_IN_NOSEDN
    End If
    ApSteer = inp
End Function

' the point to aim at for a burst from plane i to meet plane t
Private Sub Lead(ByVal i As Long, ByVal t As Long, ax As Long, ay As Long, az As Long)
    Dim d As Long, ticks As Long, h As Long
    d = FHypot3(plX(t) - plX(i), plY(t) - plY(i), plZ(t) - plZ(i))
    ticks = d \ (plV(i) + AP_BULLET_V)
    h = FMul(plV(t), A3Cos(plPitch(t)))
    If ticks > 40 Then ticks = 40
    ax = plX(t) + FMul(h, A3Sin(plYaw(t))) * ticks
    ay = plY(t) + FMul(plV(t), A3Sin(plPitch(t))) * ticks
    az = plZ(t) + FMul(h, A3Cos(plYaw(t))) * ticks
End Sub

' how far off plane i's nose a point is: the larger of the yaw and pitch errors
Private Function OffNose(ByVal i As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    Dim dx As Long, dy As Long, dz As Long, ey As Long, ep As Long
    dx = x - plX(i): dy = y - plY(i): dz = z - plZ(i)
    ey = Abs(SAng(ApAngleTo(dx, dz) - plYaw(i)))
    ep = Abs(SAng(A3Atan2(ShrA(dy, 4), ShrA(FHypot(dx, dz), 4)) - plPitch(i)))
    If ey > ep Then OffNose = ey Else OffNose = ep
End Function

Private Function NearestFoe(ByVal idx As Long, ByVal range As Long) As Long
    Dim k As Long, best As Long, bd As Long, d As Long
    best = -1
    bd = range
    For k = 0 To apNP - 1
        If k <> idx And plState(k) = PS_FLY And plSide(k) <> plSide(idx) Then
            d = ShrA(FHypot3(plX(k) - plX(idx), plY(k) - plY(idx), plZ(k) - plZ(idx)), 16)
            If plType(k) = PT_HERON Then d = d - 300      ' the escorted are the prize
            If d < bd Then
                bd = d: best = k
            End If
        End If
    Next k
    NearestFoe = best
End Function

Private Sub RearGun(ByVal idx As Long)
    Dim t As Long, ax As Long, ay As Long, az As Long, dx As Long, dy As Long, dz As Long, sc As Long, yaw As Long, pitch As Long
    If plRearCd(idx) > 0 Then
        plRearCd(idx) = plRearCd(idx) - 1
        Exit Sub
    End If
    t = NearestFoe(idx, 260)
    If t < 0 Then Exit Sub
    If OffNose(idx, plX(t), plY(t), plZ(t)) < 4500 Then Exit Sub     ' the gunner can't fire through the propeller
    sc = ptScatter(plType(idx))
    Lead idx, t, ax, ay, az
    dx = ax - plX(idx): dy = ay - plY(idx): dz = az - plZ(idx)
    sc = sc + sc \ 2                         ' from a swaying cockpit
    yaw = ApAngleTo(dx, dz) + (ApRand() Mod (2 * sc)) - sc
    pitch = SAng(A3Atan2(ShrA(dy, 4), ShrA(FHypot(dx, dz), 4))) + (ApRand() Mod (2 * sc)) - sc
    SpawnBullet idx, plX(idx), plY(idx) + 196608, plZ(idx), yaw, pitch, AP_BULLET_V
    plRearCd(idx) = 11
End Sub

Private Function Fighter(ByVal idx As Long) As Long
    Dim inp As Long, alt As Long, t As Long, ax As Long, ay As Long, az As Long, d As Long, k As Long, waiting As Boolean
    Dim dx As Long, dz As Long, retarget As Boolean
    alt = ShrA(plY(idx) - ApGroundY(plX(idx), plZ(idx)), 16)
    If plAiT(idx) > 0 Then plAiT(idx) = plAiT(idx) - 1
    If plHp(idx) <= plMaxHp(idx) \ 4 And plType(idx) <> PT_FALCON And plAi(idx) <> AI_FLEE Then
        plAi(idx) = AI_FLEE
        plTx(idx) = plX(idx): plTz(idx) = (AP_WORLD - 400) * FONE
    End If
    If alt < 110 And plAi(idx) <> AI_CLIMB And plAi(idx) <> AI_FLEE Then
        plAi(idx) = AI_CLIMB: plAiT(idx) = 40
    End If
    Select Case plAi(idx)
        Case AI_CLIMB
            inp = ApSteer(idx, plX(idx) + 200 * A3Sin(plYaw(idx)), plY(idx) + 150 * FONE, plZ(idx) + 200 * A3Cos(plYaw(idx)), False)
            If plAiT(idx) = 0 And alt > 200 Then plAi(idx) = AI_PATROL
        Case AI_FLEE
            inp = ApSteer(idx, plTx(idx), 200 * FONE, plTz(idx), False)
        Case AI_BREAK
            inp = AP_IN_THR_UP Or AP_IN_NOSEUP
            If plWp(idx) <> 0 Then inp = inp Or AP_IN_RIGHT Else inp = inp Or AP_IN_LEFT
            If plAiT(idx) = 0 Then plAi(idx) = AI_PURSUE
        Case AI_PURSUE
            t = plTarget(idx)
            retarget = t < 0
            If Not retarget Then
                If plState(t) <> PS_FLY Then retarget = True
            End If
            If Not retarget Then
                If (apTicks + idx) Mod 25 = 0 Then retarget = True
            End If
            If retarget Then
                plTarget(idx) = NearestFoe(idx, 3200)
                If plTarget(idx) < 0 Then
                    plAi(idx) = AI_PATROL
                    GoTo done
                End If
                t = plTarget(idx)
            End If
            d = ShrA(FHypot3(plX(t) - plX(idx), plY(t) - plY(idx), plZ(t) - plZ(idx)), 16)
            Lead idx, t, ax, ay, az
            inp = ApSteer(idx, ax, ay, az, True)
            If d < 360 Then
                If OffNose(idx, ax, ay, az) < 950 And plRest(idx) = 0 Then
                    inp = inp Or AP_IN_FIRE
                    plBurst(idx) = plBurst(idx) + 1
                    If plBurst(idx) > 14 Then
                        plBurst(idx) = 0: plRest(idx) = 22
                    End If
                End If
            End If
            If plRest(idx) > 0 Then plRest(idx) = plRest(idx) - 1
            ' too close, or head on: break away, climbing over (the player dives under)
            Dim headOn As Boolean
            headOn = d < 90
            If Not headOn And d < 240 Then
                If OffNose(t, plX(idx), plY(idx), plZ(idx)) < 3500 Then
                    If OffNose(idx, plX(t), plY(t), plZ(t)) < 3500 Then headOn = True
                End If
            End If
            If headOn Then
                plAi(idx) = AI_BREAK: plAiT(idx) = 20
                If SAng(ApAngleTo(plX(t) - plX(idx), plZ(t) - plZ(idx)) - plYaw(idx)) < 0 Then plWp(idx) = 1 Else plWp(idx) = 0
            ElseIf d < 330 Then
                ' someone on its tail: break, now and then
                If OffNose(t, plX(idx), plY(idx), plZ(idx)) < 2000 Then
                    If ApRand() Mod 50 = 0 Then
                        plAi(idx) = AI_BREAK
                        plAiT(idx) = 25 + (ApRand() Mod 25)
                        plWp(idx) = ApRand() And 1
                    End If
                End If
            End If
        Case Else                            ' patrol: circle the post, look for a fight
            If plObj(idx) = 2 Then           ' the ace's wingmen watch, until he is hurt
                waiting = False
                For k = 1 To apNP - 1
                    If plType(k) = PT_FALCON And plState(k) = PS_FLY And plHp(k) * 3 > plMaxHp(k) * 2 Then waiting = True
                Next k
                If waiting Then
                    plTx(idx) = plX(0): plTz(idx) = plZ(0)
                    inp = ApSteer(idx, plX(idx) + 300 * A3Sin(plYaw(idx) + 9000), plTalt(idx) * FONE, plZ(idx) + 300 * A3Cos(plYaw(idx) + 9000), False)
                    GoTo done
                End If
                plObj(idx) = 0
            End If
            If (apTicks + idx) Mod 10 = 0 Then
                t = NearestFoe(idx, 1800)
                If t >= 0 Then
                    plAi(idx) = AI_PURSUE: plTarget(idx) = t
                    GoTo done
                End If
            End If
            dx = ShrA(plTx(idx) - plX(idx), 16): dz = ShrA(plTz(idx) - plZ(idx), 16)
            If FHypot(dx, dz) > 500 Then
                inp = ApSteer(idx, plTx(idx), plTalt(idx) * FONE, plTz(idx), False)
            Else
                inp = ApSteer(idx, plX(idx) + 300 * A3Sin(plYaw(idx) + 9000), plTalt(idx) * FONE, plZ(idx) + 300 * A3Cos(plYaw(idx) + 9000), False)
            End If
    End Select
done:
    If plAi(idx) <> AI_PURSUE Then plBurst(idx) = 0
    Fighter = inp
End Function

' the escorted two-seaters and the bombers: along the route
Private Function RouteFlyer(ByVal idx As Long) As Long
    Dim w As Long, d As Long
    If plHome(idx) <> 0 Then
        RouteFlyer = ApSteer(idx, plTx(idx), plTalt(idx) * FONE, plTz(idx), False)
        Exit Function
    End If
    If plType(idx) = PT_HERON Then
        If plWp(idx) < apNRoute Then
            w = plWp(idx)
            d = FHypot(ShrA(rtX(w) - plX(idx), 16), ShrA(rtZ(w) - plZ(idx), 16))
            If d < 220 Then
                plWp(idx) = plWp(idx) + 1
                If plWp(idx) = apNRoute Then
                    plAiT(idx) = apLoiter
                    PushEv APE_ARRIVE, idx, plType(idx), plX(idx), plY(idx), plZ(idx)
                End If
            End If
            RouteFlyer = ApSteer(idx, rtX(w), rtAlt(w) * FONE, rtZ(w), False)
            Exit Function
        End If
        If plAiT(idx) > 0 Then                ' photographing: a wide circle over it
            plAiT(idx) = plAiT(idx) - 1
            RouteFlyer = ApSteer(idx, plX(idx) + 300 * A3Sin(plYaw(idx) + 7000), 320 * FONE, plZ(idx) + 300 * A3Cos(plYaw(idx) + 7000), False)
            Exit Function
        End If
        If HomeDist(plX(idx), plZ(idx)) < AP_HOME_R Then
            plHome(idx) = 1
            plTx(idx) = plX(idx): plTz(idx) = plZ(idx) - 2000 * FONE
            PushEv APE_ARRIVE, idx, plType(idx), plX(idx), plY(idx), plZ(idx)
        End If
        RouteFlyer = ApSteer(idx, AP_HOME_X * FONE, 300 * FONE, AP_HOME_Z * FONE, False)
        Exit Function
    End If
    ' the bomber: to the target, the bombs, then away north
    d = FHypot(ShrA(plTx(idx) - plX(idx), 16), ShrA(plTz(idx) - plZ(idx), 16))
    If d < 120 Then
        apLost = apLost + 1
        PushEv APE_BOMBS, idx, plType(idx), plX(idx), plY(idx), plZ(idx)
        plHome(idx) = 1
        If plObj(idx) <> 0 Then apNeed = apNeed - 1     ' through: no longer one to shoot down
        plObj(idx) = 0
        plTx(idx) = plX(idx): plTz(idx) = (AP_WORLD - 300) * FONE
    End If
    RouteFlyer = ApSteer(idx, plTx(idx), plTalt(idx) * FONE, plTz(idx), False)
End Function

Private Sub HeldFly(ByVal idx As Long)
    Dim h As Long
    h = FMul(plV(idx), A3Cos(plPitch(idx)))
    plX(idx) = plX(idx) + FMul(h, A3Sin(plYaw(idx)))
    plZ(idx) = plZ(idx) + FMul(h, A3Cos(plYaw(idx)))
    plY(idx) = plY(idx) + FMul(plV(idx), A3Sin(plPitch(idx)))
End Sub

' ---------- the autopilot ----------
Private Function NearestGround(ByVal objectiveOnly As Boolean) As Long
    Dim k As Long, best As Long, bd As Long, d As Long
    best = -1
    bd = &H7FFFFFFF
    For k = 0 To apNGr - 1
        If grAlive(k) <> 0 And (Not objectiveOnly Or grObj(k) <> 0) Then
            d = FHypot(ShrA(grX(k) - plX(0), 16), ShrA(grZ(k) - plZ(0), 16))
            If d < bd Then
                bd = d: best = k
            End If
        End If
    Next k
    NearestGround = best
End Function

Private Function Dist16(ByVal i As Long, ByVal j As Long) As Long   ' fhypot3 between two planes, whole units
    Dist16 = ShrA(FHypot3(plX(i) - plX(j), plY(i) - plY(j), plZ(i) - plZ(j)), 16)
End Function

' the autopilot's controls for the player
Public Function ApBot() As Long
    Dim inp As Long, t As Long, k As Long, j As Long, alt As Long, best As Long, bd As Long, d As Long, obj As Long, rng As Long
    Dim ax As Long, ay As Long, az As Long, under As Boolean, k2 As Long, cy As Long, ox As Long, oz As Long
    Dim hd As Long, aimAlt As Long, ticks As Long, s2 As Long, er As Long, near As Boolean
    If plState(0) <> PS_FLY Then Exit Function
    If plOnGround(0) <> 0 Then
        If plV(0) > V_LIFT + 6553 Then ApBot = AP_IN_THR_UP Or AP_IN_NOSEUP Else ApBot = AP_IN_THR_UP
        Exit Function
    End If
    alt = ShrA(plY(0) - ApGroundY(plX(0), plZ(0)), 16)
    If apBotT > 0 Then apBotT = apBotT - 1
    If apBotMode = 1 And apBotT > 0 Then      ' climbing away after a strafing run
        ApBot = ApSteer(0, plX(0) + 400 * A3Sin(plYaw(0)), 280 * FONE, plZ(0) + 400 * A3Cos(plYaw(0)), False)
        Exit Function
    End If
    If apBotMode = 1 Then apBotMode = 2       ' then out, to come round again
    ' aeroplanes first: whatever is near, or (defending) the bombers anywhere
    If apMission = 5 Then
        rng = 6000
    ElseIf apNGr <> 0 Then
        rng = 900
    Else
        rng = 1500
    End If
    t = NearestFoe(0, rng)
    If apPhase = PH_OUT And apMission = 3 Then   ' escorting: whoever is near a Heron
        best = -1
        bd = 1300
        For k = 1 To apNP - 1
            If plType(k) = PT_HERON And plState(k) = PS_FLY Then
                For j = 1 To apNP - 1
                    If plSide(j) = SIDE_ENEMY And plState(j) = PS_FLY Then
                        d = Dist16(j, k)
                        If d < bd Then
                            bd = d: best = j
                        End If
                    End If
                Next j
            End If
        Next k
        If best >= 0 Then t = best
    End If
    If (apMission = 5 Or apMission = 8) And apPhase = PH_OUT Then   ' the bombers, the ace: before the rest
        obj = -1
        For k = 1 To apNP - 1
            If plState(k) = PS_FLY And plObj(k) = 1 Then
                obj = k
                Exit For
            End If
        Next k
        t = NearestFoe(0, 500)
        If t >= 0 Then
            If plObj(t) = 2 Then t = -1          ' leave the waiting wingmen be
        End If
        If t >= 0 And obj >= 0 Then
            If plType(obj) = PT_OX Then
                If OffNose(t, plX(0), plY(0), plZ(0)) > 3000 Then t = -1
            End If
        End If
        If t < 0 Then t = obj                    ' a fighter on your tail first, then the bombers
    End If
    If t >= 0 Then
        If plAi(t) = AI_FLEE And plObj(t) = 0 And apPhase <> PH_OUT Then t = -1
    End If
    For k = 1 To apNP - 1                        ' anything about to hit you: up and away
        If plState(k) = PS_FLY And Abs(plX(k) - plX(0)) < 45 * FONE And Abs(plZ(k) - plZ(0)) < 45 * FONE And Abs(plY(k) - plY(0)) < 25 * FONE Then
            inp = AP_IN_THR_UP
            If plY(k) > plY(0) Then inp = inp Or AP_IN_NOSEDN Else inp = inp Or AP_IN_NOSEUP
            If SAng(ApAngleTo(plX(k) - plX(0), plZ(k) - plZ(0)) - plYaw(0)) > 0 Then inp = inp Or AP_IN_LEFT Else inp = inp Or AP_IN_RIGHT
            ApBot = inp
            Exit Function
        End If
    Next k
    If t >= 0 Then
        d = Dist16(t, 0)
        Lead 0, t, ax, ay, az
        inp = ApSteer(0, ax, ay, az, True)
        If d < 380 Then
            If OffNose(0, ax, ay, az) < 700 And plHeat(0) < 80 And plJam(0) = 0 Then inp = inp Or AP_IN_FIRE
        End If
        near = d < 110
        If Not near And d < 260 Then
            If OffNose(t, plX(0), plY(0), plZ(0)) < 3500 Then near = True
        End If
        If near Then
            If OffNose(0, plX(t), plY(t), plZ(t)) < 5000 Then
                ' don't ram it: under a head-on pass, or over the top of one ahead
                under = d >= 110 Or plY(t) > plY(0)
                inp = AP_IN_THR_UP Or (inp And AP_IN_FIRE)
                If under Then inp = inp Or AP_IN_NOSEDN Else inp = inp Or AP_IN_NOSEUP
                If d < 70 Then inp = inp And Not AP_IN_FIRE
            End If
        End If
        ApBot = inp
        Exit Function
    End If
    If apPhase = PH_OUT Then
        ' a ground target: line up from height, dive at it, fire, climb away
        k2 = NearestGround(True)
        If k2 < 0 And apMission = 6 Then k2 = NearestGround(False)
        If k2 >= 0 Then
            If grType(k2) <> GT_BALLOON Then        ' the guns round it first
                For k = 0 To apNGr - 1
                    If grAlive(k) <> 0 And grType(k) = GT_AA And grLine(k) = 0 Then
                        If FHypot(ShrA(grX(k) - grX(k2), 16), ShrA(grZ(k) - grZ(k2), 16)) < 450 Then
                            If FHypot(ShrA(grX(k) - plX(0), 16), ShrA(grZ(k) - plZ(0), 16)) < _
                               FHypot(ShrA(grX(k2) - plX(0), 16), ShrA(grZ(k2) - plZ(0), 16)) + 200 Then
                                k2 = k
                                Exit For
                            End If
                        End If
                    End If
                Next k
            End If
        End If
        If k2 >= 0 Then
            cy = grY(k2) + gtCy(grType(k2)) * FONE: ox = grX(k2): oz = grZ(k2)
            hd = FHypot(ShrA(grX(k2) - plX(0), 16), ShrA(grZ(k2) - plZ(0), 16))
            aimAlt = ShrA(grY(k2), 16) + 15
            If grDS(k2) <> 0 Then                    ' moving: aim where it will be
                ticks = FHypot3(grX(k2) - plX(0), cy - plY(0), grZ(k2) - plZ(0)) \ (plV(0) + AP_BULLET_V)
                s2 = grS(k2) + grDS(k2) * ticks
                If grLine(k2) = 1 Then
                    ox = s2: oz = ApRailZ(ShrA(s2, 16)) * FONE
                Else
                    ApRoadPos s2, ox, oz
                End If
            End If
            If grType(k2) = GT_BALLOON Then
                inp = ApSteer(0, grX(k2), cy, grZ(k2), True)
                If hd < 420 Then
                    If OffNose(0, grX(k2), cy, grZ(k2)) < 900 And plHeat(0) < 85 And plJam(0) = 0 Then inp = inp Or AP_IN_FIRE
                End If
                If hd < 70 Then
                    apBotMode = 1: apBotT = 40
                End If
                ApBot = inp
                Exit Function
            End If
            er = Abs(SAng(ApAngleTo(grX(k2) - plX(0), grZ(k2) - plZ(0)) - plYaw(0)))
            ' too close to line up: extend away, then turn in
            If apBotMode = 2 And hd < 900 Then
                ApBot = ApSteer(0, plX(0) - (grX(k2) - plX(0)), (aimAlt + 260) * FONE, plZ(0) - (grZ(k2) - plZ(0)), False)
                Exit Function
            End If
            apBotMode = 0
            If hd < 650 And er > 3500 Then
                apBotMode = 2
                ApBot = ApSteer(0, plX(0) - (grX(k2) - plX(0)), (aimAlt + 260) * FONE, plZ(0) - (grZ(k2) - plZ(0)), False)
                Exit Function
            End If
            If er > 2500 Or hd > 850 Then
                If hd > 1500 Then
                    ApBot = ApSteer(0, grX(k2), 330 * FONE, grZ(k2), False)
                Else
                    ApBot = ApSteer(0, grX(k2), (aimAlt + 260) * FONE, grZ(k2), False)
                End If
                Exit Function
            End If
            inp = ApSteer(0, ox, cy, oz, True)
            If hd < 450 Then
                If OffNose(0, ox, cy, oz) < 800 And plHeat(0) < 85 And plJam(0) = 0 Then inp = inp Or AP_IN_FIRE
            End If
            If alt < 70 Or hd < 90 Then
                apBotMode = 1: apBotT = 45
            End If
            ApBot = inp
            Exit Function
        End If
        If apWpNext < apNWp Then
            ApBot = ApSteer(0, wpX(apWpNext), wpAlt(apWpNext) * FONE, wpZ(apWpNext), False)
            Exit Function
        End If
        If apMission = 3 Then                    ' keep with the Herons
            For k = 1 To apNP - 1
                If plType(k) = PT_HERON And plState(k) = PS_FLY And plHome(k) = 0 Then
                    ApBot = ApSteer(0, plX(k) - 200 * A3Sin(plYaw(k)), plY(k) + 60 * FONE, plZ(k) - 200 * A3Cos(plYaw(k)), False)
                    Exit Function
                End If
            Next k
        End If
        t = NearestFoe(0, 9000)                  ' nothing else to do: find a fight
        If t >= 0 Then
            If plObj(t) <> 0 Or apMission = 8 Then
                ApBot = ApSteer(0, plX(t), plY(t), plZ(t), False)
                Exit Function
            End If
        End If
        If apMission = 5 Then                    ' waiting for the bombers over the front
            ApBot = ApSteer(0, -200 * FONE, 420 * FONE, 1200 * FONE, False)
            Exit Function
        End If
    End If
    ApBot = ApSteer(0, AP_HOME_X * FONE, 300 * FONE, AP_HOME_Z * FONE, False)
End Function

' ---------- the mission's progress ----------
Private Sub MissionUpdate()
    Dim k As Long, n As Long, w As Long, o As Long, flying As Long
    If apPhase >= PH_DONE Then Exit Sub
    ' the patrol line
    If apWpNext < apNWp Then
        w = apWpNext
        If FHypot(ShrA(wpX(w) - plX(0), 16), ShrA(wpZ(w) - plZ(0), 16)) < 260 Then
            apWpNext = apWpNext + 1
            apScore = apScore + 100
            PushEv APE_WAYPOINT, apWpNext, apNWp, wpX(w), wpAlt(w) * FONE, wpZ(w)
        End If
    End If
    Select Case apMission
        Case 1
            If apWaveN <> 0 And apWpNext >= 1 Then
                apWaveN = 0
                Enemy PT_WASP, 0, 420, 2300, &H8000&, 0, 600
                Enemy PT_WASP, 200, 460, 2400, &H8000&, 600, 600
            End If
            If apPhase = PH_OUT And apWpNext >= apNWp Then
                apPhase = PH_HOME
                PushEv APE_HOMEWARD, 0, 0, 0, 0, 0
            End If
        Case 3
            n = 0
            For k = 1 To apNP - 1
                If plType(k) = PT_HERON And plState(k) = PS_FLY And plWp(k) >= 1 Then n = n + 1
            Next k
            If apWaveN = 2 And n <> 0 Then
                apWaveN = 1
                Enemy PT_WASP, -1900, 420, 2200, &H8000&, -1500, 900
                Enemy PT_WASP, -1700, 450, 2300, &H8000&, -1500, 900
            End If
            n = 0
            For k = 1 To apNP - 1
                If plType(k) = PT_HERON And plAiT(k) > 0 And plWp(k) >= apNRoute Then n = n + 1
            Next k
            If apWaveN = 1 And n <> 0 Then
                apWaveN = 0
                Enemy PT_WASP, -3800, 450, 3200, &H6000&, AP_DEPOT_X, AP_DEPOT_Z
                Enemy PT_WASP, -1200, 430, 3400, &HA000&, AP_DEPOT_X, AP_DEPOT_Z
            End If
            n = 0
            For k = 1 To apNP - 1
                If plType(k) = PT_HERON And plHome(k) <> 0 And plState(k) = PS_FLY Then n = n + 1
            Next k
            If apPhase = PH_OUT And n > 0 Then
                flying = 0
                For k = 1 To apNP - 1
                    If plType(k) = PT_HERON And plState(k) = PS_FLY And plHome(k) = 0 Then flying = flying + 1
                Next k
                If flying = 0 Then
                    apDone = 1
                    PushEv APE_OBJECTIVE, 1, 1, 0, 0, 0
                End If
            End If
        Case 4
            If apPhase = PH_OUT And grAlive(0) <> 0 And grS(0) > 4600 * FONE Then
                apPhase = PH_FAILED: apEndT = AP_END_TICKS
                PushEv APE_FAILED, 1, 0, grX(0), 0, grZ(0)
            End If
        Case 5
            If apWaveN <> 0 And apMTick >= 900 Then
                apWaveN = 0
                For k = 0 To 1
                    o = Enemy(PT_OX, 700 + k * 150, 360, 5200 + k * 70, &H8000&, -300, -1200)
                    If o > 0 Then plObj(o) = 1
                Next k
            End If
        Case 7
            If apWaveN <> 0 And apDone >= 1 Then
                apWaveN = 0
                k = Enemy(PT_HORNET, AP_ENEMY_X, 30, AP_ENEMY_Z - 300, &H8000&, AP_ENEMY_X, AP_ENEMY_Z - 600)
                If k > 0 Then
                    plAi(k) = AI_CLIMB: plAiT(k) = 60
                End If
            End If
    End Select
    If apPhase = PH_OUT And apLost >= apLostMax Then
        apPhase = PH_FAILED: apEndT = AP_END_TICKS
        PushEv APE_FAILED, 2, apLost, 0, 0, 0
        Exit Sub
    End If
    If apPhase = PH_OUT And apNeed > 0 And apDone >= apNeed Then
        apPhase = PH_HOME
        apScore = apScore + 300
        PushEv APE_HOMEWARD, 0, 0, 0, 0, 0
    End If
    If apPhase = PH_HOME And plState(0) = PS_FLY Then
        If HomeDist(plX(0), plZ(0)) < AP_HOME_R Then
            apPhase = PH_DONE
            apEndT = AP_END_TICKS
            apMissionsFlown = apMissionsFlown + 1
            apScore = apScore + 1000 + 20 * plHp(0)
            PushEv APE_DONE, apMission, 0, plX(0), plY(0), plZ(0)
        End If
    End If
End Sub

Private Sub MoveGround()
    Dim k As Long, x As Long
    For k = 0 To apNGr - 1
        If grAlive(k) <> 0 And grDS(k) <> 0 Then
            grS(k) = grS(k) + grDS(k)
            If grLine(k) = 1 Then
                x = ShrA(grS(k), 16)
                grX(k) = grS(k)
                grZ(k) = ApRailZ(x) * FONE
                grYaw(k) = ApAngleTo(8 * FONE, (ApRailZ(x + 8) - ApRailZ(x)) * FONE)
            ElseIf grLine(k) = 2 Then
                If grS(k) > AP_ROAD_LEN Or grS(k) < 0 Then
                    grDS(k) = -grDS(k)
                    grS(k) = grS(k) + 2 * grDS(k)
                End If
                ApRoadPos grS(k), grX(k), grZ(k)
                If grDS(k) > 0 Then grYaw(k) = ApAngleTo(1300 * FONE, -1900 * FONE) Else grYaw(k) = ApAngleTo(-1300 * FONE, 1900 * FONE)
            End If
        End If
    Next k
End Sub

Public Sub ApTick(ByVal inp As Long)
    Dim k As Long, qi As Long
    If apOver <> 0 Or apWon <> 0 Then Exit Sub
    apTicks = apTicks + 1
    apMTick = apMTick + 1
    If apEndT > 0 Then apEndT = apEndT - 1
    If apPhase >= PH_DONE Then inp = inp And Not AP_IN_FIRE
    ' you
    If plState(0) <> PS_DEAD Then
        If plState(0) = PS_FLY Then ApFly 0, inp Else ApFly 0, 0
        Guns 0, (inp And AP_IN_FIRE) <> 0
        If plOnGround(0) <> 0 And ApOnRunway(plX(0), plZ(0)) And plV(0) < 13107 And plState(0) = PS_FLY Then
            plGroundT(0) = plGroundT(0) + 1
            If plGroundT(0) = 50 Then
                plAmmo(0) = AP_AMMO: plHp(0) = AP_HP: plHeat(0) = 0: plJam(0) = 0
                PushEv APE_REARMED, 0, 0, plX(0), plY(0), plZ(0)
            End If
        Else
            plGroundT(0) = 0
        End If
    End If
    If plHitT(0) < 999 Then plHitT(0) = plHitT(0) + 1
    ' everyone else
    For k = 1 To apNP - 1
        If plState(k) <> PS_DEAD Then
            qi = 0
            If plHitT(k) < 999 Then plHitT(k) = plHitT(k) + 1
            If plState(k) = PS_FLY Then
                If plHeld(k) <> 0 Then
                    HeldFly k
                    GoTo nextPlane
                End If
                If plAi(k) = AI_ROUTE Then qi = RouteFlyer(k) Else qi = Fighter(k)
                If ptRear(plType(k)) <> 0 Then RearGun k
            End If
            ApFly k, qi
            Guns k, (qi And AP_IN_FIRE) <> 0
        End If
nextPlane:
    Next k
    ' collisions between aeroplanes
    For k = 1 To apNP - 1
        If plState(k) = PS_FLY And plState(0) = PS_FLY Then
            If Abs(plX(k) - plX(0)) < 8 * FONE And Abs(plY(k) - plY(0)) < 4 * FONE And Abs(plZ(k) - plZ(0)) < 8 * FONE And plHitT(k) > 10 Then
                PlaneHit k, 0, 12              ' a glancing blow: a real one would end you both
                PlaneHit 0, k, 12
            End If
        End If
    Next k
    Bullets
    Flak
    MoveGround
    If plState(0) <> PS_FLY And apPhase < PH_DONE Then   ' shot down, or into the ground
        apPhase = PH_FAILED: apEndT = AP_END_TICKS
        PushEv APE_FAILED, 0, 0, plX(0), plY(0), plZ(0)
    End If
    MissionUpdate
End Sub

Public Function ApEnemiesLeft() As Long
    Dim k As Long, n As Long
    For k = 1 To apNP - 1
        If plSide(k) = SIDE_ENEMY And plState(k) = PS_FLY Then n = n + 1
    Next k
    ApEnemiesLeft = n
End Function

' where to go next into x, z; False: nowhere
Public Function ApObjectivePos(x As Long, z As Long) As Boolean
    Dim k As Long, best As Long, bd As Long, d As Long
    best = -1
    bd = &H7FFFFFFF
    If apPhase = PH_HOME Then
        x = AP_HOME_X * FONE: z = AP_HOME_Z * FONE
        ApObjectivePos = True
        Exit Function
    End If
    If apPhase <> PH_OUT Then Exit Function
    If apWpNext < apNWp Then
        x = wpX(apWpNext): z = wpZ(apWpNext)
        ApObjectivePos = True
        Exit Function
    End If
    For k = 0 To apNGr - 1
        If grAlive(k) <> 0 And grObj(k) <> 0 Then
            d = FHypot(ShrA(grX(k) - plX(0), 16), ShrA(grZ(k) - plZ(0), 16))
            If d < bd Then
                bd = d: best = k
            End If
        End If
    Next k
    If best >= 0 Then
        x = grX(best): z = grZ(best)
        ApObjectivePos = True
        Exit Function
    End If
    For k = 1 To apNP - 1
        If plState(k) = PS_FLY And (plObj(k) = 1 Or (apMission = 3 And plType(k) = PT_HERON And plHome(k) = 0)) Then
            d = FHypot(ShrA(plX(k) - plX(0), 16), ShrA(plZ(k) - plZ(0), 16))
            If d < bd Then
                bd = d: best = k
            End If
        End If
    Next k
    If best >= 0 Then
        x = plX(best): z = plZ(best)
        ApObjectivePos = True
    End If
End Function

Public Function ApObjectiveText() As String
    Dim s As String
    Select Case apPhase
        Case PH_HOME
            ApObjectiveText = "RETURN TO LARKSPUR FIELD"
            Exit Function
        Case PH_DONE
            ApObjectiveText = "MISSION COMPLETE"
            Exit Function
        Case PH_FAILED
            ApObjectiveText = "MISSION FAILED"
            Exit Function
    End Select
    If apWpNext < apNWp Then
        ApObjectiveText = "PATROL MARKER " & (apWpNext + 1) & " OF " & apNWp
        Exit Function
    End If
    Select Case apMission
        Case 2: s = "BALLOONS "
        Case 3
            ApObjectiveText = "ESCORT THE HERONS"
            Exit Function
        Case 4: s = "TRAIN "
        Case 5: s = "BOMBERS "
        Case 6: s = "SUPPLY DUMPS "
        Case 7: s = "HANGARS "
        Case 8
            ApObjectiveText = "THE GREY FALCON"
            Exit Function
        Case Else: s = "TARGETS "
    End Select
    ApObjectiveText = s & apDone & "/" & apNeed
End Function

Public Function ApStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To apNP - 1
        h = Fnv(h, plType(i)): h = Fnv(h, plState(i)): h = Fnv(h, plHp(i))
        h = Fnv(h, plX(i)): h = Fnv(h, plY(i)): h = Fnv(h, plZ(i)): h = Fnv(h, plV(i))
        h = Fnv(h, plYaw(i)): h = Fnv(h, plPitch(i)): h = Fnv(h, plRoll(i))
        h = Fnv(h, plThr(i)): h = Fnv(h, plHeat(i)): h = Fnv(h, plAmmo(i)): h = Fnv(h, plAi(i)): h = Fnv(h, plOnGround(i))
    Next i
    For i = 0 To apNGr - 1
        h = Fnv(h, grAlive(i)): h = Fnv(h, grHp(i)): h = Fnv(h, grX(i)): h = Fnv(h, grZ(i))
    Next i
    For i = 0 To AP_MAX_BULLETS - 1
        If buAlive(i) <> 0 Then
            h = Fnv(h, buX(i)): h = Fnv(h, buY(i)): h = Fnv(h, buZ(i))
        End If
    Next i
    h = Fnv(h, apScore): h = Fnv(h, apMission): h = Fnv(h, apPhase): h = Fnv(h, apTicks): h = Fnv(h, apMTick)
    h = Fnv(h, apKills): h = Fnv(h, apGKills): h = Fnv(h, apShots): h = Fnv(h, apHits): h = Fnv(h, apLives)
    h = Fnv(h, apOver): h = Fnv(h, apWon): h = Fnv(h, apDone): h = Fnv(h, apLost): h = Fnv(h, apRng)
    ApStateHash = h
End Function
