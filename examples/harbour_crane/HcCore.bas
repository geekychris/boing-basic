' Harbour Crane - the rules (a port of hc_core.c from amiga_mcp's examples/harbour_crane).
' A gantry crane loading a ship that rolls in the swell: the trolley runs along the gantry,
' the winch lets the hook up and down, and the load swings like a pendulum, pushed by the
' trolley's starts and stops and the wind. Land each container square in a deck slot and
' keep her level. 16.16 fixed point exactly as the C (A3Fix.bas): the same state hash.
Option Explicit

Public Const HC_SLOTS As Long = 6
Public Const HC_TIERS As Long = 4
Public Const HC_MAXBOX As Long = 16
Public Const HC_LEVELS As Long = 8
Public Const HC_GANTRY_Y As Long = 320
Public Const HC_TX_MIN As Long = -220
Public Const HC_TX_MAX As Long = 430
Public Const HC_L_MIN As Long = 20
Public Const HC_L_MAX As Long = 330
Public Const HC_QUAY_X1 As Long = 40
Public Const HC_PICK_X As Long = -140
Public Const HC_WATER_Y As Long = -70
Public Const HC_SHIP_X0 As Long = 100
Public Const HC_SLOT_W As Long = 50
Public Const HC_DECK_Y As Long = -40
Public Const HC_PIVOT_X As Long = 250
Public Const HC_PIVOT_Y As Long = -60
Public Const HC_HULL_X0 As Long = 70
Public Const HC_HULL_X1 As Long = 430
Public Const HC_BOX_H As Long = 30
Public Const HC_SNAP As Long = 14
Public Const HC_DENT_FALL As Long = 45
Public Const HC_CAPSIZE As Long = 19660          ' FX(0.30)
Public Const HC_MAX_LOST As Long = 3
Public Const HC_BETWEEN As Long = 75

Public Const HC_IN_LEFT As Long = 1
Public Const HC_IN_RIGHT As Long = 2
Public Const HC_IN_UP As Long = 4
Public Const HC_IN_DOWN As Long = 8
Public Const HC_IN_FIRE As Long = 16

Public Const HCE_NONE As Long = 0
Public Const HCE_GRAB As Long = 1
Public Const HCE_RELEASE As Long = 2
Public Const HCE_LAND As Long = 3
Public Const HCE_DENT As Long = 4
Public Const HCE_LOST As Long = 5
Public Const HCE_BUMP As Long = 6
Public Const HCE_SPLASH As Long = 7
Public Const HCE_CLEAR As Long = 8
Public Const HCE_LEVEL As Long = 9
Public Const HCE_CAPSIZE As Long = 10
Public Const HCE_TIMEOUT As Long = 11
Public Const HCE_OVER As Long = 12
Public Const HCE_WIN As Long = 13
Public Const HCE_GUST As Long = 14
Public Const HC_MAX_EVENTS As Long = 16

Private Const G_PEND As Long = 91750            ' FX(1.4)
Private Const G_FALL As Long = 104857           ' FX(1.6)
Private Const TROLLEY_VMAX As Long = 327680     ' FX(5)
Private Const TH_MAX As Long = 78643            ' FX(1.2)
Private Const TWO_PI As Long = 411774           ' FX(6.2831853)
Private Const APROF As Long = 2621              ' FX(0.04)
Private Const KOFF As Long = 3932               ' FX(0.06)
Private Const SWELL_STEP As Long = 2745         ' FX(0.0418879)

Public Type HcBox
    blen As Long
    weight As Long
End Type

Public Type HcPlaced
    box As Long
    slot As Long
    tier As Long
End Type

Public Type HcEvent
    etype As Long
    a As Long
    b As Long
End Type

