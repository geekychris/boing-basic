' Marble Tilt - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_WALL As Long = 0
Public Const SFX_BUMP As Long = 1
Public Const SFX_FALL As Long = 2
Public Const SFX_RESPAWN As Long = 3
Public Const SFX_CP As Long = 4
Public Const SFX_GATE As Long = 5
Public Const SFX_EXIT As Long = 6
Public Const SFX_OVER As Long = 7
Public Const SFX_WIN As Long = 8

Public sfxCount(0 To 8) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_WALL, 400, 40, 10
    au.SfxNoise SFX_WALL, 0, 400, 90, 3, 2
    au.SfxDefine SFX_BUMP, 900, 54, 25
    au.SfxTone SFX_BUMP, 0, 900, 900, 1500, 100, 700
    au.SfxDefine SFX_FALL, 3000, 56, 40
    au.SfxTone SFX_FALL, 0, 3000, 800, 120, 100, 1500
    au.SfxDefine SFX_RESPAWN, 800, 44, 20
    au.SfxTone SFX_RESPAWN, 0, 800, 600, 900, 80, 500
    au.SfxDefine SFX_CP, 1600, 50, 30
    au.SfxTone SFX_CP, 0, 800, 784, 784, 90, 100
    au.SfxTone SFX_CP, 800, 800, 1046, 1046, 90, 600
    au.SfxDefine SFX_GATE, 700, 34, 10
    au.SfxNoise SFX_GATE, 0, 700, 70, 12, 300
    au.SfxDefine SFX_EXIT, 4800, 60, 55
    au.SfxTone SFX_EXIT, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_EXIT, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_EXIT, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_EXIT, 3600, 1200, 1046, 1046, 110, 1000
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
