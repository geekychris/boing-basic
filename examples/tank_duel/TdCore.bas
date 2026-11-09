' Tank Duel - the rules (a port of td_core.c from amiga_mcp's examples/tank_duel).
' A tank fight in a walled arena: shells bounce once off the walls, crates break,
' and three kinds of enemy (scout, mortar, bulwark). 16.16 fixed point and 16-bit
' angles exactly as the C (A3Fix.bas), so a seed fights the same fight and gives
' the same state hash as the original.
'
' x across, z ahead; angle 0 = +z, a quarter turn = +x; one tick is 40 ms.
Option Explicit

Public Const TD_ARENA As Long = 1000
Public Const TD_MAX_OBS As Long = 20
Public Const TD_MAX_TANKS As Long = 8
Public Const TD_MAX_SHELLS As Long = 16
Public Const TD_MAX_MORTARS As Long = 6
Public Const TD_ROUNDS As Long = 8
Public Const TD_TANK_R As Long = 28
Public Const TD_SHELL_SPEED As Long = 2097152       ' FX(32)
Public Const TD_SHELL_LIFE As Long = 50
Public Const TD_RELOAD As Long = 25
Public Const TD_HP As Long = 100
Public Const TD_SHELL_DMG As Long = 20
Public Const TD_SPLASH_R As Long = 90
Public Const TD_SPLASH_DMG As Long = 35
Public Const TD_BETWEEN As Long = 75

Public Const TD_IN_LEFT As Long = 1
Public Const TD_IN_RIGHT As Long = 2
Public Const TD_IN_UP As Long = 4
Public Const TD_IN_DOWN As Long = 8
Public Const TD_IN_FIRE As Long = 16

Public Const OB_PILLAR As Long = 0
Public Const OB_PYRAMID As Long = 1
Public Const OB_CRATE As Long = 2

Public Const TK_PLAYER As Long = 0
Public Const TK_SCOUT As Long = 1
Public Const TK_MORTAR As Long = 2
Public Const TK_BULWARK As Long = 3

Public Const TDE_NONE As Long = 0
Public Const TDE_FIRE As Long = 1
Public Const TDE_EFIRE As Long = 2
Public Const TDE_LOB As Long = 3
Public Const TDE_BOUNCE As Long = 4
Public Const TDE_GLANCE As Long = 5
Public Const TDE_HIT As Long = 6
Public Const TDE_KILL As Long = 7
Public Const TDE_HURT As Long = 8
Public Const TDE_SPLASH As Long = 9
Public Const TDE_CRATE_HIT As Long = 10
Public Const TDE_CRATE_BREAK As Long = 11
Public Const TDE_ROUND_CLEAR As Long = 12
Public Const TDE_ROUND As Long = 13
Public Const TDE_DEAD As Long = 14
Public Const TDE_WIN As Long = 15
Public Const TD_MAX_EVENTS As Long = 24

Private Const SHIELD_ARC As Long = 6370
Private Const MORTAR_FLIGHT As Long = 45

Public Type TdObstacle
    kind As Long
    hp As Long
    x As Long
    z As Long
    r As Long
End Type

Public Type TdTank
    ttype As Long
    alive As Long
    hp As Long
    x As Long
    z As Long
    v As Long
    yaw As Long
    reload As Long
    aiTimer As Long
    orbit As Long
    held As Long
End Type

Public Type TdShell
    alive As Long
    owner As Long
    bounces As Long
    life As Long
    x As Long
    z As Long
    dx As Long
    dz As Long
End Type

Public Type TdMortar
    alive As Long
    owner As Long
    t As Long
    flight As Long
    x0 As Long
    z0 As Long
    tx As Long
    tz As Long
End Type

Public Type TdEvent
    etype As Long
    a As Long
    b As Long
    x As Long
    z As Long
End Type

' the game (C's TDGame)
Public tdSeed As Long, tdRng As Long
Public tdRound As Long, tdOver As Long, tdWon As Long, tdBetween As Long
Public tk(0 To 7) As TdTank
Public tdNTanks As Long
Public ob(0 To 19) As TdObstacle
Public tdNObs As Long
Public sh(0 To 15) As TdShell
Public mo(0 To 5) As TdMortar
Public tdScore As Long, tdTicks As Long
Public tdKills As Long, tdShots As Long, tdHits As Long, tdDamage As Long
Public tdEv(0 To 23) As TdEvent
Public tdNEv As Long

