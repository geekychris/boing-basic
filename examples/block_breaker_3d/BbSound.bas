' Block Breaker 3D - sound effects (game.c's game_sound_init), waiting for the
' Boing BASIC audio library: Sfx is a no-op until then.
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

Public Sub SoundInit()
End Sub

Public Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
End Sub

Public Sub SoundCleanup()
End Sub
