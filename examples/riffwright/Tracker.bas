' Riffwright - the editor: cursor, views, keys, and what a frame shows
'
' Independent of the window: the form (main.bas) passes keys to HandleKey and calls Frame
' from its timer, and the host tests do the same with an off-screen canvas. Things that need
' the window (file requesters, help, quitting) are left in reqAction for the form to do.
Option Explicit

Public Const V_PATTERN As Long = 0
Public Const V_SAMPLES As Long = 1
Public Const V_SONG As Long = 2

Public curView As Long
Public curPos As Long             ' order list position being edited
Public curPat As Long             ' pattern being edited
Public curRow As Long
Public curCh As Long
Public curField As Long           ' 0 note, 1/2 sample, 3 effect, 4/5 parameter
Public octave As Long             ' 1..3: the lower piano row starts at C of this octave
Public curSmp As Long             ' 1..31, the sample new notes get
Public editOn As Boolean
Public followOn As Boolean
Public selOn As Boolean
Public selR0 As Long, selC0 As Long, selR1 As Long, selC1 As Long
Public smpField As Long           ' sample view: 0 name .. 4 loop length
Public smpZoomS As Long, smpZoomL As Long
Public songField As Long          ' song view: 0 title .. 4 restart, 5 order grid

Public reqAction As String        ' for the form: "open", "save", "saveas", "new", "quit", "help",
                                  ' "loadsample", "savesample", "title", "samplename"
Public message As String
Public msgTime As Double
Public frameDirty As Boolean

Private typedOrder As Long        ' song view: digits typed into an order entry
Private typedCount As Long

Public Sub TrackerInit()
    InitTables
    octave = 2
    curSmp = 1
    followOn = True
    editStep = 1
    curView = V_PATTERN
    ResetCursor
End Sub

Public Sub ResetCursor()
    curPos = 0
    curPat = orders(0)
    curRow = 0
    curCh = 0
    curField = 0
    selOn = False
    smpZoomS = 0: smpZoomL = 0
    sideDirty = True
    InvalidatePattern
    frameDirty = True
    lastView = -1
End Sub

Public Sub Say(ByVal s As String)
    message = s
    msgTime = Timer
    frameDirty = True
End Sub

' ---------------------------------------------------------------- keys

' piano key → semitone above the lower row's C, or -1
Public Function PianoOffset(ByVal k As Integer) As Long
    PianoOffset = -1
    Select Case k
        Case vbKeyZ: PianoOffset = 0
        Case vbKeyS: PianoOffset = 1
        Case vbKeyX: PianoOffset = 2
        Case vbKeyD: PianoOffset = 3
        Case vbKeyC: PianoOffset = 4
        Case vbKeyV: PianoOffset = 5
        Case vbKeyG: PianoOffset = 6
        Case vbKeyB: PianoOffset = 7
        Case vbKeyH: PianoOffset = 8
        Case vbKeyN: PianoOffset = 9
        Case vbKeyJ: PianoOffset = 10
        Case vbKeyM: PianoOffset = 11
        Case 256 + &H38: PianoOffset = 12       ' ,
        Case vbKeyL: PianoOffset = 13
        Case 256 + &H39: PianoOffset = 14       ' .
        Case 256 + &H29: PianoOffset = 15       ' ;
        Case 256 + &H3A: PianoOffset = 16       ' /
        Case vbKeyQ: PianoOffset = 12
        Case vbKey2: PianoOffset = 13
        Case vbKeyW: PianoOffset = 14
        Case vbKey3: PianoOffset = 15
        Case vbKeyE: PianoOffset = 16
        Case vbKeyR: PianoOffset = 17
        Case vbKey5: PianoOffset = 18
        Case vbKeyT: PianoOffset = 19
        Case vbKey6: PianoOffset = 20
        Case vbKeyY: PianoOffset = 21
        Case vbKey7: PianoOffset = 22
        Case vbKeyU: PianoOffset = 23
        Case vbKeyI: PianoOffset = 24
        Case vbKey9: PianoOffset = 25
        Case vbKeyO: PianoOffset = 26
        Case vbKey0: PianoOffset = 27
        Case vbKeyP: PianoOffset = 28
        Case 256 + &H1A: PianoOffset = 29       ' [
        Case 256 + &HC: PianoOffset = 30        ' =
        Case 256 + &H1B: PianoOffset = 31       ' ]
    End Select
End Function

' a hex digit key → 0..15, or -1
Public Function HexKey(ByVal k As Integer) As Long
    HexKey = -1
    If k >= vbKey0 And k <= vbKey9 Then HexKey = k - vbKey0
    If k >= vbKeyA And k <= vbKeyF Then HexKey = k - vbKeyA + 10
    ' keypad digits
    Select Case k
        Case 256 + &HF: HexKey = 0
        Case 256 + &H1D To 256 + &H1F: HexKey = k - 256 - &H1D + 1
        Case 256 + &H2D To 256 + &H2F: HexKey = k - 256 - &H2D + 4
        Case 256 + &H3D To 256 + &H3F: HexKey = k - 256 - &H3D + 7
    End Select
End Function

