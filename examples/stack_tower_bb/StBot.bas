' StBot - who plays when nobody does: the title's demo (game.c's demo_step: every 6th
' tick a piece goes straight to its best place) and the bot (rotates and turns a step a
' tick, holds now and then, soft drops, hard drops or waits), for --bench, the autoplay
' key and the tests. tools/trace.c has the same two in C.
Option Explicit

Private demoT As Long
Private botPieces As Long, botCol As Long, botRot As Long, botHoldTries As Long

Public Sub BotReset()
    demoT = 0
    botPieces = -1
    botHoldTries = 0
End Sub

' the lowest place, as the title's demo picks it
Private Sub BestPlace(bc As Long, br As Long)
    Dim best As Long, r As Long, c As Long, w As Long, n As Long, k As Long, h As Long
    best = &H40000000
    bc = 0: br = 0
    For r = 0 To 3
        For c = 0 To 15
            If Not StCollides(pType, r, c, pRow) Then
                w = pRow
                Do
                    w = w - 1
                Loop Until StCollides(pType, r, c, w)
                n = StCellsOf(pType, r, c, w + 1)
                h = 0
                For k = 0 To n - 1: h = h + cellR(k) * 4: Next k
                h = h + (A3Hash(c * 4 + r + stPieces * 64) And 3)
                If h < best Then
                    best = h: bc = c: br = r
                End If
            End If
        Next c
    Next r
End Sub

' the title's demo, one tick (call before StTick)
Public Sub DemoStep()
    Dim c As Long, r As Long
    demoT = demoT + 1
    If demoT < 6 Then Exit Sub
    demoT = 0
    If stOver <> 0 Then
        StNewGame MODE_MARATHON, A3Hash(stSeed), 1, 0
        Exit Sub
    End If
    BestPlace c, r
    pRot = r
    pCol = c
    stLastCol = c
    StHardDrop
End Sub

' the bot's choice: low, filling rings, few holes under the piece
Private Sub BotPlace(bc As Long, br As Long)
    Dim best As Long, r As Long, c As Long, w As Long, n As Long, k As Long, j As Long, m As Long
    Dim h As Long, row As Long, full As Boolean, inp As Boolean
    best = &H40000000
    bc = pCol: br = pRot
    For r = 0 To 3
        For c = 0 To 15
            If Not StCollides(pType, r, c, pRow) Then
                w = pRow
                Do
                    w = w - 1
                Loop Until StCollides(pType, r, c, w)
                n = StCellsOf(pType, r, c, w + 1)
                h = 0
                For k = 0 To n - 1
                    h = h + cellR(k) * 6
                    row = cellR(k) - 1           ' a hole: an empty cell right under, not the piece's own
                    If row >= 0 Then
                        If stBoard(row * 16 + cellC(k)) = 0 Then
                            For j = 0 To n - 1
                                If cellC(j) = cellC(k) And cellR(j) = row Then Exit For
                            Next j
                            If j = n Then h = h + 10
                        End If
                    End If
                Next k
                For k = 0 To n - 1                ' rings it fills (a row counted once per cell in it)
                    row = cellR(k)
                    full = True
                    For j = 0 To 15
                        inp = False
                        For m = 0 To n - 1
                            If cellC(m) = j And cellR(m) = row Then inp = True
                        Next m
                        If Not inp And stBoard(row * 16 + j) = 0 Then
                            full = False
                            Exit For
                        End If
                    Next j
                    If full Then h = h - 40
                Next k
                h = h + (A3Hash(c * 4 + r + stPieces * 64) And 3)
                If h < best Then
                    best = h: bc = c: br = r
                End If
            End If
        Next c
    Next r
End Sub

' the bot, one tick (call before StTick)
Public Sub BotTick()
    Dim d As Long
    If stPieces <> botPieces Or botHoldTries <> 0 Then
        If stPieces <> botPieces Then botHoldTries = 0
        botPieces = stPieces
        If stPieces Mod 7 = 3 And stCanHold <> 0 And botHoldTries = 0 Then
            StHoldPiece
            botHoldTries = 1
        Else
            botHoldTries = 0
        End If
        BotPlace botCol, botRot
    End If
    If pRot <> botRot Then
        If Not StRotate(1) Then botRot = pRot
        StSoftDrop False
    ElseIf pCol <> botCol Then
        If StMod(botCol - pCol, 16) <= 8 Then d = 1 Else d = -1
        If Not StMove(d) Then botCol = pCol
        StSoftDrop False
    ElseIf stPieces Mod 3 = 0 Then
        StSoftDrop True
    ElseIf stPieces Mod 3 = 1 Then
        StSoftDrop False
        StHardDrop
    Else
        StSoftDrop False
    End If
End Sub
