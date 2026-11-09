' StCore - Stack Tower's rules, line for line from amiga_mcp's examples/stack_tower/st_core.c
' (itself the browser's stack-tower-core.js): falling pieces land on the outside of a round
' tower of 16 columns that wrap round, so moving a piece left or right turns the tower under
' it. A full ring clears.
'
' The same random generator (mulberry32), bag and rules, so a seed deals the same pieces as
' the C and the browser game; times are whole milliseconds. The state is module variables
' (st*), the board a Long array, bottom row first. tools/trace.sh and Trace.bbp check it
' against the C: the same state hash after the same games.
Option Explicit

Public Const ST_COLS As Long = 16
Public Const ST_ROWS As Long = 20
Public Const ST_HIDDEN As Long = 4
Public Const ST_TOTAL As Long = 24
Public Const ST_CELLS As Long = 384            ' ST_COLS * ST_TOTAL
Public Const ST_GARBAGE As Long = 9
Public Const ST_NPIECES As Long = 8
Public Const ST_LOCK_MS As Long = 500
Public Const ST_LOCK_RESETS As Long = 15
Public Const ST_DIG_ROWS As Long = 10
Public Const ST_QUEUE As Long = 24
Public Const ST_MAX_EVENTS As Long = 16

Public Const MODE_MARATHON As Long = 0
Public Const MODE_RISING As Long = 1
Public Const MODE_DIG As Long = 2
Public Const MODE_COUNT As Long = 3

' events, for sound and the log
Public Const STE_NONE As Long = 0
Public Const STE_MOVE As Long = 1
Public Const STE_ROTATE As Long = 2
Public Const STE_KICK As Long = 3
Public Const STE_DROP As Long = 4
Public Const STE_HOLD As Long = 5
Public Const STE_LOCK As Long = 6
Public Const STE_CLEAR As Long = 7
Public Const STE_LEVEL As Long = 8
Public Const STE_GARBAGE As Long = 9
Public Const STE_WIN As Long = 10
Public Const STE_OVER As Long = 11

' ---- the game ----
Public stMode As Long, stSeed As Long, stRng As Long
Public stBoard(0 To 383) As Long
Public stQueue(0 To 23) As Long, stNQueue As Long
Public stHold As Long                          ' -1: none
Public stCanHold As Long
Public pType As Long, pRot As Long, pCol As Long, pRow As Long   ' the falling piece
Public stLevel As Long, stStartLevel As Long, stLines As Long, stCombo As Long, stPieces As Long
Public stScore As Long, stTimeMs As Long
Public stFallMs As Long, stLockMs As Long, stResets As Long, stSoft As Long
Public stOver As Long, stWon As Long
Public stRiseMs As Long, stGarbageLeft As Long, stLastCol As Long
Public evType(0 To 15) As Long, evA(0 To 15) As Long, evB(0 To 15) As Long, stNEv As Long

' the pieces' cells after rot quarter turns clockwise, about the pivot, y up:
' (type * 4 + rot) * 5 + i
Public cellDx(0 To 159) As Long, cellDy(0 To 159) As Long
Public stNCells(0 To 7) As Long
Public stPieceName(0 To 7) As String
Public stModeName(0 To 2) As String
Public stEventName(0 To 11) As String

' the cells of the last StCellsOf call (columns wrapped)
Public cellC(0 To 4) As Long, cellR(0 To 4) As Long

Private kickX(0 To 9) As Long, kickY(0 To 9) As Long
Private lineScore(0 To 6) As Long
Private intervalTab(0 To 29) As Long
Private coreReady As Boolean

