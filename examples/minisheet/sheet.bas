' MiniSheet - a small spreadsheet in Boing BASIC (docs/ui.md): a Grid with editable cells and
' "=SUM(A1:A9)"-style formulas, a TreeView of sheets, tabs, a ListBrowser summary with sortable
' columns, a splitter, menus and a status bar.
Option Explicit

Private Const NSHEETS = 3
Private data(1 To NSHEETS) As String       ' each sheet's cells as "r,c=text" lines
Private current As Integer
Private formulas() As String                ' the current sheet's raw cell texts

Private Sub Form_Load()
    Dim i As Integer
    sheets.AddNode "book", "", "Workbook"
    For i = 1 To NSHEETS
        sheets.AddNode "s" & i, "book", "Sheet " & i
    Next
    sheets.Expand "book"
    ReDim formulas(grid.Rows - 1, grid.Cols - 1)
    current = 1
    sheets.SelectedKey = "s1"
    grid.TextMatrix(1, 1) = "10"
    grid.TextMatrix(2, 1) = "20"
    grid.TextMatrix(3, 1) = "12.5"
    SetCell 4, 1, "=SUM(A1:A3)"
    ShowCellRef
    If Environ("BOING_SMOKE") <> "" Then smoke.Interval = 1500
End Sub

' --- cells and formulas --------------------------------------------------------------------

Private Function ColName(c As Integer) As String
    ColName = Chr(64 + c)
End Function

Private Sub ShowCellRef()
    cellRef.Text = ColName(grid.Col) & grid.Row
    formula.Text = formulas(grid.Row, grid.Col)
    If formula.Text = "" Then formula.Text = grid.TextMatrix(grid.Row, grid.Col)
End Sub

' "B3" -> row 3, col 2
Private Function ParseRef(ref As String, r As Integer, c As Integer) As Boolean
    ref = UCase(Trim(ref))
    If Len(ref) < 2 Then Exit Function
    c = Asc(ref) - 64
    r = Val(Mid(ref, 2))
    ParseRef = c >= 1 And c < grid.Cols And r >= 1 And r < grid.Rows
End Function

Private Function Evaluate(f As String) As String
    Dim u As String, p As Integer, a As String, b As String
    Dim r1 As Integer, c1 As Integer, r2 As Integer, c2 As Integer, r As Integer, c As Integer
    Dim total As Double, n As Long
    u = UCase(f)
    If Left(u, 5) = "=SUM(" Or Left(u, 9) = "=AVERAGE(" Then
        p = InStr(u, "(")
        a = Mid(u, p + 1, InStr(u, ":") - p - 1)
        b = Mid(u, InStr(u, ":") + 1)
        b = Left(b, Len(b) - 1)
        If Not ParseRef(a, r1, c1) Or Not ParseRef(b, r2, c2) Then Evaluate = "#REF": Exit Function
        For r = r1 To r2
            For c = c1 To c2
                If IsNumeric(grid.TextMatrix(r, c)) Then total = total + Val(grid.TextMatrix(r, c)): n = n + 1
            Next
        Next
        If Left(u, 5) = "=SUM(" Then Evaluate = CStr(total) Else If n Then Evaluate = CStr(total / n) Else Evaluate = "0"
    Else
        Evaluate = "#NAME"
    End If
End Function

Private Sub SetCell(r As Integer, c As Integer, t As String)
    formulas(r, c) = IIf(Left(t, 1) = "=", t, "")
    If Left(t, 1) = "=" Then grid.TextMatrix(r, c) = Evaluate(t) Else grid.TextMatrix(r, c) = t
End Sub

Private Sub Recalc()
    Dim r As Integer, c As Integer
    grid.Redraw = False
    For r = 1 To grid.Rows - 1
        For c = 1 To grid.Cols - 1
            If formulas(r, c) <> "" Then grid.TextMatrix(r, c) = Evaluate(formulas(r, c))
        Next
    Next
    grid.Redraw = True
    UpdateSum
End Sub

Private Sub UpdateSum()
    Dim r As Integer, c As Integer, t As Double
    For r = grid.SelStartRow To grid.SelEndRow
        For c = grid.SelStartCol To grid.SelEndCol
            If IsNumeric(grid.TextMatrix(r, c)) Then t = t + Val(grid.TextMatrix(r, c))
        Next
    Next
    sb.Panel(1) = "Sum: " & t
End Sub

Private Sub grid_EnterCell()
    ShowCellRef
    UpdateSum
End Sub

Private Sub grid_AfterEdit(Row As Long, Col As Long)
    ' typed into the cell: a formula is kept and its value shown
    SetCell CInt(Row), CInt(Col), grid.TextMatrix(Row, Col)
    Recalc
    ShowCellRef
End Sub

