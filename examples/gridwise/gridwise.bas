' gridwise.bas - the code-behind of gridwise.afg: Gridwise's main window.
'
' The grid is drawn on the canvas by GridView.bas. Keys: cursor keys move (Shift extends
' the selection, Shift+Up/Down a page, Alt+cursor to the edges), typing starts editing in the
' formula bar (Return enters and moves down, Tab right), Del clears, F2 edits the cell.
' Amiga-key shortcuts as in the menus (see Gridwise.guide).
'
' Command line: Gridwise [file.gws|file.csv] [--script file] [--log file]
'   --script runs a command file (Script.bas commands, one per line), writes the results to
'   --log (default file.log) and quits at QUIT: the guest smoke test uses this.
Option Explicit

Private settingText As Boolean        ' formula.Text set by code: ignore its Change
Private editing As Boolean            ' the formula bar holds an edit of the cursor cell
Private lastStatus As String
Private scriptLog As String
Private autosaveTicks As Long
Private Const AUTOSAVE_SECS As Long = 120

Private Sub Form_Load()
    Dim args As String, p As Long, f As String, scr As String
    NewSheet 1000, 26
    ClearCharts
    ViewInit grid.Width, grid.Height
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
            If ScriptRC <> 0 Then MsgBox "Can't open " & f & ": " & IOError, vbExclamation
        End If
    Loop
    UpdateTitle
    Redraw
    If scr <> "" Then RunScriptFile scr
End Sub

Private Sub RunScriptFile(ByVal path As String)
    Dim fn As Integer, s As String, line_ As String, res As String, logf As String
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
    RunLines s
    Exit Sub
Failed:
    LogLines = "can't read script " & path & ": " & Err.Description & vbLf
    WriteLog
End Sub

' run script lines one at a time, redrawing and honouring SHOT/QUIT between them
Private Sub RunLines(ByVal s As String)
    Dim lines() As String, i As Long, res As String
    lines = Split(s, vbLf)
    For i = 0 To UBound(lines)
        If Trim$(lines(i)) <> "" And Left$(Trim$(lines(i)), 1) <> ";" Then
            res = RunCommand(lines(i))
            LogLines = LogLines & lines(i) & " -> " & res
            If ScriptRC > 0 Then LogLines = LogLines & " [rc " & ScriptRC & "]"
            LogLines = LogLines & vbLf
            AfterCommand
            If WantQuit Then Exit For
        End If
    Next i
    WriteLog
    If WantQuit Then Unload Me
End Sub

Private Sub WriteLog()
    Dim fn As Integer
    If scriptLog = "" Then Exit Sub
    On Error Resume Next
    fn = FreeFile
    Open scriptLog For Output As #fn
    Print #fn, LogLines;
    Print #fn, "ok"
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

Private Sub Redraw()
    DrawGrid grid
    grid.Refresh
    UpdateBars
End Sub

' the cell name, the formula bar and the status line
Private Sub UpdateBars()
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long, s As String, sum As Double, cnt As Long, r As Long, c As Long
    cellname.Caption = SelName()
    If Not editing Then
        settingText = True
        formula.Text = GetSrc(curR, curC)
        settingText = False
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
    Case vbKeyX: Exec "CUT"
    Case vbKeyC: Exec "COPY"
    Case vbKeyV: Exec "PASTE"
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
    If ScriptRC >= 10 Then status.Caption = res: lastStatus = res: Beep
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
    Exec "OPEN " & f
End Sub

Private Sub CmdSave()
    If DocPath = "" Then CmdSaveAs: Exit Sub
    Exec "SAVE " & DocPath
End Sub

Private Sub CmdSaveAs()
    Dim f As String
    f = AskFile("Save the sheet as:", IIf(DocPath = "", "RAM:Untitled.gws", DocPath))
    If f = "" Then Exit Sub
    If LCase$(Right$(f, 4)) <> ".gws" Then f = f & ".gws"
    Exec "SAVE " & f
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
    f = InputBox("Find text in the cells:", "Gridwise")
    If f = "" Then Exit Sub
    If FindNext(f, False) = "" Then status.Caption = "Not found: " & f: lastStatus = status.Caption
    Redraw
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
    autosaveTicks = autosaveTicks + 1
    If autosaveTicks >= AUTOSAVE_SECS Then
        autosaveTicks = 0
        If Modified And DocPath <> "" Then
            SaveGws DocPath & ".autosave"
            Modified = True               ' the real file is still unsaved
        End If
    End If
    UpdateTitle
End Sub
