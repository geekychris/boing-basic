' Riffwright tests - the player link (Boing.Audio with the "manual" device: nothing is heard,
' every frame is mixed on demand, so the results are the same on every platform)
Option Explicit

Function Mismatches() As Long
    Dim p As Long, r As Long, ch As Long, k As Long, bad As Long
    For p = 0 To nPat - 1
        For r = 0 To 63
            For ch = 0 To nch - 1
                k = CellIdx(p, r, ch)
                If mp.CellPeriod(auSong, p, r, ch) <> cPer(k) Or mp.CellSample(auSong, p, r, ch) <> cSmp(k) Or _
                   mp.CellEffect(auSong, p, r, ch) <> cFx(k) Or mp.CellParam(auSong, p, r, ch) <> cPrm(k) Then bad = bad + 1
            Next ch
        Next r
    Next p
    Mismatches = bad
End Function

Sub Run(ByVal frames As Long)
    Dim i As Long
    For i = 1 To frames \ 441: mp.Render 441: Next i
End Sub

Sub Main()
    Dim c As Object, pp As Long, pt As Long, pr As Long, fr As Long, b As Variant, i As Long, t() As Long
    Set c = CreateObject("Boing.Canvas")
    c.Resize 640, 480
    ViewInit c
    TrackerInit
    PlayerOpen
    Check "Boing.Audio", playerOk
    mp.Open "manual"
    Check "load", LoadMod("../demos/harbour_lights.mod")
    SongChanged
    Print "player song: ["; mp.SongName(auSong); "]"; mp.PatternCount(auSong); "patterns, length"; mp.SongLength(auSong)
    Check "every cell the same", Mismatches() = 0
    ' play: 1.5 s
    PlaySongAt 0, 0
    Run 33075
    PlayerPoll pp, pt, pr, fr
    Print "after 1.5 s: position"; pp; "pattern"; pt; "row"; pr; " playing "; playing
    Check "VU moves", ChanVU(0) + ChanVU(1) + ChanVU(2) + ChanVU(3) > 0
    PlayerRead True, 96
    Check "scope has signal", ScopeLive(1, t, 96)
    Check "scope of channel 2 moves", t(96 + 10) <> t(96 + 40) Or t(96 + 20) <> 0
    ' edits while playing reach the player
    EdNote 1, 5, 3, 37, 6
    Print "edited cell: note"; mp.CellNote(auSong, 1, 5, 3); "sample"; mp.CellSample(auSong, 1, 5, 3)
    UndoCells "odd", 1, 6, 6, 3, 3
    cPer(CellIdx(1, 6, 3)) = 431
    MirrorCell CellIdx(1, 6, 3)
    Print "odd period:"; mp.CellPeriod(auSong, 1, 6, 3)
    EdNote 20, 0, 0, 30, 1
    Print "pattern 20 made:"; mp.PatternCount(auSong) > 20; " note"; mp.CellNote(auSong, 20, 0, 0)
    Undo
    Print "undo reaches the player: note"; mp.CellNote(auSong, 20, 0, 0)
    ' samples
    SmpReverse 1
    b = mp.GetSampleBytes(auSong, 1)
    Print "sample 1 reversed in the player:"; UBound(b) + 1; "bytes, first"; b(0); "="; smpData(1)(0)
    EdSampleParams 4, 40, 15, 0, 16
    Print "sample 4: vol"; mp.SampleVolume(auSong, 4); "fine"; mp.SampleFinetune(auSong, 4); "loop"; _
        mp.SampleLoopStart(auSong, 4); mp.SampleLoopLength(auSong, 4)
    EdClearSample 9
    ' order list, mute
    EdInsertOrder 1, 4
    Print "orders in the player:"; mp.SongLength(auSong); mp.Order(auSong, 1); mp.Order(auSong, 2)
    Undo
    SetMute 1, True
    Print "mute ch2:"; mp.Mute(1)
    SetMute 1, False
    ' the pattern loop
    PlayPatternAt 3, 60
    Run 22050
    PlayerPoll pp, pt, pr, fr
    Print "pattern 3 looping: pattern"; pt; "row"; pr; " (position"; pp; ")"
    StopPlayer
    Print "stopped: playing "; playing; mp.Playing
    ' jam a note while stopped
    JamNote 0, 25, 1
    Run 882
    Check "jam note sounds", mp.ChannelVU(0) > 0
    Check "sample play cursor", PlayerSamplePos(1) >= 0
    ' start speed/tempo
    EdSpeedTempo 5, 140
    PlaySongAt 0, 0
    Run 4410
    Print "speed/tempo playing:"; CurSpeed(); CurTempo()
    StopPlayer
    ' the whole song again after a new load is still exact
    LoadMod "../demos/boing_shuffle.mod"
    SongChanged
    Check "second song exact", Mismatches() = 0
    ' render a bit of it and hash the PCM: the same on every platform
    mp.ResetHash
    PlaySongAt 0, 0
    Run 44100
    Print "PCM hash of 1 s of Boing Shuffle:"; mp.PcmHash
    StopPlayer
    PlayerClose
End Sub
