Option Explicit

Private au As Audio
Private haveAudio As Boolean
Private song As Long
Private sShoot As Long, sBoom As Long, sThrust As Long
Private vThrust As Long

Public Sub SoundInit(ByVal dir As String)
    On Error GoTo NoAudio
    Set au = CreateObject("Boing.Audio")
    au.Open
    sShoot = au.SynthTone(70, 1400, 500, 26, 1)
    sBoom = au.SynthNoise(700, 60, 9, 5)
    sThrust = au.SynthNoise(400, 30, 12, 0)
    au.SoundLoop(sThrust) = True
    au.MusicVolume = 40
    haveAudio = True
    On Error Resume Next
    song = au.LoadMusic(dir & "game.mod")      ' no music file: play without music
    If Err.Number = 0 Then au.PlayMusic song
    Exit Sub
NoAudio:
    haveAudio = False
End Sub

Public Sub SoundShoot()
    If haveAudio Then au.PlaySound sShoot, 40
End Sub

Public Sub SoundBoom()
    If haveAudio Then au.PlaySoundPri sBoom, 10, 64     ' more important than shots
End Sub

' call every frame with the thrust key's state: a looping engine noise
Public Sub SoundThrust(ByVal on_ As Boolean)
    If Not haveAudio Then Exit Sub
    If on_ And vThrust = 0 Then vThrust = au.PlaySound(sThrust, 30)
    If Not on_ And vThrust <> 0 Then au.StopVoice vThrust: vThrust = 0
End Sub

Public Sub SoundMusicSwitch()
    If haveAudio Then au.MusicEnabled = Not au.MusicEnabled
End Sub

Sub Main()
    SoundInit "PROGDIR:"
    SoundShoot
    SoundBoom
End Sub
