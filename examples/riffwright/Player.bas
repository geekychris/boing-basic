' Riffwright - the link to the MOD player (bb-audio's player object)
'
' The song model is in BASIC (Song.bas); the player keeps its own copy, which this module
' fills when a song is loaded and updates cell by cell on every edit (the Mirror* subs,
' called from Edit.bas). Without a player (the host tests, or no AHI) everything here is
' a no-op and the editor still works.
Option Explicit

Public playerOk As Boolean
Public mp As Object
Public playing As Boolean
Public playMode As Long          ' 0 stopped, 1 song, 2 pattern
Public mirrorCount As Long       ' cells sent to the player (tests)

Public Sub PlayerOpen()
    playerOk = False
End Sub

Public Sub PlayerClose()
    If playerOk Then
        On Error Resume Next
        mp.Stop
        Set mp = Nothing
    End If
    playerOk = False
End Sub

Public Sub MirrorCell(ByVal k As Long)
    mirrorCount = mirrorCount + 1
End Sub

Public Sub MirrorBlock(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    mirrorCount = mirrorCount + (r1 - r0 + 1) * (c1 - c0 + 1)
End Sub

Public Sub MirrorSample(ByVal i As Long)
End Sub

Public Sub MirrorSong()
End Sub

' the whole song, after a load or a new song
Public Sub MirrorAll()
End Sub
