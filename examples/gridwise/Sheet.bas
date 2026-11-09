' Gridwise - the sheet: cells, evaluation, recalculation in dependency order,
' number formats, clipboard, undo/redo and structural edits. No drawing, no OS calls,
' so it runs (and is tested) on every platform.
'
' Cells are numbered id = row * NC + col (0-based). Each cell keeps what the user typed
' (cSrc), its value (cKind + cNum / cTxt) and its format (cFmt). A formula cell also has a
' compiled program in the code pool (cCode/cCodeLen), see Formula.bas.
'
' Recalculation: each formula registers its precedents (single cells in per-cell lists,
' ranges in per-column lists). A change marks every formula that depends on it, directly
' or not, then those are evaluated in dependency order by a depth-first walk of their
' precedents (post-order). A formula met again on its own path is circular (#CIRC!).
Option Explicit

' value kinds
Public Const KEMPTY As Long = 0
Public Const KNUM As Long = 1
Public Const KTEXT As Long = 2
Public Const KBOOL As Long = 3
Public Const KERR As Long = 4
Private Const KRANGE As Long = 5      ' only on the evaluation stack

' cFmt bits: number format (0..255), alignment (<< 8), bold (1024), italic (2048), colour (<< 16)
Public Const NF_GENERAL As Long = 0
Public Const NF_INT As Long = 1
Public Const NF_FIX2 As Long = 2
Public Const NF_THOUS As Long = 3
Public Const NF_THOUS2 As Long = 4
Public Const NF_PCT As Long = 5
Public Const NF_PCT2 As Long = 6
Public Const NF_CURRENCY As Long = 7
Public Const NF_SCI As Long = 8
Public Const NF_DATE As Long = 9
Public Const NF_TIME As Long = 10
Public Const NF_LAST As Long = 10
Public Const AL_AUTO As Long = 0
Public Const AL_LEFT As Long = 1
Public Const AL_CENTER As Long = 2
Public Const AL_RIGHT As Long = 3
Public Const FMT_BOLD As Long = 1024
Public Const FMT_ITALIC As Long = 2048

Public NR As Long                     ' rows
Public NC As Long                     ' columns
Public NCELLS As Long
Public cSrc() As String
Public cKind() As Long
Public cNum() As Double
Public cTxt() As String
Public cFmt() As Long
Public cCode() As Long                ' start in pCode, -1 = not a formula
Public cCodeLen() As Long
Public colW() As Long                 ' column widths in pixels (the UI's, saved with the sheet)
' the text each cell shows, cached (formatting numbers is the costly part of drawing):
' valid while cDispOk, the format is cDispFmt and the epoch is DispEpoch
Private cDisp() As String
Private cDispOk() As Boolean
Private cDispFmt() As Long
Private cDispEp() As Long
Private DispEpoch As Long
Public rowH() As Long                 ' row heights in pixels
Public Modified As Boolean
Public CurrencySymbol As String
Public LastError As String            ' why the last SetCell formula did not compile
Public RecalcCount As Long            ' formulas evaluated by the last recalculation
Public FormulaCount As Long

' code and constant pools
Private pCode() As Long
Private pCodeN As Long
Private pCodeLive As Long
Private pNum() As Double
Private pNumN As Long
Private pStr() As String
Private pStrN As Long

' dependencies on single cells: dHead(cell) -> node; node: dNext, dFrom (the formula)
Private dHead() As Long
Private dNext() As Long
Private dFrom() As Long
Private dFree As Long
Private dCap As Long
' dependencies on ranges, per column and block of 32 rows: rHead(col * NB + row \ 32) -> node;
' node: rNext, rFrom, rR1, rR2 (a range has a node in every bucket it covers)
Private NB As Long
Private rHead() As Long
Private rNext() As Long
Private rFrom() As Long
Private rR1() As Long
Private rR2() As Long
Private rFree As Long
Private rCap As Long

' recalculation
Private gen As Long
Private mark() As Long                ' = gen: dirty in this recalculation
Private vis() As Long                 ' = gen: on the DFS path or done
Private done() As Long                ' = gen: evaluated
Private circ() As Long                ' = gen: part of a cycle
Private dcGen() As Long               ' per column: = gen when it holds dirty formulas,
Private dcMin() As Long, dcMax() As Long  ' between these rows (so range walks skip the rest)
Private wl() As Long                  ' work list
Private dl() As Long                  ' dirty formula list
Private fsCell() As Long, fsPc() As Long, fsR() As Long, fsC() As Long  ' DFS frames
Private batchN As Long                ' > 0: SetCell collects changes, EndBatch recalculates
Private chg() As Long
Private chgN As Long

' evaluation stack
Private Const STK As Long = 128
Private sT(0 To 127) As Long
Private sN(0 To 127) As Double
Private sS(0 To 127) As String
Private sR1(0 To 127) As Long, sC1(0 To 127) As Long, sR2(0 To 127) As Long, sC2(0 To 127) As Long

' clipboard
Public clipRows As Long, clipCols As Long, clipR0 As Long, clipC0 As Long, clipCut As Boolean
Private clipSrc() As String
Private clipFmt() As Long

' undo/redo: entries (cell, old src/fmt, new src/fmt) in groups; a group with uCell = -1
' is a whole-sheet snapshot (structural edits)
Private uCell() As Long, uOld() As String, uNew() As String, uOldF() As Long, uNewF() As Long, uGrp() As Long
Private uN As Long                    ' entries in use (undo stack top)
Private uTop As Long                  ' entries valid for redo
Private uGroup As Long
Private uOpen As Boolean
Private uSuspend As Boolean
Public UndoLimit As Long

' ---- creating ------------------------------------------------------------------------------

Public Sub NewSheet(ByVal rows As Long, ByVal cols As Long)
    Dim i As Long
    NR = rows: NC = cols: NCELLS = rows * cols
    ReDim cSrc(0 To NCELLS - 1)
    ReDim cKind(0 To NCELLS - 1)
    ReDim cNum(0 To NCELLS - 1)
    ReDim cTxt(0 To NCELLS - 1)
    ReDim cFmt(0 To NCELLS - 1)
    ReDim cCode(0 To NCELLS - 1)
    ReDim cCodeLen(0 To NCELLS - 1)
    ReDim cDisp(0 To NCELLS - 1)
    ReDim cDispOk(0 To NCELLS - 1)
    ReDim cDispFmt(0 To NCELLS - 1)
    ReDim cDispEp(0 To NCELLS - 1)
    DispEpoch = DispEpoch + 1
    ReDim dHead(0 To NCELLS - 1)
    ReDim mark(0 To NCELLS - 1)
    ReDim vis(0 To NCELLS - 1)
    ReDim done(0 To NCELLS - 1)
    ReDim circ(0 To NCELLS - 1)
    NB = (rows + 31) \ 32
    ReDim rHead(0 To cols * NB - 1)
    ReDim dcGen(0 To cols - 1): ReDim dcMin(0 To cols - 1): ReDim dcMax(0 To cols - 1)
    ReDim colW(0 To cols - 1)
    ReDim rowH(0 To rows - 1)
    For i = 0 To rows - 1: rowH(i) = 15: Next i
    For i = 0 To NCELLS - 1
        cCode(i) = -1
        dHead(i) = -1
    Next i
    For i = 0 To cols * NB - 1: rHead(i) = -1: Next i
    For i = 0 To cols - 1
        colW(i) = 72
    Next i
    ReDim pCode(0 To 4095): pCodeN = 0: pCodeLive = 0
    ReDim pNum(0 To 1023): pNumN = 0
    ReDim pStr(0 To 255): pStrN = 0
    dCap = 1024: ReDim dNext(0 To dCap - 1): ReDim dFrom(0 To dCap - 1)
    For i = 0 To dCap - 2: dNext(i) = i + 1: Next i
    dNext(dCap - 1) = -1: dFree = 0
    rCap = 256: ReDim rNext(0 To rCap - 1): ReDim rFrom(0 To rCap - 1): ReDim rR1(0 To rCap - 1): ReDim rR2(0 To rCap - 1)
    For i = 0 To rCap - 2: rNext(i) = i + 1: Next i
    rNext(rCap - 1) = -1: rFree = 0
    ReDim wl(0 To 1023)
    ReDim dl(0 To 1023)
    ReDim fsCell(0 To 255): ReDim fsPc(0 To 255): ReDim fsR(0 To 255): ReDim fsC(0 To 255)
    ReDim chg(0 To 255): chgN = 0: batchN = 0
    gen = 0
    FormulaCount = 0
    Modified = False
    If CurrencySymbol = "" Then CurrencySymbol = "$"
    If UndoLimit = 0 Then UndoLimit = 20000
    ReDim uCell(0 To 255): ReDim uOld(0 To 255): ReDim uNew(0 To 255)
    ReDim uOldF(0 To 255): ReDim uNewF(0 To 255): ReDim uGrp(0 To 255)
    uN = 0: uTop = 0: uGroup = 0: uOpen = False
End Sub

Public Function CellId(ByVal r As Long, ByVal c As Long) As Long
    CellId = r * NC + c
End Function

' ---- setting cells --------------------------------------------------------------------------

' Set what a cell holds, as typed: "" clears it, "=..." is a formula, "'..." text,
' numbers ("12", "-3.5e2", "1,234", "15%"), TRUE/FALSE, anything else text.
Public Sub SetCell(ByVal r As Long, ByVal c As Long, ByVal src As String)
    Dim id As Long
    If r < 0 Or c < 0 Or r >= NR Or c >= NC Then Exit Sub
    id = r * NC + c
    If cSrc(id) = src Then Exit Sub
    RecordUndo id, src, cFmt(id)
    SetRaw id, src
    Modified = True
    NoteChange id
End Sub

' Set a cell's format bits (no recalculation needed)
Public Sub SetFormat(ByVal r As Long, ByVal c As Long, ByVal f As Long)
    Dim id As Long
    If r < 0 Or c < 0 Or r >= NR Or c >= NC Then Exit Sub
    id = r * NC + c
    If cFmt(id) = f Then Exit Sub
    RecordUndo id, cSrc(id), f
    cFmt(id) = f
    Modified = True
End Sub

Public Function GetFormat(ByVal r As Long, ByVal c As Long) As Long
    GetFormat = cFmt(r * NC + c)
End Function

Public Function GetSrc(ByVal r As Long, ByVal c As Long) As String
    If r < 0 Or c < 0 Or r >= NR Or c >= NC Then Exit Function
    GetSrc = cSrc(r * NC + c)
End Function

Private Sub NoteChange(ByVal id As Long)
    If chgN > UBound(chg) Then ReDim Preserve chg(0 To UBound(chg) * 2 + 1)
    chg(chgN) = id
    chgN = chgN + 1
    If batchN = 0 Then Recalc
End Sub

Public Sub BeginBatch()
    batchN = batchN + 1
End Sub

Public Sub EndBatch()
    batchN = batchN - 1
    If batchN <= 0 Then batchN = 0: Recalc
End Sub

