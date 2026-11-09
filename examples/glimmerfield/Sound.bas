' Glimmerfield - music and sound effects (docs/audio.md)
'
' The music is glimmer.mod ("Glimmer Drift", made for the game by tools/modgen/glimmerfield.py
' from synthesised samples). The effects are synthesised at start-up, so the game needs no
' sample files. M toggles the music, S the effects; --nosound starts with both off.
' Game.bas sets bits in sfx (SFX_*) during a frame; SoundFrame plays them after it.
Option Explicit

Public musicOn As Boolean
Public soundOn As Boolean

Private au As Object
Private haveAudio As Boolean
Private problem As String           ' why there is no sound or no music, for the title screen
Private song As Long
Private sShoot As Long, sCrack As Long, sShatter As Long, sWisp As Long
Private sDie As Long, sWave As Long, sLife As Long, sRegrow As Long, sThrust As Long
Private vThrust As Long
Private wasThrust As Boolean

Public Sub SoundInit(ByVal dir As String, ByVal wantSound As Boolean)
    musicOn = wantSound
    soundOn = wantSound
    On Error GoTo NoAudio
    Set au = CreateObject("Boing.Audio")
    au.Open
    ' no ahi.device unit that opens: everything still works, silently
    If au.Device = "none" Then problem = "NO AHI DEVICE: SET ONE UP IN PREFS/AHI"
    sShoot = au.SynthTone(70, 1400, 500, 26, 1)
    sCrack = au.SynthNoise(180, 44, 6, 2)
    sShatter = au.SynthTone(120, 2400, 3200, 22, 2)
    sWisp = au.SynthTone(160, 300, 900, 30, 0)
    sDie = au.SynthNoise(700, 60, 9, 5)
    sWave = au.SynthTone(260, 660, 1320, 30, 2)
    sLife = au.SynthTone(320, 880, 1760, 30, 1)
    sRegrow = au.SynthTone(220, 200, 420, 20, 0)
    sThrust = au.SynthNoise(400, 30, 12, 0)
    au.SoundLoop(sThrust) = True
    au.MusicVolume = 40
    haveAudio = True
    On Error Resume Next
    song = au.LoadMusic(dir & "glimmer.mod")
    If Err.Number <> 0 Then
        If problem = "" Then problem = "NO MUSIC: GLIMMER.MOD MISSING"
        song = 0
        Err.Clear
    End If
    On Error GoTo NoAudio
    au.MusicEnabled = musicOn
    au.SoundEnabled = soundOn
    If song > 0 Then au.PlayMusic song
    Exit Sub
NoAudio:
    haveAudio = False
    problem = "NO SOUND (ERROR " & CStr(Err.Number) & ")"
End Sub

Public Sub SoundToggleMusic()
    musicOn = Not musicOn
    If haveAudio Then au.MusicEnabled = musicOn
End Sub

Public Sub SoundToggleEffects()
    soundOn = Not soundOn
    If haveAudio Then
        au.SoundEnabled = soundOn
        vThrust = 0
        wasThrust = False
    End If
End Sub

Public Sub SoundPause(ByVal p As Boolean)
    If Not haveAudio Then Exit Sub
    If p Then
        au.Pause
        au.StopSounds
        vThrust = 0
        wasThrust = False
    Else
        au.Resume
    End If
End Sub

' play this frame's events; thrust is a looped hiss while the ship thrusts
Public Sub SoundFrame(ByVal events As Long, ByVal thrusting As Boolean, ByVal audible As Boolean)
    Dim v As Long
    If Not haveAudio Or Not soundOn Then Exit Sub
    If Not audible Then thrusting = False: events = 0
    If events <> 0 Then
        If events And SFX_SHOOT Then v = au.PlaySound(sShoot, 34, 0)
        If events And SFX_CRACK Then v = au.PlaySoundPri(sCrack, 1, 50, 0)
        If events And SFX_SHATTER Then v = au.PlaySound(sShatter, 40, 20)
        If events And SFX_WISP Then v = au.PlaySound(sWisp, 40, -20)
        If events And SFX_REGROW Then v = au.PlaySound(sRegrow, 30, 0)
        If events And SFX_DIE Then v = au.PlaySoundPri(sDie, 3, 64, 0)
        If events And SFX_WAVE Then v = au.PlaySoundPri(sWave, 2, 48, 0)
        If events And SFX_LIFE Then v = au.PlaySoundPri(sLife, 2, 48, 0)
    End If
    If thrusting And Not wasThrust Then
        vThrust = au.PlaySoundPri(sThrust, 1, 18, 0)
    ElseIf wasThrust And Not thrusting Then
        au.StopVoice vThrust
        vThrust = 0
    End If
    wasThrust = thrusting
End Sub

' the bar along the bottom of the title screen
Public Function SoundStatus() As String
    If problem <> "" Then
        SoundStatus = problem
    Else
        SoundStatus = "M MUSIC " & IIf(musicOn, "ON", "OFF") & "    S SOUND " & IIf(soundOn, "ON", "OFF")
    End If
End Function

Public Function SoundCpu() As Long
    If haveAudio Then SoundCpu = au.CpuLoad Else SoundCpu = -1
End Function