Public hcSeed As Long, hcRng As Long
Public hcLevel As Long, hcOver As Long, hcWon As Long, hcBetween As Long, hcCapsized As Long
Public hcTX As Long, hcTV As Long
Public hcL As Long, hcTh As Long, hcOm As Long
Public hcLdot As Long
Public hcCarrying As Long
Public hbox(0 To 15) As HcBox
Public hcNBox As Long, hcNext As Long
Public hcHeight(0 To 5) As Long
Public placed(0 To 15) As HcPlaced
Public hcNPlaced As Long
Public hcFalling As Long
Public hcFX As Long, hcFY As Long, hcFVX As Long, hcFVY As Long, hcFY0 As Long
Public hcPrevIn As Long
Public hcWind As Long, hcGust As Long
Public hcGustTimer As Long
Public hcSwell As Long, hcPhase As Long, hcList As Long, hcHeel As Long, hcBob As Long
Public hcLoaded As Long, hcLost As Long, hcDents As Long, hcBumps As Long, hcTotalLoaded As Long
Public hcScore As Long
Public hcTimeLeft As Long, hcTicks As Long
Public hcEv(0 To 15) As HcEvent
Public hcNEv As Long

Public Sub HcInit()
    A3FixInit
End Sub

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If hcNEv < HC_MAX_EVENTS Then
        hcEv(hcNEv).etype = etype
        hcEv(hcNEv).a = a
        hcEv(hcNEv).b = b
        hcNEv = hcNEv + 1
    End If
End Sub

' mulberry32
Public Function HcRand() As Long
    Dim t As Long
    hcRng = AddW(hcRng, &H6D2B79F5)
    t = hcRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    HcRand = t Xor ShrU(t, 14)
End Function

Public Function HcBoxW(ByVal b As Long) As Long
    HcBoxW = hbox(b).blen * HC_SLOT_W - 2
End Function

Public Function HcHookX() As Long
    HcHookX = hcTX + FMul(hcL, FSinR(hcTh))
End Function

Public Function HcHookY() As Long
    HcHookY = HC_GANTRY_Y * 65536 - FMul(hcL, FCosR(hcTh))
End Function

Public Function HcWeight() As Long
    Dim k As Long, w As Long
    For k = 0 To hcNPlaced - 1
        w = w + hbox(placed(k).box).weight
    Next k
    HcWeight = w
End Function

' weight x (distance of its middle from the deck's middle, in slots)
Public Function HcMoment(ByVal extraBox As Long, ByVal extraSlot As Long) As Long
    Dim k As Long, m As Long
    For k = 0 To hcNPlaced - 1
        m = m + (hbox(placed(k).box).weight * 65536 * (2 * placed(k).slot + hbox(placed(k).box).blen - HC_SLOTS)) \ 2
    Next k
    If extraBox >= 0 Then m = m + (hbox(extraBox).weight * 65536 * (2 * extraSlot + hbox(extraBox).blen - HC_SLOTS)) \ 2
    HcMoment = m
End Function

Public Function HcListFor(ByVal moment As Long, ByVal weight As Long) As Long
    HcListFor = FMul(moment, 655)              ' FX(0.010)
End Function

Public Function HcSlotTop(ByVal slot As Long) As Long
    HcSlotTop = HC_DECK_Y + hcHeight(slot) * HC_BOX_H
End Function

' a point on the ship (its own coordinates) to the world: rolled by heel, lifted by the swell
Public Function HcShipY(ByVal lx As Long, ByVal ly As Long) As Long
    HcShipY = ly - FMul(lx - HC_PIVOT_X * 65536, FSinR(hcHeel)) + hcBob
End Function

Private Function PickThere() As Boolean
    PickThere = hcCarrying < 0 And hcFalling < 0 And hcNext < hcNBox
End Function