' by type: top speed, turn rate, hits it takes, reload
Private vmax(0 To 3) As Long
Private turnRate(0 To 3) As Long
Private hitsOf(0 To 3) As Long
Private reloadOf(0 To 3) As Long
Private roundMix(0 To 7, 0 To 2) As Long
Private obKinds(0 To 12) As Long

Public Sub TdInit()
    Dim i As Long, m As Variant, k As Variant
    A3FixInit
    vmax(0) = 393216: vmax(1) = 458752: vmax(2) = 196608: vmax(3) = 262144
    turnRate(0) = 700: turnRate(1) = 650: turnRate(2) = 300: turnRate(3) = 100
    hitsOf(0) = TD_HP: hitsOf(1) = 1: hitsOf(2) = 2: hitsOf(3) = 2
    reloadOf(0) = TD_RELOAD: reloadOf(1) = 60: reloadOf(2) = 110: reloadOf(3) = 55
    m = Array(2, 0, 0, 2, 0, 1, 1, 1, 1, 2, 0, 2, 2, 2, 0, 1, 1, 2, 2, 2, 2, 1, 2, 3)
    For i = 0 To 23
        roundMix(i \ 3, i Mod 3) = m(i)
    Next i
    k = Array(0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2)
    For i = 0 To 12
        obKinds(i) = k(i)
    Next i
End Sub

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long, ByVal x As Long, ByVal z As Long)
    If tdNEv < TD_MAX_EVENTS Then
        tdEv(tdNEv).etype = etype
        tdEv(tdNEv).a = a
        tdEv(tdNEv).b = b
        tdEv(tdNEv).x = x
        tdEv(tdNEv).z = z
        tdNEv = tdNEv + 1
    End If
End Sub

' mulberry32
Public Function TdRand() As Long
    Dim t As Long
    tdRng = AddW(tdRng, &H6D2B79F5)
    t = tdRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    TdRand = t Xor ShrU(t, 14)
End Function

Public Function TdAngleTo(ByVal dx As Long, ByVal dz As Long) As Long
    TdAngleTo = A3Atan2(ShrA(dx, 8), ShrA(dz, 8))
End Function

Public Function TdEnemiesLeft() As Long
    Dim k As Long, n As Long
    For k = 1 To tdNTanks - 1
        If tk(k).alive Then n = n + 1
    Next k
    TdEnemiesLeft = n
End Function

Public Function TdBlocked(ByVal x As Long, ByVal z As Long, ByVal r As Long) As Boolean
    Dim k As Long, lim As Long
    lim = (TD_ARENA - r) * 65536
    If x > lim Or x < -lim Or z > lim Or z < -lim Then
        TdBlocked = True
        Exit Function
    End If
    For k = 0 To tdNObs - 1
        If ob(k).kind = OB_CRATE Then
            If ob(k).hp > 0 Then
                If Abs(x - ob(k).x) < (ob(k).r + r) * 65536 And Abs(z - ob(k).z) < (ob(k).r + r) * 65536 Then
                    TdBlocked = True
                    Exit Function
                End If
            End If
        ElseIf FHypot(x - ob(k).x, z - ob(k).z) < (ob(k).r + r) * 65536 Then
            TdBlocked = True
            Exit Function
        End If
    Next k
End Function

Public Function TdAddTank(ByVal ttype As Long, ByVal x As Long, ByVal z As Long, ByVal yaw As Long) As Long
    Dim n As Long
    If tdNTanks >= TD_MAX_TANKS Then
        TdAddTank = -1
        Exit Function
    End If
    n = tdNTanks
    tk(n).ttype = ttype
    tk(n).alive = 1
    tk(n).hp = hitsOf(ttype)
    tk(n).x = x
    tk(n).z = z
    tk(n).v = 0
    tk(n).yaw = yaw And &HFFFF&
    tk(n).aiTimer = 0
    tk(n).held = 0
    tk(n).reload = reloadOf(ttype) \ 2 + UModL(TdRand(), 30)
    If TdRand() And 1 Then tk(n).orbit = 1 Else tk(n).orbit = -1
    tdNTanks = n + 1
    TdAddTank = n
End Function

