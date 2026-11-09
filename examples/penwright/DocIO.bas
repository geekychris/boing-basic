' Penwright - files: its own styled format (.pwd), plain text, RTF and HTML export,
' RTF and plain text import.
'
' .pwd is text: a "PENWRIGHT<tab>1" line, "META<tab>key<tab>value" lines, then one
' "P<tab>style<tab>align<tab>text<tab>runs" line per paragraph (Doc.ParaToLine; text
' escaped, runs "len:attr:size,...").
Option Explicit

Public DocIOError As String

' the 16 text colours (attribute bits 4..7); 0 = automatic (black)
Public Function PaletteColor(ByVal i As Long) As Long
    Select Case i And 15
    Case 0: PaletteColor = RGB(0, 0, 0)
    Case 1: PaletteColor = RGB(178, 34, 34)       ' brick red
    Case 2: PaletteColor = RGB(214, 96, 0)        ' orange
    Case 3: PaletteColor = RGB(176, 140, 0)       ' ochre
    Case 4: PaletteColor = RGB(46, 125, 50)       ' green
    Case 5: PaletteColor = RGB(0, 121, 140)       ' teal
    Case 6: PaletteColor = RGB(25, 85, 180)       ' blue
    Case 7: PaletteColor = RGB(94, 53, 160)       ' violet
    Case 8: PaletteColor = RGB(173, 20, 120)      ' magenta
    Case 9: PaletteColor = RGB(110, 110, 110)     ' grey
    Case 10: PaletteColor = RGB(121, 85, 72)      ' brown
    Case 11: PaletteColor = RGB(0, 150, 136)      ' sea green
    Case 12: PaletteColor = RGB(63, 81, 181)      ' indigo
    Case 13: PaletteColor = RGB(233, 30, 99)      ' pink
    Case 14: PaletteColor = RGB(96, 125, 139)     ' slate
    Case 15: PaletteColor = RGB(255, 255, 255)    ' white
    End Select
End Function

Public Function PaletteName(ByVal i As Long) As String
    Select Case i And 15
    Case 0: PaletteName = "Automatic"
    Case 1: PaletteName = "Red"
    Case 2: PaletteName = "Orange"
    Case 3: PaletteName = "Ochre"
    Case 4: PaletteName = "Green"
    Case 5: PaletteName = "Teal"
    Case 6: PaletteName = "Blue"
    Case 7: PaletteName = "Violet"
    Case 8: PaletteName = "Magenta"
    Case 9: PaletteName = "Grey"
    Case 10: PaletteName = "Brown"
    Case 11: PaletteName = "Sea green"
    Case 12: PaletteName = "Indigo"
    Case 13: PaletteName = "Pink"
    Case 14: PaletteName = "Slate"
    Case 15: PaletteName = "White"
    End Select
End Function

Public Function ReadFile(ByVal path As String) As String
    Dim fn As Integer, s As String
    ' (Open For Binary would create a missing file)
    If Dir(path) = "" Then Err.Raise 53, , "File not found: " & path
    fn = FreeFile
    Open path For Binary Access Read As #fn
    s = Space$(LOF(fn))
    Get #fn, , s
    Close #fn
    ReadFile = s
End Function

Public Sub WriteFile(ByVal path As String, ByVal s As String)
    Dim fn As Integer
    On Error Resume Next
    Kill path
    On Error GoTo 0
    fn = FreeFile
    Open path For Binary Access Write As #fn
    Put #fn, , s
    Close #fn
End Sub

' ---- .pwd ------------------------------------------------------------------------------

Public Function DocToPwd() As String
    Dim parts() As String, p As Long, n As Long
    ReDim parts(0 To NP + 4)
    parts(0) = "PENWRIGHT" & vbTab & "1"
    n = 1
    If DocTitle <> "" Then parts(n) = "META" & vbTab & "title" & vbTab & Esc(DocTitle): n = n + 1
    If DocAuthor <> "" Then parts(n) = "META" & vbTab & "author" & vbTab & Esc(DocAuthor): n = n + 1
    parts(n) = "META" & vbTab & "size" & vbTab & DefaultSize: n = n + 1
    For p = 0 To NP - 1
        parts(n) = "P" & vbTab & ParaToLine(p)
        n = n + 1
    Next p
    ReDim Preserve parts(0 To n - 1)
    DocToPwd = Join(parts, vbLf) & vbLf
