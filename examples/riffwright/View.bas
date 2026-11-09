' Riffwright - drawing: the pattern editor, scopes, order and sample lists, sample view
'
' Speed: the pattern's text is drawn once into an image (patImg, 64 rows) and only the
' changed rows are redrawn after an edit. A frame copies the visible part of that image
' with one DrawImagePart, at any pixel offset, so the pattern scrolls smoothly during
' playback at the cost of a handful of calls. The order and sample lists are cached the same
' way (sideImg).
Option Explicit

' ---- layout
Public Const CW As Long = 68          ' channel column width
Public Const PX0 As Long = 26         ' first channel's x
Public Const RH As Long = 10          ' row height
Public Const PY0 As Long = 84         ' pattern area top
Public Const PH As Long = 380         ' pattern area height (38 rows)
Public Const CENTER As Long = 18      ' the cursor row's place in the visible rows
Public Const SY0 As Long = 18         ' info / scope strip top
Public Const SH As Long = 52

Public cv As Object                   ' the canvas
Public scrW As Long, scrH As Long

' ---- colours
Public cBg As Long, cPanel As Long, cBeat As Long, cBar As Long, cLine As Long
Public cCurRow As Long, cCursor As Long, cPlayRow As Long, cSel As Long
Public cNote As Long, cDim As Long, cSmpC As Long, cFxC As Long, cRowNum As Long, cRowNum4 As Long
Public cTitle As Long, cText As Long, cLabel As Long, cWarn As Long, cGood As Long, cMute As Long
Public cWave As Long, cLoop As Long

' ---- cached images
Private slotImg(0 To 1) As Long       ' two pattern images: the one shown and the next one
Private slotPat(0 To 1) As Long       ' pattern in each (-1 = none)
Private slotRows(0 To 1) As Long      ' rows drawn so far (64 = complete)
Private slotCh(0 To 1) As Long
Private patImg As Long                ' the image of the pattern shown
Private blankRow As Long             ' a transparent row, to clear rows of patImg
Private sideImg As Long
Public sideDirty As Boolean
Private logoImg As Long

' ---- scope buffers
Private scX() As Long, scY() As Long
Private Const SCN As Long = 96

Public Sub ViewInit(c As Object)
    Set cv = c
    scrW = cv.Width
    scrH = cv.Height
    cBg = RGB(12, 15, 26): cPanel = RGB(22, 27, 44): cBeat = RGB(20, 26, 42): cBar = RGB(30, 37, 60)
    cLine = RGB(44, 52, 80)
    cCurRow = RGB(70, 46, 22): cCursor = RGB(255, 176, 64): cPlayRow = RGB(26, 74, 62): cSel = RGB(40, 58, 110)
    cNote = RGB(232, 238, 248): cDim = RGB(62, 72, 98): cSmpC = RGB(255, 190, 96): cFxC = RGB(110, 214, 224)
    cRowNum = RGB(112, 122, 154): cRowNum4 = RGB(214, 176, 112)
    cTitle = RGB(255, 200, 110): cText = RGB(214, 220, 236): cLabel = RGB(120, 132, 170)
    cWarn = RGB(255, 110, 90): cGood = RGB(110, 230, 150): cMute = RGB(150, 60, 60)
    cWave = RGB(110, 214, 224): cLoop = RGB(255, 176, 64)
    slotImg(0) = cv.CreateImage(PX0 + MAXCH * CW, ROWS * RH)
    slotImg(1) = cv.CreateImage(PX0 + MAXCH * CW, ROWS * RH)
    blankRow = cv.CreateImage(PX0 + MAXCH * CW, RH)
    slotPat(0) = -1: slotPat(1) = -1
    sideImg = cv.CreateImage(scrW, PH)
    sideDirty = True
    ReDim scX(0 To SCN - 1)
    ReDim scY(0 To SCN - 1)
    MakeLogo
End Sub