' put src into the cell: parse or compile, (re)register dependencies
Private Sub SetRaw(ByVal id As Long, ByVal src As String)
    Dim t As String, d As Double, ok As Boolean, f As Long
    If cCode(id) >= 0 Then
        RemoveDeps id
        pCodeLive = pCodeLive - cCodeLen(id)
        cCode(id) = -1
        cCodeLen(id) = 0
        FormulaCount = FormulaCount - 1
    End If
    cSrc(id) = src
    cTxt(id) = ""
    cNum(id) = 0
    cDispOk(id) = False
    If src = "" Then cKind(id) = KEMPTY: Exit Sub
    If Asc(src) = 61 And Len(src) > 1 Then           ' "=" (Asc reads the first character without a Mid$)
        FormulaCount = FormulaCount + 1
        If Compile(src, 2) Then
            InstallCode id
            AddDeps id
            cKind(id) = KNUM
            LastError = ""
        Else
            ' keep it as a formula that shows #ERROR! until it is fixed
            InstallErr id
            LastError = compileErr
        End If
        Exit Sub
    End If
    If Asc(src) = 39 Then cKind(id) = KTEXT: cTxt(id) = Mid$(src, 2): Exit Sub
    If ParseNumber(src, d, f) Then
        cKind(id) = KNUM
        cNum(id) = d
        If f >= 0 And (cFmt(id) And 255) = NF_GENERAL Then cFmt(id) = (cFmt(id) And Not 255) Or f
        Exit Sub
    End If
    t = UCase$(src)
    If t = "TRUE" Then cKind(id) = KBOOL: cNum(id) = 1: Exit Sub
    If t = "FALSE" Then cKind(id) = KBOOL: cNum(id) = 0: Exit Sub
    cKind(id) = KTEXT
    cTxt(id) = src
End Sub

' A number as typed: digits with an optional sign, decimals, exponent, thousands commas,
' a trailing % (fmt = NF_PCT) or a leading currency symbol (fmt = NF_THOUS2). fmt is -1
' when the text sets no format.
Public Function ParseNumber(ByVal s As String, d As Double, fmt As Long) As Boolean
    Dim i As Long, n As Long, ch As Long, digits As Long, dots As Long, t As String, pct As Boolean, cur As Boolean
    Dim e As Long, commas As Boolean
    fmt = -1
    s = Trim$(s)
    n = Len(s)
    If n = 0 Then Exit Function
    If Right$(s, 1) = "%" Then pct = True: s = Left$(s, n - 1): n = n - 1
    If n > 0 And CurrencySymbol <> "" Then
        If Left$(s, Len(CurrencySymbol)) = CurrencySymbol Then cur = True: s = Mid$(s, Len(CurrencySymbol) + 1): n = Len(s)
    End If
    If n = 0 Then Exit Function
    For i = 1 To n
        ch = Asc(Mid$(s, i, 1))
        If ch >= 48 And ch <= 57 Then
            digits = digits + 1
        ElseIf ch = 46 Then
            If dots > 0 Or e > 0 Then Exit Function
            dots = 1
        ElseIf ch = 44 Then
            If dots > 0 Or digits = 0 Or e > 0 Then Exit Function
            commas = True
        ElseIf (ch = 45 Or ch = 43) Then
            If i <> 1 And e <> i - 1 Then Exit Function
        ElseIf (ch = 69 Or ch = 101) And digits > 0 And e = 0 Then
            e = i
        Else
            Exit Function
        End If
    Next i
    If digits = 0 Then Exit Function
    If e = n Then Exit Function
    If commas Then t = Replace(s, ",", "") Else t = s
    d = Val(t)
    If pct Then d = d / 100: fmt = NF_PCT
    If cur Then fmt = NF_CURRENCY
    ParseNumber = True
End Function

Private Sub InstallCode(ByVal id As Long)
    Dim i As Long, op As Long, need As Long
    need = pCodeN + outLen
    If need > UBound(pCode) Then
        If pCodeN > 2 * pCodeLive + 4096 Then CompactCode
        need = pCodeN + outLen
        If need > UBound(pCode) Then ReDim Preserve pCode(0 To need * 2)
    End If
    If pNumN + outNumN > UBound(pNum) Then ReDim Preserve pNum(0 To (pNumN + outNumN) * 2)
    If pStrN + outStrN > UBound(pStr) Then ReDim Preserve pStr(0 To (pStrN + outStrN) * 2)
    cCode(id) = pCodeN
    cCodeLen(id) = outLen
    i = 0
    Do While i < outLen
        op = outCode(i)
        pCode(pCodeN + i) = op
        Select Case op
        Case OP_NUM
            pCode(pCodeN + i + 1) = outCode(i + 1) + pNumN
            i = i + 2
        Case OP_STR
            pCode(pCodeN + i + 1) = outCode(i + 1) + pStrN
            i = i + 2
        Case OP_REF
            pCode(pCodeN + i + 1) = outCode(i + 1)
            pCode(pCodeN + i + 2) = outCode(i + 2)
            i = i + 3
        Case OP_RANGE
            pCode(pCodeN + i + 1) = outCode(i + 1)
            pCode(pCodeN + i + 2) = outCode(i + 2)
            pCode(pCodeN + i + 3) = outCode(i + 3)
            pCode(pCodeN + i + 4) = outCode(i + 4)
            i = i + 5
        Case OP_FUNC
            pCode(pCodeN + i + 1) = outCode(i + 1)
            pCode(pCodeN + i + 2) = outCode(i + 2)
            i = i + 3
        Case OP_BOOL, OP_ERR
            pCode(pCodeN + i + 1) = outCode(i + 1)
            i = i + 2
        Case OP_JF, OP_JMP
            pCode(pCodeN + i + 1) = outCode(i + 1)    ' relative to the cell's code start
            i = i + 2
        Case Else
            i = i + 1
        End Select
    Loop
    For i = 0 To outNumN - 1: pNum(pNumN + i) = outNum(i): Next i
    For i = 0 To outStrN - 1: pStr(pStrN + i) = outStr(i): Next i
    pNumN = pNumN + outNumN
    pStrN = pStrN + outStrN
    pCodeN = pCodeN + outLen
    pCodeLive = pCodeLive + outLen
End Sub

Private Sub InstallErr(ByVal id As Long)
    outLen = 0: outNumN = 0: outStrN = 0
    ReDim outCode(0 To 255)
    outCode(0) = OP_ERR: outCode(1) = E_SYNTAX: outLen = 2
    InstallCode id
    cKind(id) = KERR
    cNum(id) = E_SYNTAX
End Sub

' The code pool fills with dead programs as formulas are edited: recompile all live ones.
Private Sub CompactCode()
    Dim i As Long
    pCodeN = 0: pCodeLive = 0: pNumN = 0: pStrN = 0
    For i = 0 To NCELLS - 1
        If cCode(i) >= 0 Then
            If Compile(cSrc(i), 2) Then
                InstallCode i
            Else
                InstallErr i
            End If
        End If
    Next i
End Sub

' ---- dependencies --------------------------------------------------------------------------

Private Sub AddDeps(ByVal id As Long)
    Dim pc As Long, e As Long, op As Long, r1 As Long, c1 As Long, r2 As Long, c2 As Long, c As Long, n As Long
    Dim bk As Long
    pc = cCode(id): e = pc + cCodeLen(id)
    Do While pc < e
        op = pCode(pc)
        Select Case op
        Case OP_REF
            r1 = pCode(pc + 1): c1 = pCode(pc + 2)
            If r1 < NR And c1 < NC Then
                If dFree < 0 Then GrowD
                n = dFree: dFree = dNext(n)
                dFrom(n) = id
                dNext(n) = dHead(r1 * NC + c1)
                dHead(r1 * NC + c1) = n
            End If
            pc = pc + 3
        Case OP_RANGE
            r1 = pCode(pc + 1): c1 = pCode(pc + 2): r2 = pCode(pc + 3): c2 = pCode(pc + 4)
            If c2 >= NC Then c2 = NC - 1
            If r2 >= NR Then r2 = NR - 1
            For c = c1 To c2
                For bk = c * NB + r1 \ 32 To c * NB + r2 \ 32
                    If rFree < 0 Then GrowR
                    n = rFree: rFree = rNext(n)
                    rFrom(n) = id: rR1(n) = r1: rR2(n) = r2
                    rNext(n) = rHead(bk)
                    rHead(bk) = n
                Next bk
            Next c
            pc = pc + 5
        Case OP_NUM, OP_STR, OP_BOOL, OP_ERR, OP_JF, OP_JMP
            pc = pc + 2
        Case OP_FUNC
            pc = pc + 3
        Case Else
            pc = pc + 1
        End Select
    Loop
End Sub

Private Sub RemoveDeps(ByVal id As Long)
    Dim pc As Long, e As Long, op As Long, r1 As Long, c1 As Long, c2 As Long, c As Long
    Dim n As Long, prev As Long, nx As Long, cell As Long, bk As Long, r2 As Long
    pc = cCode(id): e = pc + cCodeLen(id)
    Do While pc < e
        op = pCode(pc)
        Select Case op
        Case OP_REF
            r1 = pCode(pc + 1): c1 = pCode(pc + 2)
            If r1 < NR And c1 < NC Then
                cell = r1 * NC + c1
                prev = -1: n = dHead(cell)
                Do While n >= 0
                    nx = dNext(n)
                    If dFrom(n) = id Then
                        If prev < 0 Then dHead(cell) = nx Else dNext(prev) = nx
                        dNext(n) = dFree: dFree = n
                        Exit Do
                    End If
                    prev = n
                    n = nx
                Loop
            End If
            pc = pc + 3
        Case OP_RANGE
            r1 = pCode(pc + 1): c1 = pCode(pc + 2): r2 = pCode(pc + 3): c2 = pCode(pc + 4)
            If c2 >= NC Then c2 = NC - 1
            If r2 >= NR Then r2 = NR - 1
            For c = c1 To c2
                For bk = c * NB + r1 \ 32 To c * NB + r2 \ 32
                    prev = -1: n = rHead(bk)
                    Do While n >= 0
                        nx = rNext(n)
                        If rFrom(n) = id Then
                            If prev < 0 Then rHead(bk) = nx Else rNext(prev) = nx
                            rNext(n) = rFree: rFree = n
                            Exit Do
                        End If
                        prev = n
                        n = nx
                    Loop
                Next bk
            Next c
            pc = pc + 5
        Case OP_NUM, OP_STR, OP_BOOL, OP_ERR, OP_JF, OP_JMP
            pc = pc + 2
        Case OP_FUNC
            pc = pc + 3
        Case Else
            pc = pc + 1
        End Select
    Loop
End Sub

Private Sub GrowD()
    Dim i As Long, old As Long
    old = dCap: dCap = dCap * 2
    ReDim Preserve dNext(0 To dCap - 1): ReDim Preserve dFrom(0 To dCap - 1)
    For i = old To dCap - 2: dNext(i) = i + 1: Next i
    dNext(dCap - 1) = -1: dFree = old
