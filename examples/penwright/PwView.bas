' Penwright - the document view: lays the paragraphs out into lines (word wrap,
' alignment, indents per paragraph style), draws them onto a Canvas as a page on a desk,
' and keeps the cursor and selection. Works with any object with the Canvas methods, so
' the tests draw it off-screen.
'
' Text measuring goes through TW/LineH: with a canvas that has fonts (FontSize property)
' every run is set in its size; otherwise all text uses the canvas's fixed font.
Option Explicit

Public vw As Long, vh As Long             ' picture size
Public scrollY As Long                     ' pixels of the document above the view
Public curP As Long, curO As Long          ' cursor
Public ancP As Long, ancO As Long          ' selection anchor (= cursor when nothing is selected)
Public wantX As Long                       ' the x Up/Down try to keep, -1 = use the cursor's
Public CaretOn As Boolean
Public LiveSpell As Boolean
Public HasFonts As Boolean
Public PageW As Long                       ' page width in pixels (text width + margins)
Public Const MARGIN As Long = 36
Public Const TOPPAD As Long = 24
Public DrawCount As Long
Public ShowMarks As Boolean                ' show paragraph ends
Public SpellHoldP As Long                  ' the paragraph being typed in: its spelling marks wait (-1 none)
Public SpellLazy As Boolean                ' draw without checking; SpellCatchUp checks later (the form's timer)

Private ph() As Long                       ' paragraph heights (-1 = not laid out)
Private spellOk() As Boolean               ' spell marks of the paragraph are valid
Private spellMarks() As String             ' "offset:len," of misspelt words
Private cv0 As Object                      ' the canvas used for measuring
Private fixW As Long, fixH As Long

' lines of the paragraph last wrapped (WrapPara)
Private lnN As Long
Private lnS(0 To 1023) As Long, lnE(0 To 1023) As Long, lnW(0 To 1023) As Long, lnH(0 To 1023) As Long

Public colDesk As Long, colPage As Long, colSel As Long, colCaret As Long, colMark As Long

Public Sub ViewInit(cv As Object, ByVal w As Long, ByVal h As Long)
    Set cv0 = cv
    vw = w: vh = h
    fixW = cv.TextWidth("M"): fixH = cv.TextHeight("M")
    If fixW < 1 Then fixW = 6
    If fixH < 1 Then fixH = 9
    HasFonts = False
    On Error Resume Next
    cv.FontSize = 12
    If Err.Number = 0 Then HasFonts = True
    On Error GoTo 0
    PageW = w - 40
    If PageW > 640 Then PageW = 640
    scrollY = 0: curP = 0: curO = 0: ancP = 0: ancO = 0: wantX = -1
    SpellHoldP = -1
    CaretOn = True
    colDesk = RGB(148, 154, 168)
    colPage = RGB(255, 255, 255)
    colSel = RGB(190, 212, 250)
    colCaret = RGB(20, 60, 160)
    colMark = RGB(170, 170, 200)
    ReDim ph(0 To 0): ReDim spellOk(0 To 0): ReDim spellMarks(0 To 0)
    NoteAll
    SyncLayout
End Sub

Public Sub ViewResize(ByVal w As Long, ByVal h As Long)
    vw = w: vh = h
    PageW = w - 40
    If PageW > 640 Then PageW = 640
    NoteAll
    SyncLayout
End Sub

' ---- measuring -------------------------------------------------------------------------

Private Sub SetFont(cv As Object, ByVal attr As Long, ByVal size As Long)
    If Not HasFonts Then Exit Sub
    cv.FontSize = size
    cv.FontBold = (attr And A_BOLD) <> 0
    cv.FontItalic = (attr And A_ITALIC) <> 0
End Sub

Private Function TW(ByVal s As String, ByVal attr As Long, ByVal size As Long) As Long
    If HasFonts Then
        SetFont cv0, attr, size
        TW = cv0.TextWidth(s)
    Else
        TW = Len(s) * fixW
    End If
End Function

Private Function LineH(ByVal size As Long) As Long
    If HasFonts Then
        cv0.FontSize = size
        LineH = cv0.TextHeight("Mg") + size \ 4
    Else
        LineH = fixH + 7
    End If