Public Sub HandleKey(ByVal k As Integer, ByVal sh As Integer)
    Dim shift As Boolean, ctrl As Boolean, alt As Boolean, amiga As Boolean
    shift = (sh And 1) <> 0: ctrl = (sh And 2) <> 0: alt = (sh And 4) <> 0: amiga = (sh And 8) <> 0
    frameDirty = True
    ' keys that work in every view
    If amiga Then
        Select Case k
            Case vbKeyO: reqAction = "open": Exit Sub
            Case vbKeyS: If shift Then reqAction = "saveas" Else reqAction = "save"
                Exit Sub
            Case vbKeyN: reqAction = "new": Exit Sub
            Case vbKeyQ: reqAction = "quit": Exit Sub
            Case vbKeyZ: If shift Then DoRedo Else DoUndo
                Exit Sub
            Case vbKeyY: DoRedo: Exit Sub
            Case vbKey1: SetView V_PATTERN: Exit Sub
            Case vbKey2: SetView V_SAMPLES: Exit Sub
            Case vbKey3: SetView V_SONG: Exit Sub
        End Select
    End If
    Select Case k
        Case vbKeyF1: If octave > 1 Then octave = octave - 1
            Say "octave " & octave: Exit Sub
        Case vbKeyF2: If octave < 3 Then octave = octave + 1
            Say "octave " & octave: Exit Sub
        Case vbKeyF3: SelectSample curSmp - 1: Exit Sub
        Case vbKeyF4: SelectSample curSmp + 1: Exit Sub
        Case vbKeyF5: StartSong curPos, 0: Exit Sub
        Case vbKeyF6: StartPattern curPat, 0: Exit Sub
        Case vbKeyF7
            If curView = V_PATTERN Then StartSong curPos, curRow Else StartSong curPos, 0
            Exit Sub
        Case vbKeyF8, vbKeyEscape: StopSong: Exit Sub
        Case vbKeyF9: followOn = Not followOn
            If followOn Then Say "follow on" Else Say "follow off"
            Exit Sub
        Case vbKeyF10: SetView (curView + 1) Mod 3: Exit Sub
        Case 47: reqAction = "help": Exit Sub                    ' Help
    End Select
    Select Case curView
        Case V_PATTERN: PatternKey k, shift, ctrl, alt, amiga
        Case V_SAMPLES: SampleKey k, shift, ctrl, alt, amiga
        Case V_SONG: SongKey k, shift, ctrl, alt, amiga
    End Select
End Sub

Public Sub SetView(ByVal v As Long)
    curView = v
    sideDirty = True
    frameDirty = True
    Select Case v
        Case V_PATTERN: Say "pattern editor"
        Case V_SAMPLES: Say "sample editor"
        Case V_SONG: Say "song settings"
    End Select
End Sub

Public Sub DoUndo()
    Dim p As Long
    p = LastStepPattern(False)
    If Undo() Then
        If p >= 0 Then GoPattern p
        AfterBigChange
        Say lastChanged
    Else
        Say "nothing to undo"
    End If
End Sub

Public Sub DoRedo()
    Dim p As Long
    p = LastStepPattern(True)
    If Redo() Then
        If p >= 0 Then GoPattern p
        AfterBigChange
        Say lastChanged
    Else
        Say "nothing to redo"
    End If
End Sub

' after undo/redo, a load or a block operation: redraw everything
Public Sub AfterBigChange()
    InvalidatePattern
    sideDirty = True
    frameDirty = True
    If curPos >= songLen Then curPos = songLen - 1
End Sub

' show pattern p (keeps the order position if it plays p)
Private Sub GoPattern(ByVal p As Long)
    curPat = p
End Sub

Public Sub SelectSample(ByVal i As Long)
    If i < 1 Then i = 1
    If i > NSMP Then i = NSMP
    curSmp = i
    smpZoomS = 0: smpZoomL = 0
    sideDirty = True
    Say "sample " & Hex2(i) & " " & SampleText(i)
End Sub

Private Sub MoveRow(ByVal d As Long, ByVal shift As Boolean)
    If shift Then
        If Not selOn Then selOn = True: selR0 = curRow: selC0 = curCh: selC1 = curCh
    Else
        selOn = False
    End If
    curRow = curRow + d
    If curRow < 0 Then curRow = curRow + ROWS
    If curRow > ROWS - 1 Then curRow = curRow - ROWS
    If shift Then selR1 = curRow
End Sub

Private Sub MoveField(ByVal d As Long, ByVal shift As Boolean)
    If shift Then
        ' extend the selection by channels
        If Not selOn Then selOn = True: selR0 = curRow: selR1 = curRow: selC0 = curCh
        curCh = curCh + d
        If curCh < 0 Then curCh = 0
        If curCh > nch - 1 Then curCh = nch - 1
        selC1 = curCh
        Exit Sub
    End If
    selOn = False
    curField = curField + d
    If curField > 5 Then curField = 0: curCh = (curCh + 1) Mod nch
    If curField < 0 Then curField = 5: curCh = (curCh + nch - 1) Mod nch
End Sub

