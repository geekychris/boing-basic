' Gridwise - files: the own format (.gws), CSV import/export.
'
' .gws is text, one record per line, fields separated by tabs (tabs, newlines and
' backslashes in fields escaped as \t \n \\):
'   GRIDWISE<tab>1
'   SIZE<tab>rows<tab>cols
'   W<tab>col<tab>width                 column width in pixels
'   C<tab>A1<tab>format<tab>what was typed
'   CHART<tab>type<tab>range<tab>title<tab>flags
Option Explicit

Public IOError As String

Private Function ReadAll(ByVal path As String) As String
    Dim fn As Integer, s As String
    ' (Open For Binary would create a missing file)
    If Dir(path) = "" Then Err.Raise 53, , "File not found: " & path
    fn = FreeFile
    Open path For Binary Access Read As #fn
    s = Space$(LOF(fn))
    Get #fn, , s
    Close #fn
    ReadAll = s
End Function

Private Sub WriteAll(ByVal path As String, ByVal s As String)
    Dim fn As Integer
    On Error Resume Next
    Kill path
    On Error GoTo 0
    fn = FreeFile
    Open path For Binary Access Write As #fn
    Put #fn, , s
    Close #fn
End Sub

Public Function SaveGws(ByVal path As String) As Boolean
    Dim s As String
    On Error GoTo Bad
    s = "GRIDWISE" & vbTab & "1" & vbLf & "SIZE" & vbTab & NR & vbTab & NC & vbLf
    s = s & SerializeSheet() & ChartsAsText()
    WriteAll path, s
    Modified = False
    SaveGws = True
    Exit Function
Bad:
    IOError = Err.Description
End Function

Public Function LoadGws(ByVal path As String) As Boolean
    Dim s As String, p As Long, lines() As String, f() As String, rows As Long, cols As Long, rest As String
    On Error GoTo Bad
    s = Replace(ReadAll(path), vbCr, "")
    If Left$(s, 9) <> "GRIDWISE" & vbTab Then IOError = "not a Gridwise sheet": Exit Function
    rows = 1000: cols = 26
    p = InStr(s, vbLf)
    s = Mid$(s, p + 1)
    If Left$(s, 5) = "SIZE" & vbTab Then
        p = InStr(s, vbLf)
        f = Split(Left$(s, p - 1), vbTab)
        rows = Val(f(1)): cols = Val(f(2))
        If rows < 1 Or rows > 65000 Then rows = 1000
        If cols < 1 Or cols > 676 Then cols = 26
        s = Mid$(s, p + 1)
    End If
    NewSheet rows, cols
    LoadLines s, rest
    ChartsFromText rest
    Modified = False
    ClearUndo
    LoadGws = True
    Exit Function
Bad:
    IOError = Err.Description
End Function

' ---- CSV ----------------------------------------------------------------------------------

Private Function CsvField(ByVal s As String, ByVal sep As String) As String
    If InStr(s, sep) > 0 Or InStr(s, Chr$(34)) > 0 Or InStr(s, vbLf) > 0 Or Left$(s, 1) = " " Or Right$(s, 1) = " " Then
        CsvField = Chr$(34) & Replace(s, Chr$(34), Chr$(34) & Chr$(34)) & Chr$(34)
    Else
        CsvField = s
    End If
End Function

' the used area as CSV: values (numbers unformatted, so they read back exactly) or,
' with formulas = True, what was typed
Public Function SheetAsCsv(ByVal sep As String, ByVal formulas As Boolean) As String
    Dim r As Long, c As Long, mr As Long, mc As Long, parts() As String, row As String, v As String, k As Long
    UsedArea mr, mc
    If mr < 0 Then Exit Function
    ReDim parts(0 To mr)
    For r = 0 To mr
        row = ""
        For c = 0 To mc
            If c > 0 Then row = row & sep
            If formulas Then
                v = GetSrc(r, c)
            Else
                k = CellKind(r, c)
                If k = KNUM And (GetFormat(r, c) And 255) = NF_GENERAL Then
                    v = CStr(CellNum(r, c))
                Else
                    v = CellText(r, c)
                End If
            End If
            row = row & CsvField(v, sep)
        Next c
        parts(r) = row
    Next r
    SheetAsCsv = Join(parts, vbLf) & vbLf
