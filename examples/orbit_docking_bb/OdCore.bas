' OdCore - Orbit Docking's rules, line for line from amiga_mcp's examples/orbit_docking/od_core.c:
' thrusters and roll in free space, the spinning station, the docking check, crashes, debris,
' fuel, the levels, and the autopilot. Fixed point throughout (16.16 positions, 16-bit angles
' with 8 more bits of fraction, "a8"), with A3Fix.bas's C arithmetic, so a seed flies exactly
' as in the C (tools/trace.sh and Trace.bbp compare the state hashes).
Option Explicit

Public Const OD_LEVELS As Long = 6
Public Const OD_LIVES As Long = 3
Public Const OD_PORT_Z As Long = 60            ' the hub's face
Public Const OD_HUB_R As Long = 60
Public Const OD_NOSE As Long = 20              ' the craft's nose ahead of its middle
Public Const OD_START_Z As Long = 900
Public Const OD_ACC As Long = 2621             ' FX(0.04): a thruster, units a tick^2
Public Const OD_ROLL_ACC As Long = 1536        ' 6 << 8, a8 a tick^2
Public Const OD_TOL_AXIS As Long = 14          ' the docking limits
Public Const OD_TOL_CLOSE As Long = 104857     ' FX(1.6)
Public Const OD_TOL_DRIFT As Long = 52428      ' FX(0.8)
Public Const OD_TOL_ROLL As Long = 1456        ' 8 degrees
Public Const OD_TOL_SPIN As Long = 5120        ' 20 << 8: 7 degrees a second, a8 a tick
Public Const OD_BETWEEN As Long = 75

' input bits
Public Const OD_IN_LEFT As Long = 1
Public Const OD_IN_RIGHT As Long = 2
Public Const OD_IN_UP As Long = 4
Public Const OD_IN_DOWN As Long = 8
Public Const OD_IN_FWD As Long = 16             ' towards the station
Public Const OD_IN_BACK As Long = 32
Public Const OD_IN_ROLL_L As Long = 64
Public Const OD_IN_ROLL_R As Long = 128

' events
Public Const ODE_NONE As Long = 0
Public Const ODE_DOCK As Long = 1
Public Const ODE_CRASH As Long = 2
Public Const ODE_DEBRIS As Long = 3
Public Const ODE_FUEL_OUT As Long = 4
Public Const ODE_LEVEL As Long = 5
Public Const ODE_OVER As Long = 6
Public Const ODE_WIN As Long = 7
Public Const ODE_LOST As Long = 8

Private Const FX1 As Long = 65536

' ---- the game ----
Public odSeed As Long, odRng As Long
Public odLevel As Long, odLives As Long, odOver As Long, odWon As Long, odBetween As Long
Public odX As Long, odY As Long, odZ As Long, odVX As Long, odVY As Long, odVZ As Long   ' the craft, 16.16
Public odRoll As Long, odRollRate As Long      ' a8
Public odStAngle As Long, odStSpin As Long     ' the station's turn and spin, a8
Public odFuel As Long, odFuelMax As Long
Public dbZ(0 To 2) As Long, dbY(0 To 2) As Long, dbAmp(0 To 2) As Long, dbPeriod(0 To 2) As Long, dbPhase(0 To 2) As Long
Public odNDebris As Long
Public odCrashes As Long, odDocks As Long
Public odTicks As Long, odLevelTicks As Long
Public odScore As Long
Public odLastFail As Long                       ' 1 off axis, 2 too fast, 3 drifting, 4 rolled wrong, 5 spin, 6 the hub's side, 7 debris
Public evType(0 To 11) As Long, evA(0 To 11) As Long, evB(0 To 11) As Long, odNEv As Long
Public odFailName(0 To 7) As String

Private lvSpin(0 To 5) As Long, lvOffset(0 To 5) As Long, lvFuel(0 To 5) As Long, lvDebris(0 To 5) As Long
Private coreReady As Boolean

