' Riffwright - the main window: keys, the frame timer, files
'
'   Riffwright [song.mod]
Option Explicit

Private Sub Form_Load()
    ViewInit view
    TrackerInit
    PlayerOpen
    NewSong 4
    StarterSamples
    SongChanged
    filereq.Visible = False
    If Len(Trim$(Command$)) > 0 Then OpenSong Trim$(Command$)
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
    If Frame(False) Then view.Refresh
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not ConfirmDiscard() Then Cancel = True
End Sub

Private Sub Form_Unload(Cancel As Integer)
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