' the "RIFFWRIGHT" logo: letters in a warm gradient with a shadow, drawn once
Private Sub MakeLogo()
    Dim s As String, i As Long, x As Long, col As Long
    s = "RIFFWRIGHT"
    logoImg = cv.CreateImage(Len(s) * 7 + 2, 11)
    cv.SetTarget logoImg
    For i = 1 To Len(s)
        x = (i - 1) * 7
        cv.DrawText x + 1, 1, Mid$(s, i, 1), RGB(60, 20, 10)
        col = RGB(255, 220 - i * 9, 90 + i * 6)
        cv.DrawText x, 0, Mid$(s, i, 1), col
    Next i
    cv.SetTarget 0
End Sub

Public Function PatWidth() As Long
    PatWidth = PX0 + nch * CW
End Function

' ---------------------------------------------------------------- pattern image

Public Sub InvalidatePattern()
    slotPat(0) = -1: slotPat(1) = -1
End Sub

Private Function SlotOf(ByVal p As Long) As Long
    SlotOf = -1
    If slotPat(0) = p And slotCh(0) = nch Then SlotOf = 0
    If slotPat(1) = p And slotCh(1) = nch Then SlotOf = 1
End Function

' draw up to n more rows of slot s
Private Sub FillSlot(ByVal s As Long, ByVal n As Long)
    Dim r As Long, r1 As Long
    If slotRows(s) >= ROWS Then Exit Sub
    cv.SetTarget slotImg(s)
    If slotRows(s) = 0 Then cv.Cls
    r1 = slotRows(s) + n - 1
    If r1 > ROWS - 1 Then r1 = ROWS - 1
    For r = slotRows(s) To r1
        DrawRowText r, slotPat(s)
    Next r
    cv.SetTarget 0
    slotRows(s) = r1 + 1
End Sub

Private Sub ClaimSlot(ByVal s As Long, ByVal p As Long)
    slotPat(s) = p
    slotCh(s) = nch
    slotRows(s) = 0
End Sub

' make the pattern image show pattern p (all rows)
Public Sub EnsurePattern(ByVal p As Long)
    Dim s As Long
    s = SlotOf(p)
    If s < 0 Then
        ' take the slot that isn't shown
        If slotImg(0) = patImg Then s = 1 Else s = 0
        ClaimSlot s, p
    End If
    If slotRows(s) < ROWS Then FillSlot s, ROWS
    patImg = slotImg(s)
End Sub

' draw the next pattern into the spare image a few rows per frame, so following the song
' into it costs nothing (call once per frame while playing)
Public Sub PrefetchPattern(ByVal p As Long, ByVal rowsPerCall As Long)
    Dim s As Long
    s = SlotOf(p)
    If s < 0 Then
        If slotImg(0) = patImg Then s = 1 Else s = 0
        ClaimSlot s, p
    End If
    If slotImg(s) = patImg Then Exit Sub
    FillSlot s, rowsPerCall
End Sub

' redraw rows r0..r1 of pattern p's image after an edit (if it is drawn)
Public Sub RefreshRows(ByVal p As Long, ByVal r0 As Long, ByVal r1 As Long)
    Dim r As Long, s As Long
    s = SlotOf(p)
    If s < 0 Then Exit Sub
    If r0 < 0 Then r0 = 0
    If r1 > slotRows(s) - 1 Then r1 = slotRows(s) - 1
    If r1 < r0 Then Exit Sub
    cv.SetTarget slotImg(s)
    For r = r0 To r1
        cv.DrawImagePart blankRow, 0, 0, PX0 + MAXCH * CW, RH, 0, r * RH, True   ' clear to transparent
        DrawRowText r, p
    Next r
    cv.SetTarget 0
End Sub

