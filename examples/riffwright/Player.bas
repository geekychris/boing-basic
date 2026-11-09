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

' ---- per-channel state for the display
Private muted(0 To 7) As Boolean

Public Function ChanMuted(ByVal c As Long) As Boolean
    ChanMuted = muted(c)
End Function

Public Sub SetMute(ByVal c As Long, ByVal m As Boolean)
    muted(c) = m
End Sub

' 0..64
Public Function ChanVU(ByVal c As Long) As Long
    ChanVU = 0
End Function

' the last n output samples of channel c (-128..127) into a()
Public Sub ScopeData(ByVal c As Long, a() As Long, ByVal n As Long)
    Dim i As Long
    For i = 0 To n - 1: a(i) = 0: Next i
End Sub

' ---- transport (no player: a simulated clock, so follow mode and the display can be tested)
Private simStart As Double
Private simPos As Long, simRow As Long, simPat As Long

Public Sub PlaySongAt(ByVal pos As Long, ByVal row As Long)
    playing = True: playMode = 1
    simPos = pos: simRow = row: simPat = orders(pos)
    simStart = Timer
End Sub

Public Sub PlayPatternAt(ByVal pat As Long, ByVal row As Long)
    playing = True: playMode = 2
    simPos = -1: simRow = row: simPat = pat
    simStart = Timer
End Sub

Public Sub StopPlayer()
    playing = False: playMode = 0
End Sub

Public Sub SeekSong(ByVal pos As Long)
    If playMode = 1 Then simPos = pos: simPat = orders(pos): simRow = 0: simStart = Timer
End Sub

Public Sub SetPlayerSpeed()
End Sub

' where the player is: position, pattern, row, and how far into the row (0..255)
Public Sub PlayerPoll(pos As Long, pat As Long, row As Long, frac As Long)
    Dim rowsec As Double, t As Double, rows As Long
    rowsec = initSpeed * 2.5 / initTempo
    t = (Timer - simStart) / rowsec
    rows = Int(t)
    frac = Int((t - rows) * 256)
    row = simRow + rows
    pos = simPos: pat = simPat
    Do While row >= ROWS
        row = row - ROWS
        If playMode = 1 Then
            pos = pos + 1
            If pos >= songLen Then pos = 0
            pat = orders(pos)
        End If
    Loop
End Sub

Public Function CurSpeed() As Long
    CurSpeed = initSpeed
End Function

Public Function CurTempo() As Long
    CurTempo = initTempo
End Function

Public Sub JamNote(ByVal ch As Long, ByVal note As Long, ByVal smp As Long)
End Sub

' the play position in sample i, or -1
Public Function PlayerSamplePos(ByVal i As Long) As Long
    PlayerSamplePos = -1
End Function
