' Ridge Runner - the rules (a port of rr_core.c from amiga_mcp's examples/ridge_runner).
' A hover-bike race down a winding valley against three rivals, over rolling hills with
' crests that throw the bike into the air. Gates add time; finish in the first three to
' go on. 16.16 fixed point exactly as the C (A3Fix.bas): the same state hash.
Option Explicit

Public Const RR_TRACKS As Long = 6
Public Const RR_RIVALS As Long = 3
Public Const RR_LEN As Long = 16000
Public Const RR_GATE_GAP As Long = 800
Public Const RR_GATES As Long = 20
Public Const RR_TRACK_HW As Long = 70
Public Const RR_GATE_HW As Long = 90
Public Const RR_SHOULDER As Long = 150
Public Const RR_HOVER As Long = 14
Public Const RR_VMAX As Long = 851968           ' FX(13)
Public Const RR_VBOOST As Long = 1245184        ' FX(19)
Public Const RR_ENERGY As Long = 6553600        ' FX(100)
Public Const RR_BETWEEN As Long = 75

Public Const RR_IN_LEFT As Long = 1
Public Const RR_IN_RIGHT As Long = 2
Public Const RR_IN_UP As Long = 4
Public Const RR_IN_DOWN As Long = 8
Public Const RR_IN_FIRE As Long = 16

Public Const RRE_NONE As Long = 0
Public Const RRE_GATE As Long = 1
Public Const RRE_MISS As Long = 2
Public Const RRE_JUMP As Long = 3
Public Const RRE_LAND As Long = 4
Public Const RRE_BUMP As Long = 5
Public Const RRE_RIVAL_FINISH As Long = 6
Public Const RRE_FINISH As Long = 7
Public Const RRE_QUALIFY As Long = 8
Public Const RRE_FAIL As Long = 9
Public Const RRE_TRACK As Long = 10
Public Const RRE_TIMEOUT As Long = 11
Public Const RRE_OVER As Long = 12
Public Const RRE_WIN As Long = 13
Public Const RR_MAX_EVENTS As Long = 16

Private Const RPACE As Long = 720896            ' FX(11.0)
Private Const RSTEP As Long = 3276              ' FX(0.05)
Private Const BEND_LIFT As Long = 3400
Private Const BEND_BRAKE As Long = 4200
Private Const GRAV As Long = 58982              ' FX(0.9)
Private Const ACC As Long = 19660               ' FX(0.3)
Private Const ACC_B As Long = 39321             ' FX(0.6)
Private Const BRAKE As Long = 52428             ' FX(0.8)
Private Const COAST As Long = 5242              ' FX(0.08)

Public Type RrRival
    x As Long
    z As Long
    v As Long
    pace As Long
    weave As Long
    finished As Long
End Type

Public Type RrEvent
    etype As Long
    a As Long
    b As Long
End Type

Public rrSeed As Long, rrRng As Long
Public rrTrack As Long, rrOver As Long, rrWon As Long, rrBetween As Long
Public rrFinished As Long, rrPlace As Long, rrQualified As Long
Public rrX As Long, rrY As Long, rrZ As Long, rrV As Long, rrVY As Long
Public rrYaw As Long, rrSteer As Long
Public rrAir As Long
Public rrEnergy As Long
Public rrBoosting As Long, rrOfftrack As Long
Public rrGate As Long
Public rrGatesHit As Long, rrMissed As Long, rrBumps As Long, rrJumps As Long
Public rrTimeLeft As Long, rrTicks As Long, rrRaceTicks As Long
Public rrScore As Long
Public rrNFinished As Long
Public rrBumpTimer As Long
Public rv(0 To 2) As RrRival
Public rrC1 As Long, rrC2 As Long, rrPh1 As Long, rrPh2 As Long, rrA1 As Long, rrA2 As Long, rrA3 As Long, rrHph As Long
Public rrEv(0 To 15) As RrEvent
Public rrNEv As Long

Private trackName(1 To 6) As String