' the selection, or the channel under the cursor (whole pattern) when there is none
Private Sub BlockRange(r0 As Long, r1 As Long, c0 As Long, c1 As Long)
    If selOn Then
        r0 = selR0: r1 = selR1: c0 = selC0: c1 = selC1
        Dim t As Long
        If r0 > r1 Then t = r0: r0 = r1: r1 = t
        If c0 > c1 Then t = c0: c0 = c1: c1 = t
    Else
        r0 = 0: r1 = ROWS - 1: c0 = curCh: c1 = curCh
    End If
End Sub

Private Sub PatternKey(ByVal k As Integer, ByVal shift As Boolean, ByVal ctrl As Boolean, _
                       ByVal alt As Boolean, ByVal amiga As Boolean)
    Dim r0 As Long, r1 As Long, c0 As Long, c1 As Long, n As Long, off As Long, h As Long
    If amiga Then
        Select Case k
            Case vbKeyC
                BlockRange r0, r1, c0, c1
                EdCopy curPat, r0, r1, c0, c1
                Say "copied " & (r1 - r0 + 1) & " rows x " & (c1 - c0 + 1) & " channels"
            Case vbKeyX
                BlockRange r0, r1, c0, c1
                EdCut curPat, r0, r1, c0, c1
                RefreshRows curPat, r0, r1
                Say "cut"
            Case vbKeyV, vbKeyB
                If clipRows = 0 Then Say "the clipboard is empty": Exit Sub
                EdPaste curPat, curRow, curCh, k = vbKeyB
                RefreshRows curPat, curRow, curRow + clipRows - 1
                If k = vbKeyB Then Say "mix-pasted" Else Say "pasted"
            Case vbKeyA
                selOn = True: selR0 = 0: selR1 = ROWS - 1
                If shift Then selC0 = 0: selC1 = nch - 1 Else selC0 = curCh: selC1 = curCh
                Say "selected"
            Case vbKeyT
                BlockRange r0, r1, c0, c1
                If shift Then n = -1 Else n = 1
                If alt Then n = n * 12
                h = EdTranspose(curPat, r0, r1, c0, c1, n)
                RefreshRows curPat, r0, r1
                If h > 0 Then Say "transposed, " & h & " notes at the edge" Else Say "transposed " & n
            Case vbKeyI
                BlockRange r0, r1, c0, c1
                EdInterpolate curPat, r0, r1, c0, c1
                RefreshRows curPat, r0, r1
                Say "interpolated"
            Case vbKeyD                     ' duplicate this position's pattern into a new one after it
                n = FreePattern()
                EdCopyPattern curPat, n
                EdInsertOrder curPos + 1, n
                GoPosition curPos + 1
                AfterBigChange
                Say "pattern " & n & " is a copy, at position " & curPos
            Case vbKeyP                     ' a new empty pattern after this position
                n = FreePattern()
                EdInsertOrder curPos + 1, n
                GoPosition curPos + 1
                AfterBigChange
                Say "new pattern " & n & " at position " & curPos
            Case vbKeyDelete                ' clear the whole pattern
                EdClearPattern curPat
                AfterBigChange
                Say "pattern " & curPat & " cleared"
            Case vbKeyK
                BlockRange r0, r1, c0, c1
                EdSwapSample curPat, r0, r1, c0, c1, 0, curSmp
                RefreshRows curPat, r0, r1
                Say "notes set to sample " & Hex2(curSmp)
        End Select
        Exit Sub
    End If
    If ctrl Then
        Select Case k
            Case vbKeyLeft: GoPosition curPos - 1
            Case vbKeyRight: GoPosition curPos + 1
            Case vbKeyUp: SetOrderPattern curPat + 1
            Case vbKeyDown: SetOrderPattern curPat - 1
            Case vbKey1 To vbKey8
                n = k - vbKey1
                If n < nch Then
                    If shift Then SoloChannel n Else ToggleMute n
                End If
        End Select
        Exit Sub
    End If
    Select Case k
        Case vbKeyUp: If alt Then MoveRow -16, False Else MoveRow -1, shift
            Exit Sub
        Case vbKeyDown: If alt Then MoveRow 16, False Else MoveRow 1, shift
            Exit Sub
        Case 256 + &H48: MoveRow -16, False: Exit Sub                     ' PageUp
        Case 256 + &H49: MoveRow 16, False: Exit Sub                      ' PageDown
        Case 256 + &H70: curRow = 0: selOn = False: Exit Sub              ' Home
        Case 256 + &H71: curRow = ROWS - 1: selOn = False: Exit Sub       ' End
        Case vbKeyLeft: MoveField -1, shift: Exit Sub
        Case vbKeyRight: MoveField 1, shift: Exit Sub
        Case vbKeyTab
            selOn = False
            If shift Then curCh = (curCh + nch - 1) Mod nch Else curCh = (curCh + 1) Mod nch
            curField = 0
            Exit Sub
        Case vbKeySpace
            editOn = Not editOn
            If editOn Then Say "edit mode: notes go into the pattern" Else Say "jam mode: notes only play"
            Exit Sub
        Case 256 + &H5E: SelectSample curSmp + 1: Exit Sub               ' keypad +
        Case 256 + &H4A: SelectSample curSmp - 1: Exit Sub               ' keypad -
        Case 256 + &H5D                                                   ' keypad *: edit step
            editStep = (editStep + 1) Mod 9
            Say "edit step " & editStep
            Exit Sub
    End Select
    If Not editOn Then
        ' jam: play the note, leave the pattern alone; Return plays the row and steps down
        If k = vbKeyReturn Then
            JamRow curPat, curRow
            MoveRow 1, False
            Exit Sub
        End If
        If curField = 0 Then
            off = PianoOffset(k)
            If off >= 0 Then
                n = octave * 12 + 1 + off
                If n <= 48 Then JamNote curCh, n, curSmp
            End If
        End If
        Exit Sub
    End If
    Select Case k
        Case vbKeyDelete
            If shift Then
                UndoCells "clear", curPat, curRow, curRow, curCh, curCh
                EdClearCell curPat, curRow, curCh
                MirrorCell CellIdx(curPat, curRow, curCh)
            Else
                EdClear curPat, curRow, curCh, curField
            End If
            RefreshRows curPat, curRow, curRow
            MoveRow editStep, False
            Exit Sub
        Case vbKeyBack
            If curRow > 0 Then
                If shift Then EdDeleteRow curPat, curRow - 1, -1 Else EdDeleteRow curPat, curRow - 1, curCh
                RefreshRows curPat, curRow - 1, ROWS - 1
                curRow = curRow - 1
            End If
            Exit Sub
        Case vbKeyReturn
            If shift Then EdInsertRow curPat, curRow, -1 Else EdInsertRow curPat, curRow, curCh
            RefreshRows curPat, curRow, ROWS - 1
            Exit Sub
    End Select
    If curField = 0 Then
        off = PianoOffset(k)
        If off >= 0 Then
            n = octave * 12 + 1 + off
            If n > 48 Then Say "above B-3, ProTracker's top note": Exit Sub
            EdNote curPat, curRow, curCh, n, curSmp
            JamNote curCh, n, curSmp
            RefreshRows curPat, curRow, curRow
            MoveRow editStep, False
        ElseIf k = vbKey1 Or k = 256 + &H0 Then
            ' 1 (left of the piano) or ` : clear the note
            EdClear curPat, curRow, curCh, 0
            RefreshRows curPat, curRow, curRow
            MoveRow editStep, False
        End If
    Else
        h = HexKey(k)
        If h >= 0 Then
            EdDigit curPat, curRow, curCh, curField, h
            RefreshRows curPat, curRow, curRow
            ' type a whole number left to right, then go down a step
            Select Case curField
                Case 1, 3, 4: curField = curField + 1
                Case 2: curField = 1: MoveRow editStep, False
                Case 5: curField = 3: MoveRow editStep, False
            End Select
        End If
    End If
