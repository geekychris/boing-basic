' gridwise.bas - the code-behind of gridwise.afg: Gridwise's main window.
'
' The grid is drawn on the canvas by GridView.bas. Keys: cursor keys move (Shift extends
' the selection, Shift+Up/Down a page, Alt+cursor to the edges), typing starts editing in the
' formula bar (Return enters and moves down, Tab right), Del clears, F2 edits the cell.
' Amiga-key shortcuts as in the menus (see Gridwise.guide).
'
' Command line: Gridwise [file.gws|file.csv] [--script file] [--log file]
'   --script runs a command file (Script.bas commands, one per line) once the window is open,
'   writes the results to --log (default file.log) and quits at QUIT: the guest smoke test
'   uses this. "PAUSE n [tag]" in a script waits n seconds (the log then ends with
'   "paused tag", so a test can take a screenshot).
Option Explicit

Private settingText As Boolean        ' formula.Text set by code: ignore its Change
Private editing As Boolean            ' the formula bar holds an edit of the cursor cell
Private lastStatus As String
Private lastCellName As String
Private lastFind As String
Private clipText As String
Private dragMode As Long              ' 1 cells, 2 column width, 3 move chart, 4 size chart, 5 columns, 6 rows
Private dragX As Long, dragY As Long, dragW As Long, dragH As Long, dragCol As Long
Private scriptLog As String
Private autosaveTicks As Long
Private Const AUTOSAVE_SECS As Long = 120
Private Const TICKS_PER_SEC As Long = 4     ' the timer runs every 250 ms
Private scriptLines() As String
Private scriptPos As Long
Private scriptWait As Long                  ' ticks before the script goes on
Private scriptActive As Boolean

Private Sub Form_Load()
    Dim args As String, p As Long, f As String, scr As String
    LoadPrefs "Gridwise.prefs"
    NewSheet 1000, 26
    ClearCharts
    ViewInit grid.Width, grid.Height
    ShowGridLines = PrefGridLines
    mnuGridLines.Checked = PrefGridLines
    mnuAutosave.Checked = PrefAutosave
    args = Trim$(Command$)
    Do While args <> ""
        If Left$(args, 1) = Chr$(34) Then
            p = InStr(2, args, Chr$(34))
            If p = 0 Then p = Len(args) + 1
            f = Mid$(args, 2, p - 2)
            args = Trim$(Mid$(args, p + 1))
        Else
            p = InStr(args, " ")
            If p = 0 Then p = Len(args) + 1
            f = Left$(args, p - 1)
            args = Trim$(Mid$(args, p + 1))
        End If
        If f = "--script" Or f = "--log" Then
            p = InStr(args & " ", " ")
            If f = "--script" Then scr = Left$(args, p - 1) Else scriptLog = Left$(args, p - 1)
            args = Trim$(Mid$(args, p))
        ElseIf f <> "" Then
            RunCommand "OPEN " & f
            If ScriptRC <> 0 Then MsgBox "Can't open " & f & ": " & IOError, vbExclamation Else AddRecent f
        End If
    Loop
    UpdateRecent
    UpdateTitle
    Redraw
    If scr <> "" Then RunScriptFile scr
End Sub

' read a script; the timer runs it once the window is open
Private Sub RunScriptFile(ByVal path As String)
    Dim fn As Integer, s As String, line_ As String
    If scriptLog = "" Then scriptLog = path & ".log"
    On Error GoTo Failed
    fn = FreeFile
    Open path For Input As #fn
    Do While Not EOF(fn)
        Line Input #fn, line_
        s = s & line_ & vbLf
    Loop
    Close #fn
    LogLines = ""
    scriptLines = Split(Replace(s, vbCr, ""), vbLf)
    scriptPos = 0
    scriptWait = TICKS_PER_SEC
    scriptActive = True
    Exit Sub
Failed:
    LogLines = "can't read script " & path & ": " & Err.Description & vbLf
    WriteLog "ok"
End Sub