Public Sub OdInit()
    Dim v As Variant, i As Long
    If coreReady Then Exit Sub
    A3FixInit
    ' by level: spin (degrees a second), start offset across, fuel, debris
    v = Array(4, 7, 10, 10, 14, -18)
    For i = 0 To 5: lvSpin(i) = v(i): Next i
    v = Array(0, 60, 140, 100, 160, 180)
    For i = 0 To 5: lvOffset(i) = v(i): Next i
    v = Array(600, 550, 500, 500, 550, 700)
    For i = 0 To 5: lvFuel(i) = v(i): Next i
    v = Array(0, 0, 0, 1, 2, 3)
    For i = 0 To 5: lvDebris(i) = v(i): Next i
    v = Array("", "OFF THE AXIS", "TOO FAST", "DRIFTING ACROSS", "ROLLED WRONG", "NOT TURNING WITH IT", "HIT THE HUB", "HIT DEBRIS")
    For i = 0 To 7: odFailName(i) = v(i): Next i
    coreReady = True
End Sub

Private Sub PushEv(ByVal t As Long, ByVal a As Long, ByVal b As Long)
    If odNEv < 12 Then
        evType(odNEv) = t: evA(odNEv) = a: evB(odNEv) = b
        odNEv = odNEv + 1
    End If
End Sub

Public Function OdPopEvent(t As Long, a As Long, b As Long) As Boolean
    Dim i As Long
    If odNEv = 0 Then Exit Function
    t = evType(0): a = evA(0): b = evB(0)
    For i = 1 To odNEv - 1
        evType(i - 1) = evType(i): evA(i - 1) = evA(i): evB(i - 1) = evB(i)
    Next i
    odNEv = odNEv - 1
    OdPopEvent = True
End Function

' mulberry32
Private Function Rnd32() As Long
    Dim t As Long
    odRng = AddW(odRng, &H6D2B79F5)
    t = odRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    Rnd32 = t Xor ShrU(t, 14)
End Function

' the craft's roll against the slot, -16384..16383 (the slot looks the same turned half round)
Public Function OdRollError() As Long
    Dim d As Long
    d = ShrA(odRoll - odStAngle, 8) And &H7FFF&
    If d >= &H4000& Then OdRollError = d - &H8000& Else OdRollError = d
End Function

' debris k's position across at tick lt
Private Function DebrisXAt(ByVal k As Long, ByVal lt As Long) As Long
    Dim a As Long
    a = (((lt Mod dbPeriod(k)) * 65536) \ dbPeriod(k) + dbPhase(k)) And &HFFFF&
    DebrisXAt = dbAmp(k) * A3Sin(a)
End Function

Public Function OdDebrisX(ByVal k As Long) As Long
    OdDebrisX = DebrisXAt(k, odLevelTicks)
End Function

Private Sub Place()
    Dim a As Long, off As Long
    a = Rnd32() And &HFFFF&
    off = lvOffset(odLevel - 1)
    odX = ShrA(off * A3Cos(a), 16) * FX1
    odY = ShrA(off * A3Sin(a), 16) * FX1
    odZ = OD_START_Z * FX1
    odVX = 0: odVY = 0: odVZ = 0
    odRoll = (Rnd32() And &HFFFF&) * 256
    odRollRate = 0
End Sub

Public Sub OdLoadLevel(ByVal lv As Long)
    Dim k As Long
    odLevel = lv
    odStAngle = 0
    odStSpin = ((((lvSpin(lv - 1) * 65536) \ 360) * 256) \ 25)
    odFuel = lvFuel(lv - 1) * FX1
    odFuelMax = odFuel
    odNDebris = lvDebris(lv - 1)
    For k = 0 To odNDebris - 1
        dbZ(k) = 520 - k * 140
        dbY(k) = UModL(Rnd32(), 61) - 30
        dbAmp(k) = 140 + UModL(Rnd32(), 60)
        dbPeriod(k) = 150 + UModL(Rnd32(), 100)
        dbPhase(k) = Rnd32() And &HFFFF&
    Next k
    odLevelTicks = 0
    Place
End Sub

