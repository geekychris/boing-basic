' Riffwright - the main window: keys, the frame timer, files
'
'   Riffwright [song.mod] [--play] [--log] [--quit-after SEC] [--bench N]
'     --play          start playing the song at once (follow mode)
'     --log           print state changes (active window, loads, mode) for the guest tests
'     --quit-after S  close after S seconds (smoke tests; unsaved changes are dropped)
'     --bench N       play and draw N frames as fast as possible, print the timings, quit
Option Explicit

Private logOn As Boolean
Private testRun As Boolean        ' --quit-after / --bench: leave the preferences alone
Private quitAt As Double
Private benchN As Long
Private benchFrames As Long
Private benchDraw As Double
Private benchBlit As Double
Private benchWorst As Double
Private benchStart As Double

Private Sub LogLine(ByVal s As String)
    If logOn Then Debug.Print s
End Sub

Private Function ParseArgs() As String
    Dim a() As String, i As Long, song As String, play As Boolean
    a = Split(Trim$(Command$), " ")
    i = 0
    Do While i <= UBound(a)
        Select Case LCase$(a(i))
            Case "": 
            Case "--log": logOn = True
            Case "--play": play = True
            Case "--noscopes": scopesOff = True
            Case "--quit-after"
                i = i + 1
                If i <= UBound(a) Then quitAt = Timer + Val(a(i))
                testRun = True
            Case "--bench"
                i = i + 1
                If i <= UBound(a) Then benchN = CLng(Val(a(i)))
                testRun = True
                play = True
            Case Else
                song = a(i)
        End Select
        i = i + 1
    Loop
    If playerOk Then LogLine "audio " & mp.Device Else LogLine "audio none"
    If song = "" Then
        On Error Resume Next
        If App.FromWorkbench And App.ArgCount > 0 Then song = App.Arg(0)
        On Error GoTo 0
    End If
    If song <> "" Then OpenSong song
    If play Then StartSong 0, 0
    ParseArgs = song
End Function

Private Sub Form_Load()
    ViewInit view
    TrackerInit
    If InStr(Command$, "--quit-after") = 0 And InStr(Command$, "--bench") = 0 Then LoadPrefs
    PlayerOpen
    NewSong 4
    StarterSamples
    SongChanged
    On Error Resume Next
    App.ARexxPort = "RIFFWRIGHT"
    On Error GoTo 0
    menuFollow = followOn: menuView = curView
    mnuFollow.Checked = followOn
    ParseArgs
    Frame True
    view.Refresh
End Sub

' a new song gets a few synthesised instruments, so the piano keys make a sound at once
Private Sub StarterSamples()
    SynthSample 1, 0, 32, "square"
    SynthSample 2, 1, 64, "saw"
    SynthSample 3, 2, 32, "triangle"
    SynthSample 4, 3, 4000, "noise"
    ClearUndo
    songDirty = False
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    HandleKey KeyCode, Shift
    AfterInput
End Sub

' after any input: requests for the window, menu check marks, the picture
Private Sub AfterInput()
    If reqAction <> "" Then DoRequest
    SyncMenus
    If Frame(False) Then view.Refresh
End Sub

Private menuFollow As Boolean, menuEdit As Boolean, menuView As Long

Private Sub SyncMenus()
    If followOn <> menuFollow Then mnuFollow.Checked = followOn: menuFollow = followOn
    If editOn <> menuEdit Then mnuEditMode.Checked = editOn: menuEdit = editOn
    If curView <> menuView Then
        menuView = curView
        Select Case curView
            Case V_PATTERN: mnuVPattern.Checked = True
            Case V_SAMPLES: mnuVSamples.Checked = True
            Case V_SONG: mnuVSong.Checked = True
        End Select
    End If
End Sub

' ---- menus: each item does what its key does
Private Sub MenuKey(ByVal k As Integer, ByVal sh As Integer)
    HandleKey k, sh
    AfterInput
End Sub

