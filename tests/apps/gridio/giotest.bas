' Gridwise file and chart tests
Option Explicit

Private Sub Put(ByVal a As String, ByVal src As String)
    Dim r As Long, c As Long
    ParseCellName a, r, c
    SetCell r, c, src
End Sub

Private Function Show(ByVal a As String) As String
    Dim r As Long, c As Long
    ParseCellName a, r, c
    Show = CellText(r, c)
End Function

Private Function FileText(ByVal p As String) As String
    Dim fn As Integer, s As String
    fn = FreeFile
    Open p For Binary As #fn
    s = Space$(LOF(fn))
    Get #fn, , s
    Close #fn
    FileText = s
End Function

Sub Main()
    Dim cv As Object, ok As Boolean, i As Long
    NewSheet 100, 26
    ClearCharts
    Put "A1", "Month": Put "B1", "Apples": Put "C1", "Pears"
    Put "A2", "Jan": Put "B2", "12": Put "C2", "7"
    Put "A3", "Feb": Put "B3", "18": Put "C3", "9"
    Put "A4", "Mar": Put "B4", "9": Put "C4", "14"
    Put "A5", "Apr": Put "B5", "-4": Put "C5", "11"
    Put "A6", "Total": Put "B6", "=SUM(B2:B5)": Put "C6", "=SUM(C2:C5)"
    Put "D1", "Note, with ""quotes"""
    SetFormat 5, 1, NF_FIX2 Or FMT_BOLD
    colW(0) = 90
    AddChart CH_BAR, "A1:C5", "Fruit sold"
    AddChart CH_PIE, "A1:B4", "Apples"
    ok = SaveGws("t.gws")
    Print "saved "; ok
    Print FileText("t.gws");
    NewSheet 10, 5
    ok = LoadGws("t.gws")
    Print "loaded "; ok; " "; NR; "x"; NC; " B6="; Show("B6"); " C6="; Show("C6"); " charts "; NCharts; " "; chRange(0); " "; chTitle(1); " w "; colW(0)
    Print "modified "; Modified
    ' CSV
    ok = ExportCsv("t.csv", ",")
    Print FileText("t.csv");
    ok = ImportCsv("t.csv")
    Print "csv back: B6="; Show("B6"); " D1="; Show("D1"); " A6="; Show("A6")
    NewSheet 20, 10
    i = CsvIntoSheet("x;y" & vbCrLf & "1;""2;3""" & vbCrLf & """multi" & vbLf & "line"";=1+1" & vbCrLf, GuessSeparator("x;y"), 0, 0, False)
    Print "rows "; i; " A2="; Show("A2"); " B2="; Show("B2"); " A3="; Replace(Show("A3"), vbLf, "|"); " B3="; Show("B3")
    Print "sep tab "; (GuessSeparator("a" & vbTab & "b,c" & vbTab & "d") = vbTab)
    Print "tsv: "; Replace(RangeAsText(0, 0, 1, 1), vbTab, "|");
    ' charts drawn off-screen
    LoadGws "t.gws"
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 200
    For i = 0 To NCharts - 1
        cv.Cls RGB(200, 200, 200)
        DrawChart cv, i, 0, 0, 320, 200
        Print "chart "; i; " "; ChartTypeName(chType(i)); " hash "; Hex$(cv.Hash)
        If Command$ = "shot" Then cv.SaveImage "chart" & i & ".ppm"
    Next i
    cv.Cls
    DrawChartOf cv, CH_LINE, "A1:C5", "Lines", 0, 0, 320, 200
    Print "line hash "; Hex$(cv.Hash)
    If Command$ = "shot" Then cv.SaveImage "chart2.ppm"
    cv.Cls
    DrawChartOf cv, CH_BAR, "Z1:Z5", "Empty", 0, 0, 320, 200
    Print "empty hash "; Hex$(cv.Hash)
    Kill "t.gws": Kill "t.csv"
End Sub
