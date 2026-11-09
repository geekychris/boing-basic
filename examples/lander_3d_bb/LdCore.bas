' Lander 3D - the simulation (a port of ld_core.c from amiga_mcp's examples/lander_3d,
' itself the browser game's lander-3d-core.js in 16.16 fixed point): seeded terrain
' (value-noise fBm, craters with raised rims, Mars's dunes, the asteroid's curvature),
' three pads flattened into it, the craft with its main engine and RCS, the wind,
' sub-stepped touchdown checks and the autopilot.
'
' Bit for bit as the C (the engine's integer maths are at the top of this module: examples/
' common/A3Fix.bas's names and results, integer-only), so a seed builds the
' same terrain and a flight gives the same state hash as the original
' (tools/trace.sh prints the C's numbers; tests/programs/lander_3d checks them).
'
' Metres, m/s and radians are 16.16 Longs. One step is 1/100 s (four a frame).
' The level being flown is the UDT `ld`; the terrain is in module arrays.
Option Explicit

Public Const LD_STEP_HZ As Long = 100
Public Const LD_DT As Long = 655                    ' FONE / 100
Public Const LD_MAX_N As Long = 97

Public Const W_MOON As Long = 0
Public Const W_MARS As Long = 1
Public Const W_ASTEROID As Long = 2
Public Const W_COUNT As Long = 3

Public Const OUT_NONE As Long = 0
Public Const OUT_LANDED As Long = 1
Public Const OUT_OFFPAD As Long = 2
Public Const OUT_CRASHED As Long = 3
Public Const OUT_LOST As Long = 4

Public Const LDE_NONE As Long = 0
Public Const LDE_LANDED As Long = 1
Public Const LDE_OFFPAD As Long = 2
Public Const LDE_CRASHED As Long = 3
Public Const LDE_LOST As Long = 4
Public Const LDE_FUEL_OUT As Long = 5

' the worlds (ld_worlds)
Public wName(0 To 2) As String
Public wG(0 To 2) As Long
Public wAmax(0 To 2) As Long
Public wSize(0 To 2) As Long
Public wN(0 To 2) As Long
Public wHills(0 To 2) As Long
Public wRough(0 To 2) As Long
Public wCraters(0 To 2) As Long
Public wCraterMax(0 To 2) As Long
Public wWind(0 To 2) As Long
Public wDrag(0 To 2) As Long
Public wCurve(0 To 2) As Long
Public wDunes(0 To 2) As Long
Public wLimVs(0 To 2) As Long
Public wLimHs(0 To 2) As Long
Public wLimTilt(0 To 2) As Long
Public wFuel(0 To 2) As Long
Public outcomeName(0 To 4) As String

' the terrain: heights row-major z then x, and the pads
Public tWorld As Long, tN As Long, tSize As Long
Public tCell As Long, tHalf As Long, tInvCell As Long
Public tH(0 To 9408) As Long
Public padX(0 To 2) As Long, padZ(0 To 2) As Long, padR(0 To 2) As Long
Public padY(0 To 2) As Long, padMult(0 To 2) As Long

' a level being flown (the C's Level without its terrain)
Public Type LdState
    world As Long
    lvl As Long
    seed As Long
    pFuel As Long                ' LevelParams
    pStartAlt As Long
    pStartH As Long
    pStartDist As Long
    pPadScale As Long
    pWind As Long
    px As Long                   ' the craft
    py As Long
    pz As Long
    vx As Long
    vy As Long
    vz As Long
    pitch As Long
    roll As Long
    wp As Long
    wr As Long
    thr As Long
    rcs0 As Long
    rcs1 As Long
    fuel As Long
    fuelMax As Long
    t As Long                    ' steps
    outcome As Long
    rVsOk As Long                ' LdResult
    rHsOk As Long
    rTiltOk As Long
    rPad As Long
    rVs As Long
    rHs As Long
    rTilt As Long
    rSlope As Long
    rScore As Long
    rSoft As Long
    rFuelBonus As Long
    windDir As Long
    windPh As Long
    wind0 As Long
    wind1 As Long
    assist As Long
    apDown As Long
    apTarget As Long
    probeUsed As Long
    probeOutcome As Long
    nev As Long
    ev(0 To 7) As Long
End Type

Public ld As LdState
' the controls for ld_step (LdInput): throttle 0..1, pitch and roll -1..1
Public inThr As Long, inPitch As Long, inRoll As Long

Private lattice(0 To 3, 0 To 1763) As Long
Private octCells(0 To 3) As Long
Private feetX(0 To 4) As Long, feetY(0 To 4) As Long, feetZ(0 To 4) As Long
Public footX(0 To 4) As Long, footY(0 To 4) As Long, footZ(0 To 4) As Long   ' LdFeet's result
Public upX As Long, upY As Long, upZ As Long                                ' LdUp's result
Private rotX As Long, rotY As Long, rotZ As Long
Private probeS As LdState
Private ldReady As Boolean

Private Const RATE As Long = 72089           ' FX(1.1)
Private Const ALPHA As Long = 157286         ' FX(2.4)
Private Const RCS_FUEL As Long = 3932        ' FX(0.06)
Private Const MAX_TILT As Long = 85786       ' FX(1.30900), 75 degrees
Private Const PROBE_FUEL As Long = 655360000 ' FROMI(10000)

' ---------- the amiga3d engine's integer maths (a3d_math.c, a3d_fix.c), here so the
' compiler inlines them into the simulation (it inlines small procedures of the same file;
' a real VM call is slow on the QEMU guest) ----------
Public Const FONE As Long = 65536

Public a3SinTab(0 To 256) As Long        ' 257: entry 256 = entry 0 (no wrap test)
Public a3AtanTab(0 To 128) As Long
Private fixReady As Boolean

