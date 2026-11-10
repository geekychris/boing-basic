Type HiScore
    Points As Long
    Initials As String * 3
End Type

Dim f As Integer, h As HiScore, i As Integer

f = FreeFile
Open "scores.dat" For Random As #f Len = Len(h)
For i = 1 To 3
    h.Points = 5000 - i * 1000
    h.Initials = Choose(i, "ADA", "BOB", "CAT")
    Put #f, i, h
Next
Print "records:"; LOF(f) / Len(h); "of"; Len(h); "bytes"

Get #f, 2, h
Print h.Initials; h.Points
h.Points = 9999
Put #f, 2, h                      ' change one record in place
Get #f, 2, h
Print h.Initials; h.Points
Close #f

Kill "scores.dat"
