' Riffwright - the link to the MOD player (the runtime's Boing.Audio object, docs/audio.md)
'
' The song model is in BASIC (Song.bas). The player keeps its own copy of the song: this
' module fills it after a load (the song written to a temporary .mod and loaded with
' LoadMusic) and updates it cell by cell on every edit (the Mirror* subs, called from Edit.bas),
' so the music changes while it plays. Without the Audio object (a runtime without it)
' everything here falls back to a silent simulated clock and the editor still works.
Option Explicit

Public playerOk As Boolean
Public mp As Object
Public auSong As Long            ' the player's song number
Private auPats As Long           ' patterns the player's song has
Public playing As Boolean
Public playMode As Long          ' 0 stopped, 1 song, 2 pattern
Public mirrorCount As Long       ' cells sent to the player (tests)
Private loopPat As Long          ' PlayPattern without player support: the pattern to hold
Private loopPos As Long
Private muted(0 To 7) As Boolean

Public Sub PlayerOpen()
    playerOk = False
    On Error GoTo none
    Set mp = CreateObject("Boing.Audio")
    playerOk = True
    Exit Sub
none:
    Set mp = Nothing
End Sub

Public Sub PlayerClose()
    If playerOk Then
        On Error Resume Next
        mp.StopMusic
        mp.Close
        Set mp = Nothing
    End If
    playerOk = False
End Sub

Private Function TempPath(ByVal ext As String) As String
    Dim t As String
    t = Environ$("TMPDIR")
    If t = "" Then
        TempPath = "T:riffwright_mirror" & ext
    Else
        If Right$(t, 1) <> "/" Then t = t & "/"
        TempPath = t & "riffwright_mirror" & ext
    End If
End Function

' ---------------------------------------------------------------- the song

' the whole song, after a load or a new song
Public Sub MirrorAll()
    Dim p As String, i As Long
    If Not playerOk Then Exit Sub
    On Error GoTo bad
    StopPlayer
    p = TempPath(".mod")
    If Not WriteMod(p) Then Exit Sub
    If auSong <> 0 Then mp.FreeMusic auSong
    auSong = mp.LoadMusic(p)
    Kill p
    mp.EditSong auSong
    auPats = mp.PatternCount(auSong)
    For i = 0 To nch - 1: mp.Mute(i) = muted(i): Next i
    Exit Sub
bad:
    lastError = "player: " & Err.Description
    auSong = 0
End Sub

' the player's note number (1..36) for a period, 0 if it isn't one of ProTracker's notes
Private Function AuNote(ByVal per As Long) As Long
    Dim n As Long
    If per = 0 Then Exit Function
    n = noteOfPer(per And 4095)
    If n >= 13 And n <= 48 Then
        If perOfNote(n) = per Then AuNote = n - 12
    End If
End Function

Public Sub MirrorCell(ByVal k As Long)
    Dim p As Long, r As Long, c As Long, n As Long
    mirrorCount = mirrorCount + 1
    If Not playerOk Or auSong = 0 Then Exit Sub
    c = k Mod MAXCH
    If c >= nch Then Exit Sub
    p = k \ (ROWS * MAXCH)
    r = (k \ MAXCH) Mod ROWS
    On Error GoTo bad
    Do While p >= auPats
        mp.AddPattern auSong
        auPats = mp.PatternCount(auSong)
        If auPats >= MAXPAT Then Exit Do
    Loop
    n = AuNote(cPer(k))
    mp.SetCell auSong, p, r, c, n, cSmp(k), cFx(k), cPrm(k)
    If n = 0 And cPer(k) <> 0 Then mp.CellPeriod(auSong, p, r, c) = cPer(k)
    Exit Sub
bad:
    lastError = "player: " & Err.Description
End Sub