Public Sub OdNewGame(ByVal seed As Long, ByVal lv As Long)
    Dim k As Long
    OdInit
    odSeed = seed: odRng = seed
    odLives = OD_LIVES
    odOver = 0: odWon = 0: odBetween = 0
    odX = 0: odY = 0: odZ = 0: odVX = 0: odVY = 0: odVZ = 0
    odRoll = 0: odRollRate = 0: odStAngle = 0: odStSpin = 0
    odFuel = 0: odFuelMax = 0
    For k = 0 To 2
        dbZ(k) = 0: dbY(k) = 0: dbAmp(k) = 0: dbPeriod(k) = 0: dbPhase(k) = 0
    Next k
    odNDebris = 0: odCrashes = 0: odDocks = 0: odTicks = 0: odLevelTicks = 0
    odScore = 0: odLastFail = 0: odNEv = 0
    If lv < 1 Then lv = 1
    If lv > OD_LEVELS Then lv = OD_LEVELS
    OdLoadLevel lv
End Sub

Private Sub Crash(ByVal why As Long)
    odCrashes = odCrashes + 1
    odLives = odLives - 1
    odLastFail = why
    If why = 7 Then PushEv ODE_DEBRIS, why, odLives Else PushEv ODE_CRASH, why, odLives
    If odLives <= 0 Then
        odOver = 1
        PushEv ODE_OVER, odScore, 0
        Exit Sub
    End If
    PushEv ODE_LOST, odLives, 0
    odFuel = odFuelMax
    Place
End Sub

Private Sub Contact()
    Dim lat As Long, why As Long, bonus As Long
    lat = FHypot(odX, odY)
    If lat > OD_HUB_R * FX1 Then Exit Sub                   ' it misses the hub's face
    If lat > OD_TOL_AXIS * FX1 Then
        why = 1
    ElseIf -odVZ > OD_TOL_CLOSE Then
        why = 2
    ElseIf Abs(odVX) > OD_TOL_DRIFT Or Abs(odVY) > OD_TOL_DRIFT Then
        why = 3
    ElseIf Abs(OdRollError()) > OD_TOL_ROLL Then
        why = 4
    ElseIf Abs(odRollRate - odStSpin) > OD_TOL_SPIN Then
        why = 5
    End If
    If why <> 0 Then
        Crash why
        Exit Sub
    End If
    bonus = 1000 + ShrA(odFuel, 16) * 2 + 500 * odLevel - (odLevelTicks \ 25) * 2
    If bonus < 500 Then bonus = 500
    odScore = odScore + bonus
    odDocks = odDocks + 1
    odBetween = OD_BETWEEN
    odZ = (OD_PORT_Z + OD_NOSE) * FX1
    odVX = 0: odVY = 0: odVZ = 0
    odRollRate = odStSpin
    PushEv ODE_DOCK, odLevel, bonus
End Sub

' a burn on one axis (vax: 0 x, 1 y, 2 z)
Private Sub Burn(ByVal vax As Long, ByVal dv As Long, ByVal cost As Long)
    If odFuel <= 0 Then Exit Sub
    Select Case vax
        Case 0: odVX = odVX + dv
        Case 1: odVY = odVY + dv
        Case Else: odVZ = odVZ + dv
    End Select
    odFuel = odFuel - cost
    If odFuel <= 0 Then
        odFuel = 0
        PushEv ODE_FUEL_OUT, 0, 0
    End If
End Sub

