' demo.bas - uses the shapes extension (C++; Extension=shapes in demo.bbp)
Sub Main()
    Dim s As Shape, t As Shape
    Set s = CreateObject("Shape")
    s.Width = 6
    s.Height = 7
    Print "area"; s.Area(); " "; s.Describe()
    Set t = CreateObject("Boing.Shape")
    Print "default"; t.Area(); " "; t.Describe()
    Set t = Nothing
    Print "gcd"; Gcd(84, 36); Gcd(-12, 18)
End Sub
