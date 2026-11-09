' Gridwise - the grid view: scrolling, the cursor and selection, hit testing, and drawing
' the sheet (headers, cells, selection, floating charts) onto a Canvas. Works with any
' object that has the Canvas methods, so it is also drawn off-screen in the tests.
Option Explicit

Public Const HDR_H As Long = 16       ' column header height
Public Const ROW_H As Long = 15       ' row height
Public Const RHDR_W As Long = 40      ' row header width

Public vw As Long, vh As Long          ' the picture size
Public topRow As Long, leftCol As Long
Public curR As Long, curC As Long     ' the cursor cell
Public ancR As Long, ancC As Long     ' the selection's other corner (anchor)
Public selChart As Long               ' the chart selected for moving/resizing, -1 none
Public ShowGridLines As Boolean
Public ShowFormulas As Boolean        ' show what was typed instead of values
Public DrawCount As Long

' colours
Public colBack As Long, colGrid As Long, colHdr As Long, colHdrSel As Long, colHdrText As Long
Public colSel As Long, colCursor As Long, colText As Long, colErr As Long, colFormulaMark As Long

Public Sub ViewInit(ByVal w As Long, ByVal h As Long)
    vw = w: vh = h
    topRow = 0: leftCol = 0: curR = 0: curC = 0: ancR = 0: ancC = 0
    selChart = -1
    ShowGridLines = True
    colBack = RGB(255, 255, 255)
    colGrid = RGB(218, 222, 230)
    colHdr = RGB(232, 234, 240)
    colHdrSel = RGB(196, 210, 236)
    colHdrText = RGB(70, 74, 84)
    colSel = RGB(214, 228, 252)
    colCursor = RGB(28, 84, 196)
    colText = RGB(20, 20, 20)
    colErr = RGB(200, 0, 0)
End Sub

Public Sub SelBounds(r1 As Long, c1 As Long, r2 As Long, c2 As Long)
    If curR < ancR Then r1 = curR: r2 = ancR Else r1 = ancR: r2 = curR
    If curC < ancC Then c1 = curC: c2 = ancC Else c1 = ancC: c2 = curC
End Sub

Public Function SelName() As String
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long
    SelBounds r1, c1, r2, c2
    If r1 = r2 And c1 = c2 Then SelName = CellName(r1, c1) Else SelName = RangeName(r1, c1, r2, c2)
End Function

Public Function VisibleRows() As Long
    VisibleRows = (vh - HDR_H) \ ROW_H
    If VisibleRows < 1 Then VisibleRows = 1
End Function

' the columns that fit fully from leftCol
Public Function VisibleCols() As Long
    Dim x As Long, c As Long, n As Long
    x = RHDR_W
    c = leftCol
    Do While c < NC
        x = x + colW(c)
        If x > vw Then Exit Do
        n = n + 1
        c = c + 1
    Loop
    If n < 1 Then n = 1
    VisibleCols = n
End Function

' scroll so that the cursor is visible
Public Sub EnsureVisible()
    Dim x As Long, c As Long
    If curR < topRow Then topRow = curR
    If curR >= topRow + VisibleRows() Then topRow = curR - VisibleRows() + 1
    If curC < leftCol Then leftCol = curC
    Do While curC >= leftCol + VisibleCols() And leftCol < curC
        leftCol = leftCol + 1
    Loop
    If topRow < 0 Then topRow = 0
End Sub

' move the cursor; extend = keep the anchor (Shift)
Public Sub MoveCursor(ByVal r As Long, ByVal c As Long, ByVal extend As Boolean)
    If r < 0 Then r = 0
    If c < 0 Then c = 0
    If r >= NR Then r = NR - 1
    If c >= NC Then c = NC - 1
    curR = r: curC = c
    If Not extend Then ancR = r: ancC = c
    EnsureVisible
End Sub

Public Sub SelectRange(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long)
    ancR = r1: ancC = c1
    MoveCursor r2, c2, True
End Sub

' the x of column c's left edge on screen (may be off-screen); -1 if left of the view
Public Function ColX(ByVal c As Long) As Long
    Dim x As Long, i As Long
    If c < leftCol Then ColX = -1: Exit Function
    x = RHDR_W
    For i = leftCol To c - 1
        x = x + colW(i)
    Next i
    ColX = x
End Function

Public Function RowY(ByVal r As Long) As Long
    RowY = HDR_H + (r - topRow) * ROW_H
End Function

