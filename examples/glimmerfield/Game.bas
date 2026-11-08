' Glimmerfield - game logic (no drawing, no OS calls)
'
' You fly a skiff through a wrapping field of drifting glimmer crystals.
' A shot cracks a big crystal into three smaller ones and a middle one
' into two; the smallest shards shatter, but a shard you leave alone
' slowly grows back into a crystal.
' From wave 2, wisps hunt you down. Hits in quick succession build a
' combo multiplier (up to x5).
'
' Everything that decides the game is integer maths (positions are 8-bit
' fixed point, angles are 0..255) driven by our own Park-Miller random
' generator, so a run with a given seed is identical under the VM and
' native builds. Particles use Single maths; they only count for the
' checksum through their (integer) lifetimes.
Option Explicit

Public Const ARENA_W As Long = 400
Public Const ARENA_H As Long = 300
Public Const FP As Long = 256
Public Const AW As Long = 102400          ' ARENA_W * FP
Public Const AH As Long = 76800           ' ARENA_H * FP

Public Const MAX_SHARDS As Long = 96
Public Const MAX_BULLETS As Long = 32
Public Const MAX_WISPS As Long = 16
Public Const MAX_PARTS As Long = 512
Public Const MAX_POPS As Long = 12

Public Const ST_PLAY As Long = 1
Public Const ST_GAMEOVER As Long = 2

' sound events of the last step (a bit set the front end plays)
Public Const SFX_SHOOT As Long = 1
Public Const SFX_CRACK As Long = 2
Public Const SFX_SHATTER As Long = 4
Public Const SFX_WISP As Long = 8
Public Const SFX_DIE As Long = 16
Public Const SFX_WAVE As Long = 32
Public Const SFX_LIFE As Long = 64
Public Const SFX_REGROW As Long = 128

' particle colours (indexes into the front end's palette)
Public Const COL_SPARK As Long = 1
Public Const COL_FLAME As Long = 2
Public Const COL_WISP As Long = 3
Public Const COL_SHIP As Long = 4
Public Const COL_HUE0 As Long = 8         ' + crystal hue 0..3

Public Type ShipT
    x As Long
    y As Long
    vx As Long
    vy As Long
    ang As Long
    cool As Long
    shield As Long
    alive As Boolean
    respawn As Long
    thrust As Boolean
End Type

Public Type ShardT
    active As Boolean
    x As Long
    y As Long
    vx As Long
    vy As Long
    size As Long
    ang As Long
    spin As Long
    grow As Long
    hue As Long
End Type

Public Type BulletT
    active As Boolean
    x As Long
    y As Long
    vx As Long
    vy As Long
    life As Long
End Type

Public Type WispT
    active As Boolean
    x As Long
    y As Long
    vx As Long
    vy As Long
    hp As Long
    phase As Long
End Type

Public Type PartT
    life As Long
    x As Single
    y As Single
    vx As Single
    vy As Single
    col As Long
End Type

Public Type PopT
    life As Long
    x As Long
    y As Long
    msg As String
End Type

Public ship As ShipT
Public shards(0 To 95) As ShardT
Public bullets(0 To 31) As BulletT
Public wisps(0 To 15) As WispT
Public parts(0 To 511) As PartT
Public pops(0 To 11) As PopT

Public sinT(0 To 255) As Long

Public state As Long
Public score As Long
Public lives As Long
Public wave As Long
Public frame As Long
Public combo As Long
Public comboTimer As Long
Public nextLife As Long
Public waveTimer As Long
Public wispsLeft As Long
Public wispTimer As Long
Public overTimer As Long
Public sfx As Long

Public shardCount As Long
Public wispCount As Long
Public bulletCount As Long
Public partCount As Long

Public keyLeft As Boolean
Public keyRight As Boolean
Public keyThrust As Boolean
Public keyFire As Boolean
Public botMode As Boolean

Public rngSeed As Long
Private partNext As Long
Private tablesReady As Boolean

' ---------------------------------------------------------------- maths