Public Sub A3FixInit()
    Dim sinData As Variant, sinData2 As Variant, atanData As Variant, i As Long
    If fixReady Then Exit Sub
    sinData = Array( _
        0, 1608, 3216, 4821, 6424, 8022, 9616, 11204, 12785, 14359, 15924, 17479, 19024, 20557, 22078, 23586, _
        25080, 26558, 28020, 29466, 30893, 32303, 33692, 35062, 36410, 37736, 39040, 40320, 41576, 42806, 44011, 45190, _
        46341, 47464, 48559, 49624, 50660, 51665, 52639, 53581, 54491, 55368, 56212, 57022, 57798, 58538, 59244, 59914, _
        60547, 61145, 61705, 62228, 62714, 63162, 63572, 63944, 64277, 64571, 64827, 65043, 65220, 65358, 65457, 65516, _
        65536, 65516, 65457, 65358, 65220, 65043, 64827, 64571, 64277, 63944, 63572, 63162, 62714, 62228, 61705, 61145, _
        60547, 59914, 59244, 58538, 57798, 57022, 56212, 55368, 54491, 53581, 52639, 51665, 50660, 49624, 48559, 47464, _
        46341, 45190, 44011, 42806, 41576, 40320, 39040, 37736, 36410, 35062, 33692, 32303, 30893, 29466, 28020, 26558, _
        25080, 23586, 22078, 20557, 19024, 17479, 15924, 14359, 12785, 11204, 9616, 8022, 6424, 4821, 3216, 1608)
    sinData2 = Array( _
        0, -1608, -3216, -4821, -6424, -8022, -9616, -11204, -12785, -14359, -15924, -17479, -19024, -20557, -22078, -23586, _
        -25080, -26558, -28020, -29466, -30893, -32303, -33692, -35062, -36410, -37736, -39040, -40320, -41576, -42806, -44011, -45190, _
        -46341, -47464, -48559, -49624, -50660, -51665, -52639, -53581, -54491, -55368, -56212, -57022, -57798, -58538, -59244, -59914, _
        -60547, -61145, -61705, -62228, -62714, -63162, -63572, -63944, -64277, -64571, -64827, -65043, -65220, -65358, -65457, -65516, _
        -65536, -65516, -65457, -65358, -65220, -65043, -64827, -64571, -64277, -63944, -63572, -63162, -62714, -62228, -61705, -61145, _
        -60547, -59914, -59244, -58538, -57798, -57022, -56212, -55368, -54491, -53581, -52639, -51665, -50660, -49624, -48559, -47464, _
        -46341, -45190, -44011, -42806, -41576, -40320, -39040, -37736, -36410, -35062, -33692, -32303, -30893, -29466, -28020, -26558, _
        -25080, -23586, -22078, -20557, -19024, -17479, -15924, -14359, -12785, -11204, -9616, -8022, -6424, -4821, -3216, -1608)
    atanData = Array( _
        0, 81, 163, 244, 326, 407, 489, 570, 651, 732, 813, 894, 975, 1056, 1136, 1217, _
        1297, 1377, 1457, 1537, 1617, 1696, 1775, 1854, 1933, 2012, 2090, 2168, 2246, 2324, 2401, 2478, _
        2555, 2632, 2708, 2784, 2860, 2935, 3010, 3085, 3159, 3233, 3307, 3380, 3453, 3526, 3599, 3670, _
        3742, 3813, 3884, 3955, 4025, 4095, 4164, 4233, 4302, 4370, 4438, 4505, 4572, 4639, 4705, 4771, _
        4836, 4901, 4966, 5030, 5094, 5157, 5220, 5282, 5344, 5406, 5467, 5528, 5589, 5649, 5708, 5768, _
        5826, 5885, 5943, 6000, 6058, 6114, 6171, 6227, 6282, 6337, 6392, 6446, 6500, 6554, 6607, 6660, _
        6712, 6764, 6815, 6867, 6917, 6968, 7018, 7068, 7117, 7166, 7214, 7262, 7310, 7358, 7405, 7451, _
        7498, 7544, 7589, 7635, 7679, 7724, 7768, 7812, 7856, 7899, 7942, 7984, 8026, 8068, 8110, 8151, _
        8192)
    For i = 0 To 127
        a3SinTab(i) = sinData(i)
        a3SinTab(i + 128) = sinData2(i)
    Next i
    a3SinTab(256) = a3SinTab(0)
    For i = 0 To 128
        a3AtanTab(i) = atanData(i)
    Next i
    fixReady = True
End Sub

' ---------- 32-bit integer helpers ----------

' the uint32 value of a Long's bits, as a Double
Public Function UD(ByVal x As Long) As Double
    If x < 0 Then UD = x + 4294967296# Else UD = x
End Function

Public Function ShrU(ByVal x As Long, ByVal k As Long) As Long
    ShrU = ShrL(x, k)
End Function

Public Function ShlW(ByVal x As Long, ByVal k As Long) As Long
    ShlW = Shl(x, k)
End Function

Public Function AddW(ByVal a As Long, ByVal b As Long) As Long
    Dim lo As Long
    lo = (a And 65535) + (b And 65535)
    AddW = Shl(ShrL(a, 16) + ShrL(b, 16) + ShrL(lo, 16), 16) Or (lo And 65535)
End Function

' (x * y) mod 2^16 for 0 <= x, y < 2^16
Private Function M16(ByVal x As Long, ByVal y As Long) As Long
    M16 = (x * (y And 255) + (Shl(x * ShrL(y, 8), 8) And 65535)) And 65535
End Function

' low 32 bits of a * b (C's uint32 multiply)
Public Function MulW(ByVal a As Long, ByVal b As Long) As Long
    Dim al As Long, ah As Long, bl As Long, bh As Long, p2 As Long, t As Long
    al = a And 65535: ah = ShrL(a, 16)
    bl = b And 65535: bh = ShrL(b, 16)
    p2 = al * ShrL(bl, 8)
    t = al * (bl And 255) + Shl(p2 And 255, 8)
    MulW = Shl((ShrL(t, 16) + ShrL(p2, 8) + M16(ah, bl) + M16(al, bh)) And 65535, 16) Or (t And 65535)
End Function

Public Function UModL(ByVal x As Long, ByVal n As Long) As Long
    If x >= 0 Then
        UModL = x Mod n
    Else
        UModL = ((ShrL(x, 1) Mod n) * 2 + (x And 1)) Mod n
    End If
End Function

' (int16_t)(a - b): the short way round between two angles
Public Function ADiff(ByVal a As Long, ByVal b As Long) As Long
    Dim d As Long
    d = (a - b) And &HFFFF&
    If d >= 32768 Then d = d - 65536
    ADiff = d
End Function

' ---------- 16.16 fixed point ----------

' ((int64)a * b) >> 16
Public Function FMul(ByVal a As Long, ByVal b As Long) As Long
    FMul = MulShr(a, b, 16)
End Function

' ((int64)a << 16) / b, truncated
Public Function FDiv(ByVal a As Long, ByVal b As Long) As Long
    FDiv = MulDiv(a, 65536, b)
End Function

Public Function FromI(ByVal i As Long) As Long
    FromI = i * 65536
End Function

Public Function FInt(ByVal a As Long) As Long
    FInt = ShrA(a, 16)
End Function

' ---------- trig, square roots ----------

Public Function A3Sin(ByVal a As Long) As Long
    Dim i As Long, s0 As Long
    i = ShrL(a And &HFF00&, 8)
    s0 = a3SinTab(i)
    A3Sin = s0 + ShrA((a3SinTab(i + 1) - s0) * (a And 255), 8)
End Function

Public Function A3Cos(ByVal a As Long) As Long
    Dim i As Long, s0 As Long
    a = a + 16384
    i = ShrL(a And &HFF00&, 8)
    s0 = a3SinTab(i)
    A3Cos = s0 + ShrA((a3SinTab(i + 1) - s0) * (a And 255), 8)
End Function

Public Function A3AtanRatio(ByVal num As Long, ByVal den As Long) As Long
    Dim a As Long, t As Long, f As Long, r As Long
    If den <= 0 Then
        A3AtanRatio = 0
        Exit Function
    End If
    If num < 0 Then a = -num Else a = num
    If a > den Then a = den
    Do While den > &H7FFFF
        a = ShrL(a, 1)
        den = ShrL(den, 1)
    Loop
    t = (a * 2048) \ den
    f = t And 15
    t = ShrL(t, 4)
    r = a3AtanTab(t)
    If t < 128 Then r = r + ShrA((a3AtanTab(t + 1) - r) * f, 4)
    If num < 0 Then r = -r
    A3AtanRatio = r
End Function

' the angle of (x, y) from +y towards +x, 0..65535 (a yaw from dx, dz)
Public Function A3Atan2(ByVal x As Long, ByVal y As Long) As Long
    Dim ax As Long, ay As Long, a As Long
    If x < 0 Then ax = -x Else ax = x
    If y < 0 Then ay = -y Else ay = y
    If ax = 0 And ay = 0 Then
        A3Atan2 = 0
        Exit Function
    End If
    If ax <= ay Then a = A3AtanRatio(ax, ay) Else a = 16384 - A3AtanRatio(ay, ax)
    If y < 0 Then a = 32768 - a
    If x < 0 Then a = -a
    A3Atan2 = a And &HFFFF&
End Function

' floor(sqrt(v)) for 0 <= v < 2^52 (the C's bit-by-bit a3_isqrt gives the same)
Public Function ISqrtD(ByVal v As Double) As Long
    Dim r As Long, d As Double
    If v <= 0 Then
        ISqrtD = 0
        Exit Function
    End If
    r = Int(Sqr(v))
    d = r
    If d * d > v Then
        r = r - 1
    Else
        d = d + 1
        If d * d <= v Then r = r + 1
    End If
    ISqrtD = r