End Function

Public Function DocFromPwd(ByVal s As String) As Boolean
    Dim lines() As String, i As Long, f() As String, n As Long
    s = Replace(s, vbCr, "")
    If Left$(s, 10) <> "PENWRIGHT" & vbTab Then DocIOError = "not a Penwright document": Exit Function
    lines = Split(s, vbLf)
    NewDoc
    NP = 0
    For i = 1 To UBound(lines)
        If Left$(lines(i), 2) = "P" & vbTab Then
            ReserveParas NP + 1
            ParaFromLine NP, Mid$(lines(i), 3)
            NP = NP + 1
        ElseIf Left$(lines(i), 5) = "META" & vbTab Then
            f = Split(lines(i), vbTab)
            If UBound(f) >= 2 Then
                Select Case f(1)
                Case "title": DocTitle = Unesc(f(2))
                Case "author": DocAuthor = Unesc(f(2))
                Case "size": If Val(f(2)) >= 6 And Val(f(2)) <= 72 Then DefaultSize = Val(f(2))
                End Select
            End If
        End If
    Next i
    If NP = 0 Then NewDoc
    DocModified = False
    DocFromPwd = True
End Function

' make room for n paragraphs (used while loading)
Public Sub ReserveParas(ByVal n As Long)
    Dim m As Long
    If n - 1 <= UBound(pText) Then Exit Sub
    m = (UBound(pText) + 1) * 2
    If m < n Then m = n
    ReDim Preserve pText(0 To m - 1): ReDim Preserve pAttr(0 To m - 1): ReDim Preserve pSize(0 To m - 1)
    ReDim Preserve pStyle(0 To m - 1): ReDim Preserve pAlign(0 To m - 1)
End Sub

Public Function SavePwd(ByVal path As String) As Boolean
    On Error GoTo Bad
    WriteFile path, DocToPwd()
    DocModified = False
    SavePwd = True
    Exit Function
Bad:
    DocIOError = Err.Description
End Function

' Open any supported file: .pwd, .rtf, else plain text
Public Function OpenDoc(ByVal path As String) As Boolean
    Dim s As String
    On Error GoTo Bad
    s = ReadFile(path)
    If Left$(s, 10) = "PENWRIGHT" & vbTab Then
        OpenDoc = DocFromPwd(s)
    ElseIf Left$(s, 5) = "{\rtf" Then
        OpenDoc = DocFromRtf(s)
    Else
        DocFromText s
        OpenDoc = True
    End If
    Exit Function
Bad:
    DocIOError = Err.Description
End Function

' ---- plain text --------------------------------------------------------------------------

Public Sub DocFromText(ByVal s As String)
    Dim lines() As String, i As Long
    s = Replace(Replace(s, vbCr & vbLf, vbLf), vbCr, vbLf)
    If Right$(s, 1) = vbLf Then s = Left$(s, Len(s) - 1)
    lines = Split(s, vbLf)
    NewDoc
    ReserveParas UBound(lines) + 1
    For i = 0 To UBound(lines)
        pText(i) = Replace(lines(i), vbTab, "    ")
        pAttr(i) = String$(Len(pText(i)), Chr$(0))
        pSize(i) = String$(Len(pText(i)), Chr$(DefaultSize))
        pStyle(i) = PS_BODY: pAlign(i) = AL_LEFT
    Next i
    NP = UBound(lines) + 1
    DocModified = False
End Sub

' plain text, optionally wrapped at width columns (0 = one line per paragraph)
Public Function DocToText(ByVal width As Long) As String
    Dim p As Long, s As String, l As String
    For p = 0 To NP - 1
        l = pText(p)
        If pStyle(p) = PS_BULLET Then l = "* " & l
        If width > 0 Then l = WrapPlain(l, width)
        s = s & l & vbLf
    Next p
    DocToText = s
