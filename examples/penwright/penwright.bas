' penwright.bas - the code-behind of penwright.afg: Penwright's main window.
'
' The page is drawn on the canvas by PwView.bas; typing goes into the document through
' PwScript.bas (TypeText), so the keyboard, the toolbar, the ARexx port and scripts all
' share one set of commands.
'
' Command line: Penwright [file] [--script file] [--log file]   (see Gridwise for scripts;
' "PAUSE n tag" waits n seconds with "paused tag" as the log's last line)
Option Explicit

Private lastShift As Integer          ' qualifiers of the last KeyDown (KeyPress has none)
Private lastStatus As String
Private settingBars As Boolean        ' toolbar values set by code: ignore their Click
Private blink As Long
Private scriptLog As String
Private scriptLines() As String
Private scriptPos As Long
Private scriptWait As Long
Private scriptActive As Boolean
Private autosaveTicks As Long
Private findWhat As String
Private findCase As Boolean
Private findWord As Boolean
Private dragging As Boolean
Private Const TICKS_PER_SEC As Long = 4
Private Const AUTOSAVE_SECS As Long = 120

Private Sub Form_Load()
    Dim args As String, p As Long, f As String, scr As String
    NewDoc
    ViewInit page, page.Width, page.Height
    If Not LoadDictionary(App.Path & "/penwright.dict", App.Path & "/penwright.words") Then
        LoadDictionary "penwright.dict", "penwright.words"
    End If
    LiveSpell = SpellReady
    args = Trim$(Command$)
    Do While args <> ""
        p = InStr(args & " ", " ")
        f = Left$(args, p - 1)
        args = Trim$(Mid$(args, p))
        If f = "--script" Or f = "--log" Then
            p = InStr(args & " ", " ")
            If f = "--script" Then scr = Left$(args, p - 1) Else scriptLog = Left$(args, p - 1)
            args = Trim$(Mid$(args, p))
        ElseIf f <> "" Then
            RunCommand "OPEN " & f
            If PwRC <> 0 Then MsgBox "Can't open " & f & ": " & DocIOError, vbExclamation
        End If
    Loop
    UpdateTitle
    Redraw
    If scr <> "" Then LoadScript scr
End Sub

' ---- drawing -------------------------------------------------------------------------------

Private Sub Redraw()
    UpdateBars                         ' labels first: they re-lay the window out
    DrawDoc page
    page.Refresh
End Sub

Private Sub UpdateTitle()
    Dim t As String
    If PwPath = "" Then t = "Untitled" Else t = PwPath
    If DocModified Then t = t & " *"
    t = "Penwright - " & t
    If Me.Caption <> t Then Me.Caption = t
End Sub

Private Sub UpdateBars()
    Dim s As String, a As Long, z As Long, k As Long
    settingBars = True
    If style.ListIndex <> pStyle(curP) Then style.ListIndex = pStyle(curP)
    If align.ListIndex <> pAlign(curP) Then align.ListIndex = pAlign(curP)
    If TypingSet Then
        a = TypingAttr: z = TypingSize
    ElseIf HasSelection() Then
        a = AttrAt(ancP, ancO): z = SizeAt(ancP, ancO)
        If ancP > curP Or (ancP = curP And ancO > curO) Then a = AttrAt(curP, curO): z = SizeAt(curP, curO)
    Else
        a = AttrForTyping(curP, curO): z = SizeForTyping(curP, curO)
    End If
    k = (a And A_COLMASK) \ 16
    If colour.ListIndex <> k Then colour.ListIndex = k
    k = SizeIndex(z)
    If k >= 0 And size.ListIndex <> k Then size.ListIndex = k
    settingBars = False
    s = "Para " & (curP + 1) & "/" & NP & "  Col " & (curO + 1) & "   " & StyleName(pStyle(curP))
    If a And A_BOLD Then s = s & "  Bold"
    If a And A_ITALIC Then s = s & "  Italic"
    If a And A_UNDER Then s = s & "  Underline"
    s = s & "  " & z & "pt"
    If HasSelection() Then s = s & "   (" & Len(RunCommand("GETSELECTION")) & " chars selected)"
    If s <> lastStatus Then status.Caption = s: lastStatus = s
End Sub

Private Function SizeIndex(ByVal z As Long) As Long
    Dim i As Long
    SizeIndex = -1
    For i = 0 To size.ListCount - 1
        If Val(size.List(i)) = z Then SizeIndex = i: Exit Function
    Next i