Public Sub StInit()
    Dim cx As Variant, cy As Variant, v As Variant, t As Long, r As Long, i As Long, x As Long, y As Long, k As Long, tmp As Long
    If coreReady Then Exit Sub
    A3FixInit
    ' two trominoes and six pentominoes, none of the classic four-square pieces
    cx = Array(-1, 0, 1, 0, 0, _
               0, 1, 0, 0, 0, _
               -1, -1, 0, 1, 1, _
               0, 0, 1, 0, 1, _
               0, -1, 0, 1, 0, _
               -1, 0, 1, 0, 0, _
               -1, -1, 0, 0, 1, _
               -1, 0, 0, 0, 1)
    cy = Array(0, 0, 0, 0, 0, _
               0, 0, 1, 0, 0, _
               1, 0, 0, 0, 1, _
               -1, 0, 0, 1, 1, _
               -1, 0, 0, 0, 1, _
               1, 1, 1, 0, -1, _
               1, 0, 0, -1, -1, _
               1, 1, 0, -1, -1)
    v = Array(3, 3, 5, 5, 5, 5, 5, 5)
    For t = 0 To 7
        stNCells(t) = v(t)
        For r = 0 To 3
            For i = 0 To 4
                x = cx(t * 5 + i): y = cy(t * 5 + i)
                For k = 1 To r                      ' (x, y) -> (y, -x)
                    tmp = x: x = y: y = -tmp
                Next k
                cellDx((t * 4 + r) * 5 + i) = x
                cellDy((t * 4 + r) * 5 + i) = y
            Next i
        Next r
    Next t
    v = Array("ROD", "ELBOW", "CUP", "FLAG", "STAR", "ANCHOR", "STAIRS", "BOLT")
    For i = 0 To 7: stPieceName(i) = v(i): Next i
    stModeName(0) = "marathon": stModeName(1) = "rising": stModeName(2) = "dig"
    v = Array("none", "move", "rotate", "kick", "drop", "hold", "lock", "clear", "level", "garbage", "win", "over")
    For i = 0 To 11: stEventName(i) = v(i): Next i
    ' tried in order after a rotation that collides: none, sideways, up, further
    cx = Array(0, 1, -1, 0, 2, -2, 1, -1, 0, 0)
    cy = Array(0, 0, 0, 1, 0, 0, 1, 1, 2, -1)
    For i = 0 To 9: kickX(i) = cx(i): kickY(i) = cy(i): Next i
    v = Array(0, 100, 300, 600, 1000, 1500, 2100)
    For i = 0 To 6: lineScore(i) = v(i): Next i
    ' gravity: 0.9 s a row at level 1, x0.82 a level, never under 1/30 s
    v = Array(900, 738, 605, 496, 407, 334, 274, 224, 184, 151, 124, 101, 83, 68, 56, 46, 38, 33)
    For i = 0 To 29
        If i <= 17 Then intervalTab(i) = v(i) Else intervalTab(i) = 33
    Next i
    coreReady = True
End Sub

Public Function StMod(ByVal a As Long, ByVal n As Long) As Long
    StMod = ((a Mod n) + n) Mod n
End Function

Public Function StIntervalMs(ByVal lv As Long) As Long
    If lv < 1 Then
        StIntervalMs = intervalTab(0)
    ElseIf lv > 30 Then
        StIntervalMs = intervalTab(29)
    Else
        StIntervalMs = intervalTab(lv - 1)
    End If
End Function

Public Function StRiseEvery(ByVal lv As Long) As Long
    Dim v As Long
    v = 14000 - lv * 1200
    If v < 4000 Then v = 4000
    StRiseEvery = v
End Function

' FNV-1a of a string's bytes
Public Function StHash(ByVal s As String) As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 1 To Len(s)
        h = MulW(h Xor Asc(Mid$(s, i, 1)), 16777619)
    Next i
    StHash = h
End Function

' mulberry32, as the browser's rng(): the next 32 bits
Public Function StRand32() As Long
    Dim t As Long
    stRng = AddW(stRng, &H6D2B79F5)
    t = stRng
    t = MulW(t Xor ShrU(t, 15), t Or 1)
    t = t Xor AddW(t, MulW(t Xor ShrU(t, 7), t Or 61))
    StRand32 = t Xor ShrU(t, 14)