Public Sub RrInit()
    Dim nm As Variant, i As Long
    A3FixInit
    nm = Array("GREEN VALLEY", "RED CANYON", "DUNE RUN", "FROST PASS", "BASALT GORGE", "SKY RIDGE")
    For i = 1 To 6
        trackName(i) = nm(i - 1)
    Next i
End Sub

Public Function RrTrackName(ByVal n As Long) As String
    RrTrackName = trackName(n)
End Function

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If rrNEv < RR_MAX_EVENTS Then
        rrEv(rrNEv).etype = etype
        rrEv(rrNEv).a = a
        rrEv(rrNEv).b = b
        rrNEv = rrNEv + 1
    End If
End Sub

' mulberry32
Public Function RrRand() As Long
    Dim t As Long
    rrRng = AddW(rrRng, &H6D2B79F5)
    t = rrRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    RrRand = t Xor ShrU(t, 14)
End Function

Private Function S16(ByVal amp As Long, ByVal angle As Long) As Long
    Dim t As Long
    t = amp * A3Sin(angle And &HFFFF&)
    S16 = (t - (t And 65535)) \ 65536
End Function

Public Function RrCentre(ByVal z As Long) As Long
    RrCentre = S16(rrC1, z * 13 + rrPh1) + S16(rrC2, z * 34 + rrPh2)
End Function

Public Function RrHeight(ByVal x As Long, ByVal z As Long) As Long
    Dim d As Long, h As Long
    d = Abs(x - RrCentre(z))
    h = S16(rrA1, z * 20 + x * 7 + rrHph) + S16(rrA2, x * 29 - z * 17) + S16(rrA3, z * 156)
    If d > RR_SHOULDER Then h = h + ((d - RR_SHOULDER) * 3) \ 5    ' the valley's sides
    RrHeight = h
End Function

Public Function RrOnTrack(ByVal x As Long, ByVal z As Long) As Boolean
    Dim d As Long
    d = x - RrCentre(z)
    RrOnTrack = d > -RR_TRACK_HW And d < RR_TRACK_HW
End Function

Public Function RrPlaceNow() As Long
    Dim k As Long, p As Long
    If rrFinished Then
        RrPlaceNow = rrPlace
        Exit Function
    End If
    p = 1
    For k = 0 To RR_RIVALS - 1
        If rv(k).finished <> 0 Or rv(k).z > rrZ Then p = p + 1
    Next k
    RrPlaceNow = p
End Function

Public Sub RrLoadTrack(ByVal track As Long)
    Dim k As Long
    rrTrack = track
    rrC1 = 300 + track * 45
    rrC2 = 110 + track * 20
    rrPh1 = RrRand() And &HFFFF&
    rrPh2 = RrRand() And &HFFFF&
    rrHph = RrRand() And &HFFFF&
    rrA1 = 50 + track * 12
    rrA2 = 22 + track * 6
    rrA3 = 10 + track * 3
    rrX = RrCentre(0) * FONE
    rrZ = 0
    rrY = (RrHeight(ShrA(rrX, 16), 0) + RR_HOVER) * FONE
    rrV = 0: rrVY = 0
    rrYaw = 0: rrSteer = 0: rrAir = 0
    rrEnergy = RR_ENERGY
    rrBoosting = 0: rrOfftrack = 0
    rrGate = 0: rrGatesHit = 0: rrMissed = 0
    rrFinished = 0: rrPlace = 0: rrQualified = 0
    rrNFinished = 0
    rrRaceTicks = 0
    rrTimeLeft = 30 * 25
    For k = 0 To RR_RIVALS - 1
        rv(k).z = -(40 + k * 45) * 65536
        rv(k).x = 0
        rv(k).v = 0
        rv(k).pace = RPACE + track * RSTEP + (k - 1) * 32768 + UModL(RrRand(), 8192)
        rv(k).weave = RrRand() And &HFFFF&
        rv(k).finished = 0
    Next k
End Sub

