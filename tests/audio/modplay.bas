' MOD playback: render tests/audio/fx.mod (every supported effect) off-line and hash the PCM
Dim au As Object, s As Long, n As Long, lastPos As Long
Set au = CreateObject("Boing.Audio")
au.Open "manual", 22050
Print au.Device; " "; au.Rate
s = au.LoadMusic("fx.mod")
Print "song "; s; " '"; au.SongName(s); "' ch="; au.Channels(s); " len="; au.SongLength(s); " pats="; au.PatternCount(s)
Print "sample 1 "; au.SampleName(s, 1); " len="; au.SampleLength(s, 1); " vol="; au.SampleVolume(s, 1); " loop="; au.SampleLoopLength(s, 1)
Print "sample 6 finetune "; au.SampleFinetune(s, 6)
Print "cell 0/0/0: "; au.NoteName(au.CellNote(s, 0, 0, 0)); " smp "; au.CellSample(s, 0, 0, 0); " fx "; Hex(au.CellEffect(s, 0, 0, 0)); " "; Hex(au.CellParam(s, 0, 0, 0))
au.Loop = False
au.PlayMusic s
lastPos = -1
Do While au.Playing And n < 400
    au.Render 2205
    n = n + 1
    If au.Position <> lastPos Then Print "t="; n; " pos "; au.Position; " row "; au.Row; " speed "; au.Speed; " tempo "; au.Tempo: lastPos = au.Position
Loop
Print "ended "; au.SongEnded; " after "; n; " blocks, playing "; au.Playing
Print "hash "; Hex(au.PcmHash)
' looping: the song ends twice in ~30 s but keeps playing
au.ResetHash
au.Loop = True
au.PlayMusic s
n = 0
Do While au.SongEnded < 2 And n < 800
    au.Render 2205
    n = n + 1
Loop
Print "loop: ended "; au.SongEnded; " at block "; n; " playing "; au.Playing; " pos "; au.Position
Print "hash "; Hex(au.PcmHash)
' mute, solo, VU
au.PlayMusic s
au.Render 4410
Print "vu "; au.ChannelVU(0) > 0; " "; au.ChannelVU(1) > 0
au.Solo 2
au.Render 2205
Print "solo: mute0 "; au.Mute(0); " mute2 "; au.Mute(2); " vu0 "; au.ChannelVU(0)
au.Solo -1
au.Mute(1) = True
Print "mute1 "; au.Mute(1)
au.Mute(1) = False
au.JumpTo 1, 4
au.Render 10
Print "jump: pos "; au.Position; " row "; au.Row; " pattern "; au.Pattern
au.Pause
au.Render 2205
Print "paused "; au.Paused; " row "; au.Row
au.Resume
au.StopMusic
Print "stopped "; au.Playing; " current "; au.CurrentSong
On Error Resume Next
s = au.LoadMusic("nothere.mod")
Print "missing: "; Err.Number
Err.Clear
s = au.LoadMusic("modplay.bas")
Print "not a mod: "; Err.Number