End Function

Private Function StyleIndentL(ByVal st As Long) As Long
    Select Case st
    Case PS_QUOTE: StyleIndentL = 28
    Case PS_BULLET: StyleIndentL = 20
    Case PS_CODE: StyleIndentL = 8
    End Select
End Function

Private Function StyleIndentR(ByVal st As Long) As Long
    Select Case st
    Case PS_QUOTE: StyleIndentR = 28
    Case PS_CODE: StyleIndentR = 8
    End Select
End Function

Private Function SpaceBefore(ByVal st As Long) As Long
    Select Case st
    Case PS_H1: SpaceBefore = 14
    Case PS_H2: SpaceBefore = 10
    Case PS_H3: SpaceBefore = 8
    Case PS_CODE, PS_BULLET: SpaceBefore = 0
    Case Else: SpaceBefore = 2
    End Select
End Function

Private Function SpaceAfter(ByVal st As Long) As Long
    Select Case st
    Case PS_BULLET, PS_CODE: SpaceAfter = 1
    Case Else: SpaceAfter = 6
    End Select
End Function

Public Function TextWidthPx() As Long
    TextWidthPx = PageW - 2 * MARGIN
End Function

' width of characters [a, b) of paragraph p (b exclusive, 0-based offsets)
Private Function SpanW(ByVal p As Long, ByVal a As Long, ByVal b As Long) As Long
    Dim i As Long, st As Long, w As Long, at As String, sz As String
    If b <= a Then Exit Function
    If Not HasFonts Then SpanW = (b - a) * fixW: Exit Function
    at = pAttr(p): sz = pSize(p)
    st = a
    For i = a + 1 To b
        If i = b Then
            w = w + TW(Mid$(pText(p), st + 1, i - st), Asc(Mid$(at, st + 1, 1)), Asc(Mid$(sz, st + 1, 1)))
        ElseIf Mid$(at, i + 1, 1) <> Mid$(at, st + 1, 1) Or Mid$(sz, i + 1, 1) <> Mid$(sz, st + 1, 1) Then
            w = w + TW(Mid$(pText(p), st + 1, i - st), Asc(Mid$(at, st + 1, 1)), Asc(Mid$(sz, st + 1, 1)))
            st = i
        End If
    Next i
    SpanW = w
End Function

' the tallest size used in [a, b) of paragraph p
Private Function SpanMaxSize(ByVal p As Long, ByVal a As Long, ByVal b As Long) As Long
    Dim i As Long, z As Long, m As Long, sz As String
    m = StyleSize(pStyle(p))
    If Not HasFonts Then SpanMaxSize = m: Exit Function
    If b > a Then m = 0
    sz = pSize(p)
    For i = a + 1 To b
        z = Asc(Mid$(sz, i, 1))
        If z > m Then m = z
    Next i
    SpanMaxSize = m
End Function

' Break paragraph p into lines of at most w pixels: lnS/lnE/lnW/lnH, lnN of them
Private Sub WrapPara(ByVal p As Long, ByVal w As Long)
    Dim s As String, n As Long, a As Long, i As Long, lastSp As Long, cw As Long, x As Long, e As Long
    s = pText(p)
    n = Len(s)
    lnN = 0
    a = 0
    If n = 0 Then
        lnS(0) = 0: lnE(0) = 0: lnW(0) = 0: lnH(0) = LineH(StyleSize(pStyle(p))): lnN = 1
        Exit Sub
    End If
    If pStyle(p) = PS_CODE Then w = 100000      ' code is not wrapped
    Do While a < n
        ' fixed font: jump straight to the break candidate
        If Not HasFonts Then
            e = a + w \ fixW
            If e < a + 1 Then e = a + 1
            If e >= n Then
                e = n
            Else
                lastSp = InStrRev(s, " ", e + 1)
                If lastSp > a Then e = lastSp
            End If
        Else
            x = 0: lastSp = -1: e = n
            For i = a To n - 1
                cw = SpanW(p, i, i + 1)
                If x + cw > w And i > a Then
                    If lastSp > a Then e = lastSp Else e = i
                    Exit For
                End If
                x = x + cw
                If Mid$(s, i + 1, 1) = " " Then lastSp = i + 1
            Next i
        End If
        If lnN > 1023 Then Exit Do
        lnS(lnN) = a: lnE(lnN) = e
        lnW(lnN) = SpanW(p, a, TrimEnd(p, a, e))
        lnH(lnN) = LineH(SpanMaxSize(p, a, e))
        lnN = lnN + 1
        a = e
    Loop
