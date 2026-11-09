' Sphere Siege - the rules (a port of ss_core.c from amiga_mcp's examples/sphere_siege).
' A shooter inside a hollow sphere: the ship rides the inside of the shell facing the
' centre and fires inward, so a shot crosses the centre to the far wall. Enemies come
' out of the centre in spiralling trains, circle, swoop at the ship and shoot back;
' orbiters run along the shell; every fourth wave is a siege of armoured wardens.
' The ship's place is a rotation frame (R right, U up, F forward to the centre), so
' there is no pole. 16.16 fixed point exactly as the C: the same state hash.
Option Explicit

Public Const SS_R As Long = 1000
Public Const SS_LIVES As Long = 3
Public Const SS_TURN As Long = 440
Public Const SS_ACCEL As Long = 110
Public Const SS_SHOT_SPEED As Long = 110
Public Const SS_MAX_SHOTS As Long = 7
Public Const SS_FIRE_GAP As Long = 4
Public Const SS_MAX_EN As Long = 48
Public Const SS_MAX_BUL As Long = 20
Public Const SS_HIT_R As Long = 62
Public Const SS_SHIP_R As Long = 48
Public Const SS_SAFE_R As Long = 150
Public Const SS_BETWEEN As Long = 70
Public Const SS_INVULN As Long = 60
Public Const SS_EXTRA As Long = 25000
Public Const SS_SIEGE As Long = 4

Public Const SS_IN_LEFT As Long = 1
Public Const SS_IN_RIGHT As Long = 2
Public Const SS_IN_UP As Long = 4
Public Const SS_IN_DOWN As Long = 8
Public Const SS_IN_FIRE As Long = 16

Public Const EN_DART As Long = 0
Public Const EN_WEAVER As Long = 1
Public Const EN_ORBITER As Long = 2
Public Const EN_WARDEN As Long = 3

Public Const PH_WAIT As Long = 0
Public Const PH_EMERGE As Long = 1
Public Const PH_ORBIT As Long = 2
Public Const PH_SWOOP As Long = 3
Public Const PH_RETURN As Long = 4
Public Const PH_DEAD As Long = 5

Public Const SSE_NONE As Long = 0
Public Const SSE_SHOT As Long = 1
Public Const SSE_KILL As Long = 2
Public Const SSE_HIT As Long = 3
Public Const SSE_EFIRE As Long = 4
Public Const SSE_HURT As Long = 5
Public Const SSE_WAVE As Long = 6
Public Const SSE_CLEAR As Long = 7
Public Const SSE_OVER As Long = 8
Public Const SSE_LIFE As Long = 9
Public Const SSE_SWOOP As Long = 10
Public Const SS_MAX_EVENTS As Long = 24

Public Type FV
    x As Long
    y As Long
    z As Long
End Type

Public Type SsEnemy
    etype As Long
    phase As Long
    hp As Long
    timer As Long
    cool As Long
    w As Long
    swoops As Long
    d As FV
    ax As FV
    r As Long
    rHome As Long
End Type

Public Type SsMover
    alive As Long
    t As Long
    p As FV
    v As FV
End Type

Public Type SsEvent
    etype As Long
    a As Long
    b As Long
End Type

' the game, in the order of the C's SSGame (the state hash is over all of it)
Public ssSeed As Long, ssRng As Long
Public ssWave As Long, ssOver As Long, ssBetween As Long, ssSiege As Long
Public ssR As FV, ssU As FV, ssF As FV
Public ssVX As Long, ssVY As Long
Public ssLives As Long, ssInvuln As Long, ssFireCool As Long
Public ssSpeed As Long
Public en(0 To 47) As SsEnemy
Public ssNEn As Long, ssLeft As Long
Public shot(0 To 6) As SsMover
Public bul(0 To 19) As SsMover
Public ssScore As Long, ssNextExtra As Long, ssTicks As Long, ssWaveTick As Long
Public ssShots As Long, ssHits As Long, ssKills As Long, ssHurt As Long
Public ssPrevIn As Long
Public ssEv(0 To 23) As SsEvent
Public ssNEv As Long

Private enBase(0 To 3) As Long
Private fireGapOf(0 To 3) As Long

