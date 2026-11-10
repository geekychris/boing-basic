Const PI As Double = 3.14159265358979

Function Deg2Rad(ByVal d As Double) As Double
    Deg2Rad = d * PI / 180
End Function

Function Log10(ByVal x As Double) As Double
    Log10 = Log(x) / Log(10)
End Function

Print Format(Atn(1) * 4, "0.000000"); " "; Format(Sin(Deg2Rad(30)), "0.000"); " "; Log10(1000)
