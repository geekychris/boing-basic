' Gridwise commands and grid drawing
Option Explicit

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
    Dim cv As Object, errs As Long, r As Long, c As Long, e As Boolean, k As Boolean
    NewSheet 1000, 26
    ClearCharts
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 660, 420
    ViewInit 660, 420
    errs = RunScript(FileText("budget.gwr"), True)
    Print LogLines;
    Print "errors "; errs
    chW(0) = 300: chH(0) = 190
    DrawGrid cv
    Print "grid hash "; Hex$(cv.Hash)
    If Command$ = "shot" Then cv.SaveImage "grid.ppm"
    ' navigation and hit testing
    MoveCursor 50, 3, False
    Print "cursor D51: top "; topRow; " visible rows "; VisibleRows(); " cols "; VisibleCols()
    MoveCursor 50, 25, True
    Print "selection "; SelName(); " left col "; leftCol
    MoveCursor 0, 0, False
    Print "hit (45,20) "; HitTest(45, 20, r, c, e); r; c; e
    Print "hit (5,5) "; HitTest(5, 5, r, c, e); r; c; e
    Print "hit edge "; HitTest(RHDR_W + 96 - 1, 5, r, c, e); r; c; e
    Print "chart at "; ChartAt(ColX(chCol(0)) + 10, RowY(chRow(0)) + 10, k); k
    ' row heights
    LogLines = ""
    RunScript "ROWHEIGHT 3 30" & vbLf & "ROWHEIGHT 3" & vbLf & "ROWHEIGHT 0 9" & vbLf & "SELECT A1", True
    Print LogLines;
    DrawGrid cv
    Print "tall row hash "; Hex$(cv.Hash); " RowY(4) "; RowY(4); " visible "; VisibleRows()
    Print "hit in row 3: "; HitTest(60, HDR_H + 15 + 15 + 20, r, c, e); r; c
    Print "row edge at row 3 bottom: "; RowEdgeAt(10, HDR_H + 60); " none: "; RowEdgeAt(10, HDR_H + 37)
    Print "saved: "; (InStr(SerializeSheet(), "R" & vbTab & "3" & vbTab & "30") > 0)
    ' errors from commands
    LogLines = ""
    RunScript "SETCELL A1 =SUM(" & vbLf & "FOO" & vbLf & "SELECT ZZ" & vbLf & "FORMAT weird" & vbLf & "GETFORMULA A1" & vbLf & "UNDO" & vbLf & "GETCELL A1" & vbLf & "FIND transport" & vbLf & "SORT B DESC" & vbLf & "VERSION", True
    Print LogLines;
End Sub