End Sub

Private Sub GrowR()
    Dim i As Long, old As Long
    old = rCap: rCap = rCap * 2
    ReDim Preserve rNext(0 To rCap - 1): ReDim Preserve rFrom(0 To rCap - 1)
    ReDim Preserve rR1(0 To rCap - 1): ReDim Preserve rR2(0 To rCap - 1)
    For i = old To rCap - 2: rNext(i) = i + 1: Next i
    rNext(rCap - 1) = -1: rFree = old
End Sub

' ---- recalculation -----------------------------------------------------------------------------

Public Sub RecalcAll()
    Dim i As Long
    chgN = 0
    For i = 0 To NCELLS - 1
        If cCode(i) >= 0 Then
            If chgN > UBound(chg) Then ReDim Preserve chg(0 To UBound(chg) * 2 + 1)
            chg(chgN) = i
            chgN = chgN + 1
        End If
    Next i
    Recalc
End Sub

' Recalculate everything that depends on the cells in chg(0 .. chgN-1)
Private Sub Recalc()
    Dim nw As Long, ndl As Long, i As Long, x As Long, y As Long, n As Long, r As Long, c As Long
    gen = gen + 1
    nw = 0: ndl = 0
    For i = 0 To chgN - 1
        x = chg(i)
        If mark(x) <> gen Then
            mark(x) = gen
            If nw > UBound(wl) Then ReDim Preserve wl(0 To UBound(wl) * 2 + 1)
            wl(nw) = x: nw = nw + 1
            If cCode(x) >= 0 Then
                If ndl > UBound(dl) Then ReDim Preserve dl(0 To UBound(dl) * 2 + 1)
                dl(ndl) = x: ndl = ndl + 1
            End If
        End If
    Next i
    chgN = 0
    ' everything that depends on a marked cell is marked too
    Do While nw > 0
        nw = nw - 1
        x = wl(nw)
        r = x \ NC
        c = x - r * NC
        n = dHead(x)
        Do While n >= 0
            y = dFrom(n)
            If mark(y) <> gen Then
                mark(y) = gen
                If nw > UBound(wl) Then ReDim Preserve wl(0 To UBound(wl) * 2 + 1)
                wl(nw) = y: nw = nw + 1
                If ndl > UBound(dl) Then ReDim Preserve dl(0 To UBound(dl) * 2 + 1)
                dl(ndl) = y: ndl = ndl + 1
            End If
            n = dNext(n)
        Loop
        n = rHead(c * NB + r \ 32)
        Do While n >= 0
            If r >= rR1(n) Then
                If r <= rR2(n) Then
                    y = rFrom(n)
                    If mark(y) <> gen Then
                        mark(y) = gen
                        If nw > UBound(wl) Then ReDim Preserve wl(0 To UBound(wl) * 2 + 1)
                        wl(nw) = y: nw = nw + 1
                        If ndl > UBound(dl) Then ReDim Preserve dl(0 To UBound(dl) * 2 + 1)
                        dl(ndl) = y: ndl = ndl + 1
                    End If
                End If
            End If
            n = rNext(n)
        Loop
    Loop
    RecalcCount = ndl
    For i = 0 To ndl - 1
        x = dl(i)
        r = x \ NC
        c = x - r * NC
        If dcGen(c) <> gen Then
            dcGen(c) = gen: dcMin(c) = r: dcMax(c) = r
        Else
            If r < dcMin(c) Then dcMin(c) = r
            If r > dcMax(c) Then dcMax(c) = r
        End If
    Next i
    For i = 0 To ndl - 1
        If vis(dl(i)) <> gen Then Visit dl(i)
    Next i
End Sub

' depth-first over the dirty precedents of cell x, evaluating each cell after its precedents
Private Sub Visit(ByVal x As Long)
    Dim sp As Long, cell As Long, pc As Long, e As Long, op As Long, y As Long, r As Long, c As Long
    Dim r2 As Long, c2 As Long, pushed As Boolean, rr As Long
    sp = 0
    fsCell(0) = x: fsPc(0) = cCode(x): fsR(0) = -1
    vis(x) = gen
    Do While sp >= 0
        cell = fsCell(sp)
        pc = fsPc(sp)
        e = cCode(cell) + cCodeLen(cell)
        pushed = False
        Do While pc < e And Not pushed
            op = pCode(pc)
            If op = OP_REF Then
                r = pCode(pc + 1): c = pCode(pc + 2)
                pc = pc + 3
                If r < NR And c < NC Then
                    y = r * NC + c
                    If mark(y) = gen Then
                        If cCode(y) >= 0 And done(y) <> gen Then
                            If vis(y) = gen Then
                                circ(cell) = gen
                            Else
                                fsPc(sp) = pc
                                pushed = True
                            End If
                        End If
                    End If
                End If
            ElseIf op = OP_RANGE Then
                ' walk the range's dirty formula cells, column by column, only between the
                ' rows where that column has dirty formulas; fsC/fsR remember where we are
                r2 = pCode(pc + 3): c2 = pCode(pc + 4)
                If r2 >= NR Then r2 = NR - 1
                If c2 >= NC Then c2 = NC - 1
                If fsR(sp) < 0 Then
                    c = pCode(pc + 2): r = -1
                Else
                    c = fsC(sp): r = fsR(sp)
                End If
                Do While c <= c2 And Not pushed
                    If dcGen(c) = gen Then
                        If r < 0 Then
                            r = pCode(pc + 1)
                            If dcMin(c) > r Then r = dcMin(c)
                        End If
                        rr = r2
                        If dcMax(c) < rr Then rr = dcMax(c)
                        Do While r <= rr
                            y = r * NC + c
                            r = r + 1
                            If mark(y) = gen Then
                                If cCode(y) >= 0 And done(y) <> gen Then
                                    If vis(y) = gen Then
                                        circ(cell) = gen
                                    Else
                                        pushed = True
                                        Exit Do
                                    End If
                                End If
                            End If
                        Loop
                    End If
                    If Not pushed Then
                        c = c + 1
                        r = -1
                    End If
                Loop
                If pushed Then
                    fsR(sp) = r: fsC(sp) = c
                    fsPc(sp) = pc
                Else
                    fsR(sp) = -1
                    pc = pc + 5
                End If
            ElseIf op = OP_NUM Or op = OP_STR Or op = OP_BOOL Or op = OP_ERR Or op = OP_JF Or op = OP_JMP Then
                pc = pc + 2
            ElseIf op = OP_FUNC Then
                pc = pc + 3
            Else
                pc = pc + 1
            End If
        Loop
        If pushed Then
            sp = sp + 1
            If sp > UBound(fsCell) Then
                ReDim Preserve fsCell(0 To sp * 2): ReDim Preserve fsPc(0 To sp * 2)
                ReDim Preserve fsR(0 To sp * 2): ReDim Preserve fsC(0 To sp * 2)
            End If
            fsCell(sp) = y: fsPc(sp) = cCode(y): fsR(sp) = -1
            vis(y) = gen
        Else
            EvalCell cell
            done(cell) = gen
            sp = sp - 1
        End If
    Loop
End Sub

' ---- evaluation ------------------------------------------------------------------------------

Private Sub EvalCell(ByVal id As Long)
    Dim pc As Long, base As Long, e As Long, op As Long, sp As Long, r As Long, c As Long, y As Long
    Dim a As Double, b As Double, k As Long
    cDispOk(id) = False
    If circ(id) = gen Then cKind(id) = KERR: cNum(id) = E_CIRC: cTxt(id) = "": Exit Sub
    base = cCode(id)
    pc = base
    e = base + cCodeLen(id)
    sp = -1
    Do While pc < e
        op = pCode(pc)
        Select Case op
        Case OP_NUM
            sp = sp + 1
            sT(sp) = KNUM: sN(sp) = pNum(pCode(pc + 1))
            pc = pc + 2
        Case OP_REF
            sp = sp + 1
            r = pCode(pc + 1): c = pCode(pc + 2)
            If r < NR And c < NC Then
                y = r * NC + c
                k = cKind(y)
                sT(sp) = k
                sN(sp) = cNum(y)
                If k = KTEXT Then sS(sp) = cTxt(y)
            Else
                sT(sp) = KERR: sN(sp) = E_REF
            End If
            pc = pc + 3
        Case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_POW
            If sT(sp) = KNUM And sT(sp - 1) = KNUM Then
                a = sN(sp - 1): b = sN(sp)
            Else
                If Not Num2(sp - 1, sp, a, b) Then
                    sp = sp - 1
                    pc = pc + 1
                    GoTo NextOp
                End If
            End If
            sp = sp - 1
            sT(sp) = KNUM
            Select Case op
            Case OP_ADD: sN(sp) = a + b
            Case OP_SUB: sN(sp) = a - b
            Case OP_MUL: sN(sp) = a * b
            Case OP_DIV
                If b = 0 Then
                    sT(sp) = KERR: sN(sp) = E_DIV0
                Else
                    sN(sp) = a / b
                End If
            Case OP_POW
                SafePow sp, a, b
            End Select
            pc = pc + 1
        Case OP_STR
            sp = sp + 1
            sT(sp) = KTEXT: sS(sp) = pStr(pCode(pc + 1))
            pc = pc + 2
        Case OP_RANGE
            sp = sp + 1
            sT(sp) = KRANGE
            sR1(sp) = pCode(pc + 1): sC1(sp) = pCode(pc + 2): sR2(sp) = pCode(pc + 3): sC2(sp) = pCode(pc + 4)
            pc = pc + 5
        Case OP_CAT
            If Not Str2(sp - 1, sp) Then
                sp = sp - 1
            Else
                sp = sp - 1
                sS(sp) = sS(sp) & sS(sp + 1)
                sT(sp) = KTEXT
            End If
            pc = pc + 1
        Case OP_EQ, OP_NE, OP_LT, OP_GT, OP_LE, OP_GE
            k = Compare(sp - 1, sp)
            sp = sp - 1
            If k = 99 Then
                ' error kept in slot sp by Compare
            Else
                sT(sp) = KBOOL
                Select Case op
                Case OP_EQ: sN(sp) = -(k = 0)
                Case OP_NE: sN(sp) = -(k <> 0)
                Case OP_LT: sN(sp) = -(k < 0)
                Case OP_GT: sN(sp) = -(k > 0)
                Case OP_LE: sN(sp) = -(k <= 0)
                Case OP_GE: sN(sp) = -(k >= 0)
                End Select
            End If
            pc = pc + 1
        Case OP_NEG
            If ToNum(sp, a) Then sT(sp) = KNUM: sN(sp) = -a
            pc = pc + 1
        Case OP_PCT
            If ToNum(sp, a) Then sT(sp) = KNUM: sN(sp) = a / 100
            pc = pc + 1
        Case OP_FUNC
            k = pCode(pc + 2)
            CallFunc pCode(pc + 1), sp - k + 1, k
            sp = sp - k + 1
            pc = pc + 3
        Case OP_BOOL
            sp = sp + 1
            sT(sp) = KBOOL: sN(sp) = pCode(pc + 1)
            pc = pc + 2
        Case OP_ERR
            sp = sp + 1
            sT(sp) = KERR: sN(sp) = pCode(pc + 1)
            pc = pc + 2
        Case OP_JF
            If Truth(sp, k) Then
                If k = 0 Then pc = base + pCode(pc + 1) Else pc = pc + 2
                sp = sp - 1
            Else
                ' an error: it is the result
                Exit Do
            End If
        Case OP_JMP
            pc = base + pCode(pc + 1)
        Case Else
            pc = pc + 1
        End Select