' run script lines until a PAUSE or the end, redrawing and honouring SHOT/QUIT between them
Private Sub StepScript()
    Dim res As String, l As String, w() As String
    Do While scriptPos <= UBound(scriptLines)
        l = Trim$(scriptLines(scriptPos))
        scriptPos = scriptPos + 1
        If l <> "" And Left$(l, 1) <> ";" Then
            If UCase$(Left$(l, 6)) = "PAUSE " Then
                w = Split(l & " ", " ")
                scriptWait = Val(w(1)) * TICKS_PER_SEC
                If scriptWait < 1 Then scriptWait = 1
                WriteLog "paused " & Trim$(Mid$(l, 7 + Len(w(1))))
                Exit Sub
            End If
            res = RunCommand(l)
            LogLines = LogLines & l & " -> " & res
            If ScriptRC > 0 Then LogLines = LogLines & " [rc " & ScriptRC & "]"
            LogLines = LogLines & vbLf
            AfterCommand
            If WantQuit Then Exit Do
        End If
    Loop
    scriptActive = False
    WriteLog "ok"
    If WantQuit Then Unload Me
End Sub

Private Sub WriteLog(ByVal last As String)
    Dim fn As Integer
    If scriptLog = "" Then Exit Sub
    On Error Resume Next
    fn = FreeFile
    Open scriptLog For Output As #fn
    Print #fn, LogLines;
    Print #fn, last
    Close #fn
End Sub

' after any command: redraw, screenshots
Private Sub AfterCommand()
    If WantRedraw Then Redraw
    If WantShot <> "" Then
        grid.SaveImage WantShot
        WantShot = ""
    End If
    UpdateTitle
End Sub

Private Sub UpdateTitle()
    Dim t As String
    If DocPath = "" Then t = "Untitled" Else t = DocPath
    If Modified Then t = t & " *"
    t = "Gridwise - " & t
    If Me.Caption <> t Then Me.Caption = t
End Sub

' (labels first: setting a label's text re-lays the window out, which wipes the canvas)
Private Sub Redraw()
    UpdateBars
    DrawGrid grid
    grid.Refresh
End Sub

Private Sub ShowStatus(ByVal s As String)
    status.Caption = s
    lastStatus = s
    grid.Refresh
End Sub

' the cell name, the formula bar and the status line
Private Sub UpdateBars()
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long, s As String, sum As Double, cnt As Long, r As Long, c As Long
    If SelName() <> lastCellName Then lastCellName = SelName(): cellname.Caption = lastCellName
    If Not editing Then
        If formula.Text <> GetSrc(curR, curC) Then
            settingText = True
            formula.Text = GetSrc(curR, curC)
            settingText = False
        End If
    End If
    SelBounds r1, c1, r2, c2
    If r1 <> r2 Or c1 <> c2 Then
        If (r2 - r1 + 1) * (c2 - c1 + 1) <= 20000 Then
            For r = r1 To r2
                For c = c1 To c2
                    If CellKind(r, c) = KNUM Then sum = sum + CellNum(r, c): cnt = cnt + 1
                Next c
            Next r
        End If
        If cnt > 0 Then
            s = "Sum " & GeneralText(sum) & "   Average " & GeneralText(sum / cnt) & "   Count " & cnt
        Else
            s = (r2 - r1 + 1) & " x " & (c2 - c1 + 1) & " cells"
        End If
    ElseIf IsFormula(curR, curC) And LastError <> "" And CellKind(curR, curC) = KERR Then
        s = "Formula error: " & LastError
    Else
        s = CellText(curR, curC)
        If IsFormula(curR, curC) Then s = "= " & s
        If s = "" Then s = "Ready"
        s = s & "      " & NumFormatName(GetFormat(curR, curC) And 255)
    End If
    If editing Then s = "Editing " & CellName(curR, curC) & " - Return enters, Tab enters and moves right"
    If s <> lastStatus Then status.Caption = s: lastStatus = s
    If editing Then grid.Refresh
End Sub