Private Sub DrawRowText(ByVal r As Long, ByVal p As Long)
    Dim c As Long, k As Long, x As Long, y As Long, rn As String
    y = r * RH + 1
    rn = Right$("0" & r, 2)
    If r Mod 4 = 0 Then cv.DrawText 4, y, rn, cRowNum4 Else cv.DrawText 4, y, rn, cRowNum
    k = CellIdx(p, r, 0)
    For c = 0 To nch - 1
        x = PX0 + c * CW
        If cPer(k) = 0 And cSmp(k) = 0 And cFx(k) = 0 And cPrm(k) = 0 Then
            cv.DrawText x, y, "--- .. ...", cDim       ' an empty cell: one call
        Else
            If cPer(k) = 0 Then
                cv.DrawText x, y, "---", cDim
            Else
                cv.DrawText x, y, noteName(noteOfPer(cPer(k) And 4095)), cNote
            End If
            If cSmp(k) = 0 Then
                cv.DrawText x + 24, y, "..", cDim
            Else
                cv.DrawText x + 24, y, Hex2(cSmp(k)), cSmpC
            End If
            If cFx(k) = 0 And cPrm(k) = 0 Then
                cv.DrawText x + 42, y, "...", cDim
            Else
                cv.DrawText x + 42, y, Hex$(cFx(k)) & Hex2(cPrm(k)), cFxC
            End If
        End If
        k = k + 1
    Next c
End Sub

' x of a field (0 note, 1/2 sample digits, 3 effect, 4/5 parameter digits) and its width
Public Sub FieldBox(ByVal ch As Long, ByVal field As Long, x As Long, w As Long)
    x = PX0 + ch * CW
    Select Case field
        Case 0: w = 18
        Case 1: x = x + 24: w = 6
        Case 2: x = x + 30: w = 6
        Case 3: x = x + 42: w = 6
        Case 4: x = x + 48: w = 6
        Case Else: x = x + 54: w = 6
    End Select
End Sub

' ---------------------------------------------------------------- the pattern area
' viewY = the cursor's row * RH plus a sub-row offset in pixels (smooth scrolling)
Public Sub DrawPattern(ByVal p As Long, ByVal viewY As Long, ByVal curRow As Long, ByVal curCh As Long, _
                       ByVal curField As Long, ByVal playRow As Long, ByVal editOn As Boolean, _
                       ByVal selOn As Boolean, ByVal sr0 As Long, ByVal sr1 As Long, ByVal sc0 As Long, ByVal sc1 As Long)
    Dim top As Long, r As Long, y As Long, w As Long, r0 As Long, r1 As Long, sy As Long, dy As Long, h As Long
    Dim x As Long, fw As Long, c As Long, t As Long
    w = PatWidth()
    EnsurePattern p
    top = viewY - CENTER * RH                       ' pattern pixel at the area's top
    cv.Box 0, PY0, w, PH, cBg
    ' beat stripes, the play row, the selection
    r0 = top \ RH: If r0 < 0 Then r0 = 0
    r1 = (top + PH) \ RH: If r1 > ROWS - 1 Then r1 = ROWS - 1
    For r = r0 - (r0 Mod 4) To r1 Step 4
        If r >= 0 Then
            y = PY0 + r * RH - top
            If r Mod 16 = 0 Then cv.Box 0, y, w, RH, cBar Else cv.Box 0, y, w, RH, cBeat
        End If
    Next r
    If selOn Then
        If sr0 > sr1 Then t = sr0: sr0 = sr1: sr1 = t
        If sc0 > sc1 Then t = sc0: sc0 = sc1: sc1 = t
        y = PY0 + sr0 * RH - top
        h = (sr1 - sr0 + 1) * RH
        If y < PY0 Then h = h - (PY0 - y): y = PY0
        If y + h > PY0 + PH Then h = PY0 + PH - y
        If h > 0 Then cv.Box PX0 + sc0 * CW - 2, y, (sc1 - sc0) * CW + 60, h, cSel
    End If
    If playRow >= 0 Then
        y = PY0 + playRow * RH - top
        If y >= PY0 And y + RH <= PY0 + PH Then cv.Box 0, y, w, RH, cPlayRow
    End If
    ' the cursor row bar at the centre
    y = PY0 + CENTER * RH + (curRow * RH - viewY)
    If editOn Then cv.Box 0, y, w, RH, RGB(96, 34, 30) Else cv.Box 0, y, w, RH, cCurRow
    ' the rows (one copy of the cached image)
    sy = top: dy = PY0: h = PH
    If sy < 0 Then dy = PY0 - sy: h = PH + sy: sy = 0
    If sy + h > ROWS * RH Then h = ROWS * RH - sy
    If h > 0 Then cv.DrawImagePart patImg, 0, sy, w, h, 0, dy
    ' channel separators
    For c = 1 To nch
        x = PX0 + c * CW - 7
        cv.Line x, PY0, x, PY0 + PH - 1, cLine
    Next c
    ' the cursor
    FieldBox curCh, curField, x, fw
    cv.Rect x - 1, y - 1, fw + 2, RH + 1, cCursor
    ' area edges: dim the rows outside the pattern
    If top < 0 Then cv.Box 0, PY0, w, -top, cPanel
    If top + PH > ROWS * RH Then cv.Box 0, PY0 + ROWS * RH - top, w, top + PH - ROWS * RH, cPanel