NextOp:
        If sp >= STK - 8 Then sT(0) = KERR: sN(0) = E_NUM: sp = 0: Exit Do
    Loop
    If sp < 0 Then cKind(id) = KERR: cNum(id) = E_SYNTAX: Exit Sub
    Deref sp
    k = sT(sp)
    cKind(id) = k
    cNum(id) = sN(sp)
    If k = KTEXT Then cTxt(id) = sS(sp) Else cTxt(id) = ""
    If k = KNUM Then
        If cNum(id) <> cNum(id) Then cKind(id) = KERR: cNum(id) = E_NUM
    End If
End Sub

Private Sub SafePow(ByVal sp As Long, ByVal a As Double, ByVal b As Double)
    On Error GoTo Bad
    If a = 0 And b < 0 Then sT(sp) = KERR: sN(sp) = E_DIV0: Exit Sub
    If a < 0 And b <> Int(b) Then sT(sp) = KERR: sN(sp) = E_NUM: Exit Sub
    sN(sp) = a ^ b
    Exit Sub
Bad:
    sT(sp) = KERR: sN(sp) = E_NUM
End Sub

' a range on the stack that is a single cell becomes that cell's value; a larger one #VALUE!
Private Sub Deref(ByVal i As Long)
    Dim y As Long
    If sT(i) <> KRANGE Then Exit Sub
    If sR1(i) = sR2(i) And sC1(i) = sC2(i) And sR1(i) < NR And sC1(i) < NC Then
        y = sR1(i) * NC + sC1(i)
        sT(i) = cKind(y): sN(i) = cNum(y): sS(i) = cTxt(y)
    Else
        sT(i) = KERR: sN(i) = E_VALUE
    End If
End Sub

' slot i as a number; on failure slot i holds the error and False is returned
Private Function ToNum(ByVal i As Long, d As Double) As Boolean
    Dim k As Long
    k = sT(i)
    If k = KRANGE Then Deref i: k = sT(i)
    Select Case k
    Case KNUM, KBOOL
        d = sN(i): ToNum = True
    Case KEMPTY
        d = 0: ToNum = True
    Case KTEXT
        Dim f As Long
        If ParseNumber(sS(i), d, f) Then
            ToNum = True
        ElseIf sS(i) = "" Then
            d = 0: ToNum = True
        Else
            sT(i) = KERR: sN(i) = E_VALUE
        End If
    Case Else
        ' KERR stays
    End Select
End Function

' both operands as numbers; on failure the error is put into slot i (the result slot)
Private Function Num2(ByVal i As Long, ByVal j As Long, a As Double, b As Double) As Boolean
    If Not ToNum(i, a) Then Exit Function
    If Not ToNum(j, b) Then sT(i) = sT(j): sN(i) = sN(j): Exit Function
    Num2 = True
End Function

Private Function ToStr(ByVal i As Long) As Boolean
    Select Case sT(i)
    Case KRANGE
        Deref i
        ToStr = ToStr(i)
    Case KTEXT
        ToStr = True
    Case KNUM
        sS(i) = GeneralText(sN(i)): sT(i) = KTEXT: ToStr = True
    Case KBOOL
        If sN(i) <> 0 Then sS(i) = "TRUE" Else sS(i) = "FALSE"
        sT(i) = KTEXT: ToStr = True
    Case KEMPTY
        sS(i) = "": sT(i) = KTEXT: ToStr = True
    Case Else
    End Select
End Function

Private Function Str2(ByVal i As Long, ByVal j As Long) As Boolean
    If Not ToStr(i) Then Exit Function
    If Not ToStr(j) Then sT(i) = sT(j): sN(i) = sN(j): Exit Function
    Str2 = True
End Function

' compare slots i and j: -1, 0, 1, or 99 with the error in slot i
Private Function Compare(ByVal i As Long, ByVal j As Long) As Long
    Dim ki As Long, kj As Long, a As String, b As String
    Deref i: Deref j
    ki = sT(i): kj = sT(j)
    If ki = KERR Then Compare = 99: Exit Function
    If kj = KERR Then sT(i) = KERR: sN(i) = sN(j): Compare = 99: Exit Function
    If ki = KEMPTY Then
        If kj = KTEXT Then ki = KTEXT: sS(i) = "" Else ki = KNUM: sN(i) = 0
    End If
    If kj = KEMPTY Then
        If ki = KTEXT Then kj = KTEXT: sS(j) = "" Else kj = KNUM: sN(j) = 0
    End If
    If ki = KTEXT And kj = KTEXT Then
        a = LCase$(sS(i)): b = LCase$(sS(j))
        If a < b Then Compare = -1 Else If a > b Then Compare = 1 Else Compare = 0
    ElseIf ki = KTEXT Then
        Compare = 1                     ' text sorts after numbers (Excel)
    ElseIf kj = KTEXT Then
        Compare = -1
    Else
        If sN(i) < sN(j) Then Compare = -1 Else If sN(i) > sN(j) Then Compare = 1 Else Compare = 0
    End If
End Function

' slot i as a truth value (k = 0/1); False with the error in slot i
Private Function Truth(ByVal i As Long, k As Long) As Boolean
    Dim d As Double
    Deref i
    If sT(i) = KTEXT Then
        If UCase$(sS(i)) = "TRUE" Then k = 1: Truth = True: Exit Function
        If UCase$(sS(i)) = "FALSE" Then k = 0: Truth = True: Exit Function
    End If
    If Not ToNum(i, d) Then Exit Function
    If d <> 0 Then k = 1 Else k = 0
    Truth = True
End Function

' ---- functions ----------------------------------------------------------------------------------

Private Sub SetErr(ByVal i As Long, ByVal e As Long)
    sT(i) = KERR: sN(i) = e
End Sub

Private Sub SetNum(ByVal i As Long, ByVal d As Double)
    sT(i) = KNUM: sN(i) = d
End Sub

Private Sub SetStr(ByVal i As Long, ByVal s As String)
    sT(i) = KTEXT: sS(i) = s
End Sub

' the first error among the arguments, as Excel propagates them (0 = none)
Private Function ArgErr(ByVal b As Long, ByVal n As Long) As Long
    Dim i As Long
    For i = b To b + n - 1
        If sT(i) = KERR Then ArgErr = sN(i): Exit Function
    Next i
End Function

' numbers of the arguments (ranges: their numeric cells) -> accumulate
' mode 0 sum, 1 count, 2 min, 3 max, 4 product, 5 counta, 6 countblank
Private Function Aggregate(ByVal b As Long, ByVal n As Long, ByVal mode As Long, cnt As Long, errc As Long) As Double
    Dim i As Long, r As Long, c As Long, y As Long, k As Long, acc As Double, d As Double, first As Boolean
    Dim r2 As Long, c2 As Long
    first = True
    If mode = 4 Then acc = 1
    For i = b To b + n - 1
        If sT(i) = KRANGE Then
            r2 = sR2(i): c2 = sC2(i)
            If r2 >= NR Then r2 = NR - 1
            If c2 >= NC Then c2 = NC - 1
            For r = sR1(i) To r2
                y = r * NC + sC1(i)
                For c = sC1(i) To c2
                    k = cKind(y)
                    If k = KNUM Then
                        d = cNum(y)
                        cnt = cnt + 1
                        Select Case mode
                        Case 0: acc = acc + d
                        Case 2: If first Or d < acc Then acc = d
                        Case 3: If first Or d > acc Then acc = d
                        Case 4: acc = acc * d
                        End Select
                        first = False
                    ElseIf k = KERR Then
                        If mode <> 1 And mode <> 5 And mode <> 6 Then
                            If errc = 0 Then errc = cNum(y)
                        ElseIf mode = 5 Then
                            cnt = cnt + 1
                        End If
                    ElseIf k = KEMPTY Then
                        If mode = 6 Then cnt = cnt + 1
                    ElseIf mode = 5 Then
                        cnt = cnt + 1
                    ElseIf mode = 6 Then
                        If k = KTEXT Then If cTxt(y) = "" Then cnt = cnt + 1
                    End If
                    y = y + 1
                Next c
            Next r
        Else
            If mode = 5 Then
                If sT(i) <> KEMPTY Then cnt = cnt + 1
            ElseIf mode = 1 Then
                If sT(i) = KNUM Or sT(i) = KBOOL Then
                    cnt = cnt + 1
                ElseIf sT(i) = KTEXT Then
                    If ToNum(i, d) Then cnt = cnt + 1
                End If
            ElseIf mode = 6 Then
                If sT(i) = KEMPTY Then cnt = cnt + 1
            ElseIf sT(i) = KEMPTY Then
            ElseIf ToNum(i, d) Then
                cnt = cnt + 1
                Select Case mode
                Case 0: acc = acc + d
                Case 2: If first Or d < acc Then acc = d
                Case 3: If first Or d > acc Then acc = d
                Case 4: acc = acc * d
                End Select
                first = False
            Else
                If errc = 0 Then errc = sN(i)
            End If
        End If
    Next i
    Aggregate = acc
End Function

' the numbers of the arguments as a list (MEDIAN, STDEV)
Private Function NumList(ByVal b As Long, ByVal n As Long, v() As Double, errc As Long) As Long
    Dim i As Long, r As Long, c As Long, y As Long, cnt As Long, d As Double, r2 As Long, c2 As Long
    ReDim v(0 To 63)
    For i = b To b + n - 1
        If sT(i) = KRANGE Then
            r2 = sR2(i): c2 = sC2(i)
            If r2 >= NR Then r2 = NR - 1
            If c2 >= NC Then c2 = NC - 1
            For r = sR1(i) To r2
                For c = sC1(i) To c2
                    y = r * NC + c
                    If cKind(y) = KNUM Then
                        If cnt > UBound(v) Then ReDim Preserve v(0 To cnt * 2)
                        v(cnt) = cNum(y): cnt = cnt + 1
                    ElseIf cKind(y) = KERR Then
                        If errc = 0 Then errc = cNum(y)
                    End If
                Next c
            Next r
        ElseIf sT(i) <> KEMPTY Then
            If ToNum(i, d) Then
                If cnt > UBound(v) Then ReDim Preserve v(0 To cnt * 2)
                v(cnt) = d: cnt = cnt + 1
            ElseIf errc = 0 Then
                errc = sN(i)
            End If
        End If
    Next i
    NumList = cnt
End Function