Private Sub PlaceObstacles()
    Dim k As Long, tries As Long, j As Long, ok As Boolean, x As Long, z As Long, n As Long
    tdNObs = 0
    For k = 0 To 12
        n = tdNObs
        ob(n).kind = obKinds(k)
        Select Case ob(n).kind
            Case OB_PILLAR: ob(n).r = 26
            Case OB_PYRAMID: ob(n).r = 50
            Case Else: ob(n).r = 34
        End Select
        If ob(n).kind = OB_CRATE Then ob(n).hp = 2 Else ob(n).hp = 1
        For tries = 0 To 39
            x = (UModL(TdRand(), 1500) - 750) * 65536
            z = (UModL(TdRand(), 1300) - 650) * 65536
            ok = True
            If Abs(x) < 220 * 65536 And z < -450 * 65536 Then ok = False
            j = 0
            Do While j < tdNObs And ok
                If FHypot(x - ob(j).x, z - ob(j).z) < (ob(n).r + ob(j).r + 90) * 65536 Then ok = False
                j = j + 1
            Loop
            If ok Then
                ob(n).x = x
                ob(n).z = z
                tdNObs = tdNObs + 1
                Exit For
            End If
        Next tries
    Next k
End Sub

Private Sub ClearShots()
    Dim k As Long
    For k = 0 To TD_MAX_SHELLS - 1
        sh(k).alive = 0: sh(k).owner = 0: sh(k).bounces = 0: sh(k).life = 0
        sh(k).x = 0: sh(k).z = 0: sh(k).dx = 0: sh(k).dz = 0
    Next k
    For k = 0 To TD_MAX_MORTARS - 1
        mo(k).alive = 0: mo(k).owner = 0: mo(k).t = 0: mo(k).flight = 0
        mo(k).x0 = 0: mo(k).z0 = 0: mo(k).tx = 0: mo(k).tz = 0
    Next k
End Sub

Public Sub TdLoadRound(ByVal rnd As Long)
    Dim k As Long, n As Long, t As Long, keepHp As Long, x As Long, z As Long, j As Long
    keepHp = tk(0).hp
    tdRound = rnd
    ClearShots
    PlaceObstacles
    tdNTanks = 0
    TdAddTank TK_PLAYER, 0, -800 * 65536, 0
    If rnd > 1 Then
        If keepHp + 30 > TD_HP Then tk(0).hp = TD_HP Else tk(0).hp = keepHp + 30
    End If
    tk(0).reload = 0
    For t = 0 To 2
        For k = 0 To roundMix(rnd - 1, t) - 1
            x = (-600 + ((n * 397 + UModL(TdRand(), 160)) Mod 1200)) * 65536
            z = (450 + UModL(TdRand(), 350)) * 65536
            j = 0
            Do While j < 20
                If Not TdBlocked(x, z, TD_TANK_R + 10) Then Exit Do
                x = x + 60 * 65536
                j = j + 1
            Loop
            TdAddTank TK_SCOUT + t, x, z, &H8000&
            n = n + 1
        Next k
    Next t
End Sub

Public Sub TdNewGame(ByVal seed As Long, ByVal rnd As Long)
    Dim k As Long
    tdSeed = seed
    tdRng = seed
    tdOver = 0: tdWon = 0: tdBetween = 0
    tdScore = 0: tdTicks = 0
    tdKills = 0: tdShots = 0: tdHits = 0: tdDamage = 0
    tdNEv = 0
    For k = 0 To TD_MAX_TANKS - 1
        tk(k).ttype = 0: tk(k).alive = 0: tk(k).hp = 0: tk(k).x = 0: tk(k).z = 0: tk(k).v = 0
        tk(k).yaw = 0: tk(k).reload = 0: tk(k).aiTimer = 0: tk(k).orbit = 0: tk(k).held = 0
    Next k
    For k = 0 To TD_MAX_OBS - 1
        ob(k).kind = 0: ob(k).hp = 0: ob(k).x = 0: ob(k).z = 0: ob(k).r = 0
    Next k
    If rnd < 1 Then rnd = 1
    If rnd > TD_ROUNDS Then rnd = TD_ROUNDS
    TdLoadRound rnd
    tk(0).hp = TD_HP
End Sub

