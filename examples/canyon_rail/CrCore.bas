' Canyon Rail - the rules (a port of cr_core.c from amiga_mcp's examples/canyon_rail).
' A rail shooter: the camera rides a fixed winding path down a canyon at a steady speed;
' you move a sight about the view and fire. Turrets on the walls and drones swooping
' across fire bolts at you; shoot them down too, or your shield takes them. Fuel pods
' top the shield up. Hits in a row build a multiplier (up to x8). At each stage's end a
' guardian: four nodes orbiting its core. Three stages. What the sight is on is found
' with the engine's own camera maths (here in integers, as a3d_math.c), so hits are
' decided the same way they are drawn. Exactly the C's arithmetic: the same state hash.
Option Explicit

Public Const CR_STAGES As Long = 3
Public Const CR_LEN As Long = 7000
Public Const CR_SPEED As Long = 9
Public Const CR_MAX_TARGETS As Long = 40
Public Const CR_MAX_BOLTS As Long = 12
Public Const CR_SHIELD As Long = 100
Public Const CR_BOLT_DMG As Long = 12
Public Const CR_FIRE_GAP As Long = 5
Public Const CR_SIGHT_SPEED As Long = 7
Public Const CR_VIEW_W As Long = 320
Public Const CR_VIEW_H As Long = 256
Public Const CR_BETWEEN As Long = 75
Public Const CR_NODES As Long = 4

Public Const CR_IN_LEFT As Long = 1
Public Const CR_IN_RIGHT As Long = 2
Public Const CR_IN_UP As Long = 4
Public Const CR_IN_DOWN As Long = 8
Public Const CR_IN_FIRE As Long = 16

Public Const TG_TURRET As Long = 0
Public Const TG_DRONE As Long = 1
Public Const TG_POD As Long = 2

Public Const CRE_NONE As Long = 0
Public Const CRE_SHOT As Long = 1
Public Const CRE_HIT As Long = 2
Public Const CRE_KILL As Long = 3
Public Const CRE_BOLT_DOWN As Long = 4
Public Const CRE_MISS As Long = 5
Public Const CRE_HURT As Long = 6
Public Const CRE_POD As Long = 7
Public Const CRE_FIRE As Long = 8
Public Const CRE_BOSS As Long = 9
Public Const CRE_NODE As Long = 10
Public Const CRE_BOSS_DOWN As Long = 11
Public Const CRE_STAGE As Long = 12
Public Const CRE_OVER As Long = 13
Public Const CRE_WIN As Long = 14
Public Const CR_MAX_EVENTS As Long = 16

Private Const BOLT_SPEED As Long = 12
Private Const VIEW_AHEAD As Long = 1500
Public Const CR_FOV As Long = 200
Private Const NODE_R As Long = 110
Private Const BOSS_AHEAD As Long = 450

Public Type CrTarget
    ttype As Long
    alive As Long
    hp As Long
    cool As Long
    s As Long
    side As Long
    h As Long
    amp As Long
    phase As Long
End Type

Public Type CrBolt
    alive As Long
    t As Long
    flight As Long
    x0 As Long
    y0 As Long
    z0 As Long
    x1 As Long
    y1 As Long
    z1 As Long
End Type

Public Type CrEvent
    etype As Long
    a As Long
    b As Long
End Type

Public crSeed As Long, crRng As Long
Public crStage As Long, crOver As Long, crWon As Long, crBetween As Long
Public crCamS As Long
Public crBoss As Long
Public crNodeHp(0 To 3) As Long
Public crBossAngle As Long, crBossCool As Long
Public tg(0 To 39) As CrTarget
Public crNTg As Long
Public bolt(0 To 11) As CrBolt
Public crSX As Long, crSY As Long
Public crFireCool As Long, crCombo As Long, crBestCombo As Long
Public crShield As Long
Public crScore As Long, crTicks As Long
Public crShots As Long, crHits As Long, crKills As Long, crHurt As Long
Public crLastShotHit As Long
Public crEv(0 To 15) As CrEvent
Public crNEv As Long