End Function

' a3_hypot / fhypot (the same code): scaled down until the squares fit 32 bits
Public Function FHypot(ByVal a As Long, ByVal b As Long) As Long
    Dim x As Long, y As Long, sh As Long, d As Double, e As Double
    If a < 0 Then x = -a Else x = a
    If b < 0 Then y = -b Else y = b
    Do While (x Or y) >= 46000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        sh = sh + 1
    Loop
    d = x
    e = y
    d = d * d + e * e
    x = Int(Sqr(d))                 ' (inline: calling ISqrtD with a Double costs ~25 us on the guest)
    e = x
    If e * e > d Then x = x - 1
    FHypot = Shl(x, sh)
End Function

Public Function FHypot3(ByVal a As Long, ByVal b As Long, ByVal c As Long) As Long
    Dim x As Long, y As Long, z As Long, sh As Long, d As Double, e As Double, f As Double
    If a < 0 Then x = -a Else x = a
    If b < 0 Then y = -b Else y = b
    If c < 0 Then z = -c Else z = c
    Do While (x Or y Or z) >= 37000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        z = ShrL(z, 1)
        sh = sh + 1
    Loop
    d = x
    e = y
    f = z
    d = d * d + e * e + f * f
    x = Int(Sqr(d))
    e = x
    If e * e > d Then x = x - 1
    FHypot3 = Shl(x, sh)
End Function

' fsqrt: sqrt of a 16.16 value
Public Function FSqrt(ByVal a As Long) As Long
    Dim v As Long, k As Long, r As Long, d As Double, e As Double
    If a <= 0 Then
        FSqrt = 0
        Exit Function
    End If
    v = a
    Do While v < 268435456 And k < 15
        v = v * 4
        k = k + 1
    Loop
    d = v
    r = Int(Sqr(d))
    e = r
    If e * e > d Then r = r - 1
    If k <= 8 Then FSqrt = Shl(r, 8 - k) Else FSqrt = ShrL(r, k - 8)
End Function

' radians (16.16) -> the engine's 16-bit angle: (rad * 683565276) >> 32, in 16-bit pieces
' (683565276 = 10430 * 65536 + 24796)
Public Function A3Angle(ByVal radf As Long) As Long
    Dim rh As Long, rl As Long
    rh = ShrA(radf, 16)
    rl = radf And 65535
    A3Angle = rh * 10430 + ShrA(rh * 24796 + rl * 10430 + ShrL(rl * 24796, 16), 16)
End Function

Public Function FSinR(ByVal radf As Long) As Long
    FSinR = A3Sin(A3Angle(radf))
End Function

Public Function FCosR(ByVal radf As Long) As Long
    FCosR = A3Cos(A3Angle(radf))
End Function

' fatan2: radians, -pi..pi, as Math.atan2(y, x)
Public Function FAtan2(ByVal y As Long, ByVal x As Long) As Long
    Dim ax As Long, ay As Long, t As Long
    If x < 0 Then ax = -x Else ax = x
    If y < 0 Then ay = -y Else ay = y
    If ax = 0 And ay = 0 Then
        FAtan2 = 0
        Exit Function
    End If
    If ay <= ax Then t = A3AtanRatio(ay, ax) Else t = 16384 - A3AtanRatio(ax, ay)
    If x < 0 Then t = 32768 - t
    If y < 0 Then t = -t
    FAtan2 = t * 6 + ShrA(t * 18559, 16)         ' (t * 411775) >> 16
End Function

' ---------- random numbers, hashes ----------

' a3_rand: a 15-bit LCG output; state is updated
Public Function A3Rand(state As Long) As Long
    state = AddW(MulW(state, 1103515245), 12345)
    A3Rand = ShrL(state, 16) And &H7FFF&
End Function

Public Function A3Hash(ByVal x As Long) As Long
    x = x Xor ShrL(x, 16)
    x = MulW(x, &H7FEB352D)
    x = x Xor ShrL(x, 15)
    x = MulW(x, &H846CA68B)
    x = x Xor ShrL(x, 16)
    A3Hash = x
End Function

' one FNV-1a step on a 32-bit word (h ^= v; h *= 16777619)
Public Function Fnv(ByVal h As Long, ByVal v As Long) As Long
    Fnv = MulW(h Xor v, 16777619)
End Function

Public Const FNV_START As Long = &H811C9DC5

' |x| without the Abs builtin (a slow call in the VM on the guest)
Public Function AbsL(ByVal x As Long) As Long
    If x < 0 Then AbsL = -x Else AbsL = x
End Function

' a Long's bits as 8 hex digits
Public Function Hex8(ByVal x As Long) As String
    Hex8 = Right$("0000000" & Hex$(x), 8)
End Function

Private Sub SetWorld(ByVal k As Long, ByVal nm As String, ByVal g As Long, ByVal amax As Long, ByVal size As Long, _
                     ByVal n As Long, ByVal hills As Long, ByVal rough As Long, ByVal craters As Long, ByVal cmax As Long, _
                     ByVal wind As Long, ByVal drag As Long, ByVal curve As Long, ByVal dunes As Long, ByVal vs As Long, _
                     ByVal hs As Long, ByVal tilt As Long, ByVal fuel As Long)
    wName(k) = nm: wG(k) = g: wAmax(k) = amax: wSize(k) = size: wN(k) = n
    wHills(k) = hills: wRough(k) = rough: wCraters(k) = craters: wCraterMax(k) = cmax
    wWind(k) = wind: wDrag(k) = drag: wCurve(k) = curve: wDunes(k) = dunes
    wLimVs(k) = vs: wLimHs(k) = hs: wLimTilt(k) = tilt: wFuel(k) = fuel
End Sub

Public Sub LdInit()
    If ldReady Then Exit Sub
    A3FixInit
    '            name        g       amax    size n   hills    rough  cr max wind    drag  curve     dunes   vs      hs      tilt   fuel
    SetWorld 0, "MOON", 106168, 288358, 1200, 97, 2490368, 32768, 34, 90, 0, 0, 0, 0, 163840, 98304, 11437, 4063232
    SetWorld 1, "MARS", 243138, 589824, 1200, 97, 3604480, 29491, 10, 110, 196608, 2621, 0, 589824, 196608, 117964, 11437, 4325376
    SetWorld 2, "ASTEROID", 22937, 98304, 640, 65, 1703936, 40632, 26, 55, 0, 0, 58982400, 0, 98304, 65536, 13725, 5570560
    outcomeName(0) = "flying": outcomeName(1) = "landed": outcomeName(2) = "offpad"
    outcomeName(3) = "crashed": outcomeName(4) = "lost"
    octCells(0) = 4: octCells(1) = 9: octCells(2) = 19: octCells(3) = 41
    ' the feet (body space) and the engine bell
    feetX(0) = 150732: feetY(0) = -131072: feetZ(0) = 150732
    feetX(1) = -150732: feetY(1) = -131072: feetZ(1) = 150732
    feetX(2) = 150732: feetY(2) = -131072: feetZ(2) = -150732
    feetX(3) = -150732: feetY(3) = -131072: feetZ(3) = -150732
    feetX(4) = 0: feetY(4) = -98304: feetZ(4) = 0
    ldReady = True
End Sub

' ---------- maths ----------

Private Function Clamp(ByVal v As Long, ByVal lo As Long, ByVal hi As Long) As Long
    If v < lo Then
        Clamp = lo
    ElseIf v > hi Then
        Clamp = hi
    Else
        Clamp = v
    End If
End Function

Private Function Smooth(ByVal t As Long) As Long
    Smooth = MulShr(MulShr(t, t, 16), 196608 - 2 * t, 16)
End Function

Public Function LdSin(ByVal radf As Long) As Long
    LdSin = A3Sin(A3Angle(radf))
