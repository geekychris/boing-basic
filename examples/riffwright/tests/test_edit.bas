' Riffwright tests - editing and undo
Option Explicit

Function RowText(ByVal pat As Long, ByVal r As Long) As String
    Dim c As Long, s As String
    For c = 0 To nch - 1
        If c > 0 Then s = s & " | "
        s = s & CellText(CellIdx(pat, r, c))
    Next c
    RowText = s
End Function

Sub Dump(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long)
    Dim r As Long
    For r = r0 To r1
        Print "  "; Right$("0" & r, 2); " "; RowText(pat, r)
    Next r
End Sub

Sub Main()
    Dim i As Long, n As Long
    NewSong 4
    ' notes: C-2 (25) sample 1 on ch0, E-2 sample 2 on ch1, effect C40 on ch2
    EdNote 0, 0, 0, 25, 1
    EdNote 0, 1, 1, 29, 2
    EdDigit 0, 2, 2, 3, &HC
    EdDigit 0, 2, 2, 4, 4
    EdDigit 0, 2, 2, 5, 0
    EdDigit 0, 3, 3, 1, 1
    EdDigit 0, 3, 3, 2, &HF
    Print "after entry:"
    Dump 0, 0, 3
    Check "4 cells mirrored+", mirrorCount >= 7
    Check "undo count 7", UndoCount() = 7
    Check "sample 1F", cSmp(CellIdx(0, 3, 3)) = 31
    ' undo two, redo one
    Undo
    Undo
    Print "undo x2:"
    Dump 0, 3, 3
    Redo
    Print "redo:"
    Dump 0, 3, 3
    Check "redo count 1", RedoCount() = 1
    ' a new edit clears redo
    EdClear 0, 2, 2, 3
    Check "redo cleared", RedoCount() = 0
    Undo
    Check "C40 back", cFx(CellIdx(0, 2, 2)) = 12 And cPrm(CellIdx(0, 2, 2)) = &H40
    ' copy/paste a block
    EdCopy 0, 0, 2, 0, 2
    EdPaste 0, 8, 1, False
    Print "paste at row 8 ch 1:"
    Dump 0, 8, 10
    ' paste clipped at the right edge and bottom
    EdPaste 0, 62, 2, False
    Print "paste clipped:"
    Dump 0, 62, 63
    ' transpose up an octave, then past the top
    EdTranspose 0, 8, 10, 0, 3, 12
    Print "transpose +12:"
    Dump 0, 8, 9
    n = EdTranspose(0, 8, 10, 0, 3, 24)
    Print "transpose +24 clipped notes:"; n
    Dump 0, 8, 9
    Undo
    Undo
    Print "undo both:"
    Dump 0, 8, 9
    ' insert/delete rows
    EdInsertRow 0, 0, -1
    Print "insert row 0:"
    Dump 0, 0, 2
    EdDeleteRow 0, 0, -1
    EdDeleteRow 0, 0, 1
    Print "delete row 0, then row 0 of ch1:"
    Dump 0, 0, 1
    Undo
    Dump 0, 0, 1
    ' cut, mix paste
    EdCut 0, 8, 10, 1, 1
    Check "cut cleared", cPer(CellIdx(0, 8, 1)) = 0
    EdPaste 0, 8, 2, True
    Print "mix paste into ch2:"
    Dump 0, 8, 10
    ' interpolate a volume slide C00..C40
    EdDigit 0, 20, 0, 3, &HC
    EdDigit 0, 24, 0, 3, &HC
    EdDigit 0, 24, 0, 4, 4
    EdInterpolate 0, 20, 24, 0, 0
    For i = 20 To 24: Print "  "; CellText(CellIdx(0, i, 0)); : Next i
    Print
    ' swap sample
    EdSwapSample 0, 0, 63, 0, 3, 1, 5
    Check "sample swap", cSmp(CellIdx(0, 8, 2)) = 5 Or cSmp(CellIdx(0, 9, 2)) = 5
    ' order list
    EdInsertOrder 1, 3
    EdInsertOrder 2, 1
    Print "orders:"; songLen; orders(0); orders(1); orders(2); " patterns"; nPat
    EdDeleteOrder 0
    Print "orders:"; songLen; orders(0); orders(1)
    Undo
    Print "orders:"; songLen; orders(0); orders(1); orders(2)
    Print "free pattern:"; FreePattern()
    ' song settings
    EdTitle "Undo Me"
    Check "speed/tempo into row 0", EdSpeedTempo(4, 140)
    Print "  row 0: "; RowText(orders(0), 0); " ->"; initSpeed; initTempo
    Undo
    Print "["; TitleText(); "]"; initSpeed; initTempo
    Undo
    Print "["; TitleText(); "]"
    ' samples
    Dim d() As Byte
    ReDim d(0 To 999)
    For i = 0 To 999: d(i) = (i * 3) And 255: Next i
    EdSampleData 1, "load", d, 1000
    EdSampleParams 1, 50, 15, 100, 2000
    Print "smp1 len"; smpLen(1); "vol"; smpVol(1); "fine"; FineSigned(1); "loop"; smpLoopS(1); smpLoopL(1)
    Undo
    Print "smp1 len"; smpLen(1); "vol"; smpVol(1); "loop"; smpLoopS(1); smpLoopL(1)
    Undo
    Print "smp1 len"; smpLen(1)
    ' a pattern only in no order still saves
    EdNote 7, 5, 0, 30, 1
    Check "save", SaveMod("edit.mod")
    Check "load", LoadMod("edit.mod")
    Check "pattern 7 kept", cPer(CellIdx(7, 5, 0)) = perOfNote(30)
    Print "patterns"; nPat; "length"; songLen
    Kill "edit.mod"
    ' 200-step undo limit
    For i = 1 To 250: EdNote 0, i Mod 64, 0, 13 + (i Mod 36), 1: Next i
    Check "undo capped at 200", UndoCount() = 200
End Sub
