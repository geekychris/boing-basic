' Lander 3D - music and sound effects through the Audio object (docs/audio.md): the
' original's module (lander_3d.mod, "Quiet Descent") and its six effects, made
' sample for sample as game.c's game_sound_init makes them with amiga3d's a3_tone
' and a3_noise (8-bit, played at Paula period 300 = 11823 Hz).
' Without the Audio object (an older runtime) or a sound device everything is silent
' and the game runs the same.
Option Explicit

Public Const SFX_THRUST As Long = 0
Public Const SFX_RCS As Long = 1
Public Const SFX_LAND As Long = 2
Public Const SFX_CRASH As Long = 3
Public Const SFX_FUEL As Long = 4
Public Const SFX_BEEP As Long = 5

Private Const FX_RATE As Long = 11822        ' A3_FX_RATE: 3546895 \ 300 (the synthesis)
Private Const PLAY_RATE As Long = 11823      ' Paula at period 300 plays 11823 Hz

Public sfxCount(0 To 5) As Long             ' effects played (tests)
Public musicOn As Boolean, soundOn As Boolean
Public sndSum As Long                       ' a checksum of the effects' samples (tests)
Public sndStatus As String                  ' the device and the music, for --log

Private au As Object
Private auOk As Boolean
Private song As Long
Private fxSound(0 To 5) As Long, fxVol(0 To 5) As Long, fxPri(0 To 5) As Long
Private fxData() As Long                    ' the effect being made
Private noiseRng As Long

Private Sub Define(ByVal id As Long, ByVal n As Long, ByVal vol As Long, ByVal pri As Long)
    n = n - (n Mod 2)
    ReDim fxData(0 To n - 1)
    fxVol(id) = vol
    fxPri(id) = pri
End Sub

' the effect made in fxData -> a sound
Private Sub Commit(ByVal id As Long)
    Dim i As Long, n As Long
    n = UBound(fxData) + 1
    For i = 0 To n - 1
        sndSum = Fnv(sndSum, fxData(i))
    Next i
    If Not auOk Then Exit Sub
    fxSound(id) = au.CreateSound(n, PLAY_RATE, 8)
    For i = 0 To n - 1
        au.SoundData(fxSound(id), i) = fxData(i)
    Next i
End Sub

' a3_tone: a triangle sweeping f0 -> f1 Hz, fading over the last `fade` samples
Private Sub Tone(ByVal at As Long, ByVal n As Long, ByVal f0 As Long, ByVal f1 As Long, ByVal amp As Long, ByVal fade As Long)
    Dim ph As Long, i As Long, f As Long, t As Long, a As Long
    If fade < 1 Then fade = 1
    For i = 0 To n - 1
        f = f0 + ((f1 - f0) * i) \ n
        a = amp
        ph = (ph + (f * 65536) \ FX_RATE) And 65535      ' (only bits 8..15 are used)
        t = (ph \ 256) And 255
        If t < 128 Then t = t * 2 - 128 Else t = 383 - t * 2
        If i > n - fade Then a = (amp * (n - i)) \ fade
        fxData(at + i) = (t * a) \ 128
    Next i
End Sub

Private Function Noise8() As Long
    noiseRng = AddW(MulW(noiseRng, 1103515245), 12345)
    Noise8 = (ShrU(noiseRng, 16) And 255) - 128
End Function

' a3_noise: noise decaying (lp: smoothing, attack: samples to full)
Private Sub NoiseFx(ByVal n As Long, ByVal amp As Long, ByVal lp As Long, ByVal attack As Long)
    Dim i As Long, acc As Long, env As Long
    If lp < 1 Then lp = 1
    For i = 0 To n - 1
        If i < attack Then env = (amp * i) \ attack Else env = (amp * (n - i)) \ (n - attack)
        acc = acc + Noise8() - acc \ lp
        fxData(i) = ((acc \ lp) * env) \ 128
    Next i
End Sub

Public Sub SoundInit(ByVal withDevice As Boolean)
    Dim p As String
    A3FixInit
    noiseRng = 4242
    sndSum = FNV_START
    musicOn = True
    soundOn = True
    If withDevice Then
        On Error Resume Next
        Set au = CreateObject("Boing.Audio")
        auOk = (Err.Number = 0)
        Err.Clear
        On Error GoTo 0
    End If
    Define SFX_THRUST, 1200, 40, 10: NoiseFx 1200, 70, 10, 60: Commit SFX_THRUST
    Define SFX_RCS, 300, 22, 8: NoiseFx 300, 50, 1, 10: Commit SFX_RCS
    Define SFX_LAND, 4000, 54, 60
    Tone 0, 1300, 523, 523, 90, 100
    Tone 1300, 1300, 659, 659, 90, 100
    Tone 2600, 1400, 784, 784, 100, 1000
    Commit SFX_LAND
    Define SFX_CRASH, 5000, 64, 60: NoiseFx 5000, 127, 3, 20: Commit SFX_CRASH
    Define SFX_FUEL, 2400, 50, 40
    Tone 0, 1200, 880, 880, 90, 60
    Tone 1200, 1200, 660, 660, 90, 300
    Commit SFX_FUEL
    Define SFX_BEEP, 300, 30, 20: Tone 0, 300, 1400, 1400, 70, 150: Commit SFX_BEEP
    sndStatus = "no sound"
    If Not auOk Then Exit Sub
    p = GameDir()
    On Error Resume Next
    song = au.LoadMusic(p & "lander_3d.mod")
    If Err.Number <> 0 Then song = 0
    Err.Clear
    If song <> 0 Then au.PlayMusic song
    On Error GoTo 0
    sndStatus = "sound " & au.Device & ", music " & IIf(song <> 0, "playing", "not found")
End Sub

Public Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
    If auOk And soundOn Then au.PlaySoundPri fxSound(id), fxPri(id), fxVol(id)
End Sub

Public Sub ToggleMusic()
    musicOn = Not musicOn
    If auOk Then au.MusicEnabled = musicOn
End Sub

Public Sub ToggleSound()
    soundOn = Not soundOn
    If auOk Then
        au.SoundEnabled = soundOn
        If Not soundOn Then au.StopSounds
    End If
End Sub

Public Sub SoundPause(ByVal held As Boolean)
    If Not auOk Or song = 0 Then Exit Sub
    If held Then au.Pause Else au.Resume
End Sub

' the folder with the game's files: beside the program (a native build), else the current
' directory (boing run: App.Path is boing's own folder), or --dir PATH
Public Function GameDir() As String
    Dim p As String, a() As String, i As Long
    a = Split(Trim$(Command$), " ")              ' --dir PATH (boing run on the guest)
    For i = 0 To UBound(a) - 1
        If LCase$(a(i)) = "--dir" Then
            p = a(i + 1)
            If Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
            GameDir = p
            Exit Function
        End If
    Next i
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    On Error Resume Next
    If Len(Dir$(p & "lander_3d.mod")) = 0 Then
        p = CurDir$
        If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    End If
    GameDir = p
End Function

Public Sub SoundCleanup()
    If auOk Then
        au.StopSounds
        au.StopMusic
    End If
End Sub