' ---- editing -------------------------------------------------------------------------------

Private Sub StartEdit(ByVal initial As String)
    editing = True
    settingText = True
    formula.Text = initial
    settingText = False
    formula.SetFocus
    formula.SelStart = Len(initial)
    UpdateBars
End Sub

Private Sub CommitEdit(ByVal dr As Long, ByVal dc As Long)
    Dim t As String
    t = formula.Text
    editing = False
    If t <> GetSrc(curR, curC) Then
        SetCell curR, curC, t
    End If
    MoveCursor curR + dr, curC + dc, False
    Redraw
    UpdateTitle
End Sub

Private Sub formula_Change()
    If settingText Then Exit Sub
    If Not editing Then editing = True: UpdateBars
End Sub

Private Sub formula_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then
        CommitEdit 1, 0
    ElseIf KeyAscii = 9 Then
        CommitEdit 0, 1
    End If
End Sub

Private Sub enter_Click()
    CommitEdit 0, 0
End Sub

' ---- keys ----------------------------------------------------------------------------------

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim ext As Boolean, page As Long, amiga As Boolean
    ext = (Shift And 1) <> 0
    amiga = (Shift And 8) <> 0
    page = VisibleRows() - 1
    If amiga Then
        AmigaKey KeyCode, ext
        Exit Sub
    End If
    Select Case KeyCode
    Case vbKeyUp
        If (Shift And 4) <> 0 Then
            MoveCursor 0, curC, ext
        ElseIf ext And (Shift And 2) <> 0 Then
            MoveCursor curR - page, curC, False
        Else
            MoveCursor curR - 1, curC, ext
        End If
    Case vbKeyDown
        If (Shift And 4) <> 0 Then
            MoveCursor LastUsedRow(curC), curC, ext
        Else
            MoveCursor curR + 1, curC, ext
        End If
    Case vbKeyLeft
        If (Shift And 4) <> 0 Then MoveCursor curR, 0, ext Else MoveCursor curR, curC - 1, ext
    Case vbKeyRight
        If (Shift And 4) <> 0 Then MoveCursor curR, NC - 1, ext Else MoveCursor curR, curC + 1, ext
    Case vbKeyReturn
        StartEdit GetSrc(curR, curC)
        Exit Sub
    Case vbKeyTab
        If ext Then MoveCursor curR, curC - 1, False Else MoveCursor curR, curC + 1, False
    Case vbKeyDelete, vbKeyBack
        CmdClear
        Exit Sub
    Case vbKeyF2
        StartEdit GetSrc(curR, curC)
        Exit Sub
    Case vbKeyEscape
        selChart = -1
        ancR = curR: ancC = curC
    Case 47, vbKeyF1      ' Help
        CmdHelp
        Exit Sub
    Case 256 + &H48, vbKeyPageUp       ' PgUp on PC keyboards
        MoveCursor curR - page, curC, ext
    Case 256 + &H49, vbKeyPageDown
        MoveCursor curR + page, curC, ext
    Case 256 + &H70, vbKeyHome
        MoveCursor curR, 0, ext
    Case 256 + &H71, vbKeyEnd
        MoveCursor curR, LastUsedCol(curR), ext
    Case Else
        Exit Sub
    End Select
    Redraw
End Sub

Private Function LastUsedRow(ByVal c As Long) As Long
    Dim r As Long
    For r = NR - 1 To 0 Step -1
        If GetSrc(r, c) <> "" Then LastUsedRow = r: Exit Function
    Next r
End Function

Private Function LastUsedCol(ByVal r As Long) As Long
    Dim c As Long
    For c = NC - 1 To 0 Step -1
        If GetSrc(r, c) <> "" Then LastUsedCol = c: Exit Function
    Next c
End Function

Private Sub Form_KeyPress(KeyAscii As Integer)
    ' a character typed on the grid starts an edit with it
    If editing Then Exit Sub
    If KeyAscii >= 32 And KeyAscii <> 127 Then
        StartEdit Chr$(KeyAscii)
    End If