End Function

Private Sub ShowStatus(ByVal s As String)
    status.Caption = s
    lastStatus = s
    page.Refresh
End Sub

' run a command; show an error in the status line
Private Sub Exec(ByVal cmd As String)
    Dim res As String
    res = RunCommand(cmd)
    AfterCommand
    If PwRC >= 10 Then ShowStatus res: Beep
End Sub

Private Sub AfterCommand()
    If PwRedraw Then Redraw
    If PwShot <> "" Then page.SaveImage PwShot: PwShot = ""
    UpdateTitle
End Sub

' ---- keys ----------------------------------------------------------------------------------

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim ext As Boolean, amiga As Boolean, alt As Boolean, ctrl As Boolean
    lastShift = Shift
    ext = (Shift And 1) <> 0
    ctrl = (Shift And 2) <> 0
    alt = (Shift And 4) <> 0
    amiga = (Shift And 8) <> 0
    If amiga Then AmigaKey KeyCode, ext: Exit Sub
    Select Case KeyCode
    Case vbKeyLeft
        If alt Or ctrl Then MoveCaret "WL", ext Else MoveCaret "L", ext
    Case vbKeyRight
        If alt Or ctrl Then MoveCaret "WR", ext Else MoveCaret "R", ext
    Case vbKeyUp
        If alt Then
            MoveCaret "TOP", ext
        ElseIf ext And ctrl Then
            MoveCaret "PGUP", False
        Else
            MoveCaret "U", ext
        End If
    Case vbKeyDown
        If alt Then
            MoveCaret "BOT", ext
        ElseIf ext And ctrl Then
            MoveCaret "PGDN", False
        Else
            MoveCaret "D", ext
        End If
    Case 256 + &H48, vbKeyPageUp: MoveCaret "PGUP", ext
    Case 256 + &H49, vbKeyPageDown: MoveCaret "PGDN", ext
    Case 256 + &H70, vbKeyHome: MoveCaret "HOME", ext
    Case 256 + &H71, vbKeyEnd: MoveCaret "END", ext
    Case vbKeyReturn
        BreakTyping
        TypeText vbLf, False
    Case vbKeyBack
        Backspace ctrl Or alt
    Case vbKeyDelete
        DeleteForward ctrl Or alt
    Case vbKeyTab
        TypeText "    ", True
    Case vbKeyEscape
        SetCursor curP, curO, False
    Case 47, vbKeyF1                  ' Help
        ShowHelp
        Exit Sub
    Case Else
        Exit Sub
    End Select
    TypingSetOffUnlessTyping KeyCode
    CaretOn = True: blink = 0
    Redraw
    UpdateTitle
End Sub

' moving the cursor forgets attributes chosen for the next typing
Private Sub TypingSetOffUnlessTyping(ByVal k As Integer)
    Select Case k
    Case vbKeyLeft, vbKeyRight, vbKeyUp, vbKeyDown, vbKeyPageUp, vbKeyPageDown, vbKeyHome, vbKeyEnd, _
         256 + &H48, 256 + &H49, 256 + &H70, 256 + &H71
        TypingSet = False
        BreakTyping
    End Select
End Sub

Private Sub Backspace(ByVal word As Boolean)
    Dim p As Long, o As Long
    If HasSelection() Then Exec "DELETE": Exit Sub
    If curO = 0 And curP = 0 Then Exit Sub
    p = curP: o = curO
    If word Then
        MoveCaret "WL", True
    Else
        MoveCaret "L", True
    End If
    RunCommand "DELETE"
End Sub

Private Sub DeleteForward(ByVal word As Boolean)
    If HasSelection() Then RunCommand "DELETE": Exit Sub
    If word Then
        MoveCaret "WR", True
        RunCommand "DELETE"
    Else
        RunCommand "DELETE"
    End If
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    If (lastShift And (8 Or 2)) <> 0 Then Exit Sub          ' Amiga/Ctrl combinations are commands
    If KeyAscii < 32 Or KeyAscii = 127 Then Exit Sub         ' Return, Backspace... come as KeyDown
    TypeText Chr$(KeyAscii), True
    CaretOn = True: blink = 0
    Redraw
    UpdateTitle
End Sub