End Function

Public Function LdCos(ByVal radf As Long) As Long
    LdCos = A3Cos(A3Angle(radf))
End Function

Public Function FAsin(ByVal x As Long) As Long
    FAsin = FAtan2(x, FSqrt(FONE - MulShr(x, x, 16)))
End Function

' e^-x for x >= 0
Public Function FExpNeg(ByVal x As Long) As Long
    Dim k As Long, y As Long, r As Long, yy As Long
    If x <= 0 Then
        FExpNeg = FONE
        Exit Function
    End If
    If x > 1310720 Then
        FExpNeg = 0
        Exit Function
    End If
    k = x \ 45426                     ' ln 2
    y = x - k * 45426
    yy = MulShr(y, y, 16)
    r = FONE - y + yy \ 2 - MulShr(yy, y, 16) \ 6
    FExpNeg = ShrA(r, k)
End Function

' mulberry32, as the browser's rng()
Public Function LdRng(a As Long) As Long
    Dim t As Long
    a = AddW(a, &H6D2B79F5)
    t = a
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    LdRng = t Xor ShrU(t, 14)
End Function

' [0, 1) as 16.16
Private Function Rf(a As Long) As Long
    Rf = ShrU(LdRng(a), 16)
End Function

' ---------- worlds and levels ----------

Public Sub LdLevelParams(ByVal world As Long, ByVal lv As Long)
    Dim k As Long, f As Long, f2 As Long, w As Long
    If lv < 1 Then lv = 1
    k = lv - 1
    If k > 8 Then k = 8
    f = wFuel(world) - 229376 * k
    f2 = MulShr(wFuel(world), 36044, 16)
    If f > f2 Then ld.pFuel = f Else ld.pFuel = f2
    If world = W_ASTEROID Then
        ld.pStartAlt = FromI(70) + FromI(8) * k
        ld.pStartH = 78643 + 32768 * k
        ld.pStartDist = FromI(110 + 18 * k)
    Else
        ld.pStartAlt = FromI(115) + FromI(8) * k
        ld.pStartH = 196608 + 104857 * k
        ld.pStartDist = FromI(180 + 28 * k)
    End If
    If FONE - 3276 * k < 40632 Then ld.pPadScale = 40632 Else ld.pPadScale = FONE - 3276 * k
    w = wWind(world)
    If w <> 0 Then
        If w + FONE * k > FromI(11) Then ld.pWind = FromI(11) Else ld.pWind = w + FONE * k
    Else
        ld.pWind = 0
    End If
End Sub

' ---------- terrain ----------

Private Function Noise(ByVal o As Long, ByVal u As Long, ByVal v As Long) As Long
    Dim cells As Long, w As Long, i As Long, j As Long, x As Long, y As Long
    Dim fx As Long, fy As Long, a As Long, b As Long, c As Long, d As Long
    cells = octCells(o)
    w = cells + 1
    x = u * cells
    y = v * cells
    i = FInt(x)
    If i > cells - 1 Then i = cells - 1
    j = FInt(y)
    If j > cells - 1 Then j = cells - 1
    fx = Smooth(x - FromI(i))
    fy = Smooth(y - FromI(j))
    a = lattice(o, j * w + i)
    b = lattice(o, j * w + i + 1)
    c = lattice(o, (j + 1) * w + i)
    d = lattice(o, (j + 1) * w + i + 1)
    Noise = a + MulShr(b - a, fx, 16) + MulShr(c - a, fy, 16) + MulShr(MulShr(a - b - c + d, fx, 16), fy, 16)
End Function

' the ground's height at (x, z), bilinear
Public Function LdHeight(ByVal x As Long, ByVal z As Long) As Long
    Dim fx As Long, fz As Long, i As Long, j As Long, tx As Long, tz As Long, k As Long, lim As Long
    Dim a As Long, b As Long, c As Long, d As Long
    lim = tN * 65536 - 65537                     ' FROMI(n - 1) - 1
    fx = MulShr(x + tHalf, tInvCell, 16)
    If fx < 0 Then
        fx = 0
    ElseIf fx > lim Then
        fx = lim
    End If
    fz = MulShr(z + tHalf, tInvCell, 16)
    If fz < 0 Then
        fz = 0
    ElseIf fz > lim Then
        fz = lim
    End If
    tx = fx And 65535
    tz = fz And 65535
    i = ShrL(fx, 16)
    j = ShrL(fz, 16)
    k = j * tN + i
    a = tH(k)
    b = tH(k + 1)
    c = tH(k + tN)
    d = tH(k + tN + 1)
    LdHeight = a + MulShr(b - a, tx, 16) + MulShr(c - a, tz, 16) + MulShr(MulShr(a - b - c + d, tx, 16), tz, 16)
End Function

' cos of the slope (1 = level)
Public Function LdSlopeCos(ByVal x As Long, ByVal z As Long) As Long
    Dim e As Long, dx As Long, dz As Long
    e = tCell \ 2
    dx = LdHeight(x + e, z) - LdHeight(x - e, z)
    dz = LdHeight(x, z + e) - LdHeight(x, z - e)
    LdSlopeCos = MulDiv(2 * e, 65536, FHypot3(dx, 2 * e, dz))
End Function

Private Function Roughness(ByVal x As Long, ByVal z As Long, ByVal radius As Long) As Long
    Dim lo As Long, hi As Long, a As Long, f As Long, r As Long, y As Long
    lo = &H7FFFFFFF
    hi = -&H7FFFFFFF
    For a = 0 To 11
        For f = 1 To 2
            r = radius * f \ 2
            y = LdHeight(x + MulShr(A3Cos(a * 65536 \ 12), r, 16), z + MulShr(A3Sin(a * 65536 \ 12), r, 16))
            If y < lo Then lo = y
            If y > hi Then hi = y
        Next f
    Next a
    Roughness = hi - lo
End Function

Private Sub Flatten(ByVal k As Long)
    Dim n As Long, i As Long, j As Long, cnt As Long, i0 As Long, i1 As Long, j0 As Long, j1 As Long
    Dim inner As Long, outer As Long, x As Long, z As Long, d As Long, t As Long, py As Long
    Dim sum As Double
    n = tN
    inner = padR(k) + MulShr(tCell, 98304, 16)
    outer = inner + MulShr(tCell, 163840, 16) + MulShr(padR(k), 39321, 16)
    i0 = FInt(MulDiv(padX(k) - outer + tHalf, 65536, tCell)) - 1
    i1 = FInt(MulDiv(padX(k) + outer + tHalf, 65536, tCell)) + 2
    j0 = FInt(MulDiv(padZ(k) - outer + tHalf, 65536, tCell)) - 1
    j1 = FInt(MulDiv(padZ(k) + outer + tHalf, 65536, tCell)) + 2
    If i0 < 0 Then i0 = 0
    If j0 < 0 Then j0 = 0
    If i1 > n - 1 Then i1 = n - 1
    If j1 > n - 1 Then j1 = n - 1
    For j = j0 To j1
        For i = i0 To i1
            x = -tHalf + tCell * i
            z = -tHalf + tCell * j
            If FHypot(x - padX(k), z - padZ(k)) <= inner Then
                sum = sum + tH(j * n + i)
                cnt = cnt + 1
            End If
        Next i
    Next j
    If cnt > 0 Then py = Fix(sum / cnt) Else py = LdHeight(padX(k), padZ(k))
    padY(k) = py
    For j = j0 To j1
        For i = i0 To i1
            x = -tHalf + tCell * i
            z = -tHalf + tCell * j
            d = FHypot(x - padX(k), z - padZ(k))
            If d <= inner Then
                tH(j * n + i) = py
            ElseIf d < outer Then
                t = Smooth(MulDiv(d - inner, 65536, outer - inner))
                tH(j * n + i) = py + MulShr(tH(j * n + i) - py, t, 16)
            End If
        Next i
    Next j