End Function

Private Function WrapPlain(ByVal l As String, ByVal width As Long) As String
    Dim res As String, k As Long
    Do While Len(l) > width
        k = InStrRev(Left$(l, width + 1), " ")
        If k <= 1 Then k = width + 1
        res = res & RTrim$(Left$(l, k - 1)) & vbLf
        l = LTrim$(Mid$(l, k))
    Loop
    WrapPlain = res & l
End Function

' ---- HTML ----------------------------------------------------------------------------------

Private Function HtmlEsc(ByVal s As String) As String
    Dim i As Long, k As Long, res As String
    s = Replace(s, "&", "&amp;")
    s = Replace(s, "<", "&lt;")
    s = Replace(s, ">", "&gt;")
    s = Replace(s, Chr$(34), "&quot;")
    ' Latin-1 above 127 as numeric references, so any encoding reads it
    For i = 1 To Len(s)
        k = Asc(Mid$(s, i, 1))
        If k > 127 Then res = res & "&#" & k & ";" Else res = res & Mid$(s, i, 1)
    Next i
    HtmlEsc = res
End Function

Private Function HexColor(ByVal c As Long) As String
    HexColor = "#" & Right$("0" & Hex$(c And 255), 2) & Right$("0" & Hex$((c \ 256) And 255), 2) & Right$("0" & Hex$((c \ 65536) And 255), 2)
End Function

' the runs of paragraph p as HTML (tags opened and closed per run)
Private Function RunsHtml(ByVal p As Long) As String
    Dim i As Long, n As Long, st As Long, a As Long, z As Long, s As String, t As String, base As Long, css As String
    n = Len(pText(p))
    base = StyleSize(pStyle(p))
    st = 1
    For i = 2 To n + 1
        If i > n Then
            t = "x"
        ElseIf Mid$(pAttr(p), i, 1) <> Mid$(pAttr(p), st, 1) Or Mid$(pSize(p), i, 1) <> Mid$(pSize(p), st, 1) Then
            t = "x"
        Else
            t = ""
        End If
        If t <> "" Then
            a = Asc(Mid$(pAttr(p), st, 1)): z = Asc(Mid$(pSize(p), st, 1))
            t = HtmlEsc(Mid$(pText(p), st, i - st))
            If (a And A_BOLD) And Not (pStyle(p) >= PS_H1 And pStyle(p) <= PS_H3) Then t = "<b>" & t & "</b>"
            If a And A_ITALIC Then t = "<i>" & t & "</i>"
            If a And A_UNDER Then t = "<u>" & t & "</u>"
            If a And A_STRIKE Then t = "<s>" & t & "</s>"
            css = ""
            If (a And A_COLMASK) <> 0 Then css = "color:" & HexColor(PaletteColor((a And A_COLMASK) \ 16)) & ";"
            If z <> base Then css = css & "font-size:" & z & "pt;"
            If css <> "" Then t = "<span style=""" & css & """>" & t & "</span>"
            s = s & t
            st = i
        End If
    Next i
    RunsHtml = s
End Function

Public Function DocToHtml() As String
    Dim p As Long, s As String, tag As String, al As String, inList As Boolean, inPre As Boolean, title As String
    title = DocTitle
    If title = "" Then title = "Document"
    s = "<!DOCTYPE html>" & vbLf & "<html><head><meta charset=""utf-8"">" & vbLf & "<title>" & HtmlEsc(title) & "</title>" & vbLf
    If DocAuthor <> "" Then s = s & "<meta name=""author"" content=""" & HtmlEsc(DocAuthor) & """>" & vbLf
    s = s & "<style>body{font-family:Georgia,serif;font-size:" & DefaultSize & "pt;max-width:40em;margin:2em auto;line-height:1.4}" & _
        "blockquote{border-left:3px solid #999;margin-left:0;padding-left:1em;color:#444}</style>" & vbLf & "</head><body>" & vbLf
    For p = 0 To NP - 1
        If pStyle(p) = PS_BULLET And Not inList Then s = s & "<ul>" & vbLf: inList = True
        If pStyle(p) <> PS_BULLET And inList Then s = s & "</ul>" & vbLf: inList = False
        If pStyle(p) = PS_CODE And Not inPre Then s = s & "<pre>": inPre = True
        If pStyle(p) <> PS_CODE And inPre Then s = s & "</pre>" & vbLf: inPre = False
        Select Case pAlign(p)
        Case AL_CENTER: al = " style=""text-align:center"""
        Case AL_RIGHT: al = " style=""text-align:right"""
        Case AL_JUSTIFY: al = " style=""text-align:justify"""
        Case Else: al = ""
        End Select
        Select Case pStyle(p)
        Case PS_H1: tag = "h1"
        Case PS_H2: tag = "h2"
        Case PS_H3: tag = "h3"
        Case PS_QUOTE: tag = "blockquote"
        Case PS_BULLET: tag = "li"
        Case PS_CODE: tag = ""
        Case Else: tag = "p"
        End Select
        If tag = "" Then
            s = s & HtmlEsc(pText(p)) & vbLf
        ElseIf pText(p) = "" And tag = "p" Then
            s = s & "<p" & al & ">&nbsp;</p>" & vbLf
        Else
            s = s & "<" & tag & al & ">" & RunsHtml(p) & "</" & tag & ">" & vbLf
        End If
    Next p
    If inList Then s = s & "</ul>" & vbLf
    If inPre Then s = s & "</pre>" & vbLf
    DocToHtml = s & "</body></html>" & vbLf
