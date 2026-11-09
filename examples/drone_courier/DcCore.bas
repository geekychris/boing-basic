' Drone Courier - the rules (a port of dc_core.c from amiga_mcp's examples/drone_courier).
' Parcel deliveries by drone across a city of towers: collect at the depot's pad, land on
' the customer's pad before the clock runs out; fragile parcels, wind and gusts, a battery.
' 16.16 fixed point exactly as the C (A3Fix.bas): the same state hash.
Option Explicit

Public Const DC_N As Long = 12
Public Const DC_PITCH As Long = 160
Public Const DC_FOOT As Long = 55
Public Const DC_HALF As Long = 960
Public Const DC_DAYS As Long = 5
Public Const DC_MAX_FAILS As Long = 3
Public Const DC_CEILING As Long = 600
Public Const DC_VMAX As Long = 524288           ' FX(8)
Public Const DC_LAND_DOWN As Long = 131072      ' FX(2)
Public Const DC_LAND_SIDE As Long = 98304       ' FX(1.5)
Public Const DC_BETWEEN As Long = 75

Public Const DC_IN_LEFT As Long = 1
Public Const DC_IN_RIGHT As Long = 2
Public Const DC_IN_UP As Long = 4
Public Const DC_IN_DOWN As Long = 8
Public Const DC_IN_CLIMB As Long = 16

Public Const DCE_NONE As Long = 0
Public Const DCE_PICKUP As Long = 1
Public Const DCE_DELIVER As Long = 2
Public Const DCE_BUMP As Long = 3
Public Const DCE_BROKEN As Long = 4
Public Const DCE_HARD As Long = 5
Public Const DCE_LATE As Long = 6
Public Const DCE_GUST As Long = 7
Public Const DCE_FLAT As Long = 8
Public Const DCE_DAY As Long = 9
Public Const DCE_OVER As Long = 10
Public Const DCE_WIN As Long = 11
Public Const DC_MAX_EVENTS As Long = 16

Private Const DRONE_ACC As Long = 19660         ' FX(0.3)
Private Const TURN_RATE As Long = 520
Private Const CLIMB_ACC As Long = 22937         ' FX(0.35)
Private Const SINK_V As Long = -78643           ' -FX(1.2)

Public Type DcEvent
    etype As Long
    a As Long
    b As Long
End Type

Public dcSeed As Long, dcRng As Long
Public dcDay As Long, dcOver As Long, dcWon As Long, dcBetween As Long
Public dcHeight(0 To 11, 0 To 11) As Long      ' (row, col)
Public dcX As Long, dcY As Long, dcZ As Long, dcVX As Long, dcVY As Long, dcVZ As Long
Public dcYaw As Long
Public dcCarrying As Long, dcFragile As Long
Public dcDepot As Long, dcTarget As Long
Public dcJobs As Long, dcJobsDone As Long, dcFails As Long
Public dcPadR As Long
Public dcBattery As Long
Public dcWindX As Long, dcWindZ As Long, dcGustX As Long, dcGustZ As Long
Public dcGustTimer As Long
Public dcJobTime As Long, dcTicks As Long, dcScore As Long
Public dcLanded As Long
Public dcBumps As Long, dcBreakages As Long
Public dcEv(0 To 15) As DcEvent
Public dcNEv As Long

Public Sub DcInit()
    A3FixInit
End Sub

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If dcNEv < DC_MAX_EVENTS Then
        dcEv(dcNEv).etype = etype
        dcEv(dcNEv).a = a
        dcEv(dcNEv).b = b
        dcNEv = dcNEv + 1
    End If
End Sub

' mulberry32
Private Function Rnd32() As Long
    Dim t As Long
    dcRng = AddW(dcRng, &H6D2B79F5)
    t = dcRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    Rnd32 = t Xor ShrU(t, 14)
End Function

Public Function DcBlockX(ByVal col As Long) As Long
    DcBlockX = (-DC_HALF + col * DC_PITCH + DC_PITCH \ 2) * 65536
End Function