End Sub

Public Sub GoPosition(ByVal p As Long)
    If p < 0 Then p = 0
    If p > songLen - 1 Then p = songLen - 1
    curPos = p
    curPat = orders(p)
    sideDirty = True
    If playing And followOn Then SeekSong curPos
End Sub

' change the pattern played at the current position
Private Sub SetOrderPattern(ByVal p As Long)
    If p < 0 Or p > MAXPAT - 1 Then Exit Sub
    EdSetOrder curPos, p
    curPat = p
    sideDirty = True
    Say "position " & curPos & " plays pattern " & p
End Sub

Public Sub ToggleMute(ByVal c As Long)
    SetMute c, Not ChanMuted(c)
    If ChanMuted(c) Then Say "channel " & (c + 1) & " muted" Else Say "channel " & (c + 1) & " on"
End Sub

Public Sub SoloChannel(ByVal c As Long)
    Dim i As Long, alone As Boolean
    alone = Not ChanMuted(c)
    For i = 0 To nch - 1
        If i <> c And Not ChanMuted(i) Then alone = False
    Next i
    For i = 0 To nch - 1
        If alone Then SetMute i, False Else SetMute i, i <> c
    Next i
    If alone Then Say "all channels on" Else Say "channel " & (c + 1) & " solo"
End Sub

' ---------------------------------------------------------------- sample view keys