' the ride's camera (cr_camera), whole units: position, cos/sin of yaw and pitch >> 4
Public rcX As Long, rcY As Long, rcZ As Long, rcYaw As Long
Private rcCy4 As Long, rcSy4 As Long, rcCp4 As Long, rcSp4 As Long, rcFor As Long
' CrProject's results
Public prX As Long, prY As Long, prDepth As Long

Public Sub CrInit()
    A3FixInit
    rcFor = -1
End Sub

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If crNEv < CR_MAX_EVENTS Then
        crEv(crNEv).etype = etype
        crEv(crNEv).a = a
        crEv(crNEv).b = b
        crNEv = crNEv + 1
    End If
End Sub

' mulberry32
Private Function Rnd32() As Long
    Dim t As Long
    crRng = AddW(crRng, &H6D2B79F5)
    t = crRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    Rnd32 = t Xor ShrU(t, 14)
End Function

Private Function S16(ByVal amp As Long, ByVal angle As Long) As Long
    Dim t As Long
    t = amp * A3Sin(angle And &HFFFF&)
    S16 = (t - (t And 65535)) \ 65536
End Function

Public Function CrPathX(ByVal s As Long) As Long
    CrPathX = S16(260, s * 9) + S16(110, s * 23 + 9000)
End Function

Public Function CrPathY(ByVal s As Long) As Long
    CrPathY = S16(40, s * 7) + 60
End Function

Public Function CrHalfWidth(ByVal s As Long) As Long
    CrHalfWidth = 160 + S16(40, s * 13)
End Function

Public Function CrSize(ByVal ttype As Long) As Long
    Select Case ttype
        Case TG_TURRET: CrSize = 22
        Case TG_DRONE: CrSize = 16
        Case Else: CrSize = 14
    End Select
End Function

' cr_camera: the camera at the ride's place (cached per place)
Public Sub CrCamera()
    Dim s As Long
    s = crCamS
    If s = rcFor Then Exit Sub
    rcX = CrPathX(s)
    rcY = CrPathY(s) + 40
    rcZ = s
    rcYaw = A3Atan2(CrPathX(s + 80) - CrPathX(s), 80)
    rcCy4 = ShrA(A3Cos(rcYaw), 4): rcSy4 = ShrA(A3Sin(rcYaw), 4)
    rcCp4 = ShrA(A3Cos(300), 4): rcSp4 = ShrA(A3Sin(300), 4)
    rcFor = s
End Sub

' cr_project: a world point to the view (prX, prY) and its depth; False if behind
Public Function CrProject(ByVal x As Long, ByVal y As Long, ByVal z As Long) As Boolean
    Dim dx As Long, dy As Long, dz As Long, t As Long, rx As Long, rz As Long, vy As Long, vz As Long
    CrCamera
    dx = x - rcX: dy = y - rcY: dz = z - rcZ
    t = dx * rcCy4 - dz * rcSy4: rx = (t - (t And 4095)) \ 4096
    t = dx * rcSy4 + dz * rcCy4: rz = (t - (t And 4095)) \ 4096
    t = dy * rcCp4 + rz * rcSp4: vy = (t - (t And 4095)) \ 4096
    t = rz * rcCp4 - dy * rcSp4: vz = (t - (t And 4095)) \ 4096
    If vz < 16 Then Exit Function
    prX = CR_VIEW_W \ 2 + (rx * CR_FOV) \ vz
    prY = CR_VIEW_H \ 2 - (vy * CR_FOV) \ vz
    prDepth = vz
    CrProject = True
End Function

Public Sub CrTargetPos(ByVal k As Long, x As Long, y As Long, z As Long)
    z = tg(k).s
    Select Case tg(k).ttype
        Case TG_TURRET
            x = CrPathX(tg(k).s) + tg(k).side * (CrHalfWidth(tg(k).s) - 14)
            y = 30 + tg(k).h
        Case TG_DRONE
            x = CrPathX(tg(k).s) + S16(tg(k).amp, crTicks * 500 + tg(k).phase)
            y = CrPathY(tg(k).s) + 70 + S16(25, crTicks * 900 + tg(k).phase)
        Case Else
            x = CrPathX(tg(k).s) + S16(60, crTicks * 400 + tg(k).phase)
            y = CrPathY(tg(k).s) + 45
    End Select