Private Sub AmigaKey(ByVal k As Integer, ByVal shifted As Boolean)
    Select Case k
    Case vbKeyN: CmdNew
    Case vbKeyO: CmdOpen
    Case vbKeyS: If shifted Then CmdSaveAs Else CmdSave
    Case vbKeyQ: Unload Me: Exit Sub
    Case vbKeyZ: If shifted Then Exec "REDO" Else Exec "UNDO"
    Case vbKeyY: Exec "REDO"
    Case vbKeyX: CmdCopy True
    Case vbKeyC: CmdCopy False
    Case vbKeyV: CmdPaste
    Case vbKeyA: Exec "SELECTALL"
    Case vbKeyB: Exec "BOLD"
    Case vbKeyI: Exec "ITALIC"
    Case vbKeyU: Exec "UNDERLINE"
    Case vbKeyF: CmdFind
    Case vbKeyG: CmdFindNext
    Case vbKeyR: CmdReplace
    Case vbKeyK: CmdSpell
    Case vbKeyW: CmdCount
    Case vbKeyE: CmdExport
    Case vbKeyP: Exec "PLAIN"
    Case vbKeyM: ShowMarks = Not ShowMarks: Redraw
    Case vbKey0: Exec "STYLE BODY"
    Case vbKey1: Exec "STYLE HEADING1"
    Case vbKey2: Exec "STYLE HEADING2"
    Case vbKey3: Exec "STYLE HEADING3"
    Case vbKey4: Exec "STYLE QUOTE"
    Case vbKey5: Exec "STYLE BULLET"
    Case vbKey6: Exec "STYLE CODE"
    Case vbKeyLeft: Exec "ALIGN LEFT"
    Case vbKeyRight: Exec "ALIGN RIGHT"
    Case vbKeyUp: Exec "ALIGN CENTER"
    Case vbKeyDown: Exec "ALIGN JUSTIFY"
    End Select
End Sub

' ---- toolbar -------------------------------------------------------------------------------

Private Sub bold_Click()
    Exec "BOLD"
End Sub

Private Sub italic_Click()
    Exec "ITALIC"
End Sub

Private Sub under_Click()
    Exec "UNDERLINE"
End Sub

Private Sub style_Click()
    If settingBars Then Exit Sub
    Exec "STYLE " & Replace(style.Text, " ", "")
End Sub

Private Sub size_Click()
    If settingBars Then Exit Sub
    Exec "SIZE " & size.Text
End Sub

Private Sub colour_Click()
    If settingBars Then Exit Sub
    Exec "COLOR " & colour.ListIndex
End Sub

Private Sub align_Click()
    If settingBars Then Exit Sub
    Select Case align.ListIndex
    Case 0: Exec "ALIGN LEFT"
    Case 1: Exec "ALIGN CENTER"
    Case 2: Exec "ALIGN RIGHT"
    Case 3: Exec "ALIGN JUSTIFY"
    End Select
End Sub

Private Sub findbtn_Click()
    CmdFind
End Sub

Private Sub spellbtn_Click()
    CmdSpell
End Sub

' ---- commands that ask -------------------------------------------------------------------

Private Function ConfirmDiscard() As Boolean
    Dim a As Integer
    If Not DocModified Then ConfirmDiscard = True: Exit Function
    a = MsgBox("The document has unsaved changes. Save them first?", vbYesNoCancel Or vbQuestion, "Penwright")
    If a = vbCancel Then Exit Function
    If a = vbYes Then
        CmdSave
        If DocModified Then Exit Function
    End If
    ConfirmDiscard = True
End Function

Private Function AskFile(ByVal title As String, ByVal def As String) As String
    AskFile = Trim$(InputBox(title, "Penwright", def))
End Function

Private Sub CmdNew()
    If Not ConfirmDiscard() Then Exit Sub
    Exec "NEW"
End Sub

Private Sub CmdOpen()
    Dim f As String
    If Not ConfirmDiscard() Then Exit Sub
    f = AskFile("Open a document (.pwd, .rtf or text):", PwPath)
    If f <> "" Then Exec "OPEN " & f
End Sub

Private Sub CmdSave()
    If PwPath = "" Then CmdSaveAs: Exit Sub
    Exec "SAVE " & PwPath
End Sub

Private Sub CmdSaveAs()
    Dim f As String
    f = AskFile("Save the document as:", IIf(PwPath = "", "RAM:Untitled.pwd", PwPath))
    If f = "" Then Exit Sub
    If LCase$(Right$(f, 4)) <> ".pwd" Then f = f & ".pwd"
    Exec "SAVE " & f