End Sub

' channel headings above the pattern: number, mute/solo state
Public Sub DrawChannelHeads(ByVal curCh As Long)
    Dim c As Long, x As Long, s As String, col As Long
    cv.Box 0, PY0 - 12, PatWidth(), 12, cPanel
    For c = 0 To nch - 1
        x = PX0 + c * CW
        s = "CH" & (c + 1)
        col = cLabel
        If c = curCh Then col = cTitle
        If ChanMuted(c) Then s = s & " MUTE": col = cMute
        cv.DrawText x, PY0 - 11, s, col
    Next c
End Sub

' ---------------------------------------------------------------- info strip and scopes

Public Sub DrawHeader(ByVal msg As String)
    Dim t As String
    cv.Box 0, 0, scrW, SY0 - 2, cPanel
    cv.DrawImage logoImg, 6, 4
    t = TitleText()
    If Len(t) = 0 Then t = "(untitled)"
    cv.DrawText 86, 4, t, cText
    If songDirty Then cv.DrawText 86 + cv.TextWidth(t) + 6, 4, "*", cWarn
    cv.DrawText scrW - cv.TextWidth(msg) - 6, 4, msg, cLabel
End Sub

Public Sub DrawInfo(ByVal pos As Long, ByVal pat As Long, ByVal row As Long, ByVal speed As Long, _
                    ByVal tempo As Long, ByVal oct As Long, ByVal smp As Long, ByVal editOn As Boolean, _
                    ByVal followOn As Boolean, ByVal mode As Long)
    Dim y As Long
    y = SY0
    cv.Box 0, y, 226, SH, cPanel
    Lbl 6, y + 3, "POS", Right$("0" & pos, 2) & "/" & Right$("0" & songLen, 2)
    Lbl 76, y + 3, "PAT", Right$("0" & pat, 2)
    Lbl 130, y + 3, "ROW", Right$("0" & row, 2)
    Lbl 6, y + 14, "SPD", Right$("0" & speed, 2)
    Lbl 76, y + 14, "BPM", CStr(tempo)
    Lbl 130, y + 14, "OCT", CStr(oct)
    Lbl 6, y + 25, "SMP", Hex2(smp) & " " & Left$(SampleText(smp), 22)
    Flag 6, y + 38, "EDIT", editOn, cWarn
    Flag 48, y + 38, "FOLLOW", followOn, cGood
    Select Case mode
        Case 1: Flag 102, y + 38, "SONG", True, cGood
        Case 2: Flag 102, y + 38, "PATTERN", True, cGood
        Case Else: Flag 102, y + 38, "STOPPED", False, cGood
    End Select
    cv.DrawText 168, y + 38, nch & "CH", cLabel