Public Sub MirrorBlock(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    Dim r As Long, c As Long
    For r = r0 To r1
        For c = c0 To c1
            MirrorCell CellIdx(pat, r, c)
        Next c
    Next r
End Sub

Public Sub MirrorSample(ByVal i As Long)
    Dim p As String
    If Not playerOk Or auSong = 0 Then Exit Sub
    On Error GoTo bad
    If smpLen(i) = 0 Then
        mp.SampleLength(auSong, i) = 0
    Else
        ' the data goes over as a WAV file (no loop in it, so nothing is cut)
        p = TempPath(".wav")
        If SaveSampleFile(i, p, "wav") Then
            mp.LoadSample auSong, i, p
            Kill p
        End If
    End If
    mp.SampleName(auSong, i) = CleanName(smpName(i))
    mp.SampleVolume(auSong, i) = smpVol(i)
    mp.SampleFinetune(auSong, i) = FineSigned(i)
    If smpLoopL(i) > 2 Then
        mp.SampleLoopStart(auSong, i) = smpLoopS(i)
        mp.SampleLoopLength(auSong, i) = smpLoopL(i)
    Else
        mp.SampleLoopLength(auSong, i) = 0
    End If
    Exit Sub
bad:
    lastError = "player: " & Err.Description
End Sub

' title, order list, length
Public Sub MirrorSong()
    Dim i As Long
    If Not playerOk Or auSong = 0 Then Exit Sub
    On Error GoTo bad
    mp.SongName(auSong) = TitleText()
    For i = 0 To 127
        If orders(i) >= auPats Then MirrorCell CellIdx(orders(i), 0, 0)     ' makes the pattern
        mp.Order(auSong, i) = orders(i)
    Next i
    mp.SongLength(auSong) = songLen
    Exit Sub
bad:
    lastError = "player: " & Err.Description
End Sub

' ---------------------------------------------------------------- channels

Public Function ChanMuted(ByVal c As Long) As Boolean
    ChanMuted = muted(c)
End Function

Public Sub SetMute(ByVal c As Long, ByVal m As Boolean)
    muted(c) = m
    If playerOk And c < nch Then
        On Error Resume Next
        mp.Mute(c) = m
    End If
End Sub

' 0..64
Public Function ChanVU(ByVal c As Long) As Long
    If playerOk And playing Then ChanVU = mp.ChannelVU(c)
End Function

' the last n output samples of channel c (-128..127) into t(); False when nothing plays
Public Function ScopeLive(ByVal c As Long, t() As Long, ByVal n As Long) As Boolean
    If Not (playerOk And playing) Then Exit Function
    t = mp.Scope(c, n)
    ScopeLive = True
End Function

' ---------------------------------------------------------------- transport
' (without a player: a simulated clock, so follow mode and the display can be tested)
Private simStart As Double
Private simPos As Long, simRow As Long, simPat As Long

Public Sub PlaySongAt(ByVal pos As Long, ByVal row As Long)
    playing = True: playMode = 1
    If playerOk And auSong <> 0 Then
        mp.Loop = True
        mp.PlayMusic auSong, pos, row
        Exit Sub
    End If
    simPos = pos: simRow = row: simPat = orders(pos)
    simStart = Timer
End Sub

Public Sub PlayPatternAt(ByVal pat As Long, ByVal row As Long)
    Dim i As Long
    playing = True: playMode = 2
    loopPat = pat
    If playerOk And auSong <> 0 Then
        ' play from a position that has this pattern and jump back when the song leaves it
        loopPos = -1
        For i = 0 To songLen - 1
            If orders(i) = pat Then loopPos = i: Exit For
        Next i
        If loopPos < 0 Then
            ' not in the song: borrow the first position past the song's end
            If songLen < 128 Then
                loopPos = songLen
                mp.Order(auSong, loopPos) = pat
                mp.SongLength(auSong) = songLen + 1
            Else
                loopPos = 0
            End If
        End If
        mp.Loop = True
        mp.PlayMusic auSong, loopPos, row
        Exit Sub
    End If
    simPos = -1: simRow = row: simPat = pat
    simStart = Timer
End Sub

Public Sub StopPlayer()
    If playing And playMode = 2 And playerOk And auSong <> 0 Then mp.SongLength(auSong) = songLen
    playing = False: playMode = 0
    If playerOk Then
        On Error Resume Next
        mp.StopMusic
    End If
End Sub

Public Sub SeekSong(ByVal pos As Long)
    If playMode <> 1 Then Exit Sub
    If playerOk And auSong <> 0 Then
        mp.JumpTo pos, 0
    Else
        simPos = pos: simPat = orders(pos): simRow = 0: simStart = Timer
    End If
End Sub

Public Sub SetPlayerSpeed()
    If playerOk And playing Then
        mp.Speed = initSpeed
        mp.Tempo = initTempo
    End If
End Sub

' where the player is: position, pattern, row, and how far into the row (0..255)
Public Sub PlayerPoll(pos As Long, pat As Long, row As Long, frac As Long)
    Dim rowsec As Double, t As Double, nrows As Long, sp As Long
    If playerOk And auSong <> 0 Then
        pos = mp.Position
        row = mp.Row
        pat = mp.Pattern
        sp = mp.Speed
        If sp > 0 Then frac = (mp.Tick * 256) \ sp Else frac = 0
        If playMode = 2 Then
            If pos <> loopPos Then mp.JumpTo loopPos, 0: pos = loopPos: pat = loopPat
            If pos >= songLen Then pos = -1
        End If
        If Not mp.Playing Then playing = False: playMode = 0
        Exit Sub
    End If
    rowsec = initSpeed * 2.5 / initTempo
    t = (Timer - simStart) / rowsec
    nrows = Int(t)
    frac = Int((t - nrows) * 256)
    row = simRow + nrows
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
    If playerOk And playing Then CurSpeed = mp.Speed Else CurSpeed = initSpeed
End Function

Public Function CurTempo() As Long
    If playerOk And playing Then CurTempo = mp.Tempo Else CurTempo = initTempo
End Function

' play a note now on a channel (note 13..48 = C-1..B-3), also while the song plays
Public Sub JamNote(ByVal ch As Long, ByVal note As Long, ByVal smp As Long)
    If Not playerOk Or auSong = 0 Then Exit Sub
    If note < 13 Or note > 48 Or smp < 1 Then Exit Sub
    On Error Resume Next
    mp.EditSong auSong
    mp.PlayNote ch, note - 12, smp
End Sub

' play one row of a pattern now (stepping through while editing)
Public Sub JamRow(ByVal pat As Long, ByVal row As Long)
    If Not playerOk Or auSong = 0 Or playing Then Exit Sub
    On Error Resume Next
    mp.PlayRow auSong, pat, row
End Sub

' the play position in sample i, or -1
Public Function PlayerSamplePos(ByVal i As Long) As Long
    PlayerSamplePos = -1
End Function
