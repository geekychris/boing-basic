' Riffwright tests - .mod load/save
Option Explicit

Sub RoundTrip(ByVal name As String)
    Dim out As String
    If Not LoadMod("ref/" & name) Then Print name; ": load failed: "; lastError: Exit Sub
    Print name; ": "; nch; "channels,"; nPat; "patterns, length"; songLen; ", tag "; songTag
    out = "out_" & name
    If Not SaveMod(out) Then Print "save failed: "; lastError: Exit Sub
    Print "  round trip: "; CompareFiles("ref/" & name, out)
    Kill out
End Sub

Sub Main()
    Dim i As Long, k As Long
    RoundTrip "ref4.mod"
    ' what the loader made of ref4
    LoadMod "ref/ref4.mod"
    Print "title ["; TitleText(); "] restart"; songRestart
    For i = 1 To 31
        If smpLen(i) > 0 Then
            Print "  smp"; i; "["; SampleText(i); "] len"; smpLen(i); "vol"; smpVol(i); _
                "fine"; FineSigned(i); "loop"; smpLoopS(i); smpLoopL(i)
        End If
    Next i
    For i = 0 To 7
        k = CellIdx(0, i, 0)
        Print "  row"; i; ": "; CellText(CellIdx(0, i, 0)); " | "; CellText(CellIdx(0, i, 1)); _
            " | "; CellText(CellIdx(0, i, 2)); " | "; CellText(CellIdx(0, i, 3))
    Next i
    Print "  odd period 431 shows as "; NoteText(431); ", 1712 as "; NoteText(1712); ", 57 as "; NoteText(57)
    Print "  tail bytes"; UBound(songTail) + 1
    ' the demo songs
    Dim dm As Variant
    For Each dm In Array("harbour_lights.mod", "boing_shuffle.mod")
        If LoadMod("../demos/" & dm) Then
            Print dm; ": ["; TitleText(); "]"; nPat; "patterns, length"; songLen; ", samples";
            For i = 1 To 31
                If smpLen(i) > 0 Then Print " "; SampleText(i);
            Next i
            Print
            SaveMod "out.mod"
            Print "  round trip: "; CompareFiles("../demos/" & dm, "out.mod")
            Kill "out.mod"
        Else
            Print dm; ": "; lastError
        End If
    Next
    RoundTrip "ref6.mod"
    RoundTrip "ref8.mod"
    ' a new song saves as a valid M.K. file and loads back
    NewSong 4
    songTitle = PadName("fresh", 20)
    Check "new song saves", SaveMod("new.mod")
    Check "new song size 1084+1024", FileLen("new.mod") = 2108
    Check "new song loads", LoadMod("new.mod")
    Check "tag M.K.", songTag = "M.K."
    Kill "new.mod"
    ' a bad file
    Open "bad.mod" For Output As #1
    Print #1, "hello"
    Close #1
    Check "short file refused", Not LoadMod("bad.mod")
    Print "  "; lastError
    Kill "bad.mod"
End Sub
