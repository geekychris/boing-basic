' runs the Glimmerfield logic bench quietly, then a high-score table round trip
Option Explicit

Sub Main()
    Dim i As Long, p As String
    RunBench 2500, 1987, True
    RunBench 600, 7, True
    p = "glimmer_test.scores"
    HsDefaults
    Print "rank of 12000: "; HsRank(12000); " of 99: "; HsRank(99)
    Print "inserted at "; HsInsert("tester", 12345)
    Print "saved "; HsSave(p)
    hsName(0) = "x"
    HsLoad p
    For i = 0 To HS_COUNT - 1
        Print HsLine(i)
    Next i
    Kill p
    HsLoad "no_such_file.scores"
    Print "missing file: "; hsName(0); " "; hsScore(0)
End Sub
