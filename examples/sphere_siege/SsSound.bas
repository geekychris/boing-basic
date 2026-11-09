' Sphere Siege - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_SHOT As Long = 0
Public Const SFX_BOOM As Long = 1
Public Const SFX_HIT As Long = 2
Public Const SFX_EFIRE As Long = 3
Public Const SFX_HURT As Long = 4
Public Const SFX_WAVE As Long = 5
Public Const SFX_CLEAR As Long = 6
Public Const SFX_OVER As Long = 7
Public Const SFX_LIFE As Long = 8
Public Const SFX_SWOOP As Long = 9

Public sfxCount(0 To 9) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_SHOT, 600, 34, 10
    au.SfxTone SFX_SHOT, 0, 600, 2200, 900, 70, 450
    au.SfxDefine SFX_BOOM, 3200, 60, 40
    au.SfxNoise SFX_BOOM, 0, 3200, 127, 6, 2
    au.SfxDefine SFX_HIT, 700, 50, 25
    au.SfxTone SFX_HIT, 0, 700, 900, 1400, 90, 500
    au.SfxDefine SFX_EFIRE, 900, 30, 12
    au.SfxTone SFX_EFIRE, 0, 900, 500, 260, 70, 600
    au.SfxDefine SFX_HURT, 4000, 64, 55
    au.SfxNoise SFX_HURT, 0, 2000, 127, 3, 2
    au.SfxTone SFX_HURT, 2000, 2000, 200, 60, 110, 1600
    au.SfxDefine SFX_WAVE, 3600, 56, 45
    au.SfxTone SFX_WAVE, 0, 1200, 392, 392, 100, 80
    au.SfxTone SFX_WAVE, 1200, 1200, 523, 523, 100, 80
    au.SfxTone SFX_WAVE, 2400, 1200, 784, 784, 100, 900
    au.SfxDefine SFX_CLEAR, 4800, 60, 55
    au.SfxTone SFX_CLEAR, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_CLEAR, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_CLEAR, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_CLEAR, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 440, 90, 110, 3000
    au.SfxDefine SFX_LIFE, 2400, 56, 50
    au.SfxTone SFX_LIFE, 0, 1200, 1046, 1046, 100, 80
    au.SfxTone SFX_LIFE, 1200, 1200, 1568, 1568, 100, 900
    au.SfxDefine SFX_SWOOP, 1600, 26, 8
    au.SfxTone SFX_SWOOP, 0, 1600, 1500, 400, 60, 800
    soundOn = True
    Exit Sub
noSound:
    soundOn = False
End Sub

Public Sub Sfx(ByVal id As Long)
    Dim v As Long
    sfxCount(id) = sfxCount(id) + 1
    If soundOn Then v = au.Sfx(id)
End Sub

Public Function SfxTotal() As Long
    Dim i As Long
    For i = 0 To UBound(sfxCount)
        SfxTotal = SfxTotal + sfxCount(i)
    Next i
End Function

Public Sub SoundCleanup()
    If soundOn Then au.Close
    soundOn = False
End Sub