End Sub

' the end of [a, e) without trailing spaces (they don't count for alignment)
Private Function TrimEnd(ByVal p As Long, ByVal a As Long, ByVal e As Long) As Long
    Do While e > a
        If Mid$(pText(p), e, 1) <> " " Then Exit Do
        e = e - 1
    Loop
    TrimEnd = e
End Function

' ---- layout cache ---------------------------------------------------------------------------

' take the document's last changes into the height cache
Public Sub SyncLayout()
    Dim i As Long, d As Long, n As Long
    If EditSeq = 0 And Not EditAll And UBound(ph) + 1 >= NP Then Exit Sub
    If EditAll Or UBound(ph) < 0 Then
        ReDim ph(0 To NP + 63): ReDim spellOk(0 To NP + 63): ReDim spellMarks(0 To NP + 63)
        For i = 0 To UBound(ph): ph(i) = -1: Next i
    Else
        d = EditNewN - EditOldN
        n = NP - d                               ' paragraphs before the change
        If NP + 1 > UBound(ph) Then
            ReDim Preserve ph(0 To NP * 2 + 64): ReDim Preserve spellOk(0 To NP * 2 + 64)
            ReDim Preserve spellMarks(0 To NP * 2 + 64)
        End If
        If d > 0 Then
            For i = n - 1 To EditP + EditOldN Step -1
                ph(i + d) = ph(i): spellOk(i + d) = spellOk(i): spellMarks(i + d) = spellMarks(i)
            Next i
        ElseIf d < 0 Then
            For i = EditP + EditOldN To n - 1
                ph(i + d) = ph(i): spellOk(i + d) = spellOk(i): spellMarks(i + d) = spellMarks(i)
            Next i
        End If
        For i = EditP To EditP + EditNewN - 1
            If i <= UBound(ph) Then ph(i) = -1: spellOk(i) = False
        Next i
    End If
    EditSeen
    If curP >= NP Then curP = NP - 1: curO = Len(pText(curP))
    If ancP >= NP Then ancP = NP - 1: ancO = Len(pText(ancP))
    If curO > Len(pText(curP)) Then curO = Len(pText(curP))
    If ancO > Len(pText(ancP)) Then ancO = Len(pText(ancP))
End Sub

Private Function ParaH(ByVal p As Long) As Long
    Dim i As Long, h As Long
    If ph(p) < 0 Then
        WrapPara p, TextWidthPx() - StyleIndentL(pStyle(p)) - StyleIndentR(pStyle(p))
        h = SpaceBefore(pStyle(p)) + SpaceAfter(pStyle(p))
        For i = 0 To lnN - 1: h = h + lnH(i): Next i
        ph(p) = h
    End If
    ParaH = ph(p)
End Function

Public Function ParaY(ByVal p As Long) As Long
    Dim i As Long, y As Long
    y = TOPPAD
    For i = 0 To p - 1
        y = y + ParaH(i)
    Next i
    ParaY = y
End Function

Public Function DocHeight() As Long
    DocHeight = ParaY(NP) + TOPPAD
End Function

' ---- positions -------------------------------------------------------------------------------

Private Function PageX() As Long
    PageX = (vw - PageW) \ 2
    If PageX < 0 Then PageX = 0
End Function

' x of the start of line k (in lnS/lnE) of paragraph p; extra = justify gap per space
Private Function LineX(ByVal p As Long, ByVal k As Long, extra As Double) As Long
    Dim x0 As Long, w As Long, spaces As Long, i As Long, e As Long
    x0 = PageX() + MARGIN + StyleIndentL(pStyle(p))
    w = TextWidthPx() - StyleIndentL(pStyle(p)) - StyleIndentR(pStyle(p))
    extra = 0
    Select Case pAlign(p)
    Case AL_CENTER: LineX = x0 + (w - lnW(k)) \ 2
    Case AL_RIGHT: LineX = x0 + w - lnW(k)
    Case AL_JUSTIFY
        LineX = x0
        If k < lnN - 1 Then
            e = TrimEnd(p, lnS(k), lnE(k))
            For i = lnS(k) + 1 To e
                If Mid$(pText(p), i, 1) = " " Then spaces = spaces + 1
            Next i
            If spaces > 0 Then extra = (w - lnW(k)) / spaces
        End If
    Case Else: LineX = x0
    End Select
