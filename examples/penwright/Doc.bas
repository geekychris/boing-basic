' Penwright - the document model: paragraphs of styled text.
'
' A document is a list of paragraphs. Each paragraph has its text (pText), one attribute
' byte per character (pAttr, a String of the same length: bold 1, italic 2, underline 4,
' strike 8, colour index << 4 (0..15)), one size per character (pSize, a String of
' Chr$(points)), a paragraph style (body, heading 1-3, quote, bullet, code) and an
' alignment (left, centre, right, justify). Positions are (paragraph, offset) pairs,
' offsets 0..Len. Every edit replaces a contiguous run of paragraphs, so undo keeps the
' old copies of that run (see Undo).
'
' No drawing and no OS calls: the model is tested on the host (tests/apps/penwright).
Option Explicit

Public Const A_BOLD As Long = 1
Public Const A_ITALIC As Long = 2
Public Const A_UNDER As Long = 4
Public Const A_STRIKE As Long = 8
Public Const A_COLMASK As Long = 240     ' colour index 0..15 in bits 4..7

Public Const PS_BODY As Long = 0
Public Const PS_H1 As Long = 1
Public Const PS_H2 As Long = 2
Public Const PS_H3 As Long = 3
Public Const PS_QUOTE As Long = 4
Public Const PS_BULLET As Long = 5
Public Const PS_CODE As Long = 6
Public Const PS_LAST As Long = 6

Public Const AL_LEFT As Long = 0
Public Const AL_CENTER As Long = 1
Public Const AL_RIGHT As Long = 2
Public Const AL_JUSTIFY As Long = 3

Public NP As Long                       ' paragraphs in use
Public pText() As String
Public pAttr() As String
Public pSize() As String
Public pStyle() As Long
Public pAlign() As Long
Public DocModified As Boolean
Public DefaultSize As Long              ' points of new body text
Public DocTitle As String
Public DocAuthor As String

' undo: each step replaces paragraphs [uP, uP + uNewN) with the saved old ones
Private Const UMAX As Long = 400
Private uP(0 To 399) As Long
Private uOldN(0 To 399) As Long
Private uNewN(0 To 399) As Long
Private uOld(0 To 399) As String        ' the old paragraphs, serialized
Private uNew(0 To 399) As String        ' the new ones (for redo)
Private uCurP(0 To 399) As Long, uCurO(0 To 399) As Long   ' the cursor before the edit
Private uCurP2(0 To 399) As Long, uCurO2(0 To 399) As Long ' and after it
Private uKind(0 To 399) As Long         ' 1 = typing (merges with the next typing step)
Private uBase As Long                   ' oldest step (ring)
Private uCount As Long                  ' steps that can be undone
Private uRedo As Long                   ' steps above that can be redone
Private pendP As Long, pendN As Long, pendOld As String, pendCP As Long, pendCO As Long, pendKind As Long
Public UndoCursorP As Long, UndoCursorO As Long   ' where Undo/Redo leave the cursor

' ---- creating ------------------------------------------------------------------------

Public Sub NewDoc()
    ReDim pText(0 To 63): ReDim pAttr(0 To 63): ReDim pSize(0 To 63)
    ReDim pStyle(0 To 63): ReDim pAlign(0 To 63)
    If DefaultSize = 0 Then DefaultSize = 12
    NP = 1
    pText(0) = "": pAttr(0) = "": pSize(0) = ""
    pStyle(0) = PS_BODY: pAlign(0) = AL_LEFT
    DocModified = False
    DocTitle = "": DocAuthor = ""
    uCount = 0: uRedo = 0: uBase = 0
End Sub

Private Sub EnsureCap(ByVal n As Long)
    Dim m As Long
    If n - 1 <= UBound(pText) Then Exit Sub
    m = UBound(pText) + 1
    Do While m < n: m = m * 2: Loop
    ReDim Preserve pText(0 To m - 1): ReDim Preserve pAttr(0 To m - 1): ReDim Preserve pSize(0 To m - 1)
    ReDim Preserve pStyle(0 To m - 1): ReDim Preserve pAlign(0 To m - 1)
End Sub