Public Function DcBlockZ(ByVal row As Long) As Long
    DcBlockZ = (-DC_HALF + row * DC_PITCH + DC_PITCH \ 2) * 65536
End Function

' the block whose tower (x, z) is over, or -1 (a street)
Public Function DcBlockAt(ByVal x As Long, ByVal z As Long) As Long
    Dim ix As Long, iz As Long, c As Long, r As Long
    DcBlockAt = -1
    ix = ShrA(x, 16) + DC_HALF
    iz = ShrA(z, 16) + DC_HALF
    If ix < 0 Or iz < 0 Then Exit Function
    c = ix \ DC_PITCH
    r = iz \ DC_PITCH
    If c >= DC_N Or r >= DC_N Then Exit Function
    If Abs(x - DcBlockX(c)) >= DC_FOOT * 65536 Or Abs(z - DcBlockZ(r)) >= DC_FOOT * 65536 Then Exit Function
    DcBlockAt = r * DC_N + c
End Function

Public Function DcRoof(ByVal b As Long) As Long
    If b >= 0 Then DcRoof = dcHeight(b \ DC_N, b Mod DC_N)
End Function

Public Function DcGoal() As Long
    If dcCarrying Then DcGoal = dcTarget Else DcGoal = dcDepot
End Function

Private Function PickTarget() As Long
    Dim k As Long, b As Long, dr As Long, dcol As Long
    For k = 0 To 199
        b = UModL(Rnd32(), DC_N * DC_N)
        dr = b \ DC_N - dcDepot \ DC_N
        dcol = b Mod DC_N - dcDepot Mod DC_N
        If DcRoof(b) >= 40 And b <> dcDepot Then
            If dr * dr + dcol * dcol >= 9 + dcDay * 4 Then
                PickTarget = b
                Exit Function
            End If
        End If
    Next k
    PickTarget = (dcDepot + DC_N * 5 + 5) Mod (DC_N * DC_N)
End Function

Private Sub NewJob()
    dcTarget = PickTarget()
    dcJobTime = (75 - dcDay * 5) * 25
End Sub

Public Sub DcLoadDay(ByVal day As Long)
    Dim r As Long, c As Long, dr As Long, dc As Long, centre As Long, h As Long, v As Long
    dcDay = day
    For r = 0 To DC_N - 1
        For c = 0 To DC_N - 1
            dr = 2 * r - (DC_N - 1)
            dc = 2 * c - (DC_N - 1)
            centre = 400 - (dr * dr + dc * dc) * 3
            h = Rnd32()
            If UModL(h, 10) = 0 Then
                v = 0
            Else
                v = 50 + ShrU(h, 8) Mod 120
                If centre > 0 Then v = v + centre \ 2
            End If
            If v > 380 Then v = 380
            dcHeight(r, c) = v
        Next c
    Next r
    ' the depot: a mid-height tower near a corner
    dcDepot = 1 * DC_N + 1
    dcHeight(1, 1) = 120
    dcX = DcBlockX(1)
    dcZ = DcBlockZ(1)
    dcY = 120 * 65536
    dcVX = 0: dcVY = 0: dcVZ = 0
    dcYaw = &H2000&
    dcLanded = 1
    dcCarrying = 1                         ' the first parcel is aboard
    dcFragile = 0                          ' (no random number on day 1, as the C's &&)
    If day >= 2 Then
        If UModL(Rnd32(), 3) = 0 Then dcFragile = 1
    End If
    dcBattery = 100 * 65536
    dcJobs = 3 + day
    dcJobsDone = 0
    dcPadR = 36 - day * 2
    dcWindX = ((UModL(Rnd32(), 2001) - 1000) * (day - 1) * 41) \ 100
    dcWindZ = ((UModL(Rnd32(), 2001) - 1000) * (day - 1) * 41) \ 100
    dcGustX = 0: dcGustZ = 0
    dcGustTimer = 100
    NewJob
End Sub