End Function

' x of offset o within line k of paragraph p
Private Function OffsetX(ByVal p As Long, ByVal k As Long, ByVal o As Long) As Long
    Dim extra As Double, x As Long, i As Long, sp As Long
    x = LineX(p, k, extra)
    If extra > 0 Then
        For i = lnS(k) + 1 To o
            If Mid$(pText(p), i, 1) = " " Then sp = sp + 1
        Next i
    End If
    OffsetX = x + SpanW(p, lnS(k), o) + CLng(sp * extra)
End Function

' the line of paragraph p holding offset o (WrapPara must have run for p)
Private Function LineOf(ByVal p As Long, ByVal o As Long) As Long
    Dim k As Long
    For k = 0 To lnN - 1
        If o < lnE(k) Or k = lnN - 1 Then LineOf = k: Exit Function
        ' at a soft break the cursor belongs to the next line
    Next k
End Function

' the offset in line k of p nearest to x
Private Function OffsetAtX(ByVal p As Long, ByVal k As Long, ByVal x As Long) As Long
    Dim o As Long, best As Long, bd As Long, d As Long, e As Long
    e = lnE(k)
    If k < lnN - 1 Then e = e - 1          ' not after the break space
    If e < lnS(k) Then e = lnS(k)
    best = lnS(k): bd = 1000000
    For o = lnS(k) To e
        d = Abs(OffsetX(p, k, o) - x)
        If d < bd Then bd = d: best = o
    Next o
    OffsetAtX = best
End Function

' cursor position on screen: x, the line's top y and height
Public Sub CaretPos(x As Long, y As Long, h As Long)
    Dim k As Long, i As Long
    y = ParaY(curP) - scrollY + SpaceBefore(pStyle(curP))
    WrapPara curP, TextWidthPx() - StyleIndentL(pStyle(curP)) - StyleIndentR(pStyle(curP))
    k = LineOf(curP, curO)
    For i = 0 To k - 1: y = y + lnH(i): Next i
    h = lnH(k)
    x = OffsetX(curP, k, curO)
End Sub

' the document position at screen (x, y)
Public Sub PosAt(ByVal x As Long, ByVal y As Long, p As Long, o As Long)
    Dim yy As Long, k As Long, h As Long
    yy = y + scrollY
    p = 0
    Dim top As Long
    top = TOPPAD
    Do While p < NP - 1
        If yy < top + ParaH(p) Then Exit Do
        top = top + ParaH(p)
        p = p + 1
    Loop
    WrapPara p, TextWidthPx() - StyleIndentL(pStyle(p)) - StyleIndentR(pStyle(p))
    top = top + SpaceBefore(pStyle(p))
    For k = 0 To lnN - 2
        If yy < top + lnH(k) Then Exit For
        top = top + lnH(k)
    Next k
    o = OffsetAtX(p, k, x)
End Sub

Public Sub EnsureCaretVisible()
    Dim x As Long, y As Long, h As Long
    CaretPos x, y, h
    If y < 4 Then scrollY = scrollY + y - 4
    If y + h > vh - 4 Then scrollY = scrollY + (y + h) - (vh - 4)
    If scrollY < 0 Then scrollY = 0
End Sub

Public Function HasSelection() As Boolean
    HasSelection = (curP <> ancP Or curO <> ancO)
End Function

Public Sub SelRange(p1 As Long, o1 As Long, p2 As Long, o2 As Long)
    p1 = ancP: o1 = ancO: p2 = curP: o2 = curO
    OrderPos p1, o1, p2, o2
End Sub