End Sub

Private Sub CmdExport()
    Dim f As String, k As String
    k = LCase$(Trim$(InputBox("Export as: rtf, html or txt", "Penwright", "rtf")))
    If k = "" Then Exit Sub
    f = AskFile("Export to file:", "RAM:document." & k)
    If f <> "" Then Exec "EXPORT " & k & " " & f
    If PwRC = 0 Then ShowStatus "Exported to " & f
End Sub

Private Sub CmdCopy(ByVal cut As Boolean)
    If Not HasSelection() Then Exit Sub
    If cut Then Exec "CUT" Else RunCommand "COPY"
    On Error Resume Next
    Clipboard.SetText ClipPlain
End Sub

' paste: Penwright's own (styled) clipboard if the system clipboard still holds the same
' text, else the system clipboard's text
Private Sub CmdPaste()
    Dim t As String
    On Error Resume Next
    t = Clipboard.GetText
    On Error GoTo 0
    If t <> "" And t <> ClipPlain Then
        TypeText t, False
        Redraw
        UpdateTitle
    Else
        Exec "PASTE"
    End If
End Sub

Private Sub CmdFind()
    Dim f As String
    f = InputBox("Find (end with "" CASE"" to match case, "" WORD"" for whole words):", "Penwright", findWhat)
    If f = "" Then Exit Sub
    findWhat = f
    CmdFindNext
End Sub

Private Sub CmdFindNext()
    If findWhat = "" Then CmdFind: Exit Sub
    Exec "FIND " & findWhat
    If PwRC = 5 Then ShowStatus "Not found: " & findWhat
End Sub

Private Sub CmdReplace()
    Dim f As String, r As String, opt As String, n As String
    f = InputBox("Replace all - find:", "Penwright", findWhat)
    If f = "" Then Exit Sub
    r = InputBox("Replace """ & f & """ with:", "Penwright")
    opt = InputBox("Options: CASE and/or WORD (or leave empty)", "Penwright", "")
    n = RunCommand("REPLACEALL """ & f & """ """ & r & """ " & opt)
    AfterCommand
    ShowStatus n & " replaced"
End Sub

Private Sub CmdSpell()
    Dim w As String, sug As String, a As String, choices() As String
    If Not SpellReady Then ShowStatus "No dictionary (penwright.dict)": Exit Sub
    w = RunCommand("SPELLNEXT")
    AfterCommand
    If PwRC = 5 Then
        ShowStatus "No more misspelt words"
        SetCursor 0, 0, False
        Exit Sub
    End If
    sug = RunCommand("SUGGEST " & w)
    a = InputBox("""" & w & """ is not in the dictionary." & vbLf & "Suggestions: " & sug & vbLf & _
                 "Type the correction, + to learn the word, or leave it to skip:", "Penwright spelling", Trim$(Left$(sug, InStr(sug & " ", " ") - 1)))
    If a = "+" Then
        Exec "LEARN " & w
    ElseIf a <> "" And a <> w Then
        TypeText a, False
        Redraw
    End If
End Sub

Private Sub CmdCount()
    MsgBox "Words: " & WordCount() & vbLf & "Characters: " & CharCount(True) & vbLf & _
           "Characters without spaces: " & CharCount(False) & vbLf & "Paragraphs: " & NP, vbInformation, "Penwright"
End Sub

Private Sub ShowHelp()
    Shell "run >NIL: SYS:Utilities/Multiview PROGDIR:Penwright.guide"
End Sub

' ---- timer: caret blink, scripts, autosave ---------------------------------------------------

Private Sub tick_Timer()
    If scriptActive Then
        If scriptWait > 0 Then
            scriptWait = scriptWait - 1
        Else
            StepScript
            If PwQuit Then Exit Sub        ' unloaded: touching the form would load it again
        End If
    End If
    blink = blink + 1
    If blink >= 2 Then
        blink = 0
        CaretOn = Not CaretOn
        DrawDoc page
        page.Refresh
    End If
    autosaveTicks = autosaveTicks + 1
    If autosaveTicks >= AUTOSAVE_SECS * TICKS_PER_SEC Then
        autosaveTicks = 0
        If DocModified And PwPath <> "" Then
            WriteFile PwPath & ".autosave", DocToPwd()
        End If
    End If
