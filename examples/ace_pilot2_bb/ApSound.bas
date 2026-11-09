' ApSound - the effects on Boing.Audio (game.c's game_sound_init and handle_events), made at
' start-up with Audio's amiga3d-style calls, the same numbers as the C. Like the C, no music.
Option Explicit

Public Const SFX_GUN As Long = 0
Public Const SFX_EGUN As Long = 1
Public Const SFX_HIT As Long = 2
Public Const SFX_BOOM As Long = 3
Public Const SFX_FLAK As Long = 4
Public Const SFX_HURT As Long = 5
Public Const SFX_JAM As Long = 6
Public Const SFX_STALL As Long = 7
Public Const SFX_MARK As Long = 8
Public Const SFX_DONE As Long = 9
Public Const SFX_FAIL As Long = 10
Public Const SFX_LAND As Long = 11
Public Const SFX_WIN As Long = 12

Public au As Object
Public sfxCount(0 To 12) As Long

Public Sub SoundInit()
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_GUN, 700, 50, 20: au.SfxNoise SFX_GUN, 0, 700, 120, 2, 1
    au.SfxDefine SFX_EGUN, 700, 34, 15: au.SfxNoise SFX_EGUN, 0, 700, 90, 4, 1
    au.SfxDefine SFX_HIT, 600, 46, 25: au.SfxTone SFX_HIT, 0, 600, 1400, 900, 90, 500
    au.SfxDefine SFX_BOOM, 5000, 62, 45: au.SfxNoise SFX_BOOM, 0, 5000, 127, 12, 2
    au.SfxDefine SFX_FLAK, 2600, 50, 30: au.SfxNoise SFX_FLAK, 0, 2600, 120, 16, 4
    au.SfxDefine SFX_HURT, 1600, 58, 40
    au.SfxNoise SFX_HURT, 0, 800, 127, 3, 2: au.SfxTone SFX_HURT, 800, 800, 300, 160, 100, 700
    au.SfxDefine SFX_JAM, 1200, 50, 35
    au.SfxTone SFX_JAM, 0, 400, 900, 900, 90, 100: au.SfxTone SFX_JAM, 400, 800, 500, 400, 90, 700
    au.SfxDefine SFX_STALL, 2400, 48, 30: au.SfxTone SFX_STALL, 0, 2400, 700, 650, 90, 400
    au.SfxDefine SFX_MARK, 2400, 54, 35
    au.SfxTone SFX_MARK, 0, 1200, 784, 784, 100, 80: au.SfxTone SFX_MARK, 1200, 1200, 1046, 1046, 100, 900
    au.SfxDefine SFX_DONE, 4800, 60, 55
    au.SfxTone SFX_DONE, 0, 1200, 523, 523, 100, 80: au.SfxTone SFX_DONE, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_DONE, 2400, 1200, 784, 784, 100, 80: au.SfxTone SFX_DONE, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_FAIL, 6000, 60, 60: au.SfxTone SFX_FAIL, 0, 6000, 330, 80, 110, 3000
    au.SfxDefine SFX_LAND, 1800, 50, 30: au.SfxNoise SFX_LAND, 0, 1800, 80, 20, 200
    au.SfxDefine SFX_WIN, 6000, 60, 60
    au.SfxTone SFX_WIN, 0, 1500, 784, 784, 100, 80: au.SfxTone SFX_WIN, 1500, 1500, 1046, 1046, 100, 80
    au.SfxTone SFX_WIN, 3000, 3000, 1568, 1568, 110, 2000
End Sub

Public Sub SoundCleanup()
    If au Is Nothing Then Exit Sub
    au.StopSounds
End Sub

Public Sub ToggleEffects()
    If au Is Nothing Then Exit Sub
    au.SoundEnabled = Not au.SoundEnabled
End Sub

Private Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
    If Not au Is Nothing Then au.Sfx id
End Sub

' the sound for an event (a: the event's first value)
Public Sub SoundEvent(ByVal t As Long, ByVal a As Long)
    Select Case t
        Case APE_FIRE: Sfx SFX_GUN
        Case APE_HIT: Sfx SFX_HIT
        Case APE_KILL, APE_GKILL: Sfx SFX_BOOM
        Case APE_FLAK: Sfx SFX_FLAK
        Case APE_HURT: Sfx SFX_HURT
        Case APE_JAM: Sfx SFX_JAM
        Case APE_STALL: Sfx SFX_STALL
        Case APE_WAYPOINT, APE_OBJECTIVE, APE_REARMED: Sfx SFX_MARK
        Case APE_DONE: Sfx SFX_DONE
        Case APE_FAILED: Sfx SFX_FAIL
        Case APE_CRASH: If a = 0 Then Sfx SFX_BOOM
        Case APE_LANDED: Sfx SFX_LAND
        Case APE_BOMBS: Sfx SFX_FLAK
    End Select
End Sub

Public Sub SoundEnd(ByVal won As Boolean)
    If won Then Sfx SFX_WIN Else Sfx SFX_FAIL
End Sub
