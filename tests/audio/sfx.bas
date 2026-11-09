' sound effects: loaders (8SVX, WAV, raw), synthesis, voices mixed with the music
Dim au As Object, a As Long, b As Long, c As Long, d As Long, v1 As Long, v2 As Long, i As Long
Dim t As Long, sc() As Long
Set au = CreateObject("Boing.Audio")
au.Open "manual", 22050
a = au.LoadSound("beep.wav")
Print "wav: len "; au.SoundLength(a); " rate "; au.SoundRate(a); " bits "; au.SoundBits(a)
b = au.LoadSound("ping.8svx")
Print "8svx: len "; au.SoundLength(b); " rate "; au.SoundRate(b); " bits "; au.SoundBits(b); " loop "; au.SoundLoop(b)
c = au.LoadSound("ping.raw", 11025, "s8")
Print "raw: len "; au.SoundLength(c); " rate "; au.SoundRate(c); " first "; au.SoundData(c, 0); au.SoundData(c, 1)
d = au.SynthTone(200, 880, 220, 48, 1)
Print "tone: len "; au.SoundLength(d); " bits "; au.SoundBits(d)
t = 0
For i = 0 To au.SoundLength(d) - 1
    If Abs(au.SoundData(d, i)) > t Then t = Abs(au.SoundData(d, i))
Next
Print "tone peak "; t
v1 = au.PlaySound(a, 64, -64)
v2 = au.PlaySound(d, 32, 40, 0, True)
Print "voices "; v1; v2; au.VoicePlaying(v1); au.VoicePlaying(v2)
au.Render 4410
Print "after 0.2 s: "; au.VoicePlaying(v1); au.VoicePlaying(v2)
au.VoiceRate(v2) = 44100
au.VoicePan(v2) = -10
Print "rate "; au.VoiceRate(v2); " pan "; au.VoicePan(v2)
au.Render 2205
sc = au.Scope(-1, 256)
t = 0
For i = 0 To 255
    If Abs(sc(i)) > t Then t = Abs(sc(i))
Next
Print "scope peak > 1000: "; t > 1000
au.StopVoice v2
Print "stopped "; au.VoicePlaying(v2)
au.StopVoice v2
' noise, priorities: 8 voices busy with priority 5, a priority 0 sound gets none
c = au.SynthNoise(300, 50, 4, 5)
For i = 1 To 8
    v1 = au.PlaySoundPri(c, 5, 20)
Next
Print "pri 0 voice: "; au.PlaySound(c); " pri 9 voice > 0: "; au.PlaySoundPri(c, 9) > 0
au.StopSounds
' a sound made in BASIC
c = au.CreateSound(1000, 8000, 8)
For i = 0 To 999
    au.SoundData(c, i) = (i Mod 40) * 6 - 120
Next
au.SoundLoop(c) = True
v1 = au.PlaySound(c, 40)
' music under it
d = au.LoadMusic("fx.mod")
au.PlayMusic d
au.Render 22050
Print "looped voice still playing: "; au.VoicePlaying(v1)
au.SoundEnabled = False
Print "disabled: "; au.PlaySound(a); au.VoicePlaying(v1)
au.SoundEnabled = True
au.MusicEnabled = False
au.Render 2205
Print "music off: playing "; au.Playing
Print "hash "; Hex(au.PcmHash)
au.FreeSound a
On Error Resume Next
i = au.PlaySound(a)
Print "freed: "; Err.Number