End Sub

Private Sub LoadScript(ByVal path As String)
    Dim fn As Integer, s As String, l As String
    If scriptLog = "" Then scriptLog = path & ".log"
    On Error GoTo Failed
    fn = FreeFile
    Open path For Input As #fn
    Do While Not EOF(fn)
        Line Input #fn, l
        s = s & l & vbLf
    Loop
    Close #fn
    scriptLines = Split(Replace(s, vbCr, ""), vbLf)
    scriptPos = 0
    scriptWait = TICKS_PER_SEC
    scriptActive = True
    Exit Sub
Failed:
    WriteLog "can't read script " & path & ": " & Err.Description & vbLf, "ok"
End Sub

Private Sub StepScript()
    Static logText As String
    Dim l As String, res As String, w() As String
    Do While scriptPos <= UBound(scriptLines)
        l = Trim$(scriptLines(scriptPos))
        scriptPos = scriptPos + 1
        If l <> "" And Left$(l, 1) <> ";" Then
            If UCase$(Left$(l, 6)) = "PAUSE " Then
                w = Split(l & " ", " ")
                scriptWait = Val(w(1)) * TICKS_PER_SEC
                If scriptWait < 1 Then scriptWait = 1
                WriteLog logText, "paused " & Trim$(Mid$(l, 7 + Len(w(1))))
                Exit Sub
            End If
            res = RunCommand(l)
            logText = logText & l & " -> " & res
            If PwRC > 0 Then logText = logText & " [rc " & PwRC & "]"
            logText = logText & vbLf
            AfterCommand
            If PwQuit Then Exit Do
        End If
    Loop
    scriptActive = False
    WriteLog logText, "ok"
    If PwQuit Then Unload Me
End Sub

Private Sub WriteLog(ByVal text As String, ByVal last As String)
    Dim fn As Integer
    If scriptLog = "" Then Exit Sub
    On Error Resume Next
    fn = FreeFile
    Open scriptLog For Output As #fn
    Print #fn, text;
    Print #fn, last
    Close #fn
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If PwQuit Then Exit Sub
    If Not ConfirmDiscard() Then Cancel = True
End Sub

' ---- menus --------------------------------------------------------------------------------

Private Sub mnuNew_Click(): CmdNew: End Sub
Private Sub mnuOpen_Click(): CmdOpen: End Sub
Private Sub mnuSave_Click(): CmdSave: End Sub
Private Sub mnuSaveAs_Click(): CmdSaveAs: End Sub
Private Sub mnuExpRtf_Click(): ExportKind "rtf": End Sub
Private Sub mnuExpHtml_Click(): ExportKind "html": End Sub
Private Sub mnuExpTxt_Click(): ExportKind "txt": End Sub
Private Sub mnuInfo_Click()
    Dim t As String
    t = InputBox("Title of the document:", "Penwright", DocTitle)
    If t <> DocTitle Then Exec "TITLE " & t
    t = InputBox("Author:", "Penwright", DocAuthor)
    If t <> DocAuthor Then Exec "AUTHOR " & t
End Sub
Private Sub mnuHelp_Click(): ShowHelp: End Sub
Private Sub mnuAbout_Click()
    MsgBox "Penwright 1.0" & vbLf & "A word processor for AmigaOS 4," & vbLf & "written in Boing BASIC." & vbLf & vbLf & _
           IIf(SpellReady, "Spelling dictionary loaded.", "No spelling dictionary found."), vbInformation, "About Penwright"
