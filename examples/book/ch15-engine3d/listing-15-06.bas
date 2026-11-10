Option Explicit

Sub Main()
    Dim e As Engine3D, st As Long
    Set e = CreateObject("Boing.Engine3D")
    Print "Sin(16384) ="; e.Sin(16384); " (a quarter turn: 1.0 is 65536)"
    Print "Cos(0) ="; e.Cos(0); "  Sin(8192) ="; e.Sin(8192)
    Print "Atan2(1, 1) ="; e.Atan2(1, 1); " (an eighth of a turn)"
    Print "ISqrt(1000000) ="; e.ISqrt(1000000); "  Hypot(3, 4) ="; e.Hypot(3, 4)
    Print "FMul(1.5, 2.5) ="; e.FMul(98304, 163840) / 65536
    Print "FDiv(1, 4) ="; e.FDiv(65536, 262144) / 65536
    Print "FSqrt(2) ="; e.FSqrt(131072) / 65536
    st = 1
    Print "Rand:"; e.Rand(st); e.Rand(st); e.Rand(st)
    Print "Hash(42) ="; e.Hash(42)
End Sub
