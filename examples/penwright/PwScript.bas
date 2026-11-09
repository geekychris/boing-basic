' Penwright - commands by name, for the ARexx port, --script files and the tests:
' "INSERTTEXT Dear Sir", "BOLD ON", "STYLE HEADING1", "SAVE RAM:x.pwd", "WORDCOUNT".
' RunCommand returns the result; PwRC is 0, 5 (warning) or 10 (error, the result is the
' message). QUIT, SHOT and PAUSE are flags/lines for the form.
Option Explicit

Public PwRC As Long
Public PwPath As String
Public PwQuit As Boolean
Public PwShot As String
Public PwRedraw As Boolean
Public TypingAttr As Long             ' attributes for typing when they were set without a selection
Public TypingSize As Long
Public TypingSet As Boolean
Public ClipStyled As String           ' Penwright's own clipboard (styled)
Public ClipPlain As String

Private Function Word(ByVal s As String, ByVal n As Long) As String
    Dim w() As String, i As Long, k As Long
    w = Split(Trim$(s), " ")
    For i = 0 To UBound(w)
        If w(i) <> "" Then
            k = k + 1
            If k = n Then Word = w(i): Exit Function
        End If
    Next i
End Function

Private Function After(ByVal s As String, ByVal n As Long) As String
    Dim i As Long, p As Long
    s = LTrim$(s)
    p = 1
    For i = 1 To n
        p = InStr(p, s, " ")
        If p = 0 Then After = "": Exit Function
        Do While Mid$(s, p, 1) = " ": p = p + 1: Loop
    Next i
    After = Mid$(s, p)
End Function

Private Function Fail(ByVal msg As String) As String
    PwRC = 10
    Fail = msg
End Function

Public Function StyleByName(ByVal s As String) As Long
    Select Case UCase$(Replace(s, " ", ""))
    Case "BODY", "NORMAL": StyleByName = PS_BODY
    Case "HEADING1", "H1", "TITLE": StyleByName = PS_H1
    Case "HEADING2", "H2": StyleByName = PS_H2
    Case "HEADING3", "H3": StyleByName = PS_H3
    Case "QUOTE": StyleByName = PS_QUOTE
    Case "BULLET", "LIST": StyleByName = PS_BULLET
    Case "CODE": StyleByName = PS_CODE
    Case Else: StyleByName = -1
    End Select
End Function

' type text at the cursor (replacing the selection)
Public Sub TypeText(ByVal s As String, ByVal typing As Boolean)
    Dim p1 As Long, o1 As Long, p2 As Long, o2 As Long, a As Long, z As Long
    If HasSelection() Then
        SelRange p1, o1, p2, o2
        a = AttrAt(p1, o1): z = SizeAt(p1, o1)
        DeleteRange p1, o1, p2, o2
        SetCursor p1, o1, False
        If Not TypingSet Then TypingAttr = a: TypingSize = z: TypingSet = True
    End If
    If Not TypingSet Then
        TypingAttr = AttrForTyping(curP, curO)
        TypingSize = SizeForTyping(curP, curO)
    End If
    If TypingSize = 0 Then TypingSize = StyleSize(pStyle(curP))
    p1 = curP: o1 = curO
    InsertText p1, o1, s, TypingAttr, TypingSize, typing
    SyncLayout
    SetCursor p1, o1, False
    If InStr(s, vbLf) > 0 Then TypingSet = False
    EnsureCaretVisible
End Sub

' toggle or set an attribute bit: on the selection, else for the next typing
Public Sub SetAttrBit(ByVal b As Long, ByVal mode As String)
    Dim p1 As Long, o1 As Long, p2 As Long, o2 As Long, on_ As Boolean
    If HasSelection() Then
        SelRange p1, o1, p2, o2
        Select Case UCase$(mode)
        Case "ON": on_ = True
        Case "OFF": on_ = False
        Case Else: on_ = Not RangeHas(p1, o1, p2, o2, b)
        End Select
        ApplyAttr p1, o1, p2, o2, b, IIf(on_, b, 0)
    Else
        If Not TypingSet Then TypingAttr = AttrForTyping(curP, curO): TypingSize = SizeForTyping(curP, curO): TypingSet = True
        Select Case UCase$(mode)
        Case "ON": TypingAttr = TypingAttr Or b
        Case "OFF": TypingAttr = TypingAttr And Not b
        Case Else: TypingAttr = TypingAttr Xor b
        End Select
    End If
End Sub

Private Function SelParas(p1 As Long, p2 As Long) As Boolean
    Dim o1 As Long, o2 As Long
    SelRange p1, o1, p2, o2
    SelParas = True
End Function

