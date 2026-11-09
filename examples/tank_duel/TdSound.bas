' Tank Duel - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_FIRE As Long = 0
Public Const SFX_EFIRE As Long = 1
Public Const SFX_LOB As Long = 2
Public Const SFX_BOOM As Long = 3
Public Const SFX_HIT As Long = 4
Public Const SFX_GLANCE As Long = 5
Public Const SFX_BOUNCE As Long = 6
Public Const SFX_HURT As Long = 7
Public Const SFX_CRATE As Long = 8
Public Const SFX_CLEAR As Long = 9
Public Const SFX_OVER As Long = 10
Public Const SFX_WIN As Long = 11

Public sfxCount(0 To 11) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_FIRE, 1800, 60, 30
    au.SfxNoise SFX_FIRE, 0, 1800, 127, 3, 2
    au.SfxDefine SFX_EFIRE, 1400, 44, 20
    au.SfxNoise SFX_EFIRE, 0, 1400, 100, 5, 2
    au.SfxDefine SFX_LOB, 1600, 44, 20
    au.SfxTone SFX_LOB, 0, 1600, 300, 900, 80, 900
    au.SfxDefine SFX_BOOM, 4000, 60, 45
    au.SfxNoise SFX_BOOM, 0, 4000, 127, 10, 2
    au.SfxDefine SFX_HIT, 1200, 54, 35
    au.SfxNoise SFX_HIT, 0, 600, 120, 2, 2
    au.SfxTone SFX_HIT, 600, 600, 500, 300, 100, 500
    au.SfxDefine SFX_GLANCE, 900, 50, 30
    au.SfxTone SFX_GLANCE, 0, 900, 2200, 1800, 90, 800
    au.SfxDefine SFX_BOUNCE, 500, 40, 15
    au.SfxTone SFX_BOUNCE, 0, 500, 1500, 1100, 80, 400
    au.SfxDefine SFX_HURT, 2400, 60, 50
    au.SfxNoise SFX_HURT, 0, 1200, 127, 4, 2
    au.SfxTone SFX_HURT, 1200, 1200, 160, 90, 110, 1000
    au.SfxDefine SFX_CRATE, 1400, 50, 25
    au.SfxNoise SFX_CRATE, 0, 1400, 110, 6, 2
    au.SfxDefine SFX_CLEAR, 4800, 60, 55
    au.SfxTone SFX_CLEAR, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_CLEAR, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_CLEAR, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_CLEAR, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 330, 80, 110, 3000
    au.SfxDefine SFX_WIN, 6000, 60, 60
    au.SfxTone SFX_WIN, 0, 1500, 784, 784, 100, 80
    au.SfxTone SFX_WIN, 1500, 1500, 1046, 1046, 100, 80
    au.SfxTone SFX_WIN, 3000, 3000, 1568, 1568, 110, 2000
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
