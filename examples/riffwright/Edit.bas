' Riffwright - editing operations and undo/redo
'
' Every change to the song goes through here: it records an undo step, changes the model
' (Song.bas), marks the song dirty and tells the player (Player.bas) about the cells it changed,
' so an edit is heard at once while the song plays.
'
' Undo works by swapping: a step holds the state from before the change; Undo swaps it with
' the song's current state (so the step now holds the "after" state) and moves it to the redo
' list. Redo swaps it back.
Option Explicit

Public Const UK_CELLS As Long = 1
Public Const UK_SAMPLE As Long = 2
Public Const UK_SONG As Long = 3

Private Const UMAX As Long = 200

Private Type UndoStep
    kind As Long
    what As String
    pat As Long
    r0 As Long
    r1 As Long
    c0 As Long
    c1 As Long
    cells As Variant          ' Long array, 4 values per cell (UK_CELLS)
    smp As Long               ' UK_SAMPLE
    sName As String
    sLen As Long
    sFine As Long
    sHi As Long
    sVol As Long
    sLs As Long
    sLl As Long
    sData As Variant
    title As String           ' UK_SONG
    sngLen As Long
    restart As Long
    ords As Variant
    speed As Long
    tempo As Long
    npat As Long
End Type

Private undoS(1 To 200) As UndoStep
Private nUndo As Long
Private redoS(1 To 200) As UndoStep
Private nRedo As Long

' the clipboard (block copy/paste): rows x channels x 4 values
Public clipRows As Long
Public clipChans As Long
Private clip() As Long

Public editStep As Long         ' rows the cursor moves after a note (1)
Public lastChanged As String    ' for the status line

' ---------------------------------------------------------------- undo

Private Sub PushStep(st As UndoStep)
    Dim i As Long
    If nUndo = UMAX Then
        For i = 1 To UMAX - 1: undoS(i) = undoS(i + 1): Next i
        nUndo = UMAX - 1
    End If
    nUndo = nUndo + 1
    undoS(nUndo) = st
    nRedo = 0
    songDirty = True
End Sub

Public Sub ClearUndo()
    nUndo = 0
    nRedo = 0
End Sub

Public Function UndoCount() As Long
    UndoCount = nUndo
End Function

Public Function RedoCount() As Long
    RedoCount = nRedo
End Function

Public Function UndoName() As String
    If nUndo > 0 Then UndoName = undoS(nUndo).what
End Function

Public Function RedoName() As String
    If nRedo > 0 Then RedoName = redoS(nRedo).what
End Function