Public Sub RrNewGame(ByVal seed As Long, ByVal track As Long)
    rrSeed = seed
    rrRng = seed
    rrOver = 0: rrWon = 0: rrBetween = 0
    rrBumps = 0: rrJumps = 0: rrTicks = 0: rrScore = 0: rrBumpTimer = 0
    rrNEv = 0
    If track < 1 Then track = 1
    If track > RR_TRACKS Then track = RR_TRACKS
    RrLoadTrack track
End Sub

Private Sub Rivals()
    Dim k As Long, want As Long, z As Long, h0 As Long, slope As Long
    For k = 0 To RR_RIVALS - 1
        If rv(k).finished = 0 Then
            z = ShrA(rv(k).z, 16)
            h0 = RrHeight(ShrA(rv(k).x, 16), z)
            want = rv(k).pace + FMul(52428, A3Sin((z * 3 + rv(k).weave) And &HFFFF&))
            If rv(k).v < want Then
                rv(k).v = rv(k).v + ACC
                If rv(k).v > want Then rv(k).v = want
            Else
                rv(k).v = rv(k).v - COAST
            End If
            ' along the winding course, not straight down it
            slope = ((RrCentre(z + 40) - RrCentre(z)) * 65536) \ 40
            rv(k).z = rv(k).z + FDiv(rv(k).v, FHypot(FONE, slope))
            z = ShrA(rv(k).z, 16)
            rv(k).x = (RrCentre(z) + S16(40, z * 9 + rv(k).weave)) * FONE
            ' the hills slow them as they slow you
            rv(k).v = rv(k).v - (RrHeight(ShrA(rv(k).x, 16), z) - h0) * 3932
            If rv(k).v < 131072 Then rv(k).v = 131072
            If rv(k).z >= RR_LEN * 65536 Then
                rrNFinished = rrNFinished + 1
                rv(k).finished = rrNFinished
                Ev RRE_RIVAL_FINISH, k, rv(k).finished
            End If
        End If
    Next k
End Sub

