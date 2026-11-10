Option Explicit

Sub Main()
    Dim au As Audio, v As Long, st() As Long, sc() As Long, s As Long, i As Long, peak As Long
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"
    ' an effect in the amiga3d style: three tones in one 8-bit buffer
    au.SfxDefine 2, 2400, 48, 20                 ' id 2: 2400 samples, volume 48, priority 20
    au.SfxTone 2, 0, 800, 523, 523, 90, 100      ' C
    au.SfxTone 2, 800, 800, 659, 659, 90, 100    ' E
    au.SfxTone 2, 1600, 800, 784, 784, 90, 200   ' G
    v = au.Sfx(2)
    Print "Sfx voice"; v; " sound number"; au.SfxSound(2); " length"; au.SoundLength(au.SfxSound(2))

    ' a one-row song so there is music to watch
    s = au.NewSong(4)
    au.SampleLength(s, 1) = 32
    For i = 0 To 31: au.SampleData(s, 1, i) = IIf(i < 16, 100, -100): Next i
    au.SampleLoopLength(s, 1) = 32
    au.SampleVolume(s, 1) = 64
    au.SetCell s, 0, 0, 0, au.NoteFromName("A-2"), 1, 0, 0
    au.PlayMusic s
    au.Render 2205
    st = au.State()                              ' everything at once: one call a frame
    Print "playing "; st(0) <> 0; ", position"; st(2); " row"; st(3); " speed"; st(6); " tempo"; st(7)
    Print "channel 0: note "; au.NoteName(st(17)); ", sample"; st(18); ", volume"; st(19)
    sc = au.Scope(0, 64)                         ' the last 64 output samples of channel 0
    For i = 0 To 63
        If Abs(sc(i)) > peak Then peak = Abs(sc(i))
    Next i
    Print "scope:"; UBound(sc) + 1; "samples, peak"; peak
End Sub
