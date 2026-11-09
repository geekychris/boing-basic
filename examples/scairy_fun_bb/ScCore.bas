' ScCore - ScAIry Fun's simulation, line for line from amiga_mcp's examples/scairy_fun (track.c
' and world.c): the four routes built into 8 m segments with their hazards, the car, the
' autopilot (AiThink / AiSteer), traffic, the hazards, damage and the score, and the route ->
' arrival -> software update -> next route loop. One step per 1/25 s, integers only, with
' A3Fix.bas's C arithmetic, so the routes drive exactly as in the C (tools/trace.sh and
' Trace.bbp compare the state hashes).
'
' "fine" units are sixteenths of a world unit (FBITS 4); a world unit is 1/16 m.
' The C's structs are arrays: sg* the segments, hz* the hazards, ob* the objects, car*, ai*.
' Where C's && and || skip a call to the random generator, the BASIC nests Ifs.
Option Explicit

Public Const FBITS As Long = 4
Public Const SEG_BITS As Long = 7
Public Const SEG_LEN As Long = 128
Public Const SEGF As Long = 2048                ' fine units a segment
Public Const MAX_SEGS As Long = 560
Public Const LANE_W As Long = 56
Public Const SHOULDER As Long = 24
Public Const LEVEE_H As Long = 96
Public Const CAR_LEN As Long = 36
Public Const CAR_WID As Long = 15
Public Const NUM_ROUTES As Long = 4
Public Const MAX_HAZ As Long = 24
Public Const MAX_OBJS As Long = 40
Public Const MAX_SEEN As Long = 12
Public Const MAX_KMH As Long = 140
Private Const RUNOUT As Long = 40

Public Const SIDE_GRASS As Long = 0
Public Const SIDE_LEVEE As Long = 1
Public Const SIDE_DROP As Long = 2
Public Const SIDE_WALL As Long = 3
Public Const SIDE_CLIFF As Long = 4
Public Const SIDE_MEDIAN As Long = 5
Public Const SIDE_TOWN As Long = 6
Public Const SIDE_CANAL As Long = 7

Public Const SF_FLOOD As Long = 1
Public Const SF_GHOST As Long = 2
Public Const SF_OVERPASS As Long = 4
Public Const SF_RAIL_L As Long = 8
Public Const SF_RAIL_R As Long = 16
Public Const SF_GLARE As Long = 32
Public Const SF_FINISH As Long = 64
Public Const SF_CONES As Long = 128

Public Const HZ_NONE As Long = 0
Public Const HZ_FLOOD As Long = 1
Public Const HZ_GHOST As Long = 2
Public Const HZ_PHANTOM As Long = 3
Public Const HZ_CONES As Long = 4
Public Const HZ_GLARE As Long = 5
Public Const HZ_SIREN As Long = 6
Public Const HZ_DEBRIS As Long = 7
Public Const HZ_DEER As Long = 8
Public Const HZ_CYCLIST As Long = 9
Public Const HZ_TRACTOR As Long = 10
Public Const HZ_MERGE As Long = 11
Public Const HZ_GOATS As Long = 12
Public Const HZ_PEDS As Long = 13
Public Const HZ_COUNT As Long = 14

Public Const OBJ_NONE As Long = 0
Public Const OBJ_CAR As Long = 1
Public Const OBJ_TRUCK As Long = 2
Public Const OBJ_TRACTOR As Long = 3
Public Const OBJ_CYCLIST As Long = 4
Public Const OBJ_DEER As Long = 5
Public Const OBJ_CONE As Long = 6
Public Const OBJ_DEBRIS As Long = 7
Public Const OBJ_AMBULANCE As Long = 8
Public Const OBJ_GOAT As Long = 9
Public Const OBJ_PED As Long = 10

Public Const OF_ONCOMING As Long = 1
Public Const OF_KNOCKED As Long = 2
Public Const OF_TAILGATE As Long = 4
Public Const OF_PASSING As Long = 8

Public Const CAM_CHASE As Long = 0
Public Const CAM_COCKPIT As Long = 1
Public Const GS_TITLE As Long = 0
Public Const GS_INTRO As Long = 1
Public Const GS_PLAY As Long = 2
Public Const GS_ARRIVED As Long = 3
Public Const GS_UPDATE As Long = 4
Public Const GS_GAMEOVER As Long = 5
Public Const GS_WIN As Long = 6
Public Const CS_DRIVING As Long = 0
Public Const CS_AQUAPLANE As Long = 1
Public Const CS_SPLASH As Long = 2
Public Const CS_ROLL As Long = 3

Public Const IN_LEFT As Long = 1
Public Const IN_RIGHT As Long = 2
Public Const IN_UP As Long = 4
Public Const IN_DOWN As Long = 8
Public Const IN_FIRE As Long = 16
Public Const IN_VIEW As Long = 32
Public Const IN_ESC As Long = 128
Public Const IN_START As Long = 256
Public Const IN_PAUSE As Long = 512
Public Const IN_HELP As Long = 1024

Public Const MSG_NONE As Long = 0
Public Const MSG_AP_ON As Long = 1
Public Const MSG_AP_OFF As Long = 2
Public Const MSG_HAD_THAT As Long = 3
Public Const MSG_GOOD_CATCH As Long = 4
Public Const MSG_RECALC As Long = 5
Public Const MSG_ROAD_PROBABLY As Long = 6
Public Const MSG_OBSTACLE As Long = 7
Public Const MSG_HANDS As Long = 8
Public Const MSG_OOPS As Long = 9
Public Const MSG_UPDATED As Long = 10
Public Const MSG_UNAVAILABLE As Long = 11
Public Const MSG_WELCOME As Long = 12
Public Const MSG_WATER_ANYWAY As Long = 13
Public Const MSG_ARRIVED As Long = 14
Public Const MSG_BLINDED As Long = 15
Public Const MSG_PATIENT As Long = 16
Public Const MSG_TICKET As Long = 17
Public Const MSG_TOW As Long = 18
Public Const MSG_CANCELLED As Long = 19

Public Const EV_NONE As Long = 0
Public Const EV_AP_ON As Long = 1
Public Const EV_AP_OFF As Long = 2
Public Const EV_UNAVAILABLE As Long = 3
Public Const EV_SAVE As Long = 4
Public Const EV_NEEDLESS As Long = 5
Public Const EV_SCRAPE As Long = 6
Public Const EV_CONE As Long = 7
Public Const EV_DEBRIS As Long = 8
Public Const EV_REAREND As Long = 9
Public Const EV_CRASH As Long = 10
Public Const EV_SPLASH As Long = 11
Public Const EV_ROLL As Long = 12
Public Const EV_TICKET As Long = 13
Public Const EV_RESPAWN As Long = 14
Public Const EV_PHANTOM As Long = 15
Public Const EV_BLINDED As Long = 16
Public Const EV_AQUAPLANE As Long = 17
Public Const EV_ARRIVED As Long = 18
Public Const EV_GAME_OVER As Long = 19
Public Const EV_MULT_UP As Long = 20
Public Const EV_SIREN As Long = 21
Public Const EV_ROUTE_START As Long = 22
Public Const EV_HIT_ANIMAL As Long = 23
Public Const EV_SAY As Long = 24
Public Const EV_WIN As Long = 25

' ---- the routes ----
Public riName(0 To 3) As String, riDest(0 To 3) As String, riAi(0 To 3) As String
Public riNl(0 To 3) As Long, riNo(0 To 3) As Long, riLimit(0 To 3) As Long, riTraffic(0 To 3) As Long, riSky(0 To 3) As Long
Public msgText(0 To 19) As String, evName(0 To 25) As String, hzName(0 To 13) As String, objName(0 To 10) As String
Public objLen(0 To 10) As Long, objWid(0 To 10) As Long
' the sections (len, turn, hill, left, right, flags) and the hazards (type, seg, len, param) of each route
Private secData(0 To 3) As Variant, hazData(0 To 3) As Variant

' ---- the world ----
Public wRoute As Long, wNSeg As Long, wNHaz As Long, wFinish As Long
Public sgCx(0 To 559) As Long, sgY(0 To 559) As Long, sgDir(0 To 559) As Long, sgSideL(0 To 559) As Long, sgSideR(0 To 559) As Long
Public sgFlags(0 To 559) As Long, sgClosed(0 To 559) As Long, sgGhost(0 To 559) As Long, sgKnocked(0 To 559) As Long
Public hzType(0 To 23) As Long, hzSeg(0 To 23) As Long, hzLen(0 To 23) As Long, hzParam(0 To 23) As Long
Public hzState(0 To 23) As Long, hzSaid(0 To 23) As Long
Public wState As Long, wFrame As Long, wStateTimer As Long, wView As Long
Public carState As Long, carZ As Long, carD As Long, carV As Long, carS As Long, carLat As Long, carTimer As Long, carCool As Long
Public carHist(0 To 31) As Long, carHistPos As Long
Public aiOn As Long, aiLane As Long, aiPlan(0 To 15) As Long, aiPlanFrom As Long, aiPhantomTimer As Long, aiPhantomSeg As Long
Public aiBlinded As Long, aiBlindX As Long, aiBlindZ As Long, aiBlindDir As Long, aiTargetV As Long, aiLaneHold As Long
Public snZ(0 To 11) As Long, snD(0 To 11) As Long, snType(0 To 11) As Long, snPhantom(0 To 11) As Long, aiNSeen As Long
Public obType(0 To 39) As Long, obFlags(0 To 39) As Long, obColour(0 To 39) As Long, obHz(0 To 39) As Long, obLane(0 To 39) As Long
Public obZ(0 To 39) As Long, obD(0 To 39) As Long, obV(0 To 39) As Long, obVd(0 To 39) As Long, obVt(0 To 39) As Long
Public obTimer(0 To 39) As Long, obCool(0 To 39) As Long
Public wRng As Long
Public wScore As Long, wCover As Long, wMult As Long, wApFrames As Long, wDistAp As Long, wDistAll As Long
Public wSaves As Long, wNeedless As Long, wTakeovers As Long, wApRem As Long
Public wPendingSave As Long, wIncident As Long, wRouteBonus As Long, wTotalSaves As Long, wTotalNeedless As Long
Public wMsg As Long, wMsgTimer As Long, wGlare As Long, wSiren As Long
Public evType(0 To 15) As Long, evA(0 To 15) As Long, evB(0 To 15) As Long, wNEv As Long
Public wLastIn As Long
Public tuGodMode As Long, tuAiPerfect As Long, tuTrafficPct As Long, tuSpeedPct As Long, tuMultSecs As Long, tuAquaKmh As Long

Private coreReady As Boolean

Public Sub ScInit()
    Dim v As Variant, i As Long
    If coreReady Then Exit Sub
    A3FixInit
    '                   name            destination      AI     nl no limit traffic sky
    SetRoute 0, "LEVEE ROAD", "THE MARINA", "1.0", 1, 1, 80, 10, 0
    SetRoute 1, "RUSH HOUR", "THE OFFICE", "2.0", 3, 0, 110, 34, 1
    SetRoute 2, "MOUNTAIN PASS", "THE SKI LODGE", "3.0", 1, 1, 70, 8, 2
    SetRoute 3, "FLOODED TOWN", "HOME", "4.0", 1, 1, 50, 12, 3
    v = Array("", "AUTOPILOT ENGAGED", "AUTOPILOT DISENGAGED", "I HAD THAT.", "GOOD CATCH.", "RECALCULATING...", _
              "THAT IS A ROAD. PROBABLY.", "OBSTACLE DETECTED!", "KEEP YOUR HANDS ON THE WHEEL", "OOPS.", _
              "UPDATE INSTALLED. I AM BETTER NOW.", "AUTOPILOT UNAVAILABLE", "WELCOME TO SCAIRY FUN", _
              "WATER DETECTED. PROCEEDING ANYWAY.", "YOU HAVE ARRIVED.", "CAMERA BLINDED", "I AM VERY PATIENT.", _
              "TICKET: FAILED TO YIELD", "TOW TRUCK ON ITS WAY", "POLICY CANCELLED")
    For i = 0 To 19: msgText(i) = v(i): Next i
    v = Array("none", "ap_on", "ap_off", "unavailable", "save", "needless", "scrape", "cone", "debris", "rearend", "crash", _
              "splash", "roll", "ticket", "respawn", "phantom", "blinded", "aquaplane", "arrived", "game_over", "mult_up", _
              "siren", "route_start", "hit_animal", "say", "win")
    For i = 0 To 25: evName(i) = v(i): Next i
    v = Array("none", "flood", "ghost", "phantom", "cones", "glare", "siren", "debris", "deer", "cyclist", "tractor", _
              "merge", "goats", "peds")
    For i = 0 To 13: hzName(i) = v(i): Next i
    v = Array("none", "car", "truck", "tractor", "cyclist", "deer", "cone", "debris", "ambulance", "goat", "pedestrian")
    For i = 0 To 10: objName(i) = v(i): Next i
    ' half length, half width, units
    v = Array(0, 36, 90, 30, 14, 16, 4, 10, 50, 10, 5)
    For i = 0 To 10: objLen(i) = v(i): Next i
    v = Array(0, 15, 20, 16, 5, 6, 4, 10, 17, 4, 5)
    For i = 0 To 10: objWid(i) = v(i): Next i
    ' sections: len, turn, hill, left, right, flags (L levee, D drop, G grass, W wall, C cliff, M median, T town, K canal)
    secData(0) = Array(40, 0, 0, 1, 2, 0, 24, 36, 0, 1, 2, 0, 24, -36, 0, 1, 2, 0, 50, 0, 0, 1, 2, 0, _
                       30, -40, 0, 1, 2, 0, 30, 40, 0, 1, 2, 0, 40, 0, 60, 1, 2, 0, 40, 30, -60, 1, 2, 0, _
                       40, -30, 0, 1, 2, 0, 60, 0, 0, 1, 2, 0, 60, 0, 0, 1, 0, 0)
    secData(1) = Array(50, 0, 0, 5, 0, 0, 40, 30, 40, 5, 2, 16, 40, -30, -40, 5, 2, 16, 60, 0, 0, 5, 0, 0, _
                       50, -24, 0, 5, 0, 0, 50, 24, 0, 5, 0, 0, 60, 0, 50, 5, 2, 16, 40, 0, -50, 5, 0, 0, _
                       80, 0, 0, 5, 0, 0)
    secData(2) = Array(30, 0, 0, 3, 4, 16, 30, 60, 80, 3, 4, 16, 30, -60, 80, 3, 4, 16, 24, -50, 60, 3, 4, 16, _
                       24, 50, 40, 3, 4, 16, 40, 0, 60, 3, 4, 16, 30, 56, 60, 3, 4, 16, 30, -56, 40, 3, 4, 0, _
                       30, -60, 40, 3, 4, 16, 30, 60, 20, 3, 4, 16, 40, 0, 0, 3, 4, 16, 60, 0, -40, 0, 0, 0)
    secData(3) = Array(40, 0, 0, 6, 6, 0, 30, 30, 0, 7, 6, 8, 30, -30, 0, 7, 6, 0, 50, 0, 0, 7, 6, 0, _
                       30, -40, 0, 6, 6, 0, 30, 40, 0, 6, 6, 0, 60, 0, 0, 7, 6, 0, 40, 24, 0, 6, 6, 0, _
                       40, -24, 0, 6, 6, 0, 60, 0, 0, 6, 6, 0)
    ' hazards: type, segment, length, param
    hazData(0) = Array(HZ_CYCLIST, 50, 0, 0, HZ_FLOOD, 108, 12, -1, HZ_DEER, 140, 0, 0, HZ_GHOST, 152, 26, 150, _
                       HZ_TRACTOR, 236, 20, 0, HZ_FLOOD, 352, 10, -1)
    hazData(1) = Array(HZ_MERGE, 40, 0, 2, HZ_PHANTOM, 100, 2, 0, HZ_CONES, 170, 36, 2, HZ_SIREN, 236, 0, 0, _
                       HZ_PHANTOM, 300, 2, 0, HZ_DEBRIS, 360, 0, -1)
    hazData(2) = Array(HZ_GLARE, 88, 22, 0, HZ_DEBRIS, 150, 0, -1, HZ_GOATS, 185, 0, 0, HZ_GHOST, 206, 24, 140, _
                       HZ_GLARE, 266, 22, 0, HZ_DEBRIS, 330, 0, -1)
    hazData(3) = Array(HZ_PEDS, 30, 0, 0, HZ_FLOOD, 84, 14, -1, HZ_CONES, 150, 30, 0, HZ_SIREN, 205, 0, 0, _
                       HZ_FLOOD, 252, 12, -1, HZ_PHANTOM, 300, 2, 0, HZ_PEDS, 330, 0, 0)
    coreReady = True
End Sub

Private Sub SetRoute(ByVal i As Long, ByVal nm As String, ByVal dest As String, ByVal ai As String, ByVal nl As Long, _
                     ByVal no As Long, ByVal lim As Long, ByVal traffic As Long, ByVal sky As Long)
    riName(i) = nm: riDest(i) = dest: riAi(i) = ai
    riNl(i) = nl: riNo(i) = no: riLimit(i) = lim: riTraffic(i) = traffic: riSky(i) = sky
End Sub

Public Function FromKmh(ByVal k As Long) As Long
    FromKmh = (k * 256) \ 90
End Function

Public Function Kmh(ByVal v As Long) As Long
    Kmh = ShrA(v * 90, 8)
End Function

Public Function HzFails(ByVal t As Long) As Boolean
    HzFails = t >= HZ_FLOOD And t <= HZ_DEBRIS
End Function

' ---------- track.c ----------
Public Sub RouteBuild(ByVal route As Long)
    Dim cx As Long, y As Long, dir As Long, n As Long, i As Long, k As Long, s As Long, sd As Variant, hd As Variant
    Dim ln As Long, turn As Long, hill As Long, dir0 As Long, y0 As Long, t As Long, sg As Long
    wRoute = route
    sd = secData(route)
    For s = 0 To UBound(sd) Step 6
        If n >= MAX_SEGS - RUNOUT - 1 Then Exit For
        ln = sd(s): turn = sd(s + 1): hill = sd(s + 2)
        dir0 = dir: y0 = y
        For i = 0 To ln - 1
            If n >= MAX_SEGS - RUNOUT - 1 Then Exit For
            dir = dir0 + (turn * (i + 1)) \ ln
            sgCx(n) = cx
            sgY(n) = y
            sgDir(n) = dir
            sgSideL(n) = sd(s + 3): sgSideR(n) = sd(s + 4)
            sgFlags(n) = sd(s + 5)
            sgClosed(n) = 0: sgGhost(n) = 0
            cx = cx + dir
            y = y0 + (hill * (i + 1)) \ ln
            n = n + 1
        Next i
    Next s
    ' the destination, then straight road to look at
    wFinish = n
    For i = 0 To RUNOUT
        sgCx(n) = cx
        sgY(n) = y
        sgDir(n) = dir
        sgSideL(n) = sgSideL(n - 1): sgSideR(n) = sgSideR(n - 1)
        If i < 2 Then sgFlags(n) = SF_FINISH Else sgFlags(n) = 0
        sgClosed(n) = 0: sgGhost(n) = 0
        cx = cx + dir
        n = n + 1
    Next i
    wNSeg = n
    wNHaz = 0
    hd = hazData(route)
    For s = 0 To UBound(hd) Step 4
        If wNHaz >= MAX_HAZ Then Exit For
        t = hd(s)
        hzType(wNHaz) = t: hzSeg(wNHaz) = hd(s + 1): hzLen(wNHaz) = hd(s + 2): hzParam(wNHaz) = hd(s + 3)
        hzState(wNHaz) = 0
        For k = 0 To hzLen(wNHaz) - 1
            sg = hzSeg(wNHaz) + k
            If sg >= n Then Exit For
            Select Case t
                Case HZ_FLOOD: sgFlags(sg) = sgFlags(sg) Or SF_FLOOD
                Case HZ_PHANTOM: sgFlags(sg) = sgFlags(sg) Or SF_OVERPASS
                Case HZ_GLARE: sgFlags(sg) = sgFlags(sg) Or SF_GLARE
                Case HZ_CONES
                    sgFlags(sg) = sgFlags(sg) Or SF_CONES
                    sgClosed(sg) = sgClosed(sg) Or (2 ^ hzParam(wNHaz))
                Case HZ_GHOST
                    sgFlags(sg) = sgFlags(sg) Or SF_GHOST
                    ' the old lines peel away over the first two thirds
                    If k * 3 >= hzLen(wNHaz) * 2 Then
                        sgGhost(sg) = hzParam(wNHaz)
                    Else
                        sgGhost(sg) = (hzParam(wNHaz) * k * 3) \ (hzLen(wNHaz) * 2)
                    End If
            End Select
        Next k
        wNHaz = wNHaz + 1
    Next s
End Sub

Public Function SegOf(ByVal z As Long) As Long
    SegOf = ShrA(z, FBITS + SEG_BITS)
End Function

Private Function ClampSeg(ByVal i As Long) As Long
    If i < 0 Then
        ClampSeg = 0
    ElseIf i > wNSeg - 2 Then
        ClampSeg = wNSeg - 2
    Else
        ClampSeg = i
    End If
End Function

Public Function RoadCx(ByVal z As Long) As Long
    Dim j As Long, f As Long
    j = ClampSeg(SegOf(z))
    f = ShrA(z, FBITS) - j * SEG_LEN
    RoadCx = sgCx(j) + ShrA(sgDir(j) * f, SEG_BITS)
End Function

Public Function RoadY(ByVal z As Long) As Long
    Dim j As Long, f As Long
    j = ClampSeg(SegOf(z))
    f = ShrA(z, FBITS) - j * SEG_LEN
    RoadY = sgY(j) + ShrA((sgY(j + 1) - sgY(j)) * f, SEG_BITS)
End Function

Public Function RoadDir(ByVal z As Long) As Long
    Dim j As Long, f As Long, d As Long
    j = ClampSeg(SegOf(z))
    f = ShrA(z, FBITS) - j * SEG_LEN
    d = sgDir(j) + ShrA((sgDir(j + 1) - sgDir(j)) * f, SEG_BITS)
    RoadDir = A3AtanRatio(d, SEG_LEN)
End Function

Public Function RoadCurve(ByVal z As Long) As Long
    Dim j As Long
    j = ClampSeg(SegOf(z))
    RoadCurve = sgDir(j + 1) - sgDir(j)
End Function

Public Function GhostAt(ByVal z As Long) As Long
    Dim j As Long, f As Long
    j = ClampSeg(SegOf(z))
    f = ShrA(z, FBITS) - j * SEG_LEN
    If (sgFlags(j) And SF_GHOST) = 0 Then Exit Function
    GhostAt = sgGhost(j) + ShrA((sgGhost(j + 1) - sgGhost(j)) * f, SEG_BITS)
End Function

Public Function RoadLeft() As Long
    If riNo(wRoute) <> 0 Then RoadLeft = -riNo(wRoute) * LANE_W Else RoadLeft = -8
End Function

Public Function RoadRight() As Long
    RoadRight = riNl(wRoute) * LANE_W
End Function

Public Function LaneCentre(ByVal lane As Long) As Long
    LaneCentre = lane * LANE_W + LANE_W \ 2
End Function

Public Function LaneOf(ByVal d As Long) As Long
    Dim u As Long, n As Long
    u = ShrA(d, FBITS)
    n = riNl(wRoute)
    If u < 0 Then
        LaneOf = -1
    ElseIf u >= n * LANE_W Then
        LaneOf = n - 1
    Else
        LaneOf = u \ LANE_W
    End If
End Function

' ---------- world.c ----------
Private Sub Push(ByVal t As Long, ByVal a As Long, ByVal b As Long)
    If wNEv < 16 Then
        evType(wNEv) = t: evA(wNEv) = a: evB(wNEv) = b
        wNEv = wNEv + 1
    End If
End Sub

Public Function WorldPopEvent(t As Long, a As Long, b As Long) As Boolean
    Dim i As Long
    If wNEv = 0 Then Exit Function
    t = evType(0): a = evA(0): b = evB(0)
    For i = 1 To wNEv - 1
        evType(i - 1) = evType(i): evA(i - 1) = evA(i): evB(i - 1) = evB(i)
    Next i
    wNEv = wNEv - 1
    WorldPopEvent = True
End Function

Public Sub WorldSay(ByVal m As Long)
    wMsg = m
    wMsgTimer = 75
    Push EV_SAY, m, 0
End Sub

Public Sub WorldDefaults()
    tuGodMode = 0: tuAiPerfect = 0: tuTrafficPct = 100: tuSpeedPct = 100: tuMultSecs = 8: tuAquaKmh = 50
End Sub

Private Function Rnd15() As Long
    Rnd15 = A3Rand(wRng)
End Function

' ---------- damage ----------
Private Sub Hurt(ByVal n As Long, ByVal ev As Long)
    wIncident = 1
    If tuGodMode <> 0 Or wState <> GS_PLAY Then n = 0
    wCover = wCover - n
    If wCover < 0 Then wCover = 0
    Push ev, n, wCover
    If wCover = 0 And wState = GS_PLAY Then
        wState = GS_GAMEOVER
        wStateTimer = 50
        aiOn = 0
        Push EV_GAME_OVER, wScore, wRoute
        WorldSay MSG_CANCELLED
    End If
End Sub

' ---------- objects ----------
Public Function WorldSpawn(ByVal typ As Long, ByVal z As Long, ByVal d As Long, ByVal v As Long, ByVal flags As Long) As Long
    Dim i As Long
    For i = 0 To MAX_OBJS - 1
        If obType(i) = OBJ_NONE Then
            obType(i) = typ: obFlags(i) = flags And 255: obHz(i) = -1
            obZ(i) = z: obD(i) = d: obV(i) = v: obVt(i) = v: obVd(i) = 0
            obTimer(i) = 0: obCool(i) = 0
            If d < 0 Then obLane(i) = -1 - (ShrA(-d, FBITS) \ LANE_W) Else obLane(i) = LaneOf(d)
            obColour(i) = Rnd15() And 3
            WorldSpawn = i
            Exit Function
        End If
    Next i
    WorldSpawn = -1
End Function

' is lane free of moving things from dz0 to dz1 segments around z?
Private Function LaneClear(ByVal lane As Long, ByVal z As Long, ByVal dz0 As Long, ByVal dz1 As Long, ByVal skip As Long) As Boolean
    Dim i As Long, dz As Long
    For i = 0 To MAX_OBJS - 1
        If obLane(i) = lane Then
            If obType(i) <> OBJ_NONE And i <> skip Then
                dz = obZ(i) - z
                If dz > dz0 * SEGF And dz < dz1 * SEGF Then Exit Function
            End If
        End If
    Next i
    LaneClear = True
End Function

' where to pass something small in the lane: on the shoulder if there's room, otherwise to its left
Private Function SwerveTo(ByVal o As Long) As Long
    Dim rt As Long
    rt = ShrA(obD(o), FBITS) + objWid(obType(o)) + CAR_WID + 12
    If rt + CAR_WID <= RoadRight() + SHOULDER Then
        SwerveTo = rt * 16
    Else
        SwerveTo = obD(o) - (objWid(obType(o)) + CAR_WID + 12) * 16
    End If
End Function

' may object skip move into lane at z? (the car counts too)
Private Function LaneFreeFor(ByVal lane As Long, ByVal z As Long, ByVal skip As Long) As Boolean
    Dim dz As Long
    dz = carZ - z
    If carD >= 0 Then
        If LaneOf(carD) = lane And dz > -3 * SEGF And dz < 3 * SEGF Then Exit Function
    End If
    If lane < 0 And carD < 0 And dz > -3 * SEGF And dz < 3 * SEGF Then Exit Function
    LaneFreeFor = LaneClear(lane, z, -2, 3, skip)
End Function

' a cone on segment seg? its offset into d
Public Function ConeAt(ByVal sg As Long, d As Long) As Boolean
    Dim start As Long, i As Long, lane As Long
    If sg < 0 Or sg >= wNSeg Then Exit Function
    If (sgFlags(sg) And SF_CONES) = 0 Then Exit Function
    lane = 0
    Do While lane < 8
        If (sgClosed(sg) And (2 ^ lane)) <> 0 Then Exit Do
        lane = lane + 1
    Loop
    start = sg
    Do While start > 0
        If (sgFlags(start - 1) And SF_CONES) = 0 Then Exit Do
        start = start - 1
    Loop
    i = sg - start
    If i < 3 Then                        ' the taper, across the lane
        d = lane * LANE_W + ((i + 1) * LANE_W) \ 4
        ConeAt = True
    ElseIf i Mod 3 = 0 Then
        d = LaneCentre(lane)
        ConeAt = True
    End If
End Function

Private Sub SpawnHazard(ByVal i As Long)
    Dim z As Long, rr As Long, k As Long, o As Long, lane As Long, nl As Long
    z = hzSeg(i) * SEGF
    rr = RoadRight()
    nl = riNl(wRoute)
    o = -1
    Select Case hzType(i)
        Case HZ_CYCLIST
            o = WorldSpawn(OBJ_CYCLIST, z, (rr - 10) * 16, FromKmh(20), 0)
        Case HZ_DEER
            o = WorldSpawn(OBJ_DEER, z, (rr + 50) * 16, 0, 0)
        Case HZ_GOATS, HZ_PEDS
            For k = 0 To 2
                o = WorldSpawn(IIf(hzType(i) = HZ_GOATS, OBJ_GOAT, OBJ_PED), z + k * (SEGF \ 3), (rr + 40 + k * 22) * 16, 0, 0)
                If o >= 0 Then obHz(o) = i
            Next k
            o = -1
        Case HZ_TRACTOR
            o = WorldSpawn(OBJ_TRACTOR, z, LaneCentre(nl - 1) * 16, FromKmh(25), 0)
        Case HZ_MERGE
            o = WorldSpawn(OBJ_TRUCK, z, (rr + 34) * 16, FromKmh(60), 0)
            If o >= 0 Then obLane(o) = nl        ' on the slip road, for now
        Case HZ_PHANTOM
            o = WorldSpawn(OBJ_TRUCK, carZ - 4 * SEGF, LaneCentre(LaneOf(carD)) * 16, carV + FromKmh(15), OF_TAILGATE)
        Case HZ_SIREN
            o = WorldSpawn(OBJ_AMBULANCE, carZ - 12 * SEGF, LaneCentre(LaneOf(carD)) * 16, carV + FromKmh(40), 0)
            wSiren = 1
            Push EV_SIREN, hzSeg(i), 0
        Case HZ_DEBRIS
            If hzParam(i) >= 0 Then
                lane = hzParam(i)
            ElseIf carD >= 0 Then
                lane = LaneOf(carD)
            Else
                lane = nl - 1
            End If
            o = WorldSpawn(OBJ_DEBRIS, z, LaneCentre(lane) * 16, 0, 0)
    End Select
    If o >= 0 Then obHz(o) = i
End Sub

Private Sub ResolveHazard(ByVal i As Long)
    hzState(i) = 2
    If wPendingSave <> i Then Exit Sub
    If wIncident = 0 And wState = GS_PLAY Then
        wSaves = wSaves + 1
        wTotalSaves = wTotalSaves + 1
        wScore = wScore + 500
        Push EV_SAVE, hzType(i), wSaves
        WorldSay MSG_GOOD_CATCH
    End If
    wPendingSave = -1
End Sub

Private Sub HazardsUpdate()
    Dim cs As Long, i As Long, trig As Boolean
    cs = SegOf(carZ)
    For i = 0 To wNHaz - 1
        If hzState(i) = 0 Then
            If hzType(i) = HZ_SIREN Then trig = cs >= hzSeg(i) Else trig = hzSeg(i) - cs <= 32
            If trig Then
                hzState(i) = 1
                SpawnHazard i
            End If
        ElseIf hzState(i) = 1 And hzType(i) <> HZ_SIREN And cs > hzSeg(i) + hzLen(i) + 2 Then
            ResolveHazard i
        End If
    Next i
End Sub

' a failing hazard within segs ahead, -1
Public Function WorldHazardAhead(ByVal segs As Long) As Long
    Dim cs As Long, i As Long
    cs = SegOf(carZ)
    For i = 0 To wNHaz - 1
        If HzFails(hzType(i)) And hzState(i) <> 2 Then
            If hzType(i) = HZ_SIREN Then
                If hzState(i) = 1 Then
                    WorldHazardAhead = i
                    Exit Function
                End If
            ElseIf hzSeg(i) - cs <= segs And cs <= hzSeg(i) + hzLen(i) + 1 Then
                WorldHazardAhead = i
                Exit Function
            End If
        End If
    Next i
    WorldHazardAhead = -1
End Function

' ---------- traffic ----------
Private Sub TrafficSpawn()
    Dim want As Long, n As Long, i As Long, cs As Long, sg As Long, lane As Long, typ As Long, d As Long, v As Long, z As Long
    Dim nl As Long, no As Long, lim As Long
    nl = riNl(wRoute): no = riNo(wRoute): lim = riLimit(wRoute)
    want = ((riTraffic(wRoute) * 70) \ 100) * tuTrafficPct \ 100
    cs = SegOf(carZ)
    For i = 0 To MAX_OBJS - 1
        If obHz(i) < 0 And (obType(i) = OBJ_CAR Or obType(i) = OBJ_TRUCK) Then n = n + 1
    Next i
    If n >= want Then Exit Sub
    If (Rnd15() And 7) <> 0 Then Exit Sub
    If Rnd15() Mod 5 <> 0 Then typ = OBJ_CAR Else typ = OBJ_TRUCK
    Dim branch As Long
    branch = 2
    If no <> 0 Then
        If Rnd15() Mod 3 = 0 Then branch = 0
    End If
    If branch = 2 And nl > 1 Then
        If Rnd15() Mod 4 = 0 Then branch = 1
    End If
    If branch = 0 Then
        sg = cs + 30 + (Rnd15() Mod 6)
        lane = -1 - (Rnd15() Mod no)
        v = -FromKmh((lim * (85 + (Rnd15() Mod 20))) \ 100)
    ElseIf branch = 1 Then
        ' a faster car coming up from behind in a lane we're not in
        sg = cs - 9
        lane = Rnd15() Mod (nl - 1)
        If carD >= 0 Then
            If lane = LaneOf(carD) Then Exit Sub
        End If
        v = FromKmh((lim * (110 + (Rnd15() Mod 15))) \ 100)
        typ = OBJ_CAR
    Else
        sg = cs + 30 + (Rnd15() Mod 6)
        lane = Rnd15() Mod nl
        If nl = 1 Then                   ' no overtaking here: about the limit
            v = FromKmh((lim * (92 + (Rnd15() Mod 14))) \ 100)
        ElseIf typ = OBJ_TRUCK Then
            v = FromKmh((lim * 55) \ 100)
        Else
            v = FromKmh((lim * (65 + (Rnd15() Mod 25))) \ 100)
        End If
    End If
    If sg < 1 Or sg >= wFinish Then Exit Sub
    If lane >= 0 Then
        If (sgClosed(sg) And (2 ^ lane)) <> 0 Then Exit Sub
    End If
    If lane < 0 Then                     ' not inside a detour through the oncoming lane
        For i = sg - 3 To sg + 3
            If i >= 0 And i < wNSeg Then
                If (sgClosed(i) And 1) <> 0 And nl = 1 Then Exit Sub
            End If
        Next i
    End If
    z = sg * SEGF
    If Not LaneClear(lane, z, -3, 3, -1) Then Exit Sub
    d = LaneCentre(lane) * 16
    i = WorldSpawn(typ, z, d, v, IIf(v < 0, OF_ONCOMING, 0))
    If i >= 0 Then obLane(i) = lane
End Sub

' the speed history, for the truck that reacts late
Private Function CarVAgo(ByVal frames As Long) As Long
    CarVAgo = carHist((carHistPos - frames) And 31)
End Function

Private Sub VehicleFollow(ByVal i As Long)
    Dim best As Long, leadV As Long, dz As Long, gap As Long, des As Long, t As Long, k As Long, ln As Long, found As Boolean
    Dim lim As Long, near As Boolean, t2 As Long
    best = 5 * SEGF
    t = obVt(i)
    ln = objLen(obType(i))
    For k = 0 To MAX_OBJS - 1
        t2 = obType(k)
        If t2 <> OBJ_NONE Then
            If k <> i And obV(k) >= 0 And t2 <> OBJ_CYCLIST And t2 <> OBJ_DEBRIS Then
                If Abs(obD(k) - obD(i)) <= 40 * 16 Then
                    dz = obZ(k) - obZ(i)
                    If dz > 0 And dz < best Then
                        best = dz: leadV = obV(k): found = True
                    End If
                End If
            End If
        End If
    Next k
    dz = carZ - obZ(i)
    If carState = CS_DRIVING And dz > 0 And dz < best Then
        near = Abs(carD - obD(i)) < 40 * 16
        If Not near And carD >= 0 Then near = LaneOf(carD) = obLane(i)
        If near Then
            best = dz
            leadV = carV
            found = True
        End If
    End If
    If found Then
        gap = ShrA(best, FBITS) - ln - CAR_LEN
        des = (obV(i) * 25) \ 16 + 30
        If gap < des Then
            lim = leadV + (gap - des) * 2
            If lim < 0 Then lim = 0
            If lim < t Then t = lim
        End If
    End If
    If obV(i) < t Then
        obV(i) = obV(i) + 3
        If obV(i) > t Then obV(i) = t
    ElseIf obV(i) > t Then
        obV(i) = obV(i) - 10
        If obV(i) < t Then obV(i) = t
    End If
End Sub

Private Sub MoveAcross(ByVal o As Long, ByVal target As Long, ByVal rate As Long)
    If obD(o) < target Then
        obD(o) = obD(o) + rate
        If obD(o) > target Then obD(o) = target
    ElseIf obD(o) > target Then
        obD(o) = obD(o) - rate
        If obD(o) < target Then obD(o) = target
    End If
End Sub

Private Sub ObjectsUpdate()
    Dim i As Long, dz As Long, gap As Long, os As Long, cs As Long, k As Long, wt As Boolean, stp As Long, start As Long
    Dim tgt As Long, blocking As Boolean, late As Long, t As Long, s As Long, too As Long, ahead As Long, lane As Long
    Dim blocked As Boolean, nl As Long
    nl = riNl(wRoute)
    For i = 0 To MAX_OBJS - 1
        If obType(i) <> OBJ_NONE Then
            If obCool(i) > 0 Then obCool(i) = obCool(i) - 1
            dz = obZ(i) - carZ
            Select Case obType(i)
                Case OBJ_CAR, OBJ_TRUCK
                    If (obFlags(i) And OF_ONCOMING) <> 0 Then
                        If (obFlags(i) And OF_KNOCKED) <> 0 Then
                            obV(i) = 0                ' a wreck
                        Else
                            ' brake for the car in our lane, and wait after a detour through our
                            ' lane until the car is through it
                            gap = ShrA(dz, FBITS) - objLen(obType(i)) - CAR_LEN
                            os = SegOf(obZ(i)): cs = SegOf(carZ): wt = False
                            If nl = 1 And dz > 0 Then
                                k = os - 2
                                Do While k >= cs And k > os - 40
                                    If k < wNSeg Then
                                        If (sgClosed(k) And 1) <> 0 Then
                                            ' k is the zone's far end: wait there while the car is about to come through
                                            stp = (k + 4) * SEGF
                                            start = k
                                            Do While start > 0
                                                If (sgClosed(start - 1) And 1) = 0 Then Exit Do
                                                start = start - 1
                                            Loop
                                            wt = cs >= start - 12 And obZ(i) > stp And obZ(i) - stp < 3 * SEGF
                                            Exit Do
                                        End If
                                    End If
                                    k = k - 1
                                Loop
                            End If
                            tgt = LaneCentre(obLane(i)) * 16
                            blocking = Abs(carD - obD(i)) < 34 * 16 And gap > -10 And gap < 4 * SEG_LEN
                            If blocking And obV(i) = 0 Then
                                obTimer(i) = obTimer(i) + 1
                                If obTimer(i) > 50 Then obFlags(i) = obFlags(i) Or OF_PASSING
                            End If
                            If (obFlags(i) And OF_PASSING) <> 0 Then
                                ' given up waiting: over to the kerb until the car is past
                                tgt = (RoadLeft() - 26) * 16
                                If dz < -2 * SEGF Then
                                    obFlags(i) = obFlags(i) And Not OF_PASSING
                                    obTimer(i) = 0
                                End If
                                blocking = dz > 0 And gap < 2 * SEG_LEN And Abs(obD(i) - tgt) > 4 * 16
                            End If
                            If wt Or blocking Then
                                obV(i) = obV(i) + 10
                                If obV(i) > 0 Then obV(i) = 0
                            ElseIf obCool(i) = 0 And obV(i) > obVt(i) Then
                                obV(i) = obV(i) - 4
                                If obV(i) < obVt(i) Then obV(i) = obVt(i)
                            End If
                            MoveAcross i, tgt, 16
                        End If
                    ElseIf (obFlags(i) And OF_TAILGATE) <> 0 Then
                        ' sits close behind and reacts to the car half a second late
                        gap = ShrA(-dz, FBITS) - objLen(obType(i)) - CAR_LEN
                        late = CarVAgo(12)
                        t = late + (gap - 48) * 2
                        If t > late + FromKmh(30) Then t = late + FromKmh(30)
                        If t < 0 Then t = 0
                        If obV(i) < t Then
                            obV(i) = obV(i) + 6
                            If obV(i) > t Then obV(i) = t
                        ElseIf obV(i) > t Then
                            obV(i) = obV(i) - 12
                            If obV(i) < t Then obV(i) = t
                        End If
                        If carD >= 0 Then obD(i) = LaneCentre(LaneOf(carD)) * 16
                        If obHz(i) >= 0 Then
                            If hzState(obHz(i)) = 2 Then
                                obFlags(i) = obFlags(i) And Not OF_TAILGATE   ' off it goes
                                obVt(i) = FromKmh(riLimit(wRoute))
                                If nl > 1 Then obLane(i) = 0 Else obLane(i) = nl - 1
                            End If
                        End If
                    ElseIf IsMergingTruck(i) Then
                        If dz > 0 And dz < 8 * SEGF Then obLane(i) = hzParam(obHz(i))
                    Else
                        ' round a closed lane: the next lane, or the oncoming one
                        If obLane(i) >= 0 Then
                            s = SegOf(obZ(i)) + 6
                            If s < wNSeg Then
                                If (sgClosed(s) And (2 ^ obLane(i))) <> 0 Then
                                    If obLane(i) > 0 Then too = obLane(i) - 1 Else too = -1
                                    If LaneFreeFor(too, obZ(i), i) Then obLane(i) = too
                                ElseIf (sgFlags(s) And SF_CONES) = 0 And obLane(i) < 0 And (obFlags(i) And OF_ONCOMING) = 0 Then
                                    obLane(i) = 0
                                End If
                            End If
                        End If
                        VehicleFollow i
                        ' round a cyclist, within the lane
                        tgt = LaneCentre(obLane(i)) * 16
                        For k = 0 To MAX_OBJS - 1
                            If obType(k) = OBJ_CYCLIST Or obType(k) = OBJ_DEBRIS Then
                                ahead = obZ(k) - obZ(i)
                                If ahead > -SEGF And ahead < 6 * SEGF And Abs(obD(k) - tgt) < 34 * 16 Then
                                    If obType(k) = OBJ_CYCLIST Then
                                        tgt = obD(k) - 34 * 16
                                    ElseIf obType(k) = OBJ_DEBRIS Then
                                        tgt = SwerveTo(k)
                                    End If
                                End If
                            End If
                        Next k
                        MoveAcross i, tgt, 20
                    End If

                Case OBJ_AMBULANCE
                    If (obFlags(i) And OF_PASSING) = 0 Then
                        ' catch up, then sit behind the car until it moves over
                        gap = ShrA(-dz, FBITS) - objLen(obType(i)) - CAR_LEN
                        If gap > 120 Then
                            obV(i) = carV + FromKmh(40)
                        Else
                            obV(i) = carV
                            obTimer(i) = obTimer(i) + 1
                        End If
                        If Abs(carD - obD(i)) > 45 * 16 Or carState <> CS_DRIVING Then
                            obFlags(i) = obFlags(i) Or OF_PASSING
                        ElseIf obTimer(i) > 75 Then
                            ' a ticket, unless the traffic left nowhere to move over to
                            If carD >= 0 Then lane = LaneOf(carD) Else lane = 0
                            blocked = nl > 1
                            If blocked And lane > 0 Then
                                If LaneClear(lane - 1, carZ, -2, 3, i) Then blocked = False
                            End If
                            If blocked And lane < nl - 1 Then
                                If LaneClear(lane + 1, carZ, -2, 3, i) Then blocked = False
                            End If
                            If blocked Then
                                obTimer(i) = 15              ' and time to move once it can
                            Else
                                obFlags(i) = obFlags(i) Or OF_PASSING
                                Hurt 10, EV_TICKET
                                WorldSay MSG_TICKET
                            End If
                        End If
                    Else
                        ' out from behind the car first, then away
                        If Abs(carD - obD(i)) < 34 * 16 And dz < 0 Then obV(i) = carV Else obV(i) = carV + FromKmh(50)
                        If Abs(carD - obD(i)) <= 45 * 16 And dz < 2 * SEGF Then
                            ' still in the way: round it, by another lane or the oncoming one
                            If nl > 1 Then
                                If carD >= 0 Then lane = LaneOf(carD) Else lane = 0
                                If lane > 0 Then obLane(i) = lane - 1 Else obLane(i) = 1
                            Else
                                obLane(i) = -1
                            End If
                        End If
                        MoveAcross i, LaneCentre(obLane(i)) * 16, 24
                        If dz > 3 * SEGF And obHz(i) >= 0 Then
                            If hzState(obHz(i)) = 1 Then
                                wSiren = 0
                                ResolveHazard obHz(i)
                            End If
                        End If
                    End If

                Case OBJ_TRACTOR
                    If obHz(i) >= 0 Then
                        If SegOf(obZ(i)) > hzSeg(obHz(i)) + hzLen(obHz(i)) Then
                            obD(i) = obD(i) + 20             ' turns off into a field
                            obV(i) = FromKmh(10)
                            If ShrA(obD(i), FBITS) > RoadRight() + 220 Then obType(i) = OBJ_NONE
                        Else
                            VehicleFollow i
                        End If
                    Else
                        VehicleFollow i
                    End If

                Case OBJ_DEER, OBJ_GOAT, OBJ_PED
                    ' cross when the car is close; a hit one is thrown aside
                    If obVd(i) = 0 And dz > 0 And dz < IIf(obType(i) = OBJ_PED, 6, 5) * SEGF And obTimer(i) = 0 Then
                        obTimer(i) = 1
                        If obType(i) = OBJ_PED Then obVd(i) = -18 Else obVd(i) = -30
                    End If
                    obD(i) = obD(i) + obVd(i)
            End Select
            obZ(i) = obZ(i) + obV(i)
            If obType(i) <> OBJ_NONE Then
                dz = obZ(i) - carZ
                If dz < -20 * SEGF Or dz > 48 * SEGF Or SegOf(obZ(i)) >= wNSeg - 1 Or obZ(i) < 0 Then
                    If obType(i) = OBJ_AMBULANCE Then
                        wSiren = 0
                        If obHz(i) >= 0 Then
                            If hzState(obHz(i)) = 1 Then ResolveHazard obHz(i)
                        End If
                    End If
                    obType(i) = OBJ_NONE
                End If
            End If
        End If
    Next i
End Sub

Private Function IsMergingTruck(ByVal i As Long) As Boolean
    If obHz(i) >= 0 Then
        If hzType(obHz(i)) = HZ_MERGE And obLane(i) = riNl(wRoute) Then IsMergingTruck = True
    End If
End Function

Private Sub Collide()
    Dim i As Long, k As Long, cs As Long, dz As Long, dd As Long, ln As Long, wd As Long, cd As Long
    If carState <> CS_DRIVING And carState <> CS_AQUAPLANE Then Exit Sub
    For i = 0 To MAX_OBJS - 1
        If obType(i) <> OBJ_NONE And obCool(i) = 0 And (obFlags(i) And OF_KNOCKED) = 0 Then
            dz = ShrA(obZ(i) - carZ, FBITS)
            dd = ShrA(obD(i) - carD, FBITS)
            ln = objLen(obType(i))
            wd = objWid(obType(i))
            If Abs(dz) < CAR_LEN + ln And Abs(dd) < CAR_WID + wd Then
                Select Case obType(i)
                    Case OBJ_DEBRIS
                        obType(i) = OBJ_NONE
                        carV = (carV * 3) \ 4
                        Hurt 10, EV_DEBRIS
                        WorldSay MSG_OOPS
                    Case OBJ_DEER, OBJ_GOAT, OBJ_PED, OBJ_CYCLIST
                        obCool(i) = 1000
                        If dd > 0 Then obVd(i) = 60 Else obVd(i) = -60
                        obV(i) = 0
                        carV = carV \ 2
                        Hurt 20, EV_HIT_ANIMAL
                        WorldSay MSG_OOPS
                    Case Else
                        obCool(i) = 50
                        If obV(i) < 0 Then
                            ' head on: the other car ends up a wreck at the roadside
                            carV = 0
                            obV(i) = 0
                            obFlags(i) = obFlags(i) Or OF_KNOCKED
                            obD(i) = obD(i) - 48 * 16
                            Hurt 35, EV_CRASH
                        ElseIf dz > 0 Then
                            carV = (obV(i) * 3) \ 4
                            carZ = obZ(i) - (CAR_LEN + ln + 2) * 16
                            Hurt 25, EV_CRASH
                        Else
                            obV(i) = (carV * 3) \ 4
                            obZ(i) = carZ - (CAR_LEN + ln + 2) * 16
                            obFlags(i) = obFlags(i) And Not OF_TAILGATE
                            Hurt 15, EV_REAREND
                        End If
                        WorldSay MSG_OOPS
                End Select
            End If
        End If
    Next i
    ' cones in a closed lane
    cs = SegOf(carZ)
    For k = cs To cs + 1
        If k < wNSeg Then
            If sgKnocked(k) = 0 Then
                If ConeAt(k, cd) Then
                    If Abs(ShrA(k * SEGF - carZ, FBITS)) < CAR_LEN + 4 And Abs(ShrA(carD, FBITS) - cd) < CAR_WID + 4 Then
                        sgKnocked(k) = 1
                        carV = (carV * 7) \ 8
                        Hurt 2, EV_CONE
                    End If
                End If
            End If
        End If
    Next k
End Sub

' ---------- the autopilot ----------
Public Function WorldApAllowed() As Boolean
    Dim lane As Long
    If carState <> CS_DRIVING Or carD < 0 Then Exit Function      ' it can pull away from a standstill
    If wState <> GS_PLAY And wState <> GS_TITLE Then Exit Function
    lane = LaneOf(carD)
    WorldApAllowed = Abs(ShrA(carD, FBITS) - LaneCentre(lane)) <= LANE_W \ 4
End Function

Private Sub Takeover()
    Dim h As Long
    aiOn = 0
    wTakeovers = wTakeovers + 1
    wMult = 1
    wApFrames = 0
    Push EV_AP_OFF, wTakeovers, 0
    If wState <> GS_PLAY Then Exit Sub
    h = WorldHazardAhead(24)
    If h >= 0 Then
        wPendingSave = h
        wIncident = 0
        WorldSay MSG_AP_OFF
    Else
        wNeedless = wNeedless + 1
        wTotalNeedless = wTotalNeedless + 1
        Push EV_NEEDLESS, wNeedless, 0
        WorldSay MSG_HAD_THAT
    End If
End Sub

Public Sub WorldSetAp(ByVal onOff As Boolean)
    If onOff And aiOn = 0 Then
        If Not WorldApAllowed() Then
            Push EV_UNAVAILABLE, 0, 0
            WorldSay MSG_UNAVAILABLE
            Exit Sub
        End If
        aiOn = 1
        aiLane = LaneOf(carD)
        wApFrames = 0
        Push EV_AP_ON, 0, 0
        WorldSay MSG_AP_ON
    ElseIf Not onOff And aiOn <> 0 Then
        Takeover
    End If
End Sub

Private Function Perfect() As Boolean
    Perfect = tuAiPerfect <> 0 Or wState = GS_TITLE
End Function

' the lane change rules on a multi-lane road
Private Sub AiLanes()
    Dim i As Long, cs As Long, nl As Long, too As Long, en As Long, dz As Long, sg As Long
    nl = riNl(wRoute)
    cs = SegOf(carZ)
    If aiLaneHold > 0 Then
        aiLaneHold = aiLaneHold - 1
        Exit Sub
    End If
    If Perfect() Then
        ' round a closed lane
        For i = 2 To 13
            If aiLane >= 0 And cs + i < wNSeg Then
                If (sgClosed(cs + i) And (2 ^ aiLane)) <> 0 Then
                    If aiLane > 0 Then
                        too = aiLane - 1
                    ElseIf nl > 1 Then
                        too = 1
                    Else
                        too = -1
                    End If
                    en = cs + i
                    Do While en < wNSeg - 1
                        If (sgFlags(en) And SF_CONES) = 0 Then Exit Do
                        en = en + 1
                    Loop
                    If too < 0 Then
                        If Not LaneClear(-1, carZ, -2, en - cs + 1, -1) Then Exit Sub
                    End If
                    aiLane = too
                    aiLaneHold = 50
                    Exit Sub
                End If
            End If
        Next i
        If cs < wNSeg - 14 Then sg = cs + 13 Else sg = cs
        If aiLane < 0 And (sgFlags(sg) And SF_CONES) = 0 And (sgFlags(cs) And SF_CONES) = 0 Then
            aiLane = 0
            aiLaneHold = 50
            Exit Sub
        End If
    End If
    If nl < 2 Or aiLane < 0 Then Exit Sub
    If Perfect() Then
        ' move over for an ambulance
        For i = 0 To MAX_OBJS - 1
            dz = obZ(i) - carZ
            If obType(i) = OBJ_AMBULANCE And (obFlags(i) And OF_PASSING) = 0 And obLane(i) = aiLane And dz < 0 And dz > -10 * SEGF Then
                If aiLane > 0 Then too = aiLane - 1 Else too = aiLane + 1
                If Not LaneClear(too, carZ, -2, 3, i) Then
                    If aiLane < nl - 1 Then too = aiLane + 1 Else too = -9
                End If
                If too >= 0 And too < nl Then
                    If LaneClear(too, carZ, -2, 3, i) Then
                        aiLane = too
                        aiLaneHold = 125
                    End If
                End If
                Exit Sub
            End If
        Next i
    End If
    ' overtake a slow car ahead, then keep right
    For i = 0 To MAX_OBJS - 1
        dz = obZ(i) - carZ
        If obType(i) <> OBJ_NONE And obLane(i) = aiLane And dz > 0 And dz <= 6 * SEGF Then
            If obType(i) = OBJ_CAR Or obType(i) = OBJ_TRUCK Or obType(i) = OBJ_TRACTOR Then
                If obV(i) < aiTargetV - FromKmh(10) And aiLane > 0 Then
                    If LaneClear(aiLane - 1, carZ, -4, 5, -1) Then
                        aiLane = aiLane - 1
                        aiLaneHold = 100
                        Exit Sub
                    End If
                End If
            End If
        End If
    Next i
    If aiLane < nl - 1 Then
        If LaneClear(aiLane + 1, carZ, -3, 7, -1) Then
            For i = 0 To 15
                If cs + i >= wNSeg Then Exit For
                If (sgClosed(cs + i) And (2 ^ (aiLane + 1))) <> 0 Then Exit Sub
            Next i
            aiLane = aiLane + 1
            aiLaneHold = 100
        End If
    End If
End Sub

Public Function AquaKmh() As Long
    ' the town's flooded streets are deeper: they aquaplane at lower speed
    If wRoute = 3 Then AquaKmh = (tuAquaKmh * 3) \ 5 Else AquaKmh = tuAquaKmh
End Function

Public Sub AiThink()
    Dim cs As Long, k As Long, i As Long, perf As Boolean, limit As Long, z As Long, d As Long, x As Long, dz As Long, s0 As Long
    Dim sg As Long, too As Long, slow As Long, pd As Long, gap As Long, des As Long, ov As Long, idx As Long, ln As Long
    Dim dd As Long, band As Long, hit As Boolean, later As Long, stp As Long, t As Long, inl As Long, cl As Long, nl As Long
    nl = riNl(wRoute)
    cs = SegOf(carZ)
    perf = Perfect()
    ' the low sun
    If Not perf And wGlare >= 12 Then
        If aiBlinded = 0 Then
            aiBlinded = 1
            aiBlindZ = carZ
            aiBlindX = RoadCx(carZ) * 16 + carD
            If cs < wNSeg Then aiBlindDir = sgDir(cs) Else aiBlindDir = sgDir(wNSeg - 1)
            If aiOn <> 0 Then
                Push EV_BLINDED, cs, 0
                WorldSay MSG_BLINDED
            End If
        End If
    ElseIf aiBlinded <> 0 And wGlare < 6 Then
        aiBlinded = 0
        If aiOn <> 0 Then WorldSay MSG_RECALC
    End If

    If aiOn <> 0 Then AiLanes

    ' the plan: where it means to be at each of the next 16 segments
    aiPlanFrom = cs
    For k = 0 To 15
        z = (cs + k) * SEGF
        If aiBlinded <> 0 Then
            x = aiBlindX + ShrA(aiBlindDir * (z - aiBlindZ), SEG_BITS)
            d = x - RoadCx(z) * 16
        Else
            d = LaneCentre(aiLane) * 16
            If Not perf Then d = d + GhostAt(z) * 16
        End If
        aiPlan(k) = d
    Next k
    ' give a cyclist room: move over within the lane to pass
    For i = 0 To MAX_OBJS - 1
        dz = obZ(i) - carZ
        If obType(i) = OBJ_CYCLIST And dz >= -2 * SEGF And dz <= 8 * SEGF And aiBlinded = 0 Then
            s0 = SegOf(obZ(i)) - cs
            For k = s0 - 6 To s0 + 2
                If k >= 0 And k < 16 Then
                    If Abs(aiPlan(k) - obD(i)) < 34 * 16 Then aiPlan(k) = obD(i) - 34 * 16
                End If
            Next k
        End If
    Next i
    If perf Then
        ' pull over for an ambulance, swerve round debris
        For i = 0 To MAX_OBJS - 1
            dz = obZ(i) - carZ
            If obType(i) = OBJ_AMBULANCE And (obFlags(i) And OF_PASSING) = 0 And dz < 0 And dz > -8 * SEGF And nl = 1 Then
                For k = 0 To 15: aiPlan(k) = aiPlan(k) + 50 * 16: Next k
            End If
            If obType(i) = OBJ_DEBRIS And dz > -SEGF And dz < 12 * SEGF And Abs(obD(i) - aiPlan(0)) < 30 * 16 Then
                sg = SegOf(obZ(i)) - cs
                too = SwerveTo(i)
                For k = sg - 8 To sg + 1
                    If k >= 0 And k < 16 Then aiPlan(k) = too
                Next k
            End If
        Next i
    End If

    ' what it sees
    aiNSeen = 0
    If aiBlinded = 0 Then
        For i = 0 To MAX_OBJS - 1
            If aiNSeen >= MAX_SEEN Then Exit For
            dz = obZ(i) - carZ
            If obType(i) <> OBJ_NONE And dz >= -6 * SEGF And dz <= 30 * SEGF And Not (obType(i) = OBJ_DEBRIS And Not perf) Then
                snZ(aiNSeen) = obZ(i): snD(aiNSeen) = obD(i): snType(aiNSeen) = obType(i): snPhantom(aiNSeen) = 0
                aiNSeen = aiNSeen + 1
            End If
        Next i
    End If

    ' the overpass shadow: something huge in the lane, it decides
    If Not perf And aiOn <> 0 And aiPhantomTimer = 0 Then
        For k = 1 To 6
            If cs + k >= wNSeg Then Exit For
            sg = cs + k
            If (sgFlags(sg) And SF_OVERPASS) <> 0 And (sgFlags(sg - 1) And SF_OVERPASS) = 0 And sg <> aiPhantomSeg Then
                aiPhantomSeg = sg
                aiPhantomTimer = 30
                Push EV_PHANTOM, sg, 0
                WorldSay MSG_OBSTACLE
                Exit For
            End If
        Next k
    End If
    If aiPhantomTimer > 0 Then
        If aiNSeen < MAX_SEEN Then
            snZ(aiNSeen) = aiPhantomSeg * SEGF: snD(aiNSeen) = carD: snType(aiNSeen) = OBJ_CAR: snPhantom(aiNSeen) = 1
            aiNSeen = aiNSeen + 1
        End If
        aiPhantomTimer = aiPhantomTimer - 1
        If aiPhantomTimer = 0 And aiOn <> 0 Then WorldSay MSG_RECALC
    End If

    ' speed
    limit = FromKmh((riLimit(wRoute) * tuSpeedPct) \ 100)
    If perf Then
        For k = 0 To 8
            If cs + k >= wNSeg Then Exit For
            If (sgFlags(cs + k) And SF_FLOOD) <> 0 Then
                slow = FromKmh((AquaKmh() * 7) \ 10)
                If slow < limit Then limit = slow
                Exit For
            End If
        Next k
    End If
    For i = 0 To aiNSeen - 1
        dz = snZ(i) - carZ
        If dz > 0 And snPhantom(i) = 0 Then
            ov = 0
            idx = SegOf(snZ(i)) - cs
            If idx > 15 Then idx = 15
            If idx < 0 Then pd = aiPlan(0) Else pd = aiPlan(idx)
            ln = objLen(snType(i))
            ' in the path, or about to cross it
            dd = Abs(snD(i) - pd)
            band = (CAR_WID + objWid(snType(i)) + 6) * 16
            hit = dd < band
            For k = 0 To MAX_OBJS - 1
                If hit Then Exit For
                If obType(k) = snType(i) And obZ(k) = snZ(i) And obD(k) = snD(i) And obVd(k) <> 0 Then
                    later = obD(k) + obVd(k) * 45
                    hit = (obD(k) > pd + band And later < pd + band) Or (obD(k) < pd - band And later > pd - band)
                    ov = obV(k)
                End If
            Next k
            If hit Then
                For k = 0 To MAX_OBJS - 1
                    If obType(k) = snType(i) And obZ(k) = snZ(i) Then
                        ov = obV(k)
                        Exit For
                    End If
                Next k
                If ov < 0 Then ov = 0
                gap = ShrA(dz, FBITS) - ln - CAR_LEN
                If ov = 0 Then
                    ' standing or crossing: stop short of it
                    stp = (carV * carV) \ (2 * 8 * 16) + 50
                    If gap < stp + 60 Then limit = 0
                Else
                    des = (carV * 25) \ 16 + 30
                    If gap < des Then
                        t = ov + (gap - des) * 2
                        If t < 0 Then t = 0
                        If t < limit Then limit = t
                    End If
                End If
            End If
        End If
    Next i
    If aiPhantomTimer > 0 Then limit = 0
    If perf Then
        ' wait before cones it can't get round yet; creep while moving over
        If carD >= 0 Then inl = LaneOf(carD) Else inl = -1
        For k = 1 To 5
            If cs + k >= wNSeg Then Exit For
            cl = sgClosed(cs + k)
            If aiLane >= 0 Then
                If (cl And (2 ^ aiLane)) <> 0 Then
                    limit = 0
                    Exit For
                End If
            End If
            If inl >= 0 Then
                If (cl And (2 ^ inl)) <> 0 And Abs(carD - LaneCentre(aiLane) * 16) > 12 * 16 Then
                    If limit > FromKmh(12) Then limit = FromKmh(12)
                    Exit For
                End If
            End If
        Next k
    End If
    If cs >= wFinish Then
        If wNSeg - 6 - cs > 0 Then limit = FromKmh(30) Else limit = 0
    End If
    aiTargetV = limit

    ' comments
    For i = 0 To wNHaz - 1
        If hzSaid(i) = 0 And aiOn <> 0 And wState = GS_PLAY Then
            If hzType(i) = HZ_FLOOD And wRoute > 0 And cs >= hzSeg(i) - 3 And cs < hzSeg(i) Then
                hzSaid(i) = 1
                WorldSay MSG_WATER_ANYWAY
            ElseIf hzType(i) = HZ_GHOST And GhostAt(carZ + 4 * SEGF) > LANE_W \ 2 Then
                hzSaid(i) = 1
                WorldSay MSG_ROAD_PROBABLY
            ElseIf hzType(i) = HZ_TRACTOR And cs > hzSeg(i) + 6 And cs < hzSeg(i) + hzLen(i) And carV < FromKmh(30) Then
                hzSaid(i) = 1
                WorldSay MSG_PATIENT
            End If
        End If
    Next i
End Sub

Public Function AiSteer() As Long
    Dim idx As Long, target As Long, k As Long, s As Long
    idx = SegOf(carZ + 2 * SEGF) - aiPlanFrom
    If idx < 0 Then idx = 0
    If idx > 15 Then idx = 15
    target = aiPlan(idx)
    If aiBlinded <> 0 Then k = 0 Else k = RoadCurve(carZ)
    s = (k * carV * 9) \ 40 + ShrA(target - carD, FBITS) * 4
    If s > 256 Then s = 256
    If s < -256 Then s = -256
    AiSteer = s
End Function

' ---------- the car ----------
Private Sub Respawn()
    Dim s As Long, i As Long, nl As Long
    nl = riNl(wRoute)
    s = SegOf(carZ) - 4
    Do While s > 2
        If (sgFlags(s) And (SF_FLOOD Or SF_GHOST Or SF_CONES Or SF_GLARE)) = 0 Then Exit Do
        s = s - 1
    Loop
    ' and well back from the start of whatever caught it, so there's room to get going and take it by hand
    For i = 0 To wNHaz - 1
        If hzSeg(i) >= s And hzSeg(i) < s + 10 Then s = hzSeg(i) - 10
    Next i
    If s < 2 Then s = 2
    carZ = s * SEGF
    carD = LaneCentre(nl - 1) * 16
    carV = 0: carS = 0: carLat = 0
    carState = CS_DRIVING
    carCool = 0
    aiOn = 0
    aiLane = nl - 1
    aiBlinded = 0
    wMult = 1
    wApFrames = 0
    For i = 0 To MAX_OBJS - 1
        If obType(i) <> OBJ_NONE And Abs(obZ(i) - carZ) < 4 * SEGF And obType(i) <> OBJ_DEBRIS And obType(i) <> OBJ_AMBULANCE Then obType(i) = OBJ_NONE
    Next i
    Push EV_RESPAWN, s, 0
End Sub

Private Sub OffRoad(ByVal side As Long, ByVal depth As Long, ByVal edge As Long)
    Dim sg As Long, t As Long, rail As Boolean, splash As Boolean, deep As Boolean
    If SegOf(carZ) < wNSeg Then sg = SegOf(carZ) Else sg = wNSeg - 1
    If side <> 0 Then
        t = sgSideR(sg): rail = (sgFlags(sg) And SF_RAIL_R) <> 0
    Else
        t = sgSideL(sg): rail = (sgFlags(sg) And SF_RAIL_L) <> 0
    End If
    If rail Or t = SIDE_MEDIAN Or t = SIDE_WALL Then
        If side <> 0 Then carD = (edge - 2) * 16 Else carD = (edge + 2) * 16
        carS = 0
        If carCool = 0 Then
            carV = (carV * 3) \ 4
            carCool = 15
            If rail Then
                Hurt 5, EV_SCRAPE
            ElseIf t = SIDE_MEDIAN Then
                Hurt 8, EV_SCRAPE
            Else
                Hurt 10, EV_SCRAPE
            End If
        End If
    ElseIf t = SIDE_GRASS Then
        If carV > FromKmh(40) Then carV = carV - 6
        If depth > 160 Then
            If side <> 0 Then carD = (edge + 160) * 16 Else carD = (edge - 160) * 16
        End If
    ElseIf t = SIDE_TOWN Then
        If depth > 40 Then
            If side <> 0 Then carD = (edge + 38) * 16 Else carD = (edge - 38) * 16
            If carCool = 0 Then
                carV = carV \ 3
                carCool = 25
                Hurt 25, EV_CRASH
                WorldSay MSG_OOPS
            End If
        End If
    Else
        splash = t = SIDE_LEVEE Or t = SIDE_CANAL
        If splash Then deep = depth > 16 Else deep = depth > 8
        If deep Then
            If splash Then carState = CS_SPLASH Else carState = CS_ROLL
            carTimer = 50
            If side <> 0 Then carLat = 24 Else carLat = -24
            aiOn = 0
            If splash Then Hurt 40, EV_SPLASH Else Hurt 40, EV_ROLL
            If wState = GS_PLAY Then WorldSay MSG_TOW
        End If
    End If
End Sub

Private Sub CarUpdate(ByVal inp As Long)
    Dim edg As Long, cs As Long, k As Long, pull As Long, le As Long, re As Long, u As Long, playing As Boolean, dec As Long
    edg = inp And Not wLastIn
    cs = SegOf(carZ)
    playing = wState = GS_PLAY
    If carCool > 0 Then carCool = carCool - 1
    If carState = CS_SPLASH Or carState = CS_ROLL Then
        carV = (carV * 15) \ 16
        carZ = carZ + carV
        carD = carD + carLat
        carTimer = carTimer - 1
        If carTimer <= 0 Then Respawn
        Exit Sub
    End If

    If playing Then
        If (edg And IN_FIRE) <> 0 Then
            WorldSetAp aiOn = 0
        ElseIf aiOn <> 0 And (inp And (IN_LEFT Or IN_RIGHT Or IN_DOWN)) <> 0 Then
            WorldSetAp False
        End If
    End If

    If aiOn <> 0 Or Not playing Then
        If aiPhantomTimer > 0 Then dec = 18 Else dec = 8
        carS = AiSteer()
        If carV < aiTargetV Then
            carV = carV + 3
            If carV > aiTargetV Then carV = aiTargetV
        ElseIf carV > aiTargetV Then
            carV = carV - dec
            If carV < aiTargetV Then carV = aiTargetV
        End If
    Else
        If (inp And IN_LEFT) <> 0 Then
            carS = carS - 40
            If carS < -256 Then carS = -256
        ElseIf (inp And IN_RIGHT) <> 0 Then
            carS = carS + 40
            If carS > 256 Then carS = 256
        ElseIf carS > 0 Then
            carS = carS - 64
            If carS < 0 Then carS = 0
        ElseIf carS < 0 Then
            carS = carS + 64
            If carS > 0 Then carS = 0
        End If
        If (inp And IN_DOWN) <> 0 Then
            carV = carV - 12
        ElseIf (inp And IN_UP) <> 0 Then
            carV = carV + 4
        Else
            carV = carV - 1
        End If
        If carV < 0 Then carV = 0
        If carV > FromKmh(MAX_KMH) Then carV = FromKmh(MAX_KMH)
    End If

    k = RoadCurve(carZ)
    pull = (k * carV * carV) \ 8000
    Dim flooded As Boolean
    If cs < wNSeg Then flooded = (sgFlags(cs) And SF_FLOOD) <> 0
    If flooded And carV > FromKmh(AquaKmh()) Then
        If carState <> CS_AQUAPLANE Then Push EV_AQUAPLANE, Kmh(carV), 0
        carState = CS_AQUAPLANE
        carLat = -((carV - FromKmh(AquaKmh())) * 3) \ 2
        carV = carV - 1
    Else
        carState = CS_DRIVING
        carLat = (carS * carV) \ 1800 - pull
    End If
    carD = carD + carLat
    carZ = carZ + carV

    u = ShrA(carD, FBITS)
    le = RoadLeft() - SHOULDER
    re = RoadRight() + SHOULDER
    If u < le Then
        OffRoad 0, le - u, le
    ElseIf u > re Then
        OffRoad 1, u - re, re
    End If

    carHist(carHistPos And 31) = carV
    carHistPos = carHistPos + 1
End Sub

' ---------- route and game flow ----------
Private Sub PlaceCar()
    Dim k As Long, nl As Long
    nl = riNl(wRoute)
    carState = 0: carS = 0: carLat = 0: carTimer = 0: carCool = 0: carHistPos = 0
    For k = 0 To 31: carHist(k) = 0: Next k
    carZ = 3 * SEGF
    carD = LaneCentre(nl - 1) * 16
    carV = FromKmh((riLimit(wRoute) * 7) \ 10)
    aiOn = 1: aiLane = nl - 1
    For k = 0 To 15: aiPlan(k) = 0: Next k
    aiPlanFrom = 0: aiPhantomTimer = 0: aiPhantomSeg = -1
    aiBlinded = 0: aiBlindX = 0: aiBlindZ = 0: aiBlindDir = 0: aiTargetV = 0: aiLaneHold = 0
    For k = 0 To MAX_SEEN - 1
        snZ(k) = 0: snD(k) = 0: snType(k) = 0: snPhantom(k) = 0
    Next k
    aiNSeen = 0
End Sub

Public Sub WorldStartRoute(ByVal route As Long)
    Dim i As Long
    RouteBuild route
    For i = 0 To MAX_OBJS - 1
        obType(i) = 0: obFlags(i) = 0: obColour(i) = 0: obHz(i) = 0: obLane(i) = 0: obZ(i) = 0: obD(i) = 0
        obV(i) = 0: obVd(i) = 0: obVt(i) = 0: obTimer(i) = 0: obCool(i) = 0
    Next i
    For i = 0 To MAX_SEGS - 1: sgKnocked(i) = 0: Next i
    For i = 0 To MAX_HAZ - 1: hzSaid(i) = 0: Next i
    PlaceCar
    wMult = 1
    wApFrames = 0
    wApRem = 0
    wDistAp = 0: wDistAll = 0
    wSaves = 0: wNeedless = 0: wTakeovers = 0
    wPendingSave = -1
    wIncident = 0
    wRouteBonus = 0
    wGlare = 0
    wSiren = 0
    wState = GS_INTRO
    wStateTimer = 100
    Push EV_ROUTE_START, route, 0
End Sub

Public Sub WorldStartGame()
    wScore = 0
    wCover = 100
    wTotalSaves = 0: wTotalNeedless = 0
    WorldStartRoute 0
    WorldSay MSG_HANDS
End Sub

Public Sub WorldInit()
    Dim keep As Boolean, t0 As Long, t1 As Long, t2 As Long, t3 As Long, t4 As Long, t5 As Long, i As Long
    ScInit
    keep = tuSpeedPct <> 0
    t0 = tuGodMode: t1 = tuAiPerfect: t2 = tuTrafficPct: t3 = tuSpeedPct: t4 = tuMultSecs: t5 = tuAquaKmh
    ' memset(w, 0): everything
    wRoute = 0: wNSeg = 0: wNHaz = 0: wFinish = 0
    For i = 0 To MAX_SEGS - 1
        sgCx(i) = 0: sgY(i) = 0: sgDir(i) = 0: sgSideL(i) = 0: sgSideR(i) = 0: sgFlags(i) = 0: sgClosed(i) = 0: sgGhost(i) = 0
    Next i
    For i = 0 To MAX_HAZ - 1
        hzType(i) = 0: hzSeg(i) = 0: hzLen(i) = 0: hzParam(i) = 0: hzState(i) = 0
    Next i
    wState = 0: wFrame = 0: wStateTimer = 0: wView = 0
    wScore = 0: wCover = 0: wMult = 0: wApFrames = 0: wDistAp = 0: wDistAll = 0
    wSaves = 0: wNeedless = 0: wTakeovers = 0: wApRem = 0: wPendingSave = 0: wIncident = 0: wRouteBonus = 0
    wTotalSaves = 0: wTotalNeedless = 0: wMsg = 0: wMsgTimer = 0: wGlare = 0: wSiren = 0: wNEv = 0: wLastIn = 0
    If keep Then
        tuGodMode = t0: tuAiPerfect = t1: tuTrafficPct = t2: tuSpeedPct = t3: tuMultSecs = t4: tuAquaKmh = t5
    Else
        WorldDefaults
    End If
    wRng = 1234567
    WorldStartRoute 0
    wNEv = 0
    wState = GS_TITLE
    wCover = 100
End Sub

Public Function WorldApPct() As Long
    Dim den As Long
    If wDistAll <= 0 Then
        WorldApPct = 100
        Exit Function
    End If
    den = ShrA(wDistAll, 8)
    If den = 0 Then den = 1
    WorldApPct = (ShrA(wDistAp, 8) * 100) \ den
End Function

Private Sub Arrive()
    Dim pct As Long
    pct = WorldApPct()
    wRouteBonus = pct * 50 + wSaves * 500
    wScore = wScore + wRouteBonus
    wCover = wCover + 30
    If wCover > 100 Then wCover = 100
    wState = GS_ARRIVED
    wStateTimer = 250
    aiOn = 1
    aiBlinded = 0
    wPendingSave = -1
    Push EV_ARRIVED, wRoute, wScore
    WorldSay MSG_ARRIVED
End Sub

Private Sub ScoreUpdate()
    Dim m As Long
    If wState <> GS_PLAY Or carState = CS_SPLASH Or carState = CS_ROLL Then Exit Sub
    wDistAll = wDistAll + carV
    If aiOn = 0 Then Exit Sub
    wDistAp = wDistAp + carV
    wApRem = wApRem + carV * wMult
    wScore = wScore + ShrA(wApRem, 8)
    wApRem = wApRem And 255
    wApFrames = wApFrames + 1
    m = 1 + wApFrames \ (tuMultSecs * 25)
    If m > 8 Then m = 8
    If m > wMult Then
        wMult = m
        Push EV_MULT_UP, m, 0
    End If
End Sub

Public Sub WorldUpdate(ByVal inp As Long)
    Dim edg As Long, raw As Long, cs As Long, k As Long, g As Long
    edg = inp And Not wLastIn
    raw = inp
    wFrame = wFrame + 1
    If wMsgTimer > 0 Then
        wMsgTimer = wMsgTimer - 1
        If wMsgTimer = 0 Then wMsg = MSG_NONE
    End If
    If wStateTimer > 0 Then wStateTimer = wStateTimer - 1

    Select Case wState
        Case GS_TITLE
            If (edg And (IN_FIRE Or IN_START)) <> 0 Then
                WorldStartGame
                wLastIn = inp
                Exit Sub
            End If
            If SegOf(carZ) >= wFinish - 2 Then PlaceCar
        Case GS_INTRO
            If wStateTimer = 0 Or (edg And (IN_FIRE Or IN_START)) <> 0 Then
                wState = GS_PLAY
                edg = 0
                inp = inp And Not IN_FIRE
            End If
        Case GS_ARRIVED
            If wStateTimer = 0 Or (wStateTimer < 210 And (edg And (IN_FIRE Or IN_START)) <> 0) Then
                If wRoute < NUM_ROUTES - 1 Then
                    wState = GS_UPDATE
                    wStateTimer = 200
                    WorldSay MSG_UPDATED
                Else
                    wState = GS_WIN
                    wStateTimer = 50
                    Push EV_WIN, wScore, 0
                End If
            End If
        Case GS_UPDATE
            If wStateTimer = 0 Or (wStateTimer < 160 And (edg And (IN_FIRE Or IN_START)) <> 0) Then WorldStartRoute wRoute + 1
            wLastIn = inp
            Exit Sub
        Case GS_GAMEOVER, GS_WIN
            If wStateTimer = 0 And (edg And (IN_FIRE Or IN_START)) <> 0 Then
                WorldInit
                wLastIn = inp
                Exit Sub
            End If
    End Select

    ' the sun: glare builds up over the segments ahead
    cs = SegOf(carZ)
    g = 0
    For k = 0 To 3
        If cs + k >= wNSeg Then Exit For
        If (sgFlags(cs + k) And SF_GLARE) <> 0 Then
            g = 16
            Exit For
        End If
    Next k
    If wGlare < g Then
        wGlare = wGlare + 1
    ElseIf wGlare > g Then
        wGlare = wGlare - 1
    End If

    If wState = GS_PLAY Or wState = GS_TITLE Then
        HazardsUpdate
        TrafficSpawn
    End If
    AiThink
    If wState = GS_PLAY Then CarUpdate inp Else CarUpdate 0
    ObjectsUpdate
    Collide
    ScoreUpdate

    If wState = GS_PLAY And SegOf(carZ) >= wFinish And carState = CS_DRIVING Then Arrive
    wLastIn = raw                        ' the press that started the route isn't a new one next frame
End Sub

' the whole state, as tools/trace.c's state_hash
Public Function ScStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    h = Fnv(h, wRoute): h = Fnv(h, wState): h = Fnv(h, wFrame): h = Fnv(h, wStateTimer): h = Fnv(h, wRng)
    h = Fnv(h, carState): h = Fnv(h, carZ): h = Fnv(h, carD): h = Fnv(h, carV): h = Fnv(h, carS): h = Fnv(h, carLat)
    h = Fnv(h, carTimer): h = Fnv(h, carCool)
    h = Fnv(h, aiOn): h = Fnv(h, aiLane): h = Fnv(h, aiTargetV): h = Fnv(h, aiBlinded): h = Fnv(h, aiPhantomTimer): h = Fnv(h, aiNSeen)
    For i = 0 To 15: h = Fnv(h, aiPlan(i)): Next i
    For i = 0 To MAX_OBJS - 1
        If obType(i) <> 0 Then
            h = Fnv(h, i): h = Fnv(h, obType(i)): h = Fnv(h, obFlags(i)): h = Fnv(h, obLane(i))
            h = Fnv(h, obZ(i)): h = Fnv(h, obD(i)): h = Fnv(h, obV(i)): h = Fnv(h, obTimer(i))
        End If
    Next i
    For i = 0 To wNHaz - 1: h = Fnv(h, hzState(i)): Next i
    h = Fnv(h, wScore): h = Fnv(h, wCover): h = Fnv(h, wMult): h = Fnv(h, wApFrames): h = Fnv(h, wDistAp): h = Fnv(h, wDistAll)
    h = Fnv(h, wSaves): h = Fnv(h, wNeedless): h = Fnv(h, wTakeovers): h = Fnv(h, wMsg): h = Fnv(h, wGlare): h = Fnv(h, wSiren)
    ScStateHash = h
End Function