End Sub

' Amiga-key shortcuts (the same as the menus)
Private Sub AmigaKey(ByVal k As Integer, ByVal shifted As Boolean)
    Select Case k
    Case vbKeyN: CmdNew
    Case vbKeyO: CmdOpen
    Case vbKeyS: If shifted Then CmdSaveAs Else CmdSave
    Case vbKeyQ: CmdQuit
    Case vbKeyZ: If shifted Then Exec "REDO" Else Exec "UNDO"
    Case vbKeyY: Exec "REDO"
    Case vbKeyX: CmdCopy True
    Case vbKeyC: CmdCopy False
    Case vbKeyV: CmdPaste
    Case vbKeyD: Exec "FILLDOWN"
    Case vbKeyR: Exec "FILLRIGHT"
    Case vbKeyB: Exec "BOLD"
    Case vbKeyI: Exec "ITALIC"
    Case vbKeyF: CmdFind
    Case vbKeyG: CmdGoto
    Case vbKeyA: SelectRange 0, 0, NR - 1, NC - 1: Redraw
    Case vbKeyK: CmdChart
    Case vbKeyE: CmdExportCsv
    Case vbKeyL: Exec "SHOWFORMULAS " & IIf(ShowFormulas, "OFF", "ON")
    Case vbKey1: Exec "FORMAT GENERAL"
    Case vbKey2: Exec "FORMAT FIXED"
    Case vbKey3: Exec "FORMAT THOUSANDS2"
    Case vbKey4: Exec "FORMAT CURRENCY"
    Case vbKey5: Exec "FORMAT PERCENT"
    Case vbKey6: Exec "FORMAT DATE"
    Case vbKeyLeft: Exec "ALIGN LEFT"
    Case vbKeyRight: Exec "ALIGN RIGHT"
    Case vbKeyUp, vbKeyDown: Exec "ALIGN CENTER"
    Case 256 + &HC: AdjustWidth 8      ' Amiga + "=": wider
    Case 256 + &HB: AdjustWidth -8     ' Amiga + "-": narrower
    End Select
End Sub

' run a command and show its error, if any
Private Sub Exec(ByVal cmd As String)
    Dim res As String
    res = RunCommand(cmd)
    If ScriptRC >= 10 Then ShowStatus res: Beep
    AfterCommand
End Sub

Private Sub AdjustWidth(ByVal d As Long)
    Dim c As Long, r1 As Long, c1 As Long, r2 As Long, c2 As Long
    SelBounds r1, c1, r2, c2
    For c = c1 To c2
        Exec "COLWIDTH " & ColName(c) & " " & (colW(c) + d)
    Next c
End Sub

' ---- commands that ask the user -----------------------------------------------------------

Private Function AskFile(ByVal title As String, ByVal def As String) As String
    AskFile = Trim$(InputBox(title, "Gridwise", def))
End Function

Private Function ConfirmDiscard() As Boolean
    Dim a As Integer
    If Not Modified Then ConfirmDiscard = True: Exit Function
    a = MsgBox("The sheet has unsaved changes. Save them first?", vbYesNoCancel Or vbQuestion, "Gridwise")
    If a = vbCancel Then Exit Function
    If a = vbYes Then
        CmdSave
        If Modified Then Exit Function
    End If
    ConfirmDiscard = True
End Function

Private Sub CmdNew()
    If Not ConfirmDiscard() Then Exit Sub
    Exec "NEW"
End Sub

Private Sub CmdOpen()
    Dim f As String
    If Not ConfirmDiscard() Then Exit Sub
    f = AskFile("Open a sheet (.gws or .csv):", DocPath)
    If f = "" Then Exit Sub
    OpenFile f
End Sub

Private Sub OpenFile(ByVal f As String)
    Exec "OPEN " & f
    If ScriptRC = 0 Then AddRecent f: UpdateRecent
End Sub