End Function

' the last used row and column (-1 if the sheet is empty)
Public Sub UsedArea(mr As Long, mc As Long)
    Dim r As Long, c As Long
    mr = -1: mc = -1
    For r = 0 To NR - 1
        For c = 0 To NC - 1
            If GetSrc(r, c) <> "" Then
                If r > mr Then mr = r
                If c > mc Then mc = c
            End If
        Next c
    Next r
End Sub

Public Function ExportCsv(ByVal path As String, ByVal sep As String) As Boolean
    On Error GoTo Bad
    WriteAll path, SheetAsCsv(sep, False)
    ExportCsv = True
    Exit Function
Bad:
    IOError = Err.Description
End Function

' Parse CSV text into rows of fields (RFC 4180: quotes, doubled quotes, newlines in quotes)
' and put it into the sheet at (r0, c0). Fields are entered as if typed, except that a
' field starting with "=" is kept as text unless allowFormulas.
Public Function CsvIntoSheet(ByVal s As String, ByVal sep As String, ByVal r0 As Long, ByVal c0 As Long, _
                             ByVal allowFormulas As Boolean) As Long
    Dim i As Long, n As Long, ch As String, fld As String, inq As Boolean, r As Long, c As Long, q As String
    Dim quoted As Boolean
    q = Chr$(34)
    s = Replace(s, vbCr & vbLf, vbLf)
    n = Len(s)
    i = 1
    BeginAction
    BeginBatch
    Do While i <= n
        ch = Mid$(s, i, 1)
        If inq Then
            If ch = q Then
                If Mid$(s, i + 1, 1) = q Then
                    fld = fld & q: i = i + 1
                Else
                    inq = False
                End If
            Else
                fld = fld & ch
            End If
        ElseIf ch = q Then
            inq = True: quoted = True
        ElseIf ch = sep Or ch = vbLf Then
            PutCsvField r0 + r, c0 + c, fld, quoted, allowFormulas
            fld = "": quoted = False
            If ch = sep Then
                c = c + 1
            Else
                r = r + 1: c = 0
            End If
        Else
            fld = fld & ch
        End If
        i = i + 1
    Loop
    If fld <> "" Or c > 0 Then PutCsvField r0 + r, c0 + c, fld, quoted, allowFormulas: r = r + 1
    EndBatch
    EndAction
    CsvIntoSheet = r
End Function

Private Sub PutCsvField(ByVal r As Long, ByVal c As Long, ByVal fld As String, ByVal quoted As Boolean, ByVal allowFormulas As Boolean)
    If fld = "" Then Exit Sub
    If Left$(fld, 1) = "'" Then
        fld = "'" & fld
    ElseIf Left$(fld, 1) = "=" And Not allowFormulas Then
        fld = "'" & fld
    End If
    SetCell r, c, fld
End Sub

' the separator a CSV file most likely uses: , ; or tab (from its first line)
Public Function GuessSeparator(ByVal s As String) As String
    Dim l As String, p As Long, nc As Long, ns As Long, nt As Long
    p = InStr(s, vbLf)
    If p > 0 Then l = Left$(s, p) Else l = s
    nc = Len(l) - Len(Replace(l, ",", ""))
    ns = Len(l) - Len(Replace(l, ";", ""))
    nt = Len(l) - Len(Replace(l, vbTab, ""))
    If nt > nc And nt >= ns Then
        GuessSeparator = vbTab
    ElseIf ns > nc Then
        GuessSeparator = ";"
    Else
        GuessSeparator = ","
    End If
End Function

Public Function ImportCsv(ByVal path As String) As Boolean
    Dim s As String, rows As Long, lines As Long
    On Error GoTo Bad
    s = ReadAll(path)
    lines = Len(s) - Len(Replace(s, vbLf, "")) + 1
    rows = 1000
    If lines + 10 > rows Then rows = lines + 10
    NewSheet rows, 26
    ClearCharts
    CsvIntoSheet s, GuessSeparator(s), 0, 0, False
    Modified = False
    ClearUndo
    ImportCsv = True
    Exit Function
Bad:
    IOError = Err.Description
End Function