Private Sub mnuNew_Click(): MenuKey vbKeyN, 8: End Sub
Private Sub mnuOpen_Click(): MenuKey vbKeyO, 8: End Sub
Private Sub mnuSave_Click(): MenuKey vbKeyS, 8: End Sub
Private Sub mnuSaveAs_Click(): MenuKey vbKeyS, 9: End Sub
Private Sub mnuLoadSmp_Click(): reqAction = "loadsample": AfterInput: End Sub
Private Sub mnuSaveSmp_Click(): reqAction = "savesample": AfterInput: End Sub
Private Sub mnuQuit_Click(): MenuKey vbKeyQ, 8: End Sub
Private Sub mnuUndo_Click(): MenuKey vbKeyZ, 8: End Sub
Private Sub mnuRedo_Click(): MenuKey vbKeyY, 8: End Sub
Private Sub mnuCut_Click(): PatternMenu vbKeyX, 8: End Sub
Private Sub mnuCopy_Click(): PatternMenu vbKeyC, 8: End Sub
Private Sub mnuPaste_Click(): PatternMenu vbKeyV, 8: End Sub
Private Sub mnuMix_Click(): PatternMenu vbKeyB, 8: End Sub
Private Sub mnuSelAll_Click(): PatternMenu vbKeyA, 8: End Sub
Private Sub mnuTrUp_Click(): PatternMenu vbKeyT, 8: End Sub
Private Sub mnuTrDown_Click(): PatternMenu vbKeyT, 9: End Sub
Private Sub mnuOctUp_Click(): PatternMenu vbKeyT, 12: End Sub
Private Sub mnuOctDown_Click(): PatternMenu vbKeyT, 13: End Sub
Private Sub mnuInterp_Click(): PatternMenu vbKeyI, 8: End Sub
Private Sub mnuSetSmp_Click(): PatternMenu vbKeyK, 8: End Sub
Private Sub mnuDupPat_Click(): PatternMenu vbKeyD, 8: End Sub
Private Sub mnuNewPat_Click(): PatternMenu vbKeyP, 8: End Sub
Private Sub mnuClrPat_Click(): PatternMenu vbKeyDelete, 8: End Sub
Private Sub mnuPlaySong_Click(): MenuKey vbKeyF5, 0: End Sub
Private Sub mnuPlayPat_Click(): MenuKey vbKeyF6, 0: End Sub
Private Sub mnuPlayRow_Click(): MenuKey vbKeyF7, 0: End Sub
Private Sub mnuStop_Click(): MenuKey vbKeyEscape, 0: End Sub
Private Sub mnuFollow_Click()
    followOn = mnuFollow.Checked: menuFollow = followOn
    AfterInput
End Sub
Private Sub mnuEditMode_Click()
    editOn = mnuEditMode.Checked: menuEdit = editOn
    AfterInput
End Sub
Private Sub mnuVPattern_Click(): SetView V_PATTERN: AfterInput: End Sub
Private Sub mnuVSamples_Click(): SetView V_SAMPLES: AfterInput: End Sub
Private Sub mnuVSong_Click(): SetView V_SONG: AfterInput: End Sub
Private Sub mnuGuide_Click(): reqAction = "help": AfterInput: End Sub
Private Sub mnuKeys_Click(): reqAction = "helpkeys": AfterInput: End Sub
Private Sub mnuAbout_Click()
    MsgBox "Riffwright 1.0" & vbLf & vbLf & "A ProTracker music editor written in Boing BASIC." & vbLf & _
        "Demo songs: CC0, free to use for anything.", vbInformation, "About Riffwright"
End Sub

' block commands work in the pattern editor
Private Sub PatternMenu(ByVal k As Integer, ByVal sh As Integer)
    If curView <> V_PATTERN Then SetView V_PATTERN
    MenuKey k, sh
End Sub

' ---- mouse on the canvas
Private Sub view_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    MouseDown Button, Shift, X, Y
    AfterInput
End Sub

Private Sub view_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    MouseMove Button, Shift, X, Y
    If Frame(False) Then view.Refresh
End Sub

Private Sub view_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    MouseUp Button, Shift, X, Y
    AfterInput
End Sub

Private Sub view_MouseWheel(Delta As Integer)
    MouseWheel Delta
    AfterInput
End Sub