Private Sub SaveCells(st As UndoStep, ByVal what As String, ByVal pat As Long, ByVal r0 As Long, _
                      ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    Dim a() As Long, r As Long, c As Long, k As Long, j As Long
    st.kind = UK_CELLS
    st.what = what
    st.pat = pat: st.r0 = r0: st.r1 = r1: st.c0 = c0: st.c1 = c1
    ReDim a(0 To (r1 - r0 + 1) * (c1 - c0 + 1) * 4 - 1)
    j = 0
    For r = r0 To r1
        For c = c0 To c1
            k = CellIdx(pat, r, c)
            a(j) = cPer(k): a(j + 1) = cSmp(k): a(j + 2) = cFx(k): a(j + 3) = cPrm(k)
            j = j + 4
        Next c
    Next r
    st.cells = a
End Sub

' start an undo step for a block of cells (call before changing them)
Public Sub UndoCells(ByVal what As String, ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, _
                     ByVal c0 As Long, ByVal c1 As Long)
    Dim st As UndoStep
    SaveCells st, what, pat, r0, r1, c0, c1
    PushStep st
    lastChanged = what
End Sub

Private Sub SaveSample(st As UndoStep, ByVal what As String, ByVal i As Long)
    st.kind = UK_SAMPLE
    st.what = what
    st.smp = i
    st.sName = smpName(i): st.sLen = smpLen(i): st.sFine = smpFine(i): st.sHi = smpRawHi(i)
    st.sVol = smpVol(i): st.sLs = smpLoopS(i): st.sLl = smpLoopL(i)
    st.sData = smpData(i)
End Sub

Public Sub UndoSample(ByVal what As String, ByVal i As Long)
    Dim st As UndoStep
    SaveSample st, what, i
    PushStep st
    lastChanged = what
End Sub

Private Sub SaveSong(st As UndoStep, ByVal what As String)
    Dim o() As Long, i As Long
    st.kind = UK_SONG
    st.what = what
    st.title = songTitle: st.sngLen = songLen: st.restart = songRestart
    ReDim o(0 To 127)
    For i = 0 To 127: o(i) = orders(i): Next i
    st.ords = o
    st.speed = initSpeed: st.tempo = initTempo: st.npat = nPat
End Sub

Public Sub UndoSong(ByVal what As String)
    Dim st As UndoStep
    SaveSong st, what
    PushStep st
    lastChanged = what
End Sub

' put a step's state into the song; st gets the state it replaced
Private Sub SwapIn(st As UndoStep)
    Dim cur As UndoStep, a() As Long, r As Long, c As Long, k As Long, j As Long, i As Long
    Select Case st.kind
        Case UK_CELLS
            SaveCells cur, st.what, st.pat, st.r0, st.r1, st.c0, st.c1
            a = st.cells
            j = 0
            For r = st.r0 To st.r1
                For c = st.c0 To st.c1
                    k = CellIdx(st.pat, r, c)
                    cPer(k) = a(j): cSmp(k) = a(j + 1): cFx(k) = a(j + 2): cPrm(k) = a(j + 3)
                    j = j + 4
                Next c
            Next r
            MirrorBlock st.pat, st.r0, st.r1, st.c0, st.c1
        Case UK_SAMPLE
            SaveSample cur, st.what, st.smp
            i = st.smp
            smpName(i) = st.sName: smpLen(i) = st.sLen: smpFine(i) = st.sFine: smpRawHi(i) = st.sHi
            smpVol(i) = st.sVol: smpLoopS(i) = st.sLs: smpLoopL(i) = st.sLl
            smpData(i) = st.sData
            MirrorSample i
        Case UK_SONG
            SaveSong cur, st.what
            songTitle = st.title: songLen = st.sngLen: songRestart = st.restart
            a = st.ords
            For i = 0 To 127: orders(i) = a(i): Next i
            initSpeed = st.speed: initTempo = st.tempo: nPat = st.npat
            MirrorSong
    End Select
    st = cur
End Sub

Public Function Undo() As Boolean
    If nUndo = 0 Then Exit Function
    lastChanged = "undo " & undoS(nUndo).what
    SwapIn undoS(nUndo)
    nRedo = nRedo + 1
    redoS(nRedo) = undoS(nUndo)
    nUndo = nUndo - 1
    songDirty = True
    Undo = True
End Function

Public Function Redo() As Boolean
    If nRedo = 0 Then Exit Function
    lastChanged = "redo " & redoS(nRedo).what
    SwapIn redoS(nRedo)
    nUndo = nUndo + 1
    undoS(nUndo) = redoS(nRedo)
    nRedo = nRedo - 1
    songDirty = True
    Redo = True
End Function

' the region the last undo/redo touched, for the editor to jump there (pattern, row, channel)
Public Function LastStepPattern(ByVal redoSide As Boolean) As Long
    LastStepPattern = -1
    If redoSide Then
        If nRedo > 0 Then
            If redoS(nRedo).kind = UK_CELLS Then LastStepPattern = redoS(nRedo).pat
        End If
    ElseIf nUndo > 0 Then
        If undoS(nUndo).kind = UK_CELLS Then LastStepPattern = undoS(nUndo).pat
    End If
End Function

' ---------------------------------------------------------------- cells

' note 1..60 (13..48 is ProTracker's C-1..B-3); note 0 clears the note and the sample
Public Sub EdNote(ByVal pat As Long, ByVal row As Long, ByVal ch As Long, ByVal note As Long, ByVal smp As Long)
    Dim k As Long
    k = CellIdx(pat, row, ch)
    UndoCells "note", pat, row, row, ch, ch
    If note <= 0 Then
        cPer(k) = 0: cSmp(k) = 0
    Else
        cPer(k) = perOfNote(note)
        cSmp(k) = smp
    End If
    MirrorCell k