' the size new text gets in a paragraph style
Public Function StyleSize(ByVal st As Long) As Long
    Select Case st
    Case PS_H1: StyleSize = DefaultSize * 2
    Case PS_H2: StyleSize = (DefaultSize * 3) \ 2
    Case PS_H3: StyleSize = (DefaultSize * 5) \ 4
    Case Else: StyleSize = DefaultSize
    End Select
End Function

Public Function StyleName(ByVal st As Long) As String
    Select Case st
    Case PS_BODY: StyleName = "Body"
    Case PS_H1: StyleName = "Heading 1"
    Case PS_H2: StyleName = "Heading 2"
    Case PS_H3: StyleName = "Heading 3"
    Case PS_QUOTE: StyleName = "Quote"
    Case PS_BULLET: StyleName = "Bullet"
    Case PS_CODE: StyleName = "Code"
    End Select
End Function

' ---- reading ---------------------------------------------------------------------------

Public Function ParaLen(ByVal p As Long) As Long
    ParaLen = Len(pText(p))
End Function

Public Function AttrAt(ByVal p As Long, ByVal o As Long) As Long
    ' attribute of the character at offset o (0-based)
    If o < Len(pAttr(p)) Then AttrAt = Asc(Mid$(pAttr(p), o + 1, 1))
End Function

Public Function SizeAt(ByVal p As Long, ByVal o As Long) As Long
    If o < Len(pSize(p)) Then SizeAt = Asc(Mid$(pSize(p), o + 1, 1)) Else SizeAt = StyleSize(pStyle(p))
End Function

' the attributes typing at (p, o) gets: those of the character before, else after
Public Function AttrForTyping(ByVal p As Long, ByVal o As Long) As Long
    If o > 0 Then
        AttrForTyping = AttrAt(p, o - 1)
    ElseIf Len(pAttr(p)) > 0 Then
        AttrForTyping = AttrAt(p, 0)
    End If
End Function

Public Function SizeForTyping(ByVal p As Long, ByVal o As Long) As Long
    If o > 0 And o <= Len(pSize(p)) Then
        SizeForTyping = Asc(Mid$(pSize(p), o, 1))
    ElseIf Len(pSize(p)) > 0 Then
        SizeForTyping = Asc(Left$(pSize(p), 1))
    Else
        SizeForTyping = StyleSize(pStyle(p))
    End If
End Function

' order two positions
Public Sub OrderPos(p1 As Long, o1 As Long, p2 As Long, o2 As Long)
    Dim t As Long
    If p2 < p1 Or (p2 = p1 And o2 < o1) Then
        t = p1: p1 = p2: p2 = t
        t = o1: o1 = o2: o2 = t
    End If
End Sub

' plain text of a range (paragraphs separated by vbLf)
Public Function GetText(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long) As String
    Dim p As Long, s As String
    OrderPos p1, o1, p2, o2
    If p1 = p2 Then GetText = Mid$(pText(p1), o1 + 1, o2 - o1): Exit Function
    s = Mid$(pText(p1), o1 + 1)
    For p = p1 + 1 To p2 - 1
        s = s & vbLf & pText(p)
    Next p
    GetText = s & vbLf & Left$(pText(p2), o2)
End Function

Public Function AllText() As String
    AllText = GetText(0, 0, NP - 1, Len(pText(NP - 1)))
End Function

' ---- undo bookkeeping ------------------------------------------------------------------

' paragraph p as one line: style, align, text, attrs, sizes (all escaped)
Public Function ParaToLine(ByVal p As Long) As String
    ParaToLine = pStyle(p) & vbTab & pAlign(p) & vbTab & Esc(pText(p)) & vbTab & RunsOf(p)
End Function

' Load paragraph p from a ParaToLine line
Public Sub ParaFromLine(ByVal p As Long, ByVal l As String)
    Dim f() As String
    f = Split(l, vbTab)
    pStyle(p) = Val(f(0))
    If pStyle(p) < 0 Or pStyle(p) > PS_LAST Then pStyle(p) = PS_BODY
    pAlign(p) = Val(f(1)) And 3
    pText(p) = Unesc(f(2))
    If UBound(f) >= 3 Then RunsInto p, f(3) Else RunsInto p, ""