Private Sub tick_Timer()
    Dim t As Double
    If quitAt > 0 And Timer >= quitAt Then
        LogLine "quit"
        songDirty = False
        quitAt = 0
        Unload Me
        Exit Sub
    End If
    If benchN > 0 Then RunBench: Exit Sub
    If Frame(False) Then view.Refresh
End Sub

Private Sub Form_Activate()
    LogLine "active"
End Sub

Private Sub Form_Deactivate()
    LogLine "inactive"
End Sub

' --bench: frames as fast as they go with the pattern scrolling, then a report
Private Sub RunBench()
    Dim i As Long, t0 As Double, t1 As Double, t2 As Double
    tick.Enabled = False
    benchStart = Timer
    For i = 1 To benchN
        t0 = Timer
        frameDirty = True
        Frame False
        t1 = Timer
        view.Refresh
        t2 = Timer
        benchDraw = benchDraw + (t1 - t0)
        benchBlit = benchBlit + (t2 - t1)
        If t2 - t0 > benchWorst Then benchWorst = t2 - t0
        If i Mod 25 = 0 Then DoEvents
    Next i
    t0 = Timer - benchStart
    Debug.Print "bench frames"; benchN; " total"; Format$(t0, "0.000"); "s  fps "; Format$(benchN / t0, "0.0")
    Debug.Print "  draw ms/frame "; Format$(benchDraw * 1000 / benchN, "0.000"); _
        "  blit ms/frame "; Format$(benchBlit * 1000 / benchN, "0.000"); "  worst ms "; Format$(benchWorst * 1000, "0.0")
    If playerOk Then Debug.Print "  audio "; mp.Device; ", mixer CPU "; Format$(mp.CpuLoad / 10, "0.0"); "%, still playing: "; mp.Playing; ", position"; mp.Position
    benchN = 0
    songDirty = False
    Unload Me
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not ConfirmDiscard() Then Cancel = True
End Sub

Private Sub Form_Unload(Cancel As Integer)
    If Not testRun Then SavePrefs
    PlayerClose
End Sub

Private Function ConfirmDiscard() As Boolean
    Dim r As Long, p As String
    If Not songDirty Then ConfirmDiscard = True: Exit Function
    r = App.Request("The song " & songFileName() & " has unsaved changes.", "_Save|_Discard|_Cancel", "Riffwright")
    Select Case r
        Case 1
            p = songPath
            If p = "" Then p = AskFile("Save the module", "#?.mod", True)
            If p = "" Then Exit Function
            If Not SaveSong(p) Then Exit Function
            ConfirmDiscard = True
        Case 2: ConfirmDiscard = True
    End Select
End Function

' save, and give a new file a project icon that opens it in Riffwright
Private Function SaveSong(ByVal p As String) As Boolean
    Dim tmpl As String
    If Not SaveMod(p) Then Say "can't save: " & lastError: Exit Function
    SaveSong = True
    Say "saved " & songFileName() & " (" & FileLen(p) & " bytes)"
    If Len(Dir$(p & ".info")) = 0 Then
        tmpl = DataPath("def_mod.info")
        On Error Resume Next
        If tmpl <> "" Then App.SaveIcon p, "", Left$(tmpl, Len(tmpl) - 5) Else App.SaveIcon p
        On Error GoTo 0
    End If
End Function

' a file that ships with Riffwright: beside the program, else in the current drawer
Private Function DataPath(ByVal name As String) As String
    Dim p As String
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    If Len(Dir$(p & name)) > 0 Then DataPath = p & name: Exit Function
    If Len(Dir$(name)) > 0 Then
        p = CurDir$
        If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
        DataPath = p & name
    End If
End Function

' the AmigaGuide manual, at a node (opens asynchronously)
Private Sub ShowGuide(ByVal node As String)
    Dim p As String
    p = DataPath("Riffwright.guide")
    If p = "" Then Say "Riffwright.guide is missing": Exit Sub
    On Error Resume Next
    App.ShowHelp p, node
    If Err.Number <> 0 Then Say "can't open the guide: " & Err.Description
End Sub