End Sub

Public Sub CrNodePos(ByVal k As Long, x As Long, y As Long, z As Long)
    Dim bs As Long, a As Long
    bs = CR_LEN + BOSS_AHEAD
    a = (crBossAngle + k * 16384) And &HFFFF&
    x = CrPathX(bs) + ShrA(A3Cos(a) * NODE_R, 16)
    y = CrPathY(bs) + 90 + ShrA(A3Sin(a) * NODE_R, 16)
    z = bs
End Sub

Public Sub CrBoltPos(ByVal k As Long, x As Long, y As Long, z As Long)
    Dim f As Long
    f = FDiv(bolt(k).t * 65536, bolt(k).flight * 65536)
    x = ShrA(bolt(k).x0 + FMul(bolt(k).x1 - bolt(k).x0, f), 16)
    y = ShrA(bolt(k).y0 + FMul(bolt(k).y1 - bolt(k).y0, f), 16)
    z = ShrA(bolt(k).z0 + FMul(bolt(k).z1 - bolt(k).z0, f), 16)
End Sub

Private Sub ClearBolts()
    Dim k As Long
    For k = 0 To CR_MAX_BOLTS - 1
        bolt(k).alive = 0: bolt(k).t = 0: bolt(k).flight = 0
        bolt(k).x0 = 0: bolt(k).y0 = 0: bolt(k).z0 = 0: bolt(k).x1 = 0: bolt(k).y1 = 0: bolt(k).z1 = 0
    Next k
End Sub

Public Sub CrLoadStage(ByVal stage As Long)
    Dim k As Long, n As Long, r As Long
    n = 18 + 6 * stage
    crStage = stage
    crCamS = 0
    crBoss = 0
    crBossAngle = 0
    crBossCool = 60
    For k = 0 To CR_NODES - 1
        crNodeHp(k) = 3 + stage
    Next k
    ClearBolts
    If n < CR_MAX_TARGETS Then crNTg = n Else crNTg = CR_MAX_TARGETS
    For k = 0 To crNTg - 1
        r = UModL(Rnd32(), 100)
        If r < 45 Then
            tg(k).ttype = TG_TURRET
        ElseIf r < 45 + 30 + stage * 3 Then
            tg(k).ttype = TG_DRONE
        Else
            tg(k).ttype = TG_POD
        End If
        tg(k).alive = 1
        If tg(k).ttype = TG_TURRET Then tg(k).hp = 2 Else tg(k).hp = 1
        tg(k).s = 700 + (k * (CR_LEN - 1100)) \ crNTg + UModL(Rnd32(), 120)
        If Rnd32() And 1 Then tg(k).side = 1 Else tg(k).side = -1
        tg(k).h = 40 + UModL(Rnd32(), 140)
        tg(k).amp = 60 + UModL(Rnd32(), 80)
        tg(k).phase = Rnd32() And &HFFFF&
        tg(k).cool = 20 + UModL(Rnd32(), 60)
    Next k
End Sub

Public Sub CrNewGame(ByVal seed As Long, ByVal stage As Long)
    Dim k As Long
    crSeed = seed
    crRng = seed
    crOver = 0: crWon = 0: crBetween = 0
    crSX = CR_VIEW_W \ 2
    crSY = CR_VIEW_H \ 2
    crFireCool = 0: crCombo = 0: crBestCombo = 0
    crShield = CR_SHIELD
    crScore = 0: crTicks = 0
    crShots = 0: crHits = 0: crKills = 0: crHurt = 0: crLastShotHit = 0
    crNEv = 0
    For k = 0 To CR_MAX_TARGETS - 1
        tg(k).ttype = 0: tg(k).alive = 0: tg(k).hp = 0: tg(k).cool = 0: tg(k).s = 0
        tg(k).side = 0: tg(k).h = 0: tg(k).amp = 0: tg(k).phase = 0
    Next k
    rcFor = -1
    If stage < 1 Then stage = 1
    If stage > CR_STAGES Then stage = CR_STAGES
    CrLoadStage stage
End Sub