Public Sub SetCursor(ByVal p As Long, ByVal o As Long, ByVal extend As Boolean)
    If p < 0 Then p = 0: o = 0
    If p >= NP Then p = NP - 1: o = Len(pText(p))
    If o < 0 Then o = 0
    If o > Len(pText(p)) Then o = Len(pText(p))
    curP = p: curO = o
    If Not extend Then ancP = p: ancO = o
    CaretOn = True
End Sub

' cursor movement by keys: dir = "L" "R" "U" "D" "HOME" "END" "PGUP" "PGDN" "WL" "WR" "TOP" "BOT"
Public Sub MoveCaret(ByVal dir As String, ByVal extend As Boolean)
    Dim x As Long, y As Long, h As Long, k As Long, p As Long, o As Long, keepX As Boolean
    Select Case dir
    Case "L"
        If HasSelection() And Not extend Then
            SelRange p, o, k, h: SetCursor p, o, False
        ElseIf curO > 0 Then
            SetCursor curP, curO - 1, extend
        ElseIf curP > 0 Then
            SetCursor curP - 1, Len(pText(curP - 1)), extend
        End If
    Case "R"
        If HasSelection() And Not extend Then
            SelRange k, h, p, o: SetCursor p, o, False
        ElseIf curO < Len(pText(curP)) Then
            SetCursor curP, curO + 1, extend
        ElseIf curP < NP - 1 Then
            SetCursor curP + 1, 0, extend
        End If
    Case "WL"
        If curO = 0 And curP > 0 Then
            SetCursor curP - 1, Len(pText(curP - 1)), extend
        Else
            SetCursor curP, PrevWordStart(curP, curO), extend
        End If
    Case "WR"
        If curO >= Len(pText(curP)) And curP < NP - 1 Then
            SetCursor curP + 1, 0, extend
        Else
            SetCursor curP, NextWordStart(curP, curO), extend
        End If
    Case "U", "D", "PGUP", "PGDN"
        CaretPos x, y, h
        If wantX >= 0 Then x = wantX
        Select Case dir
        Case "U": y = y - 2
        Case "D": y = y + h + 2
        Case "PGUP": y = y - vh + h: scrollY = scrollY - vh + 2 * h
        Case "PGDN": y = y + vh - h: scrollY = scrollY + vh - 2 * h
        End Select
        If scrollY > DocHeight() - vh Then scrollY = DocHeight() - vh
        If scrollY < 0 Then scrollY = 0
        If y + scrollY < TOPPAD Then
            SetCursor 0, 0, extend
        ElseIf y + scrollY >= ParaY(NP) Then
            SetCursor NP - 1, Len(pText(NP - 1)), extend
        Else
            PosAt x, y, p, o
            SetCursor p, o, extend
        End If
        wantX = x
        keepX = True
    Case "HOME", "END"
        WrapPara curP, TextWidthPx() - StyleIndentL(pStyle(curP)) - StyleIndentR(pStyle(curP))
        k = LineOf(curP, curO)
        If dir = "HOME" Then
            SetCursor curP, lnS(k), extend
        ElseIf k < lnN - 1 Then
            SetCursor curP, lnE(k) - 1, extend
        Else
            SetCursor curP, lnE(k), extend
        End If
    Case "TOP": SetCursor 0, 0, extend
    Case "BOT": SetCursor NP - 1, Len(pText(NP - 1)), extend
    End Select
    If Not keepX Then wantX = -1
    EnsureCaretVisible
End Sub

' ---- spelling marks ------------------------------------------------------------------------

Private Function SpellMarksOf(ByVal p As Long) As String
    Dim o As Long, wl As Long, pp As Long, s As String
    If p = SpellHoldP Then SpellMarksOf = "": Exit Function
    If SpellLazy And Not spellOk(p) Then SpellMarksOf = "": Exit Function
    If Not spellOk(p) Then
        s = ""
        If SpellReady And pStyle(p) <> PS_CODE Then
            pp = p: o = 0
            Do
                If Not NextMisspeltIn(pp, o, wl) Then Exit Do
                s = s & o & ":" & wl & ","
                o = o + wl
            Loop
        End If
        spellMarks(p) = s
        spellOk(p) = True
    End If
    SpellMarksOf = spellMarks(p)
End Function