Public Sub OdTick(ByVal inp As Long)
    Dim k As Long, zprev As Long, bx As Long, by As Long, a As Long, c As Long, sn As Long
    Dim ax As Long, ay As Long, cost As Long
    If odOver <> 0 Or odWon <> 0 Then Exit Sub
    odTicks = odTicks + 1
    odStAngle = (odStAngle + odStSpin) And &HFFFFFF               ' a8: a turn is 1 << 24
    If odBetween > 0 Then
        odRoll = (odRoll + odRollRate) And &HFFFFFF               ' docked: turning with it
        odBetween = odBetween - 1
        If odBetween = 0 Then
            If odLevel >= OD_LEVELS Then
                odWon = 1
                PushEv ODE_WIN, odScore, 0
                Exit Sub
            End If
            OdLoadLevel odLevel + 1
            PushEv ODE_LEVEL, odLevel, 0
        End If
        Exit Sub
    End If
    odLevelTicks = odLevelTicks + 1
    ' the thrusters across are the craft's own: right is the view's right, whatever the roll
    If inp And OD_IN_RIGHT Then bx = 1
    If inp And OD_IN_LEFT Then bx = bx - 1
    If inp And OD_IN_UP Then by = 1
    If inp And OD_IN_DOWN Then by = by - 1
    If (bx <> 0 Or by <> 0) And odFuel > 0 Then
        a = ShrA(odRoll, 8) And &HFFFF&
        c = A3Cos(a): sn = A3Sin(a)
        ax = FMul(OD_ACC, -bx * c - by * sn)
        ay = FMul(OD_ACC, -bx * sn + by * c)
        If bx <> 0 Then cost = FX1
        If by <> 0 Then cost = cost + FX1
        Burn 0, ax, cost
        odVY = odVY + ay
    End If
    If inp And OD_IN_FWD Then Burn 2, -OD_ACC, FX1
    If inp And OD_IN_BACK Then Burn 2, OD_ACC, FX1
    If odFuel > 0 And (inp And (OD_IN_ROLL_L Or OD_IN_ROLL_R)) <> 0 Then
        If inp And OD_IN_ROLL_R Then odRollRate = odRollRate + OD_ROLL_ACC Else odRollRate = odRollRate - OD_ROLL_ACC
        odFuel = odFuel - FX1 \ 2
        If odFuel <= 0 Then
            odFuel = 0
            PushEv ODE_FUEL_OUT, 0, 0
        End If
    End If
    odRoll = (odRoll + odRollRate) And &HFFFFFF
    zprev = odZ
    odX = odX + odVX
    odY = odY + odVY
    odZ = odZ + odVZ
    ' drifted right away: lost in space
    If odZ > 1600 * FX1 Or Abs(odX) > 900 * FX1 Or Abs(odY) > 900 * FX1 Then
        Crash 1
        Exit Sub
    End If
    ' debris
    For k = 0 To odNDebris - 1
        If Abs(odZ - dbZ(k) * FX1) < 22 * FX1 Then
            If Abs(odY - dbY(k) * FX1) < 26 * FX1 Then
                If Abs(odX - OdDebrisX(k)) < 26 * FX1 Then
                    Crash 7
                    Exit Sub
                End If
            End If
        End If
    Next k
    ' the hub: its face, and its side
    If odZ <= (OD_PORT_Z + OD_NOSE) * FX1 And zprev > (OD_PORT_Z + OD_NOSE) * FX1 Then
        Contact
    ElseIf odZ < (OD_PORT_Z + OD_NOSE) * FX1 And odZ > -300 * FX1 Then
        If FHypot(odX, odY) < (OD_HUB_R + 10) * FX1 Then Crash 6
    End If
End Sub

' ---------- the autopilot ----------

' ticks to cover d starting at speed v0 (both towards the station), thrusting up to speed vc
Private Function TicksTo(ByVal d As Long, ByVal v0 As Long, ByVal vc As Long) As Long
    Dim tAcc As Long, dAcc As Long
    If d <= 0 Then Exit Function
    If v0 < 0 Then v0 = 0
    If v0 >= vc Then
        TicksTo = d \ vc
        Exit Function
    End If
    tAcc = FDiv(vc - v0, OD_ACC)
    dAcc = FMul((v0 + vc) \ 2, tAcc)
    If d <= dAcc Then
        TicksTo = ShrA(FDiv(FSqrt(FMul(v0, v0) + 2 * FMul(OD_ACC, d)) - v0, OD_ACC), 16)
    Else
        TicksTo = ShrA(tAcc, 16) + (d - dAcc) \ vc
    End If
End Function

Private Function ClampF(ByVal v As Long, ByVal lo As Long, ByVal hi As Long) As Long
    If v < lo Then
        ClampF = lo
    ElseIf v > hi Then
        ClampF = hi
    Else
        ClampF = v
    End If
End Function

