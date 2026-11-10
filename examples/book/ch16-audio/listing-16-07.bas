' Build a four-channel song from BASIC, play it, save it and export it as a WAV file
Option Explicit

Sub Main()
    Dim au As Audio, s As Long, i As Long, r As Long, p As Long, t As Long
    Dim melody As Variant
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"

    s = au.NewSong(4)
    au.SongName(s) = "manual tune"
    ' sample 1: one cycle of a square wave, 32 bytes, looped
    au.SampleLength(s, 1) = 32
    For i = 0 To 31
        If i < 16 Then au.SampleData(s, 1, i) = 80 Else au.SampleData(s, 1, i) = -80
    Next i
    au.SampleLoopStart(s, 1) = 0
    au.SampleLoopLength(s, 1) = 32
    au.SampleVolume(s, 1) = 48
    au.SampleName(s, 1) = "square"

    ' pattern 0: a melody on channel 0, every fourth row
    melody = Array("C-2", "E-2", "G-2", "C-3", "G-2", "E-2", "C-2", "---", _
                   "D-2", "F-2", "A-2", "D-3", "A-2", "F-2", "D-2", "---")
    For i = 0 To 15
        If melody(i) <> "---" Then au.SetCell s, 0, i * 4, 0, au.NoteFromName(melody(i)), 1, 0, 0
    Next i
    au.SetCell s, 0, 0, 1, au.NoteFromName("C-1"), 1, &HC, 32   ' a bass note, volume 32 (effect C)
    ' pattern 1: a copy of pattern 0, a fifth higher on the bass
    p = au.AddPattern(s)
    au.CopyPattern s, 0, p
    au.CellNote(s, p, 0, 1) = au.NoteFromName("G-1")
    ' the order list: 0, 1, 0
    au.SongLength(s) = 3
    au.Order(s, 0) = 0: au.Order(s, 1) = 1: au.Order(s, 2) = 0
    Print au.SongName(s); ":"; au.SongLength(s); "positions,"; au.PatternCount(s); "patterns,"; au.Channels(s); "channels"
    Print "cell 0/4/0 is "; au.NoteName(au.CellNote(s, 0, 4, 0)); ", packed &H"; Hex$(au.Cell(s, 0, 4, 0))

    ' play it once through, mixing 0.1 s at a time
    au.Loop = False
    au.PlayMusic s
    t = 0
    Do While au.Playing
        au.Render 2205
        t = t + 1
        If t = 30 Then Print "after 3 s: position"; au.Position; " row"; au.Row; " pattern"; au.Pattern
    Loop
    Print "played"; t / 10; "seconds, ended"; au.SongEnded; "time"
    Print "PCM hash"; au.PcmHash

    au.SaveMusic s, "tune.mod"
    au.RenderToWav s, "tune.wav"
    Print "tune.mod"; FileLen("tune.mod"); "bytes, tune.wav"; FileLen("tune.wav"); "bytes"
    Kill "tune.mod": Kill "tune.wav"
End Sub