Private Sub formula_KeyPress(KeyAscii As Integer)
    Dim r As Integer, c As Integer
    If KeyAscii <> 13 Then Exit Sub
    If ParseRef(cellRef.Text, r, c) Then
        SetCell r, c, formula.Text
        Recalc
    End If
End Sub

Private Sub cellRef_KeyPress(KeyAscii As Integer)
    Dim r As Integer, c As Integer
    If KeyAscii = 13 And ParseRef(cellRef.Text, r, c) Then
        grid.Row = r
        grid.Col = c
    End If
End Sub

' --- sheets (TreeView) ----------------------------------------------------------------------

Private Sub SaveSheet()
    Dim r As Integer, c As Integer, s As String
    For r = 1 To grid.Rows - 1
        For c = 1 To grid.Cols - 1
            If formulas(r, c) <> "" Then
                s = s & r & "," & c & "=" & formulas(r, c) & vbLf
            ElseIf grid.TextMatrix(r, c) <> "" Then
                s = s & r & "," & c & "=" & grid.TextMatrix(r, c) & vbLf
            End If
        Next
    Next
    data(current) = s
End Sub

Private Sub LoadSheet(i As Integer)
    Dim lines() As String, k As Integer, eq As Integer, comma As Integer
    grid.Redraw = False
    grid.Clear
    ReDim formulas(grid.Rows - 1, grid.Cols - 1)
    lines = Split(data(i), vbLf)
    For k = 0 To UBound(lines)
        eq = InStr(lines(k), "=")
        comma = InStr(lines(k), ",")
        If eq > 0 And comma > 0 Then SetCell CInt(Left(lines(k), comma - 1)), CInt(Mid(lines(k), comma + 1, eq - comma - 1)), Mid(lines(k), eq + 1)
    Next
    current = i
    grid.Redraw = True
    Recalc
End Sub

Private Sub sheets_NodeClick()
    Dim k As String
    k = sheets.SelectedKey
    If Left(k, 1) <> "s" Then Exit Sub
    If Val(Mid(k, 2)) = current Then Exit Sub
    SaveSheet
    LoadSheet Val(Mid(k, 2))
    sb.Text = "Sheet " & current
End Sub

' --- summary tab (ListBrowser with columns) -------------------------------------------------

Private Sub FillSummary()
    Dim c As Integer, r As Integer, n As Long, t As Double
    summary.Clear
    For c = 1 To grid.Cols - 1
        n = 0: t = 0
        For r = 1 To grid.Rows - 1
            If IsNumeric(grid.TextMatrix(r, c)) Then n = n + 1: t = t + Val(grid.TextMatrix(r, c))
        Next
        If n Then summary.AddItem ColName(c) & vbTab & n & vbTab & t & vbTab & Format(t / n, "0.00")
    Next
End Sub

Private Sub pages_Click()
    If pages.Tab = 1 Then FillSummary
End Sub

Private Sub refresh_Click(): FillSummary: End Sub

' --- menus ----------------------------------------------------------------------------------

Private Sub mnuClear_Click()
    If MsgBox("Clear the sheet?", vbYesNo + vbQuestion) = vbYes Then
        grid.Clear
        ReDim formulas(grid.Rows - 1, grid.Cols - 1)
    End If
End Sub

Private Sub mnuExport_Click()
    Dim d As Object, f As Integer, r As Integer, c As Integer, line As String
    Set d = CreateObject("Boing.CommonDialog")
    d.DialogTitle = "Export as text"
    d.Filter = "#?.txt"
    d.Flags = cdlOFNOverwritePrompt
    d.ShowSave
    If d.Cancelled Then Exit Sub
    f = FreeFile
    Open d.FileName For Output As #f
    For r = 1 To grid.Rows - 1
        line = ""
        For c = 1 To grid.Cols - 1
            line = line & grid.TextMatrix(r, c) & IIf(c < grid.Cols - 1, vbTab, "")
        Next
        If Replace(line, vbTab, "") <> "" Then Print #f, line
    Next
    Close #f
    sb.Text = "Exported " & d.FileName
End Sub

Private Sub mnuQuit_Click(): Unload Me: End Sub
Private Sub mnuBold_Click(): grid.CellBold = Not grid.CellBold: End Sub
Private Sub mnuRed_Click(): grid.CellForeColor = vbRed: End Sub
Private Sub mnuYellow_Click(): grid.CellBackColor = vbYellow: End Sub

Private Sub mnuPlain_Click()
    grid.CellBold = False
    grid.CellForeColor = vbBlack
    grid.CellBackColor = vbWhite
End Sub

' --- BOING_SMOKE=1 --------------------------------------------------------------------------

Private Sub smoke_Timer()
    smoke.Enabled = False
    Print IIf(grid.TextMatrix(4, 1) = "42.5" And sheets.NodeCount = 4 And pages.TabCount = 2, "PASS", "FAIL " & grid.TextMatrix(4, 1))
    Unload Me
End Sub