End Sub

' the attribute and size runs of a paragraph: "len:attr:size,len:attr:size"
Public Function RunsOf(ByVal p As Long) As String
    Dim i As Long, n As Long, a As String, z As String, st As Long, s As String
    n = Len(pText(p))
    If n = 0 Then Exit Function
    st = 1
    For i = 2 To n + 1
        If i > n Then
            a = "": z = ""
        Else
            a = Mid$(pAttr(p), i, 1): z = Mid$(pSize(p), i, 1)
        End If
        If i > n Or a <> Mid$(pAttr(p), st, 1) Or z <> Mid$(pSize(p), st, 1) Then
            If s <> "" Then s = s & ","
            s = s & (i - st) & ":" & Asc(Mid$(pAttr(p), st, 1)) & ":" & Asc(Mid$(pSize(p), st, 1))
            st = i
        End If
    Next i
    RunsOf = s
End Function

Public Sub RunsInto(ByVal p As Long, ByVal runs As String)
    Dim parts() As String, i As Long, f() As String, n As Long, a As String, z As String, k As Long
    n = Len(pText(p))
    a = "": z = ""
    If runs <> "" Then
        parts = Split(runs, ",")
        For i = 0 To UBound(parts)
            f = Split(parts(i), ":")
            If UBound(f) >= 2 Then
                k = Val(f(0))
                a = a & String$(k, Chr$(Val(f(1)) And 255))
                z = z & String$(k, Chr$(ClampSize(Val(f(2)))))
            End If
        Next i
    End If
    If Len(a) < n Then
        k = n - Len(a)
        a = a & String$(k, Chr$(0))
        z = z & String$(k, Chr$(StyleSize(pStyle(p))))
    End If
    pAttr(p) = Left$(a, n)
    pSize(p) = Left$(z, n)
End Sub

Public Function ClampSize(ByVal z As Long) As Long
    If z < 6 Then z = 6
    If z > 96 Then z = 96
    ClampSize = z
End Function