Private Sub SampleKey(ByVal k As Integer, ByVal shift As Boolean, ByVal ctrl As Boolean, _
                      ByVal alt As Boolean, ByVal amiga As Boolean)
    Dim d As Long, off As Long, n As Long, s As Long
    s = curSmp
    Select Case k
        Case vbKeyUp: If smpField > 0 Then smpField = smpField - 1
            Exit Sub
        Case vbKeyDown: If smpField < 4 Then smpField = smpField + 1
            Exit Sub
        Case vbKeyLeft, vbKeyRight
            If k = vbKeyLeft Then d = -1 Else d = 1
            If alt Then ScrollZoom d: Exit Sub
            If shift Then d = d * 16
            Select Case smpField
                Case 1: EdSampleParams s, smpVol(s) + d, smpFine(s), smpLoopS(s), smpLoopL(s)
                Case 2: EdSampleParams s, smpVol(s), (FineSigned(s) + d + 16) And 15, smpLoopS(s), smpLoopL(s)
                    If FineSigned(s) = -8 And d > 0 Then EdSampleParams s, smpVol(s), 0, smpLoopS(s), smpLoopL(s)
                Case 3: EdSampleParams s, smpVol(s), smpFine(s), smpLoopS(s) + d * 2 * 16, smpLoopL(s)
                Case 4
                    If smpLoopL(s) <= 2 And d > 0 Then
                        EdSampleParams s, smpVol(s), smpFine(s), smpLoopS(s), smpLen(s) - smpLoopS(s)
                    Else
                        EdSampleParams s, smpVol(s), smpFine(s), smpLoopS(s), smpLoopL(s) + d * 2 * 16
                    End If
            End Select
            sideDirty = True
            Exit Sub
        Case vbKeyReturn: If smpField = 0 Then reqAction = "samplename"
            Exit Sub
        Case vbKeyL: reqAction = "loadsample": Exit Sub
        Case vbKeyW: reqAction = "savesample": Exit Sub
        Case 256 + &H5E, 256 + &HC: ZoomIn: Exit Sub          ' + =
        Case 256 + &H4A, 256 + &HB: ZoomOut: Exit Sub         ' - -
        Case vbKeyDelete
            If smpLen(s) > 0 Then EdClearSample s: sideDirty = True: Say "sample cleared"
            Exit Sub
        Case vbKeyR
            If SmpReverse(s) Then Say "reversed"
            Exit Sub
        Case vbKeyN
            If SmpNormalise(s) Then Say "normalised"
            Exit Sub
        Case vbKeyX
            If SmpCropToLoop(s) Then Say "cut to the loop" Else Say "no loop to cut to"
            Exit Sub
    End Select
    ' piano keys play the sample
    off = PianoOffset(k)
    If off >= 0 Then
        n = octave * 12 + 1 + off
        If n <= 48 Then JamNote curCh, n, s
    End If
End Sub

Private Sub ZoomIn()
    If smpLen(curSmp) = 0 Then Exit Sub
    If smpZoomL = 0 Then smpZoomS = 0: smpZoomL = smpLen(curSmp)
    If smpZoomL >= 64 Then
        smpZoomS = smpZoomS + smpZoomL \ 4
        smpZoomL = smpZoomL \ 2
    End If
End Sub

Private Sub ZoomOut()
    If smpZoomL = 0 Then Exit Sub
    smpZoomS = smpZoomS - smpZoomL \ 2
    smpZoomL = smpZoomL * 2
    If smpZoomS < 0 Then smpZoomS = 0
    If smpZoomS + smpZoomL > smpLen(curSmp) Then smpZoomS = 0: smpZoomL = 0
End Sub

Private Sub ScrollZoom(ByVal d As Long)
    If smpZoomL = 0 Then Exit Sub
    smpZoomS = smpZoomS + d * (smpZoomL \ 4)
    If smpZoomS < 0 Then smpZoomS = 0
    If smpZoomS + smpZoomL > smpLen(curSmp) Then smpZoomS = smpLen(curSmp) - smpZoomL
End Sub

' ---------------------------------------------------------------- song view keys

Private Sub SongKey(ByVal k As Integer, ByVal shift As Boolean, ByVal ctrl As Boolean, _
                    ByVal alt As Boolean, ByVal amiga As Boolean)
    Dim d As Long, h As Long, ok As Boolean
    If songField = 5 Then
        Select Case k
            Case vbKeyLeft: GoPosition curPos - 1: typedCount = 0
            Case vbKeyRight: GoPosition curPos + 1: typedCount = 0
            Case vbKeyUp
                If curPos >= 16 Then GoPosition curPos - 16 Else songField = 4
                typedCount = 0
            Case vbKeyDown: GoPosition curPos + 16: typedCount = 0
            Case 256 + &H47, vbKeyReturn                          ' Ins / Return: insert a position
                EdInsertOrder curPos, curPat
                Say "position inserted"
            Case vbKeyDelete
                EdDeleteOrder curPos
                GoPosition curPos
                Say "position deleted"
            Case vbKeyAdd, 256 + &H5E: SetOrderPattern curPat + 1
            Case vbKeySubtract, 256 + &H4A: SetOrderPattern curPat - 1
            Case Else
                h = HexKey(k)
                If h >= 0 And h <= 9 Then
                    If typedCount = 0 Then typedOrder = h Else typedOrder = (typedOrder * 10 + h) Mod 100
                    typedCount = typedCount + 1
                    SetOrderPattern typedOrder
                    If typedCount >= 2 Then typedCount = 0: GoPosition curPos + 1
                End If
        End Select
        Exit Sub
    End If
    Select Case k
        Case vbKeyUp: If songField > 0 Then songField = songField - 1
        Case vbKeyDown: songField = songField + 1
        Case vbKeyReturn: If songField = 0 Then reqAction = "title"
        Case vbKeyLeft, vbKeyRight
            If k = vbKeyLeft Then d = -1 Else d = 1
            If shift Then d = d * 10
            Select Case songField
                Case 1, 2
                    If songField = 1 Then ok = EdSpeedTempo(initSpeed + d, initTempo) Else ok = EdSpeedTempo(initSpeed, initTempo + d)
                    If ok Then
                        SetPlayerSpeed
                        InvalidatePattern
                        Say "speed " & initSpeed & ", tempo " & initTempo & " (Fxx in row 0 of pattern " & orders(0) & ")"
                    Else
                        Say "row 0 of pattern " & orders(0) & " has no free effect column for it"
                    End If
                Case 3: EdSongLength songLen + d
                Case 4
                    UndoSong "restart"
                    songRestart = songRestart + d
                    If songRestart < 0 Then songRestart = 0
                    If songRestart > 127 Then songRestart = 127
                    MirrorSong
            End Select
            sideDirty = True
    End Select
