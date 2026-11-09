' OdSound - the effects on Boing.Audio (game.c's game_sound_init and handle_events), made at
' start-up with Audio's amiga3d-style calls, the same numbers as the C. The original has no
' music.
Option Explicit

Public Const SFX_THRUST As Long = 0
Public Const SFX_DOCK As Long = 1
Public Const SFX_CRASH As Long = 2
Public Const SFX_FUEL As Long = 3
Public Const SFX_OVER As Long = 4
Public Const SFX_WIN As Long = 5

Public au As Object
Public sfxCount(0 To 5) As Long

Public Sub SoundInit()
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_THRUST, 600, 20, 5
    au.SfxNoise SFX_THRUST, 0, 600, 50, 20, 100
    au.SfxDefine SFX_DOCK, 4800, 60, 55
    au.SfxNoise SFX_DOCK, 0, 800, 110, 3, 2
    au.SfxTone SFX_DOCK, 800, 1300, 523, 523, 100, 80
    au.SfxTone SFX_DOCK, 2100, 1300, 659, 659, 100, 80
    au.SfxTone SFX_DOCK, 3400, 1400, 784, 784, 110, 1000
    au.SfxDefine SFX_CRASH, 5000, 64, 60
    au.SfxNoise SFX_CRASH, 0, 3000, 127, 6, 2
    au.SfxTone SFX_CRASH, 3000, 2000, 200, 80, 100, 1800
    au.SfxDefine SFX_FUEL, 2400, 50, 40
    au.SfxTone SFX_FUEL, 0, 800, 880, 880, 90, 100
    au.SfxTone SFX_FUEL, 1600, 800, 880, 880, 90, 600
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 440, 110, 110, 3000
    au.SfxDefine SFX_WIN, 6000, 60, 60
    au.SfxTone SFX_WIN, 0, 1500, 784, 784, 100, 80
    au.SfxTone SFX_WIN, 1500, 1500, 1046, 1046, 100, 80
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

Public Sub SoundThrust()
    Sfx SFX_THRUST
End Sub

Public Sub SoundEvent(ByVal t As Long)
    Select Case t
        Case ODE_DOCK: Sfx SFX_DOCK
        Case ODE_CRASH, ODE_DEBRIS: Sfx SFX_CRASH
        Case ODE_FUEL_OUT: Sfx SFX_FUEL
        Case ODE_OVER: Sfx SFX_OVER
        Case ODE_WIN: Sfx SFX_WIN
    End Select
End Sub
