' Tank Duel - sound effects (game.c's game_sound_init), waiting for the Boing BASIC
' audio library: Sfx is a no-op until then.
Option Explicit

Public Const SFX_FIRE As Long = 0
Public Const SFX_EFIRE As Long = 1
Public Const SFX_LOB As Long = 2
Public Const SFX_BOOM As Long = 3
Public Const SFX_HIT As Long = 4
Public Const SFX_GLANCE As Long = 5
Public Const SFX_BOUNCE As Long = 6
Public Const SFX_HURT As Long = 7
Public Const SFX_CRATE As Long = 8
Public Const SFX_CLEAR As Long = 9
Public Const SFX_OVER As Long = 10
Public Const SFX_WIN As Long = 11

Public sfxCount(0 To 11) As Long

Public Sub SoundInit()
End Sub

Public Sub Sfx(ByVal id As Long)
    sfxCount(id) = sfxCount(id) + 1
End Sub

Public Sub SoundCleanup()
End Sub
