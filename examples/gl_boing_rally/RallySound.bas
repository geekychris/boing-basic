' Boing Rally - sound effects, synthesised with Boing.Audio's effect generator (docs/audio.md).
' Without audio (the host, AHI missing) the game runs silently.
Option Explicit

Public Const SFX_JUMP As Long = 0
Public Const SFX_GEM As Long = 1
Public Const SFX_CRASH As Long = 2
Public Const SFX_FALL As Long = 3
Public Const SFX_BOOST As Long = 4
Public Const SFX_RAMP As Long = 5
Public Const SFX_LIFE As Long = 6
Public Const SFX_OVER As Long = 7

Public soundOn As Boolean
Public sfxPlayed As Long
Private au As Object

Public Sub SoundInit()
    On Error GoTo noSound
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_JUMP, 1400, 44, 20
    au.SfxTone SFX_JUMP, 0, 1400, 330, 880, 80, 500
    au.SfxDefine SFX_GEM, 2000, 50, 30
    au.SfxTone SFX_GEM, 0, 700, 1318, 1318, 80, 100
    au.SfxTone SFX_GEM, 700, 1300, 1760, 1760, 80, 900
    au.SfxDefine SFX_CRASH, 3200, 60, 50
    au.SfxNoise SFX_CRASH, 0, 3200, 110, 4, 10
    au.SfxDefine SFX_FALL, 4000, 54, 40
    au.SfxTone SFX_FALL, 0, 4000, 700, 90, 90, 1500
    au.SfxDefine SFX_BOOST, 1800, 40, 15
    au.SfxTone SFX_BOOST, 0, 1800, 200, 600, 70, 600
    au.SfxNoise SFX_BOOST, 0, 1800, 30, 20, 200
    au.SfxDefine SFX_RAMP, 2400, 48, 25
    au.SfxTone SFX_RAMP, 0, 2400, 260, 1040, 90, 800
    au.SfxDefine SFX_LIFE, 4200, 56, 45
    au.SfxTone SFX_LIFE, 0, 1000, 659, 659, 90, 80
    au.SfxTone SFX_LIFE, 1000, 1000, 784, 784, 90, 80
    au.SfxTone SFX_LIFE, 2000, 2200, 1318, 1318, 100, 1200
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 392, 98, 110, 3000
    soundOn = True
    Exit Sub
noSound:
    soundOn = False
End Sub

Public Sub Sfx(ByVal id As Long)
    Dim v As Long
    sfxPlayed = sfxPlayed + 1
    If soundOn Then v = au.Sfx(id)
End Sub

' the sound for what happened in the frame (RallyCore's lastEvent)
Public Sub SfxEvent(ByVal ev As String)
    Select Case ev
        Case "jump": Sfx SFX_JUMP
        Case "gem": Sfx SFX_GEM
        Case "crash": Sfx SFX_CRASH
        Case "fall": Sfx SFX_FALL
        Case "boost": Sfx SFX_BOOST
        Case "ramp": Sfx SFX_RAMP
        Case "life": Sfx SFX_LIFE
        Case "over": Sfx SFX_OVER
    End Select
End Sub

Public Sub SoundCleanup()
    If soundOn Then au.Close
    soundOn = False
End Sub
