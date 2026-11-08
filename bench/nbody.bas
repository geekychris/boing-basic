' n-body simulation (the Computer Language Benchmarks Game, 5 bodies)
Type Body
    X As Double: Y As Double: Z As Double
    VX As Double: VY As Double: VZ As Double
    M As Double
End Type
Const PI = 3.141592653589793
Const SOLAR = 4 * PI * PI
Const DPY = 365.24
Dim b(4) As Body

Sub Init()
    b(0).M = SOLAR
    b(1).X = 4.84143144246472: b(1).Y = -1.16032004402743: b(1).Z = -0.103622044471123
    b(1).VX = 0.00166007664274403 * DPY: b(1).VY = 0.00769901118419740 * DPY: b(1).VZ = -0.0000690460016972063 * DPY
    b(1).M = 0.000954791938424327 * SOLAR
    b(2).X = 8.34336671824458: b(2).Y = 4.1247985641243: b(2).Z = -0.403523417114321
    b(2).VX = -0.00276742510726862 * DPY: b(2).VY = 0.00499852801234917 * DPY: b(2).VZ = 0.0000230417297573763 * DPY
    b(2).M = 0.000285885980666130 * SOLAR
    b(3).X = 12.8943695621391: b(3).Y = -15.1111514016986: b(3).Z = -0.223307578892655
    b(3).VX = 0.00296460137564761 * DPY: b(3).VY = 0.00237847173959480 * DPY: b(3).VZ = -0.0000296589568540237 * DPY
    b(3).M = 0.0000436624404335156 * SOLAR
    b(4).X = 15.3796971148509: b(4).Y = -25.9193146099880: b(4).Z = 0.179258772950371
    b(4).VX = 0.00268067772490389 * DPY: b(4).VY = 0.00162824170038242 * DPY: b(4).VZ = -0.0000951592254519715 * DPY
    b(4).M = 0.0000515138902046611 * SOLAR
    Dim i As Integer, px As Double, py As Double, pz As Double
    For i = 0 To 4
        px = px + b(i).VX * b(i).M: py = py + b(i).VY * b(i).M: pz = pz + b(i).VZ * b(i).M
    Next
    b(0).VX = -px / SOLAR: b(0).VY = -py / SOLAR: b(0).VZ = -pz / SOLAR
End Sub

Function Energy() As Double
    Dim i As Integer, j As Integer, e As Double, dx As Double, dy As Double, dz As Double
    For i = 0 To 4
        e = e + 0.5 * b(i).M * (b(i).VX * b(i).VX + b(i).VY * b(i).VY + b(i).VZ * b(i).VZ)
        For j = i + 1 To 4
            dx = b(i).X - b(j).X: dy = b(i).Y - b(j).Y: dz = b(i).Z - b(j).Z
            e = e - b(i).M * b(j).M / Sqr(dx * dx + dy * dy + dz * dz)
        Next
    Next
    Energy = e
End Function

Sub Advance(ByVal dt As Double)
    Dim i As Integer, j As Integer, dx As Double, dy As Double, dz As Double, d2 As Double, mag As Double
    For i = 0 To 4
        For j = i + 1 To 4
            dx = b(i).X - b(j).X: dy = b(i).Y - b(j).Y: dz = b(i).Z - b(j).Z
            d2 = dx * dx + dy * dy + dz * dz
            mag = dt / (d2 * Sqr(d2))
            b(i).VX = b(i).VX - dx * b(j).M * mag: b(i).VY = b(i).VY - dy * b(j).M * mag: b(i).VZ = b(i).VZ - dz * b(j).M * mag
            b(j).VX = b(j).VX + dx * b(i).M * mag: b(j).VY = b(j).VY + dy * b(i).M * mag: b(j).VZ = b(j).VZ + dz * b(i).M * mag
        Next
    Next
    For i = 0 To 4
        b(i).X = b(i).X + dt * b(i).VX: b(i).Y = b(i).Y + dt * b(i).VY: b(i).Z = b(i).Z + dt * b(i).VZ
    Next
End Sub

Dim n As Long, k As Long
n = Val(Command$): If n = 0 Then n = 1
Init
Print Format(Energy(), "0.000000000")
For k = 1 To 300000 * n
    Advance 0.01
Next
Print Format(Energy(), "0.000000000")