Private Sub UpdateRecent()
    Dim i As Long, m As Object
    For i = 0 To 7
        Set m = Me.Controls("mnuRecent" & i)
        If i < NRecent Then
            If m.Caption <> Recent(i) Then m.Caption = Recent(i)
            If Not m.Enabled Then m.Enabled = True
            If Not m.Visible Then m.Visible = True
        ElseIf i > 0 Then
            If m.Visible Then m.Visible = False
        End If
    Next i
End Sub

Private Sub CmdSave()
    If DocPath = "" Then CmdSaveAs: Exit Sub
    Exec "SAVE " & DocPath
    If ScriptRC = 0 Then AddRecent DocPath: UpdateRecent
End Sub

Private Sub CmdSaveAs()
    Dim f As String
    f = AskFile("Save the sheet as:", IIf(DocPath = "", "RAM:Untitled.gws", DocPath))
    If f = "" Then Exit Sub
    If LCase$(Right$(f, 4)) <> ".gws" Then f = f & ".gws"
    Exec "SAVE " & f
    If ScriptRC = 0 Then AddRecent f: UpdateRecent
End Sub

Private Sub CmdExportCsv()
    Dim f As String
    f = AskFile("Export the values as CSV to:", "RAM:sheet.csv")
    If f = "" Then Exit Sub
    Exec "EXPORTCSV " & f
End Sub

Private Sub CmdClear()
    Exec "CLEAR"
End Sub

Private Sub CmdFind()
    Dim f As String
    f = InputBox("Find text in the cells:", "Gridwise", lastFind)
    If f = "" Then Exit Sub
    lastFind = f
    Redraw
    If FindNext(f, False) = "" Then ShowStatus "Not found: " & f Else Redraw
End Sub

Private Sub CmdGoto()
    Dim f As String
    f = InputBox("Go to cell or range (e.g. B12 or A1:C9):", "Gridwise", SelName())
    If f = "" Then Exit Sub
    Exec "SELECT " & f
End Sub

Private Sub CmdChart()
    Dim t As String, k As String
    k = InputBox("Chart the selection " & SelName() & " as: bar, line or pie", "Gridwise", "bar")
    If k = "" Then Exit Sub
    t = InputBox("Chart title:", "Gridwise", "")
    Exec "CHART " & k & " " & SelName() & " " & t
End Sub

Private Sub CmdHelp()
    Shell "run >NIL: SYS:Utilities/Multiview PROGDIR:Gridwise.guide"
End Sub

Private Sub CmdQuit()
    Unload Me
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If WantQuit Then Exit Sub
    If Not ConfirmDiscard() Then Cancel = True
End Sub

' ---- autosave ------------------------------------------------------------------------------

Private Sub tick_Timer()
    If scriptActive Then
        If scriptWait > 0 Then
            scriptWait = scriptWait - 1
        Else
            StepScript
            If WantQuit Then Exit Sub      ' the form is unloaded: touching it would load it again
        End If
    End If
    autosaveTicks = autosaveTicks + 1
    If autosaveTicks >= AUTOSAVE_SECS * TICKS_PER_SEC Then
        autosaveTicks = 0
        If Modified And DocPath <> "" And PrefAutosave Then
            SaveGws DocPath & ".autosave"
            Modified = True               ' the real file is still unsaved
        End If
    End If
    UpdateTitle
End Sub

' ---- menus --------------------------------------------------------------------------------

Private Sub mnuNew_Click(): CmdNew: End Sub
Private Sub mnuOpen_Click(): CmdOpen: End Sub
Private Sub mnuSave_Click(): CmdSave: End Sub
Private Sub mnuSaveAs_Click(): CmdSaveAs: End Sub
Private Sub mnuImport_Click()
    Dim f As String
    If Not ConfirmDiscard() Then Exit Sub
    f = AskFile("Import a CSV file:", "")
    If f <> "" Then Exec "IMPORTCSV " & f