End Sub

' field 1/2 = sample hi/lo digit, 3 = effect, 4/5 = parameter hi/lo digit
Public Sub EdDigit(ByVal pat As Long, ByVal row As Long, ByVal ch As Long, ByVal field As Long, ByVal v As Long)
    Dim k As Long
    k = CellIdx(pat, row, ch)
    UndoCells "edit", pat, row, row, ch, ch
    Select Case field
        Case 1: cSmp(k) = ((v And 1) * 16) Or (cSmp(k) And 15)        ' 0..1F
        Case 2: cSmp(k) = (cSmp(k) And &HF0) Or (v And 15)
        Case 3: cFx(k) = v And 15
        Case 4: cPrm(k) = ((v And 15) * 16) Or (cPrm(k) And 15)
        Case 5: cPrm(k) = (cPrm(k) And &HF0) Or (v And 15)
    End Select
    If cSmp(k) > 31 Then cSmp(k) = 31
    MirrorCell k
End Sub

' clear the field group under the cursor: 0 = note+sample, 1/2 = sample, 3..5 = effect
Public Sub EdClear(ByVal pat As Long, ByVal row As Long, ByVal ch As Long, ByVal field As Long)
    Dim k As Long
    k = CellIdx(pat, row, ch)
    UndoCells "clear", pat, row, row, ch, ch
    Select Case field
        Case 0: cPer(k) = 0: cSmp(k) = 0
        Case 1, 2: cSmp(k) = 0
        Case Else: cFx(k) = 0: cPrm(k) = 0
    End Select
    MirrorCell k
End Sub

Public Sub EdClearCell(ByVal pat As Long, ByVal row As Long, ByVal ch As Long)
    Dim k As Long
    k = CellIdx(pat, row, ch)
    cPer(k) = 0: cSmp(k) = 0: cFx(k) = 0: cPrm(k) = 0
End Sub

' insert an empty row at row (rows below move down, the last falls off); ch = -1 all channels
Public Sub EdInsertRow(ByVal pat As Long, ByVal row As Long, ByVal ch As Long)
    Dim c0 As Long, c1 As Long, r As Long, c As Long, k As Long, k2 As Long
    ChanRange ch, c0, c1
    UndoCells "insert row", pat, row, ROWS - 1, c0, c1
    For r = ROWS - 1 To row + 1 Step -1
        For c = c0 To c1
            k = CellIdx(pat, r, c): k2 = CellIdx(pat, r - 1, c)
            cPer(k) = cPer(k2): cSmp(k) = cSmp(k2): cFx(k) = cFx(k2): cPrm(k) = cPrm(k2)
        Next c
    Next r
    For c = c0 To c1: EdClearCell pat, row, c: Next c
    MirrorBlock pat, row, ROWS - 1, c0, c1
End Sub

Public Sub EdDeleteRow(ByVal pat As Long, ByVal row As Long, ByVal ch As Long)
    Dim c0 As Long, c1 As Long, r As Long, c As Long, k As Long, k2 As Long
    ChanRange ch, c0, c1
    UndoCells "delete row", pat, row, ROWS - 1, c0, c1
    For r = row To ROWS - 2
        For c = c0 To c1
            k = CellIdx(pat, r, c): k2 = CellIdx(pat, r + 1, c)
            cPer(k) = cPer(k2): cSmp(k) = cSmp(k2): cFx(k) = cFx(k2): cPrm(k) = cPrm(k2)
        Next c
    Next r
    For c = c0 To c1: EdClearCell pat, ROWS - 1, c: Next c
    MirrorBlock pat, row, ROWS - 1, c0, c1