End Sub

' ---------------------------------------------------------------- playback

Public Sub StartSong(ByVal pos As Long, ByVal row As Long)
    PlaySongAt pos, row
    Say "playing the song from position " & pos
End Sub

Public Sub StartPattern(ByVal pat As Long, ByVal row As Long)
    PlayPatternAt pat, row
    Say "playing pattern " & pat
End Sub

Public Sub StopSong()
    StopPlayer
    Say "stopped"
End Sub

' ---------------------------------------------------------------- a frame

' follow the player, then draw. Call every timer tick; returns True when something was drawn.
Private sigHeader As String, sigInfo As String, sigHeads As String, sigStatus As String
Private lastView As Long, lastSidePP As Long, scopesLive As Boolean, lastSmpPos As Long

Public Function Frame(ByVal force As Boolean) As Boolean
    Dim pr As Long, pp As Long
    pr = -1: pp = -1
    ' the player's state for this frame: one call (two with the scopes)
    PlayerRead playing And Not scopesOff, SCN
    inFrame = True
    Frame = FrameDraw(force, pr, pp)
    inFrame = False
End Function

Private Function FrameDraw(ByVal force As Boolean, pr As Long, pp As Long) As Boolean
    Dim viewY As Long, ppat As Long, frac As Long, mode As Long
    Dim hint As String, msg As String, sig As String, c As Long, sp As Long
    If playing Then
        PlayerPoll pp, ppat, pr, frac
        If followOn Then
            If playMode = 1 And pp <> curPos Then curPos = pp: sideDirty = True
            curPat = ppat
            curRow = pr
        End If
        frameDirty = True
        ' draw the pattern that comes next while this one plays
        If playMode = 1 Then
            If pp + 1 < songLen Then PrefetchPattern orders(pp + 1), 8 Else PrefetchPattern orders(0), 8
        End If
    End If
    If message <> "" And Timer - msgTime > 4 Then message = "": frameDirty = True
    If curView = V_SAMPLES Then
        ' the play cursor in the waveform while the sample sounds (and one frame after)
        sp = PlayerSamplePos(curSmp)
        If sp >= 0 Or lastSmpPos >= 0 Then frameDirty = True
        lastSmpPos = sp
    End If
    If Not (frameDirty Or force) Then Exit Function
    frameDirty = False
    If playing And followOn Then viewY = curRow * RH + (frac * RH) \ 256 Else viewY = curRow * RH
    If playing Then mode = playMode Else mode = 0
    ' Only the parts that changed are drawn again: the back buffer keeps the rest
    ' (Refresh always shows the whole picture).
    If curView <> lastView Then force = True: lastView = curView
    sig = songFileName() & "|" & TitleText() & "|" & songDirty
    If force Or sig <> sigHeader Then DrawHeader songFileName(): sigHeader = sig
    sig = curPos & "|" & curPat & "|" & curRow & "|" & CurSpeed() & "|" & CurTempo() & "|" & octave & "|" & _
          curSmp & "|" & editOn & "|" & followOn & "|" & mode & "|" & smpName(curSmp)
    If force Or sig <> sigInfo Then
        DrawInfo curPos, curPat, curRow, CurSpeed(), CurTempo(), octave, curSmp, editOn, followOn, mode
        sigInfo = sig
    End If
    If force Or playing Or scopesLive Then DrawScopes: scopesLive = playing
    Select Case curView
        Case V_PATTERN
            sig = curCh & "|" & nch
            For c = 0 To nch - 1: sig = sig & IIf(ChanMuted(c), "m", "-"): Next c
            If force Or sig <> sigHeads Then DrawChannelHeads curCh: sigHeads = sig
            If ppat = curPat Then pr = pr Else pr = -1
            If followOn Then pr = -1
            DrawPattern curPat, viewY, curRow, curCh, curField, pr, editOn, selOn, selR0, selR1, selC0, selC1
            If force Or sideDirty Or pp <> lastSidePP Then
                cv.Box PatWidth(), PY0 - 12, scrW - PatWidth(), PH + 12, cBg
                If pp <> lastSidePP Then sideDirty = True
                If SideVisible() Then DrawSide curPos, pp, curSmp, 0
                lastSidePP = pp
            End If
            hint = "F1/F2 octave  F3/F4 sample  F5 play  F8 stop  Space edit  F10 view  Help"
        Case V_SAMPLES
            DrawSampleView curSmp, smpField, smpZoomS, smpZoomL, PlayerSamplePos(curSmp)
            hint = "Amiga+1/2/3 pattern/samples/song  F10 next view"
        Case V_SONG
            DrawSongView songField, curPos, pp
            hint = "Amiga+1/2/3 pattern/samples/song  F10 next view"
    End Select
    msg = message
    If msg = "" Then msg = "Riffwright"
    sig = msg & "|" & hint
    If force Or sig <> sigStatus Then DrawStatus msg, hint: sigStatus = sig
    FrameDraw = True
End Function

