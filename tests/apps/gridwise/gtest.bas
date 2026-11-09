' Tests of the Gridwise sheet engine
Option Explicit

Private Sub Put(ByVal a As String, ByVal src As String)
    Dim r As Long, c As Long
    If Not ParseCellName(a, r, c) Then Print "bad name "; a: Exit Sub
    SetCell r, c, src
End Sub

Private Function Show(ByVal a As String) As String
    Dim r As Long, c As Long
    ParseCellName a, r, c
    Show = CellText(r, c)
End Function

Private Sub T(ByVal formula As String)
    Put "Z100", formula
    Print formula; " -> "; Show("Z100");
    If LastError <> "" Then Print "  ["; LastError; "]" Else Print
End Sub

Sub Main()
    NewSheet 200, 26
    Put "A1", "10": Put "A2", "20": Put "A3", "30.5": Put "A4", "text": Put "A5", "TRUE"
    Put "B1", "=A1*2": Put "B2", "=B1+A2": Put "B3", "=SUM(A1:A3)"
    Print "B1="; Show("B1"); " B2="; Show("B2"); " B3="; Show("B3")
    Put "A1", "100"
    Print "after A1=100: B1="; Show("B1"); " B2="; Show("B2"); " B3="; Show("B3"); " recalc="; RecalcCount
    ' expressions
    T "=1+2*3"
    T "=(1+2)*3"
    T "=2^3^2"
    T "=-2^2"
    T "=10/4"
    T "=1/0"
    T "=50%"
    T "=""a""&""b""&1"
    T "=1<2"
    T "=""abc""=""ABC"""
    T "=A4+1"
    T "=A5+1"
    T "=SUM(A1:A5)"
    T "=AVERAGE(A1:A3)"
    T "=MIN(A1:A3)"
    T "=MAX(A1:A3, 500)"
    T "=COUNT(A1:A5)"
    T "=COUNTA(A1:A10)"
    T "=COUNTBLANK(A1:A10)"
    T "=IF(A1>50, ""big"", ""small"")"
    T "=IF(A1<50, 1/0, 7)"
    T "=IF(0, 1)"
    T "=ROUND(2.5, 0)"
    T "=ROUND(-2.5, 0)"
    T "=ROUND(3.14159, 2)"
    T "=ROUNDUP(3.141, 1)"
    T "=ROUNDDOWN(-3.19, 1)"
    T "=ABS(-4)"
    T "=SQRT(16)"
    T "=SQRT(-1)"
    T "=INT(-3.5)"
    T "=MOD(-7, 3)"
    T "=POWER(2, 10)"
    T "=PI()"
    T "=LEN(""hello"")"
    T "=LEFT(""hello"", 2)&RIGHT(""hello"")"
    T "=MID(""spreadsheet"", 7, 5)"
    T "=UPPER(""abc"")&LOWER(""DEF"")"
    T "=TRIM(""  a   b  "")"
    T "=CONCATENATE(""x"", A1, ""y"")"
    T "=CONCAT(A1:A3)"
    T "=TEXT(1234.5, ""#,##0.00"")"
    T "=VALUE(""12.5"")+1"
    T "=AND(1, TRUE, A1>5)"
    T "=OR(0, FALSE)"
    T "=NOT(A1=100)"
    T "=PRODUCT(2, 3, 4)"
    T "=SUMIF(A1:A3, "">15"")"
    T "=COUNTIF(A1:A5, ""text"")"
    T "=AVERAGEIF(A1:A3, ""<>20"")"
    T "=IFERROR(1/0, ""oops"")"
    T "=ISNUMBER(A1)&ISTEXT(A4)&ISBLANK(A9)"
    T "=MEDIAN(5, 1, 3, 2)"
    T "=STDEV(2, 4, 4, 4, 5, 5, 7, 9)"
    T "=SIGN(-3)+EXP(0)+LN(1)+LOG10(1000)"
    T "=FIND(""ea"", ""spreadsheet"")"
    T "=SUBSTITUTE(""a-b-c"", ""-"", ""+"")"
    T "=REPT(""ab"", 3)"
    T "=EXACT(""a"", ""A"")"
    T "=ROWS(A1:B7)*10+COLUMNS(A1:C1)"
    T "=CHOOSE(2, ""one"", ""two"", ""three"")"
    T "=TRUNC(-8.9)"
    T "=YEAR(DATE(2026,11,8))*10000+MONTH(DATE(2026,11,8))*100+DAY(DATE(2026,11,8))"
    T "=1+"
    T "=FOO(1)"
    T "=SUM(1,2"
    T "=#REF!+1"
    T "=A1:A3"
    T "=A1"
    ' VLOOKUP
    Put "D1", "apple": Put "E1", "1.5"
    Put "D2", "banana": Put "E2", "0.25"
    Put "D3", "cherry": Put "E3", "4"
    T "=VLOOKUP(""banana"", D1:E3, 2, FALSE)"
    T "=VLOOKUP(""kiwi"", D1:E3, 2, FALSE)"
    Put "F1", "10": Put "G1", "a": Put "F2", "20": Put "G2", "b": Put "F3", "30": Put "G3", "c"
    T "=VLOOKUP(25, F1:G3, 2)"
    ' circular references
    Put "H1", "=H2+1": Put "H2", "=H1+1"
    Print "circular: H1="; Show("H1"); " H2="; Show("H2")
    Put "H2", "5"
    Print "fixed: H1="; Show("H1"); " H2="; Show("H2")
    Put "H3", "=H3"
    Print "self: H3="; Show("H3")
    ' a long chain, recalculated in order
    Dim i As Long
    BeginBatch
    Put "J1", "1"
    For i = 2 To 200
        Put "J" & i, "=J" & (i - 1) & "+1"
    Next i
    EndBatch
    Print "chain J200="; Show("J200")
    Put "J1", "1000"
    Print "chain J200="; Show("J200"); " recalc="; RecalcCount
    ' a running total over ranges
    For i = 1 To 50
        Put "K" & i, CStr(i)
        Put "L" & i, "=SUM($K$1:K" & i & ")"
    Next i
    Print "running L50="; Show("L50")
    Put "K1", "101"
    Print "running L50="; Show("L50"); " recalc="; RecalcCount
    ' formats
    Put "M1", "1234.5678"
    Dim f As Long
    For f = 0 To NF_LAST
        SetFormat 0, 12, f
        Print NumFormatName(f); ": "; Show("M1")
    Next f
    Put "M2", "15%": Print "15% -> "; Show("M2"); " fmt "; GetFormat(1, 12)
    Put "M3", "1,234": Print "1,234 -> "; Show("M3")
    Put "M4", "$5": Print "$5 -> "; Show("M4")
    Put "M5", "-0.000012345": Print "small -> "; Show("M5")
    Put "M6", "=1/3": Print "1/3 -> "; Show("M6")
    Put "M7", "123456789012": Print "big -> "; Show("M7")
    Put "M8", "'123": Print "'123 -> "; Show("M8"); " kind "; CellKind(7, 12)
    ' moving references
    Print AdjustFormula("=A1+$B$2+C$3+$D4+SUM(A1:B2)&""A1""", 2, 1)
    Print AdjustFormula("=A1+1", -1, 0)
    Print ShiftFormula("=A1+A5+SUM(A2:A9)", False, 2, 3)
    Print ShiftFormula("=A1+A5+B3", False, 2, -2)
    Print ShiftFormula("=A1+C1+$D$1", True, 1, 1)
    ' copy / paste
    ClearRange 0, 0, 199, 25
    Put "A1", "1": Put "A2", "2": Put "B1", "=A1*10"
    CopyRange 0, 1, 0, 1, False
    PasteAt 1, 1, 1, 1
    Print "paste: B2="; Show("B2"); " src "; GetSrc(1, 1)
    PasteAt 2, 1, 3, 1
    Print "fill-paste: B3..B5 src "; GetSrc(2, 1); " "; GetSrc(3, 1); " "; GetSrc(4, 1)
    FillDown 0, 1, 5, 1
    Print "filldown B6 src "; GetSrc(5, 1)
    ' undo / redo
    Put "C1", "5"
    Put "C1", "6"
    Undo
    Print "undo: C1="; Show("C1")
    Undo
    Print "undo: C1="; Show("C1")
    Redo
    Print "redo: C1="; Show("C1")
    InsertRowsCols False, 0, 1
    Print "insert row: B2 src "; GetSrc(1, 1); " A2="; Show("A2")
    Undo
    Print "undo insert: B1 src "; GetSrc(0, 1); " A1="; Show("A1")
    Redo
    Print "redo insert: B2 src "; GetSrc(1, 1)
    Undo
    ' sort
    ClearRange 0, 0, 199, 25
    ClearUndo
    Put "A1", "pear": Put "B1", "3"
    Put "A2", "apple": Put "B2", "1"
    Put "A3", "fig": Put "B3", "2"
    Put "A4", "": Put "B4", "0"
    SortRange 0, 0, 3, 1, 1, True
    Print "sort by B: "; Show("A1"); " "; Show("A2"); " "; Show("A3"); " "; Show("A4")
    SortRange 0, 0, 3, 1, 0, False
    Print "sort by A desc: "; Show("A1"); " "; Show("A2"); " "; Show("A3"); " ["; Show("A4"); "]"
    ' serialize round trip
    Put "C1", "=SUM(B1:B4)": Put "C2", "tab" & vbTab & "x\y"
    SetFormat 0, 2, NF_FIX2 Or FMT_BOLD
    colW(2) = 120
    Dim body As String, rest As String
    body = SerializeSheet()
    Print body;
    NewSheet 200, 26
    LoadLines body & "X" & vbTab & "extra" & vbLf, rest
    Print "loaded C1="; Show("C1"); " fmt "; GetFormat(0, 2); " C2 ok "; (GetSrc(1, 2) = "tab" & vbTab & "x\y"); " W="; colW(2); " rest "; rest;
    Print "done"
End Sub