End Sub
Private Sub mnuExport_Click(): CmdExportCsv: End Sub
Private Sub mnuHelp_Click(): CmdHelp: End Sub
Private Sub mnuAbout_Click()
    MsgBox "Gridwise 1.0" & vbLf & "A spreadsheet with charts for AmigaOS 4," & vbLf & "written in Boing BASIC." & vbLf & vbLf & _
           NR & " rows x " & NC & " columns, " & FormulaCount & " formulas", vbInformation, "About Gridwise"
End Sub
Private Sub mnuQuit_Click(): CmdQuit: End Sub
Private Sub mnuUndo_Click(): Exec "UNDO": End Sub
Private Sub mnuRedo_Click(): Exec "REDO": End Sub
Private Sub mnuCut_Click(): CmdCopy True: End Sub
Private Sub mnuCopy_Click(): CmdCopy False: End Sub
Private Sub mnuPaste_Click(): CmdPaste: End Sub
Private Sub mnuClear_Click(): CmdClear: End Sub
Private Sub mnuFillDown_Click(): Exec "FILLDOWN": End Sub
Private Sub mnuFillRight_Click(): Exec "FILLRIGHT": End Sub
Private Sub mnuSelAll_Click(): SelectRange 0, 0, NR - 1, NC - 1: Redraw: End Sub
Private Sub mnuFind_Click(): CmdFind: End Sub
Private Sub mnuFindNext_Click()
    If lastFind = "" Then CmdFind: Exit Sub
    Redraw
    If FindNext(lastFind, False) = "" Then ShowStatus "Not found: " & lastFind Else Redraw
End Sub
Private Sub mnuGoto_Click(): CmdGoto: End Sub
Private Sub mnuBold_Click(): Exec "BOLD": End Sub
Private Sub mnuItalic_Click(): Exec "ITALIC": End Sub
Private Sub mnuNfGeneral_Click(): Exec "FORMAT GENERAL": End Sub
Private Sub mnuNfInt_Click(): Exec "FORMAT INTEGER": End Sub
Private Sub mnuNfFixed_Click(): Exec "FORMAT FIXED": End Sub
Private Sub mnuNfThous_Click(): Exec "FORMAT THOUSANDS": End Sub
Private Sub mnuNfThous2_Click(): Exec "FORMAT THOUSANDS2": End Sub
Private Sub mnuNfCurrency_Click(): Exec "FORMAT CURRENCY": End Sub
Private Sub mnuNfPercent_Click(): Exec "FORMAT PERCENT": End Sub
Private Sub mnuNfPercent2_Click(): Exec "FORMAT PERCENT2": End Sub
Private Sub mnuNfSci_Click(): Exec "FORMAT SCIENTIFIC": End Sub
Private Sub mnuNfDate_Click(): Exec "FORMAT DATE": End Sub
Private Sub mnuNfTime_Click(): Exec "FORMAT TIME": End Sub
Private Sub mnuAlAuto_Click(): Exec "ALIGN AUTO": End Sub
Private Sub mnuAlLeft_Click(): Exec "ALIGN LEFT": End Sub
Private Sub mnuAlCenter_Click(): Exec "ALIGN CENTER": End Sub
Private Sub mnuAlRight_Click(): Exec "ALIGN RIGHT": End Sub
Private Sub mnuWider_Click(): AdjustWidth 8: End Sub
Private Sub mnuNarrower_Click(): AdjustWidth -8: End Sub
Private Sub mnuInsRow_Click(): Exec "INSERTROW": End Sub
Private Sub mnuDelRow_Click(): Exec "DELETEROW": End Sub
Private Sub mnuInsCol_Click(): Exec "INSERTCOL": End Sub
Private Sub mnuDelCol_Click(): Exec "DELETECOL": End Sub
Private Sub mnuSortAsc_Click(): Exec "SORT " & ColName(curC) & " ASC": End Sub
Private Sub mnuSortDesc_Click(): Exec "SORT " & ColName(curC) & " DESC": End Sub
Private Sub mnuRecalc_Click()
    Dim t As Double
    t = TimerMs
    Exec "RECALC"
    ShowStatus RecalcCount & " formulas recalculated in " & Format$(TimerMs - t, "0") & " ms"
