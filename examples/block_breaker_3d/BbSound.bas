' Block Breaker 3D - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_WALL As Long = 0
Public Const SFX_PADDLE As Long = 1
Public Const SFX_BREAK As Long = 2
Public Const SFX_HIT As Long = 3
Public Const SFX_STEEL As Long = 4
Public Const SFX_LOST As Long = 5
Public Const SFX_SERVE As Long = 6
Public Const SFX_CAPSULE As Long = 7
Public Const SFX_CLEAR As Long = 8
Public Const SFX_OVER As Long = 9
Public Const SFX_WIN As Long = 10

Public sfxCount(0 To 10) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_WALL, 200, 20, 5
    au.SfxTone SFX_WALL, 0, 200, 300, 260, 50, 150
    au.SfxDefine SFX_PADDLE, 700, 48, 20
    au.SfxTone SFX_PADDLE, 0, 700, 520, 620, 100, 500
    au.SfxDefine SFX_BREAK, 1400, 50, 25
    au.SfxNoise SFX_BREAK, 0, 700, 90, 3, 2
    au.SfxTone SFX_BREAK, 700, 700, 900, 1500, 80, 600
    au.SfxDefine SFX_HIT, 500, 44, 22
    au.SfxTone SFX_HIT, 0, 500, 1200, 900, 90, 400
    au.SfxDefine SFX_STEEL, 900, 44, 22
    au.SfxTone SFX_STEEL, 0, 900, 2000, 1900, 90, 850
    au.SfxDefine SFX_LOST, 5000, 60, 50
    au.SfxTone SFX_LOST, 0, 5000, 600, 90, 110, 2500
    au.SfxDefine SFX_SERVE, 600, 40, 15
    au.SfxTone SFX_SERVE, 0, 600, 400, 900, 90, 300
    au.SfxDefine SFX_CAPSULE, 3000, 54, 40
    au.SfxTone SFX_CAPSULE, 0, 1000, 659, 659, 90, 120
    au.SfxTone SFX_CAPSULE, 1000, 1000, 880, 880, 90, 120
    au.SfxTone SFX_CAPSULE, 2000, 1000, 1318, 1318, 100, 800
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
