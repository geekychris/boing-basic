' Gridwise - commands by name: the ARexx port, --script files and the tests all drive the
' sheet through RunCommand ("SETCELL A1 =SUM(B1:B9)", "GETCELL A1", "CHART BAR A1:C5 Sales").
' Returns the result text; ScriptRC is 0 (ok), 5 (warning) or 10 (error, the message is
' the result). Commands that need the window (QUIT, SHOT, HELP) set flags for the form.
Option Explicit

Public ScriptRC As Long
Public DocPath As String
Public WantQuit As Boolean
Public WantShot As String
Public WantRedraw As Boolean
Public LogLines As String              ' what PRINT/LOG collected (scripts)

Private Function Arg(ByVal s As String, ByVal n As Long) As String
    ' the n-th space-separated word (1-based); "quoted words" count as one
    Dim i As Long, k As Long, w As String, q As Boolean, ch As String
    s = Trim$(s)
    k = 1
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch = Chr$(34) Then
            q = Not q
        ElseIf ch = " " And Not q Then
            If w <> "" Or (i > 1 And Mid$(s, i - 1, 1) = Chr$(34)) Then
                If k = n Then Arg = w: Exit Function
                k = k + 1
                w = ""
            End If
        Else
            w = w & ch
        End If
    Next i
    If k = n Then Arg = w
End Function

' everything after the first n words
Private Function RestAfter(ByVal s As String, ByVal n As Long) As String
    Dim i As Long, p As Long
    s = Trim$(s)
    p = 1
    For i = 1 To n
        p = InStr(p, s, " ")
        If p = 0 Then RestAfter = "": Exit Function
        Do While Mid$(s, p, 1) = " ": p = p + 1: Loop
    Next i
    RestAfter = Mid$(s, p)
    If Left$(RestAfter, 1) = Chr$(34) And Right$(RestAfter, 1) = Chr$(34) And Len(RestAfter) >= 2 Then
        RestAfter = Mid$(RestAfter, 2, Len(RestAfter) - 2)
    End If
End Function

Private Function Bad(ByVal msg As String) As String
    ScriptRC = 10
    Bad = msg
End Function

Public Function FormatByName(ByVal s As String) As Long
    Select Case UCase$(s)
    Case "GENERAL": FormatByName = NF_GENERAL
    Case "INTEGER", "0": FormatByName = NF_INT
    Case "FIXED", "0.00": FormatByName = NF_FIX2
    Case "THOUSANDS", "#,##0": FormatByName = NF_THOUS
    Case "THOUSANDS2", "#,##0.00": FormatByName = NF_THOUS2
    Case "PERCENT", "0%": FormatByName = NF_PCT
    Case "PERCENT2", "0.00%": FormatByName = NF_PCT2
    Case "CURRENCY": FormatByName = NF_CURRENCY
    Case "SCIENTIFIC": FormatByName = NF_SCI
    Case "DATE": FormatByName = NF_DATE
    Case "TIME": FormatByName = NF_TIME
    Case Else: FormatByName = -1
    End Select
End Function

