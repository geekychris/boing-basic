Type Rec
    Id As Long
    Name As String * 8
    Score As Double
End Type
Dim r As Rec, i As Integer
Open "recs.dat" For Random As #1 Len = Len(r)
For i = 1 To 3
    r.Id = i
    r.Name = "item" & i
    r.Score = i * 1.5
    Put #1, i, r
Next
Get #1, 2, r
Print r.Id; "["; r.Name; "]"; r.Score
Print LOF(1)
Close #1
Open "bin.dat" For Binary As #1
Dim l As Long, s As String
l = 305419896
Put #1, , l
Put #1, , "Hello"
Seek #1, 1
l = 0
Get #1, , l
s = Space(5)
Get #1, , s
Print l; s; Seek(1); LOF(1)
Close #1
Kill "recs.dat"
Kill "bin.dat"