' the autopilot's input
Public Function OdBot() As Long
    Dim inp As Long, want As Long, lat As Long, er As Long, rateWant As Long, k As Long, aligned As Boolean
    Dim wx As Long, wy As Long, br As Long, bu As Long, a As Long, c As Long, sn As Long
    Dim ahead As Long, sp As Long, t0 As Long, t1 As Long, t As Long, clear As Boolean, whenT As Long
    If odOver <> 0 Or odWon <> 0 Or odBetween <> 0 Then Exit Function
    ' across: towards the axis, gently - the speed wanted, turned into the craft's own right and up
    wx = ClampF(-odX \ 30, -FX1, FX1) - odVX
    wy = ClampF(-odY \ 30, -FX1, FX1) - odVY
    a = ShrA(odRoll, 8) And &HFFFF&
    c = A3Cos(a): sn = A3Sin(a)
    br = FMul(wx, -c) + FMul(wy, -sn)
    bu = FMul(wx, -sn) + FMul(wy, c)
    If br > 1966 Then
        inp = inp Or OD_IN_RIGHT
    ElseIf br < -1966 Then
        inp = inp Or OD_IN_LEFT
    End If
    If bu > 1966 Then
        inp = inp Or OD_IN_UP
    ElseIf bu < -1966 Then
        inp = inp Or OD_IN_DOWN
    End If
    ' roll: onto the slot, turning with it
    er = OdRollError()
    rateWant = odStSpin - (er * 256) \ 12
    If rateWant > odStSpin + 35840 Then rateWant = odStSpin + 35840
    If rateWant < odStSpin - 35840 Then rateWant = odStSpin - 35840
    If odRollRate < rateWant - 768 Then
        inp = inp Or OD_IN_ROLL_R
    ElseIf odRollRate > rateWant + 768 Then
        inp = inp Or OD_IN_ROLL_L
    End If
    ' along: in slowly once lined up; hold off otherwise
    lat = FHypot(odX, odY)
    aligned = lat < 6 * FX1 And Abs(er) < 700 And Abs(odRollRate - odStSpin) < 2048 And _
              Abs(odVX) < 19660 And Abs(odVY) < 19660
    If aligned Then
        want = -ClampF((odZ - (OD_PORT_Z + OD_NOSE) * FX1) \ 60, 45875, 196608)
    ElseIf odZ > 300 * FX1 Then
        want = -39321
    Else
        want = 0
    End If
    ' debris ahead: through its slice at 1.5 a tick, and only when it will be clear of us the
    ' whole way across; otherwise wait short of it, or back out if already close
    For k = 0 To odNDebris - 1
        ahead = odZ - dbZ(k) * FX1
        If ahead > -30 * FX1 And ahead <= 450 * FX1 And ahead > -26 * FX1 Then
            If want > -98304 Then want = -98304               ' through its slice briskly
            sp = 98304
            t0 = TicksTo(ahead - 30 * FX1, -odVZ, sp)
            t1 = TicksTo(ahead + 30 * FX1, -odVZ, sp)
            If t0 < 0 Then t0 = 0
            clear = True
            t = t0 - 6
            Do While t <= t1 + 6 And clear
                If t > 0 Then whenT = odLevelTicks + t Else whenT = odLevelTicks
                If Abs(DebrisXAt(k, whenT) - odX) < 70 * FX1 Then clear = False
                t = t + 3
            Loop
            If Not clear Then
                If ahead > 60 * FX1 Then want = 0 Else want = 52428
            End If
        End If
    Next k
    If odVZ > want + OD_ACC Then
        inp = inp Or OD_IN_FWD
    ElseIf odVZ < want - OD_ACC Then
        inp = inp Or OD_IN_BACK
    End If
    OdBot = inp
End Function

Public Function OdStateHash() As Long
    Dim h As Long
    h = FNV_START
    h = Fnv(h, odScore): h = Fnv(h, odLevel): h = Fnv(h, odLives)
    h = Fnv(h, odX): h = Fnv(h, odY): h = Fnv(h, odZ): h = Fnv(h, odVX): h = Fnv(h, odVY): h = Fnv(h, odVZ)
    h = Fnv(h, odRoll): h = Fnv(h, odRollRate): h = Fnv(h, odStAngle): h = Fnv(h, odFuel)
    h = Fnv(h, odCrashes): h = Fnv(h, odDocks): h = Fnv(h, odTicks): h = Fnv(h, odOver): h = Fnv(h, odWon)
    OdStateHash = h
End Function