Public Sub SsInit()
    A3FixInit
    enBase(0) = 100: enBase(1) = 150: enBase(2) = 200: enBase(3) = 400
    fireGapOf(0) = 140: fireGapOf(1) = 95: fireGapOf(2) = 75: fireGapOf(3) = 55
End Sub

' ---------- vectors ----------
Public Function FvDot(a As FV, b As FV) As Long
    FvDot = MulShr(a.x, b.x, 16) + MulShr(a.y, b.y, 16) + MulShr(a.z, b.z, 16)
End Function

Public Sub FvCross(a As FV, b As FV, o As FV)
    Dim rx As Long, ry As Long, rz As Long
    rx = MulShr(a.y, b.z, 16) - MulShr(a.z, b.y, 16)
    ry = MulShr(a.z, b.x, 16) - MulShr(a.x, b.z, 16)
    rz = MulShr(a.x, b.y, 16) - MulShr(a.y, b.x, 16)
    o.x = rx
    o.y = ry
    o.z = rz
End Sub

' to unit length: a 32-bit length, then a Newton step for the last bits
Public Sub FvNorm(v As FV)
    Dim ln As Long, s As Long
    ln = FHypot3(v.x, v.y, v.z)
    If ln < 16 Then
        v.x = 0: v.y = 0: v.z = FONE
        Exit Sub
    End If
    v.x = FDiv(v.x, ln): v.y = FDiv(v.y, ln): v.z = FDiv(v.z, ln)
    s = (3 * FONE - FvDot(v, v)) \ 2
    v.x = MulShr(v.x, s, 16): v.y = MulShr(v.y, s, 16): v.z = MulShr(v.z, s, 16)
End Sub

' a turned towards b by angle ang, b away from a: a turn in their plane
Private Sub TurnFV(a As FV, b As FV, ByVal ang As Long)
    Dim c As Long, s As Long, ax As Long, ay As Long, az As Long
    c = A3Cos(ang)
    s = A3Sin(ang)
    ax = MulShr(a.x, c, 16) + MulShr(b.x, s, 16)
    ay = MulShr(a.y, c, 16) + MulShr(b.y, s, 16)
    az = MulShr(a.z, c, 16) + MulShr(b.z, s, 16)
    b.x = MulShr(b.x, c, 16) - MulShr(a.x, s, 16)
    b.y = MulShr(b.y, c, 16) - MulShr(a.y, s, 16)
    b.z = MulShr(b.z, c, 16) - MulShr(a.z, s, 16)
    a.x = ax: a.y = ay: a.z = az
End Sub

' v less its part along unit u, made unit
Private Sub Perp(v As FV, u As FV)
    Dim k As Long
    k = FvDot(v, u)
    v.x = v.x - MulShr(u.x, k, 16)
    v.y = v.y - MulShr(u.y, k, 16)
    v.z = v.z - MulShr(u.z, k, 16)
    FvNorm v
End Sub

Private Sub Orthonormal()
    FvNorm ssF
    Perp ssR, ssF
    FvCross ssF, ssR, ssU
End Sub

Private Function Rnd32(ByVal n As Long) As Long
    If n Then Rnd32 = A3Rand(ssRng) Mod n
End Function

' -1..1
Private Function RndFix() As Long
    RndFix = Rnd32(32768) * 4 - FONE
End Function

Private Sub RandDir(v As FV)
    Dim h As Long
    Do
        v.x = RndFix()
        v.y = RndFix()
        v.z = RndFix()
        h = FHypot3(v.x, v.y, v.z)
    Loop While h < FONE \ 4 Or h > FONE
    FvNorm v
End Sub

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If ssNEv < SS_MAX_EVENTS Then
        ssEv(ssNEv).etype = etype
        ssEv(ssNEv).a = a
        ssEv(ssNEv).b = b
        ssNEv = ssNEv + 1
    End If
End Sub

' ---------- positions ----------
Public Sub SsShipPos(p As FV)
    p.x = -ssF.x * SS_R
    p.y = -ssF.y * SS_R
    p.z = -ssF.z * SS_R
End Sub

Public Sub SsEnemyPos(ByVal k As Long, p As FV)
    p.x = MulShr(en(k).d.x, en(k).r, 16)
    p.y = MulShr(en(k).d.y, en(k).r, 16)
    p.z = MulShr(en(k).d.z, en(k).r, 16)
