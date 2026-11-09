' PbSound - Boing Pinball's music and sound effects on the Audio object
' (docs/audio.md). The effects are the C original's (game.c's game_sound_init),
' made sample for sample as amiga3d's a3_tone / a3_noise do, 8-bit at 11.8 kHz;
' the music is "Silver Ball Shuffle" (art/boing_pinball.mod). Without the Audio
' object, or without a sound device, the game is silent and nothing else changes.
Option Explicit

Public Const SFX_FLIP As Long = 0
Public Const SFX_BUMPER As Long = 1
Public Const SFX_SLING As Long = 2
Public Const SFX_DROP As Long = 3
Public Const SFX_SPIN As Long = 4
Public Const SFX_LANE As Long = 5
Public Const SFX_SAUCER As Long = 6
Public Const SFX_KICK As Long = 7
Public Const SFX_PLUNGE As Long = 8
Public Const SFX_DRAIN As Long = 9
Public Const SFX_JINGLE As Long = 10
Public Const SFX_BIG As Long = 11
Public Const SFX_WARN As Long = 12
Public Const SFX_RAMP As Long = 13
Public Const SFX_FAIL As Long = 14
Public Const SFX_WALL As Long = 15

Private Const FX_RATE As Long = 11823           ' 3546895 / 300, the Paula period the C plays them at

Public soundOn As Boolean
Public musicOn As Boolean
Public soundsPlayed As Long

Private au As Object
Private haveAudio As Boolean
Private sfxId(0 To 15) As Long
Private sfxVol(0 To 15) As Long
Private sfxPri(0 To 15) As Long
Private song As Long
Private buf() As Long
Private nrng As Long

Private Sub Tone(ByVal n As Long, ByVal f0 As Long, ByVal f1 As Long, ByVal amp As Long, ByVal fade As Long, ByVal at As Long)
    Dim ph As Double, i As Long, f As Long, t As Long, a As Long
    If fade < 1 Then fade = 1
    For i = 0 To n - 1
        f = f0 + ((f1 - f0) * i) \ n
        ph = ph + (f * 65536) \ FX_RATE
        If ph >= 4294967296# Then ph = ph - 4294967296#
        t = Int(ph / 256#) And 255
        If t < 128 Then t = t * 2 - 128 Else t = 383 - t * 2
        a = amp
        If i > n - fade Then a = (amp * (n - i)) \ fade
        buf(at + i) = (t * a) \ 128
    Next i
End Sub

Private Function Noise8() As Long
    Noise8 = (A3Rand(nrng) And 255) - 128         ' (A3Rand's 15 bits: the C's (rng >> 16) & 255)
End Function

Private Sub Noise(ByVal n As Long, ByVal amp As Long, ByVal lp As Long, ByVal attack As Long)
    Dim i As Long, acc As Long, env As Long
    If lp < 1 Then lp = 1
    For i = 0 To n - 1
        If i < attack Then env = (amp * i) \ attack Else env = (amp * (n - i)) \ (n - attack)
        acc = acc + Noise8() - acc \ lp
        buf(i) = ((acc \ lp) * env) \ 128
    Next i
End Sub

Private Sub Arp(notes As Variant, ByVal per As Long, ByVal amp As Long)
    Dim i As Long
    For i = 0 To UBound(notes)
        Tone per, notes(i), notes(i), amp, per \ 3, i * per
    Next i
End Sub

' define effect id: len samples, volume, priority; buf() is filled by the caller first
Private Sub Define(ByVal id As Long, ByVal n As Long, ByVal vol As Long, ByVal pri As Long)
    Dim s As Long, i As Long, v As Long
    n = n And Not 1
    s = au.CreateSound(n, FX_RATE, 8)
    For i = 0 To n - 1
        v = buf(i)
        If v > 127 Then v = 127
        If v < -128 Then v = -128
        au.SoundData(s, i) = v
    Next i
    sfxId(id) = s: sfxVol(id) = vol: sfxPri(id) = pri
End Sub

Private Sub Clear(ByVal n As Long)
    Dim i As Long
    ReDim buf(0 To n)
    For i = 0 To n
        buf(i) = 0
    Next i
End Sub

Public Sub SoundInit(ByVal musicPath As String)
    soundOn = True
    musicOn = True
    nrng = 4242
    On Error Resume Next
    Set au = CreateObject("Boing.Audio")
    If Err.Number <> 0 Or au Is Nothing Then
        haveAudio = False
        Exit Sub
    End If
    haveAudio = True
    Clear 600: Tone 600, 140, 70, 40, 300, 0: Noise 600, 70, 3, 2: Define SFX_FLIP, 600, 40, 20
    Clear 1100: Tone 1100, 620, 240, 110, 500, 0: Noise 400, 50, 1, 2: Define SFX_BUMPER, 1100, 55, 30
    Clear 800: Tone 800, 330, 140, 100, 400, 0: Define SFX_SLING, 800, 45, 25
    Clear 700: Tone 700, 980, 500, 90, 300, 0: Noise 500, 60, 2, 2: Define SFX_DROP, 700, 45, 25
    Clear 200: Tone 200, 1900, 1900, 60, 120, 0: Define SFX_SPIN, 200, 25, 8
    Clear 800: Tone 800, 880, 1320, 90, 300, 0: Define SFX_LANE, 800, 40, 18
    Clear 2400: Tone 2400, 130, 60, 120, 1200, 0: Define SFX_SAUCER, 2400, 55, 30
    Clear 900: Noise 900, 110, 4, 4: Define SFX_KICK, 900, 50, 26
    Clear 2000: Noise 2000, 90, 6, 200: Define SFX_PLUNGE, 2000, 50, 28
    Clear 7000: Tone 7000, 420, 70, 100, 3000, 0: Define SFX_DRAIN, 7000, 55, 40
    Clear 3600: Arp Array(784, 988, 1175, 1568), 900, 90: Define SFX_JINGLE, 3600, 50, 45
    Clear 8400: Arp Array(440, 523, 659, 880, 1047, 1319, 1760), 1200, 100: Define SFX_BIG, 8400, 60, 60
    Clear 4200: Tone 4200, 110, 110, 120, 1500, 0: Define SFX_WARN, 4200, 60, 50
    Clear 3000: Arp Array(523, 784, 1047), 1000, 90: Define SFX_RAMP, 3000, 45, 30
    Clear 3000: Tone 3000, 300, 150, 80, 1500, 0: Define SFX_FAIL, 3000, 40, 25
    Clear 300: Noise 300, 60, 3, 2: Define SFX_WALL, 300, 30, 6
    Erase buf
    If Len(musicPath) > 0 Then
        song = au.LoadMusic(musicPath)
        If Err.Number <> 0 Then song = 0
        If song Then au.PlayMusic song
    End If
    Err.Clear
End Sub

Public Sub Sfx(ByVal id As Long)
    If Not haveAudio Or Not soundOn Then Exit Sub
    If sfxId(id) = 0 Then Exit Sub
    On Error Resume Next
    au.PlaySoundPri sfxId(id), sfxPri(id), sfxVol(id)
    soundsPlayed = soundsPlayed + 1
End Sub

Public Sub SoundToggleMusic()
    musicOn = Not musicOn
    If haveAudio Then
        On Error Resume Next
        au.MusicEnabled = musicOn
    End If
End Sub

Public Function SoundDevice() As String
    If Not haveAudio Then
        SoundDevice = "none"
        Exit Function
    End If
    On Error Resume Next
    SoundDevice = au.Device
End Function

' the sounds for the events of the last step (the C's handle_events)
Public Sub SoundEvents()
    Dim i As Long
    For i = 0 To gNev - 1
        Select Case gev(i).etype
            Case EV_BUMPER: Sfx SFX_BUMPER
            Case EV_SLING: Sfx SFX_SLING
            Case EV_DROP: Sfx SFX_DROP
            Case EV_SPIN: Sfx SFX_SPIN
            Case EV_SENSOR
                If gev(i).kind = SN_LANE Or gev(i).kind = SN_IN Then Sfx SFX_LANE
            Case EV_SAUCER: Sfx SFX_SAUCER
            Case EV_KICK: Sfx SFX_KICK
            Case EV_PLUNGE: Sfx SFX_PLUNGE
            Case EV_DRAIN: Sfx SFX_DRAIN
            Case EV_FLIPSTOP
                If gev(i).up Then Sfx SFX_FLIP
            Case EV_WALL
                If gev(i).val > 900 Then Sfx SFX_WALL
            Case EV_RAMP: Sfx SFX_RAMP
            Case EV_RAMPFAIL: Sfx SFX_FAIL
            Case EV_SKILL, EV_LANESDONE, EV_BANK, EV_LOCK, EV_SAVE, EV_MISSIONSTART: Sfx SFX_JINGLE
            Case EV_MULTIBALL, EV_JACKPOT, EV_MISSIONDONE, EV_SUPERNOVA: Sfx SFX_BIG
            Case EV_TILTWARN, EV_TILT, EV_MISSIONFAIL: Sfx SFX_WARN
        End Select
    Next i
End Sub

Public Sub SoundCleanup()
    If Not haveAudio Then Exit Sub
    On Error Resume Next
    au.StopMusic
    au.StopSounds
    au.Close
    Set au = Nothing
    haveAudio = False
End Sub
