' song editing (what the tracker does): an 8-channel song built from BASIC, saved, reloaded,
' played; live notes and rows; export to WAV
Dim au As Object, s As Long, t As Long, i As Long, ch As Long, r As Long, p As Long, ok As Boolean
Set au = CreateObject("Boing.Audio")
au.Open "manual"
s = au.NewSong(8)
au.SongName(s) = "bb edit test"
Print au.SongName(s); " ch "; au.Channels(s); " len "; au.SongLength(s); " pats "; au.PatternCount(s)
' sample 1: a 32-byte square cycle, looped; sample 2: a 64-byte saw, looped
au.SampleLength(s, 1) = 32
For i = 0 To 31
    If i < 16 Then au.SampleData(s, 1, i) = 90 Else au.SampleData(s, 1, i) = -90
Next
au.SampleLoopStart(s, 1) = 0
au.SampleLoopLength(s, 1) = 32
au.SampleVolume(s, 1) = 40
au.SampleName(s, 1) = "square"
au.SampleLength(s, 2) = 64
For i = 0 To 63
    au.SampleData(s, 2, i) = i * 4 - 128
Next
au.SampleLoopLength(s, 2) = 64
au.SampleVolume(s, 2) = 50
au.SampleFinetune(s, 2) = -2
Print "smp2 ft "; au.SampleFinetune(s, 2); " len "; au.SampleLength(s, 2); " loop "; au.SampleLoopStart(s, 2); au.SampleLoopLength(s, 2)
p = au.AddPattern(s)
Print "added pattern "; p; " count "; au.PatternCount(s)
For ch = 0 To 7
    For r = 0 To 63 Step 8
        au.SetCell s, 0, r, ch, 1 + (ch * 3 + r \ 8) Mod 36, 1 + ch Mod 2, 0, 0
    Next
Next
au.CellEffect(s, 0, 4, 0) = 4
au.CellParam(s, 0, 4, 0) = &H48
au.SetCell s, 0, 0, 7, au.NoteFromName("C-2"), 2, &HF, 5
au.CopyPattern s, 0, 1
au.CellNote(s, 1, 8, 3) = au.NoteFromName("A#3")
au.CellPeriod(s, 1, 16, 3) = 300
au.Cell(s, 1, 24, 5) = au.Cell(s, 0, 4, 0)
au.ClearPattern s, 0
au.CopyPattern s, 1, 0
au.SetCell s, 0, 63, 0, 0, 0, &HE, &H60
au.SongLength(s) = 3
au.Order(s, 0) = 0: au.Order(s, 1) = 1: au.Order(s, 2) = 0
Print "order "; au.Order(s, 0); au.Order(s, 1); au.Order(s, 2); " len "; au.SongLength(s)
Print "cell 1/8/3 "; au.NoteName(au.CellNote(s, 1, 8, 3)); " period 1/16/3 "; au.CellPeriod(s, 1, 16, 3); " note "; au.NoteName(au.CellNote(s, 1, 16, 3))
Print "packed "; Hex(au.Cell(s, 1, 24, 5)); " = "; Hex(au.Cell(s, 1, 4, 0))
Print "names "; au.NoteName(1); " "; au.NoteName(13); " "; au.NoteName(36); " "; au.NoteName(0); " "; au.NoteFromName("G#2"); " period "; au.NotePeriod(13); au.NotePeriod(13, 7)
au.SaveMusic s, "edit8.mod"
Print "saved "; FileLen("edit8.mod")
t = au.LoadMusic("edit8.mod")
ok = True
For p = 0 To 1
    For ch = 0 To 7
        For r = 0 To 63
            If au.Cell(t, p, r, ch) <> au.Cell(s, p, r, ch) Then ok = False
        Next
    Next
Next
For i = 0 To 63
    If au.SampleData(t, 2, i) <> au.SampleData(s, 2, i) Then ok = False
Next
Print "reloaded same: "; ok; " ch "; au.Channels(t); " '"; au.SongName(t); "' "; au.SampleName(t, 1); " ft "; au.SampleFinetune(t, 2)
au.Loop = False
au.PlayMusic t
i = 0
Do While au.Playing And i < 1000
    au.Render 2205
    ' edit while playing: the second time pattern 0 plays it is different
    If i = 20 Then au.SetCell t, 0, 32, 2, 25, 1, &HC, 20
    i = i + 1
Loop
Print "8ch played "; i; " blocks, ended "; au.SongEnded
Print "hash "; Hex(au.PcmHash)
' live notes with the music stopped, on the edit song
au.ResetHash
au.EditSong = s
au.PlayNote 0, 13, 1
au.Render 1000
Print "note on ch0: note "; au.ChannelNote(0); " smp "; au.ChannelSample(0); " vol "; au.ChannelVolume(0); " vu>0 "; au.ChannelVU(0) > 0
au.PlayNote 1, 20, 2, 10, 4, &H4C
au.Render 1000
Print "ch1 vol "; au.ChannelVolume(1)
au.NoteOff 0
au.Render 500
Print "off: vu "; au.ChannelVU(0)
au.PlayRow s, 1, 8
au.Render 2000
Print "row: ch3 note "; au.NoteName(au.ChannelNote(3))
Print "hash "; Hex(au.PcmHash)
' 6 channels save as 6CHN
p = au.NewSong(6)
au.SaveMusic p, "six.mod"
p = au.LoadMusic("six.mod")
Print "six: "; au.Channels(p)
au.RenderToWav t, "edit8.wav"
Print "wav "; FileLen("edit8.wav")
au.FreeMusic t
On Error Resume Next
i = au.Channels(t)
Print "freed "; Err.Number
Err.Clear
au.SetCell s, 0, 64, 0, 1, 1, 0, 0
Print "bad row "; Err.Number
Err.Clear
au.CellNote(s, 0, 0, 0) = 37
Print "bad note "; Err.Number