End Sub

Public Sub LdMakeTerrain(ByVal world As Long, ByVal seed As Long, ByVal padScale As Long)
    Dim r As Long, n As Long, i As Long, j As Long, o As Long, c As Long, k As Long, w As Long
    Dim amps(0 To 3) As Long, duneDir As Long, duneK As Long, cdd As Long, sdd As Long
    Dim u As Long, v As Long, y As Long, x As Long, z As Long, arg As Long, s As Long, d As Long
    Dim rr As Long, bigR As Long, cx As Long, cz As Long, depth As Long, rim As Long, reach As Long
    Dim i0 As Long, i1 As Long, j0 As Long, j1 As Long, dy As Long, q As Long, half As Long
    LdInit
    If seed <> 0 Then r = seed Else r = &H9E3779B9
    n = wN(world)
    tWorld = world
    tN = n
    tSize = wSize(world)
    tCell = MulDiv(FromI(tSize), 65536, FromI(n - 1))
    tInvCell = MulDiv(FONE, 65536, tCell)
    tHalf = FromI(tSize \ 2)
    For k = 0 To 9408
        tH(k) = 0
    Next k
    For o = 0 To 3
        w = octCells(o) + 1
        For k = 0 To w * w - 1
            lattice(o, k) = Rf(r) * 2 - FONE
        Next k
    Next o
    amps(0) = FONE
    amps(1) = wRough(world)
    amps(2) = MulShr(wRough(world), wRough(world), 16)
    amps(3) = MulShr(MulShr(amps(2), wRough(world), 16), 52428, 16)
    duneDir = MulShr(Rf(r), 205887, 16)
    duneK = 5882                                 ' FX(6.2831853 / 70)
    cdd = LdCos(duneDir)
    sdd = LdSin(duneDir)
    For j = 0 To n - 1
        For i = 0 To n - 1
            u = FromI(i) \ (n - 1)
            v = FromI(j) \ (n - 1)
            y = 0
            x = -tHalf + tCell * i
            z = -tHalf + tCell * j
            For o = 0 To 3
                y = y + MulShr(Noise(o, u, v), amps(o), 16)
            Next o
            y = MulShr(y, wHills(world), 16)
            If wDunes(world) <> 0 Then
                arg = MulShr(MulShr(x, cdd, 16) + MulShr(z, sdd, 16), duneK, 16) + 2 * Noise(1, u, v)
                s = AbsL(LdSin(arg))
                y = y + MulShr(wDunes(world), MulShr(s, FSqrt(s), 16), 16)
            End If
            If wCurve(world) <> 0 Then
                d = FHypot(x, z)
                y = y - MulShr(d, MulDiv(d, 65536, 2 * wCurve(world)), 16)
            End If
            tH(j * n + i) = y
        Next i
    Next j
    ' craters: a bowl with a raised rim
    For c = 0 To wCraters(world) - 1
        rr = Rf(r)
        bigR = FromI(10) + MulShr(MulShr(rr, rr, 16), FromI(wCraterMax(world)), 16)
        cx = MulShr(Rf(r) - 32768, MulShr(FromI(tSize), 62259, 16), 16)
        cz = MulShr(Rf(r) - 32768, MulShr(FromI(tSize), 62259, 16), 16)
        depth = MulShr(bigR, 11796 + MulShr(Rf(r), 7864, 16), 16)
        rim = MulShr(bigR, 3932 + MulShr(Rf(r), 3276, 16), 16)
        reach = MulShr(bigR, 104857, 16)
        i0 = FInt(MulDiv(cx - reach + tHalf, 65536, tCell))
        i1 = FInt(MulDiv(cx + reach + tHalf, 65536, tCell)) + 1
        j0 = FInt(MulDiv(cz - reach + tHalf, 65536, tCell))
        j1 = FInt(MulDiv(cz + reach + tHalf, 65536, tCell)) + 1
        If i0 < 0 Then i0 = 0
        If j0 < 0 Then j0 = 0
        If i1 > n - 1 Then i1 = n - 1
        If j1 > n - 1 Then j1 = n - 1
        For j = j0 To j1
            For i = i0 To i1
                x = -tHalf + tCell * i
                z = -tHalf + tCell * j
                d = MulDiv(FHypot(x - cx, z - cz), 65536, bigR)
                dy = 0
                If d < FONE Then dy = dy - MulShr(depth, FONE - MulShr(d, d, 16), 16)
                q = MulDiv(d - FONE, 65536, 14417)
                dy = dy + MulShr(rim, FExpNeg(MulShr(q, q, 16)), 16)
                tH(j * n + i) = tH(j * n + i) + dy
            Next i
        Next j
    Next c
    ' pads: the x1 on the smoothest ground, the x5 on the roughest that is still
    ' well apart from the others
    Dim candX(0 To 79) As Long, candZ(0 To 79) As Long, candR(0 To 79) As Long
    Dim chosen(0 To 2) As Long, m As Long, a As Long, b As Long, pick As Long, idx As Long, ok As Boolean
    Dim margin As Long, span As Long, minSep As Long, tx As Long, tz As Long, tr As Long
    margin = MulShr(FromI(tSize), 7864, 16)
    span = tHalf - margin
    minSep = MulShr(FromI(tSize), 17039, 16)
    For k = 0 To 79
        candX(k) = MulShr(Rf(r) * 2 - FONE, span, 16)
        candZ(k) = MulShr(Rf(r) * 2 - FONE, span, 16)
        candR(k) = Roughness(candX(k), candZ(k), FromI(30))
    Next k
    For a = 1 To 79                               ' sort by roughness (insertion, stable)
        b = a
        Do While b > 0
            If candR(b - 1) <= candR(b) Then Exit Do
            tx = candX(b): tz = candZ(b): tr = candR(b)
            candX(b) = candX(b - 1): candZ(b) = candZ(b - 1): candR(b) = candR(b - 1)
            candX(b - 1) = tx: candZ(b - 1) = tz: candR(b - 1) = tr
            b = b - 1
        Loop
    Next a
    For m = 0 To 2
        pick = -1
        For k = 0 To 79
            If m = 0 Then
                idx = k
            ElseIf m = 1 Then
                idx = 79 - k
            Else
                idx = 26 + k
            End If
            If idx >= 80 Then Exit For
            ok = True
            For q = 0 To m - 1
                If FHypot(candX(chosen(q)) - candX(idx), candZ(chosen(q)) - candZ(idx)) <= minSep Then ok = False
            Next q
            If ok Then
                pick = idx
                Exit For
            End If
        Next k
        If pick < 0 Then
            If m = 0 Then
                pick = m
            ElseIf m = 1 Then
                pick = 79 - m
            Else
                pick = 26 + m
            End If
        End If
        chosen(m) = pick
    Next m
    For m = 0 To 2
        padX(m) = candX(chosen(m))
        padZ(m) = candZ(chosen(m))
        Select Case m
            Case 0: padR(m) = MulShr(1114112, padScale, 16): padMult(m) = 1
            Case 1: padR(m) = MulShr(786432, padScale, 16): padMult(m) = 2
            Case 2: padR(m) = MulShr(557056, padScale, 16): padMult(m) = 5
        End Select
        Flatten m
    Next m
End Sub

' ---------- the craft ----------