' ---------- moving and colliding ----------
Private Sub PushOut(ByVal i As Long)
    Dim k As Long, lim As Long, dx As Long, dz As Long, px As Long, pz As Long, reach As Long, d As Long
    lim = (TD_ARENA - TD_TANK_R) * 65536
    For k = 0 To tdNObs - 1
        dx = tk(i).x - ob(k).x
        dz = tk(i).z - ob(k).z
        reach = (ob(k).r + TD_TANK_R) * 65536
        If ob(k).kind = OB_CRATE Then
            If ob(k).hp > 0 And Abs(dx) < reach And Abs(dz) < reach Then
                px = reach - Abs(dx)
                pz = reach - Abs(dz)
                If px < pz Then
                    If dx < 0 Then tk(i).x = tk(i).x - px Else tk(i).x = tk(i).x + px
                Else
                    If dz < 0 Then tk(i).z = tk(i).z - pz Else tk(i).z = tk(i).z + pz
                End If
            End If
        ElseIf Abs(dx) < reach + FONE And Abs(dz) < reach + FONE Then   ' (FHypot can be a little short)
            d = FHypot(dx, dz)
            If d < reach Then
                If d < FONE Then
                    dx = FONE
                    d = FONE
                End If
                tk(i).x = ob(k).x + FDiv(FMul(dx, reach), d)
                tk(i).z = ob(k).z + FDiv(FMul(dz, reach), d)
            End If
        End If
    Next k
    If tk(i).x > lim Then tk(i).x = lim
    If tk(i).x < -lim Then tk(i).x = -lim
    If tk(i).z > lim Then tk(i).z = lim
    If tk(i).z < -lim Then tk(i).z = -lim
End Sub

Private Sub TanksApart()
    Dim i As Long, j As Long, dx As Long, dz As Long, d As Long, push As Long, mx As Long, mz As Long
    For i = 0 To tdNTanks - 1
        For j = i + 1 To tdNTanks - 1
            If tk(i).alive <> 0 And tk(j).alive <> 0 Then
                dx = tk(j).x - tk(i).x
                dz = tk(j).z - tk(i).z
                If Abs(dx) < 57 * 65536 And Abs(dz) < 57 * 65536 Then
                    d = FHypot(dx, dz)
                    If d < 56 * 65536 Then
                        If d < FONE Then
                            dx = FONE
                            d = FONE
                        End If
                        push = (56 * 65536 - d) \ 2
                        mx = FDiv(FMul(dx, push), d)
                        mz = FDiv(FMul(dz, push), d)
                        tk(i).x = tk(i).x - mx: tk(i).z = tk(i).z - mz
                        tk(j).x = tk(j).x + mx: tk(j).z = tk(j).z + mz
                    End If
                End If
            End If
        Next j
    Next i
End Sub

' turn towards heading want and drive at speed (negative: back)
Private Sub Drive(ByVal i As Long, ByVal want As Long, ByVal speed As Long)
    Dim d As Long, r As Long
    d = ADiff(want, tk(i).yaw)
    r = turnRate(tk(i).ttype)
    If d > r Then d = r
    If d < -r Then d = -r
    tk(i).yaw = (tk(i).yaw + d) And &HFFFF&
    If tk(i).v < speed Then
        tk(i).v = tk(i).v + 32768
        If tk(i).v > speed Then tk(i).v = speed
    ElseIf tk(i).v > speed Then
        tk(i).v = tk(i).v - 39321
        If tk(i).v < speed Then tk(i).v = speed
    End If
    tk(i).x = tk(i).x + FMul(tk(i).v, A3Sin(tk(i).yaw))
    tk(i).z = tk(i).z + FMul(tk(i).v, A3Cos(tk(i).yaw))
    PushOut i
End Sub

Public Function TdFire(ByVal i As Long) As Boolean
    Dim k As Long, fx As Long, fz As Long
    If tk(i).reload > 0 Or tk(i).alive = 0 Then Exit Function
    For k = 0 To TD_MAX_SHELLS - 1
        If sh(k).alive = 0 Then Exit For
    Next k
    If k = TD_MAX_SHELLS Then Exit Function
    fx = A3Sin(tk(i).yaw)
    fz = A3Cos(tk(i).yaw)
    sh(k).alive = 1
    sh(k).owner = i
    sh(k).bounces = 1
    sh(k).life = TD_SHELL_LIFE
    sh(k).x = tk(i).x + fx * (TD_TANK_R + 6)
    sh(k).z = tk(i).z + fz * (TD_TANK_R + 6)
    sh(k).dx = FMul(TD_SHELL_SPEED, fx)
    sh(k).dz = FMul(TD_SHELL_SPEED, fz)
    tk(i).reload = reloadOf(tk(i).ttype)
    If i = 0 Then
        tdShots = tdShots + 1
        Ev TDE_FIRE, i, 0, tk(i).x, tk(i).z
    Else
        Ev TDE_EFIRE, i, 0, tk(i).x, tk(i).z
    End If
    TdFire = True