' a bolt from (x, y, z) at the camera, aimed where the camera will be
Private Sub FireBolt(ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Dim k As Long, flight As Long, ahead As Long, speed As Long, s1 As Long
    ahead = z - crCamS
    If crBoss Then speed = BOLT_SPEED Else speed = CR_SPEED + BOLT_SPEED
    For k = 0 To CR_MAX_BOLTS - 1
        If bolt(k).alive = 0 Then Exit For
    Next k
    If k = CR_MAX_BOLTS Or ahead < 60 Then Exit Sub
    flight = ahead \ speed
    If flight < 8 Then flight = 8
    If crBoss Then s1 = crCamS Else s1 = crCamS + CR_SPEED * flight
    bolt(k).alive = 1
    bolt(k).t = 0
    bolt(k).flight = flight
    bolt(k).x0 = x * 65536: bolt(k).y0 = y * 65536: bolt(k).z0 = z * 65536
    bolt(k).x1 = CrPathX(s1) * 65536: bolt(k).y1 = (CrPathY(s1) + 40) * 65536: bolt(k).z1 = s1 * 65536
    Ev CRE_FIRE, k, 0
End Sub

Public Function CrMult() As Long
    Dim m As Long
    m = 1 + crCombo \ 4
    If m > 8 Then m = 8
    CrMult = m
End Function

Private Sub Hurt()
    crShield = crShield - CR_BOLT_DMG
    crHurt = crHurt + 1
    crCombo = 0
    Ev CRE_HURT, crShield, 0
    If crShield <= 0 Then
        crShield = 0
        crOver = 1
        Ev CRE_OVER, crScore, 0
    End If
End Sub

' is the sight on (x, y, z) of this size, nearer than the best so far?
Private Function TryHit(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal size As Long, bd As Long) As Boolean
    Dim r As Long, ddx As Long, ddy As Long
    If CrProject(x, y, z) Then
        r = (size * CR_FOV) \ prDepth + 3
        ddx = prX - crSX
        ddy = prY - crSY
        If ddx * ddx + ddy * ddy <= r * r And prDepth < bd Then
            bd = prDepth
            TryHit = True
        End If
    End If
End Function

' the shot: the nearest thing the sight is on
Private Sub Shoot()
    Dim k As Long, best As Long, kind As Long, bd As Long, x As Long, y As Long, z As Long, ahead As Long
    best = -1
    bd = &H7FFFFFFF
    crShots = crShots + 1
    crFireCool = CR_FIRE_GAP
    Ev CRE_SHOT, crSX, crSY
    For k = 0 To CR_MAX_BOLTS - 1
        If bolt(k).alive Then
            CrBoltPos k, x, y, z
            If TryHit(x, y, z, 9, bd) Then best = k: kind = 1
        End If
    Next k
    If crBoss Then
        For k = 0 To CR_NODES - 1
            If crNodeHp(k) > 0 Then
                CrNodePos k, x, y, z
                If TryHit(x, y, z, 22, bd) Then best = k: kind = 2
            End If
        Next k
    Else
        For k = 0 To crNTg - 1
            ahead = tg(k).s - crCamS
            If tg(k).alive <> 0 And ahead >= 30 And ahead <= VIEW_AHEAD Then
                CrTargetPos k, x, y, z
                If TryHit(x, y, z, CrSize(tg(k).ttype), bd) Then best = k: kind = 0
            End If
        Next k
    End If
    If best >= 0 Then crLastShotHit = 1 Else crLastShotHit = 0
    If best < 0 Then
        crCombo = 0
        Ev CRE_MISS, 0, 0
        Exit Sub
    End If
    crHits = crHits + 1
    crCombo = crCombo + 1
    If crCombo > crBestCombo Then crBestCombo = crCombo
    If kind = 1 Then
        bolt(best).alive = 0
        crScore = crScore + 25 * CrMult()
        Ev CRE_BOLT_DOWN, best, 0
    ElseIf kind = 2 Then
        crNodeHp(best) = crNodeHp(best) - 1
        If crNodeHp(best) > 0 Then
            Ev CRE_HIT, best, crNodeHp(best)
            Exit Sub
        End If
        crScore = crScore + 500 * CrMult()
        Ev CRE_NODE, best, 0
        For k = 0 To CR_NODES - 1
            If crNodeHp(k) > 0 Then Exit Sub
        Next k
        crScore = crScore + 2000 * crStage
        crBetween = CR_BETWEEN
        ClearBolts
        Ev CRE_BOSS_DOWN, crStage, 0
    Else
        tg(best).hp = tg(best).hp - 1
        If tg(best).hp > 0 Then
            Ev CRE_HIT, best, tg(best).hp
            Exit Sub
        End If
        tg(best).alive = 0
        crKills = crKills + 1
        If tg(best).ttype = TG_POD Then
            If crShield + 25 > CR_SHIELD Then crShield = CR_SHIELD Else crShield = crShield + 25
            crScore = crScore + 50 * CrMult()
            Ev CRE_POD, best, crShield
        Else
            If tg(best).ttype = TG_TURRET Then crScore = crScore + 100 * CrMult() Else crScore = crScore + 150 * CrMult()
            Ev CRE_KILL, best, tg(best).ttype
        End If
    End If
End Sub

Public Sub CrTick(ByVal inp As Long)
    Dim k As Long, ahead As Long, x As Long, y As Long, z As Long, n As Long, j As Long
    If crOver <> 0 Or crWon <> 0 Then Exit Sub
    crTicks = crTicks + 1
    If crBetween > 0 Then
        crBetween = crBetween - 1
        If crBetween = 0 Then
            If crStage >= CR_STAGES Then
                crWon = 1
                Ev CRE_WIN, crScore, 0
                Exit Sub
            End If
            CrLoadStage crStage + 1
            Ev CRE_STAGE, crStage, 0
        End If
        Exit Sub
    End If
    ' the ride, up to the guardian
    If crBoss = 0 Then
        crCamS = crCamS + CR_SPEED
        If crCamS >= CR_LEN Then
            crCamS = CR_LEN
            crBoss = 1
            Ev CRE_BOSS, crStage, 0
        End If
    End If
    ' the sight
    If inp And CR_IN_LEFT Then crSX = crSX - CR_SIGHT_SPEED
    If inp And CR_IN_RIGHT Then crSX = crSX + CR_SIGHT_SPEED
    If inp And CR_IN_UP Then crSY = crSY - CR_SIGHT_SPEED
    If inp And CR_IN_DOWN Then crSY = crSY + CR_SIGHT_SPEED
    If crSX < 8 Then crSX = 8
    If crSX > CR_VIEW_W - 8 Then crSX = CR_VIEW_W - 8
    If crSY < 8 Then crSY = 8
    If crSY > CR_VIEW_H - 8 Then crSY = CR_VIEW_H - 8
    If crFireCool > 0 Then crFireCool = crFireCool - 1
    If (inp And CR_IN_FIRE) <> 0 And crFireCool = 0 Then Shoot
    If crBetween Then Exit Sub
    ' the enemies fire
    If crBoss = 0 Then
        For k = 0 To crNTg - 1
            If tg(k).alive <> 0 And tg(k).ttype <> TG_POD Then
                ahead = tg(k).s - crCamS
                If ahead < 20 Then
                    tg(k).alive = 0                      ' passed by
                ElseIf ahead <= 1100 And ahead >= 250 Then
                    tg(k).cool = tg(k).cool - 1
                    If tg(k).cool <= 0 Then
                        tg(k).cool = 70 - crStage * 10 + UModL(Rnd32(), 40)
                        CrTargetPos k, x, y, z
                        FireBolt x, y, z
                    End If
                End If
            End If
        Next k
    Else
        crBossAngle = crBossAngle + 300 + crStage * 60
        crBossCool = crBossCool - 1
        If crBossCool <= 0 Then
            n = UModL(Rnd32(), CR_NODES)
            j = 0
            Do While j < CR_NODES And crNodeHp(n) <= 0
                n = (n + 1) Mod CR_NODES
                j = j + 1
            Loop
            CrNodePos n, x, y, z
            FireBolt x, y, z
            crBossCool = 46 - crStage * 8
        End If
    End If
    ' the bolts
    For k = 0 To CR_MAX_BOLTS - 1
        If bolt(k).alive Then
            bolt(k).t = bolt(k).t + 1
            If bolt(k).t >= bolt(k).flight Then
                bolt(k).alive = 0
                Hurt
                If crOver Then Exit Sub
            End If
        End If
    Next k
End Sub

' ---------- the autopilot ----------
Public Function CrBot() As Long
    Dim k As Long, px As Long, py As Long, found As Boolean, r As Long, x As Long, y As Long, z As Long
    Dim best As Long, nearV As Long, dd As Long, ahead As Long, inp As Long
    If crOver <> 0 Or crWon <> 0 Or crBetween <> 0 Then Exit Function
    best = &H7FFFFFFF
    ' a bolt about to land first
    For k = 0 To CR_MAX_BOLTS - 1
        If bolt(k).alive Then
            CrBoltPos k, x, y, z
            If CrProject(x, y, z) Then
                If bolt(k).flight - bolt(k).t < best Then
                    best = bolt(k).flight - bolt(k).t
                    px = prX: py = prY
                    r = (9 * CR_FOV) \ prDepth + 3
                    found = True
                End If
            End If
        End If
    Next k
    If Not found Or best > 28 Then
        nearV = &H7FFFFFFF
        If crBoss Then
            For k = 0 To CR_NODES - 1
                If crNodeHp(k) > 0 Then
                    CrNodePos k, x, y, z
                    If CrProject(x, y, z) Then
                        dd = (prX - crSX) * (prX - crSX) + (prY - crSY) * (prY - crSY)
                        If dd < nearV Then
                            nearV = dd
                            px = prX: py = prY
                            r = (22 * CR_FOV) \ prDepth + 3
                            found = True
                        End If
                    End If
                End If
            Next k
        Else
            For k = 0 To crNTg - 1
                ahead = tg(k).s - crCamS
                If tg(k).alive <> 0 And ahead >= 60 And ahead <= 1100 Then
                    CrTargetPos k, x, y, z
                    If CrProject(x, y, z) Then
                        If prX >= 4 And prX <= CR_VIEW_W - 4 And prY >= 4 And prY <= CR_VIEW_H - 4 Then
                            If ahead < nearV Then
                                nearV = ahead
                                px = prX: py = prY
                                r = (CrSize(tg(k).ttype) * CR_FOV) \ prDepth + 3
                                found = True
                            End If
                        End If
                    End If
                End If
            Next k
        End If
    End If
    If Not found Then Exit Function
    If px > crSX + 3 Then inp = inp Or CR_IN_RIGHT
    If px < crSX - 3 Then inp = inp Or CR_IN_LEFT
    If py > crSY + 3 Then inp = inp Or CR_IN_DOWN
    If py < crSY - 3 Then inp = inp Or CR_IN_UP
    If (px - crSX) * (px - crSX) + (py - crSY) * (py - crSY) <= (r - 2) * (r - 2) And crFireCool = 0 Then inp = inp Or CR_IN_FIRE
    CrBot = inp
End Function

Public Function CrStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    h = Fnv(h, crScore): h = Fnv(h, crStage): h = Fnv(h, crCamS): h = Fnv(h, crBoss)
    h = Fnv(h, crSX): h = Fnv(h, crSY): h = Fnv(h, crShield): h = Fnv(h, crCombo)
    h = Fnv(h, crShots): h = Fnv(h, crHits): h = Fnv(h, crKills): h = Fnv(h, crHurt)
    h = Fnv(h, crTicks): h = Fnv(h, crOver): h = Fnv(h, crWon)
    For i = 0 To 3
        h = Fnv(h, crNodeHp(i))
    Next i
    For i = 0 To crNTg - 1
        h = Fnv(h, tg(i).alive * 16 + tg(i).hp)
    Next i
    CrStateHash = h
End Function

Public Function CrAutoGame(ByVal seed As Long, ByVal stage As Long, ByVal maxTicks As Long) As Long
    Dim t As Long
    CrNewGame seed, stage
    Do While t < maxTicks And crOver = 0 And crWon = 0
        CrTick CrBot()
        crNEv = 0
        t = t + 1
    Loop
    CrAutoGame = t
End Function