End Function

' ---- RTF ------------------------------------------------------------------------------------

Private Function RtfEsc(ByVal s As String) As String
    Dim i As Long, k As Long, res As String, ch As String
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        k = Asc(ch)
        If ch = "\" Or ch = "{" Or ch = "}" Then
            res = res & "\" & ch
        ElseIf k > 127 Then
            res = res & "\'" & LCase$(Right$("0" & Hex$(k), 2))
        ElseIf k = 9 Then
            res = res & "\tab "
        Else
            res = res & ch
        End If
    Next i
    RtfEsc = res
End Function

Public Function DocToRtf() As String
    Dim p As Long, s As String, i As Long, n As Long, st As Long, a As Long, z As Long, c As Long, t As String
    s = "{\rtf1\ansi\ansicpg1252\deff0" & vbLf & "{\fonttbl{\f0\froman Times New Roman;}{\f1\fswiss Helvetica;}{\f2\fmodern Courier New;}}" & vbLf
    s = s & "{\colortbl;"
    For i = 0 To 15
        c = PaletteColor(i)
        s = s & "\red" & (c And 255) & "\green" & ((c \ 256) And 255) & "\blue" & ((c \ 65536) And 255) & ";"
    Next i
    s = s & "}" & vbLf
    If DocTitle <> "" Or DocAuthor <> "" Then
        s = s & "{\info"
        If DocTitle <> "" Then s = s & "{\title " & RtfEsc(DocTitle) & "}"
        If DocAuthor <> "" Then s = s & "{\author " & RtfEsc(DocAuthor) & "}"
        s = s & "}" & vbLf
    End If
    For p = 0 To NP - 1
        s = s & "\pard"
        Select Case pAlign(p)
        Case AL_CENTER: s = s & "\qc"
        Case AL_RIGHT: s = s & "\qr"
        Case AL_JUSTIFY: s = s & "\qj"
        Case Else: s = s & "\ql"
        End Select
        Select Case pStyle(p)
        Case PS_H1, PS_H2, PS_H3: s = s & "\sb240\sa120\f1"
        Case PS_QUOTE: s = s & "\li720\ri720\f0"
        Case PS_BULLET: s = s & "\fi-360\li720\f0 \bullet\tab"
        Case PS_CODE: s = s & "\f2"
        Case Else: s = s & "\sa120\f0"
        End Select
        s = s & " "
        n = Len(pText(p))
        st = 1
        For i = 2 To n + 1
            If i > n Then
                t = "x"
            ElseIf Mid$(pAttr(p), i, 1) <> Mid$(pAttr(p), st, 1) Or Mid$(pSize(p), i, 1) <> Mid$(pSize(p), st, 1) Then
                t = "x"
            Else
                t = ""
            End If
            If t <> "" Then
                a = Asc(Mid$(pAttr(p), st, 1)): z = Asc(Mid$(pSize(p), st, 1))
                s = s & "{\fs" & (z * 2)
                If a And A_BOLD Then s = s & "\b"
                If a And A_ITALIC Then s = s & "\i"
                If a And A_UNDER Then s = s & "\ul"
                If a And A_STRIKE Then s = s & "\strike"
                If (a And A_COLMASK) <> 0 Then s = s & "\cf" & ((a And A_COLMASK) \ 16 + 1)
                s = s & " " & RtfEsc(Mid$(pText(p), st, i - st)) & "}"
                st = i
            End If
        Next i
        s = s & "\par" & vbLf
    Next p
    DocToRtf = s & "}" & vbLf