' a body vector rotated by pitch (about x) after roll (about z), with the cosines
' and sines given -> rotX, rotY, rotZ
Private Sub RotCS(ByVal cr As Long, ByVal sr As Long, ByVal cp As Long, ByVal sp As Long, _
                  ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Dim x1 As Long, y1 As Long
    x1 = MulShr(x, cr, 16) - MulShr(y, sr, 16)
    y1 = MulShr(x, sr, 16) + MulShr(y, cr, 16)
    rotX = x1
    rotY = MulShr(y1, cp, 16) - MulShr(z, sp, 16)
    rotZ = MulShr(y1, sp, 16) + MulShr(z, cp, 16)
End Sub

' the craft's up direction -> upX, upY, upZ
Public Sub LdUp()
    RotCS LdCos(ld.roll), LdSin(ld.roll), LdCos(ld.pitch), LdSin(ld.pitch), 0, FONE, 0
    upX = rotX: upY = rotY: upZ = rotZ
End Sub

' radians from vertical
Public Function LdTilt() As Long
    LdUp
    LdTilt = FAtan2(FHypot(upX, upZ), upY)
End Function

' the four feet and the engine bell, world space -> footX/Y/Z(0..4)
Public Sub LdFeet()
    Dim cr As Long, sr As Long, cp As Long, sp As Long, k As Long
    cr = LdCos(ld.roll): sr = LdSin(ld.roll): cp = LdCos(ld.pitch): sp = LdSin(ld.pitch)
    For k = 0 To 4
        RotCS cr, sr, cp, sp, feetX(k), feetY(k), feetZ(k)
        footX(k) = rotX + ld.px
        footY(k) = rotY + ld.py
        footZ(k) = rotZ + ld.pz
    Next k
End Sub

' height of the feet above the ground
Public Function LdAgl() As Long
    LdAgl = ld.py - 131072 - LdHeight(ld.px, ld.pz)
End Function

Private Sub PushEv(ByVal e As Long)
    If ld.nev < 8 Then
        ld.ev(ld.nev) = e
        ld.nev = ld.nev + 1
    End If
End Sub

Public Function LdPopEvent() As Long
    Dim k As Long
    If ld.nev = 0 Then
        LdPopEvent = LDE_NONE
        Exit Function
    End If
    LdPopEvent = ld.ev(0)
    For k = 0 To ld.nev - 2
        ld.ev(k) = ld.ev(k + 1)
    Next k
    ld.nev = ld.nev - 1
End Function

Private Sub WindAt(ByVal t As Long)
    Dim s As Long, a As Long, ph As Long
    If ld.pWind = 0 Then
        ld.wind0 = 0
        ld.wind1 = 0
        Exit Sub
    End If
    ph = ld.windPh
    s = MulShr(ld.pWind, 42598 + MulShr(16384, LdSin(MulShr(t, 13762, 16) + ph), 16) + _
             MulShr(MulShr(11796, LdSin(MulShr(t, 85196, 16) + 2 * ph), 16), LdSin(MulShr(t, 24248, 16)), 16), 16)
    a = ld.windDir + MulShr(22937, LdSin(MulShr(t, 8519, 16) + ph), 16)
    ld.wind0 = MulShr(LdCos(a), s, 16)
    ld.wind1 = MulShr(LdSin(a), s, 16)
End Sub

Private Sub Finish(ByVal oc As Long)
    ld.outcome = oc
    If oc <> OUT_CRASHED And oc <> OUT_LOST Then
        ld.vx = 0: ld.vy = 0: ld.vz = 0
        ld.wp = 0: ld.wr = 0
    End If
    ld.thr = 0
    Select Case oc
        Case OUT_LANDED: PushEv LDE_LANDED
        Case OUT_OFFPAD: PushEv LDE_OFFPAD
        Case OUT_CRASHED: PushEv LDE_CRASHED
        Case Else: PushEv LDE_LOST
    End Select
End Sub

' touchdown: any foot or the bell at or below the ground decides it
Private Function Contact() As Boolean
    Dim pen As Long, vs As Long, hs As Long, tilt As Long, k As Long, f As Long, pad As Long
    Dim g As Long, touching As Boolean, inside As Boolean, w As Long, soft As Long
    LdFeet
    For k = 0 To 4
        g = LdHeight(footX(k), footZ(k))
        If footY(k) <= g Then
            touching = True
            If g - footY(k) > pen Then pen = g - footY(k)
        End If
    Next k
    If Not touching Then Exit Function
    w = ld.world
    ld.py = ld.py + pen
    vs = -ld.vy
    hs = FHypot(ld.vx, ld.vz)
    tilt = LdTilt()
    pad = -1
    For k = 0 To 2
        inside = FHypot(ld.px - padX(k), ld.pz - padZ(k)) <= padR(k) - 78643
        For f = 0 To 3
            If Not inside Then Exit For
            If FHypot(footX(f) - padX(k), footZ(f) - padZ(k)) > padR(k) + 13107 Then inside = False
        Next f
        If inside Then
            pad = k
            Exit For
        End If
    Next k
    ld.rVs = vs: ld.rHs = hs: ld.rTilt = tilt
    ld.rScore = 0: ld.rSoft = 0: ld.rFuelBonus = 0
    ld.rVsOk = -(vs <= wLimVs(w))
    ld.rHsOk = -(hs <= wLimHs(w))
    ld.rTiltOk = -(tilt <= wLimTilt(w))
    If pad >= 0 Then ld.rPad = padMult(pad) Else ld.rPad = 0
    ld.rSlope = LdSlopeCos(ld.px, ld.pz)
    If ld.rVsOk <> 0 And ld.rHsOk <> 0 And ld.rTiltOk <> 0 And pad >= 0 Then
        soft = 60 * (FONE - MulDiv(vs, 65536, wLimVs(w))) + 30 * (FONE - MulDiv(tilt, 65536, wLimTilt(w))) + 20 * (FONE - MulDiv(hs, 65536, wLimHs(w)))
        ld.rSoft = FInt(soft + 32768)
        ld.rFuelBonus = FInt(MulShr(MulDiv(ld.fuel, 65536, ld.fuelMax), FromI(150), 16) + 32768)
        ld.rScore = (100 + ld.rSoft + ld.rFuelBonus) * ld.rPad
        Finish OUT_LANDED
    ElseIf ld.rVsOk <> 0 And ld.rHsOk <> 0 And ld.rTiltOk <> 0 And ld.rSlope >= 63589 Then    ' <= 14 degrees
        ld.rScore = 25
        Finish OUT_OFFPAD
    Else
        Finish OUT_CRASHED
    End If
    Contact = True
End Function

' one RCS axis: the new rate from the rate w and the command cmd
Private Function Axis(ByVal w As Long, ByVal cmd As Long, ByVal k As Long) As Long
    Dim e As Long, a As Long, sgn As Long
    If ld.fuel <= 0 Then
        Axis = w
        Exit Function
    End If
    If ld.assist <> 0 Then
        e = MulShr(cmd, RATE, 16) - w
        a = Clamp(e * 6, -ALPHA, ALPHA)
        If AbsL(a) > 13107 Then
            If a > 0 Then sgn = 1 Else sgn = -1
            If k = 0 Then ld.rcs0 = sgn Else ld.rcs1 = sgn
        End If
        Axis = w + a \ LD_STEP_HZ
        Exit Function
    End If
    If cmd <> 0 Then
        If cmd > 0 Then sgn = 1 Else sgn = -1
        If k = 0 Then ld.rcs0 = sgn Else ld.rcs1 = sgn
    End If
    Axis = w + MulShr(cmd, ALPHA, 16) \ LD_STEP_HZ
End Function

' one 1/100 s step with the controls inThr, inPitch, inRoll
Public Sub LdStep()
    Dim w As Long, thr As Long, ax As Long, ay As Long, az As Long, speed As Long, burn As Long
    Dim subs As Long, s As Long, div As Long, amax As Long, drag As Long, nr As Long, lim As Long
    ld.t = ld.t + 1
    If ld.outcome <> 0 Then Exit Sub
    w = ld.world
    thr = Clamp(inThr, 0, FONE)
    If ld.fuel <= 0 Then thr = 0
    ld.rcs0 = 0
    ld.rcs1 = 0
    ld.wp = Axis(ld.wp, Clamp(inPitch, -FONE, FONE), 0)
    ld.wr = Axis(ld.wr, Clamp(inRoll, -FONE, FONE), 1)
    ld.pitch = Clamp(ld.pitch + ld.wp \ LD_STEP_HZ, -MAX_TILT, MAX_TILT)
    ld.roll = Clamp(ld.roll + ld.wr \ LD_STEP_HZ, -MAX_TILT, MAX_TILT)
    If AbsL(ld.pitch) >= MAX_TILT Then ld.wp = 0
    If AbsL(ld.roll) >= MAX_TILT Then ld.wr = 0
    nr = 0
    If ld.rcs0 <> 0 Then nr = 1
    If ld.rcs1 <> 0 Then nr = nr + 1
    burn = thr \ LD_STEP_HZ + nr * RCS_FUEL \ LD_STEP_HZ
    If ld.fuel > 0 Then
        ld.fuel = ld.fuel - burn
        If ld.fuel <= 0 Then
            ld.fuel = 0
            PushEv LDE_FUEL_OUT
        End If
    End If
    ld.thr = thr
    LdUp
    amax = wAmax(w)
    ax = MulShr(MulShr(upX, amax, 16), thr, 16)
    ay = MulShr(MulShr(upY, amax, 16), thr, 16) - wG(w)
    az = MulShr(MulShr(upZ, amax, 16), thr, 16)
    WindAt ld.t * LD_DT
    drag = wDrag(w)
    If drag <> 0 Then
        ax = ax + MulShr(drag, ld.wind0 - ld.vx, 16)
        az = az + MulShr(drag, ld.wind1 - ld.vz, 16)
        ay = ay - MulShr(MulShr(drag, 19660, 16), ld.vy, 16)
    End If
    ' sub-steps keep the touchdown check honest at any speed
    speed = FHypot3(ld.vx, ld.vy, ld.vz) + amax \ LD_STEP_HZ
    subs = (speed \ LD_STEP_HZ + 16384 - 1) \ 16384
    If subs < 1 Then subs = 1
    If subs > 64 Then subs = 64
    div = LD_STEP_HZ * subs
    For s = 1 To subs
        ld.vx = ld.vx + ax \ div
        ld.vy = ld.vy + ay \ div
        ld.vz = ld.vz + az \ div
        ld.px = ld.px + ld.vx \ div
        ld.py = ld.py + ld.vy \ div
        ld.pz = ld.pz + ld.vz \ div
        If Contact() Then Exit Sub
    Next s
    lim = MulShr(tHalf, 75366, 16)
    If AbsL(ld.px) > lim Or AbsL(ld.pz) > lim Or ld.py > FromI(6000) Then Finish OUT_LOST
End Sub

Public Function LdNearestPad(ByVal easiest As Boolean) As Long
    Dim k As Long, pick As Long, best As Long, d As Long, s As Long
    best = &H7FFFFFFF
    For k = 0 To 2
        d = FHypot(padX(k) - ld.px, padZ(k) - ld.pz)
        If easiest Then s = MulDiv(d, 65536, padR(k)) Else s = d
        If s < best Then
            best = s
            pick = k
        End If
    Next k
    LdNearestPad = pick
End Function

' ---------- the autopilot: sets inThr, inPitch, inRoll ----------

Public Sub LdAutopilot()
    Dim w As Long, pk As Long, dx As Long, dz As Long, dist As Long, h As Long, hi As Long, clearance As Long
    Dim vmax As Long, aH As Long, vh As Long, vd0 As Long, vd1 As Long, kh As Long, ax As Long, ay As Long, az As Long
    Dim vyDes As Long, amag As Long, ux As Long, uy As Long, uz As Long, maxT As Long, rollT As Long, pitchT As Long
    Dim k As Long, lm As Long, t As Long, g As Long, cap As Long, m As Long, six As Long, halfR As Long
    Dim cruise As Long, hiLim As Long, v1 As Long, v2 As Long, hh As Long, s As Long, den As Long, tmp As Long
    w = ld.world
    If ld.apTarget < 0 Then ld.apTarget = LdNearestPad(True)
    pk = ld.apTarget
    dx = padX(pk) - ld.px
    dz = padZ(pk) - ld.pz
    dist = FHypot(dx, dz)
    h = ld.py - 131072 - padY(pk)
    hi = -&H7FFFFFFF
    If dist > FromI(140) Then lm = MulDiv(FromI(140), 65536, dist) Else lm = FONE
    For k = 0 To 8
        t = MulShr(FromI(k) \ 8, lm, 16)
        g = LdHeight(ld.px + MulShr(dx, t, 16), ld.pz + MulShr(dz, t, 16))
        If g > hi Then hi = g
    Next k
    clearance = ld.py - 131072 - hi
    vmax = MulShr(wAmax(w), 209715, 16)
    tmp = FromI(4) + MulShr(dist, 9175, 16)
    If tmp < vmax Then vmax = tmp
    aH = MulShr(wAmax(w), 26656, 16)                    ' sin 24 degrees
    vh = vmax
    tmp = MulShr(dist, 18350, 16)
    If tmp < vh Then vh = tmp
    tmp = FSqrt(MulShr(MulShr(39321, aH, 16), dist, 16))
    If tmp < vh Then vh = tmp
    If dist > 655 Then
        vd0 = MulShr(MulDiv(dx, 65536, dist), vh, 16)
        vd1 = MulShr(MulDiv(dz, 65536, dist), vh, 16)
    Else
        vd0 = 0
        vd1 = 0
    End If
    If ld.apDown <> 0 Then
        cap = MulShr(wLimHs(w), 22937, 16)
        m = FHypot(vd0, vd1)
        If m > cap Then
            vd0 = MulShr(vd0, MulDiv(cap, 65536, m), 16)
            vd1 = MulShr(vd1, MulDiv(cap, 65536, m), 16)
        End If
        kh = 91750
    Else
        kh = 58982
    End If
    ax = MulShr(vd0 - ld.vx, kh, 16)
    az = MulShr(vd1 - ld.vz, kh, 16)
    ' hold a cruise height while far; descend once over the pad (with hysteresis,
    ' so gusts don't send it back up)
    six = FromI(6)
    halfR = MulShr(padR(pk), 29491, 16)
    If six < halfR Then tmp = six Else tmp = halfR
    If dist < tmp Then
        ld.apDown = 1
    ElseIf dist > MulShr(padR(pk), 55705, 16) Then
        ld.apDown = 0
    End If
    If ld.apDown = 0 Then
        If dist < FromI(60) Then
            cruise = FromI(14)
        Else
            cruise = MulShr(dist, 5242, 16)
            If cruise <= FromI(25) Then cruise = FromI(25)
        End If
        vyDes = Clamp(MulShr(cruise - clearance, 22937, 16), FromI(-4), FromI(6))
    Else
        hiLim = MulShr(wLimVs(w), 36044, 16) + MulShr(h, 3276, 16)
        vyDes = -Clamp(MulShr(h, 7864, 16) + 39321, 39321, hiLim)
        If h < FromI(6) Then
            v1 = MulShr(wLimVs(w), 29491, 16)
            v2 = 26214 + MulShr(h, 9830, 16)
            If v1 < v2 Then vyDes = -v1 Else vyDes = -v2
        End If
    End If
    If ld.apDown <> 0 And h < FromI(8) And vyDes < 0 Then
        If FHypot(ld.vx, ld.vz) > MulShr(wLimHs(w), 32768, 16) Then vyDes = 0
    End If
    If ld.apDown <> 0 And h < FromI(10) And vyDes < 0 Then
        If dist > MulShr(padR(pk), 32768, 16) Then vyDes = 0
    End If
    ay = MulShr(vyDes - ld.vy, 104857, 16) + wG(w)
    amag = FHypot3(ax, ay, az)
    If amag < 1 Then amag = 1
    ux = MulDiv(ax, 65536, amag)
    uy = MulDiv(ay, 65536, amag)
    uz = MulDiv(az, 65536, amag)
    If h < 98304 Then
        maxT = 3431                               ' 3 degrees
    ElseIf h < FromI(6) Then
        If 10294 < wLimTilt(w) - 1143 Then maxT = 10294 Else maxT = wLimTilt(w) - 1143
    Else
        maxT = 32026                              ' 28 degrees
    End If
    If uy < LdCos(maxT) Then
        hh = FHypot(ux, uz)
        s = LdSin(maxT)
        If hh < 1 Then hh = 1
        ux = MulShr(MulDiv(ux, 65536, hh), s, 16)
        uz = MulShr(MulDiv(uz, 65536, hh), s, 16)
        uy = LdCos(maxT)
    End If
    den = MulShr(wAmax(w), uy, 16)
    If den > 0 Then
        If ay > 0 Then tmp = ay Else tmp = 0
        inThr = Clamp(MulDiv(tmp, 65536, den), 0, FONE)
    Else
        inThr = FONE
    End If
    ' the attitude that points the thrust that way: u = [-sin r, cos r cos p, cos r sin p]
    rollT = FAsin(Clamp(-ux, -FONE, FONE))
    pitchT = FAtan2(uz, uy)
    inPitch = Clamp(MulShr(pitchT - ld.pitch, 183500, 16) - MulShr(ld.wp, 26214, 16), -FONE, FONE)
    inRoll = Clamp(MulShr(rollT - ld.roll, 183500, 16) - MulShr(ld.wr, 26214, 16), -FONE, FONE)