Private Sub Bike(ByVal inp As Long)
    Dim dir As Long, rate As Long, k As Long, vmax As Long, accel As Long, gy As Long, follow As Long
    Dim x As Long, z As Long, impact As Long
    If inp And RR_IN_RIGHT Then dir = dir + 1
    If inp And RR_IN_LEFT Then dir = dir - 1
    ' steering: quicker at low speed, hardly any in the air
    rate = 520 - ShrA(rrV, 16) * 14
    If rrAir Then rate = rate \ 3
    rrYaw = (rrYaw + dir * rate) And &HFFFF&
    rrSteer = dir
    ' throttle, brake, boost (once empty, it needs a fifth of a charge to start again)
    If (inp And RR_IN_FIRE) = 0 Then
        rrBoosting = 0
    ElseIf rrBoosting Then
        If rrEnergy > 0 Then rrBoosting = 1 Else rrBoosting = 0
    Else
        If rrEnergy >= RR_ENERGY \ 5 Then rrBoosting = 1 Else rrBoosting = 0
    End If
    If rrBoosting Then
        vmax = RR_VBOOST: accel = ACC_B
        rrEnergy = rrEnergy - 78643
        If rrEnergy < 0 Then rrEnergy = 0
    Else
        vmax = RR_VMAX: accel = ACC
        If rrEnergy < RR_ENERGY Then
            rrEnergy = rrEnergy + 16384
            If rrEnergy > RR_ENERGY Then rrEnergy = RR_ENERGY
        End If
    End If
    If RrOnTrack(ShrA(rrX, 16), ShrA(rrZ, 16)) Then rrOfftrack = 0 Else rrOfftrack = 1
    If rrOfftrack Then vmax = (vmax * 3) \ 5
    If rrAir = 0 Then
        If (inp And RR_IN_UP) <> 0 Or rrBoosting <> 0 Then
            If rrV < vmax Then
                rrV = rrV + accel
                If rrV > vmax Then rrV = vmax
            End If
        End If
        If inp And RR_IN_DOWN Then rrV = rrV - BRAKE
        If (inp And (RR_IN_UP Or RR_IN_DOWN)) = 0 And rrBoosting = 0 Then rrV = rrV - COAST
        If rrV > vmax Then rrV = rrV - rrV \ 20      ' rough ground, or the boost run out
    End If
    If rrV < 0 Then rrV = 0
    rrX = rrX + FMul(rrV, A3Sin(rrYaw))
    rrZ = rrZ + FMul(rrV, A3Cos(rrYaw))
    If rrZ < -200 * 65536 Then rrZ = -200 * 65536
    x = ShrA(rrX, 16)
    z = ShrA(rrZ, 16)
    ' hovering: follow the ground, unless it falls away faster than gravity can: then fly
    gy = (RrHeight(x, z) + RR_HOVER) * FONE
    If rrAir = 0 Then
        follow = gy - rrY
        If follow < rrVY - GRAV And rrV > 262144 Then
            rrAir = 1
            rrVY = rrVY - GRAV
            rrY = rrY + rrVY
        Else
            rrVY = follow
            rrY = gy
            rrV = rrV - FMul(follow, 3932)          ' uphill slows, downhill speeds
            If rrV < 0 Then rrV = 0
        End If
    Else
        rrAir = rrAir + 1
        rrVY = rrVY - GRAV
        rrY = rrY + rrVY
        If rrY <= gy Then
            impact = -rrVY
            If rrAir > 8 Then
                rrJumps = rrJumps + 1
                Ev RRE_JUMP, rrAir, ShrA(impact, 16)
            End If
            rrY = gy
            rrVY = 0
            rrAir = 0
            If impact > 589824 Then
                rrV = (rrV * 4) \ 5
                rrBumps = rrBumps + 1
                Ev RRE_LAND, ShrA(impact, 16), 1
            End If
        End If
    End If
    ' the rivals: bumping one slows you and pushes you aside
    If rrBumpTimer > 0 Then rrBumpTimer = rrBumpTimer - 1
    For k = 0 To RR_RIVALS - 1
        If rv(k).finished = 0 And rrAir = 0 Then
            If Abs(rv(k).x - rrX) < 22 * 65536 And Abs(rv(k).z - rrZ) < 36 * 65536 Then
                If rv(k).x < rrX Then rrX = rrX + 4 * 65536 Else rrX = rrX - 4 * 65536
                If rrBumpTimer = 0 Then
                    rrV = (rrV * 15) \ 16
                    rrBumps = rrBumps + 1
                    rrBumpTimer = 12
                    Ev RRE_BUMP, k, 0
                End If
            End If
        End If
    Next k
End Sub

Public Sub RrTick(ByVal inp As Long)
    Dim gz As Long, d As Long, bonus As Long
    If rrOver <> 0 Or rrWon <> 0 Then Exit Sub
    rrTicks = rrTicks + 1
    If rrBetween > 0 Then
        Rivals
        rrBetween = rrBetween - 1
        If rrBetween = 0 Then
            If rrQualified = 0 Then
                rrOver = 1
                Ev RRE_OVER, rrScore, 0
                Exit Sub
            End If
            If rrTrack >= RR_TRACKS Then
                rrWon = 1
                Ev RRE_WIN, rrScore, 0
                Exit Sub
            End If
            RrLoadTrack rrTrack + 1
            Ev RRE_TRACK, rrTrack, 0
        End If
        Exit Sub
    End If
    rrRaceTicks = rrRaceTicks + 1
    Bike inp
    Rivals
    ' the gates
    If rrGate < RR_GATES Then
        If rrZ >= (rrGate + 1) * RR_GATE_GAP * 65536 Then
            gz = (rrGate + 1) * RR_GATE_GAP
            d = ShrA(rrX, 16) - RrCentre(gz)
            If d > -RR_GATE_HW And d < RR_GATE_HW Then
                rrGatesHit = rrGatesHit + 1
                rrScore = rrScore + 100
                rrTimeLeft = rrTimeLeft + (9 - rrTrack \ 2) * 25
                Ev RRE_GATE, rrGate, 0
            Else
                rrMissed = rrMissed + 1
                rrTimeLeft = rrTimeLeft - 75
                Ev RRE_MISS, rrGate, 0
            End If
            rrGate = rrGate + 1
        End If
    End If
    ' the finish
    If rrZ >= RR_LEN * 65536 Then
        rrFinished = 1
        rrNFinished = rrNFinished + 1
        rrPlace = rrNFinished
        If rrPlace <= 3 Then rrQualified = 1 Else rrQualified = 0
        bonus = (4 - rrPlace) * 1000 + (rrTimeLeft \ 25) * 10
        If bonus > 0 Then rrScore = rrScore + bonus
        Ev RRE_FINISH, rrPlace, bonus
        If rrQualified Then Ev RRE_QUALIFY, rrPlace, 0 Else Ev RRE_FAIL, rrPlace, 0
        rrBetween = RR_BETWEEN
        Exit Sub
    End If
    rrTimeLeft = rrTimeLeft - 1
    If rrTimeLeft <= 0 Then
        rrTimeLeft = 0
        rrOver = 1
        Ev RRE_TIMEOUT, rrGate, 0
        Ev RRE_OVER, rrScore, 0
    End If