End Function

Private Sub Lob(ByVal i As Long)
    Dim k As Long
    For k = 0 To TD_MAX_MORTARS - 1
        If mo(k).alive = 0 Then Exit For
    Next k
    If k = TD_MAX_MORTARS Then Exit Sub
    mo(k).alive = 1
    mo(k).owner = i
    mo(k).t = 0
    mo(k).flight = MORTAR_FLIGHT
    mo(k).x0 = tk(i).x
    mo(k).z0 = tk(i).z
    mo(k).tx = tk(0).x + FMul(tk(0).v, A3Sin(tk(0).yaw)) * (MORTAR_FLIGHT \ 2)
    mo(k).tz = tk(0).z + FMul(tk(0).v, A3Cos(tk(0).yaw)) * (MORTAR_FLIGHT \ 2)
    tk(i).reload = reloadOf(tk(i).ttype)
    Ev TDE_LOB, i, k, mo(k).tx, mo(k).tz
End Sub

Private Sub Damage(ByVal i As Long, ByVal amount As Long, ByVal x As Long, ByVal z As Long)
    If tk(i).alive = 0 Then Exit Sub
    If i = 0 Then
        tk(0).hp = tk(0).hp - amount
        tdDamage = tdDamage + amount
        Ev TDE_HURT, amount, tk(0).hp, x, z
        If tk(0).hp <= 0 Then
            tk(0).hp = 0
            tk(0).alive = 0
            tdOver = 1
            Ev TDE_DEAD, 0, 0, tk(0).x, tk(0).z
        End If
        Exit Sub
    End If
    tk(i).hp = tk(i).hp - 1
    If tk(i).hp > 0 Then
        Ev TDE_HIT, i, tk(i).hp, x, z
        Exit Sub
    End If
    tk(i).alive = 0
    tdKills = tdKills + 1
    Select Case tk(i).ttype
        Case TK_SCOUT: tdScore = tdScore + 100
        Case TK_MORTAR: tdScore = tdScore + 200
        Case Else: tdScore = tdScore + 300
    End Select
    Ev TDE_KILL, i, tk(i).ttype, tk(i).x, tk(i).z
End Sub