Public Function RunCommand(ByVal line As String) As String
    Dim cmd As String, a1 As String, a2 As String, r As Long, c As Long, r1 As Long, c1 As Long, r2 As Long, c2 As Long
    Dim n As Long, s As String, k As Long
    ScriptRC = 0
    line = Trim$(line)
    If line = "" Or Left$(line, 1) = ";" Or Left$(line, 1) = "#" Then Exit Function
    cmd = UCase$(Arg(line, 1))
    a1 = Arg(line, 2)
    a2 = Arg(line, 3)
    SelBounds r1, c1, r2, c2
    WantRedraw = True
    Select Case cmd
    Case "GETCELL", "GETFORMULA", "GETVALUE"
        If a1 = "" Then
            r = curR: c = curC
        ElseIf Not ParseCellName(a1, r, c) Then
            RunCommand = Bad("bad cell " & a1): Exit Function
        End If
        If r >= NR Or c >= NC Then RunCommand = Bad("outside the sheet"): Exit Function
        WantRedraw = False
        Select Case cmd
        Case "GETCELL": RunCommand = CellText(r, c)
        Case "GETFORMULA": RunCommand = GetSrc(r, c)
        Case Else
            If CellKind(r, c) = KNUM Then RunCommand = CStr(CellNum(r, c)) Else RunCommand = CellText(r, c)
        End Select
    Case "SETCELL"
        If Not ParseCellName(a1, r, c) Then RunCommand = Bad("bad cell " & a1): Exit Function
        SetCell r, c, RestAfter(line, 2)
        If LastError <> "" And Left$(RestAfter(line, 2), 1) = "=" Then ScriptRC = 5: RunCommand = LastError
    Case "SELECT", "GOTO"
        If Not ParseRange(a1, r1, c1, r2, c2) Then RunCommand = Bad("bad range " & a1): Exit Function
        SelectRange r1, c1, r2, c2
        RunCommand = SelName()
    Case "GETSELECTION"
        RunCommand = SelName()
        WantRedraw = False
    Case "CLEAR"
        If a1 <> "" Then
            If Not ParseRange(a1, r1, c1, r2, c2) Then RunCommand = Bad("bad range " & a1): Exit Function
        End If
        ClearRange r1, c1, r2, c2
    Case "COPY", "CUT"
        CopyRange r1, c1, r2, c2, cmd = "CUT"
    Case "PASTE"
        If a1 <> "" Then
            If Not ParseCellName(a1, r1, c1) Then RunCommand = Bad("bad cell " & a1): Exit Function
            r2 = r1: c2 = c1
        End If
        PasteAt r1, c1, r2 - r1 + 1, c2 - c1 + 1
    Case "FILLDOWN": FillDown r1, c1, r2, c2
    Case "FILLRIGHT": FillRight r1, c1, r2, c2
    Case "UNDO": Undo
    Case "REDO": Redo
    Case "FORMAT"
        k = FormatByName(a1)
        If k < 0 Then RunCommand = Bad("unknown format " & a1): Exit Function
        FormatRange r1, c1, r2, c2, 255, k
    Case "BOLD", "ITALIC"
        If cmd = "BOLD" Then k = FMT_BOLD Else k = FMT_ITALIC
        If UCase$(a1) = "OFF" Then
            FormatRange r1, c1, r2, c2, k, 0
        ElseIf UCase$(a1) = "ON" Then
            FormatRange r1, c1, r2, c2, k, k
        Else
            If (GetFormat(curR, curC) And k) <> 0 Then FormatRange r1, c1, r2, c2, k, 0 Else FormatRange r1, c1, r2, c2, k, k
        End If
    Case "ALIGN"
        Select Case UCase$(a1)
        Case "LEFT": k = AL_LEFT
        Case "CENTER", "CENTRE": k = AL_CENTER
        Case "RIGHT": k = AL_RIGHT
        Case "AUTO", "": k = AL_AUTO
        Case Else: RunCommand = Bad("ALIGN LEFT|CENTER|RIGHT|AUTO"): Exit Function
        End Select
        FormatRange r1, c1, r2, c2, 768, k * 256
    Case "COLWIDTH"
        If Not ParseCellName(a1 & "1", r, c) Then RunCommand = Bad("bad column " & a1): Exit Function
        If c >= NC Then RunCommand = Bad("bad column"): Exit Function
        If a2 = "" Then
            RunCommand = CStr(colW(c)): WantRedraw = False
        Else
            n = Val(a2)
            If n < 12 Then n = 12
            If n > 600 Then n = 600
            colW(c) = n
            Modified = True
        End If
    Case "INSERTROW", "DELETEROW", "INSERTCOL", "DELETECOL"
        n = Val(a1): If n < 1 Then n = 1
        Select Case cmd
        Case "INSERTROW": InsertRowsCols False, r1, n
        Case "DELETEROW": InsertRowsCols False, r1, -n
        Case "INSERTCOL": InsertRowsCols True, c1, n
        Case "DELETECOL": InsertRowsCols True, c1, -n
        End Select
    Case "SORT"
        If a1 = "" Then
            k = curC
        ElseIf ParseCellName(a1 & "1", r, k) Then
        Else
            RunCommand = Bad("SORT column [ASC|DESC]"): Exit Function
        End If
        If k < c1 Or k > c2 Then c1 = k: c2 = k
        SortRange r1, c1, r2, c2, k, UCase$(a2) <> "DESC"
    Case "CHART"
        Select Case UCase$(a1)
        Case "BAR": k = CH_BAR
        Case "LINE": k = CH_LINE
        Case "PIE": k = CH_PIE
        Case Else: RunCommand = Bad("CHART BAR|LINE|PIE range [title]"): Exit Function
        End Select
        If a2 = "" Then a2 = SelName()
        If Not ParseRange(a2, r1, c1, r2, c2) Then RunCommand = Bad("bad range " & a2): Exit Function
        n = AddChart(k, RangeName(r1, c1, r2, c2), RestAfter(line, 3))
        PlaceChart n, r1
        RunCommand = CStr(n)
    Case "DELCHART"
        If a1 = "" Then n = selChart Else n = Val(a1)
        If n < 0 Or n >= NCharts Then RunCommand = Bad("no such chart"): Exit Function
        RemoveChart n
        selChart = -1
    Case "CHARTS"
        RunCommand = CStr(NCharts): WantRedraw = False
    Case "NEW"
        NewSheet 1000, 26
        ClearCharts
        ViewInit vw, vh
        DocPath = ""
    Case "OPEN"
        s = RestAfter(line, 1)
        If LCase$(Right$(s, 4)) = ".csv" Then
            If Not ImportCsv(s) Then RunCommand = Bad(IOError): Exit Function
            DocPath = ""
        Else
            If Not LoadGws(s) Then RunCommand = Bad(IOError): Exit Function
            DocPath = s
        End If
        ViewInit vw, vh
    Case "SAVE", "SAVEAS"
        s = RestAfter(line, 1)
        If s = "" Then s = DocPath
        If s = "" Then RunCommand = Bad("no file name"): Exit Function
        If Not SaveGws(s) Then RunCommand = Bad(IOError): Exit Function
        DocPath = s
    Case "IMPORTCSV"
        If Not ImportCsv(RestAfter(line, 1)) Then RunCommand = Bad(IOError): Exit Function
        DocPath = ""
        ViewInit vw, vh
    Case "EXPORTCSV"
        If Not ExportCsv(RestAfter(line, 1), ",") Then RunCommand = Bad(IOError): Exit Function
    Case "RECALC"
        RecalcAll
        RunCommand = CStr(RecalcCount)
    Case "FIND"
        RunCommand = FindNext(RestAfter(line, 1), False)
        If RunCommand = "" Then ScriptRC = 5
    Case "SIZE"
        RunCommand = NR & " " & NC: WantRedraw = False
    Case "MODIFIED"
        RunCommand = CStr(-CLng(Modified)): WantRedraw = False
    Case "FILENAME"
        RunCommand = DocPath: WantRedraw = False
    Case "SHOWFORMULAS"
        ShowFormulas = (UCase$(a1) <> "OFF")
    Case "PRINT", "LOG"
        LogLines = LogLines & RestAfter(line, 1) & vbLf
        WantRedraw = False
    Case "SHOT"
        WantShot = RestAfter(line, 1)
    Case "QUIT"
        WantQuit = True
    Case "VERSION"
        RunCommand = "Gridwise 1.0": WantRedraw = False
    Case Else
        RunCommand = Bad("unknown command " & cmd)
        WantRedraw = False
    End Select