Public Function HcSupportY(ByVal x0 As Long, ByVal x1 As Long, ByVal withPick As Boolean) As Long
    Dim top As Long, y As Long, s As Long, half As Long, a As Long, b As Long, s0 As Long, s1 As Long
    top = HC_WATER_Y * 65536
    If x0 < HC_QUAY_X1 * 65536 And top < 0 Then top = 0
    If withPick Then
        If PickThere() Then
            half = (HcBoxW(hcNext) * 65536) \ 2
            If x1 > HC_PICK_X * 65536 - half And x0 < HC_PICK_X * 65536 + half And top < HC_BOX_H * 65536 Then top = HC_BOX_H * 65536
        End If
    End If
    If x1 > HC_HULL_X0 * 65536 And x0 < HC_HULL_X1 * 65536 Then
        If x0 < HC_HULL_X0 * 65536 Then a = HC_HULL_X0 * 65536 Else a = x0
        If x1 > HC_HULL_X1 * 65536 Then b = HC_HULL_X1 * 65536 Else b = x1
        y = HcShipY(a, HC_DECK_Y * 65536)
        If y > top Then top = y
        y = HcShipY(b, HC_DECK_Y * 65536)
        If y > top Then top = y
    End If
    For s = 0 To HC_SLOTS - 1
        s0 = (HC_SHIP_X0 + s * HC_SLOT_W) * 65536
        s1 = s0 + HC_SLOT_W * 65536
        If Not (x1 <= s0 Or x0 >= s1 Or hcHeight(s) = 0) Then
            y = HcShipY(s0 + (HC_SLOT_W \ 2) * 65536, HcSlotTop(s) * 65536)
            If y > top Then top = y
        End If
    Next s
    HcSupportY = top
End Function

Public Function HcFits(ByVal b As Long, ByVal slot As Long) As Boolean
    Dim k As Long
    If slot < 0 Or slot + hbox(b).blen > HC_SLOTS Then Exit Function
    For k = 1 To hbox(b).blen - 1
        If hcHeight(slot + k) <> hcHeight(slot) Then Exit Function
    Next k
    HcFits = hcHeight(slot) < HC_TIERS
End Function

Public Sub HcLoadLevel(ByVal level As Long)
    Dim k As Long, r As Long
    hcLevel = level
    If 5 + level < 12 Then hcNBox = 5 + level Else hcNBox = 12
    For k = 0 To hcNBox - 1
        r = UModL(HcRand(), 100)
        If level >= 2 And r < 25 + level * 2 Then hbox(k).blen = 2 Else hbox(k).blen = 1
        r = UModL(HcRand(), 100)
        If r < 45 - level * 3 Then
            hbox(k).weight = 1
        ElseIf r < 85 - level * 3 Then
            hbox(k).weight = 2
        Else
            hbox(k).weight = 3
        End If
        If hbox(k).blen = 2 And hbox(k).weight < 4 Then          ' (the C's && draws no number otherwise)
            If HcRand() And 1 Then hbox(k).weight = hbox(k).weight + 1
        End If
    Next k
    For k = 0 To HC_SLOTS - 1
        hcHeight(k) = 0
    Next k
    hcNPlaced = 0
    hcNext = 0
    hcCarrying = -1: hcFalling = -1
    hcTX = HC_PICK_X * 65536
    hcTV = 0
    hcL = 140 * 65536
    hcTh = 0: hcOm = 0: hcLdot = 0
    If level >= 2 Then
        If level And 1 Then hcWind = -(level - 1) * 393 Else hcWind = (level - 1) * 393      ' FX(0.006)
    Else
        hcWind = 0
    End If
    hcGust = 0
    hcGustTimer = 100
    hcSwell = 1310 + (level - 1) * 720              ' FX(0.02) + n * FX(0.011)
    hcPhase = 0
    hcList = 0: hcHeel = 0: hcBob = 0
    hcLoaded = 0: hcLost = 0: hcDents = 0
    hcTimeLeft = (60 + 25 * hcNBox) * 25
End Sub

Public Sub HcNewGame(ByVal seed As Long, ByVal level As Long)
    Dim k As Long
    hcSeed = seed
    hcRng = seed
    hcOver = 0: hcWon = 0: hcBetween = 0: hcCapsized = 0
    hcFX = 0: hcFY = 0: hcFVX = 0: hcFVY = 0: hcFY0 = 0
    hcPrevIn = 0: hcBumps = 0: hcTotalLoaded = 0: hcScore = 0: hcTicks = 0
    hcNEv = 0
    For k = 0 To HC_MAXBOX - 1
        hbox(k).blen = 0: hbox(k).weight = 0
        placed(k).box = 0: placed(k).slot = 0: placed(k).tier = 0
    Next k
    If level < 1 Then level = 1
    If level > HC_LEVELS Then level = HC_LEVELS
    HcLoadLevel level
End Sub

