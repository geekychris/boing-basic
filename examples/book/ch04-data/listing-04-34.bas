Type Point
    X As Long
    Y As Long
End Type

Type Player
    Name As String
    Initials As String * 3
    Pos As Point                    ' a nested type
    Scores(1 To 3) As Integer       ' a fixed-size array field
    Lives As Integer
End Type

Dim p As Player
p.Name = "Ann"
p.Initials = "ANNE"
p.Pos.X = 10: p.Pos.Y = 20
p.Scores(2) = 500
p.Lives = 3
Print p.Name; " ["; p.Initials; "] at"; p.Pos.X; ","; p.Pos.Y; " score"; p.Scores(2)