Public Function Esc(ByVal s As String) As String
    s = Replace(s, "\", "\\")
    s = Replace(s, vbTab, "\t")
    s = Replace(s, vbLf, "\n")
    Esc = Replace(s, vbCr, "\r")
End Function

Public Function Unesc(ByVal s As String) As String
    Dim i As Long, p As Long, res As String, ch As String
    If InStr(s, "\") = 0 Then Unesc = s: Exit Function
    i = 1
    Do
        p = InStr(i, s, "\")
        If p = 0 Or p = Len(s) Then res = res & Mid$(s, i): Exit Do
        res = res & Mid$(s, i, p - i)
        ch = Mid$(s, p + 1, 1)
        Select Case ch
        Case "t": res = res & vbTab
        Case "n": res = res & vbLf
        Case "r": res = res & vbCr
        Case Else: res = res & ch
        End Select
        i = p + 2
    Loop
    Unesc = res
End Function

Private Function SaveParas(ByVal p As Long, ByVal n As Long) As String
    Dim i As Long, s As String
    For i = p To p + n - 1
        If i > p Then s = s & vbLf
        s = s & ParaToLine(i)
    Next i
    SaveParas = s
End Function

' Before changing paragraphs [p, p + n): remember them. kind 1 = typing.
Public Sub BeginEdit(ByVal p As Long, ByVal n As Long, ByVal curP As Long, ByVal curO As Long, ByVal kind As Long)
    pendP = p: pendN = n: pendOld = SaveParas(p, n)
    pendCP = curP: pendCO = curO: pendKind = kind
End Sub

' After the change: the run is now newN paragraphs long; the cursor ends at (curP, curO)
Public Sub EndEdit(ByVal newN As Long, ByVal curP As Long, ByVal curO As Long)
    Dim k As Long, prev As Long
    DocModified = True
    ' typing in the same paragraph merges with the previous typing step
    If pendKind = 1 And uCount > 0 And uRedo = 0 Then
        prev = (uBase + uCount - 1) Mod UMAX
        If uKind(prev) = 1 And uP(prev) = pendP And uNewN(prev) = 1 And pendN = 1 And newN = 1 Then
            uNew(prev) = SaveParas(pendP, 1)
            uCurP2(prev) = curP: uCurO2(prev) = curO
            Exit Sub
        End If
    End If
    If uCount = UMAX Then uBase = (uBase + 1) Mod UMAX: uCount = uCount - 1
    k = (uBase + uCount) Mod UMAX
    uP(k) = pendP: uOldN(k) = pendN: uNewN(k) = newN
    uOld(k) = pendOld: uNew(k) = SaveParas(pendP, newN)
    uCurP(k) = pendCP: uCurO(k) = pendCO: uCurP2(k) = curP: uCurO2(k) = curO
    uKind(k) = pendKind
    uCount = uCount + 1
    uRedo = 0
End Sub

' end a run of typing (the next typing starts a new undo step)
Public Sub BreakTyping()
    If uCount > 0 Then uKind((uBase + uCount - 1) Mod UMAX) = 0
End Sub

Public Function CanUndo() As Boolean
    CanUndo = uCount > 0
End Function

Public Function CanRedo() As Boolean
    CanRedo = uRedo > 0
End Function

' replace paragraphs [p, p + n) with the ones in text (lines)
Private Sub ReplaceParas(ByVal p As Long, ByVal n As Long, ByVal text As String)
    Dim lines() As String, m As Long, i As Long
    lines = Split(text, vbLf)
    m = UBound(lines) + 1
    ShiftParas p + n, m - n
    For i = 0 To m - 1
        ParaFromLine p + i, lines(i)
    Next i
End Sub

' move paragraphs from index `from` to the end by d (d > 0 opens a gap, d < 0 closes one)
Private Sub ShiftParas(ByVal from As Long, ByVal d As Long)
    Dim i As Long
    If d = 0 Then Exit Sub
    EnsureCap NP + d
    If d > 0 Then
        For i = NP - 1 To from Step -1
            pText(i + d) = pText(i): pAttr(i + d) = pAttr(i): pSize(i + d) = pSize(i)
            pStyle(i + d) = pStyle(i): pAlign(i + d) = pAlign(i)
        Next i
    Else
        For i = from To NP - 1
            pText(i + d) = pText(i): pAttr(i + d) = pAttr(i): pSize(i + d) = pSize(i)
            pStyle(i + d) = pStyle(i): pAlign(i + d) = pAlign(i)
        Next i
        For i = NP + d To NP - 1
            pText(i) = "": pAttr(i) = "": pSize(i) = ""
        Next i
    End If
    NP = NP + d
End Sub

Public Sub Undo()
    Dim k As Long
    If uCount = 0 Then Exit Sub
    k = (uBase + uCount - 1) Mod UMAX
    ReplaceParas uP(k), uNewN(k), uOld(k)
    UndoCursorP = uCurP(k): UndoCursorO = uCurO(k)
    uCount = uCount - 1
    uRedo = uRedo + 1
    DocModified = True
End Sub

Public Sub Redo()
    Dim k As Long
    If uRedo = 0 Then Exit Sub
    k = (uBase + uCount) Mod UMAX
    ReplaceParas uP(k), uOldN(k), uNew(k)
    UndoCursorP = uCurP2(k): UndoCursorO = uCurO2(k)
    uCount = uCount + 1
    uRedo = uRedo - 1
    DocModified = True
End Sub

' ---- editing ---------------------------------------------------------------------------

' Insert text (may hold vbLf = new paragraphs) at (p, o) with one attribute and size.
' Returns the position after it in (p, o).
Public Sub InsertText(p As Long, o As Long, ByVal s As String, ByVal attr As Long, ByVal sz As Long, ByVal typing As Boolean)
    Dim lines() As String, n As Long, i As Long, tailT As String, tailA As String, tailZ As String
    Dim st As Long, al As Long
    If s = "" Then Exit Sub
    If p >= NP Then p = NP - 1: o = Len(pText(p))
    If o > Len(pText(p)) Then o = Len(pText(p))
    s = Replace(Replace(s, vbCr & vbLf, vbLf), vbCr, vbLf)
    lines = Split(s, vbLf)
    n = UBound(lines)
    BeginEdit p, 1, p, o, IIf(typing And n = 0, 1, 0)
    If n = 0 Then
        pText(p) = Left$(pText(p), o) & s & Mid$(pText(p), o + 1)
        pAttr(p) = Left$(pAttr(p), o) & String$(Len(s), Chr$(attr)) & Mid$(pAttr(p), o + 1)
        pSize(p) = Left$(pSize(p), o) & String$(Len(s), Chr$(sz)) & Mid$(pSize(p), o + 1)
        o = o + Len(s)
        EndEdit 1, p, o
        Exit Sub
    End If
    tailT = Mid$(pText(p), o + 1): tailA = Mid$(pAttr(p), o + 1): tailZ = Mid$(pSize(p), o + 1)
    st = pStyle(p): al = pAlign(p)
    ShiftParas p + 1, n
    pText(p) = Left$(pText(p), o) & lines(0)
    pAttr(p) = Left$(pAttr(p), o) & String$(Len(lines(0)), Chr$(attr))
    pSize(p) = Left$(pSize(p), o) & String$(Len(lines(0)), Chr$(sz))
    For i = 1 To n
        ' a new paragraph after a heading is body text; otherwise it keeps the style
        If st >= PS_H1 And st <= PS_H3 Then pStyle(p + i) = PS_BODY Else pStyle(p + i) = st
        pAlign(p + i) = al
        pText(p + i) = lines(i)
        pAttr(p + i) = String$(Len(lines(i)), Chr$(attr))
        If pStyle(p + i) <> st Then sz = StyleSize(pStyle(p + i))
        pSize(p + i) = String$(Len(lines(i)), Chr$(sz))
    Next i
    o = Len(lines(n))
    p = p + n
    pText(p) = pText(p) & tailT: pAttr(p) = pAttr(p) & tailA: pSize(p) = pSize(p) & tailZ
    EndEdit n + 1, p, o
End Sub

' Delete the range; the cursor ends at its start
Public Sub DeleteRange(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long)
    OrderPos p1, o1, p2, o2
    If p1 = p2 And o1 = o2 Then Exit Sub
    BeginEdit p1, p2 - p1 + 1, p2, o2, 0
    pText(p1) = Left$(pText(p1), o1) & Mid$(pText(p2), o2 + 1)
    pAttr(p1) = Left$(pAttr(p1), o1) & Mid$(pAttr(p2), o2 + 1)
    pSize(p1) = Left$(pSize(p1), o1) & Mid$(pSize(p2), o2 + 1)
    If p2 > p1 Then ShiftParas p2 + 1, -(p2 - p1)
    EndEdit 1, p1, o1
End Sub

' Set (mask bits to bits) on the characters of the range
Public Sub ApplyAttr(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long, ByVal mask As Long, ByVal bits As Long)
    Dim p As Long, a As Long, b As Long, i As Long, s As String
    OrderPos p1, o1, p2, o2
    BeginEdit p1, p2 - p1 + 1, p1, o1, 0
    For p = p1 To p2
        If p = p1 Then a = o1 Else a = 0
        If p = p2 Then b = o2 Else b = Len(pText(p))
        s = pAttr(p)
        For i = a + 1 To b
            Mid$(s, i, 1) = Chr$((Asc(Mid$(s, i, 1)) And Not mask) Or (bits And mask))
        Next i
        pAttr(p) = s
    Next p
    EndEdit p2 - p1 + 1, p2, o2
End Sub

Public Sub ApplySize(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long, ByVal sz As Long)
    Dim p As Long, a As Long, b As Long
    OrderPos p1, o1, p2, o2
    sz = ClampSize(sz)
    BeginEdit p1, p2 - p1 + 1, p1, o1, 0
    For p = p1 To p2
        If p = p1 Then a = o1 Else a = 0
        If p = p2 Then b = o2 Else b = Len(pText(p))
        If b > a Then pSize(p) = Left$(pSize(p), a) & String$(b - a, Chr$(sz)) & Mid$(pSize(p), b + 1)
    Next p
    EndEdit p2 - p1 + 1, p2, o2
End Sub

' paragraph style (resets the sizes of the text to the style's) and alignment
Public Sub ApplyParaStyle(ByVal p1 As Long, ByVal p2 As Long, ByVal st As Long)
    Dim p As Long, t As Long
    If p2 < p1 Then t = p1: p1 = p2: p2 = t
    BeginEdit p1, p2 - p1 + 1, p1, 0, 0
    For p = p1 To p2
        pStyle(p) = st
        pSize(p) = String$(Len(pText(p)), Chr$(StyleSize(st)))
        If st >= PS_H1 And st <= PS_H3 Then
            pAttr(p) = BitsOn(pAttr(p), A_BOLD)
        End If
    Next p
    EndEdit p2 - p1 + 1, p1, 0
End Sub

Private Function BitsOn(ByVal s As String, ByVal b As Long) As String
    Dim i As Long
    For i = 1 To Len(s)
        Mid$(s, i, 1) = Chr$(Asc(Mid$(s, i, 1)) Or b)
    Next i
    BitsOn = s
End Function

Public Sub ApplyAlign(ByVal p1 As Long, ByVal p2 As Long, ByVal al As Long)
    Dim p As Long, t As Long
    If p2 < p1 Then t = p1: p1 = p2: p2 = t
    BeginEdit p1, p2 - p1 + 1, p1, 0, 0
    For p = p1 To p2
        pAlign(p) = al
    Next p
    EndEdit p2 - p1 + 1, p1, 0
End Sub

' True if every character of the range has all bits of b
Public Function RangeHas(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long, ByVal b As Long) As Boolean
    Dim p As Long, a As Long, e As Long, i As Long, any As Boolean
    OrderPos p1, o1, p2, o2
    For p = p1 To p2
        If p = p1 Then a = o1 Else a = 0
        If p = p2 Then e = o2 Else e = Len(pText(p))
        For i = a + 1 To e
            any = True
            If (Asc(Mid$(pAttr(p), i, 1)) And b) <> b Then Exit Function
        Next i
    Next p
    RangeHas = any
End Function

' ---- clipboard (styled, inside Penwright) ---------------------------------------------------

Public Function CopyStyled(ByVal p1 As Long, ByVal o1 As Long, ByVal p2 As Long, ByVal o2 As Long) As String
    ' the range as ParaToLine lines (the first and last cut to the range)
    Dim p As Long, a As Long, b As Long, s As String, t As String
    OrderPos p1, o1, p2, o2
    For p = p1 To p2
        If p = p1 Then a = o1 Else a = 0
        If p = p2 Then b = o2 Else b = Len(pText(p))
        t = pStyle(p) & vbTab & pAlign(p) & vbTab & Esc(Mid$(pText(p), a + 1, b - a)) & vbTab & RunsOfPart(p, a, b)
        If p > p1 Then s = s & vbLf
        s = s & t
    Next p
    CopyStyled = s
End Function

Private Function RunsOfPart(ByVal p As Long, ByVal a As Long, ByVal b As Long) As String
    Dim st As String, sa As String, sz As String, r As String
    st = pText(p): sa = pAttr(p): sz = pSize(p)
    pText(p) = Mid$(st, a + 1, b - a): pAttr(p) = Mid$(sa, a + 1, b - a): pSize(p) = Mid$(sz, a + 1, b - a)
    r = RunsOf(p)
    pText(p) = st: pAttr(p) = sa: pSize(p) = sz
    RunsOfPart = r
End Function

' paste CopyStyled text at (p, o); returns the end in (p, o)
Public Sub PasteStyled(p As Long, o As Long, ByVal clip As String)
    Dim lines() As String, n As Long, i As Long, tailT As String, tailA As String, tailZ As String
    Dim f() As String, t As String, a As String, z As String
    lines = Split(clip, vbLf)
    n = UBound(lines)
    BeginEdit p, 1, p, o, 0
    tailT = Mid$(pText(p), o + 1): tailA = Mid$(pAttr(p), o + 1): tailZ = Mid$(pSize(p), o + 1)
    pText(p) = Left$(pText(p), o): pAttr(p) = Left$(pAttr(p), o): pSize(p) = Left$(pSize(p), o)
    ShiftParas p + 1, n
    For i = 0 To n
        ' decode the piece into the scratch paragraph values
        f = Split(lines(i), vbTab)
        If UBound(f) < 3 Then ReDim Preserve f(0 To 3)
        t = Unesc(f(2))
        DecodeRuns t, f(3), Val(f(0)), a, z
        If i = 0 Then
            pText(p) = pText(p) & t: pAttr(p) = pAttr(p) & a: pSize(p) = pSize(p) & z
            If o = 0 And n > 0 Then pStyle(p) = Val(f(0)) And 7: pAlign(p) = Val(f(1)) And 3
        Else
            pText(p + i) = t: pAttr(p + i) = a: pSize(p + i) = z
            pStyle(p + i) = Val(f(0)): pAlign(p + i) = Val(f(1)) And 3
            If pStyle(p + i) > PS_LAST Or pStyle(p + i) < 0 Then pStyle(p + i) = PS_BODY
        End If
    Next i
    p = p + n
    o = Len(pText(p))
    pText(p) = pText(p) & tailT: pAttr(p) = pAttr(p) & tailA: pSize(p) = pSize(p) & tailZ
    EndEdit n + 1, p, o
End Sub

Private Sub DecodeRuns(ByVal t As String, ByVal runs As String, ByVal st As Long, a As String, z As String)
    Dim parts() As String, i As Long, f() As String, k As Long, n As Long
    a = "": z = ""
    n = Len(t)
    If runs <> "" Then
        parts = Split(runs, ",")
        For i = 0 To UBound(parts)
            f = Split(parts(i), ":")
            If UBound(f) >= 2 Then
                k = Val(f(0))
                a = a & String$(k, Chr$(Val(f(1)) And 255))
                z = z & String$(k, Chr$(ClampSize(Val(f(2)))))
            End If
        Next i
    End If
    If Len(a) < n Then
        a = a & String$(n - Len(a), Chr$(0))
        z = z & String$(n - Len(z), Chr$(StyleSize(st)))
    End If
    a = Left$(a, n): z = Left$(z, n)
End Sub

' ---- search -----------------------------------------------------------------------------

Private Function IsWordChar(ByVal ch As String) As Boolean
    Dim k As Long
    If ch = "" Then Exit Function
    k = Asc(ch)
    IsWordChar = (k >= 48 And k <= 57) Or (k >= 65 And k <= 90) Or (k >= 97 And k <= 122) Or k = 39 Or k = 95 Or k >= 192
End Function

' Find what from (p, o) forwards, wrapping round the end once. On success (p, o) is the
' match start and True is returned. Matches stay inside one paragraph.
Public Function FindText(p As Long, o As Long, ByVal what As String, ByVal matchCase As Boolean, ByVal wholeWord As Boolean) As Boolean
    Dim n As Long, pp As Long, oo As Long
    If what = "" Then Exit Function
    For n = 0 To NP
        pp = (p + n) Mod NP
        If n = 0 Then oo = o Else oo = 0
        If FindInPara(pp, oo, what, matchCase, wholeWord) Then
            If n < NP Or oo < o Then
                p = pp: o = oo: FindText = True
            End If
            Exit Function
        End If
    Next n
End Function

' Replace every match; returns how many (one undo step per paragraph changed... grouped)
Public Function ReplaceAll(ByVal what As String, ByVal repl As String, ByVal matchCase As Boolean, ByVal wholeWord As Boolean) As Long
    Dim p As Long, o As Long, cnt As Long, a As Long, sz As Long, guard As Long
    If what = "" Then Exit Function
    p = 0: o = 0
    BeginEdit 0, NP, 0, 0, 0
    Dim saveOld As String
    saveOld = pendOld
    Do
        If Not FindInPara(p, o, what, matchCase, wholeWord) Then
            p = p + 1: o = 0
            If p >= NP Then Exit Do
        Else
            a = AttrAt(p, o): sz = SizeAt(p, o)
            pText(p) = Left$(pText(p), o) & repl & Mid$(pText(p), o + Len(what) + 1)
            pAttr(p) = Left$(pAttr(p), o) & String$(Len(repl), Chr$(a)) & Mid$(pAttr(p), o + Len(what) + 1)
            pSize(p) = Left$(pSize(p), o) & String$(Len(repl), Chr$(sz)) & Mid$(pSize(p), o + Len(what) + 1)
            o = o + Len(repl)
            cnt = cnt + 1
        End If
        guard = guard + 1
        If guard > 1000000 Then Exit Do
    Loop
    If cnt > 0 Then
        pendP = 0: pendN = NP: pendOld = saveOld: pendKind = 0
        EndEdit NP, 0, 0
    End If
    ReplaceAll = cnt
End Function

Private Function FindInPara(ByVal p As Long, o As Long, ByVal what As String, ByVal matchCase As Boolean, ByVal wholeWord As Boolean) As Boolean
    Dim hay As String, k As Long, q As Long
    hay = pText(p)
    If Not matchCase Then hay = LCase$(hay): what = LCase$(what)
    q = o + 1
    Do
        If q > Len(hay) Then Exit Function
        k = InStr(q, hay, what)
        If k = 0 Then Exit Function
        If wholeWord Then
            Dim before As Boolean
            before = False
            If k > 1 Then before = IsWordChar(Mid$(hay, k - 1, 1))
            If before Or IsWordChar(Mid$(hay, k + Len(what), 1)) Then
                q = k + 1
            Else
                o = k - 1: FindInPara = True: Exit Function
            End If
        Else
            o = k - 1: FindInPara = True: Exit Function
        End If
    Loop
End Function

' ---- counting ---------------------------------------------------------------------------

Public Function WordCount() As Long
    Dim p As Long, i As Long, inWord As Boolean, n As Long, s As String, ch As String
    For p = 0 To NP - 1
        s = pText(p)
        inWord = False
        For i = 1 To Len(s)
            ch = Mid$(s, i, 1)
            If ch = " " Or ch = vbTab Then
                inWord = False
            ElseIf Not inWord Then
                If IsWordChar(ch) Then inWord = True: n = n + 1
            End If
        Next i
    Next p
    WordCount = n
End Function

Public Function CharCount(ByVal withSpaces As Boolean) As Long
    Dim p As Long, n As Long
    For p = 0 To NP - 1
        If withSpaces Then
            n = n + Len(pText(p))
        Else
            n = n + Len(Replace(Replace(pText(p), " ", ""), vbTab, ""))
        End If
    Next p
    CharCount = n
End Function

' the word around offset o of paragraph p: its start and length
Public Sub WordAt(ByVal p As Long, ByVal o As Long, ws As Long, wl As Long)
    Dim s As String, a As Long, b As Long
    s = pText(p)
    a = o: b = o
    Do While a > 0
        If Not IsWordChar(Mid$(s, a, 1)) Then Exit Do
        a = a - 1
    Loop
    Do While b < Len(s)
        If Not IsWordChar(Mid$(s, b + 1, 1)) Then Exit Do
        b = b + 1
    Loop
    ws = a: wl = b - a
End Sub

' next word start after offset o (for Ctrl+Right), or the paragraph end
Public Function NextWordStart(ByVal p As Long, ByVal o As Long) As Long
    Dim s As String
    s = pText(p)
    Do While o < Len(s)
        If Not IsWordChar(Mid$(s, o + 1, 1)) Then Exit Do
        o = o + 1
    Loop
    Do While o < Len(s)
        If IsWordChar(Mid$(s, o + 1, 1)) Then Exit Do
        o = o + 1
    Loop
    NextWordStart = o
End Function

Public Function PrevWordStart(ByVal p As Long, ByVal o As Long) As Long
    Dim s As String
    s = pText(p)
    Do While o > 0
        If IsWordChar(Mid$(s, o, 1)) Then Exit Do
        o = o - 1
    Loop
    Do While o > 0
        If Not IsWordChar(Mid$(s, o, 1)) Then Exit Do
        o = o - 1
    Loop
    PrevWordStart = o
End Function