End Sub

Private Sub Lbl(ByVal x As Long, ByVal y As Long, ByVal l As String, ByVal v As String)
    cv.DrawText x, y, l, cLabel
    cv.DrawText x + 24, y, v, cText
End Sub

Private Sub Flag(ByVal x As Long, ByVal y As Long, ByVal t As String, ByVal onOff As Boolean, ByVal col As Long)
    Dim w As Long
    w = cv.TextWidth(t) + 6
    If onOff Then
        cv.Box x, y - 1, w, 11, col
        cv.DrawText x + 3, y, t, cBg
    Else
        cv.Rect x, y - 1, w, 11, cLine
        cv.DrawText x + 3, y, t, cDim
    End If
End Sub

' scopes and VU meters, one box per channel
Public Sub DrawScopes()
    Dim c As Long, x0 As Long, w As Long, i As Long, y0 As Long, h As Long, vu As Long, col As Long
    Dim vh As Long
    x0 = 230
    w = (scrW - x0 - 4) \ nch
    y0 = SY0
    h = SH
    cv.Box x0, y0, scrW - x0, h, cBg
    For c = 0 To nch - 1
        cv.Rect x0 + c * w, y0, w - 4, h, cLine
        ScopeData c, scY, SCN
        For i = 0 To SCN - 1
            scX(i) = x0 + c * w + 2 + (i * (w - 12)) \ SCN
            scY(i) = y0 + h \ 2 + (scY(i) * (h - 6)) \ 256
        Next i
        If ChanMuted(c) Then col = cMute Else col = cWave
        cv.PSetMany scX, scY, col, SCN
        vu = ChanVU(c)
        vh = (vu * (h - 4)) \ 64
        If vh > 0 Then
            If vu > 56 Then col = cWarn Else If vu > 40 Then col = cCursor Else col = cGood
            cv.Box x0 + c * w + w - 10, y0 + h - 2 - vh, 4, vh, col
        End If
        cv.DrawText x0 + c * w + 3, y0 + 2, CStr(c + 1), cDim
    Next c
End Sub

' ---------------------------------------------------------------- side panel: orders and samples

Public Function SideX() As Long
    SideX = PatWidth() + 6
End Function

Public Function SideVisible() As Boolean
    SideVisible = scrW - SideX() >= 150
End Function

Public Sub DrawSide(ByVal curPos As Long, ByVal playPos As Long, ByVal curSmp As Long, ByVal focus As Long)
    Dim x As Long, w As Long, i As Long, y As Long, first As Long, s As String, col As Long, ow As Long
    If Not SideVisible() Then Exit Sub
    x = SideX()
    w = scrW - x
    If sideDirty Then
        cv.SetTarget sideImg
        cv.Cls
        ' order list: 38 lines around the current position
        ow = 64
        cv.Box 0, 0, ow, PH, cPanel
        cv.DrawText 4, 2, "ORDER", cLabel
        first = curPos - 17: If first < 0 Then first = 0
        For i = first To first + 35
            If i >= songLen Then Exit For
            y = 14 + (i - first) * RH
            If i = curPos Then cv.Box 0, y - 1, ow, RH, IIf(focus = 1, cCursor, cCurRow)
            If i = playPos Then cv.Box 0, y - 1, 3, RH, cGood
            If i = curPos And focus = 1 Then col = cBg Else col = cText
            cv.DrawText 6, y, Right$("00" & i, 3) & " " & Right$("0" & orders(i), 2), col
        Next i
        ' sample list
        cv.Box ow + 4, 0, w - ow - 4, PH, cPanel
        cv.DrawText ow + 8, 2, "SAMPLES", cLabel
        For i = 1 To NSMP
            y = 14 + (i - 1) * 11
            If i = curSmp Then cv.Box ow + 4, y - 1, w - ow - 4, 11, IIf(focus = 2, cCursor, cCurRow)
            If i = curSmp And focus = 2 Then col = cBg Else col = cText
            s = SampleText(i)
            If smpLen(i) = 0 And Len(s) = 0 Then
                cv.DrawText ow + 8, y, Hex2(i), cDim
            Else
                cv.DrawText ow + 8, y, Hex2(i), IIf(col = cBg, cBg, cSmpC)
                cv.DrawText ow + 26, y, Left$(s, (w - ow - 30) \ 6), col
            End If
        Next i
        cv.SetTarget 0
        sideDirty = False
    End If
    cv.DrawImagePart sideImg, 0, 0, w, PH, x, PY0, True