Public Sub InitTables()
    Dim i As Long
    If tablesReady Then Exit Sub
    For i = 0 To 255
        sinT(i) = CLng(Sin(i * 6.28318530717959 / 256#) * 256#)
    Next i
    tablesReady = True
End Sub

Public Function SinA(ByVal a As Long) As Long
    SinA = sinT(a And 255)
End Function

Public Function CosA(ByVal a As Long) As Long
    CosA = sinT((a + 64) And 255)
End Function

Public Sub SeedRng(ByVal s As Long)
    If s < 0 Then s = -s
    rngSeed = (s Mod 2147483646) + 1
End Sub

' Park-Miller minimal standard with Schrage's method: never overflows a Long
Public Function RandL(ByVal n As Long) As Long
    Dim hi As Long, lo As Long
    hi = rngSeed \ 127773
    lo = rngSeed Mod 127773
    rngSeed = 16807 * lo - 2836 * hi
    If rngSeed <= 0 Then rngSeed = rngSeed + 2147483647
    RandL = rngSeed Mod n
End Function

' angle 0..255 of the vector (dx, dy); 0 = right, 64 = down
Public Function AngleTo(ByVal dx As Long, ByVal dy As Long) As Long
    Dim ax As Long, ay As Long, t As Long, a As Long
    ax = Abs(dx)
    ay = Abs(dy)
    If ax = 0 And ay = 0 Then
        AngleTo = 0
        Exit Function
    End If
    If ax >= ay Then
        t = (ay * 256) \ ax
        a = (t * (8192 + 9 * (256 - t))) \ 65536
    Else
        t = (ax * 256) \ ay
        a = 64 - (t * (8192 + 9 * (256 - t))) \ 65536
    End If
    If dx < 0 Then a = 128 - a
    If dy < 0 Then a = 256 - a
    AngleTo = a And 255
End Function

' signed difference b - a in -128..127
Public Function AngleDiff(ByVal a As Long, ByVal b As Long) As Long
    Dim d As Long
    d = (b - a) And 255
    If d >= 128 Then d = d - 256
    AngleDiff = d
End Function

Private Function WrapL(ByVal v As Long, ByVal lim As Long) As Long
    If v < 0 Then
        v = v + lim
    ElseIf v >= lim Then
        v = v - lim
    End If
    WrapL = v
End Function

' shortest distance on the wrapping field, in pixels
Public Function DeltaPx(ByVal a As Long, ByVal b As Long, ByVal limPx As Long) As Long
    Dim d As Long
    d = (a - b) \ FP
    If d > limPx \ 2 Then
        d = d - limPx
    ElseIf d < -(limPx \ 2) Then
        d = d + limPx
    End If
    DeltaPx = d
End Function

Public Function ShardRadius(ByVal size As Long) As Long
    Select Case size
        Case 3
            ShardRadius = 18
        Case 2
            ShardRadius = 11
        Case Else
            ShardRadius = 6
    End Select
End Function

' ---------------------------------------------------------------- spawning

Public Sub Burst(ByVal px As Single, ByVal py As Single, ByVal n As Long, _
                 ByVal col As Long, ByVal speed As Single)
    Dim k As Long, tries As Long, a As Long, sp As Single
    For k = 1 To n
        tries = 0
        Do While parts(partNext).life > 0 And tries < MAX_PARTS
            partNext = (partNext + 1) Mod MAX_PARTS
            tries = tries + 1
        Loop
        If tries >= MAX_PARTS Then Exit Sub
        a = RandL(256)
        sp = speed * (20 + RandL(100)) / 100!
        parts(partNext).x = px
        parts(partNext).y = py
        parts(partNext).vx = CosA(a) * sp / 256!
        parts(partNext).vy = SinA(a) * sp / 256!
        parts(partNext).life = 18 + RandL(24)
        parts(partNext).col = col
        partNext = (partNext + 1) Mod MAX_PARTS
    Next k
End Sub

Public Sub AddPop(ByVal x As Long, ByVal y As Long, ByVal msg As String)
    Dim i As Long, best As Long
    best = 0
    For i = 0 To MAX_POPS - 1
        If pops(i).life <= 0 Then
            best = i
            Exit For
        End If
        If pops(i).life < pops(best).life Then best = i
    Next i
    pops(best).life = 40
    pops(best).x = x
    pops(best).y = y
    pops(best).msg = msg
End Sub

Private Function SpawnShard(ByVal x As Long, ByVal y As Long, ByVal size As Long, _
                            ByVal dirAng As Long, ByVal hue As Long) As Long
    Dim i As Long, spd As Long
    For i = 0 To MAX_SHARDS - 1
        If Not shards(i).active Then
            spd = 60 + RandL(60) + (3 - size) * 50 + wave * 4
            shards(i).active = True
            shards(i).x = WrapL(x, AW)
            shards(i).y = WrapL(y, AH)
            shards(i).vx = CosA(dirAng) * spd \ 256
            shards(i).vy = SinA(dirAng) * spd \ 256
            shards(i).size = size
            shards(i).ang = RandL(256)
            shards(i).spin = RandL(7) - 3
            shards(i).grow = 0
            shards(i).hue = hue
            SpawnShard = i
            Exit Function
        End If
    Next i
    SpawnShard = -1
End Function

Private Sub SpawnWisp()
    Dim i As Long
    For i = 0 To MAX_WISPS - 1
        If Not wisps(i).active Then
            wisps(i).active = True
            If RandL(2) = 0 Then
                wisps(i).x = 0
                wisps(i).y = RandL(AH)
            Else
                wisps(i).x = RandL(AW)
                wisps(i).y = 0
            End If
            wisps(i).vx = 0
            wisps(i).vy = 0
            wisps(i).hp = 3
            wisps(i).phase = RandL(256)
            Burst wisps(i).x / FP, wisps(i).y / FP, 16, COL_WISP, 2!
            Exit Sub
        End If
    Next i
End Sub

Private Sub ResetShip()
    ship.x = AW \ 2
    ship.y = AH \ 2
    ship.vx = 0
    ship.vy = 0
    ship.ang = 192
    ship.cool = 0
    ship.shield = 120
    ship.alive = True
    ship.respawn = 0
    ship.thrust = False
End Sub

Private Sub StartWave(ByVal n As Long)
    Dim k As Long, big As Long, x As Long, y As Long
    wave = n
    big = 3 + 2 * n
    If big > 14 Then big = 14
    For k = 1 To big
        ' along the edges, away from the ship in the middle
        If RandL(2) = 0 Then
            x = RandL(AW)
            y = RandL(AH \ 5)
        Else
            x = RandL(AW \ 5)
            y = RandL(AH)
        End If
        SpawnShard x, y, 3, RandL(256), RandL(4)
    Next k
    wispsLeft = 2 * (n - 1)
    If wispsLeft > 10 Then wispsLeft = 10
    wispTimer = 200
    sfx = sfx Or SFX_WAVE
    AddPop ARENA_W \ 2 - 24, ARENA_H \ 2 - 30, "WAVE " & CStr(n)
End Sub

Public Sub NewGame(ByVal seed As Long)
    Dim i As Long
    InitTables
    SeedRng seed
    For i = 0 To MAX_SHARDS - 1
        shards(i).active = False
    Next i
    For i = 0 To MAX_BULLETS - 1
        bullets(i).active = False
    Next i
    For i = 0 To MAX_WISPS - 1
        wisps(i).active = False
    Next i
    For i = 0 To MAX_PARTS - 1
        parts(i).life = 0
    Next i
    For i = 0 To MAX_POPS - 1
        pops(i).life = 0
        pops(i).msg = ""
    Next i
    partNext = 0
    score = 0
    lives = 3
    frame = 0
    combo = 1
    comboTimer = 0
    nextLife = 25000
    waveTimer = 0
    overTimer = 0
    sfx = 0
    keyLeft = False
    keyRight = False
    keyThrust = False
    keyFire = False
    state = ST_PLAY
    ResetShip
    StartWave 1
End Sub

' ---------------------------------------------------------------- scoring

Private Sub AddScore(ByVal pts As Long, ByVal x As Long, ByVal y As Long)
    Dim gained As Long
    If comboTimer > 0 Then
        If combo < 5 Then combo = combo + 1
    Else
        combo = 1
    End If
    comboTimer = 30
    gained = pts * combo
    score = score + gained
    If combo > 1 Then
        AddPop x, y, "+" & CStr(gained) & " x" & CStr(combo)
    Else
        AddPop x, y, "+" & CStr(gained)
    End If
    If score >= nextLife Then
        lives = lives + 1
        nextLife = nextLife + 25000
        sfx = sfx Or SFX_LIFE
    End If
End Sub

' ---------------------------------------------------------------- the bot

' Deterministic autopilot for attract mode and --bench: aims at the nearest
' threat with lead, shoots when lined up, backs off from close crystals.
Public Sub BotThink()
    Dim i As Long, dx As Long, dy As Long, d2 As Long
    Dim best As Long, bestD As Long, isWisp As Boolean
    Dim tx As Long, ty As Long, tvx As Long, tvy As Long, lead As Long
    Dim want As Long, diff As Long, r As Long, dangerD As Long
    Dim fleeX As Long, fleeY As Long

    keyLeft = False
    keyRight = False
    keyThrust = False
    keyFire = False
    If Not ship.alive Then Exit Sub

    best = -1
    bestD = 2147483647
    dangerD = 2147483647
    For i = 0 To MAX_SHARDS - 1
        If shards(i).active Then
            dx = DeltaPx(shards(i).x, ship.x, ARENA_W)
            dy = DeltaPx(shards(i).y, ship.y, ARENA_H)
            d2 = dx * dx + dy * dy
            If d2 < bestD Then
                bestD = d2
                best = i
                isWisp = False
            End If
            r = ShardRadius(shards(i).size) + 26
            If d2 < r * r And d2 < dangerD Then
                dangerD = d2
                fleeX = -dx
                fleeY = -dy
            End If
        End If
    Next i
    For i = 0 To MAX_WISPS - 1
        If wisps(i).active Then
            dx = DeltaPx(wisps(i).x, ship.x, ARENA_W)
            dy = DeltaPx(wisps(i).y, ship.y, ARENA_H)
            d2 = (dx * dx + dy * dy) \ 2      ' wisps count as twice as close
            If d2 < bestD Then
                bestD = d2
                best = i
                isWisp = True
            End If
        End If
    Next i
    If best < 0 Then Exit Sub

    If isWisp Then
        tx = wisps(best).x
        ty = wisps(best).y
        tvx = wisps(best).vx
        tvy = wisps(best).vy
    Else
        tx = shards(best).x
        ty = shards(best).y
        tvx = shards(best).vx
        tvy = shards(best).vy
    End If
    dx = DeltaPx(tx, ship.x, ARENA_W)
    dy = DeltaPx(ty, ship.y, ARENA_H)
    lead = (Abs(dx) + Abs(dy)) \ 6
    dx = dx + ((tvx - ship.vx) * lead) \ FP
    dy = dy + ((tvy - ship.vy) * lead) \ FP

    If dangerD < 2147483647 And ship.shield = 0 Then
        ' turn away and burn
        want = AngleTo(fleeX, fleeY)
        diff = AngleDiff(ship.ang, want)
        If Abs(diff) < 40 Then keyThrust = True
    Else
        want = AngleTo(dx, dy)
        diff = AngleDiff(ship.ang, want)
        If Abs(diff) < 10 Then keyFire = True
        If bestD > 150 * 150 And Abs(diff) < 24 Then keyThrust = True
    End If
    If diff > 3 Then
        keyRight = True
    ElseIf diff < -3 Then
        keyLeft = True
    End If
End Sub

' ---------------------------------------------------------------- update

Private Sub UpdateShip()
    Dim i As Long
    If Not ship.alive Then
        If ship.respawn > 0 Then ship.respawn = ship.respawn - 1
        If ship.respawn = 0 And lives > 0 Then
            If CenterClear() Then ResetShip
        End If
        Exit Sub
    End If
    If keyLeft Then ship.ang = (ship.ang - 4) And 255
    If keyRight Then ship.ang = (ship.ang + 4) And 255
    ship.thrust = keyThrust
    If keyThrust Then
        ship.vx = ship.vx + CosA(ship.ang) * 20 \ 256
        ship.vy = ship.vy + SinA(ship.ang) * 20 \ 256
        Burst (ship.x - CosA(ship.ang) * 6) / FP, (ship.y - SinA(ship.ang) * 6) / FP, _
              3, COL_FLAME, 1.5!
    End If
    ship.vx = ship.vx - ship.vx \ 48
    ship.vy = ship.vy - ship.vy \ 48
    ship.x = WrapL(ship.x + ship.vx, AW)
    ship.y = WrapL(ship.y + ship.vy, AH)
    If ship.shield > 0 Then ship.shield = ship.shield - 1
    If ship.cool > 0 Then ship.cool = ship.cool - 1
    If keyFire And ship.cool = 0 Then
        For i = 0 To MAX_BULLETS - 1
            If Not bullets(i).active Then
                bullets(i).active = True
                bullets(i).x = WrapL(ship.x + CosA(ship.ang) * 9, AW)
                bullets(i).y = WrapL(ship.y + SinA(ship.ang) * 9, AH)
                bullets(i).vx = ship.vx + CosA(ship.ang) * 6
                bullets(i).vy = ship.vy + SinA(ship.ang) * 6
                bullets(i).life = 45
                ship.cool = 6
                sfx = sfx Or SFX_SHOOT
                Exit For
            End If
        Next i
    End If
End Sub

Private Function CenterClear() As Boolean
    Dim i As Long, dx As Long, dy As Long
    For i = 0 To MAX_SHARDS - 1
        If shards(i).active Then
            dx = DeltaPx(shards(i).x, AW \ 2, ARENA_W)
            dy = DeltaPx(shards(i).y, AH \ 2, ARENA_H)
            If dx * dx + dy * dy < 60 * 60 Then
                CenterClear = False
                Exit Function
            End If
        End If
    Next i
    For i = 0 To MAX_WISPS - 1
        If wisps(i).active Then
            dx = DeltaPx(wisps(i).x, AW \ 2, ARENA_W)
            dy = DeltaPx(wisps(i).y, AH \ 2, ARENA_H)
            If dx * dx + dy * dy < 90 * 90 Then
                CenterClear = False
                Exit Function
            End If
        End If
    Next i
    CenterClear = True
End Function

Private Sub UpdateBullets()
    Dim i As Long
    bulletCount = 0
    For i = 0 To MAX_BULLETS - 1
        If bullets(i).active Then
            bullets(i).x = WrapL(bullets(i).x + bullets(i).vx, AW)
            bullets(i).y = WrapL(bullets(i).y + bullets(i).vy, AH)
            bullets(i).life = bullets(i).life - 1
            If bullets(i).life <= 0 Then
                bullets(i).active = False
            Else
                bulletCount = bulletCount + 1
            End If
        End If
    Next i
End Sub

Private Sub UpdateShards()
    Dim i As Long
    shardCount = 0
    For i = 0 To MAX_SHARDS - 1
        If shards(i).active Then
            shards(i).x = WrapL(shards(i).x + shards(i).vx, AW)
            shards(i).y = WrapL(shards(i).y + shards(i).vy, AH)
            shards(i).ang = (shards(i).ang + shards(i).spin) And 255
            If shards(i).size < 3 Then
                ' a shard left alone grows back: 1 -> 2 after 16 s, 2 -> 3 after 26 s
                shards(i).grow = shards(i).grow + 1
                If shards(i).grow >= 500 * shards(i).size + 300 Then
                    shards(i).size = shards(i).size + 1
                    shards(i).grow = 0
                    sfx = sfx Or SFX_REGROW
                    Burst shards(i).x / FP, shards(i).y / FP, 12, COL_HUE0 + shards(i).hue, 1!
                End If
            ElseIf ((frame + shards(i).ang) And 7) = 0 Then
                ' big crystals glitter
                Burst shards(i).x / FP, shards(i).y / FP, 1, COL_HUE0 + shards(i).hue, 0.7!
            End If
            shardCount = shardCount + 1
        End If
    Next i
End Sub

Private Sub UpdateWisps()
    Dim i As Long, dx As Long, dy As Long, maxV As Long, acc As Long
    wispCount = 0
    maxV = 420 + wave * 12
    If maxV > 700 Then maxV = 700
    For i = 0 To MAX_WISPS - 1
        If wisps(i).active Then
            If ship.alive Then
                dx = DeltaPx(ship.x, wisps(i).x, ARENA_W)
                dy = DeltaPx(ship.y, wisps(i).y, ARENA_H)
            Else
                dx = DeltaPx(AW \ 4, wisps(i).x, ARENA_W)
                dy = DeltaPx(AH \ 4, wisps(i).y, ARENA_H)
            End If
            acc = 7
            wisps(i).vx = wisps(i).vx + Sgn(dx) * acc
            wisps(i).vy = wisps(i).vy + Sgn(dy) * acc
            If wisps(i).vx > maxV Then wisps(i).vx = maxV
            If wisps(i).vx < -maxV Then wisps(i).vx = -maxV
            If wisps(i).vy > maxV Then wisps(i).vy = maxV
            If wisps(i).vy < -maxV Then wisps(i).vy = -maxV
            wisps(i).phase = (wisps(i).phase + 9) And 255
            ' weave across the direction of travel
            wisps(i).x = WrapL(wisps(i).x + wisps(i).vx + SinA(wisps(i).phase) * 3 \ 4, AW)
            wisps(i).y = WrapL(wisps(i).y + wisps(i).vy + CosA(wisps(i).phase) * 3 \ 4, AH)
            If (frame And 3) = 0 Then
                Burst wisps(i).x / FP, wisps(i).y / FP, 1, COL_WISP, 0.5!
            End If
            wispCount = wispCount + 1
        End If
    Next i
    If wispsLeft > 0 Then
        wispTimer = wispTimer - 1
        If wispTimer <= 0 Then
            SpawnWisp
            wispsLeft = wispsLeft - 1
            wispTimer = 180
        End If
    End If
End Sub

Private Sub UpdateParts()
    Dim i As Long
    partCount = 0
    For i = 0 To MAX_PARTS - 1
        If parts(i).life > 0 Then
            parts(i).x = parts(i).x + parts(i).vx
            parts(i).y = parts(i).y + parts(i).vy
            parts(i).vx = parts(i).vx * 0.94!
            parts(i).vy = parts(i).vy * 0.94!
            parts(i).life = parts(i).life - 1
            If parts(i).x < 0! Or parts(i).x >= ARENA_W Or parts(i).y < 0! Or parts(i).y >= ARENA_H Then
                parts(i).life = 0
            End If
            If parts(i).life > 0 Then partCount = partCount + 1
        End If
    Next i
End Sub

Private Sub UpdatePops()
    Dim i As Long
    For i = 0 To MAX_POPS - 1
        If pops(i).life > 0 Then
            pops(i).life = pops(i).life - 1
            If (pops(i).life And 1) = 0 Then pops(i).y = pops(i).y - 1
        End If
    Next i
End Sub

' ---------------------------------------------------------------- collisions

Private Sub CrackShard(ByVal i As Long, ByVal hitAng As Long)
    Dim sz As Long, x As Long, y As Long, h As Long, pts As Long
    sz = shards(i).size
    x = shards(i).x
    y = shards(i).y
    h = shards(i).hue
    shards(i).active = False
    Select Case sz
        Case 3
            pts = 10
        Case 2
            pts = 25
        Case Else
            pts = 50
    End Select
    AddScore pts, x \ FP, y \ FP
    Burst x / FP, y / FP, 10 + sz * 10, COL_HUE0 + h, 1! + sz
    If sz = 3 Then SpawnShard x, y, 2, hitAng + 112 + RandL(32), h
    If sz > 1 Then
        SpawnShard x, y, sz - 1, hitAng + 40 + RandL(24), h
        SpawnShard x, y, sz - 1, hitAng - 40 - RandL(24), h
        sfx = sfx Or SFX_CRACK
    Else
        sfx = sfx Or SFX_SHATTER
    End If
End Sub

Private Sub KillShip()
    ship.alive = False
    ship.respawn = 90
    ship.thrust = False
    lives = lives - 1
    combo = 1
    comboTimer = 0
    sfx = sfx Or SFX_DIE
    Burst ship.x / FP, ship.y / FP, 60, COL_SHIP, 3!
    Burst ship.x / FP, ship.y / FP, 30, COL_FLAME, 2!
    If lives <= 0 Then
        state = ST_GAMEOVER
        overTimer = 200
    End If
End Sub

Private Sub Collide()
    Dim b As Long, s As Long, w As Long, dx As Long, dy As Long, r As Long

    ' bullets against crystals and wisps
    For b = 0 To MAX_BULLETS - 1
        If bullets(b).active Then
            For s = 0 To MAX_SHARDS - 1
                If shards(s).active Then
                    dx = DeltaPx(bullets(b).x, shards(s).x, ARENA_W)
                    dy = DeltaPx(bullets(b).y, shards(s).y, ARENA_H)
                    r = ShardRadius(shards(s).size) + 1
                    If dx * dx + dy * dy <= r * r Then
                        bullets(b).active = False
                        CrackShard s, AngleTo(bullets(b).vx, bullets(b).vy)
                        Exit For
                    End If
                End If
            Next s
        End If
        If bullets(b).active Then
            For w = 0 To MAX_WISPS - 1
                If wisps(w).active Then
                    dx = DeltaPx(bullets(b).x, wisps(w).x, ARENA_W)
                    dy = DeltaPx(bullets(b).y, wisps(w).y, ARENA_H)
                    If dx * dx + dy * dy <= 64 Then
                        bullets(b).active = False
                        wisps(w).hp = wisps(w).hp - 1
                        wisps(w).vx = wisps(w).vx + bullets(b).vx \ 4
                        wisps(w).vy = wisps(w).vy + bullets(b).vy \ 4
                        If wisps(w).hp <= 0 Then
                            wisps(w).active = False
                            AddScore 150, wisps(w).x \ FP, wisps(w).y \ FP
                            Burst wisps(w).x / FP, wisps(w).y / FP, 40, COL_WISP, 2.5!
                            sfx = sfx Or SFX_WISP
                        Else
                            Burst wisps(w).x / FP, wisps(w).y / FP, 6, COL_WISP, 1.5!
                        End If
                        Exit For
                    End If
                End If
            Next w
        End If
    Next b

    ' the ship against crystals and wisps
    If ship.alive And ship.shield = 0 Then
        For s = 0 To MAX_SHARDS - 1
            If shards(s).active Then
                dx = DeltaPx(ship.x, shards(s).x, ARENA_W)
                dy = DeltaPx(ship.y, shards(s).y, ARENA_H)
                r = ShardRadius(shards(s).size) + 6
                If dx * dx + dy * dy <= r * r Then
                    CrackShard s, ship.ang
                    KillShip
                    Exit Sub
                End If
            End If
        Next s
        For w = 0 To MAX_WISPS - 1
            If wisps(w).active Then
                dx = DeltaPx(ship.x, wisps(w).x, ARENA_W)
                dy = DeltaPx(ship.y, wisps(w).y, ARENA_H)
                If dx * dx + dy * dy <= 13 * 13 Then
                    wisps(w).active = False
                    KillShip
                    Exit Sub
                End If
            End If
        Next w
    End If
End Sub

Private Sub WaveLogic()
    If shardCount = 0 And wispCount = 0 And wispsLeft = 0 Then
        If waveTimer = 0 Then
            waveTimer = 120
            score = score + 500 * wave
            AddPop ARENA_W \ 2 - 40, ARENA_H \ 2 + 10, "CLEAR +" & CStr(500 * wave)
        Else
            waveTimer = waveTimer - 1
            If waveTimer = 0 Then StartWave wave + 1
        End If
    End If
End Sub

' One 1/50 s step of the game.
Public Sub GameStep()
    frame = frame + 1
    sfx = 0
    If comboTimer > 0 Then comboTimer = comboTimer - 1
    If state = ST_PLAY Then
        If botMode Then BotThink
        UpdateShip
    Else
        If overTimer > 0 Then overTimer = overTimer - 1
    End If
    UpdateBullets
    UpdateShards
    UpdateWisps
    If state = ST_PLAY Then
        Collide
        WaveLogic
    End If
    UpdateParts
    UpdatePops
End Sub

' ---------------------------------------------------------------- HUD

Public Function HudText() As String
    Dim t As String
    t = "SCORE " & Format$(score, "0000000") & "   WAVE " & CStr(wave) & "   LIVES " & CStr(lives)
    If combo > 1 Then t = t & "   COMBO x" & CStr(combo)
    HudText = t
End Function

' A hash of the whole game state, to check that the VM and native builds agree.
Public Function StateHash() As Long
    Dim h As Long, i As Long
    h = (score Mod 1000003)
    h = (h * 31 + ship.x \ 16) Mod 1000003
    h = (h * 31 + ship.y \ 16) Mod 1000003
    h = (h * 31 + ship.ang) Mod 1000003
    h = (h * 31 + lives * 7 + wave) Mod 1000003
    For i = 0 To MAX_SHARDS - 1
        If shards(i).active Then
            h = (h * 31 + shards(i).x \ 64 + shards(i).y \ 64 + shards(i).size) Mod 1000003
        End If
    Next i
    For i = 0 To MAX_WISPS - 1
        If wisps(i).active Then
            h = (h * 31 + wisps(i).x \ 64 + wisps(i).y \ 64) Mod 1000003
        End If
    Next i
    h = (h * 31 + partCount) Mod 1000003
    h = (h * 31 + (rngSeed Mod 65536)) Mod 1000003
    StateHash = h
End Function
