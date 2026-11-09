' Drone Courier - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_PICKUP As Long = 0
Public Const SFX_DELIVER As Long = 1
Public Const SFX_BUMP As Long = 2
Public Const SFX_BROKEN As Long = 3
Public Const SFX_LATE As Long = 4
Public Const SFX_GUST As Long = 5
Public Const SFX_DAY As Long = 6
Public Const SFX_OVER As Long = 7
Public Const SFX_WIN As Long = 8
Public Const SFX_HUM As Long = 9

Public sfxCount(0 To 9) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_PICKUP, 1600, 50, 30
    au.SfxTone SFX_PICKUP, 0, 800, 660, 660, 90, 100
    au.SfxTone SFX_PICKUP, 800, 800, 990, 990, 90, 600
    au.SfxDefine SFX_DELIVER, 4800, 60, 50
    au.SfxTone SFX_DELIVER, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_DELIVER, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_DELIVER, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_DELIVER, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_BUMP, 900, 54, 30
    au.SfxNoise SFX_BUMP, 0, 900, 120, 3, 2
    au.SfxDefine SFX_BROKEN, 3000, 60, 50
    au.SfxNoise SFX_BROKEN, 0, 1500, 127, 1, 2
    au.SfxTone SFX_BROKEN, 1500, 1500, 300, 120, 100, 1200
    au.SfxDefine SFX_LATE, 3000, 56, 45
    au.SfxTone SFX_LATE, 0, 3000, 400, 200, 100, 1500
    au.SfxDefine SFX_GUST, 2400, 30, 8
    au.SfxNoise SFX_GUST, 0, 2400, 60, 30, 1200
    au.SfxDefine SFX_DAY, 4800, 60, 55
    au.SfxTone SFX_DAY, 0, 1600, 784, 784, 100, 80
    au.SfxTone SFX_DAY, 1600, 1600, 988, 988, 100, 80
    au.SfxTone SFX_DAY, 3200, 1600, 1175, 1175, 110, 1000
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 440, 110, 110, 3000
    au.SfxDefine SFX_WIN, 6000, 60, 60
    au.SfxTone SFX_WIN, 0, 1500, 784, 784, 100, 80
    au.SfxTone SFX_WIN, 1500, 1500, 1046, 1046, 100, 80
    au.SfxTone SFX_WIN, 3000, 3000, 1568, 1568, 110, 2000
    au.SfxDefine SFX_HUM, 800, 14, 2
    au.SfxTone SFX_HUM, 0, 800, 180, 190, 60, 100
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