' does a cell value (kind k, number d, text s) match an Excel criterion (">5", "<>x", "apple", 3)?
Private Function Matches(ByVal k As Long, ByVal d As Double, ByVal s As String, ByVal crit As String, _
                         ByVal critIsNum As Boolean, ByVal critNum As Double) As Boolean
    Dim op As String, rest As String, cv As Double, f As Long, cmp As Long, isn As Boolean
    If critIsNum Then
        Matches = (k = KNUM And d = critNum)
        Exit Function
    End If
    op = ""
    If Left$(crit, 2) = "<=" Or Left$(crit, 2) = ">=" Or Left$(crit, 2) = "<>" Then
        op = Left$(crit, 2): rest = Mid$(crit, 3)
    ElseIf Left$(crit, 1) = "<" Or Left$(crit, 1) = ">" Or Left$(crit, 1) = "=" Then
        op = Left$(crit, 1): rest = Mid$(crit, 2)
    Else
        op = "=": rest = crit
    End If
    isn = ParseNumber(rest, cv, f)
    If isn Then
        If k <> KNUM Then
            Matches = (op = "<>")
            Exit Function
        End If
        If d < cv Then cmp = -1 Else If d > cv Then cmp = 1 Else cmp = 0
    Else
        If k = KNUM Or k = KBOOL Then
            If op = "<>" Then Matches = True
            Exit Function
        End If
        If k = KEMPTY Then s = ""
        If InStr(rest, "*") > 0 Or InStr(rest, "?") > 0 Then
            If LCase$(s) Like LCase$(rest) Then cmp = 0 Else cmp = 1
        Else
            s = LCase$(s): rest = LCase$(rest)
            If s < rest Then cmp = -1 Else If s > rest Then cmp = 1 Else cmp = 0
        End If
    End If
    Select Case op
    Case "=": Matches = (cmp = 0)
    Case "<>": Matches = (cmp <> 0)
    Case "<": Matches = (cmp < 0)
    Case ">": Matches = (cmp > 0)
    Case "<=": Matches = (cmp <= 0)
    Case ">=": Matches = (cmp >= 0)
    End Select
End Function

' SUMIF / COUNTIF / AVERAGEIF: mode 0 sum, 1 count, 2 average
Private Sub CondAgg(ByVal b As Long, ByVal n As Long, ByVal mode As Long)
    Dim crit As String, critIsNum As Boolean, critNum As Double, r As Long, c As Long, y As Long, ys As Long
    Dim acc As Double, cnt As Long, dr As Long, dc As Long, hasSum As Boolean, r2 As Long, c2 As Long
    If sT(b) <> KRANGE Then SetErr b, E_VALUE: Exit Sub
    If sT(b + 1) = KRANGE Then Deref b + 1
    If sT(b + 1) = KERR Then SetErr b, sN(b + 1): Exit Sub
    If sT(b + 1) = KNUM Then
        critIsNum = True: critNum = sN(b + 1)
    Else
        ToStr b + 1
        crit = sS(b + 1)
    End If
    If n = 3 Then
        If sT(b + 2) <> KRANGE Then SetErr b, E_VALUE: Exit Sub
        hasSum = True
        dr = sR1(b + 2) - sR1(b): dc = sC1(b + 2) - sC1(b)
    End If
    r2 = sR2(b): c2 = sC2(b)
    If r2 >= NR Then r2 = NR - 1
    If c2 >= NC Then c2 = NC - 1
    For r = sR1(b) To r2
        For c = sC1(b) To c2
            y = r * NC + c
            If Matches(cKind(y), cNum(y), cTxt(y), crit, critIsNum, critNum) Then
                If mode = 1 Then
                    cnt = cnt + 1
                Else
                    If hasSum Then
                        If r + dr < NR And c + dc < NC Then ys = (r + dr) * NC + c + dc Else ys = -1
                    Else
                        ys = y
                    End If
                    If ys >= 0 Then
                        If cKind(ys) = KNUM Then acc = acc + cNum(ys): cnt = cnt + 1
                    End If
                End If
            End If
        Next c
    Next r
    Select Case mode
    Case 0: SetNum b, acc
    Case 1: SetNum b, cnt
    Case 2: If cnt = 0 Then SetErr b, E_DIV0 Else SetNum b, acc / cnt
    End Select
End Sub

Private Function RoundTo(ByVal x As Double, ByVal digits As Long, ByVal mode As Long) As Double
    ' mode 0 half away from zero (Excel ROUND), 1 up (away from 0), 2 down (towards 0)
    Dim m As Double, y As Double
    m = 10 ^ digits
    y = Abs(x) * m
    Select Case mode
    Case 0: y = Int(y + 0.5 + 0.0000000001 * y)
    Case 1
        If y - Int(y) > 0.0000000001 Then y = Int(y) + 1 Else y = Int(y)
    Case 2: y = Int(y + 0.0000000001 * y)
    End Select
    y = y / m
    If x < 0 Then y = -y
    RoundTo = y
End Function

