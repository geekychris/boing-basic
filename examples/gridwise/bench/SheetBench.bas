' Gridwise engine benchmark: a 1000 x 26 sheet of formulas.
'   column A numbers, B..Y each =<left>*1.01+<two left> (or similar), Z = SUM(A:Y) of the row,
'   then a totals block. Times: entering all cells (parse + compile), a full recalculation,
'   an edit of A1 (its row), an edit that changes a whole column's sum chain, and formatting
'   the text of one screen of cells (40 x 10).
Option Explicit

Sub Main()
    Dim t0 As Double, r As Long, c As Long, i As Long, s As String, n As Long, rows As Long
    rows = 1000
    If Command$ <> "" Then rows = Val(Command$)
    NewSheet rows + 2, 26
    t0 = Timer
    BeginBatch
    For r = 0 To rows - 1
        SetCell r, 0, CStr(r + 1)
        SetCell r, 1, "=A" & (r + 1) & "*2"
        For c = 2 To 24
            SetCell r, c, "=" & ColName(c - 1) & (r + 1) & "+" & ColName(c - 2) & (r + 1) & "*0.5"
        Next c
        SetCell r, 25, "=SUM(A" & (r + 1) & ":Y" & (r + 1) & ")"
    Next r
    For c = 0 To 25
        SetCell rows, c, "=SUM(" & ColName(c) & "1:" & ColName(c) & rows & ")"
    Next c
    SetCell rows + 1, 0, "=AVERAGE(Z1:Z" & rows & ")"
    t0 = Timer - t0
    ' (the EndBatch below does the first full recalculation)
    Print "enter "; NCELLS - 25; " cells: "; Format$(t0 * 1000, "0"); " ms"
    t0 = Timer
    EndBatch
    Print "first recalc: "; Format$((Timer - t0) * 1000, "0"); " ms, "; RecalcCount; " formulas"
    t0 = Timer
    RecalcAll
    Print "full recalc: "; Format$((Timer - t0) * 1000, "0"); " ms, "; RecalcCount; " formulas"
    t0 = Timer
    For i = 1 To 10
        SetCell 0, 0, CStr(i)
    Next i
    Print "edit A1 (x10): "; Format$((Timer - t0) * 100, "0.0"); " ms each, "; RecalcCount; " formulas"
    t0 = Timer
    For i = 1 To 10
        SetCell rows \ 2, 0, CStr(i * 7)
    Next i
    Print "edit A"; rows \ 2 + 1; " (x10): "; Format$((Timer - t0) * 100, "0.0"); " ms each, "; RecalcCount; " formulas"
    t0 = Timer
    For i = 1 To 20
        For r = 0 To 39
            For c = 0 To 9
                s = CellText(r + i * 10, c)
                n = n + Len(s)
            Next c
        Next r
    Next i
    Print "cell text, 40x10 screen: "; Format$((Timer - t0) * 1000 / 20, "0.0"); " ms"
    Print "Z1="; CellText(0, 25); " Z"; rows + 1; "="; CellText(rows, 25); " A"; rows + 2; "="; CellText(rows + 1, 0)
End Sub