End Sub
Private Sub mnuFormulas_Click(): ShowFormulas = mnuFormulas.Checked: Redraw: End Sub
Private Sub mnuGridLines_Click()
    ShowGridLines = mnuGridLines.Checked
    PrefGridLines = ShowGridLines
    SavePrefs
    Redraw
End Sub
Private Sub mnuAutosave_Click(): PrefAutosave = mnuAutosave.Checked: SavePrefs: End Sub
Private Sub mnuCurrency_Click()
    Dim v As String
    v = Trim$(InputBox("Currency symbol (up to 4 characters) for the Currency format:", "Gridwise", CurrencySymbol))
    If v = "" Or Len(v) > 4 Then Exit Sub
    CurrencySymbol = v
    SavePrefs
    Redraw
End Sub
Private Sub mnuRecent0_Click(): OpenRecent 0: End Sub
Private Sub mnuRecent1_Click(): OpenRecent 1: End Sub
Private Sub mnuRecent2_Click(): OpenRecent 2: End Sub
Private Sub mnuRecent3_Click(): OpenRecent 3: End Sub
Private Sub mnuRecent4_Click(): OpenRecent 4: End Sub
Private Sub mnuRecent5_Click(): OpenRecent 5: End Sub
Private Sub mnuRecent6_Click(): OpenRecent 6: End Sub
Private Sub mnuRecent7_Click(): OpenRecent 7: End Sub
Private Sub OpenRecent(ByVal i As Long)
    If i >= NRecent Then Exit Sub
    If Not ConfirmDiscard() Then Exit Sub
    OpenFile Recent(i)
End Sub
Private Sub mnuBar_Click(): CmdChartKind "BAR": End Sub
Private Sub mnuLine_Click(): CmdChartKind "LINE": End Sub
Private Sub mnuPie_Click(): CmdChartKind "PIE": End Sub
Private Sub mnuDelChart_Click()
    If selChart < 0 Then ShowStatus "Click a chart first": Exit Sub
    Exec "DELCHART"
End Sub
Private Sub mnuCCut_Click(): CmdCopy True: End Sub
Private Sub mnuCCopy_Click(): CmdCopy False: End Sub
Private Sub mnuCPaste_Click(): CmdPaste: End Sub
Private Sub mnuCClear_Click(): CmdClear: End Sub
Private Sub mnuCBold_Click(): Exec "BOLD": End Sub
Private Sub mnuCChart_Click(): CmdChartKind "BAR": End Sub

Private Sub CmdChartKind(ByVal k As String)
    Dim t As String
    t = InputBox("Title of the " & LCase$(k) & " chart of " & SelName() & ":", "Gridwise", "")
    Exec "CHART " & k & " " & SelName() & " " & t
End Sub

' copy also puts the cells' text on the system clipboard (tab-separated)
Private Sub CmdCopy(ByVal cut As Boolean)
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long
    SelBounds r1, c1, r2, c2
    clipText = RangeAsText(r1, c1, r2, c2)
    On Error Resume Next
    Clipboard.SetText clipText
    On Error GoTo 0
    If cut Then Exec "CUT" Else Exec "COPY"
End Sub

' paste Gridwise's own cells, or text another program put on the clipboard
Private Sub CmdPaste()
    Dim t As String
    On Error Resume Next
    t = Clipboard.GetText
    On Error GoTo 0
    If t <> "" And Replace(t, vbCr, "") <> clipText Then
        PasteText curR, curC, t
        Redraw
        UpdateTitle
    Else
        Exec "PASTE"
    End If
End Sub

' ---- mouse --------------------------------------------------------------------------------