Private Sub CallFunc(ByVal f As Long, ByVal b As Long, ByVal n As Long)
    Dim d As Double, d2 As Double, cnt As Long, errc As Long, k As Long, i As Long, s As String, t As String
    Dim v() As Double, m As Long, j As Long, tmp As Double
    If n = 0 Then
        ' functions without arguments push their result
        Select Case f
        Case F_PI: SetNum b, 3.14159265358979
        Case F_TODAY: SetNum b, Int(CDbl(Now))
        Case F_NOW: SetNum b, CDbl(Now)
        Case F_NA: SetErr b, E_NA
        Case Else: SetErr b, E_VALUE
        End Select
        Exit Sub
    End If
    Select Case f
    Case F_SUM, F_AVERAGE, F_MIN, F_MAX, F_COUNT, F_COUNTA, F_PRODUCT, F_COUNTBLANK
        Select Case f
        Case F_SUM, F_AVERAGE: m = 0
        Case F_MIN: m = 2
        Case F_MAX: m = 3
        Case F_COUNT: m = 1
        Case F_COUNTA: m = 5
        Case F_PRODUCT: m = 4
        Case F_COUNTBLANK: m = 6
        End Select
        d = Aggregate(b, n, m, cnt, errc)
        If errc <> 0 Then SetErr b, errc: Exit Sub
        Select Case f
        Case F_AVERAGE: If cnt = 0 Then SetErr b, E_DIV0 Else SetNum b, d / cnt
        Case F_COUNT, F_COUNTA, F_COUNTBLANK: SetNum b, cnt
        Case F_MIN, F_MAX: If cnt = 0 Then SetNum b, 0 Else SetNum b, d
        Case Else: SetNum b, d
        End Select
    Case F_MEDIAN, F_STDEV
        cnt = NumList(b, n, v, errc)
        If errc <> 0 Then SetErr b, errc: Exit Sub
        If f = F_MEDIAN Then
            If cnt = 0 Then SetErr b, E_NUM: Exit Sub
            For i = 1 To cnt - 1              ' insertion sort: lists are small
                tmp = v(i): j = i - 1
                Do While j >= 0
                    If v(j) <= tmp Then Exit Do
                    v(j + 1) = v(j): j = j - 1
                Loop
                v(j + 1) = tmp
            Next i
            If cnt Mod 2 = 1 Then SetNum b, v(cnt \ 2) Else SetNum b, (v(cnt \ 2 - 1) + v(cnt \ 2)) / 2
        Else
            If cnt < 2 Then SetErr b, E_DIV0: Exit Sub
            d = 0
            For i = 0 To cnt - 1: d = d + v(i): Next i
            d = d / cnt
            d2 = 0
            For i = 0 To cnt - 1: d2 = d2 + (v(i) - d) * (v(i) - d): Next i
            SetNum b, Sqr(d2 / (cnt - 1))
        End If
    Case F_SUMIF: CondAgg b, n, 0
    Case F_COUNTIF: CondAgg b, n, 1
    Case F_AVERAGEIF: CondAgg b, n, 2
    Case F_AND, F_OR
        If f = F_AND Then k = 1 Else k = 0
        For i = b To b + n - 1
            If sT(i) = KRANGE And Not (sR1(i) = sR2(i) And sC1(i) = sC2(i)) Then
                SetErr b, E_VALUE: Exit Sub
            End If
            If Not Truth(i, j) Then SetErr b, sN(i): Exit Sub
            If f = F_AND Then k = k And j Else k = k Or j
        Next i
        sT(b) = KBOOL: sN(b) = k
    Case F_NOT
        If Not Truth(b, j) Then Exit Sub
        sT(b) = KBOOL: sN(b) = 1 - j
    Case F_IFERROR
        Deref b
        If sT(b) = KERR Then
            Deref b + 1
            sT(b) = sT(b + 1): sN(b) = sN(b + 1): sS(b) = sS(b + 1)
        End If
    Case F_ISNUMBER, F_ISTEXT, F_ISBLANK
        Deref b
        Select Case f
        Case F_ISNUMBER: k = -(sT(b) = KNUM)
        Case F_ISTEXT: k = -(sT(b) = KTEXT)
        Case F_ISBLANK: k = -(sT(b) = KEMPTY)
        End Select
        sT(b) = KBOOL: sN(b) = k
    Case F_ROWS, F_COLUMNS
        If sT(b) <> KRANGE Then SetNum b, 1: Exit Sub
        If f = F_ROWS Then SetNum b, sR2(b) - sR1(b) + 1 Else SetNum b, sC2(b) - sC1(b) + 1
    Case F_CHOOSE
        If Not ToNum(b, d) Then Exit Sub
        k = Int(d)
        If k < 1 Or k > n - 1 Then SetErr b, E_VALUE: Exit Sub
        Deref b + k
        sT(b) = sT(b + k): sN(b) = sN(b + k): sS(b) = sS(b + k)
    Case F_VLOOKUP
        VLookup b, n
    Case F_LEN, F_UPPER, F_LOWER, F_TRIM, F_LEFT, F_RIGHT, F_MID, F_CONCAT, F_FIND, F_SUBSTITUTE, F_REPT, F_EXACT, F_TEXT, F_VALUE
        TextFunc f, b, n
    Case Else
        ' numeric functions of 1 or 2 numbers
        If Not ToNum(b, d) Then Exit Sub
        If n >= 2 Then
            If Not ToNum(b + 1, d2) Then SetErr b, sN(b + 1): Exit Sub
        End If
        Select Case f
        Case F_ROUND, F_ROUNDUP, F_ROUNDDOWN, F_TRUNC
            If n < 2 Then d2 = 0
            Select Case f
            Case F_ROUND: SetNum b, RoundTo(d, Int(d2), 0)
            Case F_ROUNDUP: SetNum b, RoundTo(d, Int(d2), 1)
            Case Else: SetNum b, RoundTo(d, Int(d2), 2)
            End Select
        Case F_ABS: SetNum b, Abs(d)
        Case F_SQRT: If d < 0 Then SetErr b, E_NUM Else SetNum b, Sqr(d)
        Case F_INT: SetNum b, Int(d)
        Case F_MOD
            If d2 = 0 Then SetErr b, E_DIV0 Else SetNum b, d - d2 * Int(d / d2)
        Case F_POWER: SafePow b, d, d2: If sT(b) <> KERR Then sT(b) = KNUM
        Case F_EXP
            If d > 709 Then SetErr b, E_NUM Else SetNum b, Exp(d)
        Case F_LN: If d <= 0 Then SetErr b, E_NUM Else SetNum b, Log(d)
        Case F_LOG10: If d <= 0 Then SetErr b, E_NUM Else SetNum b, Log(d) / Log(10#)
        Case F_SIN: SetNum b, Sin(d)
        Case F_COS: SetNum b, Cos(d)
        Case F_TAN: SetNum b, Tan(d)
        Case F_SIGN: SetNum b, Sgn(d)
        Case F_YEAR, F_MONTH, F_DAY
            If d < -657434 Or d > 2958465 Then SetErr b, E_NUM: Exit Sub
            Select Case f
            Case F_YEAR: SetNum b, Year(CDate(d))
            Case F_MONTH: SetNum b, Month(CDate(d))
            Case F_DAY: SetNum b, Day(CDate(d))
            End Select
        Case F_DATE
            Dim d3 As Double
            If Not ToNum(b + 2, d3) Then SetErr b, sN(b + 2): Exit Sub
            If d < 100 Or d > 9999 Then SetErr b, E_NUM: Exit Sub
            SetNum b, CDbl(DateSerial(Int(d), Int(d2), Int(d3)))
        Case Else
            SetErr b, E_NAME
        End Select
    End Select
End Sub

Private Sub TextFunc(ByVal f As Long, ByVal b As Long, ByVal n As Long)
    Dim s As String, i As Long, d As Double, d2 As Double, k As Long, fm As Long
    If f = F_TEXT Or f = F_VALUE Then
        If f = F_VALUE Then
            Deref b
            If sT(b) = KNUM Then Exit Sub
            If Not ToStr(b) Then Exit Sub
            If ParseNumber(sS(b), d, fm) Then SetNum b, d Else SetErr b, E_VALUE
            Exit Sub
        End If
        If Not ToNum(b, d) Then Exit Sub
        If Not ToStr(b + 1) Then SetErr b, sN(b + 1): Exit Sub
        SetStr b, FormatWith(d, sS(b + 1))
        Exit Sub
    End If
    If f = F_CONCAT Then
        s = ""
        For i = b To b + n - 1
            If sT(i) = KRANGE Then
                Dim r As Long, c As Long, y As Long
                For r = sR1(i) To sR2(i)
                    For c = sC1(i) To sC2(i)
                        If r < NR And c < NC Then
                            y = r * NC + c
                            Select Case cKind(y)
                            Case KTEXT: s = s & cTxt(y)
                            Case KNUM: s = s & GeneralText(cNum(y))
                            Case KBOOL: If cNum(y) <> 0 Then s = s & "TRUE" Else s = s & "FALSE"
                            Case KERR: SetErr b, cNum(y): Exit Sub
                            End Select
                        End If
                    Next c
                Next r
            Else
                If Not ToStr(i) Then SetErr b, sN(i): Exit Sub
                s = s & sS(i)
            End If
        Next i
        SetStr b, s
        Exit Sub
    End If
    If Not ToStr(b) Then Exit Sub
    s = sS(b)
    Select Case f
    Case F_LEN: SetNum b, Len(s)
    Case F_UPPER: SetStr b, UCase$(s)
    Case F_LOWER: SetStr b, LCase$(s)
    Case F_TRIM: SetStr b, TrimSpaces(s)
    Case F_LEFT, F_RIGHT
        If n = 2 Then
            If Not ToNum(b + 1, d) Then SetErr b, sN(b + 1): Exit Sub
        Else
            d = 1
        End If
        If d < 0 Then SetErr b, E_VALUE: Exit Sub
        If f = F_LEFT Then SetStr b, Left$(s, Int(d)) Else SetStr b, Right$(s, Int(d))
    Case F_MID
        If Not ToNum(b + 1, d) Then SetErr b, sN(b + 1): Exit Sub
        If Not ToNum(b + 2, d2) Then SetErr b, sN(b + 2): Exit Sub
        If d < 1 Or d2 < 0 Then SetErr b, E_VALUE: Exit Sub
        SetStr b, Mid$(s, Int(d), Int(d2))
    Case F_FIND
        ' FIND(needle, haystack [, start])
        If Not ToStr(b + 1) Then SetErr b, sN(b + 1): Exit Sub
        d = 1
        If n = 3 Then
            If Not ToNum(b + 2, d) Then SetErr b, sN(b + 2): Exit Sub
        End If
        If d < 1 Then SetErr b, E_VALUE: Exit Sub
        k = InStr(Int(d), sS(b + 1), s)
        If k = 0 Then SetErr b, E_VALUE Else SetNum b, k
    Case F_SUBSTITUTE
        If Not ToStr(b + 1) Then SetErr b, sN(b + 1): Exit Sub
        If Not ToStr(b + 2) Then SetErr b, sN(b + 2): Exit Sub
        If sS(b + 1) = "" Then SetStr b, s Else SetStr b, Replace(s, sS(b + 1), sS(b + 2))
    Case F_REPT
        If Not ToNum(b + 1, d) Then SetErr b, sN(b + 1): Exit Sub
        If d < 0 Or d * Len(s) > 32767 Then SetErr b, E_VALUE: Exit Sub
        Dim t As String
        For i = 1 To Int(d): t = t & s: Next i
        SetStr b, t
    Case F_EXACT
        If Not ToStr(b + 1) Then SetErr b, sN(b + 1): Exit Sub
        sT(b) = KBOOL: sN(b) = -(s = sS(b + 1))
    End Select
End Sub

Private Function TrimSpaces(ByVal s As String) As String
    s = Trim$(s)
    Do While InStr(s, "  ") > 0
        s = Replace(s, "  ", " ")
    Loop
    TrimSpaces = s
End Function

Private Sub VLookup(ByVal b As Long, ByVal n As Long)
    Dim exact As Boolean, col As Long, d As Double, r As Long, y As Long, best As Long, k As Long, key As Long
    If sT(b + 1) <> KRANGE Then SetErr b, E_VALUE: Exit Sub
    If Not ToNum(b + 2, d) Then SetErr b, sN(b + 2): Exit Sub
    col = Int(d)
    If col < 1 Or col > sC2(b + 1) - sC1(b + 1) + 1 Then SetErr b, E_REF: Exit Sub
    exact = False
    If n = 4 Then
        If Not Truth(b + 3, k) Then SetErr b, sN(b + 3): Exit Sub
        exact = (k = 0)
    End If
    Deref b
    If sT(b) = KERR Then Exit Sub
    best = -1
    ' compare the key in slot b with each first-column cell, using slot b + 3 as scratch
    For r = sR1(b + 1) To sR2(b + 1)
        If r >= NR Then Exit For
        y = r * NC + sC1(b + 1)
        sT(b + 3) = cKind(y): sN(b + 3) = cNum(y): sS(b + 3) = cTxt(y)
        If sT(b + 3) <> KEMPTY And sT(b + 3) <> KERR Then
            ' Compare wants (cell, key) and may convert empties; keep a copy of the key
            sT(b + 2) = sT(b): sN(b + 2) = sN(b): sS(b + 2) = sS(b)
            key = Compare(b + 3, b + 2)
            If key = 0 Then best = r: Exit For
            If Not exact And key < 0 Then
                If (sT(b + 3) = KTEXT) = (sT(b) = KTEXT) Then best = r
            ElseIf Not exact And key > 0 Then
                Exit For
            End If
        End If
    Next r
    If best < 0 Then SetErr b, E_NA: Exit Sub
    If sC1(b + 1) + col - 1 >= NC Then SetErr b, E_REF: Exit Sub
    y = best * NC + sC1(b + 1) + col - 1
    sT(b) = cKind(y): sN(b) = cNum(y): sS(b) = cTxt(y)
End Sub

' ---- showing values ----------------------------------------------------------------------------

' a number in the General format: up to 10 significant digits, scientific when large/small
Public Function GeneralText(ByVal d As Double) As String
    Dim a As Double, s As String
    a = Abs(d)
    If d = Int(d) And a < 1E+15 Then
        GeneralText = Format$(d, "0")
        Exit Function
    End If
    If a >= 10000000000# Or a < 0.0001 Then
        If a = 0 Then GeneralText = "0": Exit Function
        GeneralText = Format$(d, "0.#####E+00")
        Exit Function
    End If
    ' 10 significant digits
    Dim digits As Long
    digits = 9 - Int(Log(a) / Log(10#))
    If digits < 0 Then digits = 0
    If digits > 10 Then digits = 10
    s = Format$(Round(d, digits), "0." & String$(digits, "#"))
    If Right$(s, 1) = "." Then s = Left$(s, Len(s) - 1)
    GeneralText = s
End Function

Public Function FormatWith(ByVal d As Double, ByVal pattern As String) As String
    On Error GoTo Bad
    FormatWith = Format$(d, pattern)
    Exit Function
Bad:
    FormatWith = GeneralText(d)
End Function

Public Function NumFormatPattern(ByVal nf As Long) As String
    Select Case nf
    Case NF_INT: NumFormatPattern = "0"
    Case NF_FIX2: NumFormatPattern = "0.00"
    Case NF_THOUS: NumFormatPattern = "#,##0"
    Case NF_THOUS2: NumFormatPattern = "#,##0.00"
    Case NF_PCT: NumFormatPattern = "0%"
    Case NF_PCT2: NumFormatPattern = "0.00%"
    Case NF_CURRENCY: NumFormatPattern = "#,##0.00"
    Case NF_SCI: NumFormatPattern = "0.00E+00"
    Case NF_DATE: NumFormatPattern = "yyyy-mm-dd"
    Case NF_TIME: NumFormatPattern = "hh:nn:ss"
    Case Else: NumFormatPattern = ""
    End Select
End Function

Public Function NumFormatName(ByVal nf As Long) As String
    Select Case nf
    Case NF_GENERAL: NumFormatName = "General"
    Case NF_INT: NumFormatName = "Integer (0)"
    Case NF_FIX2: NumFormatName = "Fixed (0.00)"
    Case NF_THOUS: NumFormatName = "Thousands (#,##0)"
    Case NF_THOUS2: NumFormatName = "Thousands (#,##0.00)"
    Case NF_PCT: NumFormatName = "Percent (0%)"
    Case NF_PCT2: NumFormatName = "Percent (0.00%)"
    Case NF_CURRENCY: NumFormatName = "Currency"
    Case NF_SCI: NumFormatName = "Scientific (0.00E+00)"
    Case NF_DATE: NumFormatName = "Date (yyyy-mm-dd)"
    Case NF_TIME: NumFormatName = "Time (hh:nn:ss)"
    End Select
End Function

' after a change that affects every cell's text (the currency symbol)
Public Sub InvalidateDisplay()
    DispEpoch = DispEpoch + 1
End Sub

' The text a cell shows (cached)
Public Function CellText(ByVal r As Long, ByVal c As Long) As String
    Dim id As Long
    If r < 0 Or c < 0 Or r >= NR Or c >= NC Then Exit Function
    id = r * NC + c
    If cDispOk(id) Then
        If cDispFmt(id) = cFmt(id) Then
            If cDispEp(id) = DispEpoch Then CellText = cDisp(id): Exit Function
        End If
    End If
    CellText = MakeCellText(id)
    cDisp(id) = CellText
    cDispOk(id) = True
    cDispFmt(id) = cFmt(id)
    cDispEp(id) = DispEpoch
End Function

Private Function MakeCellText(ByVal id As Long) As String
    Dim nf As Long, d As Double
    Select Case cKind(id)
    Case KEMPTY
        MakeCellText = ""
    Case KTEXT
        MakeCellText = cTxt(id)
    Case KNUM
        d = cNum(id)
        nf = cFmt(id) And 255
        If nf = NF_GENERAL Then
            MakeCellText = GeneralText(d)
        ElseIf nf = NF_CURRENCY Then
            If d < 0 Then
                MakeCellText = "-" & CurrencySymbol & Format$(-d, "#,##0.00")
            Else
                MakeCellText = CurrencySymbol & Format$(d, "#,##0.00")
            End If
        ElseIf nf = NF_DATE Or nf = NF_TIME Then
            If d < -657434 Or d > 2958465 Then MakeCellText = "#####" Else MakeCellText = Format$(CDate(d), NumFormatPattern(nf))
        Else
            MakeCellText = FormatWith(d, NumFormatPattern(nf))
        End If
    Case KBOOL
        If cNum(id) <> 0 Then MakeCellText = "TRUE" Else MakeCellText = "FALSE"
    Case KERR
        MakeCellText = ErrName(cNum(id))
    End Select
End Function

Public Function CellKind(ByVal r As Long, ByVal c As Long) As Long
    CellKind = cKind(r * NC + c)
End Function

Public Function CellNum(ByVal r As Long, ByVal c As Long) As Double
    CellNum = cNum(r * NC + c)
End Function

Public Function IsFormula(ByVal r As Long, ByVal c As Long) As Boolean
    IsFormula = cCode(r * NC + c) >= 0
End Function

' the alignment a cell is drawn with (AL_LEFT/CENTER/RIGHT)
Public Function CellAlign(ByVal r As Long, ByVal c As Long) As Long
    Dim id As Long, a As Long
    id = r * NC + c
    a = (cFmt(id) \ 256) And 3
    If a = AL_AUTO Then
        Select Case cKind(id)
        Case KNUM: a = AL_RIGHT
        Case KBOOL, KERR: a = AL_CENTER
        Case Else: a = AL_LEFT
        End Select
    End If
    CellAlign = a
End Function

' ---- undo / redo -------------------------------------------------------------------------------

' Every SetCell/SetFormat between BeginAction and EndAction is one undo step.
Public Sub BeginAction()
    uGroup = uGroup + 1
    uOpen = True
End Sub

Public Sub EndAction()
    uOpen = False
End Sub

Private Sub GrowU()
    Dim m As Long
    m = UBound(uCell) * 2 + 1
    ReDim Preserve uCell(0 To m): ReDim Preserve uOld(0 To m): ReDim Preserve uNew(0 To m)
    ReDim Preserve uOldF(0 To m): ReDim Preserve uNewF(0 To m): ReDim Preserve uGrp(0 To m)
End Sub

Private Sub RecordUndo(ByVal id As Long, ByVal newSrc As String, ByVal newFmt As Long)
    If uSuspend Then Exit Sub
    If Not uOpen Then uGroup = uGroup + 1
    If uN > UBound(uCell) Then
        If uN >= UndoLimit Then DropOldestUndo
        If uN > UBound(uCell) Then GrowU
    End If
    uCell(uN) = id: uOld(uN) = cSrc(id): uOldF(uN) = cFmt(id)
    uNew(uN) = newSrc: uNewF(uN) = newFmt: uGrp(uN) = uGroup
    uN = uN + 1
    uTop = uN
End Sub

' record a whole-sheet snapshot (before a structural edit); the matching "after" snapshot
' is taken by EndSnapshot
Public Sub BeginSnapshot()
    If uN + 1 > UBound(uCell) Then GrowU
    uGroup = uGroup + 1
    uCell(uN) = -1: uOld(uN) = SerializeSheet(): uNew(uN) = "": uGrp(uN) = uGroup
    uN = uN + 1
    uTop = uN
    uSuspend = True
End Sub

Public Sub EndSnapshot()
    uSuspend = False
    uNew(uN - 1) = SerializeSheet()
End Sub

Private Sub DropOldestUndo()
    Dim g As Long, k As Long, i As Long
    ' drop whole groups from the bottom until a quarter of the limit is free
    Do While k < uN
        g = uGrp(k)
        Do While k < uN
            If uGrp(k) <> g Then Exit Do
            k = k + 1
        Loop
        If uN - k <= (UndoLimit * 3) \ 4 Then Exit Do
    Loop
    For i = k To uN - 1
        uCell(i - k) = uCell(i): uOld(i - k) = uOld(i): uNew(i - k) = uNew(i)
        uOldF(i - k) = uOldF(i): uNewF(i - k) = uNewF(i): uGrp(i - k) = uGrp(i)
    Next i
    uN = uN - k
End Sub

Public Function CanUndo() As Boolean
    CanUndo = uN > 0
End Function

Public Function CanRedo() As Boolean
    CanRedo = uTop > uN
End Function

Public Sub Undo()
    Dim g As Long, id As Long
    If uN = 0 Then Exit Sub
    g = uGrp(uN - 1)
    uSuspend = True
    BeginBatch
    Do While uN > 0
        If uGrp(uN - 1) <> g Then Exit Do
        uN = uN - 1
        id = uCell(uN)
        If id < 0 Then
            DeserializeSheet uOld(uN)
        Else
            SetRaw id, uOld(uN)
            cFmt(id) = uOldF(uN)
            NoteChange id
        End If
    Loop
    EndBatch
    uSuspend = False
    Modified = True
End Sub

Public Sub Redo()
    Dim g As Long, id As Long
    If uTop <= uN Then Exit Sub
    g = uGrp(uN)
    uSuspend = True
    BeginBatch
    Do While uN < uTop
        If uGrp(uN) <> g Then Exit Do
        id = uCell(uN)
        If id < 0 Then
            DeserializeSheet uNew(uN)
        Else
            SetRaw id, uNew(uN)
            cFmt(id) = uNewF(uN)
            NoteChange id
        End If
        uN = uN + 1
    Loop
    EndBatch
    uSuspend = False
    Modified = True
End Sub

' ---- clipboard ---------------------------------------------------------------------------------

Public Sub CopyRange(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long, ByVal cut As Boolean)
    Dim r As Long, c As Long, k As Long
    clipRows = r2 - r1 + 1: clipCols = c2 - c1 + 1
    clipR0 = r1: clipC0 = c1: clipCut = cut
    ReDim clipSrc(0 To clipRows * clipCols - 1)
    ReDim clipFmt(0 To clipRows * clipCols - 1)
    For r = r1 To r2
        For c = c1 To c2
            clipSrc(k) = cSrc(r * NC + c)
            clipFmt(k) = cFmt(r * NC + c)
            k = k + 1
        Next c
    Next r
    If cut Then
        BeginAction
        BeginBatch
        For r = r1 To r2
            For c = c1 To c2
                SetCell r, c, ""
            Next c
        Next r
        EndBatch
        EndAction
    End If
End Sub

' Paste the clipboard with its top-left at (r, c); formulas move their relative
' references (not after a cut, as Excel). A selection bigger than the clipboard
' (rows x cols multiples) is filled with repeats.
Public Sub PasteAt(ByVal r As Long, ByVal c As Long, ByVal selRows As Long, ByVal selCols As Long)
    Dim i As Long, j As Long, rr As Long, cc As Long, src As String, reps As Long, repc As Long, a As Long, b As Long
    If clipRows = 0 Then Exit Sub
    reps = 1: repc = 1
    If selRows > clipRows And selRows Mod clipRows = 0 Then reps = selRows \ clipRows
    If selCols > clipCols And selCols Mod clipCols = 0 Then repc = selCols \ clipCols
    BeginAction
    BeginBatch
    For a = 0 To reps - 1
        For b = 0 To repc - 1
            For i = 0 To clipRows - 1
                For j = 0 To clipCols - 1
                    rr = r + a * clipRows + i: cc = c + b * clipCols + j
                    If rr < NR And cc < NC Then
                        src = clipSrc(i * clipCols + j)
                        If Not clipCut Then src = AdjustFormula(src, rr - (clipR0 + i), cc - (clipC0 + j))
                        SetFormat rr, cc, clipFmt(i * clipCols + j)
                        SetCell rr, cc, src
                    End If
                Next j
            Next i
        Next b
    Next a
    EndBatch
    EndAction
    If clipCut Then clipCut = False: clipR0 = r: clipC0 = c
End Sub

' the range as tab-separated text (for the system clipboard): what the cells show
Public Function RangeAsText(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long) As String
    Dim r As Long, c As Long, s As String
    For r = r1 To r2
        For c = c1 To c2
            If c > c1 Then s = s & vbTab
            s = s & CellText(r, c)
        Next c
        s = s & vbLf
    Next r
    RangeAsText = s
End Function

' paste tab-separated text (from another program) at (r, c)
Public Sub PasteText(ByVal r As Long, ByVal c As Long, ByVal txt As String)
    Dim lines() As String, cells() As String, i As Long, j As Long
    txt = Replace(txt, vbCr, "")
    If Right$(txt, 1) = vbLf Then txt = Left$(txt, Len(txt) - 1)
    lines = Split(txt, vbLf)
    BeginAction
    BeginBatch
    For i = 0 To UBound(lines)
        cells = Split(lines(i), vbTab)
        For j = 0 To UBound(cells)
            SetCell r + i, c + j, cells(j)
        Next j
    Next i
    EndBatch
    EndAction
End Sub

Public Sub ClearRange(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long)
    Dim r As Long, c As Long
    BeginAction
    BeginBatch
    For r = r1 To r2
        For c = c1 To c2
            SetCell r, c, ""
        Next c
    Next r
    EndBatch
    EndAction
End Sub

' Fill down: the top row of the range copied into the rows below (references move)
Public Sub FillDown(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long)
    Dim r As Long, c As Long
    BeginAction
    BeginBatch
    For c = c1 To c2
        For r = r1 + 1 To r2
            SetFormat r, c, cFmt(r1 * NC + c)
            SetCell r, c, AdjustFormula(cSrc(r1 * NC + c), r - r1, 0)
        Next r
    Next c
    EndBatch
    EndAction
End Sub

Public Sub FillRight(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long)
    Dim r As Long, c As Long
    BeginAction
    BeginBatch
    For r = r1 To r2
        For c = c1 + 1 To c2
            SetFormat r, c, cFmt(r * NC + c1)
            SetCell r, c, AdjustFormula(cSrc(r * NC + c1), 0, c - c1)
        Next c
    Next r
    EndBatch
    EndAction
End Sub

' apply format bits to a range: mask selects the bits to change
Public Sub FormatRange(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long, ByVal mask As Long, ByVal bits As Long)
    Dim r As Long, c As Long, id As Long
    BeginAction
    For r = r1 To r2
        For c = c1 To c2
            id = r * NC + c
            SetFormat r, c, (cFmt(id) And Not mask) Or (bits And mask)
        Next c
    Next r
    EndAction
End Sub

' ---- structural edits --------------------------------------------------------------------------

' Insert n empty rows before row `at` (n < 0 deletes -n rows from `at`), or columns.
' Every formula's references are rewritten; the last rows/columns fall off the sheet.
Public Sub InsertRowsCols(ByVal isCol As Boolean, ByVal at As Long, ByVal n As Long)
    Dim src() As String, fm() As Long, r As Long, c As Long, sr As Long, sc As Long, id As Long, s As String
    Dim w() As Long, hh() As Long
    BeginSnapshot
    ReDim hh(0 To NR - 1)
    For r = 0 To NR - 1: hh(r) = rowH(r): Next r
    ReDim src(0 To NCELLS - 1)
    ReDim fm(0 To NCELLS - 1)
    For id = 0 To NCELLS - 1
        src(id) = cSrc(id): fm(id) = cFmt(id)
    Next id
    ReDim w(0 To NC - 1)
    For c = 0 To NC - 1: w(c) = colW(c): Next c
    ClearAll
    For r = 0 To NR - 1
        For c = 0 To NC - 1
            sr = r: sc = c
            If isCol Then
                If c >= at Then
                    If n > 0 And c < at + n Then sc = -1 Else sc = c - n
                End If
            Else
                If r >= at Then
                    If n > 0 And r < at + n Then sr = -1 Else sr = r - n
                End If
            End If
            If sr >= 0 And sc >= 0 And sr < NR And sc < NC Then
                id = sr * NC + sc
                s = src(id)
                If Left$(s, 1) = "=" Then s = ShiftFormula(s, isCol, at, n)
                cFmt(r * NC + c) = fm(id)
                If s <> "" Then SetRaw r * NC + c, s
            End If
        Next c
    Next r
    If Not isCol Then
        For r = 0 To NR - 1
            sr = r
            If r >= at Then
                If n > 0 And r < at + n Then sr = -1 Else sr = r - n
            End If
            If sr >= 0 And sr < NR Then rowH(r) = hh(sr) Else rowH(r) = 15
        Next r
    End If
    If isCol Then
        For c = 0 To NC - 1
            sc = c
            If c >= at Then
                If n > 0 And c < at + n Then sc = -1 Else sc = c - n
            End If
            If sc >= 0 And sc < NC Then colW(c) = w(sc) Else colW(c) = 72
        Next c
    End If
    RecalcAll
    EndSnapshot
    Modified = True
End Sub

' empty every cell (no undo, no recalculation)
Private Sub ClearAll()
    Dim i As Long
    For i = 0 To NCELLS - 1
        If cCode(i) >= 0 Then cCode(i) = -1: cCodeLen(i) = 0
        cSrc(i) = "": cTxt(i) = "": cKind(i) = KEMPTY: cNum(i) = 0: cFmt(i) = 0: cDispOk(i) = False
        dHead(i) = -1
    Next i
    For i = 0 To NC * NB - 1: rHead(i) = -1: Next i
    For i = 0 To dCap - 2: dNext(i) = i + 1: Next i
    dNext(dCap - 1) = -1: dFree = 0
    For i = 0 To rCap - 2: rNext(i) = i + 1: Next i
    rNext(rCap - 1) = -1: rFree = 0
    pCodeN = 0: pCodeLive = 0: pNumN = 0: pStrN = 0
    FormulaCount = 0
End Sub

' Sort the rows r1..r2 of columns c1..c2 by column key (ascending or not). Formulas are
' moved as they are (their references are not rewritten, as in most spreadsheets).
Public Sub SortRange(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long, ByVal key As Long, ByVal ascending As Boolean)
    Dim n As Long, order() As Long, i As Long, j As Long, t As Long, src() As String, fm() As Long, c As Long
    Dim kk() As Long, kn() As Double, ks() As String, cmp As Long
    n = r2 - r1 + 1
    If n < 2 Then Exit Sub
    ReDim order(0 To n - 1): ReDim kk(0 To n - 1): ReDim kn(0 To n - 1): ReDim ks(0 To n - 1)
    For i = 0 To n - 1
        order(i) = i
        kk(i) = cKind((r1 + i) * NC + key): kn(i) = cNum((r1 + i) * NC + key): ks(i) = LCase$(cTxt((r1 + i) * NC + key))
    Next i
    ' insertion sort (stable)
    For i = 1 To n - 1
        t = order(i)
        j = i - 1
        Do While j >= 0
            cmp = KeyCmp(kk(order(j)), kn(order(j)), ks(order(j)), kk(t), kn(t), ks(t))
            If Not ascending Then cmp = -cmp
            If kk(order(j)) = KEMPTY Then cmp = 1           ' blanks always last
            If kk(t) = KEMPTY Then cmp = -1
            If cmp <= 0 Then Exit Do
            order(j + 1) = order(j)
            j = j - 1
        Loop
        order(j + 1) = t
    Next i
    ReDim src(0 To n * (c2 - c1 + 1) - 1): ReDim fm(0 To n * (c2 - c1 + 1) - 1)
    For i = 0 To n - 1
        For c = c1 To c2
            src(i * (c2 - c1 + 1) + c - c1) = cSrc((r1 + i) * NC + c)
            fm(i * (c2 - c1 + 1) + c - c1) = cFmt((r1 + i) * NC + c)
        Next c
    Next i
    BeginAction
    BeginBatch
    For i = 0 To n - 1
        For c = c1 To c2
            SetFormat r1 + i, c, fm(order(i) * (c2 - c1 + 1) + c - c1)
            SetCell r1 + i, c, src(order(i) * (c2 - c1 + 1) + c - c1)
        Next c
    Next i
    EndBatch
    EndAction
End Sub

Private Function KeyCmp(ByVal k1 As Long, ByVal n1 As Double, ByVal s1 As String, ByVal k2 As Long, ByVal n2 As Double, ByVal s2 As String) As Long
    Dim t1 As Boolean, t2 As Boolean
    t1 = (k1 = KTEXT): t2 = (k2 = KTEXT)
    If t1 And t2 Then
        If s1 < s2 Then KeyCmp = -1 Else If s1 > s2 Then KeyCmp = 1
    ElseIf t1 Then
        KeyCmp = 1
    ElseIf t2 Then
        KeyCmp = -1
    Else
        If n1 < n2 Then KeyCmp = -1 Else If n1 > n2 Then KeyCmp = 1
    End If
End Function

' ---- serializing (the .gws file body, also the undo snapshots) ---------------------------------

Public Function EscapeField(ByVal s As String) As String
    s = Replace(s, "\", "\\")
    s = Replace(s, vbTab, "\t")
    s = Replace(s, vbLf, "\n")
    EscapeField = Replace(s, vbCr, "\r")
End Function

Public Function UnescapeField(ByVal s As String) As String
    Dim i As Long, ch As String, res As String, p As Long
    If InStr(s, "\") = 0 Then UnescapeField = s: Exit Function
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
    UnescapeField = res
End Function

' the cells and column widths as lines "C<tab>A1<tab>fmt<tab>src" and "W<tab>col<tab>width"
Public Function SerializeSheet() As String
    Dim parts() As String, n As Long, id As Long, c As Long
    ReDim parts(0 To 255)
    For c = 0 To NC - 1
        If colW(c) <> 72 Then
            If n > UBound(parts) Then ReDim Preserve parts(0 To n * 2)
            parts(n) = "W" & vbTab & ColName(c) & vbTab & CStr(colW(c)): n = n + 1
        End If
    Next c
    For id = 0 To NR - 1
        If rowH(id) <> 15 Then
            If n > UBound(parts) Then ReDim Preserve parts(0 To n * 2)
            parts(n) = "R" & vbTab & CStr(id + 1) & vbTab & CStr(rowH(id)): n = n + 1
        End If
    Next id
    For id = 0 To NCELLS - 1
        If cSrc(id) <> "" Or cFmt(id) <> 0 Then
            If n > UBound(parts) Then ReDim Preserve parts(0 To n * 2)
            parts(n) = "C" & vbTab & CellName(id \ NC, id Mod NC) & vbTab & CStr(cFmt(id)) & vbTab & EscapeField(cSrc(id))
            n = n + 1
        End If
    Next id
    If n = 0 Then SerializeSheet = "": Exit Function
    ReDim Preserve parts(0 To n - 1)
    SerializeSheet = Join(parts, vbLf) & vbLf
End Function

' Load lines made by SerializeSheet into the (cleared) sheet. Unknown lines are skipped
' and returned in `rest` for the caller (charts, settings).
Public Sub DeserializeSheet(ByVal body As String)
    Dim rest As String
    LoadLines body, rest
End Sub

Public Sub LoadLines(ByVal body As String, rest As String)
    Dim lines() As String, i As Long, f() As String, r As Long, c As Long, id As Long
    ClearAll
    For c = 0 To NC - 1: colW(c) = 72: Next c
    For r = 0 To NR - 1: rowH(r) = 15: Next r
    rest = ""
    If body = "" Then Exit Sub
    lines = Split(body, vbLf)
    uSuspend = True
    For i = 0 To UBound(lines)
        If Left$(lines(i), 2) = "C" & vbTab Then
            f = Split(lines(i), vbTab, 4)
            If UBound(f) >= 3 Then
                If ParseCellName(f(1), r, c) Then
                    If r < NR And c < NC Then
                        id = r * NC + c
                        cFmt(id) = Val(f(2))
                        SetRaw id, UnescapeField(f(3))
                        cFmt(id) = Val(f(2))       ' SetRaw may set a format from "15%"
                    End If
                End If
            End If
        ElseIf Left$(lines(i), 2) = "R" & vbTab Then
            f = Split(lines(i), vbTab)
            If UBound(f) >= 2 Then
                r = Val(f(1)) - 1
                If r >= 0 And r < NR Then rowH(r) = Val(f(2))
                If rowH(r) < 8 Then rowH(r) = 8
            End If
        ElseIf Left$(lines(i), 2) = "W" & vbTab Then
            f = Split(lines(i), vbTab)
            If UBound(f) >= 2 Then
                If ParseCellName(f(1) & "1", r, c) Then
                    If c < NC Then colW(c) = Val(f(2))
                End If
            End If
        ElseIf lines(i) <> "" Then
            rest = rest & lines(i) & vbLf
        End If
    Next i
    uSuspend = False
    RecalcAll
End Sub

' forget the undo history (after loading a file)
Public Sub ClearUndo()
    uN = 0: uTop = 0
End Sub