Public Sub DcNewGame(ByVal seed As Long, ByVal day As Long)
    dcSeed = seed
    dcRng = seed
    dcOver = 0: dcWon = 0: dcBetween = 0
    dcFails = 0: dcTicks = 0: dcScore = 0: dcBumps = 0: dcBreakages = 0
    dcNEv = 0
    If day < 1 Then day = 1
    If day > DC_DAYS Then day = DC_DAYS
    DcLoadDay day
End Sub

Private Sub Fail(ByVal etype As Long)
    dcFails = dcFails + 1
    Ev etype, dcFails, 0
    If dcFails >= DC_MAX_FAILS Then
        dcOver = 1
        Ev DCE_OVER, dcScore, 0
    End If
End Sub

' touched down on block b's roof (or the street, b < 0) at speeds vy, vside
Private Sub Touchdown(ByVal b As Long, ByVal vy As Long, ByVal vside As Long)
    Dim hard As Boolean, dx As Long, dz As Long, bonus As Long
    If b <> DcGoal() Then Exit Sub
    hard = -vy > DC_LAND_DOWN Or vside > DC_LAND_SIDE
    dx = dcX - DcBlockX(b Mod DC_N)
    dz = dcZ - DcBlockZ(b \ DC_N)
    If FHypot(dx, dz) > dcPadR * 65536 Then Exit Sub        ' on the roof, not the pad
    If hard Then
        Ev DCE_HARD, ShrA(-vy, 12), ShrA(vside, 12)
        If dcCarrying <> 0 And dcFragile <> 0 Then
            dcBreakages = dcBreakages + 1
            dcCarrying = 0
            Fail DCE_BROKEN
            NewJob
        End If
        Exit Sub
    End If
    If dcCarrying = 0 Then
        dcCarrying = 1
        dcFragile = 0
        If dcDay >= 2 Then
            If UModL(Rnd32(), 3) = 0 Then dcFragile = 1
        End If
        dcBattery = 100 * 65536
        Ev DCE_PICKUP, dcFragile, 0
        Exit Sub
    End If
    bonus = 200 + (dcJobTime \ 25) * 5
    If dcFragile Then bonus = bonus + 150
    dcScore = dcScore + bonus
    dcCarrying = 0
    dcJobsDone = dcJobsDone + 1
    Ev DCE_DELIVER, dcJobsDone, bonus
    If dcJobsDone >= dcJobs Then
        dcScore = dcScore + 500 * dcDay
        dcBetween = DC_BETWEEN
        Exit Sub
    End If
    NewJob
End Sub