Private Sub Lose(ByVal b As Long)
    hcLost = hcLost + 1
    hcScore = hcScore - 100
    Ev HCE_LOST, b, hcLost
    If hcLost >= HC_MAX_LOST Then
        hcOver = 1
        Ev HCE_OVER, hcScore, 0
    End If
End Sub

' the falling box reaches whatever is below it
Private Sub Land()
    Dim b As Long, ln As Long, s As Long, x0 As Long, x1 As Long, off As Long
    b = hcFalling
    ln = hbox(b).blen
    x0 = hcFX
    x1 = x0 + HcBoxW(b) * 65536
    hcFalling = -1
    If x1 <= HC_QUAY_X1 * 65536 Then          ' back on the quay: it waits there again
        hcNext = b
        If hcFY0 - hcFY > HC_DENT_FALL * 65536 Then
            hcDents = hcDents + 1
            hcScore = hcScore - 40
            Ev HCE_DENT, b, 0
        End If
        Ev HCE_LAND, -1, 0
        Exit Sub
    End If
    s = (x0 - HC_SHIP_X0 * 65536 + (HC_SLOT_W * 65536) \ 2) \ (HC_SLOT_W * 65536)
    If x0 < HC_SHIP_X0 * 65536 - (HC_SLOT_W * 65536) \ 2 Then s = -1
    off = x0 - (HC_SHIP_X0 + s * HC_SLOT_W) * 65536
    If Not HcFits(b, s) Or Abs(off) > HC_SNAP * 65536 Then
        Lose b
        Exit Sub
    End If
    placed(hcNPlaced).box = b
    placed(hcNPlaced).slot = s
    placed(hcNPlaced).tier = hcHeight(s)
    hcNPlaced = hcNPlaced + 1
    Do While ln > 0
        hcHeight(s + ln - 1) = hcHeight(s + ln - 1) + 1
        ln = ln - 1
    Loop
    hcLoaded = hcLoaded + 1
    hcTotalLoaded = hcTotalLoaded + 1
    If hcFY0 - hcFY > HC_DENT_FALL * 65536 Then
        hcDents = hcDents + 1
        hcScore = hcScore - 40
        Ev HCE_DENT, b, 0
    Else
        hcScore = hcScore + 50 * hbox(b).weight
    End If
    Ev HCE_LAND, s, placed(hcNPlaced - 1).tier
End Sub

Private Sub Ship()
    Dim k As Long, w As Long, tiers As Long, swell As Long
    w = HcWeight()
    hcPhase = hcPhase + SWELL_STEP
    If hcPhase >= TWO_PI Then hcPhase = hcPhase - TWO_PI
    hcList = HcListFor(HcMoment(-1, 0), w)
    For k = 0 To hcNPlaced - 1
        tiers = tiers + (hbox(placed(k).box).weight * 65536 * (2 * placed(k).tier + 1)) \ 2
    Next k
    If w Then tiers = tiers \ w                  ' the load's mean height, in tiers
    swell = FMul(hcSwell, FONE + tiers \ 2)
    hcHeel = hcList + FMul(swell, FSinR(hcPhase))
    hcBob = FMul((3 + hcLevel \ 2) * 65536, FSinR(hcPhase + 85196))     ' FX(1.3)
End Sub

Private Sub Swing(ByVal accel As Long)
    Dim k As Long, wind As Long, sn As Long, cs As Long, a As Long
    wind = hcWind + hcGust
    If hcCarrying < 0 Then wind = wind \ 4      ' the bare hook hardly catches it
    For k = 0 To 3
        sn = FSinR(hcTh)
        cs = FCosR(hcTh)
        a = -FDiv(FMul(G_PEND, sn) + FMul(accel - wind, cs) + 2 * FMul(hcLdot, hcOm), hcL)
        hcOm = hcOm + a \ 4
        hcOm = hcOm - hcOm \ 300
        hcTh = hcTh + hcOm \ 4
        If hcTh > TH_MAX Then
            hcTh = TH_MAX
            hcOm = 0
        End If
        If hcTh < -TH_MAX Then
            hcTh = -TH_MAX
            hcOm = 0
        End If
    Next k
End Sub