End Function

' floor(rand() * n), as the browser's: (uint64)r * n >> 32 (exact in a Double)
Public Function StRandBelow(ByVal n As Long) As Long
    StRandBelow = Int(UD(StRand32()) * n / 4294967296#)
End Function

Private Sub PushEv(ByVal t As Long, ByVal a As Long, ByVal b As Long)
    If stNEv < ST_MAX_EVENTS Then
        evType(stNEv) = t: evA(stNEv) = a: evB(stNEv) = b
        stNEv = stNEv + 1
    End If
End Sub

' the oldest event into t, a, b; False when there is none
Public Function StPopEvent(t As Long, a As Long, b As Long) As Boolean
    Dim i As Long
    If stNEv = 0 Then Exit Function
    t = evType(0): a = evA(0): b = evB(0)
    For i = 1 To stNEv - 1
        evType(i - 1) = evType(i): evA(i - 1) = evA(i): evB(i - 1) = evB(i)
    Next i
    stNEv = stNEv - 1
    StPopEvent = True
End Function

' a piece's cells into cellC / cellR (columns wrapped); returns the count
Public Function StCellsOf(ByVal typ As Long, ByVal rot As Long, ByVal col As Long, ByVal row As Long) As Long
    Dim n As Long, i As Long, b As Long
    n = stNCells(typ)
    b = (typ * 4 + (rot And 3)) * 5
    For i = 0 To n - 1
        cellC(i) = (col + cellDx(b + i)) And 15
        cellR(i) = row + cellDy(b + i)
    Next i
    StCellsOf = n
End Function

Public Function StCollides(ByVal typ As Long, ByVal rot As Long, ByVal col As Long, ByVal row As Long) As Boolean
    Dim n As Long, i As Long, b As Long, y As Long
    n = stNCells(typ)
    b = (typ * 4 + (rot And 3)) * 5
    For i = 0 To n - 1
        y = row + cellDy(b + i)
        If y < 0 Or y >= ST_TOTAL Then
            StCollides = True
            Exit Function
        End If
        If stBoard(y * 16 + ((col + cellDx(b + i)) And 15)) <> 0 Then
            StCollides = True
            Exit Function
        End If
    Next i
End Function

Private Sub Bag()
    Dim b(0 To 7) As Long, i As Long, j As Long, t As Long
    For i = 0 To 7: b(i) = i: Next i
    For i = 7 To 1 Step -1
        j = StRandBelow(i + 1)
        t = b(i): b(i) = b(j): b(j) = t
    Next i
    For i = 0 To 7
        If stNQueue >= ST_QUEUE Then Exit For
        stQueue(stNQueue) = b(i)
        stNQueue = stNQueue + 1
    Next i
End Sub

Private Sub Refill()
    Do While stNQueue < 8
        Bag
    Loop
End Sub

' the next n pieces into out(); returns how many
Public Function StPreview(ByVal n As Long, outq() As Long) As Long
    Dim i As Long
    Refill
    For i = 0 To n - 1
        If i >= stNQueue Then Exit For
        outq(i) = stQueue(i)
    Next i
    StPreview = i
End Function

' a ring of rubble with gaps holes into row()
Private Sub GarbageRow(ByVal gaps As Long, row() As Long)
    Dim freec(0 To 15) As Long, nf As Long, i As Long, c As Long, seen As Boolean
    For i = 0 To 15: row(i) = ST_GARBAGE: Next i
    Do While nf < gaps
        c = StRandBelow(ST_COLS)
        seen = False
        For i = 0 To nf - 1
            If freec(i) = c Then seen = True
        Next i
        If Not seen Then
            freec(nf) = c
            nf = nf + 1
        End If
    Loop
    For i = 0 To nf - 1: row(freec(i)) = 0: Next i
End Sub

Private Sub Spawn(ByVal typ As Long, ByVal col As Long)
    Dim fresh As Boolean, i As Long
    fresh = typ < 0
    Refill
    If fresh Then
        typ = stQueue(0)
        For i = 1 To stNQueue - 1: stQueue(i - 1) = stQueue(i): Next i
        stNQueue = stNQueue - 1
    End If
    pType = typ
    pRot = 0
    pCol = col And 15
    pRow = ST_ROWS + 1
    stFallMs = 0: stLockMs = 0: stResets = 0
    If fresh Then stCanHold = 1
    If StCollides(pType, pRot, pCol, pRow) Then
        pRow = pRow + 1                         ' try one higher before giving up
        If StCollides(pType, pRot, pCol, pRow) Then
            stOver = 1
            PushEv STE_OVER, 0, 0
        End If
    End If
End Sub

' seed: C's uint32 bits (the games' seeds stay below 2^31)
Public Sub StNewGame(ByVal mode As Long, ByVal seed As Long, ByVal lv As Long, ByVal col As Long)
    Dim i As Long, r As Long, row(0 To 15) As Long, g As Long
    StInit
    For i = 0 To ST_CELLS - 1: stBoard(i) = 0: Next i
    For i = 0 To ST_QUEUE - 1: stQueue(i) = 0: Next i
    stNQueue = 0: stNEv = 0
    pType = 0: pRot = 0: pCol = 0: pRow = 0
    stLines = 0: stPieces = 0: stScore = 0: stTimeMs = 0
    stFallMs = 0: stLockMs = 0: stResets = 0: stSoft = 0
    stOver = 0: stWon = 0: stRiseMs = 0: stGarbageLeft = 0
    stMode = mode
    stSeed = seed
    stRng = StHash(CStr(UD(seed)) & ":" & stModeName(mode))
    If stRng = 0 Then stRng = &H9E3779B9
    stHold = -1
    stCanHold = 1
    If lv < 1 Then lv = 1
    stLevel = lv: stStartLevel = lv
    stCombo = -1
    stLastCol = col
    If mode = MODE_DIG Then
        For r = 0 To ST_DIG_ROWS - 1
            If r Mod 3 = 0 Then g = 2 Else g = 1
            GarbageRow g, row
            For i = 0 To 15: stBoard(r * 16 + i) = row(i): Next i
        Next r
        stGarbageLeft = ST_DIG_ROWS
    End If
    Refill
    Spawn -1, col
End Sub

Private Function Touching() As Boolean
    Touching = StCollides(pType, pRot, pCol, pRow - 1)
End Function

' a successful move or turn on the stack restarts the lock timer, a limited number of times
Private Sub Moved()
    If stResets < ST_LOCK_RESETS Then
        If Touching() Then
            stLockMs = 0
            stResets = stResets + 1
        End If
    End If
End Sub

Public Function StMove(ByVal dir As Long) As Boolean
    Dim c As Long
    If stOver <> 0 Or stWon <> 0 Then Exit Function
    c = (pCol + dir) And 15
    If StCollides(pType, pRot, c, pRow) Then Exit Function
    pCol = c
    stLastCol = c
    Moved
    PushEv STE_MOVE, dir, 0
    StMove = True
End Function

Public Function StRotate(ByVal dir As Long) As Boolean
    Dim k As Long, r As Long, c As Long, w As Long
    If stOver <> 0 Or stWon <> 0 Then Exit Function
    For k = 0 To 9
        r = (pRot + dir) And 3
        c = (pCol + kickX(k) * dir) And 15
        w = pRow + kickY(k)
        If Not StCollides(pType, r, c, w) Then
            pRot = r: pCol = c: pRow = w
            stLastCol = c
            Moved
            If k = 0 Then PushEv STE_ROTATE, dir, 0 Else PushEv STE_KICK, dir, 0
            StRotate = True
            Exit Function
        End If
    Next k
End Function

Public Function StGhostRow() As Long
    Dim w As Long
    w = pRow
    Do
        w = w - 1
    Loop Until StCollides(pType, pRot, pCol, w)
    StGhostRow = w + 1
End Function

Private Function RowFull(ByVal r As Long) As Boolean
    Dim c As Long, b As Long
    b = r * 16
    For c = 0 To 15
        If stBoard(b + c) = 0 Then Exit Function
    Next c
    RowFull = True
End Function

Public Function StCountGarbageRows() As Long
    Dim r As Long, c As Long, n As Long
    For r = 0 To ST_TOTAL - 1
        For c = 0 To 15
            If stBoard(r * 16 + c) = ST_GARBAGE Then
                n = n + 1
                Exit For
            End If
        Next c
    Next r
    StCountGarbageRows = n
End Function

' clears the full rows, the rest falling down; returns how many
Private Function ClearFullRows() As Long
    Dim r As Long, k As Long, c As Long, n As Long
    For r = 0 To ST_TOTAL - 1
        If RowFull(r) Then
            n = n + 1
        Else
            If k <> r Then
                For c = 0 To 15: stBoard(k * 16 + c) = stBoard(r * 16 + c): Next c
            End If
            k = k + 1
        End If
    Next r
    For r = k To ST_TOTAL - 1
        For c = 0 To 15: stBoard(r * 16 + c) = 0: Next c
    Next r
    ClearFullRows = n
End Function

Private Sub LockPiece()
    Dim n As Long, i As Long, allHidden As Boolean, nr As Long, pts As Long, lv As Long
    n = StCellsOf(pType, pRot, pCol, pRow)
    allHidden = True
    For i = 0 To n - 1
        stBoard(cellR(i) * 16 + cellC(i)) = pType + 1
        If cellR(i) < ST_ROWS Then allHidden = False
    Next i
    stPieces = stPieces + 1
    PushEv STE_LOCK, pType, 0
    If allHidden Then
        stOver = 1
        PushEv STE_OVER, 1, 0
        Exit Sub
    End If
    nr = ClearFullRows()
    If nr > 0 Then
        stCombo = stCombo + 1
        stLines = stLines + nr
        If nr < 7 Then pts = lineScore(nr) * stLevel Else pts = lineScore(6) * stLevel
        If stCombo > 0 Then pts = pts + 50 * stCombo * stLevel
        stScore = stScore + pts
        PushEv STE_CLEAR, nr, pts
        If stMode = MODE_DIG Then
            stGarbageLeft = StCountGarbageRows()
            If stGarbageLeft = 0 Then
                stWon = 1
                PushEv STE_WIN, stTimeMs, 0
                Exit Sub
            End If
        End If
        lv = stStartLevel + stLines \ 10
        If stMode <> MODE_DIG And lv > stLevel Then
            stLevel = lv
            PushEv STE_LEVEL, lv, 0
        End If
    Else
        stCombo = -1
    End If
    Spawn -1, stLastCol
End Sub

Public Function StHardDrop() As Long
    Dim t As Long, dist As Long
    If stOver <> 0 Or stWon <> 0 Then Exit Function
    t = StGhostRow()
    dist = pRow - t
    pRow = t
    stScore = stScore + 2 * dist
    PushEv STE_DROP, dist, 0
    LockPiece
    StHardDrop = dist
End Function

Public Sub StSoftDrop(ByVal onOff As Boolean)
    If onOff Then stSoft = 1 Else stSoft = 0
End Sub

Public Function StHoldPiece() As Boolean
    Dim cur As Long, t As Long
    If stOver <> 0 Or stWon <> 0 Or stCanHold = 0 Then Exit Function
    cur = pType
    If stHold < 0 Then
        stHold = cur
        Spawn -1, stLastCol
    Else
        t = stHold
        stHold = cur
        Spawn t, stLastCol
    End If
    stCanHold = 0
    PushEv STE_HOLD, cur, 0
    StHoldPiece = True
End Function

Public Sub StAddGarbage(ByVal gaps As Long)
    Dim row(0 To 15) As Long, c As Long, i As Long, spilled As Boolean
    GarbageRow gaps, row
    For c = 0 To 15
        If stBoard((ST_TOTAL - 1) * 16 + c) <> 0 Then spilled = True
    Next c
    For i = ST_CELLS - 1 To 16 Step -1: stBoard(i) = stBoard(i - 16): Next i
    For c = 0 To 15: stBoard(c) = row(c): Next c
    If spilled Then
        stOver = 1
        PushEv STE_OVER, 2, 0
        Exit Sub
    End If
    If StCollides(pType, pRot, pCol, pRow) Then
        pRow = pRow + 1
        If StCollides(pType, pRot, pCol, pRow) Then
            stOver = 1
            PushEv STE_OVER, 2, 0
            Exit Sub
        End If
    End If
    PushEv STE_GARBAGE, 0, 0
End Sub

Public Sub StTick(ByVal dt As Long)
    Dim stp As Long, iv As Long, s As Long, every As Long
    If stOver <> 0 Or stWon <> 0 Then Exit Sub
    stTimeMs = stTimeMs + dt
    If stMode = MODE_RISING Then
        every = StRiseEvery(stLevel)
        stRiseMs = stRiseMs + dt
        If stRiseMs >= every Then
            stRiseMs = stRiseMs - every
            If stLevel >= 6 Then StAddGarbage 1 Else StAddGarbage 2
            If stOver <> 0 Then Exit Sub
        End If
    End If
    iv = StIntervalMs(stLevel)
    stp = iv
    If stSoft <> 0 Then
        s = iv \ 20
        If s < 17 Then s = 17
        If s < iv Then stp = s Else stp = iv
    End If
    If Touching() Then
        stFallMs = 0
        stLockMs = stLockMs + dt
        If stLockMs >= ST_LOCK_MS Or (stResets >= ST_LOCK_RESETS And stLockMs >= ST_LOCK_MS \ 3) Then LockPiece
        Exit Sub
    End If
    stFallMs = stFallMs + dt
    Do While stFallMs >= stp
        If Touching() Then Exit Do
        stFallMs = stFallMs - stp
        pRow = pRow - 1
        If stSoft <> 0 Then stScore = stScore + 1
    Loop
    If Touching() Then stFallMs = 0
End Sub

' the whole state, as tools/trace.c's state_hash
Public Function StStateHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To ST_CELLS - 1: h = Fnv(h, stBoard(i)): Next i
    h = Fnv(h, stMode): h = Fnv(h, stRng): h = Fnv(h, stNQueue)
    For i = 0 To stNQueue - 1: h = Fnv(h, stQueue(i)): Next i
    h = Fnv(h, stHold): h = Fnv(h, stCanHold)
    h = Fnv(h, pType): h = Fnv(h, pRot): h = Fnv(h, pCol): h = Fnv(h, pRow)
    h = Fnv(h, stLevel): h = Fnv(h, stLines): h = Fnv(h, stCombo): h = Fnv(h, stPieces)
    h = Fnv(h, stScore): h = Fnv(h, stTimeMs)
    h = Fnv(h, stFallMs): h = Fnv(h, stLockMs): h = Fnv(h, stResets): h = Fnv(h, stSoft)
    h = Fnv(h, stOver): h = Fnv(h, stWon): h = Fnv(h, stRiseMs): h = Fnv(h, stGarbageLeft)
    h = Fnv(h, stLastCol)
    StStateHash = h
End Function

Public Function StBoardHash() As Long
    Dim h As Long, i As Long
    h = FNV_START
    For i = 0 To ST_CELLS - 1: h = Fnv(h, stBoard(i)): Next i
    StBoardHash = h
End Function