Private Sub grid_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim r As Long, c As Long, edge As Boolean, ch As Long, corner As Boolean, cx As Long, cy As Long
    If Button <> 1 Then Exit Sub
    If editing Then CommitEdit 0, 0
    dragMode = 0
    ch = ChartAt(X, Y, corner)
    If ch >= 0 Then
        selChart = ch
        ChartPos ch, cx, cy
        dragX = X: dragY = Y
        If corner Then
            dragMode = 4: dragW = chW(ch): dragH = chH(ch)
        Else
            dragMode = 3: dragW = cx: dragH = cy
        End If
        Redraw
        Exit Sub
    End If
    selChart = -1
    If Not HitTest(X, Y, r, c, edge) Then Exit Sub
    If edge Then
        dragMode = 2: dragCol = c: dragX = X: dragW = colW(c)
    ElseIf r = -1 And c = -1 Then
        SelectRange 0, 0, NR - 1, NC - 1
    ElseIf r = -1 Then
        If (Shift And 1) <> 0 Then
            ancR = 0: curR = NR - 1: curC = c
        Else
            ancR = 0: ancC = c: curR = NR - 1: curC = c
        End If
        dragMode = 5
    ElseIf c = -1 Then
        If (Shift And 1) <> 0 Then
            ancC = 0: curC = NC - 1: curR = r
        Else
            ancC = 0: ancR = r: curC = NC - 1: curR = r
        End If
        dragMode = 6
    Else
        MoveCursor r, c, (Shift And 1) <> 0
        dragMode = 1
    End If
    Redraw
End Sub

Private Sub grid_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim r As Long, c As Long, edge As Boolean, w As Long
    If Button <> 1 Or dragMode = 0 Then Exit Sub
    Select Case dragMode
    Case 1, 5, 6
        ' scroll when dragging past the edges
        If Y >= vh And topRow + VisibleRows() < NR Then topRow = topRow + 1
        If Y < HDR_H And topRow > 0 Then topRow = topRow - 1
        If X >= vw And leftCol < NC - 1 Then leftCol = leftCol + 1
        If X < RHDR_W And leftCol > 0 Then leftCol = leftCol - 1
        If Y < HDR_H Then Y = HDR_H
        If Y >= vh Then Y = vh - 1
        If X < RHDR_W Then X = RHDR_W
        If X >= vw Then X = vw - 1
        If HitTest(X, Y, r, c, edge) Then
            If dragMode = 1 Then curR = r: curC = c
            If dragMode = 5 Then curC = c
            If dragMode = 6 Then curR = r
        End If
    Case 2
        w = dragW + X - dragX
        If w < 12 Then w = 12
        If w > 600 Then w = 600
        colW(dragCol) = w
        Modified = True
    Case 3
        MoveChartTo selChart, dragW + X - dragX, dragH + Y - dragY
    Case 4
        chW(selChart) = dragW + X - dragX
        chH(selChart) = dragH + Y - dragY
        If chW(selChart) < 120 Then chW(selChart) = 120
        If chH(selChart) < 80 Then chH(selChart) = 80
        Modified = True
    End Select
    Redraw
End Sub

' put a chart's top-left at screen (x, y): it snaps to the cell there
Private Sub MoveChartTo(ByVal i As Long, ByVal x As Long, ByVal y As Long)
    Dim r As Long, c As Long, edge As Boolean
    If x < RHDR_W Then x = RHDR_W
    If y < HDR_H Then y = HDR_H
    If HitTest(x, y, r, c, edge) Then
        If r >= 0 And c >= 0 Then
            If chRow(i) <> r Or chCol(i) <> c Then chRow(i) = r: chCol(i) = c: Modified = True
        End If
    End If
End Sub

Private Sub grid_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    dragMode = 0
    UpdateTitle
End Sub

Private Sub grid_DblClick()
    If selChart >= 0 Then Exit Sub
    StartEdit GetSrc(curR, curC)
End Sub

Private Sub grid_MouseWheel(Delta As Integer)
    topRow = topRow - Delta * 3
    If topRow < 0 Then topRow = 0
    If topRow > NR - VisibleRows() Then topRow = NR - VisibleRows()
    Redraw
End Sub