Public Function RunCommand(ByVal line As String) As String
    Dim cmd As String, a1 As String, rest As String, p1 As Long, o1 As Long, p2 As Long, o2 As Long, k As Long, s As String
    Dim p As Long, o As Long
    PwRC = 0
    line = Trim$(line)
    If line = "" Or Left$(line, 1) = ";" Then Exit Function
    cmd = UCase$(Word(line, 1))
    a1 = Word(line, 2)
    rest = After(line, 1)
    PwRedraw = True
    SelRange p1, o1, p2, o2
    Select Case cmd
    Case "INSERTTEXT", "TYPE"
        TypeText Replace(rest, "\n", vbLf), cmd = "TYPE"
    Case "NEWPARAGRAPH", "RETURN"
        TypeText vbLf, False
    Case "GETTEXT"
        If HasSelection() Then RunCommand = GetText(p1, o1, p2, o2) Else RunCommand = AllText()
        PwRedraw = False
    Case "GETPARA"
        k = Val(a1)
        If k < 0 Or k >= NP Then RunCommand = Fail("no paragraph " & k): Exit Function
        RunCommand = pText(k): PwRedraw = False
    Case "PARACOUNT"
        RunCommand = CStr(NP): PwRedraw = False
    Case "GETCURSOR"
        RunCommand = curP & " " & curO: PwRedraw = False
    Case "SETCURSOR", "GOTO"
        SetCursor Val(a1), Val(Word(line, 3)), False
        EnsureCaretVisible
    Case "SELECT"
        SetCursor Val(a1), Val(Word(line, 3)), False
        SetCursor Val(Word(line, 4)), Val(Word(line, 5)), True
        EnsureCaretVisible
    Case "SELECTALL"
        SetCursor 0, 0, False
        SetCursor NP - 1, Len(pText(NP - 1)), True
    Case "GETSELECTION"
        RunCommand = GetText(p1, o1, p2, o2): PwRedraw = False
    Case "DELETE"
        If HasSelection() Then
            DeleteRange p1, o1, p2, o2
        ElseIf curO < Len(pText(curP)) Then
            DeleteRange curP, curO, curP, curO + 1
        ElseIf curP < NP - 1 Then
            DeleteRange curP, curO, curP + 1, 0
        End If
        SyncLayout
        SetCursor p1, o1, False
    Case "BOLD": SetAttrBit A_BOLD, a1
    Case "ITALIC": SetAttrBit A_ITALIC, a1
    Case "UNDERLINE": SetAttrBit A_UNDER, a1
    Case "STRIKE": SetAttrBit A_STRIKE, a1
    Case "COLOR", "COLOUR"
        k = Val(a1) And 15
        If HasSelection() Then
            ApplyAttr p1, o1, p2, o2, A_COLMASK, k * 16
        Else
            If Not TypingSet Then TypingAttr = AttrForTyping(curP, curO): TypingSize = SizeForTyping(curP, curO): TypingSet = True
            TypingAttr = (TypingAttr And Not A_COLMASK) Or k * 16
        End If
    Case "SIZE"
        k = ClampSize(Val(a1))
        If HasSelection() Then
            ApplySize p1, o1, p2, o2, k
        Else
            If Not TypingSet Then TypingAttr = AttrForTyping(curP, curO): TypingSet = True
            TypingSize = k
        End If
    Case "PLAIN"
        If HasSelection() Then ApplyAttr p1, o1, p2, o2, 255, 0 Else TypingAttr = 0: TypingSet = True
    Case "STYLE"
        k = StyleByName(rest)
        If k < 0 Then RunCommand = Fail("unknown style " & rest): Exit Function
        ApplyParaStyle p1, p2, k
        TypingSet = False
    Case "ALIGN"
        Select Case UCase$(a1)
        Case "LEFT": k = AL_LEFT
        Case "CENTER", "CENTRE": k = AL_CENTER
        Case "RIGHT": k = AL_RIGHT
        Case "JUSTIFY": k = AL_JUSTIFY
        Case Else: RunCommand = Fail("ALIGN LEFT|CENTER|RIGHT|JUSTIFY"): Exit Function
        End Select
        ApplyAlign p1, p2, k
    Case "FIND"
        ' FIND text [CASE] [WORD]: options as the last words
        Dim mc As Boolean, ww As Boolean, what As String
        what = rest
        Do
            If UCase$(Right$(what, 5)) = " CASE" Then
                mc = True: what = Left$(what, Len(what) - 5)
            ElseIf UCase$(Right$(what, 5)) = " WORD" Then
                ww = True: what = Left$(what, Len(what) - 5)
            Else
                Exit Do
            End If
        Loop
        p = curP: o = curO
        If HasSelection() Then p = p2: o = o2
        If FindText(p, o, what, mc, ww) Then
            SetCursor p, o, False
            SetCursor p, o + Len(what), True
            EnsureCaretVisible
            RunCommand = p & " " & o
        Else
            PwRC = 5: RunCommand = "not found"
        End If
    Case "REPLACEALL"
        ' REPLACEALL "find" "with" [CASE] [WORD]
        Dim q() As String
        q = Split(rest, Chr$(34))
        If UBound(q) < 3 Then RunCommand = Fail("REPLACEALL ""find"" ""with"" [CASE] [WORD]"): Exit Function
        s = UCase$(q(UBound(q)))
        k = ReplaceAll(q(1), q(3), InStr(s, "CASE") > 0, InStr(s, "WORD") > 0)
        SyncLayout
        SetCursor curP, curO, False
        RunCommand = CStr(k)
    Case "WORDCOUNT"
        RunCommand = CStr(WordCount()): PwRedraw = False
    Case "CHARCOUNT"
        RunCommand = CStr(CharCount(True)): PwRedraw = False
    Case "UNDO", "REDO"
        If cmd = "UNDO" Then Undo Else Redo
        SyncLayout
        SetCursor UndoCursorP, UndoCursorO, False
        EnsureCaretVisible
    Case "COPY", "CUT"
        If Not HasSelection() Then PwRC = 5: Exit Function
        ClipStyled = CopyStyled(p1, o1, p2, o2)
        ClipPlain = GetText(p1, o1, p2, o2)
        If cmd = "CUT" Then
            DeleteRange p1, o1, p2, o2
            SyncLayout
            SetCursor p1, o1, False
        End If
    Case "PASTE"
        If ClipStyled = "" Then PwRC = 5: Exit Function
        If HasSelection() Then
            DeleteRange p1, o1, p2, o2
            SyncLayout
            SetCursor p1, o1, False
        End If
        p = curP: o = curO
        PasteStyled p, o, ClipStyled
        SyncLayout
        SetCursor p, o, False
        EnsureCaretVisible
    Case "NEW"
        NewDoc
        SyncLayout
        SetCursor 0, 0, False
        scrollY = 0
        PwPath = ""
    Case "OPEN"
        If Not OpenDoc(rest) Then RunCommand = Fail(DocIOError): Exit Function
        SyncLayout
        SetCursor 0, 0, False
        scrollY = 0
        If LCase$(Right$(rest, 4)) = ".pwd" Then PwPath = rest Else PwPath = ""
    Case "SAVE", "SAVEAS"
        s = rest
        If s = "" Then s = PwPath
        If s = "" Then RunCommand = Fail("no file name"): Exit Function
        If Not SavePwd(s) Then RunCommand = Fail(DocIOError): Exit Function
        PwPath = s
    Case "EXPORT"
        ' EXPORT RTF|HTML|TXT path
        If Not ExportAs(After(line, 2), a1) Then RunCommand = Fail(DocIOError): Exit Function
    Case "SPELLNEXT"
        Dim wl As Long
        p = curP: o = curO
        If HasSelection() Then p = p2: o = o2
        If Not SpellReady Then RunCommand = Fail("no dictionary"): Exit Function
        If NextMisspelt(p, o, wl) Then
            SetCursor p, o, False
            SetCursor p, o + wl, True
            EnsureCaretVisible
            RunCommand = Mid$(pText(p), o + 1, wl)
        Else
            PwRC = 5: RunCommand = "no more"
        End If
    Case "SUGGEST"
        If a1 = "" Then a1 = GetText(p1, o1, p2, o2)
        RunCommand = Replace(Suggest(a1, 6), vbLf, " "): PwRedraw = False
    Case "LEARN"
        If a1 = "" Then a1 = GetText(p1, o1, p2, o2)
        AddWord a1
        SpellChanged
    Case "LIVESPELL"
        LiveSpell = (UCase$(a1) <> "OFF")
    Case "TITLE"
        DocTitle = rest: DocModified = True
    Case "AUTHOR"
        DocAuthor = rest: DocModified = True
    Case "MODIFIED"
        RunCommand = CStr(-CLng(DocModified)): PwRedraw = False
    Case "FILENAME"
        RunCommand = PwPath: PwRedraw = False
    Case "SHOT"
        PwShot = rest
    Case "QUIT"
        PwQuit = True
    Case "VERSION"
        RunCommand = "Penwright 1.0": PwRedraw = False
    Case Else
        RunCommand = Fail("unknown command " & cmd)
        PwRedraw = False
    End Select
End Function
