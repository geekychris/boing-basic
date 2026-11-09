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
    filereq.Visible = False
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
    If reqAction <> "" Then DoRequest
    If Frame(False) Then view.Refresh
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
        Frame True
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
    If Not songDirty Then ConfirmDiscard = True: Exit Function
    ConfirmDiscard = (MsgBox("The song has unsaved changes. Throw them away?", vbYesNo + vbQuestion, "Riffwright") = vbYes)
End Function

Private Function AskFile(ByVal title As String, ByVal pattern As String, ByVal save As Boolean) As String
    filereq.DialogTitle = title
    filereq.Pattern = pattern
    filereq.SaveMode = save
    filereq.ShowOpen
    AskFile = filereq.FileName
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
            If SaveMod(p) Then Say "saved " & songFileName() & " (" & FileLen(p) & " bytes)" Else Say "can't save: " & lastError
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
            Say "help: see Riffwright.guide"
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
