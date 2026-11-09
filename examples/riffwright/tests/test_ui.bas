' Riffwright tests - keys into the editor, frames on an off-screen canvas
Option Explicit

Sub Keys(ByVal s As String)
    ' letters as piano keys; ">" Down, "<" Up, "]" Right, " " Space
    Dim i As Long, ch As String
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        Select Case ch
            Case ">": HandleKey vbKeyDown, 0
            Case "<": HandleKey vbKeyUp, 0
            Case "}": HandleKey vbKeyRight, 0
            Case "{": HandleKey vbKeyLeft, 0
            Case "_": HandleKey vbKeySpace, 0
            Case Else: HandleKey Asc(UCase$(ch)), 0
        End Select
    Next i
End Sub

Function RowText(ByVal pat As Long, ByVal r As Long) As String
    Dim c As Long, s As String
    For c = 0 To nch - 1
        If c > 0 Then s = s & " | "
        s = s & CellText(CellIdx(pat, r, c))
    Next c
    RowText = s
End Function

Sub Main()
    Dim c As Object, i As Long, t As Double, n As Long
    Set c = CreateObject("Boing.Canvas")
    c.Resize 640, 480
    ViewInit c
    TrackerInit
    NewSong 4
    SynthSample 1, 0, 32, "square"
    SynthSample 2, 1, 64, "saw"
    SongChanged
    Check "first frame draws", Frame(True)
    ' jam mode: notes don't go in
    Keys "zxc"
    Check "jam leaves the pattern", cPer(CellIdx(0, 0, 0)) = 0
    ' edit mode, octave 2: Z = C-2, then Q = C-3
    Keys "_zsq"
    Print "rows:"
    For i = 0 To 3: Print "  "; RowText(0, i): Next i
    Check "cursor moved 3 rows", curRow = 3
    ' sample and effect columns: cursor right to the sample's low digit, type 2; effect C 2 0
    Keys "<<<}}2}}C20"
    Print "  "; RowText(0, 0)
    Print "  "; RowText(0, 1)
    ' octave up, F4 next sample
    HandleKey vbKeyF2, 0
    HandleKey vbKeyF4, 0
    HandleKey vbKeyTab, 0
    curRow = 8
    Keys "zm"
    Print "  "; RowText(0, 8)
    Print "  "; RowText(0, 9)
    ' undo with Amiga+Z, redo Amiga+Shift+Z
    HandleKey vbKeyZ, 8
    Print "undo:  "; RowText(0, 9)
    HandleKey vbKeyZ, 9
    Print "redo:  "; RowText(0, 9)
    ' select rows 0..3 of channel 1 with Shift+Down, copy, paste at row 16
    curRow = 0: curCh = 0: curField = 0
    For i = 1 To 3: HandleKey vbKeyDown, 1: Next i
    HandleKey vbKeyC, 8
    curRow = 16
    HandleKey vbKeyV, 8
    Print "paste: "; RowText(0, 16); " / "; RowText(0, 17)
    ' transpose the pasted block up a semitone: select 16..19, Amiga+T
    curRow = 16
    For i = 1 To 3: HandleKey vbKeyDown, 1: Next i
    HandleKey vbKeyT, 8
    Print "transp:"; RowText(0, 16); " / "; RowText(0, 17)
    ' mute channel 2 with Ctrl+2
    HandleKey vbKey2, 2
    Check "ch2 muted", ChanMuted(1)
    ' views
    HandleKey vbKeyF10, 0
    Check "sample view", curView = V_SAMPLES
    Check "sample view draws", Frame(True)
    If Environ$("RIFF_SHOTS") <> "" Then c.SaveImage Environ$("RIFF_SHOTS") & "/shot_samples.ppm"
    HandleKey vbKeyDown, 0
    HandleKey vbKeyRight, 1
    Print "sample 2 volume after Shift+Right on 64:"; smpVol(2)
    HandleKey vbKeyLeft, 1
    Print "and Shift+Left:"; smpVol(2)
    HandleKey vbKeyF10, 0
    Check "song view", curView = V_SONG
    HandleKey vbKeyDown, 0
    HandleKey vbKeyRight, 0
    Print "speed"; initSpeed
    Frame True
    If Environ$("RIFF_SHOTS") <> "" Then c.SaveImage Environ$("RIFF_SHOTS") & "/shot_song.ppm"
    HandleKey vbKey1, 8
    Check "Amiga+1 pattern view", curView = V_PATTERN
    ' file actions are left for the form
    HandleKey vbKeyS, 8
    Print "Amiga+S asks the form to: "; reqAction
    reqAction = ""
    ' frames: draw time with the play cursor moving
    curRow = 20
    Frame True
    If Environ$("RIFF_SHOTS") <> "" Then c.SaveImage Environ$("RIFF_SHOTS") & "/shot_pattern.ppm"
    Print "frame hash"; c.Hash
    t = Timer
    n = 200
    For i = 1 To n
        curRow = i Mod 64
        frameDirty = True
        Frame False
    Next i
    t = Timer - t
    If Environ$("RIFF_BENCH") <> "" Then Print "ms per frame:"; Format$(t * 1000 / n, "0.00")
    RexxTests
End Sub

Sub RexxTests()
    Dim rc As Long, r As String
    r = RexxCommand("LOAD", "../demos/boing_shuffle.mod", rc)
    Print "LOAD ->"; rc; r
    r = RexxCommand("PLAY", "2", rc)
    Print "PLAY 2 ->"; rc; r; " playing="; playing
    r = RexxCommand("POSITION", "", rc)
    Print "POSITION ->"; rc; r
    r = RexxCommand("STOP", "", rc)
    Print "STOP ->"; rc; r; " playing="; playing
    r = RexxCommand("POSITION", "4", rc)
    Print "POSITION 4 ->"; rc; r
    r = RexxCommand("POSITION", "99", rc)
    Print "POSITION 99 ->"; rc; r
    r = RexxCommand("SAVE", "rexx.mod", rc)
    Print "SAVE ->"; rc; r; " "; CompareFiles("rexx.mod", "../demos/boing_shuffle.mod")
    Kill "rexx.mod"
    r = RexxCommand("LOAD", """nothing.mod""", rc)
    Print "LOAD missing ->"; rc; r
    r = RexxCommand("JUMP", "", rc)
    Print "JUMP ->"; rc; r
End Sub