' NextMisspelt limited to one paragraph
Private Function NextMisspeltIn(ByVal p As Long, o As Long, wl As Long) As Boolean
    Dim pp As Long, oo As Long, saveNP As Long
    pp = p: oo = o
    saveNP = NP
    NP = p + 1                       ' stop at the end of this paragraph
    NextMisspeltIn = NextMisspelt(pp, oo, wl)
    NP = saveNP
    If NextMisspeltIn Then o = oo
End Function

' ---- drawing -------------------------------------------------------------------------------

Public Sub DrawDoc(cv As Object)
    Dim p As Long, y As Long, k As Long, x As Long, i As Long, st As Long, py As Long, h As Long
    Dim sp1 As Long, so1 As Long, sp2 As Long, so2 As Long, hasSel As Boolean, a As Long, z As Long
    Dim extra As Double, seg As String, segA As Long, segZ As Long, s As String, colr As Long, baseY As Long
    Dim tx As Long, sw As Long, j As Long, marks As String, mk() As String, mo As Long, ml As Long
    Dim cx As Long, cy As Long, ch As Long, top As Long, x1 As Long, x2 As Long, ty As Long
    DrawCount = DrawCount + 1
    SyncLayout
    cv.Box 0, 0, vw, vh, colDesk
    cv.Box PageX() + 4, 0, PageW, vh, RGB(110, 114, 128)            ' page shadow
    cv.Box PageX(), 0, PageW, vh, colPage
    hasSel = HasSelection()
    SelRange sp1, so1, sp2, so2
    ' find the first visible paragraph
    top = TOPPAD - scrollY
    p = 0
    Do While p < NP
        If top + ParaH(p) >= 0 Then Exit Do
        top = top + ParaH(p)
        p = p + 1
    Loop
    If scrollY < TOPPAD Then cv.Box PageX(), 0, PageW, TOPPAD - scrollY, colPage
    Do While p < NP And top < vh
        st = pStyle(p)
        WrapPara p, TextWidthPx() - StyleIndentL(st) - StyleIndentR(st)
        y = top + SpaceBefore(st)
        If st = PS_CODE Then
            cv.Box PageX() + MARGIN, top, TextWidthPx(), ParaH(p) - 1, RGB(240, 240, 236)
        ElseIf st = PS_QUOTE Then
            cv.Box PageX() + MARGIN + 10, y, 3, ParaH(p) - SpaceBefore(st) - SpaceAfter(st), RGB(150, 160, 190)
        End If
        If HasSpell() Then marks = SpellMarksOf(p) Else marks = ""
        For k = 0 To lnN - 1
            h = lnH(k)
            baseY = y + (h - LineH(SpanMaxSize(p, lnS(k), lnE(k)))) + 2
            x = LineX(p, k, extra)
            If k = 0 And st = PS_BULLET Then
                cv.Circle x - 10, y + h \ 2, 2, RGB(40, 40, 40), True
            End If
            ' selection behind the text
            If hasSel And p >= sp1 And p <= sp2 Then
                Dim a1 As Long, a2 As Long
                If p = sp1 Then a1 = so1 Else a1 = 0
                If p = sp2 Then a2 = so2 Else a2 = Len(pText(p)) + 1
                If a1 < lnS(k) Then a1 = lnS(k)
                If a2 > lnE(k) And k < lnN - 1 Then a2 = lnE(k)
                If a2 > a1 Or (a2 >= a1 And p < sp2 And k = lnN - 1) Then
                    x1 = OffsetX(p, k, a1)
                    If a2 > Len(pText(p)) Then
                        x2 = OffsetX(p, k, Len(pText(p))) + fixW
                    Else
                        x2 = OffsetX(p, k, a2)
                    End If
                    cv.Box x1, y, x2 - x1, h, colSel
                End If
            End If
            ' the runs of the line
            i = lnS(k)
            tx = x
            Do While i < lnE(k)
                a = Asc(Mid$(pAttr(p), i + 1, 1)): z = Asc(Mid$(pSize(p), i + 1, 1))
                j = RunEnd(p, i, lnE(k))
                If extra > 0 Then
                    ' justified: words are drawn one by one, spaces stretched
                    If Mid$(pText(p), i + 1, 1) = " " Then
                        j = i + 1
                    Else
                        Dim sp As Long
                        sp = InStr(i + 1, pText(p), " ")
                        If sp > 0 And sp - 1 < j Then j = sp - 1
                    End If
                End If
                seg = Mid$(pText(p), i + 1, j - i)
                colr = PaletteColor((a And A_COLMASK) \ 16)
                If st = PS_QUOTE And (a And A_COLMASK) = 0 Then colr = RGB(70, 70, 90)
                SetFont cv, a, z
                sw = TW(seg, a, z)
                If HasFonts Then ty = baseY + LineH(SpanMaxSize(p, lnS(k), lnE(k))) - LineH(z) Else ty = baseY
                If seg <> " " Then
                    cv.DrawText tx, ty, seg, colr
                    If (a And A_BOLD) <> 0 And Not HasFonts Then cv.DrawText tx + 1, ty, seg, colr
                    If (a And A_ITALIC) <> 0 And Not HasFonts Then
                        ' the fixed font has no italic: a light dotted line under the run
                        For cx = tx To tx + sw - 1 Step 3
                            cv.PSet cx, ty + fixH + 1, RGB(150, 150, 190)
                        Next cx
                    End If
                End If
                If (a And A_UNDER) <> 0 Then cv.Line tx, ty + fixH + 1, tx + sw - 1, ty + fixH + 1, colr
                If (a And A_STRIKE) <> 0 Then cv.Line tx, ty + fixH \ 2, tx + sw - 1, ty + fixH \ 2, colr
                tx = tx + sw
                If extra > 0 And seg = " " Then tx = tx + CLng(extra)
                i = j
            Loop
            ' spelling squiggles
            If marks <> "" Then
                If k = 0 Then mk = Split(marks, ",")
                For j = 0 To UBound(mk) - 1
                    mo = Val(mk(j)): ml = Val(Mid$(mk(j), InStr(mk(j), ":") + 1))
                    If mo >= lnS(k) And mo < lnE(k) Then
                        x1 = OffsetX(p, k, mo): x2 = OffsetX(p, k, mo + ml)
                        For cx = x1 To x2 - 2 Step 2
                            cv.PSet cx, baseY + fixH + 2 + ((cx \ 2) Mod 2), RGB(220, 0, 0)
                        Next cx
                    End If
                Next j
            End If
            If ShowMarks And k = lnN - 1 Then cv.DrawText tx + 2, baseY, Chr$(182), colMark
            ' the caret
            If p = curP And CaretOn Then
                If curO >= lnS(k) And (curO < lnE(k) Or k = lnN - 1) Then
                    If LineOf(p, curO) = k Then
                        cx = OffsetX(p, k, curO)
                        cv.Box cx - 1, y + 1, 2, h - 2, colCaret
                    End If
                End If
            End If
            y = y + h
        Next k
        top = top + ParaH(p)
        p = p + 1
    Loop
    ' the page ends
    If top < vh And p >= NP Then
        cv.Box PageX(), top + TOPPAD, PageW + 4, vh, colDesk
    End If
End Sub

Private Function HasSpell() As Boolean
    HasSpell = LiveSpell And SpellReady
End Function

' Check the spelling of up to maxParas visible paragraphs that have no marks yet; True if
' any were checked (then the page needs drawing again)
Public Function SpellCatchUp(ByVal maxParas As Long) As Boolean
    Dim p As Long, top As Long, n As Long, lazy As Boolean, m As String
    If Not HasSpell() Then Exit Function
    top = TOPPAD - scrollY
    p = 0
    Do While p < NP
        If top + ParaH(p) >= 0 Then Exit Do
        top = top + ParaH(p)
        p = p + 1
    Loop
    lazy = SpellLazy
    SpellLazy = False
    Do While p < NP And top < vh And n < maxParas
        If Not spellOk(p) And p <> SpellHoldP Then
            m = SpellMarksOf(p)
            n = n + 1
            SpellCatchUp = True
        End If
        top = top + ParaH(p)
        p = p + 1
    Loop
    SpellLazy = lazy
End Function

' after the dictionary changed: recheck every paragraph
Public Sub SpellChanged()
    Dim i As Long
    For i = 0 To UBound(spellOk): spellOk(i) = False: Next i
End Sub