End Sub

' ---------- levels ----------

' the autopilot's test flight, in slices: begin, then run until it returns True;
' it tops up ld's tank if the autopilot needed more
Public Sub LdProbeBegin()
    probeS = ld
    probeS.fuel = PROBE_FUEL
    probeS.fuelMax = PROBE_FUEL
End Sub

Public Function LdProbeRun(ByVal steps As Long) As Boolean
    Dim keep As LdState, kThr As Long, kPitch As Long, kRoll As Long, need As Long, done As Boolean
    keep = ld
    kThr = inThr: kPitch = inPitch: kRoll = inRoll
    ld = probeS
    Do While steps > 0 And ld.outcome = 0 And ld.t < LD_STEP_HZ * 400
        LdAutopilot
        LdStep
        steps = steps - 1
    Loop
    done = ld.outcome <> 0 Or ld.t >= LD_STEP_HZ * 400
    probeS = ld
    ld = keep
    inThr = kThr: inPitch = kPitch: inRoll = kRoll
    If Not done Then Exit Function
    ld.probeUsed = PROBE_FUEL - probeS.fuel
    ld.probeOutcome = probeS.outcome
    If probeS.outcome = OUT_LANDED Then
        need = (MulShr(ld.probeUsed, 85196, 16) + FONE - 1) And &HFFFF0000
        If need > ld.fuelMax Then                ' top up by the difference
            ld.fuel = ld.fuel + need - ld.fuelMax
            ld.fuelMax = need
        End If
    End If
    LdProbeRun = True