' the load (or the bare hook) can't go through what is under it
Private Sub Collide()
    Dim hx As Long, hy As Long, half As Long, bottom As Long, sup As Long, pen As Long, speed As Long
    hx = HcHookX()
    hy = HcHookY()
    If hcCarrying >= 0 Then
        half = (HcBoxW(hcCarrying) * 65536) \ 2
        bottom = hy - HC_BOX_H * 65536
    Else
        half = 4 * 65536
        bottom = hy - 4 * 65536
    End If
    sup = HcSupportY(hx - half, hx + half, True)
    If bottom >= sup Then Exit Sub
    pen = sup - bottom
    speed = Abs(FMul(hcOm, hcL)) + Abs(hcLdot)
    hcL = hcL - pen
    If hcL < HC_L_MIN * 65536 Then hcL = HC_L_MIN * 65536
    hcLdot = 0
    If sup <= HC_WATER_Y * 65536 Then
        If speed > 32768 Then Ev HCE_SPLASH, 0, 0
        hcOm = hcOm - hcOm \ 4
        Exit Sub
    End If
    If speed > 98304 Then
        hcBumps = hcBumps + 1
        Ev HCE_BUMP, ShrA(speed, 16), 0
        If hcCarrying >= 0 And speed > 229376 Then
            hcDents = hcDents + 1
            hcScore = hcScore - 20
            Ev HCE_DENT, hcCarrying, 1
        End If
    End If
    hcOm = (-hcOm) \ 2
End Sub

Private Sub Fire()
    Dim hx As Long, hy As Long, sv As Long
    hx = HcHookX()
    hy = HcHookY()
    If hcCarrying >= 0 Then
        sv = FMul(hcOm, hcL)
        hcFalling = hcCarrying
        hcCarrying = -1
        hcFX = hx - (HcBoxW(hcFalling) * 65536) \ 2
        hcFY = hy - HC_BOX_H * 65536
        hcFY0 = hcFY
        hcFVX = hcTV + FMul(sv, FCosR(hcTh))
        hcFVY = FMul(sv, FSinR(hcTh)) - FMul(hcLdot, FCosR(hcTh))
        Ev HCE_RELEASE, hcFalling, 0
        Exit Sub
    End If
    If Not PickThere() Then Exit Sub
    If Abs(hx - HC_PICK_X * 65536) < 12 * 65536 And hy - HC_BOX_H * 65536 < 8 * 65536 And Abs(FMul(hcOm, hcL)) < 98304 Then
        hcCarrying = hcNext
        hcNext = hcNext + 1
        Ev HCE_GRAB, hcCarrying, 0
    End If
End Sub