End Sub

Public Function SsEnemyLive(ByVal k As Long) As Boolean
    SsEnemyLive = en(k).phase <> PH_WAIT And en(k).phase <> PH_DEAD And en(k).r >= SS_SAFE_R * FONE
End Function

Public Function SsEnemyScore(ByVal etype As Long, ByVal wave As Long) As Long
    SsEnemyScore = enBase(etype) + 10 * (wave - 1)
End Function

' where a direction from the centre lies in the ship's frame (z > 0: the far side)
Public Sub SsLocal(d As FV, x As Long, y As Long, z As Long)
    x = FvDot(d, ssR)
    y = FvDot(d, ssU)
    z = FvDot(d, ssF)
End Sub

Public Sub SsFace(d As FV)
    ssF = d
    Orthonormal
    ssVX = 0
    ssVY = 0
End Sub

' ---------- waves ----------
Private Sub ClearMovers(m() As SsMover)
    Dim k As Long
    For k = LBound(m) To UBound(m)
        m(k).alive = 0: m(k).t = 0
        m(k).p.x = 0: m(k).p.y = 0: m(k).p.z = 0
        m(k).v.x = 0: m(k).v.y = 0: m(k).v.z = 0
    Next k
End Sub

Public Sub SsStartWave(ByVal wave As Long)
    Dim groups As Long, per As Long, gi As Long, j As Long, n As Long, etype As Long, dir As Long, k As Long
    Dim ax As FV, d0 As FV
    ssWave = wave
    If wave Mod SS_SIEGE = 0 Then ssSiege = 1 Else ssSiege = 0
    ssSpeed = 256 + 18 * (wave - 1)
    If ssSpeed > 520 Then ssSpeed = 520
    groups = 3 + (wave - 1) \ 2
    If groups > 6 Then groups = 6
    If ssSiege Then per = 5 Else per = 6
    For k = 0 To SS_MAX_EN - 1
        en(k).etype = 0: en(k).phase = 0: en(k).hp = 0: en(k).timer = 0: en(k).cool = 0
        en(k).w = 0: en(k).swoops = 0
        en(k).d.x = 0: en(k).d.y = 0: en(k).d.z = 0
        en(k).ax.x = 0: en(k).ax.y = 0: en(k).ax.z = 0
        en(k).r = 0: en(k).rHome = 0
    Next k
    For gi = 0 To groups - 1
        If gi And 1 Then dir = -1 Else dir = 1
        If ssSiege Then
            If gi And 1 Then etype = EN_WEAVER Else etype = EN_WARDEN
        ElseIf wave >= 3 And gi Mod 3 = 2 Then
            etype = EN_ORBITER
        ElseIf wave >= 2 And (gi And 1) <> 0 Then
            etype = EN_WEAVER
        Else
            etype = EN_DART
        End If
        RandDir ax
        RandDir d0
        Perp d0, ax
        j = 0
        Do While j < per And n < SS_MAX_EN
            en(n).etype = etype
            en(n).phase = PH_WAIT
            If etype = EN_WARDEN Then en(n).hp = 3 Else en(n).hp = 1
            en(n).timer = 30 + gi * 55 + j * 6
            en(n).d = d0
            en(n).ax = ax
            en(n).w = dir * ShrA(1000 * ssSpeed, 8)
            en(n).r = 0
            If etype = EN_ORBITER Then
                en(n).rHome = 900 * FONE
            Else
                en(n).rHome = (480 + Rnd32(260)) * FONE
            End If
            en(n).cool = 60 + Rnd32(90)
            j = j + 1
            n = n + 1
        Loop
    Next gi
    ssNEn = n
    ssLeft = n
    ssBetween = 0
    ssWaveTick = 0
    ClearMovers bul
    Ev SSE_WAVE, wave, ssSiege
End Sub