End Function

' put a new chart right of the used cells, below any chart already there
Public Sub PlaceChart(ByVal n As Long, ByVal r As Long)
    Dim mr As Long, mc As Long, i As Long, moved As Boolean, rows As Long
    UsedArea mr, mc
    chCol(n) = mc + 1
    If chCol(n) >= NC - 1 Then chCol(n) = 0
    chRow(n) = r
    rows = (chH(n) + ROW_H - 1) \ ROW_H + 1
    Do
        moved = False
        For i = 0 To NCharts - 1
            If i <> n Then
                If chCol(i) = chCol(n) And chRow(n) < chRow(i) + (chH(i) + ROW_H - 1) \ ROW_H + 1 And chRow(n) + rows > chRow(i) Then
                    chRow(n) = chRow(i) + (chH(i) + ROW_H - 1) \ ROW_H + 1
                    moved = True
                End If
            End If
        Next i
    Loop While moved
End Sub

' Find the next cell (after the cursor, row by row) whose shown text contains what
' (case-insensitive); moves the cursor there and returns its name, "" if none
Public Function FindNext(ByVal what As String, ByVal inFormulas As Boolean) As String
    Dim r As Long, c As Long, start As Long, id As Long, n As Long, s As String
    If what = "" Then Exit Function
    what = LCase$(what)
    start = curR * NC + curC
    For n = 1 To NCELLS
        id = (start + n) Mod NCELLS
        r = id \ NC: c = id Mod NC
        If inFormulas Then s = GetSrc(r, c) Else s = CellText(r, c)
        If s <> "" Then
            If InStr(LCase$(s), what) > 0 Then
                MoveCursor r, c, False
                FindNext = CellName(r, c)
                Exit Function
            End If
        End If
    Next n
End Function

' Run a script: one command per line; "> result" lines go to LogLines with ECHO
Public Function RunScript(ByVal text As String, ByVal echo As Boolean) As Long
    Dim lines() As String, i As Long, res As String, errs As Long
    lines = Split(Replace(text, vbCr, ""), vbLf)
    For i = 0 To UBound(lines)
        res = RunCommand(lines(i))
        If echo And Trim$(lines(i)) <> "" And Left$(Trim$(lines(i)), 1) <> ";" Then
            LogLines = LogLines & lines(i) & " -> " & res & IIf(ScriptRC > 0, " [rc " & ScriptRC & "]", "") & vbLf
        End If
        If ScriptRC >= 10 Then errs = errs + 1
        If WantQuit Then Exit For
    Next i
    RunScript = errs
End Function