' which cell is at (x, y): r = -1 for the column header, c = -1 for the row header.
' Returns False outside the sheet. edge = True when x is within 3 px of a column's right
' edge in the header (for resizing).
Public Function HitTest(ByVal x As Long, ByVal y As Long, r As Long, c As Long, edge As Boolean) As Boolean
    Dim cx As Long, i As Long
    edge = False
    If y < HDR_H Then
        r = -1
    Else
        r = topRow + (y - HDR_H) \ ROW_H
        If r >= NR Then Exit Function
    End If
    If x < RHDR_W Then
        c = -1
    Else
        cx = RHDR_W
        i = leftCol
        Do While i < NC
            If x < cx + colW(i) Then Exit Do
            cx = cx + colW(i)
            i = i + 1
        Loop
        If i >= NC Then Exit Function
        c = i
        If r = -1 And cx + colW(i) - x <= 3 Then edge = True
        If r = -1 And x - cx <= 2 And i > leftCol Then c = i - 1: edge = True
    End If
    HitTest = True
End Function

' the chart under (x, y), -1 if none; corner = True on its bottom-right resize handle
Public Function ChartAt(ByVal x As Long, ByVal y As Long, corner As Boolean) As Long
    Dim i As Long, cx As Long, cy As Long
    ChartAt = -1
    For i = NCharts - 1 To 0 Step -1
        ChartPos i, cx, cy
        If x >= cx And y >= cy And x < cx + chW(i) And y < cy + chH(i) Then
            corner = (x >= cx + chW(i) - 8 And y >= cy + chH(i) - 8)
            ChartAt = i
            Exit Function
        End If
    Next i
End Function

' a chart's top-left on screen (it scrolls with its anchor cell)
Public Sub ChartPos(ByVal i As Long, x As Long, y As Long)
    Dim c As Long
    x = RHDR_W
    If chCol(i) >= leftCol Then
        For c = leftCol To chCol(i) - 1: x = x + colW(c): Next c
    Else
        For c = chCol(i) To leftCol - 1: x = x - colW(c): Next c
    End If
    y = HDR_H + (chRow(i) - topRow) * ROW_H
End Sub

' ---- drawing -------------------------------------------------------------------------------

' text cut to fit w pixels (the canvas font is fixed width)
Private Function Clip(cv As Object, ByVal s As String, ByVal w As Long) As String
    Dim n As Long, cw As Long
    cw = cv.TextWidth("M")
    If cw < 1 Then cw = 6
    n = w \ cw
    If n < 0 Then n = 0
    If Len(s) > n Then Clip = Left$(s, n) Else Clip = s
End Function