Public Sub SsNewGame(ByVal seed As Long, ByVal wave As Long)
    ssSeed = seed
    ssRng = AddW(MulW(seed, &H9E3779B1), 1)
    ssOver = 0: ssBetween = 0: ssSiege = 0
    ssR.x = FONE: ssR.y = 0: ssR.z = 0
    ssU.x = 0: ssU.y = FONE: ssU.z = 0
    ssF.x = 0: ssF.y = 0: ssF.z = FONE
    ssVX = 0: ssVY = 0
    ssLives = SS_LIVES
    ssInvuln = 0: ssFireCool = 0
    ClearMovers shot
    ssScore = 0: ssNextExtra = SS_EXTRA: ssTicks = 0
    ssShots = 0: ssHits = 0: ssKills = 0: ssHurt = 0: ssPrevIn = 0
    ssNEv = 0
    If wave < 1 Then wave = 1
    SsStartWave wave
End Sub

' ---------- the ship ----------
Private Sub Hurt(ByVal cause As Long)
    If ssInvuln > 0 Or ssOver <> 0 Then Exit Sub
    ssLives = ssLives - 1
    ssHurt = ssHurt + 1
    ssInvuln = SS_INVULN
    ClearMovers bul
    Ev SSE_HURT, ssLives, cause
    If ssLives <= 0 Then
        ssOver = 1
        Ev SSE_OVER, 0, 0
    End If
End Sub

Private Function Approach(ByVal v As Long, ByVal target As Long, ByVal stp As Long) As Long
    If v < target Then
        If v + stp > target Then Approach = target Else Approach = v + stp
    ElseIf v > target Then
        If v - stp < target Then Approach = target Else Approach = v - stp
    Else
        Approach = v
    End If
End Function

Private Sub MoveShip(ByVal inp As Long)
    Dim tx As Long, ty As Long
    If inp And SS_IN_RIGHT Then tx = tx + SS_TURN
    If inp And SS_IN_LEFT Then tx = tx - SS_TURN
    If inp And SS_IN_UP Then ty = ty + SS_TURN
    If inp And SS_IN_DOWN Then ty = ty - SS_TURN
    ssVX = Approach(ssVX, tx, SS_ACCEL)
    ssVY = Approach(ssVY, ty, SS_ACCEL)
    If ssVX Then TurnFV ssR, ssF, ssVX          ' the ship towards +R: F away from R
    If ssVY Then TurnFV ssU, ssF, ssVY
    If ssVX <> 0 Or ssVY <> 0 Then Orthonormal
End Sub

Private Sub Fire()
    Dim k As Long
    If ssFireCool > 0 Then Exit Sub
    For k = 0 To SS_MAX_SHOTS - 1
        If shot(k).alive = 0 Then
            shot(k).alive = 1
            shot(k).t = 0
            SsShipPos shot(k).p
            shot(k).v.x = ssF.x * SS_SHOT_SPEED
            shot(k).v.y = ssF.y * SS_SHOT_SPEED
            shot(k).v.z = ssF.z * SS_SHOT_SPEED
            ssShots = ssShots + 1
            ssFireCool = SS_FIRE_GAP
            Ev SSE_SHOT, k, 0
            Exit Sub
        End If
    Next k
End Sub

Private Sub KillEnemy(ByVal k As Long)
    en(k).phase = PH_DEAD
    ssKills = ssKills + 1
    ssLeft = ssLeft - 1
    ssScore = ssScore + SsEnemyScore(en(k).etype, ssWave)
    Ev SSE_KILL, k, en(k).etype
End Sub