End Function

' A small RTF reader: paragraphs, \b \i \ul \strike \fs \cf (nearest palette colour),
' \qc \qr \qj, \'hh, \tab, groups. Skips font/colour tables, \info, \* destinations, pictures.
Public Function DocFromRtf(ByVal s As String) As Boolean
    Dim i As Long, n As Long, ch As String, word As String, num As String, hasNum As Boolean
    Dim depth As Long, skipDepth As Long, a As Long, z As Long, al As Long
    Dim stA(0 To 63) As Long, stZ(0 To 63) As Long, stSkip(0 To 63) As Long
    Dim colors(0 To 63) As Long, ncol As Long, inColTbl As Boolean, cr As Long, cg As Long, cb As Long
    Dim curT As String, curA As String, curZ As String
    NewDoc
    NP = 0
    z = DefaultSize
    n = Len(s)
    i = 1
    Do While i <= n
        ch = Mid$(s, i, 1)
        If ch = "{" Then
            If depth < 63 Then stA(depth) = a: stZ(depth) = z: stSkip(depth) = skipDepth
            depth = depth + 1
            i = i + 1
        ElseIf ch = "}" Then
            depth = depth - 1
            If depth < 0 Then Exit Do
            If depth < 63 Then a = stA(depth): z = stZ(depth): skipDepth = stSkip(depth)
            If inColTbl And skipDepth = 0 Then inColTbl = False
            i = i + 1
        ElseIf ch = "\" Then
            i = i + 1
            ch = Mid$(s, i, 1)
            If ch = "\" Or ch = "{" Or ch = "}" Then
                If skipDepth = 0 Then curT = curT & ch: curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                i = i + 1
            ElseIf ch = "'" Then
                If skipDepth = 0 Then
                    curT = curT & Chr$(Val("&H" & Mid$(s, i + 1, 2)))
                    curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                End If
                i = i + 3
            ElseIf ch = "*" Then
                skipDepth = depth
                i = i + 1
            Else
                word = "": num = "": hasNum = False
                Do While i <= n
                    ch = Mid$(s, i, 1)
                    If (ch >= "a" And ch <= "z") Or (ch >= "A" And ch <= "Z") Then word = word & ch: i = i + 1 Else Exit Do
                Loop
                If ch = "-" Or (ch >= "0" And ch <= "9") Then
                    hasNum = True
                    num = ch: i = i + 1
                    Do While i <= n
                        ch = Mid$(s, i, 1)
                        If ch >= "0" And ch <= "9" Then num = num & ch: i = i + 1 Else Exit Do
                    Loop
                End If
                If Mid$(s, i, 1) = " " Then i = i + 1
                Select Case word
                Case "fonttbl", "stylesheet", "info", "pict", "header", "footer", "listtable", "listoverridetable", "generator"
                    skipDepth = depth
                Case "colortbl"
                    inColTbl = True: ncol = 0: cr = 0: cg = 0: cb = 0
                Case "red": cr = Val(num)
                Case "green": cg = Val(num)
                Case "blue": cb = Val(num)
                Case "par", "line"
                    If skipDepth = 0 Then
                        ReserveParas NP + 1
                        pText(NP) = curT: pAttr(NP) = curA: pSize(NP) = curZ
                        pStyle(NP) = PS_BODY: pAlign(NP) = al
                        NP = NP + 1
                        curT = "": curA = "": curZ = ""
                    End If
                Case "pard": al = AL_LEFT
                Case "qc": al = AL_CENTER
                Case "qr": al = AL_RIGHT
                Case "qj": al = AL_JUSTIFY
                Case "ql": al = AL_LEFT
                Case "plain": a = 0: z = DefaultSize
                Case "b": If hasNum And num = "0" Then a = a And Not A_BOLD Else a = a Or A_BOLD
                Case "i": If hasNum And num = "0" Then a = a And Not A_ITALIC Else a = a Or A_ITALIC
                Case "ul": If hasNum And num = "0" Then a = a And Not A_UNDER Else a = a Or A_UNDER
                Case "ulnone": a = a And Not A_UNDER
                Case "strike": If hasNum And num = "0" Then a = a And Not A_STRIKE Else a = a Or A_STRIKE
                Case "fs": If hasNum Then z = ClampSize(Val(num) \ 2)
                Case "cf"
                    If hasNum Then
                        If Val(num) > 0 And Val(num) < ncol Then
                            a = (a And Not A_COLMASK) Or (NearestPalette(colors(Val(num))) * 16)
                        Else
                            a = a And Not A_COLMASK
                        End If
                    End If
                Case "tab"
                    If skipDepth = 0 Then curT = curT & "    ": curA = curA & String$(4, Chr$(a)): curZ = curZ & String$(4, Chr$(z))
                Case "bullet"
                    If skipDepth = 0 Then curT = curT & Chr$(183): curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                Case "emdash", "endash"
                    If skipDepth = 0 Then curT = curT & "-": curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                Case "lquote", "rquote"
                    If skipDepth = 0 Then curT = curT & "'": curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                Case "ldblquote", "rdblquote"
                    If skipDepth = 0 Then curT = curT & Chr$(34): curA = curA & Chr$(a): curZ = curZ & Chr$(z)
                End Select
            End If
        ElseIf ch = vbCr Or ch = vbLf Then
            i = i + 1
        ElseIf ch = ";" And inColTbl Then
            If ncol <= 62 Then colors(ncol) = RGB(cr, cg, cb): ncol = ncol + 1
            cr = 0: cg = 0: cb = 0
            i = i + 1
        Else
            If skipDepth = 0 And depth > 0 And Not inColTbl Then
                curT = curT & ch: curA = curA & Chr$(a): curZ = curZ & Chr$(z)
            End If
            i = i + 1
        End If
    Loop
    If curT <> "" Then
        ReserveParas NP + 1
        pText(NP) = curT: pAttr(NP) = curA: pSize(NP) = curZ: pStyle(NP) = PS_BODY: pAlign(NP) = al
        NP = NP + 1
    End If
    If NP = 0 Then NewDoc
    DocModified = False
    DocFromRtf = True
End Function

Private Function NearestPalette(ByVal c As Long) As Long
    Dim i As Long, best As Long, bd As Long, d As Long, p As Long
    bd = 1000000
    For i = 0 To 15
        p = PaletteColor(i)
        d = Abs((c And 255) - (p And 255)) + Abs(((c \ 256) And 255) - ((p \ 256) And 255)) + Abs(((c \ 65536) And 255) - ((p \ 65536) And 255))
        If d < bd Then bd = d: best = i
    Next i
    NearestPalette = best
End Function

Public Function ExportAs(ByVal path As String, ByVal fmt As String) As Boolean
    On Error GoTo Bad
    Select Case LCase$(fmt)
    Case "rtf": WriteFile path, DocToRtf()
    Case "html", "htm": WriteFile path, DocToHtml()
    Case "txt", "text": WriteFile path, DocToText(0)
    Case Else: DocIOError = "unknown format " & fmt: Exit Function
    End Select
    ExportAs = True
    Exit Function
Bad:
    DocIOError = Err.Description
End Function