Public Function songFileName() As String
    Dim p As String, k As Long
    p = songPath
    k = InStrRev(p, "/"): If InStrRev(p, ":") > k Then k = InStrRev(p, ":")
    If k > 0 Then p = Mid$(p, k + 1)
    If p = "" Then p = "new song"
    songFileName = p
End Function

' after a load or new song
Public Sub SongChanged()
    DeriveSpeedTempo
    ClearUndo
    MirrorAll
    ResetCursor
    If curSmp < 1 Then curSmp = 1
End Sub

' ---------------------------------------------------------------- ARexx
' A command for the RIFFWRIGHT port: returns the result string; rc gets 0, 5 (warning) or
' 10 (error). LOAD and SAVE are done here (no requester); the form only passes them on.
Public Function RexxCommand(ByVal cmd As String, ByVal args As String, rc As Long) As String
    Dim n As Long
    rc = 0
    args = Trim$(args)
    If Left$(args, 1) = """" And Right$(args, 1) = """" And Len(args) >= 2 Then args = Mid$(args, 2, Len(args) - 2)
    Select Case UCase$(cmd)
        Case "PLAY"
            If args <> "" Then n = CLng(Val(args)) Else n = curPos
            If n < 0 Or n >= songLen Then rc = 5: RexxCommand = "bad position": Exit Function
            curPos = n: curPat = orders(n)
            StartSong n, 0
            RexxCommand = "playing"
        Case "STOP"
            StopSong
            RexxCommand = "stopped"
        Case "LOAD"
            If args = "" Then rc = 10: RexxCommand = "LOAD needs a file": Exit Function
            StopPlayer
            If LoadMod(args) Then
                SongChanged
                Say "loaded " & songFileName() & " (ARexx)"
                RexxCommand = TitleText()
            Else
                rc = 10: RexxCommand = lastError
                NewSong 4
                SongChanged
            End If
        Case "SAVE"
            If args = "" Then args = songPath
            If args = "" Then rc = 10: RexxCommand = "SAVE needs a file": Exit Function
            If SaveMod(args) Then RexxCommand = args Else rc = 10: RexxCommand = lastError
        Case "POSITION"
            If args <> "" Then
                n = CLng(Val(args))
                If n < 0 Or n >= songLen Then rc = 5: RexxCommand = "bad position": Exit Function
                GoPosition n
                If playing Then SeekSong n
            End If
            If playing Then
                Dim pp As Long, ppat As Long, pr As Long, fr As Long
                PlayerPoll pp, ppat, pr, fr
                RexxCommand = CStr(pp)
            Else
                RexxCommand = CStr(curPos)
            End If
        Case "TITLE"
            RexxCommand = TitleText()
        Case "VERSION"
            RexxCommand = "Riffwright 1.0"
        Case Else
            rc = 10
            RexxCommand = "unknown command " & cmd
    End Select
    frameDirty = True
End Function

' ---------------------------------------------------------------- mouse
' (canvas pixels; button 1 left, 2 right)
Private dragKind As Long          ' 0 none, 1 pattern selection, 2 loop start, 3 loop end
Private dragR0 As Long, dragC0 As Long, dragF0 As Long

' the pattern cell under (x, y) in the pattern view: False outside
Public Function CellAt(ByVal x As Long, ByVal y As Long, row As Long, ch As Long, field As Long) As Boolean
    Dim ox As Long
    If y < PY0 Or y >= PY0 + PH Or x < PX0 Or x >= PatWidth() Then Exit Function
    row = curRow + (y - (PY0 + CENTER * RH)) \ RH
    If y < PY0 + CENTER * RH Then row = curRow - ((PY0 + CENTER * RH - y + RH - 1) \ RH)
    If row < 0 Or row > ROWS - 1 Then Exit Function
    ch = (x - PX0) \ CW
    ox = (x - PX0) Mod CW
    Select Case ox
        Case Is < 24: field = 0
        Case Is < 30: field = 1
        Case Is < 42: field = 2
        Case Is < 48: field = 3
        Case Is < 54: field = 4
        Case Else: field = 5
    End Select
    CellAt = True
End Function

' x of a sample offset in the sample view's waveform, and back
Private Function WaveX(ByVal ofs As Long) As Long
    Dim zs As Long, zl As Long
    zs = smpZoomS: zl = smpZoomL
    If zl <= 0 Then zs = 0: zl = smpLen(curSmp)
    If zl <= 0 Then zl = 1
    WaveX = 6 + ((ofs - zs) * (scrW - 12)) \ zl
End Function

Private Function WaveOfs(ByVal x As Long) As Long
    Dim zs As Long, zl As Long
    zs = smpZoomS: zl = smpZoomL
    If zl <= 0 Then zs = 0: zl = smpLen(curSmp)
    WaveOfs = zs + ((x - 6) * zl) \ (scrW - 12)
    If WaveOfs < 0 Then WaveOfs = 0
    If WaveOfs > smpLen(curSmp) Then WaveOfs = smpLen(curSmp)
End Function

