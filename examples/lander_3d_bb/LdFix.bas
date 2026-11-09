' LdFix - the amiga3d engine's integer maths (a3d_math.c, a3d_fix.c) for Lander 3D, bit for
' bit as the C: examples/common/A3Fix.bas with the same names and results, but integer-only
' (the Shl / ShrA / ShrL / MulShr / MulDiv builtins, 16-bit partial products). Written when
' A3Fix's CDbl() expressions cost ~29 us each on the QEMU guest (fixed in the VM since);
' the game code calls MulShr / MulDiv directly for FMUL / FDIV.
'
' Values are Longs holding C's int32_t / uint32_t bit patterns:
'   ShrA(x, k), ShrL(x, k), Shl(x, k)   the builtins: x >> k (int32 / uint32), x << k wrapping
'   AddW/MulW   + and * wrapping to 32 bits (uint32 arithmetic)
'   FMul/FDiv   16.16 FMUL/FDIV: MulShr(a, b, 16), MulDiv(a, 65536, b)
Option Explicit

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
    a = Abs(num)
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
    ax = Abs(x)
    ay = Abs(y)
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
    x = Abs(a)
    y = Abs(b)
    Do While (x Or y) >= 46000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        sh = sh + 1
    Loop
    d = x
    e = y
    FHypot = Shl(ISqrtD(d * d + e * e), sh)
End Function

Public Function FHypot3(ByVal a As Long, ByVal b As Long, ByVal c As Long) As Long
    Dim x As Long, y As Long, z As Long, sh As Long, d As Double, e As Double, f As Double
    x = Abs(a)
    y = Abs(b)
    z = Abs(c)
    Do While (x Or y Or z) >= 37000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        z = ShrL(z, 1)
        sh = sh + 1
    Loop
    d = x
    e = y
    f = z
    FHypot3 = Shl(ISqrtD(d * d + e * e + f * f), sh)
End Function

' fsqrt: sqrt of a 16.16 value
Public Function FSqrt(ByVal a As Long) As Long
    Dim v As Long, k As Long, r As Long
    If a <= 0 Then
        FSqrt = 0
        Exit Function
    End If
    v = a
    Do While v < 268435456 And k < 15
        v = v * 4
        k = k + 1
    Loop
    r = ISqrtD(v)
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
    ax = Abs(x)
    ay = Abs(y)
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

' a Long's bits as 8 hex digits
Public Function Hex8(ByVal x As Long) As String
    Hex8 = Right$("0000000" & Hex$(x), 8)
End Function