End Sub

' ---------------------------------------------------------------- status line

Public Sub DrawStatus(ByVal msg As String, ByVal hint As String)
    cv.Box 0, scrH - 14, scrW, 14, cPanel
    cv.DrawText 6, scrH - 11, msg, cText
    If cv.TextWidth(msg) + cv.TextWidth(hint) + 24 <= scrW Then
        cv.DrawText scrW - cv.TextWidth(hint) - 6, scrH - 11, hint, cLabel
    End If
End Sub

' ---------------------------------------------------------------- sample view

' the sample editor: waveform with loop, the parameters, the sample list
Public Sub DrawSampleView(ByVal smp As Long, ByVal field As Long, ByVal zoomStart As Long, ByVal zoomLen As Long, _
                          ByVal playPos As Long)
    Dim x0 As Long, y0 As Long, w As Long, h As Long, i As Long, mid As Long
    Dim xs() As Long, d As Variant, n As Long, a As Long, b As Long, v As Long, j As Long, lo As Long, hi As Long
    Dim lx As Long, labels As Variant, vals(0 To 5) As String
    cv.Box 0, PY0 - 12, scrW, PH + 12, cBg
    x0 = 6: y0 = PY0 + 4: w = scrW - 12: h = 220
    cv.Box x0, y0, w, h, cPanel
    mid = y0 + h \ 2
    cv.Line x0, mid, x0 + w - 1, mid, cLine
    cv.DrawText x0 + 4, y0 + 3, "SAMPLE " & Hex2(smp) & "  " & SampleText(smp), cTitle
    n = smpLen(smp)
    If n > 0 Then
        If zoomLen <= 0 Or zoomStart + zoomLen > n Then zoomStart = 0: zoomLen = n
        d = smpData(smp)
        ' one vertical line per column from min to max of the samples it covers
        For i = 0 To w - 1
            a = zoomStart + (i * zoomLen) \ w
            b = zoomStart + ((i + 1) * zoomLen) \ w - 1
            If b < a Then b = a
            If b > n - 1 Then b = n - 1
            lo = 127: hi = -128
            ' long columns: sample a few points (keeps a 128 KB sample quick in the VM)
            Dim stp As Long
            stp = (b - a) \ 16 + 1
            For j = a To b Step stp
                v = d(j): If v > 127 Then v = v - 256
                If v < lo Then lo = v
                If v > hi Then hi = v
            Next j
            cv.Line x0 + i, mid - (hi * (h - 20)) \ 256, x0 + i, mid - (lo * (h - 20)) \ 256, cWave
        Next i
        ' loop
        If smpLoopL(smp) > 2 Then
            lx = x0 + ((smpLoopS(smp) - zoomStart) * w) \ zoomLen
            If lx >= x0 And lx < x0 + w Then cv.Line lx, y0, lx, y0 + h - 1, cLoop
            lx = x0 + ((smpLoopS(smp) + smpLoopL(smp) - zoomStart) * w) \ zoomLen
            If lx >= x0 And lx <= x0 + w Then cv.Line lx - 1, y0, lx - 1, y0 + h - 1, cLoop
        End If
        If playPos >= 0 Then
            lx = x0 + ((playPos - zoomStart) * w) \ zoomLen
            If lx >= x0 And lx < x0 + w Then cv.Line lx, y0, lx, y0 + h - 1, cGood
        End If
        cv.DrawText x0 + 4, y0 + h - 12, "view " & zoomStart & " - " & (zoomStart + zoomLen) & " of " & n, cLabel
    Else
        cv.DrawText x0 + w \ 2 - 60, mid - 4, "(empty - L loads a sample)", cDim
    End If
    ' parameters
    labels = Array("NAME", "VOLUME", "FINETUNE", "LOOP START", "LOOP LENGTH", "LENGTH")
    vals(0) = SampleText(smp)
    vals(1) = CStr(smpVol(smp))
    vals(2) = CStr(FineSigned(smp))
    vals(3) = CStr(smpLoopS(smp))
    If smpLoopL(smp) <= 2 Then vals(4) = "no loop" Else vals(4) = CStr(smpLoopL(smp))
    vals(5) = CStr(n) & " bytes"
    For i = 0 To 5
        y0 = PY0 + 236 + i * 13
        If i = field Then cv.Box 4, y0 - 2, 260, 12, cCurRow
        cv.DrawText 8, y0, labels(i), cLabel
        cv.DrawText 90, y0, vals(i), IIf(i = field, cTitle, cText)
    Next i
    cv.DrawText 290, PY0 + 236, "Up/Down choose, Left/Right change (Shift: x16)", cLabel
    cv.DrawText 290, PY0 + 249, "Return edit name, piano keys play the sample", cLabel
    cv.DrawText 290, PY0 + 262, "L load  W save  +/- zoom  Shift+Left/Right scroll", cLabel
    cv.DrawText 290, PY0 + 275, "R reverse  N normalise  X cut to loop  Del clear", cLabel
    cv.DrawText 290, PY0 + 288, "F3/F4 previous/next sample", cLabel