Public Sub HcTick(ByVal inp As Long)
    Dim w As Long, acc As Long, target As Long, prevV As Long, winch As Long, r As Long, sup As Long, b As Long, bonus As Long
    If hcOver <> 0 Or hcWon <> 0 Then Exit Sub
    hcTicks = hcTicks + 1
    If hcBetween > 0 Then
        hcBetween = hcBetween - 1
        If hcBetween = 0 Then
            If hcLevel >= HC_LEVELS Then
                hcWon = 1
                Ev HCE_WIN, hcScore, 0
                Exit Sub
            End If
            HcLoadLevel hcLevel + 1
            Ev HCE_LEVEL, hcLevel, 0
        End If
        Exit Sub
    End If
    Ship
    If Abs(hcHeel) > HC_CAPSIZE Then
        hcCapsized = 1
        hcOver = 1
        Ev HCE_CAPSIZE, ShrA(hcHeel, 10), 0
        Ev HCE_OVER, hcScore, 0
        Exit Sub
    End If
    hcTimeLeft = hcTimeLeft - 1
    If hcTimeLeft <= 0 Then
        hcOver = 1
        Ev HCE_TIMEOUT, 0, 0
        Ev HCE_OVER, hcScore, 0
        Exit Sub
    End If
    ' gusts from level 4
    If hcLevel >= 4 Then
        hcGustTimer = hcGustTimer - 1
        If hcGustTimer <= 0 Then
            r = UModL(HcRand(), 200)
            If hcGust Then hcGust = 0 Else hcGust = (r - 100) * 13 * hcLevel      ' FX(0.0002)
            hcGustTimer = 40 + UModL(HcRand(), 120)
            If hcGust Then Ev HCE_GUST, ShrA(hcGust, 8), 0
        End If
    End If
    ' the trolley: heavier loads start and stop more slowly
    If hcCarrying >= 0 Then w = hbox(hcCarrying).weight
    acc = 5242 - w * 524                           ' FX(0.08) - w * FX(0.008)
    If inp And HC_IN_RIGHT Then
        target = TROLLEY_VMAX
    ElseIf inp And HC_IN_LEFT Then
        target = -TROLLEY_VMAX
    End If
    prevV = hcTV
    If hcTV < target Then
        hcTV = hcTV + acc
        If hcTV > target Then hcTV = target
    ElseIf hcTV > target Then
        hcTV = hcTV - acc
        If hcTV < target Then hcTV = target
    End If
    hcTX = hcTX + hcTV
    If hcTX < HC_TX_MIN * 65536 Then
        hcTX = HC_TX_MIN * 65536
        hcTV = 0
    End If
    If hcTX > HC_TX_MAX * 65536 Then
        hcTX = HC_TX_MAX * 65536
        hcTV = 0
    End If
    ' the winch
    winch = 262144 - w * 32768
    If inp And HC_IN_UP Then
        hcLdot = -winch
    ElseIf inp And HC_IN_DOWN Then
        hcLdot = winch
    Else
        hcLdot = 0
    End If
    hcL = hcL + hcLdot
    If hcL < HC_L_MIN * 65536 Then
        hcL = HC_L_MIN * 65536
        hcLdot = 0
    End If
    If hcL > HC_L_MAX * 65536 Then
        hcL = HC_L_MAX * 65536
        hcLdot = 0
    End If
    Swing hcTV - prevV
    Collide
    If (inp And HC_IN_FIRE) <> 0 And (hcPrevIn And HC_IN_FIRE) = 0 Then Fire
    hcPrevIn = inp
    ' a box on its way down
    If hcFalling >= 0 Then
        hcFVY = hcFVY - G_FALL
        hcFX = hcFX + hcFVX
        hcFY = hcFY + hcFVY
        sup = HcSupportY(hcFX, hcFX + HcBoxW(hcFalling) * 65536, False)
        If hcFY <= sup Then
            hcFY = sup
            If sup <= HC_WATER_Y * 65536 Then
                b = hcFalling
                Ev HCE_SPLASH, 1, 0
                hcFalling = -1
                Lose b
            Else
                Land
            End If
        End If
    End If
    If hcOver = 0 And hcNext >= hcNBox And hcCarrying < 0 And hcFalling < 0 Then
        bonus = (hcTimeLeft \ 25) * 2
        If Abs(hcList) < 2621 Then bonus = bonus + 200        ' FX(0.04)
        hcScore = hcScore + bonus
        hcBetween = HC_BETWEEN
        Ev HCE_CLEAR, hcLevel, bonus
    End If
End Sub

' ---------- the autopilot ----------
Public Function HcBestSlot(ByVal b As Long) As Long
    Dim s As Long, best As Long, w As Long, cost As Long, bestCost As Long
    best = -1
    w = HcWeight() + hbox(b).weight
    For s = 0 To HC_SLOTS - 1
        If HcFits(b, s) Then
            cost = Abs(HcListFor(HcMoment(b, s), w)) * 8 + (hcHeight(s) * 65536) \ 10
            If best < 0 Or cost < bestCost Then
                best = s
                bestCost = cost
            End If
        End If
    Next s
    HcBestSlot = best
End Function

' the trolley's speed to aim for, err from the goal (see hc_core.c)
Private Function Approach(ByVal er As Long, ByVal off As Long) As Long
    Dim dist As Long, v As Long
    dist = Abs(er)
    v = FSqrt(2 * FMul(APROF, dist))            ' slowing down in time to stop there
    If v > TROLLEY_VMAX Then v = TROLLEY_VMAX
    If dist < 2 * 65536 Then
        v = 0
    ElseIf v < 19660 Then
        v = 19660                               ' creep the last few units
    End If
    If er < 0 Then v = -v
    Approach = v + FMul(off, KOFF)
