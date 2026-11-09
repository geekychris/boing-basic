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
        ' jam: play the note, leave the pattern alone
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
    Dim d As Long, h As Long
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
                Case 1: EdSpeedTempo initSpeed + d, initTempo: SetPlayerSpeed
                Case 2: EdSpeedTempo initSpeed, initTempo + d: SetPlayerSpeed
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
Public Function Frame(ByVal force As Boolean) As Boolean
    Dim viewY As Long, pr As Long, pp As Long, ppat As Long, frac As Long, mode As Long
    Dim hint As String, msg As String
    pr = -1: pp = -1
    If playing Then
        PlayerPoll pp, ppat, pr, frac
        If followOn Then
            If playMode = 1 And pp <> curPos Then curPos = pp: sideDirty = True
            curPat = ppat
            curRow = pr
        End If
        frameDirty = True
    End If
    If message <> "" And Timer - msgTime > 4 Then message = "": frameDirty = True
    If Not (frameDirty Or force) Then Exit Function
    frameDirty = False
    If playing And followOn Then viewY = curRow * RH + (frac * RH) \ 256 Else viewY = curRow * RH
    If playing Then mode = playMode Else mode = 0
    DrawHeader songFileName()
    DrawInfo curPos, curPat, curRow, CurSpeed(), CurTempo(), octave, curSmp, editOn, followOn, mode
    DrawScopes
    Select Case curView
        Case V_PATTERN
            DrawChannelHeads curCh
            If ppat = curPat Then pr = pr Else pr = -1
            If followOn Then pr = -1
            DrawPattern curPat, viewY, curRow, curCh, curField, pr, editOn, selOn, selR0, selR1, selC0, selC1
            If SideVisible() Then
                cv.Box PatWidth(), PY0 - 12, scrW - PatWidth(), PH + 12, cBg
                DrawSide curPos, pp, curSmp, 0
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
    If msg = "" Then msg = "Riffwright - " & nch & " channel ProTracker editor"
    DrawStatus msg, hint
    Frame = True
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
    ClearUndo
    MirrorAll
    ResetCursor
    If curSmp < 1 Then curSmp = 1
End Sub