Public Sub MouseDown(ByVal btn As Long, ByVal sh As Long, ByVal x As Long, ByVal y As Long)
    Dim r As Long, c As Long, f As Long, i As Long, sx As Long
    frameDirty = True
    dragKind = 0
    ' the lights in the info panel
    If y >= SY0 + 36 And y < SY0 + 49 Then
        If x >= 6 And x < 44 Then
            editOn = Not editOn
            If editOn Then Say "edit mode" Else Say "jam mode"
            Exit Sub
        End If
        If x >= 48 And x < 96 Then HandleKey vbKeyF9, 0: Exit Sub
    End If
    Select Case curView
        Case V_PATTERN
            If CellAt(x, y, r, c, f) Then
                If c < nch Then
                    ' the cursor moves on the button's release, so the view keeps still while dragging
                    selOn = False
                    dragKind = 1: dragR0 = r: dragC0 = c: dragF0 = f
                End If
                Exit Sub
            End If
            If y >= PY0 - 12 And y < PY0 And x >= PX0 Then
                c = (x - PX0) \ CW
                If c < nch Then
                    If btn = 2 Then SoloChannel c Else ToggleMute c
                End If
                Exit Sub
            End If
            If SideVisible() And y >= PY0 + 14 And y < PY0 + PH And x >= SideX() Then
                sx = x - SideX()
                If sx < 64 Then
                    i = curPos - 17: If i < 0 Then i = 0
                    i = i + (y - PY0 - 13) \ RH
                    If i < songLen Then GoPosition i
                Else
                    i = 1 + (y - PY0 - 13) \ 11
                    If i >= 1 And i <= NSMP Then SelectSample i
                End If
            End If
        Case V_SAMPLES
            If y >= PY0 + 4 And y < PY0 + 224 And smpLen(curSmp) > 0 Then
                ' drag the nearer loop marker; a click without a loop makes one from here to the end
                If smpLoopL(curSmp) <= 2 Then
                    i = (WaveOfs(x) \ 2) * 2
                    If smpLen(curSmp) - i < 4 Then Exit Sub
                    EdSampleParams curSmp, smpVol(curSmp), smpFine(curSmp), i, smpLen(curSmp) - i
                    dragKind = 2
                ElseIf Abs(x - WaveX(smpLoopS(curSmp))) <= Abs(x - WaveX(smpLoopS(curSmp) + smpLoopL(curSmp))) Then
                    dragKind = 2
                Else
                    dragKind = 3
                End If
                MouseMove btn, sh, x, y
            ElseIf y >= PY0 + 234 And y < PY0 + 312 And x < 264 Then
                smpField = (y - PY0 - 234) \ 13
                If smpField > 4 Then smpField = 4
                If smpField = 0 And btn = 1 Then reqAction = "samplename"
            End If
        Case V_SONG
            If y >= PY0 + 10 And y < PY0 + 80 Then
                songField = (y - PY0 - 10) \ 14
                If songField = 0 Then reqAction = "title"
            ElseIf y >= PY0 + 125 And y < PY0 + 253 Then
                i = ((y - PY0 - 125) \ 16) * 16 + (x - 6) \ 38
                If i >= 0 And i < 128 And (x - 6) \ 38 < 16 Then
                    songField = 5
                    If i < songLen Then GoPosition i Else curPos = i: curPat = orders(i)
                End If
            End If
    End Select
End Sub

Public Sub MouseMove(ByVal btn As Long, ByVal sh As Long, ByVal x As Long, ByVal y As Long)
    Dim r As Long, c As Long, f As Long, o As Long, e As Long
    Select Case dragKind
        Case 1
            If y < PY0 Then y = PY0
            If y >= PY0 + PH Then y = PY0 + PH - 1
            If x < PX0 Then x = PX0
            If x >= PatWidth() Then x = PatWidth() - 1
            If CellAt(x, y, r, c, f) Then
                If c > nch - 1 Then c = nch - 1
                If r <> dragR0 Or c <> dragC0 Then
                    selOn = True
                    selR0 = dragR0: selC0 = dragC0: selR1 = r: selC1 = c
                End If
            End If
            frameDirty = True
        Case 2, 3
            o = (WaveOfs(x) \ 2) * 2
            e = smpLoopS(curSmp) + smpLoopL(curSmp)
            If dragKind = 2 Then
                If o > e - 2 Then o = e - 2
                EdSampleParamsQuiet curSmp, o, e - o
            Else
                If o < smpLoopS(curSmp) + 2 Then o = smpLoopS(curSmp) + 2
                EdSampleParamsQuiet curSmp, smpLoopS(curSmp), o - smpLoopS(curSmp)
            End If
            frameDirty = True
    End Select
End Sub

Public Sub MouseUp(ByVal btn As Long, ByVal sh As Long, ByVal x As Long, ByVal y As Long)
    If dragKind <> 0 Then MouseMove btn, sh, x, y
    If dragKind = 1 Then
        If selOn Then
            curCh = selC1
        Else
            curRow = dragR0: curCh = dragC0: curField = dragF0
        End If
    End If
    dragKind = 0
End Sub

Public Sub MouseWheel(ByVal delta As Long)
    frameDirty = True
    Select Case curView
        Case V_PATTERN
            If delta > 0 Then MoveRow -2, False Else MoveRow 2, False
        Case V_SAMPLES
            If delta > 0 Then ZoomIn Else ZoomOut
    End Select
End Sub