' ---------- shells ----------
Private Sub Shells()
    Dim k As Long, s As Long, j As Long, lim As Long, dx As Long, dz As Long, a As Long, rr As Long
    lim = TD_ARENA * 65536
    rr = TD_TANK_R * 65536
    For k = 0 To TD_MAX_SHELLS - 1
        If sh(k).alive Then
            sh(k).life = sh(k).life - 1
            If sh(k).life <= 0 Then
                sh(k).alive = 0
            Else
                s = 0
                Do While s < 4 And sh(k).alive <> 0
                    sh(k).x = sh(k).x + sh(k).dx \ 4
                    sh(k).z = sh(k).z + sh(k).dz \ 4
                    ' the walls: one bounce, then it's spent
                    If sh(k).x > lim Or sh(k).x < -lim Or sh(k).z > lim Or sh(k).z < -lim Then
                        If sh(k).bounces = 0 Then
                            sh(k).alive = 0
                            Ev TDE_SPLASH, 0, 0, sh(k).x, sh(k).z
                            Exit Do
                        End If
                        sh(k).bounces = sh(k).bounces - 1
                        If sh(k).x > lim Or sh(k).x < -lim Then
                            sh(k).dx = -sh(k).dx
                            If sh(k).x > 0 Then sh(k).x = 2 * lim - sh(k).x Else sh(k).x = -2 * lim - sh(k).x
                        End If
                        If sh(k).z > lim Or sh(k).z < -lim Then
                            sh(k).dz = -sh(k).dz
                            If sh(k).z > 0 Then sh(k).z = 2 * lim - sh(k).z Else sh(k).z = -2 * lim - sh(k).z
                        End If
                        Ev TDE_BOUNCE, k, 0, sh(k).x, sh(k).z
                    End If
                    ' obstacles
                    j = 0
                    Do While j < tdNObs And sh(k).alive <> 0
                        If ob(j).kind = OB_CRATE Then
                            If ob(j).hp > 0 And Abs(sh(k).x - ob(j).x) < ob(j).r * 65536 And Abs(sh(k).z - ob(j).z) < ob(j).r * 65536 Then
                                sh(k).alive = 0
                                ob(j).hp = ob(j).hp - 1
                                If ob(j).hp <= 0 Then
                                    If sh(k).owner = 0 Then tdScore = tdScore + 20
                                    Ev TDE_CRATE_BREAK, j, 0, ob(j).x, ob(j).z
                                Else
                                    Ev TDE_CRATE_HIT, j, ob(j).hp, sh(k).x, sh(k).z
                                End If
                            End If
                        ElseIf Abs(sh(k).x - ob(j).x) < (ob(j).r + 1) * 65536 And Abs(sh(k).z - ob(j).z) < (ob(j).r + 1) * 65536 Then
                            If FHypot(sh(k).x - ob(j).x, sh(k).z - ob(j).z) < ob(j).r * 65536 Then
                                sh(k).alive = 0
                                Ev TDE_SPLASH, 1, 0, sh(k).x, sh(k).z
                            End If
                        End If
                        j = j + 1
                    Loop
                    ' tanks: its own only after a bounce
                    j = 0
                    Do While j < tdNTanks And sh(k).alive <> 0
                        If tk(j).alive <> 0 And Not (j = sh(k).owner And sh(k).bounces <> 0) And Not (sh(k).owner <> 0 And j <> 0) Then
                            dx = sh(k).x - tk(j).x
                            dz = sh(k).z - tk(j).z
                            If Abs(dx) < rr And Abs(dz) < rr Then
                                If FHypot(dx, dz) < rr Then
                                    If tk(j).ttype = TK_BULWARK And Abs(ADiff(TdAngleTo(dx, dz), tk(j).yaw)) < SHIELD_ARC Then
                                        ' off the shield
                                        Ev TDE_GLANCE, j, 0, sh(k).x, sh(k).z
                                        If sh(k).bounces Then
                                            a = (2 * tk(j).yaw - TdAngleTo(-sh(k).dx, -sh(k).dz)) And &HFFFF&
                                            sh(k).bounces = sh(k).bounces - 1
                                            sh(k).dx = FMul(TD_SHELL_SPEED, A3Sin(a))
                                            sh(k).dz = FMul(TD_SHELL_SPEED, A3Cos(a))
                                            sh(k).x = tk(j).x + FMul((TD_TANK_R + 4) * 65536, A3Sin(a))
                                            sh(k).z = tk(j).z + FMul((TD_TANK_R + 4) * 65536, A3Cos(a))
                                            sh(k).owner = j
                                        Else
                                            sh(k).alive = 0
                                        End If
                                        Exit Do
                                    End If
                                    sh(k).alive = 0
                                    If sh(k).owner = 0 And j <> 0 Then tdHits = tdHits + 1
                                    Damage j, TD_SHELL_DMG, sh(k).x, sh(k).z
                                End If
                            End If
                        End If
                        j = j + 1
                    Loop
                    s = s + 1
                Loop
            End If
        End If
    Next k
End Sub

Private Sub Mortars()
    Dim k As Long, j As Long, d As Long
    For k = 0 To TD_MAX_MORTARS - 1
        If mo(k).alive Then
            mo(k).t = mo(k).t + 1
            If mo(k).t >= mo(k).flight Then
                mo(k).alive = 0
                Ev TDE_SPLASH, 2, k, mo(k).tx, mo(k).tz
                For j = 0 To tdNTanks - 1
                    If tk(j).alive Then
                        d = FHypot(tk(j).x - mo(k).tx, tk(j).z - mo(k).tz)
                        If d < TD_SPLASH_R * 65536 Then
                            If j = 0 Then
                                Damage 0, TD_SPLASH_DMG - ShrA(FMul(TD_SPLASH_DMG * 65536, FDiv(d, TD_SPLASH_R * 65536)), 16), mo(k).tx, mo(k).tz
                            ElseIf d < (TD_SPLASH_R \ 2) * 65536 Then
                                Damage j, 1, mo(k).tx, mo(k).tz
                            End If
                        End If
                    End If
                Next j
            End If
        End If
    Next k
End Sub