End Sub

' ---------------------------------------------------------------- song view

Public Sub DrawSongView(ByVal field As Long, ByVal curPos As Long, ByVal playPos As Long)
    Dim i As Long, x As Long, y As Long, labels As Variant, vals(0 To 4) As String, col As Long
    cv.Box 0, PY0 - 12, scrW, PH + 12, cBg
    cv.DrawText 8, PY0 - 6, "SONG", cTitle
    labels = Array("TITLE", "SPEED", "TEMPO (BPM)", "LENGTH", "RESTART")
    vals(0) = TitleText()
    vals(1) = CStr(initSpeed)
    vals(2) = CStr(initTempo)
    vals(3) = CStr(songLen)
    If songRestart >= songLen Then vals(4) = "none (" & songRestart & ")" Else vals(4) = CStr(songRestart)
    For i = 0 To 4
        y = PY0 + 12 + i * 14
        If i = field Then cv.Box 4, y - 2, 300, 12, cCurRow
        cv.DrawText 8, y, labels(i), cLabel
        cv.DrawText 100, y, vals(i), IIf(i = field, cTitle, cText)
    Next i
    cv.DrawText 8, PY0 + 90, "Format " & songTag & ", " & nch & " channels, " & nPat & " patterns, " & ModSize() & " bytes", cLabel
    ' the order list as a grid of 128 positions
    cv.DrawText 8, PY0 + 112, "ORDER LIST  (cursor keys, 0-9 type a pattern, Ins/Del insert/delete)", cLabel
    For i = 0 To 127
        x = 8 + (i Mod 16) * 38
        y = PY0 + 128 + (i \ 16) * 16
        If i < songLen Then col = cText Else col = cDim
        If i = curPos Then
            cv.Box x - 2, y - 3, 34, 14, IIf(field = 5, cCursor, cCurRow)
            If field = 5 Then col = cBg
        End If
        If i = playPos Then cv.Box x - 2, y + 10, 34, 2, cGood
        cv.DrawText x, y, Right$("0" & orders(i), 2), col
    Next i
    cv.DrawText 8, PY0 + 266, "Up/Down choose a setting, Left/Right change it, Return edits the title", cLabel
End Sub