End Sub

' ---------- the autopilot ----------
Public Function RrBot() As Long
    Dim x As Long, z As Long, zt As Long, xt As Long, want As Long, diff As Long, za As Long, zb As Long, bend As Long
    Dim inp As Long, adiffv As Long
    If rrOver <> 0 Or rrWon <> 0 Or rrBetween <> 0 Then Exit Function
    x = ShrA(rrX, 16)
    z = ShrA(rrZ, 16)
    zt = z + 170 + ShrA(rrV, 16) * 8
    xt = RrCentre(zt)
    want = A3Atan2(xt - x, zt - z)
    diff = ADiff(want, rrYaw)
    If diff > 200 Then inp = inp Or RR_IN_RIGHT
    If diff < -200 Then inp = inp Or RR_IN_LEFT
    ' how sharply the course bends ahead: ease off for it
    za = z + 120
    zb = z + 260
    bend = Abs(ADiff(A3Atan2(RrCentre(zb) - RrCentre(za), zb - za), A3Atan2(RrCentre(za) - RrCentre(z), za - z)))
    adiffv = Abs(diff)
    If (adiffv > 5000 And rrV > 524288) Or (bend > BEND_BRAKE And rrV > 655360) Then
        inp = inp Or RR_IN_DOWN
    ElseIf adiffv < 3000 And (bend < BEND_LIFT Or rrV < 655360) Then
        inp = inp Or RR_IN_UP
    End If
    If diff < 1200 And diff > -1200 And rrEnergy > 2621440 And rrOfftrack = 0 And rrAir = 0 Then inp = inp Or RR_IN_FIRE
    If rrBoosting <> 0 And rrEnergy > 0 And diff < 2500 And diff > -2500 And rrOfftrack = 0 Then inp = inp Or RR_IN_FIRE
    RrBot = inp
End Function

Public Function RrStateHash() As Long
    Dim h As Long
    h = FNV_START
    h = Fnv(h, rrScore): h = Fnv(h, rrTrack): h = Fnv(h, rrX): h = Fnv(h, rrY): h = Fnv(h, rrZ)
    h = Fnv(h, rrV): h = Fnv(h, rrVY): h = Fnv(h, rrYaw): h = Fnv(h, rrAir): h = Fnv(h, rrEnergy)
    h = Fnv(h, rrGate): h = Fnv(h, rrGatesHit): h = Fnv(h, rrMissed): h = Fnv(h, rrBumps): h = Fnv(h, rrJumps)
    h = Fnv(h, rrTimeLeft): h = Fnv(h, rrTicks): h = Fnv(h, rrPlace): h = Fnv(h, rrOver): h = Fnv(h, rrWon)
    h = Fnv(h, rv(0).z): h = Fnv(h, rv(1).z): h = Fnv(h, rv(2).z): h = Fnv(h, rv(0).x): h = Fnv(h, rrNFinished)
    RrStateHash = h
End Function