Public Sub DrawGrid(cv As Object)
    Dim r As Long, c As Long, x As Long, y As Long, nrows As Long, r1 As Long, c1 As Long, r2 As Long, c2 As Long
    Dim xs(0 To 700) As Long, ncols As Long, lastC As Long, s As String, w As Long, a As Long, f As Long
    Dim tx As Long, ty As Long, k As Long, th As Long, tw As Long, cw As Long, span As Long, cc As Long
    Dim fc As Long, i As Long, cx As Long, cy As Long
    DrawCount = DrawCount + 1
    th = cv.TextHeight("A")
    cw = cv.TextWidth("M")
    cv.Box 0, 0, vw, vh, colBack
    nrows = (vh - HDR_H) \ ROW_H + 1
    ' column edges
    x = RHDR_W
    c = leftCol
    ncols = 0
    xs(0) = x
    Do While c < NC And x < vw
        x = x + colW(c)
        ncols = ncols + 1
        xs(ncols) = x
        c = c + 1
    Loop
    lastC = leftCol + ncols - 1
    SelBounds r1, c1, r2, c2
    ' selection background
    If r2 >= topRow And c2 >= leftCol Then
        Dim sx1 As Long, sx2 As Long, sy1 As Long, sy2 As Long
        If c1 < leftCol Then sx1 = RHDR_W Else sx1 = xs(c1 - leftCol)
        If c2 > lastC Then sx2 = vw Else sx2 = xs(c2 - leftCol + 1)
        sy1 = RowY(r1): If sy1 < HDR_H Then sy1 = HDR_H
        sy2 = RowY(r2 + 1)
        If Not (r1 = r2 And c1 = c2) Then cv.Box sx1, sy1, sx2 - sx1, sy2 - sy1, colSel
    End If
    ' grid lines
    If ShowGridLines Then
        For i = 0 To ncols
            cv.Line xs(i) - 1, HDR_H, xs(i) - 1, vh - 1, colGrid
        Next i
        For r = 0 To nrows
            y = HDR_H + r * ROW_H - 1
            cv.Line RHDR_W, y, vw - 1, y, colGrid
        Next r
    End If
    ' cells
    ty = (ROW_H - th) \ 2
    For r = topRow To topRow + nrows - 1
        If r >= NR Then Exit For
        y = RowY(r)
        For c = leftCol To lastC
            If ShowFormulas Then
                s = GetSrc(r, c)
                k = KTEXT
                If s = "" Then k = KEMPTY
            Else
                k = CellKind(r, c)
                If k <> KEMPTY Then s = CellText(r, c)
            End If
            If k <> KEMPTY Then
                w = colW(c) - 4
                f = GetFormat(r, c)
                If ShowFormulas Then a = AL_LEFT Else a = CellAlign(r, c)
                tw = Len(s) * cw
                If k = KNUM And tw > w And Not ShowFormulas Then
                    s = String$(w \ cw, "#")
                    tw = Len(s) * cw
                End If
                ' left-aligned text runs on over empty cells to its right
                span = w
                If tw > w And a = AL_LEFT Then
                    cc = c + 1
                    Do While cc <= lastC And span < tw
                        If GetSrc(r, cc) <> "" Then Exit Do
                        span = span + colW(cc)
                        cc = cc + 1
                    Loop
                    If span > w Then
                        ' wipe the grid lines the text runs over
                        cv.Box xs(c - leftCol + 1) - 1, y, span - w, ROW_H - 1, colBack
                    End If
                End If
                s = Clip(cv, s, span)
                tw = Len(s) * cw
                Select Case a
                Case AL_RIGHT: tx = xs(c - leftCol) + colW(c) - 3 - tw
                Case AL_CENTER: tx = xs(c - leftCol) + (colW(c) - tw) \ 2
                Case Else: tx = xs(c - leftCol) + 2
                End Select
                If k = KERR Then fc = colErr Else fc = colText
                cv.DrawText tx, y + ty, s, fc
                If (f And FMT_BOLD) <> 0 Then cv.DrawText tx + 1, y + ty, s, fc
                If (f And FMT_ITALIC) <> 0 Then cv.Line tx, y + ty + th, tx + tw - 1, y + ty + th, fc
            End If
        Next c
    Next r
    ' headers
    cv.Box 0, 0, vw, HDR_H, colHdr
    cv.Box 0, HDR_H, RHDR_W, vh - HDR_H, colHdr
    For i = 0 To ncols - 1
        c = leftCol + i
        If c >= c1 And c <= c2 Then cv.Box xs(i), 0, colW(c) - 1, HDR_H - 1, colHdrSel
        s = ColName(c)
        cv.DrawText xs(i) + (colW(c) - Len(s) * cw) \ 2, (HDR_H - th) \ 2, s, colHdrText
        cv.Line xs(i + 1) - 1, 0, xs(i + 1) - 1, HDR_H - 1, RGB(190, 194, 204)
    Next i
    For r = topRow To topRow + nrows - 1
        If r >= NR Then Exit For
        y = RowY(r)
        If r >= r1 And r <= r2 Then cv.Box 0, y, RHDR_W - 1, ROW_H - 1, colHdrSel
        s = CStr(r + 1)
        cv.DrawText RHDR_W - 4 - Len(s) * cw, y + ty, s, colHdrText
        cv.Line 0, y + ROW_H - 1, RHDR_W - 1, y + ROW_H - 1, RGB(190, 194, 204)
    Next r
    cv.Line 0, HDR_H - 1, vw - 1, HDR_H - 1, RGB(160, 164, 176)
    cv.Line RHDR_W - 1, 0, RHDR_W - 1, vh - 1, RGB(160, 164, 176)
    ' selection outline and the cursor
    If curR >= topRow And curR < topRow + nrows And curC >= leftCol And curC <= lastC Then
        x = xs(curC - leftCol): y = RowY(curR)
        cv.Rect x - 1, y - 1, colW(curC) + 1, ROW_H + 1, colCursor
        cv.Rect x, y, colW(curC) - 1, ROW_H - 1, colCursor
    End If
    ' floating charts
    For i = 0 To NCharts - 1
        ChartPos i, cx, cy
        If cx < vw And cy < vh And cx + chW(i) > RHDR_W And cy + chH(i) > HDR_H Then
            cv.Box cx + 3, cy + 3, chW(i), chH(i), RGB(170, 170, 178)
            DrawChart cv, i, cx, cy, chW(i), chH(i)
            If i = selChart Then
                cv.Rect cx - 1, cy - 1, chW(i) + 2, chH(i) + 2, colCursor
                cv.Box cx + chW(i) - 6, cy + chH(i) - 6, 6, 6, colCursor
            End If
        End If
    Next i
End Sub