End Sub

Private Sub ChanRange(ByVal ch As Long, c0 As Long, c1 As Long)
    If ch < 0 Then c0 = 0: c1 = nch - 1 Else c0 = ch: c1 = ch
End Sub

Private Sub Order2(a As Long, b As Long)
    Dim t As Long
    If a > b Then t = a: a = b: b = t
End Sub

' ---------------------------------------------------------------- blocks

Public Sub EdCopy(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    Dim r As Long, c As Long, k As Long, j As Long
    Order2 r0, r1: Order2 c0, c1
    clipRows = r1 - r0 + 1
    clipChans = c1 - c0 + 1
    ReDim clip(0 To clipRows * clipChans * 4 - 1)
    j = 0
    For r = r0 To r1
        For c = c0 To c1
            k = CellIdx(pat, r, c)
            clip(j) = cPer(k): clip(j + 1) = cSmp(k): clip(j + 2) = cFx(k): clip(j + 3) = cPrm(k)
            j = j + 4
        Next c
    Next r
End Sub

Public Sub EdCut(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    Dim r As Long, c As Long
    Order2 r0, r1: Order2 c0, c1
    EdCopy pat, r0, r1, c0, c1
    UndoCells "cut", pat, r0, r1, c0, c1
    For r = r0 To r1
        For c = c0 To c1: EdClearCell pat, r, c: Next c
    Next r
    MirrorBlock pat, r0, r1, c0, c1
End Sub

' paste the clipboard with its top left at (row, ch), clipped to the pattern;
' mix = True keeps the cells' existing fields where the clipboard's are empty
Public Sub EdPaste(ByVal pat As Long, ByVal row As Long, ByVal ch As Long, ByVal mix As Boolean)
    Dim r As Long, c As Long, k As Long, j As Long, r1 As Long, c1 As Long
    If clipRows = 0 Then Exit Sub
    r1 = row + clipRows - 1: If r1 > ROWS - 1 Then r1 = ROWS - 1
    c1 = ch + clipChans - 1: If c1 > nch - 1 Then c1 = nch - 1
    If mix Then UndoCells "mix paste", pat, row, r1, ch, c1 Else UndoCells "paste", pat, row, r1, ch, c1
    For r = row To r1
        For c = ch To c1
            k = CellIdx(pat, r, c)
            j = (((r - row) * clipChans) + (c - ch)) * 4
            If mix Then
                If clip(j) <> 0 Then cPer(k) = clip(j): cSmp(k) = clip(j + 1)
                If clip(j + 2) <> 0 Or clip(j + 3) <> 0 Then cFx(k) = clip(j + 2): cPrm(k) = clip(j + 3)
            Else
                cPer(k) = clip(j): cSmp(k) = clip(j + 1): cFx(k) = clip(j + 2): cPrm(k) = clip(j + 3)
            End If
        Next c
    Next r
    MirrorBlock pat, row, r1, ch, c1
End Sub

' transpose the notes of a block by semitones, kept inside ProTracker's C-1..B-3;
' smp > 0 only transposes notes of that sample. Returns how many notes hit the edge.
Public Function EdTranspose(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, _
                            ByVal c1 As Long, ByVal semis As Long, Optional ByVal smp As Long = 0) As Long
    Dim r As Long, c As Long, k As Long, n As Long, clipped As Long
    Order2 r0, r1: Order2 c0, c1
    UndoCells "transpose", pat, r0, r1, c0, c1
    For r = r0 To r1
        For c = c0 To c1
            k = CellIdx(pat, r, c)
            If cPer(k) <> 0 And (smp = 0 Or cSmp(k) = smp) Then
                n = noteOfPer(cPer(k) And 4095) + semis
                If n < 13 Then n = 13: clipped = clipped + 1
                If n > 48 Then n = 48: clipped = clipped + 1
                cPer(k) = perOfNote(n)
            End If
        Next c
    Next r
    MirrorBlock pat, r0, r1, c0, c1
    EdTranspose = clipped
End Function

' change the sample number of every note in a block (from = 0: all notes)
Public Sub EdSwapSample(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, _
                        ByVal c1 As Long, ByVal from As Long, ByVal toSmp As Long)
    Dim r As Long, c As Long, k As Long
    Order2 r0, r1: Order2 c0, c1
    UndoCells "set sample", pat, r0, r1, c0, c1
    For r = r0 To r1
        For c = c0 To c1
            k = CellIdx(pat, r, c)
            If cSmp(k) <> 0 And (from = 0 Or cSmp(k) = from) Then cSmp(k) = toSmp
        Next c
    Next r
    MirrorBlock pat, r0, r1, c0, c1
End Sub

' fill a block's effect parameters from the first to the last row's values (volume slides by hand)
Public Sub EdInterpolate(ByVal pat As Long, ByVal r0 As Long, ByVal r1 As Long, ByVal c0 As Long, ByVal c1 As Long)
    Dim r As Long, c As Long, ka As Long, kb As Long, k As Long, a As Long, b As Long
    Order2 r0, r1: Order2 c0, c1
    If r1 - r0 < 2 Then Exit Sub
    UndoCells "interpolate", pat, r0, r1, c0, c1
    For c = c0 To c1
        ka = CellIdx(pat, r0, c): kb = CellIdx(pat, r1, c)
        If cFx(ka) = cFx(kb) Then
            a = cPrm(ka): b = cPrm(kb)
            For r = r0 + 1 To r1 - 1
                k = CellIdx(pat, r, c)
                cFx(k) = cFx(ka)
                cPrm(k) = a + ((b - a) * (r - r0)) \ (r1 - r0)
            Next r
        End If
    Next c
    MirrorBlock pat, r0, r1, c0, c1
End Sub

Public Sub EdClearPattern(ByVal pat As Long)
    Dim r As Long, c As Long
    UndoCells "clear pattern", pat, 0, ROWS - 1, 0, nch - 1
    For r = 0 To ROWS - 1
        For c = 0 To nch - 1: EdClearCell pat, r, c: Next c
    Next r
    MirrorBlock pat, 0, ROWS - 1, 0, nch - 1
End Sub

' copy pattern a over pattern b
Public Sub EdCopyPattern(ByVal a As Long, ByVal b As Long)
    Dim r As Long, c As Long, k As Long, k2 As Long
    UndoCells "copy pattern", b, 0, ROWS - 1, 0, nch - 1
    For r = 0 To ROWS - 1
        For c = 0 To nch - 1
            k = CellIdx(b, r, c): k2 = CellIdx(a, r, c)
            cPer(k) = cPer(k2): cSmp(k) = cSmp(k2): cFx(k) = cFx(k2): cPrm(k) = cPrm(k2)
        Next c
    Next r
    If b + 1 > nPat Then nPat = b + 1
    MirrorBlock b, 0, ROWS - 1, 0, nch - 1
End Sub

' ---------------------------------------------------------------- song and order list

Public Sub EdSetOrder(ByVal pos As Long, ByVal pat As Long)
    If pat < 0 Then pat = 0
    If pat > MAXPAT - 1 Then pat = MAXPAT - 1
    UndoSong "order"
    orders(pos) = pat
    If pat + 1 > nPat Then nPat = pat + 1
    MirrorSong
End Sub

Public Sub EdInsertOrder(ByVal pos As Long, ByVal pat As Long)
    Dim i As Long
    If songLen >= 128 Then Exit Sub
    UndoSong "insert position"
    For i = 127 To pos + 1 Step -1: orders(i) = orders(i - 1): Next i
    orders(pos) = pat
    songLen = songLen + 1
    If pat + 1 > nPat Then nPat = pat + 1
    MirrorSong
End Sub

Public Sub EdDeleteOrder(ByVal pos As Long)
    Dim i As Long
    If songLen <= 1 Then Exit Sub
    UndoSong "delete position"
    For i = pos To 126: orders(i) = orders(i + 1): Next i
    orders(127) = 0
    songLen = songLen - 1
    MirrorSong
End Sub

Public Sub EdSongLength(ByVal n As Long)
    If n < 1 Then n = 1
    If n > 128 Then n = 128
    UndoSong "song length"
    songLen = n
    MirrorSong
End Sub

Public Sub EdTitle(ByVal t As String)
    UndoSong "title"
    songTitle = PadName(t, 20)
    MirrorSong
End Sub

Public Sub EdSpeedTempo(ByVal speed As Long, ByVal tempo As Long)
    If speed < 1 Then speed = 1
    If speed > 31 Then speed = 31
    If tempo < 32 Then tempo = 32
    If tempo > 255 Then tempo = 255
    UndoSong "speed/tempo"
    initSpeed = speed
    initTempo = tempo
    MirrorSong
End Sub

' the first pattern number with nothing in it and not in the order list
Public Function FreePattern() As Long
    Dim p As Long, i As Long, used As Boolean
    For p = 0 To MAXPAT - 1
        used = PatternUsed(p)
        If Not used Then
            For i = 0 To songLen - 1
                If orders(i) = p Then used = True: Exit For
            Next i
        End If
        If Not used Then FreePattern = p: Exit Function
    Next p
    FreePattern = MAXPAT - 1
End Function

' ---------------------------------------------------------------- samples

Public Sub EdSampleName(ByVal i As Long, ByVal s As String)
    UndoSample "sample name", i
    smpName(i) = PadName(s, 22)
    MirrorSample i
End Sub

Public Sub EdSampleParams(ByVal i As Long, ByVal vol As Long, ByVal fine As Long, ByVal ls As Long, ByVal ll As Long)
    If vol < 0 Then vol = 0
    If vol > 64 Then vol = 64
    fine = fine And 15
    ls = (ls \ 2) * 2: ll = (ll \ 2) * 2
    If ls < 0 Then ls = 0
    If ls > smpLen(i) Then ls = smpLen(i)
    If ll < 2 Then ll = 2
    If ls + ll > smpLen(i) And ll > 2 Then ll = smpLen(i) - ls
    If ll < 2 Then ll = 2
    UndoSample "sample settings", i
    smpVol(i) = vol: smpFine(i) = fine: smpLoopS(i) = ls: smpLoopL(i) = ll
    MirrorSample i
End Sub

' replace a sample's data (Byte array of signed 8-bit values); keeps the loop inside it
Public Sub EdSampleData(ByVal i As Long, ByVal what As String, d As Variant, ByVal n As Long)
    UndoSample what, i
    n = (n \ 2) * 2
    If n > 131070 Then n = 131070                 ' ProTracker's limit (64 K words)
    If n <= 0 Then
        smpData(i) = Empty: smpLen(i) = 0
    Else
        If UBound(d) + 1 > n Then
            Dim t() As Byte
            t = d
            ReDim Preserve t(0 To n - 1)
            smpData(i) = t
        Else
            smpData(i) = d
        End If
        smpLen(i) = n
    End If
    If smpLoopS(i) + smpLoopL(i) > smpLen(i) Then smpLoopS(i) = 0: smpLoopL(i) = 2
    If smpVol(i) = 0 And n > 0 Then smpVol(i) = 64
    MirrorSample i
End Sub

Public Sub EdClearSample(ByVal i As Long)
    UndoSample "clear sample", i
    ClearSample i
    MirrorSample i
End Sub
