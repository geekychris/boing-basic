Type Point
    X As Long
    Y As Long
End Type
Type Person
    Name As String
    Age As Integer
    Pos As Point
    Tags(1 To 3) As String
    Code As String * 4
End Type
Dim p As Person, q As Person
p.Name = "Ada"
p.Age = 36
p.Pos.X = 10
p.Pos.Y = 20
p.Tags(1) = "math"
p.Code = "AB"
q = p
q.Name = "Bob"
q.Tags(1) = "art"
Print p.Name; p.Age; p.Pos.X; p.Pos.Y; " "; p.Tags(1); " ["; p.Code; "]"
Print q.Name; q.Age; " "; q.Tags(1)
Sub Move(pt As Point, ByVal dx As Long)
    pt.X = pt.X + dx
End Sub
Move p.Pos, 5
Print p.Pos.X
Dim pts(1 To 3) As Point
pts(2).X = 7
Print pts(2).X; pts(1).X
With p
    .Age = .Age + 1
    Print .Name; .Age
    With .Pos
        .Y = 99
    End With
End With
Print p.Pos.Y
Function MakePoint(ByVal x As Long, ByVal y As Long) As Point
    MakePoint.X = x
    MakePoint.Y = y
End Function
Dim m As Point
m = MakePoint(3, 4)
Print m.X; m.Y
Print Len(m)