' ---------- the enemies ----------
Private Sub Think(ByVal k As Long)
    Dim dx As Long, dz As Long, d As Long, speed As Long, toA As Long, want As Long
    dx = tk(0).x - tk(k).x
    dz = tk(0).z - tk(k).z
    d = FHypot(dx, dz)
    speed = vmax(tk(k).ttype)
    toA = TdAngleTo(dx, dz)
    want = toA
    tk(k).aiTimer = tk(k).aiTimer + 1
    If tk(k).reload > 0 Then tk(k).reload = tk(k).reload - 1
    Select Case tk(k).ttype
        Case TK_SCOUT
            If tk(k).aiTimer Mod 120 > 70 Then          ' turn in to snipe
                want = toA
                speed = FONE
                If Abs(ADiff(toA, tk(k).yaw)) < 700 And d < 900 * 65536 Then TdFire k
            ElseIf d > 420 * 65536 Then
                want = toA + tk(k).orbit * &H1000&
            ElseIf d < 260 * 65536 Then
                want = toA + tk(k).orbit * &H6000&
            Else
                want = toA + tk(k).orbit * &H4000&
            End If
            If tk(k).aiTimer Mod 400 = 399 Then tk(k).orbit = -tk(k).orbit
        Case TK_MORTAR
            If d < 450 * 65536 Then
                want = toA + &H8000&
            ElseIf d > 750 * 65536 Then
                want = toA
            Else
                speed = 0
            End If
            If tk(k).reload = 0 And d < 1100 * 65536 Then Lob k
        Case TK_BULWARK
            If d < 240 * 65536 Then speed = 0
            If Abs(ADiff(toA, tk(k).yaw)) < 600 And d < 900 * 65536 Then TdFire k
    End Select
    ' something in the way ahead: steer round it
    If speed > 0 Then
        If TdBlocked(tk(k).x + 70 * A3Sin(tk(k).yaw), tk(k).z + 70 * A3Cos(tk(k).yaw), TD_TANK_R) Then
            want = tk(k).yaw + tk(k).orbit * &H2000&
        End If
    End If
    Drive k, want And &HFFFF&, speed
End Sub

' ---------- the tick ----------
Public Sub TdTick(ByVal inp As Long)
    Dim k As Long, dir As Long, speed As Long, bonus As Long
    If tdOver <> 0 Or tdWon <> 0 Then Exit Sub
    tdTicks = tdTicks + 1
    If tdBetween > 0 Then
        tdBetween = tdBetween - 1
        If tdBetween = 0 Then
            If tdRound >= TD_ROUNDS Then
                tdWon = 1
                Ev TDE_WIN, tdScore, 0, 0, 0
                Exit Sub
            End If
            TdLoadRound tdRound + 1
            Ev TDE_ROUND, tdRound, 0, 0, 0
        End If
        Exit Sub
    End If
    ' the player
    dir = 0
    If inp And TD_IN_RIGHT Then dir = dir + 1
    If inp And TD_IN_LEFT Then dir = dir - 1
    If inp And TD_IN_UP Then
        speed = vmax(0)
    ElseIf inp And TD_IN_DOWN Then
        speed = (-vmax(0) * 3) \ 5
    Else
        speed = 0
    End If
    Drive 0, (tk(0).yaw + dir * turnRate(0)) And &HFFFF&, speed
    If tk(0).reload > 0 Then tk(0).reload = tk(0).reload - 1
    If inp And TD_IN_FIRE Then TdFire 0
    ' the enemies
    For k = 1 To tdNTanks - 1
        If tk(k).alive <> 0 And tk(k).held = 0 Then Think k
    Next k
    TanksApart
    For k = 0 To tdNTanks - 1
        If tk(k).alive Then PushOut k
    Next k
    Shells
    Mortars
    If tdOver = 0 And tdNTanks > 1 Then
        If TdEnemiesLeft() = 0 Then
            bonus = 500 * tdRound + tk(0).hp * 5
            tdScore = tdScore + bonus
            tdBetween = TD_BETWEEN
            ClearShots
            Ev TDE_ROUND_CLEAR, tdRound, bonus, 0, 0
        End If
    End If
End Sub

