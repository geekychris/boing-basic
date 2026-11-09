' StSound - music and sound effects (game.c's game_sound_init and handle_events). A stub
' until the Boing BASIC sound library lands: the calls are made where the C makes them.
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

Public sfxCount(0 To 9) As Long          ' effects played (tests)

Public Sub SoundInit()
End Sub

Public Sub SoundCleanup()
End Sub

Private Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
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