Private Function AskFile(ByVal title As String, ByVal pattern As String, ByVal save As Boolean) As String
    Dim p As String, k As Long
    dlg.DialogTitle = title
    dlg.Filter = pattern
    If prefDir <> "" Then dlg.InitDir = prefDir
    dlg.FileName = ""
    If save Then
        dlg.Flags = &H2                      ' ask before overwriting
        dlg.ShowSave
    Else
        dlg.Flags = &H1000                   ' the file must exist
        dlg.ShowOpen
    End If
    If dlg.Cancelled Then Exit Function
    p = dlg.FileName
    k = InStrRev(p, "/"): If InStrRev(p, ":") > k Then k = InStrRev(p, ":")
    If k > 0 Then prefDir = Left$(p, k)
    AskFile = p
End Function

Private Sub OpenSong(ByVal path As String)
    StopPlayer
    If LoadMod(path) Then
        SongChanged
        LogLine "loaded " & path & " " & nch & " " & nPat
        Say "loaded " & songFileName() & ": " & nch & " channels, " & nPat & " patterns"
    Else
        Say "can't load " & path & ": " & lastError
        NewSong 4
        SongChanged
    End If
End Sub

Private Sub DoRequest()
    Dim a As String, p As String, s As String
    a = reqAction
    reqAction = ""
    Select Case a
        Case "open"
            If Not ConfirmDiscard() Then Exit Sub
            p = AskFile("Open a module", "#?.mod", False)
            If p <> "" Then OpenSong p
        Case "save", "saveas"
            p = songPath
            If a = "saveas" Or p = "" Then p = AskFile("Save the module", "#?.mod", True)
            If p = "" Then Exit Sub
            SaveSong p
        Case "new"
            If Not ConfirmDiscard() Then Exit Sub
            StopPlayer
            NewSong 4
            StarterSamples
            SongChanged
            Say "new song"
        Case "quit"
            If ConfirmDiscard() Then songDirty = False: Unload Me
        Case "help"
            ShowGuide "Main"
        Case "helpkeys"
            ShowGuide "Keys"
        Case "title"
            s = InputBox("Song title (20 characters):", "Riffwright", TitleText())
            If s <> "" Then EdTitle s
        Case "samplename"
            s = InputBox("Sample name (22 characters):", "Riffwright", SampleText(curSmp))
            If s <> "" Then EdSampleName curSmp, s: sideDirty = True
        Case "loadsample"
            p = AskFile("Load a sample (8SVX, WAV, raw)", "#?", False)
            If p <> "" Then
                If LoadSampleFile(curSmp, p) Then Say "sample " & Hex2(curSmp) & ": " & smpInfo Else Say "can't load: " & smpError
                sideDirty = True
            End If
        Case "savesample"
            p = AskFile("Save the sample (.8svx, .wav or .raw)", "#?", True)
            If p <> "" Then
                s = "8svx"
                If LCase$(Right$(p, 4)) = ".wav" Then s = "wav"
                If LCase$(Right$(p, 4)) = ".raw" Then s = "raw"
                If SaveSampleFile(curSmp, p, s) Then Say "sample saved as " & UCase$(s) Else Say "can't save: " & smpError
            End If
    End Select
    frameDirty = True
End Sub

' ---- ARexx: the RIFFWRIGHT port (PLAY [pos], STOP, LOAD file, SAVE [file], POSITION [n], TITLE, VERSION)
Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Dim rc As Long
    LogLine "arexx " & Cmd & " " & Args
    Result = RexxCommand(Cmd, Args, rc)
    App.ARexxRC = rc
    AfterInput
End Sub

' ---- files dropped on the window: a module opens, a sample goes into the current sample
Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    Dim p As String, ext As String
    If Count < 1 Then Exit Sub
    p = App.DropFile(0)
    ext = LCase$(Mid$(p, InStrRev(p, ".") + 1))
    LogLine "dropped " & p
    If ext = "mod" Or LCase$(Left$(Mid$(p, InStrRev(p, "/") + 1), 4)) = "mod." Then
        If ConfirmDiscard() Then OpenSong p
    ElseIf LoadSampleFile(curSmp, p) Then
        Say "sample " & Hex2(curSmp) & ": " & smpInfo
        sideDirty = True
    Else
        Say "can't use " & p & ": " & smpError
    End If
    AfterInput
End Sub