' ---------- the autopilot ----------
Public Function TdBot() As Long
    Dim e As Long, best As Long, dx As Long, dz As Long, d As Long, k As Long
    Dim want As Long, diff As Long, toA As Long, inp As Long, dd As Long
    Dim rel As Long, side As Long, lean As Long, tdx As Long, tdz As Long
    If tdOver <> 0 Or tdWon <> 0 Or tdBetween <> 0 Or tk(0).alive = 0 Then Exit Function
    e = -1
    For k = 1 To tdNTanks - 1
        If tk(k).alive Then
            dd = FHypot(tk(k).x - tk(0).x, tk(k).z - tk(0).z)
            If e < 0 Or dd < best Then
                e = k
                best = dd
            End If
        End If
    Next k
    If e < 0 Then Exit Function
    dx = tk(e).x - tk(0).x
    dz = tk(e).z - tk(0).z
    d = best
    toA = TdAngleTo(dx, dz)
    ' a bulwark: circle it at 320, the way it is already turning away from,
    ' until well off its shield; then stop, aim and fire
    If tk(e).ttype = TK_BULWARK Then
        rel = ADiff(TdAngleTo(-dx, -dz), tk(e).yaw)
        If rel >= 0 Then side = 1 Else side = -1
        If Abs(rel) < SHIELD_ARC + 2600 Then
            lean = ShrA(d - 320 * 65536, 16) * 40
            If lean > &H2000& Then lean = &H2000&
            If lean < -&H2000& Then lean = -&H2000&
            want = toA - side * (&H4000& - lean)
            inp = inp Or TD_IN_UP
        Else
            want = toA
        End If
    Else
        want = toA
        If d > 420 * 65536 Then
            inp = inp Or TD_IN_UP
        ElseIf d < 230 * 65536 Then
            inp = inp Or TD_IN_DOWN
        End If
    End If
    ' out of a mortar's ring
    For k = 0 To TD_MAX_MORTARS - 1
        If mo(k).alive Then
            If FHypot(tk(0).x - mo(k).tx, tk(0).z - mo(k).tz) < (TD_SPLASH_R + 40) * 65536 Then
                want = TdAngleTo(tk(0).x - mo(k).tx, tk(0).z - mo(k).tz)
                inp = (inp And Not TD_IN_DOWN) Or TD_IN_UP
            End If
        End If
    Next k
    ' something in the way
    If inp And TD_IN_UP Then
        If TdBlocked(tk(0).x + 60 * A3Sin(tk(0).yaw), tk(0).z + 60 * A3Cos(tk(0).yaw), TD_TANK_R) Then
            want = tk(0).yaw + &H3000&
        End If
    End If
    diff = ADiff(want, tk(0).yaw)
    If diff > 250 Then inp = inp Or TD_IN_RIGHT
    If diff < -250 Then inp = inp Or TD_IN_LEFT
    ' shoot when lined up on an enemy and not at its shield
    For k = 1 To tdNTanks - 1
        If tk(k).alive Then
            tdx = tk(k).x - tk(0).x
            tdz = tk(k).z - tk(0).z
            If Abs(ADiff(TdAngleTo(tdx, tdz), tk(0).yaw)) <= 450 Then
                If FHypot(tdx, tdz) <= 1000 * 65536 Then
                    If Not (tk(k).ttype = TK_BULWARK And Abs(ADiff(TdAngleTo(-tdx, -tdz), tk(k).yaw)) < SHIELD_ARC) Then
                        If tk(0).reload = 0 Then inp = inp Or TD_IN_FIRE
                    End If
                End If
            End If
        End If
    Next k
    TdBot = inp
End Function

Public Function TdStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To tdNTanks - 1
        h = Fnv(h, tk(i).alive)
        h = Fnv(h, tk(i).hp)
        h = Fnv(h, tk(i).x)
        h = Fnv(h, tk(i).z)
        h = Fnv(h, tk(i).yaw)
        h = Fnv(h, tk(i).v)
    Next i
    For i = 0 To tdNObs - 1
        h = Fnv(h, ob(i).hp + ob(i).x)
    Next i
    h = Fnv(h, tdScore): h = Fnv(h, tdRound): h = Fnv(h, tdTicks): h = Fnv(h, tdKills)
    h = Fnv(h, tdShots): h = Fnv(h, tdHits): h = Fnv(h, tdDamage): h = Fnv(h, tdOver)
    h = Fnv(h, tdWon)
    TdStateHash = h
End Function

' a whole fight by the autopilot: ticks played (stops when it ends)
Public Function TdFight(ByVal seed As Long, ByVal rnd As Long, ByVal maxTicks As Long) As Long
    Dim t As Long
    TdNewGame seed, rnd
    Do While t < maxTicks And tdOver = 0 And tdWon = 0
        TdTick TdBot()
        tdNEv = 0
        t = t + 1
    Loop
    TdFight = t
End Function
