' ScSound - music, effects and the AI's voice on Boing.Audio (game.c's game_sound_init and
' handle_events): "Autopilot Lounge" (scairy.mod), the ten effects synthesised at start-up with
' the same numbers as the C, and the AI's 19 lines (scairy.voc, split into sc_voice_NN.raw by
' tools/make_assets.py: signed 8-bit at 11025 Hz).
Option Explicit

Public Const SFX_CRASH As Long = 0
Public Const SFX_SPLASH As Long = 1
Public Const SFX_SCRAPE As Long = 2
Public Const SFX_CHIME_ON As Long = 3
Public Const SFX_CHIME_OFF As Long = 4
Public Const SFX_CONE As Long = 5
Public Const SFX_SAVE As Long = 6
Public Const SFX_ALERT As Long = 7
Public Const SFX_SIREN As Long = 8
Public Const SFX_BLIP As Long = 9

Public au As Object
Public sfxCount(0 To 9) As Long, voiceCount As Long
Private voice(0 To 19) As Long, song As Long, voiceVoice As Long

Public Sub SoundInit(ByVal withMusic As Boolean)
    Dim ln As Variant, pr As Variant, vl As Variant, k As Long, n As Long, i As Long, s As Long
    Set au = CreateObject("Boing.Audio")
    ln = Array(2048, 4096, 512, 2400, 2400, 320, 3600, 3000, 6000, 600)
    pr = Array(60, 60, 40, 30, 30, 30, 50, 50, 20, 10)
    vl = Array(64, 64, 44, 40, 40, 48, 44, 48, 36, 30)
    For k = 0 To 9
        n = ln(k)
        au.SfxDefine k, n, vl(k), pr(k)
        Select Case k
            Case SFX_CRASH: au.SfxNoise k, 0, n, 127, 2, 8
            Case SFX_SPLASH: au.SfxNoise k, 0, n, 127, 6, 600
            Case SFX_SCRAPE
                au.SfxNoise k, 0, n, 90, 1, 4
                s = au.SfxSound(k)
                For i = 0 To n - 1
                    If ((i \ 6) And 1) <> 0 Then au.SoundData(s, i) = au.SoundData(s, i) \ 2
                Next i
            Case SFX_CHIME_ON: au.SfxTone k, 0, n \ 2, 660, 660, 90, 200: au.SfxTone k, n \ 2, n \ 2, 990, 990, 90, 900
            Case SFX_CHIME_OFF: au.SfxTone k, 0, n \ 2, 990, 990, 90, 200: au.SfxTone k, n \ 2, n \ 2, 660, 660, 90, 900
            Case SFX_CONE: au.SfxTone k, 0, n, 220, 90, 110, n
            Case SFX_SAVE
                au.SfxTone k, 0, 1200, 523, 523, 90, 150
                au.SfxTone k, 1200, 1200, 659, 659, 90, 150
                au.SfxTone k, 2400, 1200, 784, 784, 100, 900
            Case SFX_ALERT: au.SfxTone k, 0, 900, 1200, 1200, 110, 60: au.SfxTone k, 1400, 900, 1200, 1200, 110, 60
            Case SFX_SIREN: au.SfxTone k, 0, n \ 2, 620, 930, 100, 40: au.SfxTone k, n \ 2, n \ 2, 930, 620, 100, 300
            Case SFX_BLIP: au.SfxTone k, 0, n, 1500, 1800, 80, n
        End Select
    Next k
    On Error Resume Next
    For k = 1 To 19
        voice(k) = au.LoadSound(DataFile("sc_voice_" & Format$(k, "00") & ".raw"), 11025, "s8")
        If Err.Number <> 0 Then voice(k) = 0: Err.Clear
    Next k
    If withMusic Then
        song = au.LoadMusic(DataFile("scairy.mod"))
        If Err.Number <> 0 Then song = 0: Err.Clear
        If song <> 0 Then au.PlayMusic song
    End If
    On Error GoTo 0
End Sub

Public Sub SoundCleanup()
    If au Is Nothing Then Exit Sub
    au.StopMusic
    au.StopSounds
End Sub

Public Sub ToggleMusic()
    If Not au Is Nothing Then au.MusicEnabled = Not au.MusicEnabled
End Sub

Public Sub ToggleEffects()
    If Not au Is Nothing Then au.SoundEnabled = Not au.SoundEnabled
End Sub

Public Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
    If Not au Is Nothing Then au.Sfx id
End Sub

' the AI says line m (a3_voice_say: one at a time)
Public Sub VoiceSay(ByVal m As Long)
    If m <= 0 Or m > 19 Then Exit Sub
    voiceCount = voiceCount + 1
    If au Is Nothing Then Exit Sub
    If voice(m) = 0 Then Exit Sub
    If voiceVoice <> 0 Then au.StopVoice voiceVoice
    voiceVoice = au.PlaySoundPri(voice(m), 70, 64)
End Sub

Public Sub SoundEvent(ByVal t As Long, ByVal a As Long)
    Select Case t
        Case EV_SAY: VoiceSay a
        Case EV_AP_ON: Sfx SFX_CHIME_ON
        Case EV_AP_OFF: Sfx SFX_CHIME_OFF
        Case EV_UNAVAILABLE, EV_MULT_UP: Sfx SFX_BLIP
        Case EV_SAVE, EV_ARRIVED: Sfx SFX_SAVE
        Case EV_SCRAPE: Sfx SFX_SCRAPE
        Case EV_CONE: Sfx SFX_CONE
        Case EV_DEBRIS, EV_REAREND, EV_CRASH, EV_ROLL, EV_HIT_ANIMAL: Sfx SFX_CRASH
        Case EV_SPLASH: Sfx SFX_SPLASH
        Case EV_PHANTOM, EV_TICKET: Sfx SFX_ALERT
    End Select
End Sub
