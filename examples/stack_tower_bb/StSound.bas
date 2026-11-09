' StSound - music and sound effects on the Boing.Audio object (game.c's game_sound_init
' and handle_events): the original's module, "Tower Climb", and its ten effects made at
' start-up with the amiga3d calls (Audio's SfxDefine / SfxTone / SfxNoise are a3d_sound.c's
' arithmetic, so they are the same samples).
Option Explicit

Public Const SFX_MOVE As Long = 0
Public Const SFX_ROTATE As Long = 1
Public Const SFX_DROP As Long = 2
Public Const SFX_LOCK As Long = 3
Public Const SFX_CLEAR As Long = 4
Public Const SFX_LEVEL As Long = 5
Public Const SFX_OVER As Long = 6
Public Const SFX_HOLD As Long = 7
Public Const SFX_GARBAGE As Long = 8
Public Const SFX_WIN As Long = 9

Public au As Object
Public sfxCount(0 To 9) As Long          ' effects played (tests)
Private song As Long

Public Sub SoundInit(ByVal withMusic As Boolean)
    Set au = CreateObject("Boing.Audio")
    au.SfxDefine SFX_MOVE, 160, 24, 10
    au.SfxTone SFX_MOVE, 0, 160, 900, 900, 60, 120
    au.SfxDefine SFX_ROTATE, 300, 30, 12
    au.SfxTone SFX_ROTATE, 0, 300, 700, 1100, 70, 200
    au.SfxDefine SFX_DROP, 900, 50, 30
    au.SfxNoise SFX_DROP, 0, 900, 110, 4, 4
    au.SfxDefine SFX_LOCK, 400, 40, 20
    au.SfxTone SFX_LOCK, 0, 400, 220, 140, 90, 380
    au.SfxDefine SFX_CLEAR, 3000, 50, 40
    au.SfxTone SFX_CLEAR, 0, 1000, 523, 523, 90, 120
    au.SfxTone SFX_CLEAR, 1000, 1000, 659, 659, 90, 120
    au.SfxTone SFX_CLEAR, 2000, 1000, 1046, 1046, 100, 800
    au.SfxDefine SFX_LEVEL, 3600, 50, 45
    au.SfxTone SFX_LEVEL, 0, 1200, 392, 392, 90, 100
    au.SfxTone SFX_LEVEL, 1200, 1200, 523, 523, 90, 100
    au.SfxTone SFX_LEVEL, 2400, 1200, 784, 784, 100, 1000
    au.SfxDefine SFX_OVER, 6000, 60, 60
    au.SfxTone SFX_OVER, 0, 6000, 440, 110, 110, 3000
    au.SfxDefine SFX_HOLD, 400, 30, 12
    au.SfxTone SFX_HOLD, 0, 400, 1300, 700, 70, 300
    au.SfxDefine SFX_GARBAGE, 1400, 50, 30
    au.SfxNoise SFX_GARBAGE, 0, 1400, 120, 8, 200
    au.SfxDefine SFX_WIN, 4800, 60, 60
    au.SfxTone SFX_WIN, 0, 1200, 523, 523, 100, 80
    au.SfxTone SFX_WIN, 1200, 1200, 659, 659, 100, 80
    au.SfxTone SFX_WIN, 2400, 1200, 784, 784, 100, 80
    au.SfxTone SFX_WIN, 3600, 1200, 1046, 1046, 110, 1000
    If withMusic Then
        On Error Resume Next
        song = au.LoadMusic(DataFile("stack_tower.mod"))
        If Err.Number <> 0 Then song = 0
        On Error GoTo 0
        If song <> 0 Then au.PlayMusic song
    End If
End Sub

Public Sub SoundCleanup()
    If au Is Nothing Then Exit Sub
    au.StopMusic
    au.StopSounds
End Sub

Public Sub ToggleMusic()
    au.MusicEnabled = Not au.MusicEnabled
End Sub

Public Sub ToggleEffects()
    au.SoundEnabled = Not au.SoundEnabled
End Sub

Private Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
    If Not au Is Nothing Then au.Sfx id
End Sub

' the sound for a rules event
Public Sub SoundEvent(ByVal t As Long)
    Select Case t
        Case STE_MOVE: Sfx SFX_MOVE
        Case STE_ROTATE, STE_KICK: Sfx SFX_ROTATE
        Case STE_DROP: Sfx SFX_DROP
        Case STE_LOCK: Sfx SFX_LOCK
        Case STE_HOLD: Sfx SFX_HOLD
        Case STE_GARBAGE: Sfx SFX_GARBAGE
        Case STE_CLEAR: Sfx SFX_CLEAR
        Case STE_LEVEL: Sfx SFX_LEVEL
        Case STE_OVER: Sfx SFX_OVER
        Case STE_WIN: Sfx SFX_WIN
    End Select
End Sub
