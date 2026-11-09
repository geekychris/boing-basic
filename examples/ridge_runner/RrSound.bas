' Ridge Runner - sound effects: the C original's game_sound_init (game.c), the same synthesis on
' Boing.Audio's amiga3d-style effects (docs/audio.md), so they are byte for byte the
' originals'. The game has no music (neither has the C one).
Option Explicit

Public Const SFX_GATE As Long = 0
Public Const SFX_MISS As Long = 1
Public Const SFX_JUMP As Long = 2
Public Const SFX_LAND As Long = 3
Public Const SFX_BUMP As Long = 4
Public Const SFX_FINISH As Long = 5
Public Const SFX_FAIL As Long = 6
Public Const SFX_BEEP As Long = 7
Public Const SFX_GO As Long = 8
Public Const SFX_OVER As Long = 9
Public Const SFX_WIN As Long = 10

Public sfxCount(0 To 10) As Long
Public soundOn As Boolean
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_GATE, 1600, 50, 30
    au.SfxTone SFX_GATE, 0, 800, 880, 880, 90, 100
    au.SfxTone SFX_GATE, 800, 800, 1318, 1318, 90, 600
    au.SfxDefine SFX_MISS, 2400, 54, 30
    au.SfxTone SFX_MISS, 0, 2400, 300, 180, 100, 1200
    au.SfxDefine SFX_JUMP, 1200, 40, 15
    au.SfxTone SFX_JUMP, 0, 1200, 400, 900, 80, 800
    au.SfxDefine SFX_LAND, 1400, 54, 25
    au.SfxNoise SFX_LAND, 0, 1400, 120, 5, 2
    au.SfxDefine SFX_BUMP, 700, 44, 20
    au.SfxNoise SFX_BUMP, 0, 400, 110, 2, 2
    au.SfxTone SFX_BUMP, 400, 300, 200, 150, 90, 250
    au.SfxDefine SFX_FINISH, 4800, 60, 55
    au.SfxTone SFX_FINISH, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_FINISH, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_FINISH, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_FINISH, 3600, 1200, 1046, 1046, 110, 1000
    au.SfxDefine SFX_FAIL, 4000, 60, 55
    au.SfxTone SFX_FAIL, 0, 4000, 392, 196, 100, 2500
    au.SfxDefine SFX_BEEP, 900, 50, 40
    au.SfxTone SFX_BEEP, 0, 900, 660, 660, 90, 300
    au.SfxDefine SFX_GO, 2000, 56, 45
    au.SfxTone SFX_GO, 0, 2000, 1320, 1320, 100, 1200
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