Public Sub DcTick(ByVal inp As Long)
    Dim dir As Long, k As Long, fx As Long, fz As Long, sp As Long, drain As Long
    Dim px As Long, pz As Long, py As Long, roof As Long, b As Long, pb As Long, vy As Long, vside As Long, speed As Long
    If dcOver <> 0 Or dcWon <> 0 Then Exit Sub
    dcTicks = dcTicks + 1
    If dcBetween > 0 Then
        dcBetween = dcBetween - 1
        If dcBetween = 0 Then
            If dcDay >= DC_DAYS Then
                dcWon = 1
                Ev DCE_WIN, dcScore, 0
                Exit Sub
            End If
            DcLoadDay dcDay + 1
            Ev DCE_DAY, dcDay, 0
        End If
        Exit Sub
    End If
    ' the clock
    dcJobTime = dcJobTime - 1
    If dcJobTime <= 0 Then
        Fail DCE_LATE
        If dcOver Then Exit Sub
        NewJob
    End If
    ' gusts from day 2
    If dcDay >= 2 Then
        dcGustTimer = dcGustTimer - 1
        If dcGustTimer <= 0 Then
            If dcGustX Then dcGustX = 0 Else dcGustX = ((UModL(Rnd32(), 2001) - 1000) * dcDay * 52) \ 100
            If dcGustX Then dcGustZ = ((UModL(Rnd32(), 2001) - 1000) * dcDay * 52) \ 100 Else dcGustZ = 0
            dcGustTimer = 60 + UModL(Rnd32(), 140)
            If dcGustX Then Ev DCE_GUST, 0, 0
        End If
    End If
    ' turning, flying, climbing
    If inp And DC_IN_RIGHT Then dir = dir + 1
    If inp And DC_IN_LEFT Then dir = dir - 1
    dcYaw = (dcYaw + dir * TURN_RATE) And &HFFFF&
    fx = A3Sin(dcYaw)
    fz = A3Cos(dcYaw)
    If inp And DC_IN_UP Then
        dcVX = dcVX + FMul(DRONE_ACC, fx)
        dcVZ = dcVZ + FMul(DRONE_ACC, fz)
    End If
    If inp And DC_IN_DOWN Then
        dcVX = dcVX - FMul(DRONE_ACC, fx)
        dcVZ = dcVZ - FMul(DRONE_ACC, fz)
    End If
    If dcLanded = 0 Then
        dcVX = dcVX + dcWindX + dcGustX
        dcVZ = dcVZ + dcWindZ + dcGustZ
    End If
    dcVX = dcVX - dcVX \ 24
    dcVZ = dcVZ - dcVZ \ 24
    sp = FHypot(dcVX, dcVZ)
    If sp > DC_VMAX Then
        dcVX = FDiv(FMul(dcVX, DC_VMAX), sp)
        dcVZ = FDiv(FMul(dcVZ, DC_VMAX), sp)
    End If
    If inp And DC_IN_CLIMB Then
        dcVY = dcVY + CLIMB_ACC
        If dcVY > 262144 Then dcVY = 262144
    ElseIf dcVY > SINK_V Then
        dcVY = dcVY - 9830
        If dcVY < SINK_V Then dcVY = SINK_V
    End If
    ' the battery
    drain = 786
    If inp And DC_IN_CLIMB Then drain = drain + 1966
    If inp And (DC_IN_UP Or DC_IN_DOWN) Then drain = drain + 655
    dcBattery = dcBattery - drain
    If dcBattery <= 0 Then
        dcBattery = 0
        dcOver = 1
        Ev DCE_FLAT, 0, 0
        Ev DCE_OVER, dcScore, 0
        Exit Sub
    End If
    If dcLanded <> 0 And dcVY <= 0 Then          ' sitting: the throttle slides it
        dcVY = 0
        dcVX = dcVX - dcVX \ 4
        dcVZ = dcVZ - dcVZ \ 4
    End If
    For k = 0 To 1
        px = dcX: pz = dcZ: py = dcY
        dcX = dcX + dcVX \ 2
        dcZ = dcZ + dcVZ \ 2
        dcY = dcY + dcVY \ 2
        If dcX > (DC_HALF + 200) * 65536 Then dcX = (DC_HALF + 200) * 65536
        If dcX < -(DC_HALF + 200) * 65536 Then dcX = -(DC_HALF + 200) * 65536
        If dcZ > (DC_HALF + 200) * 65536 Then dcZ = (DC_HALF + 200) * 65536
        If dcZ < -(DC_HALF + 200) * 65536 Then dcZ = -(DC_HALF + 200) * 65536
        If dcY > DC_CEILING * 65536 Then
            dcY = DC_CEILING * 65536
            dcVY = 0
        End If
        b = DcBlockAt(dcX, dcZ)
        roof = DcRoof(b) * 65536
        If dcY < roof Then
            pb = DcBlockAt(px, pz)
            If pb = b And py >= roof - FONE Then
                ' down onto the roof (or the street)
                vy = dcVY
                vside = FHypot(dcVX, dcVZ)
                dcY = roof
                dcVY = 0
                If dcLanded = 0 Then
                    dcLanded = 1
                    Touchdown b, vy, vside
                End If
            Else
                ' into a tower's side: back out, bounced
                speed = FHypot(dcVX, dcVZ)
                dcX = px
                dcZ = pz
                If Abs(px - DcBlockX(b Mod DC_N)) >= DC_FOOT * 65536 Then
                    dcVX = (-dcVX * 3) \ 10
                Else
                    dcVZ = (-dcVZ * 3) \ 10
                End If
                dcBumps = dcBumps + 1
                Ev DCE_BUMP, b, ShrA(speed, 12)
                If dcCarrying <> 0 And dcFragile <> 0 And speed > 163840 Then
                    dcBreakages = dcBreakages + 1
                    dcCarrying = 0
                    Fail DCE_BROKEN
                    If dcOver Then Exit Sub
                    NewJob
                End If
            End If
        ElseIf dcY > roof + 32768 Then
            dcLanded = 0
        End If
    Next k