' shot s's step from p - v to p against enemy k: its closest approach
Private Function ShotHits(ByVal s As Long, ByVal k As Long) As Boolean
    Dim ep As FV, ex As Long, ey As Long, ez As Long, a0 As Long, a As Long, d2 As Long
    SsEnemyPos k, ep
    ex = ShrA(ep.x - shot(s).p.x, 16)
    If ex > 400 Or ex < -400 Then Exit Function
    ey = ShrA(ep.y - shot(s).p.y, 16)
    If ey > 400 Or ey < -400 Then Exit Function
    ez = ShrA(ep.z - shot(s).p.z, 16)
    If ez > 400 Or ez < -400 Then Exit Function
    a0 = Fix((CDbl(ex) * shot(s).v.x + CDbl(ey) * shot(s).v.y + CDbl(ez) * shot(s).v.z) / 7208960#)
    If a0 > 0 Then
        a = 0
    ElseIf a0 < -SS_SHOT_SPEED Then
        a = -SS_SHOT_SPEED
    Else
        a = a0
    End If
    d2 = ex * ex + ey * ey + ez * ez - 2 * a * a0 + a * a
    ShotHits = d2 < SS_HIT_R * SS_HIT_R
End Function

Private Sub MoveShots()
    Dim k As Long, j As Long
    For k = 0 To SS_MAX_SHOTS - 1
        If shot(k).alive Then
            shot(k).p.x = shot(k).p.x + shot(k).v.x
            shot(k).p.y = shot(k).p.y + shot(k).v.y
            shot(k).p.z = shot(k).p.z + shot(k).v.z
            shot(k).t = shot(k).t + 1
            If shot(k).t * SS_SHOT_SPEED > 2 * SS_R + 20 Then
                shot(k).alive = 0
            Else
                For j = 0 To ssNEn - 1
                    If SsEnemyLive(j) Then
                        If ShotHits(k, j) Then
                            shot(k).alive = 0
                            ssHits = ssHits + 1
                            en(j).hp = en(j).hp - 1
                            If en(j).hp <= 0 Then
                                KillEnemy j
                            Else
                                Ev SSE_HIT, j, en(j).hp
                            End If
                            Exit For
                        End If
                    End If
                Next j
            End If
        End If
    Next k
End Sub

' ---------- enemies ----------
Private Function DistUnits(a As FV, b As FV) As Long
    Dim dx As Long, dy As Long, dz As Long
    dx = ShrA(a.x - b.x, 16)
    dy = ShrA(a.y - b.y, 16)
    dz = ShrA(a.z - b.z, 16)
    DistUnits = ISqrtD(CDbl(UD(dx * dx + dy * dy + dz * dz)))
End Function

Private Sub EnemyFire(ByVal k As Long, ship As FV)
    Dim p As FV, v As FV, b As Long, spd As Long
    spd = ShrA(20 * ssSpeed, 8)
    SsEnemyPos k, p
    If DistUnits(p, ship) < 220 Then Exit Sub        ' too close to dodge: hold fire
    For b = 0 To SS_MAX_BUL - 1
        If bul(b).alive = 0 Then
            v.x = ship.x - p.x
            v.y = ship.y - p.y
            v.z = ship.z - p.z
            FvNorm v
            bul(b).alive = 1
            bul(b).t = 0
            bul(b).p = p
            bul(b).v.x = v.x * spd
            bul(b).v.y = v.y * spd
            bul(b).v.z = v.z * spd
            Ev SSE_EFIRE, k, b
            Exit Sub
        End If
    Next b
End Sub

Private Function FireGap(ByVal etype As Long) As Long
    FireGap = (fireGapOf(etype) * 256) \ ssSpeed
End Function

Private Sub MoveEnemy(ByVal k As Long, ship As FV)
    Dim t As FV, n As FV, a As FV, p As FV, stp As Long, c As Long, sgn As Long
    If en(k).phase = PH_DEAD Then Exit Sub
    If en(k).phase = PH_WAIT Then
        en(k).timer = en(k).timer - 1
        If en(k).timer <= 0 Then en(k).phase = PH_EMERGE
        Exit Sub
    End If
    stp = (ssSpeed * FONE) \ 256
    ' along its great circle
    FvCross en(k).ax, en(k).d, n
    TurnFV en(k).d, n, en(k).w
    FvNorm en(k).d
    Perp en(k).ax, en(k).d

    t.x = -ssF.x: t.y = -ssF.y: t.z = -ssF.z     ' the ship's direction
    Select Case en(k).phase
        Case PH_EMERGE
            en(k).r = en(k).r + 13 * stp
            If en(k).r >= en(k).rHome Then
                en(k).r = en(k).rHome
                en(k).phase = PH_ORBIT
                en(k).timer = 50 + Rnd32(110)
                If en(k).w > 0 Then sgn = 1 Else sgn = -1
                If en(k).etype = EN_ORBITER Then
                    en(k).w = sgn * (130 + Rnd32(110))
                Else
                    en(k).w = sgn * ShrA((300 + Rnd32(220)) * ssSpeed, 8)
                End If
            End If
        Case PH_ORBIT
            en(k).timer = en(k).timer - 1
            If en(k).timer <= 0 Then
                If en(k).etype = EN_ORBITER Then         ' a new great circle now and then
                    RandDir en(k).ax
                    Perp en(k).ax, en(k).d
                    en(k).timer = 80 + Rnd32(80)
                Else
                    en(k).phase = PH_SWOOP
                    en(k).timer = 110
                    en(k).swoops = en(k).swoops + 1
                    en(k).w = ShrA(720 * ssSpeed, 8)
                    Ev SSE_SWOOP, k, 0
                End If
            End If
        Case PH_SWOOP
            c = FvDot(en(k).d, t)
            FvCross en(k).d, t, a                ' turning about d x t takes d towards the ship
            If FHypot3(a.x, a.y, a.z) > FONE \ 64 Then
                FvNorm a
                en(k).ax = a
            End If
            If en(k).r < 880 * FONE Then en(k).r = en(k).r + 22 * stp
            If c > 64552 Then
                en(k).phase = PH_RETURN
                en(k).timer = 22
            Else
                en(k).timer = en(k).timer - 1
                If en(k).timer <= 0 Then
                    en(k).phase = PH_RETURN
                    en(k).timer = 22
                End If
            End If
        Case PH_RETURN                               ' on past the ship, then back in
            en(k).timer = en(k).timer - 1
            If en(k).timer <= 0 Then
                If en(k).r > en(k).rHome Then
                    en(k).r = en(k).r - 16 * stp
                    If en(k).r < en(k).rHome Then en(k).r = en(k).rHome
                Else
                    RandDir en(k).ax
                    Perp en(k).ax, en(k).d
                    en(k).phase = PH_ORBIT
                    en(k).timer = 60 + Rnd32(100)
                    If ssWaveTick > 1500 Then en(k).timer = en(k).timer - 40
                    If k And 1 Then sgn = -1 Else sgn = 1
                    en(k).w = sgn * ShrA((300 + Rnd32(200)) * ssSpeed, 8)
                End If
            End If
    End Select
    ' fire
    If en(k).phase = PH_ORBIT Or en(k).phase = PH_SWOOP Or (en(k).phase = PH_RETURN And en(k).etype <> EN_DART) Then
        If en(k).etype <> EN_DART Or en(k).phase = PH_SWOOP Then
            en(k).cool = en(k).cool - 1
            If en(k).cool <= 0 Then
                en(k).cool = FireGap(en(k).etype) + Rnd32(40)
                If ssWaveTick > 40 Then EnemyFire k, ship
            End If
        End If
    End If
    ' into the ship
    If en(k).r > 700 * FONE Then
        SsEnemyPos k, p
        If DistUnits(p, ship) < 70 And ssInvuln = 0 Then
            KillEnemy k
            Hurt 1
        End If
    End If
End Sub

Private Sub MoveBullets(ship As FV)
    Dim k As Long
    For k = 0 To SS_MAX_BUL - 1
        If bul(k).alive Then
            bul(k).p.x = bul(k).p.x + bul(k).v.x
            bul(k).p.y = bul(k).p.y + bul(k).v.y
            bul(k).p.z = bul(k).p.z + bul(k).v.z
            bul(k).t = bul(k).t + 1
            If bul(k).t > 160 Then
                bul(k).alive = 0
            ElseIf FHypot3(ShrA(bul(k).p.x, 4), ShrA(bul(k).p.y, 4), ShrA(bul(k).p.z, 4)) > (SS_R + 40) * 4096 Then
                bul(k).alive = 0
            ElseIf DistUnits(bul(k).p, ship) < SS_SHIP_R Then
                bul(k).alive = 0
                Hurt 0
                If ssOver Then Exit Sub
            End If
        End If
    Next k
End Sub

Public Sub SsTick(ByVal inp As Long)
    Dim ship As FV, k As Long
    If ssOver Then Exit Sub
    ssTicks = ssTicks + 1
    If ssInvuln > 0 Then ssInvuln = ssInvuln - 1
    If ssFireCool > 0 Then ssFireCool = ssFireCool - 1
    MoveShip inp
    If inp And SS_IN_FIRE Then Fire
    ssPrevIn = inp
    MoveShots
    If ssBetween > 0 Then
        ssBetween = ssBetween - 1
        If ssBetween = 0 Then SsStartWave ssWave + 1
        Exit Sub
    End If
    ssWaveTick = ssWaveTick + 1
    SsShipPos ship
    k = 0
    Do While k < ssNEn And ssOver = 0
        MoveEnemy k, ship
        k = k + 1
    Loop
    If ssOver = 0 Then MoveBullets ship
    If ssScore >= ssNextExtra Then
        ssLives = ssLives + 1
        ssNextExtra = ssNextExtra + SS_EXTRA
        Ev SSE_LIFE, ssLives, 0
    End If
    If ssLeft <= 0 And ssOver = 0 Then
        ssScore = ssScore + 500 * ssWave
        ssBetween = SS_BETWEEN
        ClearMovers bul
        Ev SSE_CLEAR, ssWave, 0
    End If
End Sub

' ---------- the autopilot ----------
' steer the line of fire onto the nearest enemy (for one on the far side the frame
' turns the other way), dodge bullets close by, fire when one is on the line
Public Function SsBot() As Long
    Dim inp As Long, k As Long, best As Long, lx As Long, ly As Long, lz As Long
    Dim bx As Long, by As Long, bz As Long, cost As Long, bcost As Long, lat As Long
    Dim n As FV, pd As FV, ship As FV, lead As Long, c As Long, sn As Long
    Dim sx As Long, sy As Long, stopx As Long, stopy As Long, danger As Boolean
    Dim rx As Long, ry As Long, rz As Long, vx As Long, vy As Long, vz As Long, vv As Long
    Dim t As Long, mx As Long, my As Long, mz As Long
    best = -1
    bcost = &H7FFFFFFF
    SsShipPos ship
    For k = 0 To ssNEn - 1
        If SsEnemyLive(k) Then
            ' lead it: where it will be when a shot gets there
            SsLocal en(k).d, lx, ly, lz
            lead = (SS_R * FONE + MulShr(lz, en(k).r, 16)) \ (SS_SHOT_SPEED * FONE)
            FvCross en(k).ax, en(k).d, n
            c = A3Cos(en(k).w * lead)
            sn = A3Sin(en(k).w * lead)
            pd.x = MulShr(en(k).d.x, c, 16) + MulShr(n.x, sn, 16)
            pd.y = MulShr(en(k).d.y, c, 16) + MulShr(n.y, sn, 16)
            pd.z = MulShr(en(k).d.z, c, 16) + MulShr(n.z, sn, 16)
            SsLocal pd, lx, ly, lz
            lat = Abs(lx) + Abs(ly)
            If MulShr(lat, en(k).r, 16) < 50 * FONE And ssFireCool = 0 Then inp = inp Or SS_IN_FIRE
            If en(k).phase = PH_SWOOP Then cost = lat Else cost = lat + FONE \ 8
            If cost < bcost Then
                bcost = cost
                best = k
                bx = lx: by = ly: bz = lz
            End If
        End If
    Next k
    If best >= 0 Then
        If bz > 0 Then
            sx = -bx: sy = -by
        Else
            sx = bx: sy = by
        End If
        stopx = (ssVX * ssVX) \ 35
        stopy = (ssVY * ssVY) \ 35
        If ssVX > 0 Then t = stopx Else t = 0
        If sx > FONE \ 90 + t Then
            inp = inp Or SS_IN_RIGHT
        Else
            If ssVX < 0 Then t = stopx Else t = 0
            If sx < -(FONE \ 90) - t Then inp = inp Or SS_IN_LEFT
        End If
        If ssVY > 0 Then t = stopy Else t = 0
        If sy > FONE \ 90 + t Then
            inp = inp Or SS_IN_UP
        Else
            If ssVY < 0 Then t = stopy Else t = 0
            If sy < -(FONE \ 90) - t Then inp = inp Or SS_IN_DOWN
        End If
    End If
    ' dodge: a bullet that would pass close in the next few ticks takes over the
    ' stick: keep moving the way the ship goes, or start sideways
    If ssInvuln = 0 Then
        k = 0
        Do While k < SS_MAX_BUL And Not danger
            If bul(k).alive Then
                rx = ShrA(bul(k).p.x - ship.x, 16)
                ry = ShrA(bul(k).p.y - ship.y, 16)
                rz = ShrA(bul(k).p.z - ship.z, 16)
                If Not (rx > 600 Or rx < -600 Or ry > 600 Or ry < -600 Or rz > 600 Or rz < -600) Then
                    vx = ShrA(bul(k).v.x, 12)
                    vy = ShrA(bul(k).v.y, 12)
                    vz = ShrA(bul(k).v.z, 12)
                    vv = vx * vx + vy * vy + vz * vz
                    If vv > 0 Then
                        t = -(((rx * vx + ry * vy + rz * vz) * 16) \ vv)
                        If t >= 0 And t <= 14 Then
                            mx = rx + (vx * t) \ 16
                            my = ry + (vy * t) \ 16
                            mz = rz + (vz * t) \ 16
                            If mx * mx + my * my + mz * mz < 75 * 75 Then danger = True
                        End If
                    End If
                End If
            End If
            k = k + 1
        Loop
        If danger Then
            inp = inp And Not (SS_IN_LEFT Or SS_IN_RIGHT Or SS_IN_UP Or SS_IN_DOWN)
            If ssVX > 0 Or (ssVX = 0 And ssVY = 0 And (ssTicks And 64) <> 0) Then
                inp = inp Or SS_IN_RIGHT
            ElseIf ssVX < 0 Or (ssVX = 0 And ssVY = 0) Then
                inp = inp Or SS_IN_LEFT
            ElseIf ssVY > 0 Then
                inp = inp Or SS_IN_UP
            Else
                inp = inp Or SS_IN_DOWN
            End If
        End If
    End If
    SsBot = inp
End Function

Private Function HashFV(ByVal h As Long, v As FV) As Long
    HashFV = Fnv(Fnv(Fnv(h, v.x), v.y), v.z)
End Function

Private Function HashMover(ByVal h As Long, m As SsMover) As Long
    h = Fnv(Fnv(h, m.alive), m.t)
    h = HashFV(h, m.p)
    HashMover = HashFV(h, m.v)
End Function

' the C hashes the whole SSGame struct as 32-bit words up to its events: the same fields in the same order
Public Function SsStateHash() As Long
    Dim h As Long, k As Long
    h = FNV_START
    h = Fnv(h, ssSeed): h = Fnv(h, ssRng): h = Fnv(h, ssWave): h = Fnv(h, ssOver)
    h = Fnv(h, ssBetween): h = Fnv(h, ssSiege)
    h = HashFV(h, ssR): h = HashFV(h, ssU): h = HashFV(h, ssF)
    h = Fnv(h, ssVX): h = Fnv(h, ssVY): h = Fnv(h, ssLives): h = Fnv(h, ssInvuln)
    h = Fnv(h, ssFireCool): h = Fnv(h, ssSpeed)
    For k = 0 To SS_MAX_EN - 1
        h = Fnv(h, en(k).etype): h = Fnv(h, en(k).phase): h = Fnv(h, en(k).hp): h = Fnv(h, en(k).timer)
        h = Fnv(h, en(k).cool): h = Fnv(h, en(k).w): h = Fnv(h, en(k).swoops)
        h = HashFV(h, en(k).d): h = HashFV(h, en(k).ax)
        h = Fnv(h, en(k).r): h = Fnv(h, en(k).rHome)
    Next k
    h = Fnv(h, ssNEn): h = Fnv(h, ssLeft)
    For k = 0 To SS_MAX_SHOTS - 1
        h = HashMover(h, shot(k))
    Next k
    For k = 0 To SS_MAX_BUL - 1
        h = HashMover(h, bul(k))
    Next k
    h = Fnv(h, ssScore): h = Fnv(h, ssNextExtra): h = Fnv(h, ssTicks): h = Fnv(h, ssWaveTick)
    h = Fnv(h, ssShots): h = Fnv(h, ssHits): h = Fnv(h, ssKills): h = Fnv(h, ssHurt)
    h = Fnv(h, ssPrevIn)
    SsStateHash = h
End Function

' the autopilot plays from a wave: ticks played
Public Function SsAutoGame(ByVal seed As Long, ByVal wave As Long, ByVal maxTicks As Long) As Long
    Dim t As Long
    SsNewGame seed, wave
    Do While t < maxTicks And ssOver = 0
        SsTick SsBot()
        ssNEv = 0
        t = t + 1
    Loop
    SsAutoGame = t
End Function
