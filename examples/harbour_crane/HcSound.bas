' Harbour Crane - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_GRAB As Long = 0
Public Const SFX_RELEASE As Long = 1
Public Const SFX_LAND As Long = 2
Public Const SFX_DENT As Long = 3
Public Const SFX_LOST As Long = 4
Public Const SFX_BUMP As Long = 5
Public Const SFX_SPLASH As Long = 6
Public Const SFX_CLEAR As Long = 7
Public Const SFX_OVER As Long = 8
Public Const SFX_WIN As Long = 9
Public Const SFX_GUST As Long = 10

Public sfxCount(0 To 10) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_GRAB, 900, 44, 20
    au.SfxNoise SFX_GRAB, 0, 300, 80, 2, 2
    au.SfxTone SFX_GRAB, 300, 600, 300, 300, 80, 400
    au.SfxDefine SFX_RELEASE, 600, 40, 20
    au.SfxTone SFX_RELEASE, 0, 600, 500, 350, 80, 400
    au.SfxDefine SFX_LAND, 1600, 54, 30
    au.SfxNoise SFX_LAND, 0, 900, 120, 6, 2
    au.SfxTone SFX_LAND, 900, 700, 140, 110, 90, 600
    au.SfxDefine SFX_DENT, 2400, 60, 40
    au.SfxNoise SFX_DENT, 0, 1200, 127, 2, 2
    au.SfxTone SFX_DENT, 1200, 1200, 220, 160, 110, 1000
    au.SfxDefine SFX_LOST, 6000, 60, 50
    au.SfxNoise SFX_LOST, 0, 3000, 110, 10, 300
    au.SfxTone SFX_LOST, 3000, 3000, 300, 80, 90, 2500
    au.SfxDefine SFX_BUMP, 600, 40, 15
    au.SfxNoise SFX_BUMP, 0, 600, 100, 4, 2
    au.SfxDefine SFX_SPLASH, 3000, 50, 25
    au.SfxNoise SFX_SPLASH, 0, 3000, 90, 14, 400
    au.SfxDefine SFX_CLEAR, 4800, 60, 55
    au.SfxTone SFX_CLEAR, 0, 1200, 392, 392, 100, 80
    au.SfxTone SFX_CLEAR, 1200, 1200, 392, 392, 100, 80
    au.SfxTone SFX_CLEAR, 2400, 2400, 523, 523, 110, 1600
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 330, 90, 110, 3000
    au.SfxDefine SFX_WIN, 6000, 60, 60
    au.SfxTone SFX_WIN, 0, 1500, 523, 523, 100, 80
    au.SfxTone SFX_WIN, 1500, 1500, 659, 659, 100, 80
    au.SfxTone SFX_WIN, 3000, 3000, 784, 784, 110, 2000
    au.SfxDefine SFX_GUST, 2400, 34, 10
    au.SfxNoise SFX_GUST, 0, 2400, 60, 30, 1200
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
