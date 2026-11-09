' amiga3d-style effects (SfxDefine/SfxTone/SfxNoise/Sfx, the same bytes as a3d_sound.c) and
' the tracker extras: PlayPattern, bulk sample bytes, ChannelPos, song start speed/tempo/restart
Dim au As Object, s As Long, i As Long, v As Long, h As Long, b() As Byte, c() As Byte, t As Long
Set au = CreateObject("Boing.Audio")
au.Open "manual"
au.SfxDefine 3, 3000, 40, 10
au.SfxTone 3, 0, 1200, 523, 784, 90, 200
au.SfxNoise 3, 1200, 1800, 100, 4, 50
s = au.SfxSound(3)
h = 0
For i = 0 To 2999
    h = (h * 31 + au.SoundData(s, i)) And &HFFFFFF
Next
Print "sfx 3: len "; au.SoundLength(s); " rate "; au.SoundRate(s); " check "; Hex(h)
v = au.Sfx(3)
Print "voice "; v > 0; au.VoicePlaying(v); au.VoiceVolume(v)
au.Render 22050
Print "done "; au.VoicePlaying(v)
au.SfxDefine 3, 100
Print "redefined len "; au.SoundLength(au.SfxSound(3)); " sfx 9 "; au.Sfx(9)
' tracker extras
s = au.LoadMusic("fx.mod")
Print "speed "; au.SongSpeed(s); " tempo "; au.SongTempo(s); " restart "; au.SongRestart(s)
au.SongTempo(s) = 150
au.SongRestart(s) = 1
au.PlayMusic s
Print "start tempo "; au.Tempo
au.PlayPattern s, 1, 4
For i = 1 To 60
    au.Render 2205
    If au.Pattern <> 1 Then Print "left the pattern": Exit For
Next
Print "pattern mode: pattern "; au.Pattern; " playing "; au.Playing; " ended "; au.SongEnded
Print "chpos "; au.ChannelPos(0) >= 0; " silent ch "; au.ChannelPos(7)
b = au.GetSampleBytes(s, 2)
Print "bytes "; UBound(b) + 1; " = "; au.SampleLength(s, 2); " first "; b(0); b(1)
ReDim c(9)
For i = 0 To 9
    c(i) = (i * 25) And 255
Next
au.SetSampleBytes s, 7, c
Print "set: len "; au.SampleLength(s, 7); " data "; au.SampleData(s, 7, 1); au.SampleData(s, 7, 9)
au.SetSampleBytes s, 7, c, 4
Print "set 4: len "; au.SampleLength(s, 7)
au.SaveMusic s, "x.mod"
t = au.LoadMusic("x.mod")
Print "restart kept "; au.SongRestart(t)
Kill "x.mod"