End Sub

' ---------- the autopilot ----------
Public Function DcBot() As Long
    Dim inp As Long, goal As Long, r As Long, c As Long, want As Long, diff As Long, sky As Long
    Dim gx As Long, gz As Long, dx As Long, dz As Long, d As Long, along As Long, spWant As Long, cruise As Long
    Dim high As Boolean
    If dcOver <> 0 Or dcWon <> 0 Or dcBetween <> 0 Then Exit Function
    goal = DcGoal()
    gx = DcBlockX(goal Mod DC_N)
    gz = DcBlockZ(goal \ DC_N)
    For r = 0 To DC_N - 1
        For c = 0 To DC_N - 1
            If dcHeight(r, c) > sky Then sky = dcHeight(r, c)
        Next c
    Next r
    cruise = (sky + 50) * 65536
    dx = gx - dcX
    dz = gz - dcZ
    d = FHypot(dx, dz)
    ' the speed along the drone's heading
    along = FMul(dcVX, A3Sin(dcYaw)) + FMul(dcVZ, A3Cos(dcYaw))
    If d > 10 * 65536 Then
        want = A3Atan2(ShrA(dx, 8) - ShrA(dcVX * 12, 8), ShrA(dz, 8) - ShrA(dcVZ * 12, 8))   ' allowing for drift
        diff = ADiff(want, dcYaw)
        If diff > 300 Then inp = inp Or DC_IN_RIGHT
        If diff < -300 Then inp = inp Or DC_IN_LEFT
    End If
    ' up over the skyline before going anywhere far; down when over the pad
    If d > (dcPadR \ 2) * 65536 Or FHypot(dcVX, dcVZ) > 52428 Then
        high = dcY >= cruise - 15 * 65536
        If Not high And d > 60 * 65536 Then
            If dcVY < 196608 Then inp = inp Or DC_IN_CLIMB
            spWant = 0
        Else
            If dcY < cruise And dcVY < 32768 And d > 60 * 65536 Then inp = inp Or DC_IN_CLIMB
            If d <= 60 * 65536 And dcVY < 0 And dcY < DcRoof(goal) * 65536 + 40 * 65536 Then inp = inp Or DC_IN_CLIMB
            spWant = d \ 16
            If spWant > DC_VMAX - FONE Then spWant = DC_VMAX - FONE
            If diff > 6000 Or diff < -6000 Then spWant = 0
        End If
        If along < spWant - 13107 Then
            inp = inp Or DC_IN_UP
        ElseIf along > spWant + 13107 Then
            inp = inp Or DC_IN_DOWN
        End If
    Else
        ' over the pad: hold still and settle gently
        If along > 9830 Then
            inp = inp Or DC_IN_DOWN
        ElseIf along < -9830 Then
            inp = inp Or DC_IN_UP
        End If
        If dcVY < -78643 Then inp = inp Or DC_IN_CLIMB
    End If
    DcBot = inp
End Function

Public Function DcStateHash() As Long
    Dim h As Long
    h = FNV_START
    h = Fnv(h, dcScore): h = Fnv(h, dcDay): h = Fnv(h, dcX): h = Fnv(h, dcY): h = Fnv(h, dcZ)
    h = Fnv(h, dcVX): h = Fnv(h, dcVY): h = Fnv(h, dcVZ): h = Fnv(h, dcYaw): h = Fnv(h, dcCarrying)
    h = Fnv(h, dcTarget): h = Fnv(h, dcJobsDone): h = Fnv(h, dcFails): h = Fnv(h, dcBattery): h = Fnv(h, dcJobTime)
    h = Fnv(h, dcTicks): h = Fnv(h, dcBumps): h = Fnv(h, dcOver): h = Fnv(h, dcWon)
    DcStateHash = h
End Function
