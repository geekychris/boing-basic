' Canyon Rail - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_SHOT As Long = 0
Public Const SFX_BOOM As Long = 1
Public Const SFX_HIT As Long = 2
Public Const SFX_BOLT As Long = 3
Public Const SFX_EFIRE As Long = 4
Public Const SFX_HURT As Long = 5
Public Const SFX_POD As Long = 6
Public Const SFX_BOSS As Long = 7
Public Const SFX_CLEAR As Long = 8
Public Const SFX_OVER As Long = 9
Public Const SFX_WIN As Long = 10

Public sfxCount(0 To 10) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_SHOT, 500, 36, 10
    au.SfxTone SFX_SHOT, 0, 500, 1800, 700, 80, 400
    au.SfxDefine SFX_BOOM, 3000, 60, 40
    au.SfxNoise SFX_BOOM, 0, 3000, 127, 8, 2
    au.SfxDefine SFX_HIT, 700, 50, 25
    au.SfxTone SFX_HIT, 0, 700, 1200, 900, 90, 500
    au.SfxDefine SFX_BOLT, 900, 50, 25
    au.SfxNoise SFX_BOLT, 0, 400, 110, 2, 2
    au.SfxTone SFX_BOLT, 400, 500, 1600, 2400, 80, 400
    au.SfxDefine SFX_EFIRE, 900, 34, 12
    au.SfxTone SFX_EFIRE, 0, 900, 300, 700, 70, 600
    au.SfxDefine SFX_HURT, 2400, 60, 50
    au.SfxNoise SFX_HURT, 0, 1200, 127, 4, 2
    au.SfxTone SFX_HURT, 1200, 1200, 160, 90, 110, 1000
    au.SfxDefine SFX_POD, 1600, 50, 30
    au.SfxTone SFX_POD, 0, 800, 784, 784, 90, 100
    au.SfxTone SFX_POD, 800, 800, 1175, 1175, 90, 600
    au.SfxDefine SFX_BOSS, 4000, 60, 50
    au.SfxTone SFX_BOSS, 0, 2000, 110, 110, 110, 100
    au.SfxTone SFX_BOSS, 2000, 2000, 98, 98, 110, 1500
    au.SfxDefine SFX_CLEAR, 4800, 60, 55
    au.SfxTone SFX_CLEAR, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_CLEAR, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_CLEAR, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_CLEAR, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 440, 110, 110, 3000
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