End Function

Public Sub LdNewLevel(ByVal world As Long, ByVal lv As Long, ByVal seed As Long, ByVal doProbe As Boolean)
    Dim r As Long, sx As Long, sz As Long, best As Long, dir As Long, ground As Long, y As Long, lim As Long
    Dim t As Long, k As Long, a As Long, x As Long, z As Long, sc As Long, g As Long, blank As LdState
    LdInit
    ld = blank
    r = seed Xor &H5BD1E995
    ld.world = world
    ld.lvl = lv
    ld.seed = seed
    ld.assist = 1
    ld.apTarget = -1
    LdLevelParams world, lv
    LdMakeTerrain world, seed, ld.pPadScale
    lim = MulShr(tHalf, 52428, 16)
    best = -&H7FFFFFFF
    For t = 0 To 23
        a = MulShr(Rf(r), 411774, 16)
        x = padX(0) + MulShr(LdCos(a), ld.pStartDist, 16)
        z = padZ(0) + MulShr(LdSin(a), ld.pStartDist, 16)
        If AbsL(x) < lim And AbsL(z) < lim Then sc = FromI(1000) Else sc = 0
        sc = sc - MulShr(FHypot(x, z), 6553, 16) + Rf(r)
        If sc > best Then
            best = sc
            sx = x
            sz = z
        End If
    Next t
    sx = Clamp(sx, -MulShr(tHalf, 55705, 16), MulShr(tHalf, 55705, 16))
    sz = Clamp(sz, -MulShr(tHalf, 55705, 16), MulShr(tHalf, 55705, 16))
    dir = FAtan2(padZ(0) - sz, padX(0) - sx) + MulShr(Rf(r) - 32768, 78643, 16)
    ground = -&H7FFFFFFF
    For k = 0 To 10
        g = LdHeight(sx + ((padX(0) - sx) \ 10) * k, sz + ((padZ(0) - sz) \ 10) * k)
        If g > ground Then ground = g
    Next k
    y = LdHeight(sx, sz)
    If ground > y Then y = ground
    ld.px = sx
    ld.py = y + ld.pStartAlt
    ld.pz = sz
    ld.vx = MulShr(LdCos(dir), ld.pStartH, 16)
    ld.vy = -98304
    ld.vz = MulShr(LdSin(dir), ld.pStartH, 16)
    ld.fuel = ld.pFuel
    ld.fuelMax = ld.pFuel
    ld.windDir = MulShr(Rf(r), 411774, 16)
    ld.windPh = MulShr(Rf(r), FromI(10), 16)
    ' every level can be landed: fly it once with the autopilot and enough fuel,
    ' and give the tank 30 % more than that flight used
    If doProbe Then
        LdProbeBegin
        Do While Not LdProbeRun(1000)
        Loop
    End If
End Sub

' ---------- hashes, for the tests ----------

Public Function LdTerrainHash() As Long
    Dim h As Long, k As Long
    h = FNV_START
    For k = 0 To tN * tN - 1
        h = Fnv(h, tH(k))
    Next k
    For k = 0 To 2
        h = Fnv(h, padX(k)): h = Fnv(h, padZ(k)): h = Fnv(h, padR(k))
        h = Fnv(h, padY(k)): h = Fnv(h, padMult(k))
    Next k
    LdTerrainHash = h
End Function

Public Function LdStateHash() As Long
    Dim h As Long
    h = FNV_START
    h = Fnv(h, ld.px): h = Fnv(h, ld.vx): h = Fnv(h, ld.py): h = Fnv(h, ld.vy): h = Fnv(h, ld.pz): h = Fnv(h, ld.vz)
    h = Fnv(h, ld.pitch): h = Fnv(h, ld.roll): h = Fnv(h, ld.wp): h = Fnv(h, ld.wr)
    h = Fnv(h, ld.thr): h = Fnv(h, ld.rcs0): h = Fnv(h, ld.rcs1)
    h = Fnv(h, ld.fuel): h = Fnv(h, ld.fuelMax): h = Fnv(h, ld.t): h = Fnv(h, ld.outcome)
    h = Fnv(h, ld.rScore): h = Fnv(h, ld.rSoft): h = Fnv(h, ld.rFuelBonus)
    h = Fnv(h, ld.rPad): h = Fnv(h, ld.apDown): h = Fnv(h, ld.apTarget)
    h = Fnv(h, ld.wind0): h = Fnv(h, ld.wind1): h = Fnv(h, ld.nev)
    LdStateHash = h
End Function