End Sub
Private Sub mnuQuit_Click(): Unload Me: End Sub
Private Sub mnuUndo_Click(): Exec "UNDO": End Sub
Private Sub mnuRedo_Click(): Exec "REDO": End Sub
Private Sub mnuCut_Click(): CmdCopy True: End Sub
Private Sub mnuCopy_Click(): CmdCopy False: End Sub
Private Sub mnuPaste_Click(): CmdPaste: End Sub
Private Sub mnuSelAll_Click(): Exec "SELECTALL": End Sub
Private Sub mnuFind_Click(): CmdFind: End Sub
Private Sub mnuFindNext_Click(): CmdFindNext: End Sub
Private Sub mnuReplace_Click(): CmdReplace: End Sub
Private Sub mnuBold_Click(): Exec "BOLD": End Sub
Private Sub mnuItalic_Click(): Exec "ITALIC": End Sub
Private Sub mnuUnder_Click(): Exec "UNDERLINE": End Sub
Private Sub mnuStrike_Click(): Exec "STRIKE": End Sub
Private Sub mnuPlain_Click(): Exec "PLAIN": End Sub
Private Sub mnuBigger_Click(): StepSize 1: End Sub
Private Sub mnuSmaller_Click(): StepSize -1: End Sub
Private Sub mnuStBody_Click(): Exec "STYLE BODY": End Sub
Private Sub mnuStH1_Click(): Exec "STYLE HEADING1": End Sub
Private Sub mnuStH2_Click(): Exec "STYLE HEADING2": End Sub
Private Sub mnuStH3_Click(): Exec "STYLE HEADING3": End Sub
Private Sub mnuStQuote_Click(): Exec "STYLE QUOTE": End Sub
Private Sub mnuStBullet_Click(): Exec "STYLE BULLET": End Sub
Private Sub mnuStCode_Click(): Exec "STYLE CODE": End Sub
Private Sub mnuAlLeft_Click(): Exec "ALIGN LEFT": End Sub
Private Sub mnuAlCenter_Click(): Exec "ALIGN CENTER": End Sub
Private Sub mnuAlRight_Click(): Exec "ALIGN RIGHT": End Sub
Private Sub mnuAlJustify_Click(): Exec "ALIGN JUSTIFY": End Sub
Private Sub mnuSpell_Click(): CmdSpell: End Sub
Private Sub mnuLive_Click(): LiveSpell = mnuLive.Checked: Redraw: End Sub
Private Sub mnuCount_Click(): CmdCount: End Sub
Private Sub mnuMarks_Click(): ShowMarks = mnuMarks.Checked: Redraw: End Sub

Private Sub ExportKind(ByVal k As String)
    Dim f As String, base As String
    base = PwPath
    If base = "" Then base = "RAM:document.pwd"
    If InStrRev(base, ".") > 0 Then base = Left$(base, InStrRev(base, ".") - 1)
    f = AskFile("Export as " & UCase$(k) & " to:", base & "." & k)
    If f = "" Then Exit Sub
    Exec "EXPORT " & k & " " & f
    If PwRC = 0 Then ShowStatus "Exported to " & f
End Sub

' the next size up or down in the size list
Private Sub StepSize(ByVal d As Long)
    Dim k As Long
    k = size.ListIndex + d
    If k < 0 Or k >= size.ListCount Then Exit Sub
    Exec "SIZE " & size.List(k)
End Sub

' ---- mouse --------------------------------------------------------------------------------

Private Sub page_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim p As Long, o As Long
    If Button <> 1 Then Exit Sub
    PosAt X, Y, p, o
    SetCursor p, o, (Shift And 1) <> 0
    TypingSet = False
    BreakTyping
    dragging = True
    wantX = -1
    Redraw
End Sub

Private Sub page_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim p As Long, o As Long
    If Not dragging Then Exit Sub
    If Y < 0 Then scrollY = scrollY - 16
    If Y >= vh Then scrollY = scrollY + 16
    If scrollY > DocHeight() - vh Then scrollY = DocHeight() - vh
    If scrollY < 0 Then scrollY = 0
    PosAt X, Y, p, o
    SetCursor p, o, True
    Redraw
End Sub

Private Sub page_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    dragging = False
End Sub

Private Sub page_DblClick()
    Dim ws As Long, wl As Long
    WordAt curP, curO, ws, wl
    If wl = 0 Then Exit Sub
    SetCursor curP, ws, False
    SetCursor curP, ws + wl, True
    dragging = False
    Redraw
End Sub

Private Sub page_MouseWheel(Delta As Integer)
    scrollY = scrollY - Delta * 48
    If scrollY > DocHeight() - vh Then scrollY = DocHeight() - vh
    If scrollY < 0 Then scrollY = 0
    Redraw
End Sub

Private Sub mnuXCut_Click(): CmdCopy True: End Sub
Private Sub mnuXCopy_Click(): CmdCopy False: End Sub
Private Sub mnuXPaste_Click(): CmdPaste: End Sub
Private Sub mnuXBold_Click(): Exec "BOLD": End Sub
Private Sub mnuXItalic_Click(): Exec "ITALIC": End Sub
Private Sub mnuXSpell_Click(): CmdSpell: End Sub