End Function

Public Function HcBot() As Long
    Dim hx As Long, hy As Long, goal As Long, wantY As Long, vdes As Long, sv As Long, top As Long, half As Long, travel As Long
    Dim inp As Long, s As Long, nearG As Boolean, low As Boolean, b As Long, y As Long, sup As Long
    If hcOver <> 0 Or hcWon <> 0 Or hcBetween <> 0 Or hcFalling >= 0 Then Exit Function
    top = HC_BOX_H * 65536
    hx = HcHookX()
    hy = HcHookY()
    sv = FMul(hcOm, hcL)
    For s = 0 To HC_SLOTS - 1
        y = HcShipY((HC_SHIP_X0 + s * HC_SLOT_W + HC_SLOT_W \ 2) * 65536, HcSlotTop(s) * 65536)
        If y > top Then top = y
    Next s
    If hcCarrying < 0 Then
        If hcNext >= hcNBox Then Exit Function
        b = hcNext
        goal = HC_PICK_X * 65536
        half = 4 * 65536
        travel = top + 3 * HC_BOX_H * 65536
    Else
        b = hcCarrying
        s = HcBestSlot(b)
        If s < 0 Then s = 0
        half = (HcBoxW(b) * 65536) \ 2
        goal = (HC_SHIP_X0 + s * HC_SLOT_W) * 65536 + half + 65536
        travel = top + (2 * HC_BOX_H + 20) * 65536
    End If
    ' lowered once it is over the goal and still; it carries on down unless it drifts well off
    low = hy < travel - 15 * 65536
    If low Then
        nearG = Abs(hx - goal) < 9 * 65536 And Abs(sv) < 78643
    Else
        nearG = Abs(hx - goal) < 6 * 65536 And Abs(hcTX - goal) < 8 * 65536 And Abs(sv) < 52428
    End If
    If nearG Then
        sup = HcSupportY(hx - half, hx + half, hcCarrying < 0)
        If hcCarrying < 0 Then wantY = sup + 4 * 65536 Else wantY = sup + (HC_BOX_H + 4) * 65536
        If hy - wantY < 5 * 65536 And Abs(hx - goal) < 7 * 65536 And (hcPrevIn And HC_IN_FIRE) = 0 Then
            HcBot = HC_IN_FIRE
            Exit Function
        End If
    Else
        wantY = travel
    End If
    ' the winch
    If hy < wantY - 3 * 65536 Then
        inp = inp Or HC_IN_UP
    ElseIf hy > wantY + 3 * 65536 Then
        inp = inp Or HC_IN_DOWN
    End If
    ' the trolley, held still while the load is still low and off target
    If low And Not nearG And Abs(hx - goal) > 9 * 65536 Then
        vdes = FMul(hx - hcTX, KOFF)
    Else
        vdes = Approach(goal - hcTX, hx - hcTX)
    End If
    If hcTV < vdes - 2621 Then
        inp = inp Or HC_IN_RIGHT
    ElseIf hcTV > vdes + 2621 Then
        inp = inp Or HC_IN_LEFT
    End If
    HcBot = inp
End Function

Public Function HcStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To HC_SLOTS - 1
        h = Fnv(h, hcHeight(i))
    Next i
    h = Fnv(h, hcScore): h = Fnv(h, hcLevel): h = Fnv(h, hcTX): h = Fnv(h, hcTV): h = Fnv(h, hcL)
    h = Fnv(h, hcTh): h = Fnv(h, hcOm): h = Fnv(h, hcCarrying): h = Fnv(h, hcNext): h = Fnv(h, hcFalling)
    h = Fnv(h, hcFX): h = Fnv(h, hcFY): h = Fnv(h, hcHeel): h = Fnv(h, hcList): h = Fnv(h, hcLoaded)
    h = Fnv(h, hcLost): h = Fnv(h, hcDents): h = Fnv(h, hcBumps): h = Fnv(h, hcTicks): h = Fnv(h, hcOver)
    h = Fnv(h, hcWon): h = Fnv(h, hcTimeLeft): h = Fnv(h, hcTotalLoaded)
    HcStateHash = h
End Function
