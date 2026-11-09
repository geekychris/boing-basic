' Gridwise - the formula compiler.
'
' A formula ("=SUM(A1:A10)*2") is compiled to a small postfix program of Longs that
' Sheet.bas runs on a value stack. Numbers and strings go into constant pools.
' The same lexer rewrites the references of a formula when it is copied, filled or
' rows/columns are inserted (AdjustFormula), so relative references move and
' $-anchored ones stay.
'
' Grammar (Excel's precedence, lowest first):
'   compare := concat (("=" | "<>" | "<" | ">" | "<=" | ">=") concat)*
'   concat  := add ("&" add)*
'   add     := mul (("+" | "-") mul)*
'   mul     := pow (("*" | "/") pow)*
'   pow     := unary ("^" unary)*
'   unary   := ("-" | "+") unary | postfix
'   postfix := primary "%"*
'   primary := number | "text" | TRUE | FALSE | ref [":" ref] | name "(" args ")" | "(" compare ")"
Option Explicit

' ---- opcodes -------------------------------------------------------------------------
Public Const OP_NUM As Long = 1       ' k            push numPool(k)
Public Const OP_STR As Long = 2       ' k            push strPool(k)
Public Const OP_REF As Long = 3       ' r c          push the value of cell (r, c)
Public Const OP_RANGE As Long = 4     ' r1 c1 r2 c2  push a range
Public Const OP_ADD As Long = 5
Public Const OP_SUB As Long = 6
Public Const OP_MUL As Long = 7
Public Const OP_DIV As Long = 8
Public Const OP_POW As Long = 9
Public Const OP_CAT As Long = 10
Public Const OP_EQ As Long = 11
Public Const OP_NE As Long = 12
Public Const OP_LT As Long = 13
Public Const OP_GT As Long = 14
Public Const OP_LE As Long = 15
Public Const OP_GE As Long = 16
Public Const OP_NEG As Long = 17
Public Const OP_PCT As Long = 18
Public Const OP_FUNC As Long = 19     ' fid argc
Public Const OP_BOOL As Long = 20     ' v (0/1)
Public Const OP_ERR As Long = 21      ' code
Public Const OP_JF As Long = 22       ' target   pop; jump if false (IF)
Public Const OP_JMP As Long = 23      ' target

' ---- error codes (cell value kind KERR, the code in the number) ---------------------------
Public Const E_DIV0 As Long = 1
Public Const E_VALUE As Long = 2
Public Const E_REF As Long = 3
Public Const E_NAME As Long = 4
Public Const E_NA As Long = 5
Public Const E_NUM As Long = 6
Public Const E_CIRC As Long = 7
Public Const E_SYNTAX As Long = 8

' ---- functions -------------------------------------------------------------------------
Public Const F_SUM As Long = 1
Public Const F_AVERAGE As Long = 2
Public Const F_MIN As Long = 3
Public Const F_MAX As Long = 4
Public Const F_COUNT As Long = 5
Public Const F_COUNTA As Long = 6
Public Const F_IF As Long = 7
Public Const F_ROUND As Long = 8
Public Const F_ABS As Long = 9
Public Const F_SQRT As Long = 10
Public Const F_INT As Long = 11
Public Const F_MOD As Long = 12
Public Const F_POWER As Long = 13
Public Const F_PI As Long = 14
Public Const F_LEN As Long = 15
Public Const F_LEFT As Long = 16
Public Const F_RIGHT As Long = 17
Public Const F_MID As Long = 18
Public Const F_UPPER As Long = 19
Public Const F_LOWER As Long = 20
Public Const F_TRIM As Long = 21
Public Const F_CONCAT As Long = 22
Public Const F_TEXT As Long = 23
Public Const F_VALUE As Long = 24
Public Const F_AND As Long = 25
Public Const F_OR As Long = 26
Public Const F_NOT As Long = 27
Public Const F_PRODUCT As Long = 28
Public Const F_ROUNDUP As Long = 29
Public Const F_ROUNDDOWN As Long = 30
Public Const F_SUMIF As Long = 31
Public Const F_COUNTIF As Long = 32
Public Const F_IFERROR As Long = 33
Public Const F_ISNUMBER As Long = 34
Public Const F_ISTEXT As Long = 35
Public Const F_ISBLANK As Long = 36
Public Const F_MEDIAN As Long = 37
Public Const F_EXP As Long = 38
Public Const F_LN As Long = 39
Public Const F_LOG10 As Long = 40
Public Const F_SIN As Long = 41
Public Const F_COS As Long = 42
Public Const F_TAN As Long = 43
Public Const F_SIGN As Long = 44
Public Const F_TODAY As Long = 45
Public Const F_NOW As Long = 46
Public Const F_FIND As Long = 47
Public Const F_SUBSTITUTE As Long = 48
Public Const F_REPT As Long = 49
Public Const F_EXACT As Long = 50
Public Const F_AVERAGEIF As Long = 51
Public Const F_STDEV As Long = 52
Public Const F_NA As Long = 53
Public Const F_ROWS As Long = 54
Public Const F_COLUMNS As Long = 55
Public Const F_CHOOSE As Long = 56
Public Const F_VLOOKUP As Long = 57
Public Const F_TRUNC As Long = 58
Public Const F_COUNTBLANK As Long = 59
Public Const F_YEAR As Long = 60
Public Const F_MONTH As Long = 61
Public Const F_DAY As Long = 62
Public Const F_DATE As Long = 63
Public Const F_LAST As Long = 63

' ---- token kinds -------------------------------------------------------------------------
Private Const T_END As Long = 0
Private Const T_NUM As Long = 1
Private Const T_STR As Long = 2
Private Const T_REF As Long = 3
Private Const T_NAME As Long = 4
Private Const T_OP As Long = 5        ' tokOp holds the character code (or 1 = <=, 2 = >=, 3 = <>)
Private Const T_ERR As Long = 6       ' #REF! etc. written in the formula
Private Const T_BAD As Long = 7

' ---- the compiled program (read by Sheet.bas after Compile) -------------------------------
Public outCode() As Long
Public outLen As Long
Public outNum() As Double
Public outNumN As Long
Public outStr() As String
Public outStrN As Long
Public compileErr As String        ' "" when the formula compiled

' ---- lexer state ---------------------------------------------------------------------------
Private lxS As String
Private lxPos As Long              ' 1-based index of the next character
Private lxLen As Long
Private tokKind As Long
Private tokStart As Long           ' where the token starts in lxS
Private tokOp As Long
Private tokNum As Double
Private tokText As String
Private tokRow As Long             ' 0-based
Private tokCol As Long
Private tokAbsR As Boolean
Private tokAbsC As Boolean
Private failed As Boolean
Private inited As Boolean

Private Sub InitPools()
    If inited Then Exit Sub
    ReDim outCode(0 To 255)
    ReDim outNum(0 To 31)
    ReDim outStr(0 To 15)
    inited = True
End Sub

' ---- column letters --------------------------------------------------------------------------

Public Function ColName(ByVal c As Long) As String
    ' 0 -> A, 25 -> Z, 26 -> AA
    If c < 26 Then
        ColName = Chr$(65 + c)
    Else
        ColName = Chr$(64 + c \ 26) & Chr$(65 + c Mod 26)
    End If
End Function

Public Function CellName(ByVal r As Long, ByVal c As Long) As String
    CellName = ColName(c) & CStr(r + 1)
End Function

' Parse "B12" / "$B$12" into (r, c); False if it is not a cell name.
Public Function ParseCellName(ByVal s As String, r As Long, c As Long) As Boolean
    Dim i As Long, n As Long, ch As Long, cc As Long, rr As Long, letters As Long
    s = UCase$(Trim$(s))
    n = Len(s)
    i = 1
    If i <= n Then If Mid$(s, i, 1) = "$" Then i = i + 1
    Do While i <= n
        ch = Asc(Mid$(s, i, 1))
        If ch < 65 Or ch > 90 Then Exit Do
        cc = cc * 26 + (ch - 64)
        letters = letters + 1
        i = i + 1
    Loop
    If letters = 0 Or letters > 2 Then Exit Function
    If i <= n Then If Mid$(s, i, 1) = "$" Then i = i + 1
    If i > n Then Exit Function
    Do While i <= n
        ch = Asc(Mid$(s, i, 1))
        If ch < 48 Or ch > 57 Then Exit Function
        rr = rr * 10 + (ch - 48)
        If rr > 99999 Then Exit Function
        i = i + 1
    Loop
    If rr < 1 Then Exit Function
    r = rr - 1
    c = cc - 1
    ParseCellName = True
End Function

' ---- the lexer ----------------------------------------------------------------------------------

Private Sub LexStart(ByVal s As String, ByVal from As Long)
    lxS = s
    lxLen = Len(s)
    lxPos = from
    failed = False
    NextTok
End Sub

Private Function IsLetter(ByVal ch As Long) As Boolean
    IsLetter = (ch >= 65 And ch <= 90) Or (ch >= 97 And ch <= 122) Or ch = 95
End Function

Private Function IsDigit(ByVal ch As Long) As Boolean
    IsDigit = ch >= 48 And ch <= 57
End Function

Private Function PeekCh(ByVal p As Long) As Long
    If p > lxLen Then PeekCh = 0 Else PeekCh = Asc(Mid$(lxS, p, 1))
End Function

Private Sub NextTok()
    Dim ch As Long, p As Long, q As Long, t As String, cc As Long, rr As Long, nl As Long
    Do While lxPos <= lxLen
        ch = Asc(Mid$(lxS, lxPos, 1))
        If ch <> 32 And ch <> 9 Then Exit Do
        lxPos = lxPos + 1
    Loop
    tokStart = lxPos
    If lxPos > lxLen Then tokKind = T_END: Exit Sub
    ch = Asc(Mid$(lxS, lxPos, 1))
    If IsDigit(ch) Or (ch = 46 And IsDigit(PeekCh(lxPos + 1))) Then
        p = lxPos
        Do While IsDigit(PeekCh(p)): p = p + 1: Loop
        If PeekCh(p) = 46 Then
            p = p + 1
            Do While IsDigit(PeekCh(p)): p = p + 1: Loop
        End If
        If PeekCh(p) = 69 Or PeekCh(p) = 101 Then
            q = p + 1
            If PeekCh(q) = 43 Or PeekCh(q) = 45 Then q = q + 1
            If IsDigit(PeekCh(q)) Then
                p = q
                Do While IsDigit(PeekCh(p)): p = p + 1: Loop
            End If
        End If
        tokNum = Val(Mid$(lxS, lxPos, p - lxPos))
        tokKind = T_NUM
        lxPos = p
        Exit Sub
    End If
    If ch = 34 Then
        t = ""
        p = lxPos + 1
        Do
            If p > lxLen Then tokKind = T_BAD: lxPos = p: Exit Sub
            If PeekCh(p) = 34 Then
                If PeekCh(p + 1) = 34 Then
                    t = t & Chr$(34)
                    p = p + 2
                Else
                    p = p + 1
                    Exit Do
                End If
            Else
                q = InStr(p, lxS, Chr$(34))
                If q = 0 Then tokKind = T_BAD: lxPos = lxLen + 1: Exit Sub
                t = t & Mid$(lxS, p, q - p)
                p = q
            End If
        Loop
        tokText = t
        tokKind = T_STR
        lxPos = p
        Exit Sub
    End If
    If ch = 35 Then    ' #REF! #DIV/0! ... written in a formula
        Dim e As Long
        For e = 1 To 8
            t = ErrName(e)
            If UCase$(Mid$(lxS, lxPos, Len(t))) = t Then
                tokKind = T_ERR
                tokOp = e
                lxPos = lxPos + Len(t)
                Exit Sub
            End If
        Next e
        tokKind = T_BAD
        lxPos = lxPos + 1
        Exit Sub
    End If
    If IsLetter(ch) Or ch = 36 Then
        ' a reference ($A$1) or a name (SUM, TRUE)
        p = lxPos
        tokAbsC = False: tokAbsR = False
        If ch = 36 Then tokAbsC = True: p = p + 1
        q = p
        cc = 0: nl = 0
        Do While IsLetter(PeekCh(p)) And PeekCh(p) <> 95
            ch = PeekCh(p)
            If ch >= 97 Then ch = ch - 32
            If nl < 3 Then cc = cc * 26 + (ch - 64)
            nl = nl + 1
            p = p + 1
        Loop
        If nl >= 1 And nl <= 2 Then
            q = p
            If PeekCh(q) = 36 Then tokAbsR = True: q = q + 1
            If IsDigit(PeekCh(q)) Then
                rr = 0
                Do While IsDigit(PeekCh(q))
                    rr = rr * 10 + (PeekCh(q) - 48)
                    If rr > 99999 Then rr = 99999
                    q = q + 1
                Loop
                If Not IsLetter(PeekCh(q)) And PeekCh(q) <> 40 And rr >= 1 Then
                    tokKind = T_REF
                    tokRow = rr - 1
                    tokCol = cc - 1
                    lxPos = q
                    Exit Sub
                End If
            End If
        End If
        If tokAbsC Then tokKind = T_BAD: lxPos = lxPos + 1: Exit Sub
        p = lxPos
        Do While IsLetter(PeekCh(p)) Or IsDigit(PeekCh(p)) Or PeekCh(p) = 46
            p = p + 1
        Loop
        tokText = UCase$(Mid$(lxS, lxPos, p - lxPos))
        tokKind = T_NAME
        lxPos = p
        Exit Sub
    End If
    tokKind = T_OP
    tokOp = ch
    lxPos = lxPos + 1
    If ch = 60 Then
        If PeekCh(lxPos) = 61 Then
            tokOp = 1: lxPos = lxPos + 1
        ElseIf PeekCh(lxPos) = 62 Then
            tokOp = 3: lxPos = lxPos + 1
        End If
    ElseIf ch = 62 Then
        If PeekCh(lxPos) = 61 Then tokOp = 2: lxPos = lxPos + 1
    End If
    Select Case tokOp
    Case 1, 2, 3, 37, 38, 40, 41, 42, 43, 44, 45, 47, 58, 59, 60, 61, 62, 94
    Case Else
        tokKind = T_BAD
    End Select
End Sub

Public Function ErrName(ByVal e As Long) As String
    Select Case e
    Case E_DIV0: ErrName = "#DIV/0!"
    Case E_VALUE: ErrName = "#VALUE!"
    Case E_REF: ErrName = "#REF!"
    Case E_NAME: ErrName = "#NAME?"
    Case E_NA: ErrName = "#N/A"
    Case E_NUM: ErrName = "#NUM!"
    Case E_CIRC: ErrName = "#CIRC!"
    Case Else: ErrName = "#ERROR!"
    End Select
End Function

' ---- emitting ----------------------------------------------------------------------------------

Private Sub Emit(ByVal v As Long)
    If outLen > UBound(outCode) Then ReDim Preserve outCode(0 To UBound(outCode) * 2 + 1)
    outCode(outLen) = v
    outLen = outLen + 1
End Sub

Private Sub EmitNum(ByVal d As Double)
    If outNumN > UBound(outNum) Then ReDim Preserve outNum(0 To UBound(outNum) * 2 + 1)
    outNum(outNumN) = d
    Emit OP_NUM
    Emit outNumN
    outNumN = outNumN + 1
End Sub

Private Sub EmitStr(ByVal s As String)
    If outStrN > UBound(outStr) Then ReDim Preserve outStr(0 To UBound(outStr) * 2 + 1)
    outStr(outStrN) = s
    Emit OP_STR
    Emit outStrN
    outStrN = outStrN + 1
End Sub

Private Sub Fail(ByVal msg As String)
    If Not failed Then compileErr = msg
    failed = True
End Sub

' Compile the formula text after the "=" (from = index of the first character after it).
' Returns True on success; the program is in outCode(0..outLen-1).
Public Function Compile(ByVal s As String, ByVal from As Long) As Boolean
    InitPools
    outLen = 0: outNumN = 0: outStrN = 0
    compileErr = ""
    LexStart s, from
    If tokKind = T_END Then Fail "empty formula"
    PCompare
    If Not failed And tokKind <> T_END Then Fail "unexpected '" & Mid$(lxS, tokStart, 1) & "' at " & tokStart
    Compile = Not failed
End Function

Private Function IsOp(ByVal op As Long) As Boolean
    IsOp = (tokKind = T_OP And tokOp = op)
End Function

Private Sub PCompare()
    Dim op As Long
    PConcat
    Do While tokKind = T_OP And Not failed
        Select Case tokOp
        Case 61: op = OP_EQ
        Case 3: op = OP_NE
        Case 60: op = OP_LT
        Case 62: op = OP_GT
        Case 1: op = OP_LE
        Case 2: op = OP_GE
        Case Else: Exit Do
        End Select
        NextTok
        PConcat
        Emit op
    Loop
End Sub

Private Sub PConcat()
    PAdd
    Do While IsOp(38) And Not failed
        NextTok
        PAdd
        Emit OP_CAT
    Loop
End Sub

Private Sub PAdd()
    Dim op As Long
    PMul
    Do While tokKind = T_OP And Not failed
        If tokOp = 43 Then
            op = OP_ADD
        ElseIf tokOp = 45 Then
            op = OP_SUB
        Else
            Exit Do
        End If
        NextTok
        PMul
        Emit op
    Loop
End Sub

Private Sub PMul()
    Dim op As Long
    PPow
    Do While tokKind = T_OP And Not failed
        If tokOp = 42 Then
            op = OP_MUL
        ElseIf tokOp = 47 Then
            op = OP_DIV
        Else
            Exit Do
        End If
        NextTok
        PPow
        Emit op
    Loop
End Sub

Private Sub PPow()
    PUnary
    Do While IsOp(94) And Not failed
        NextTok
        PUnary
        Emit OP_POW
    Loop
End Sub

Private Sub PUnary()
    If IsOp(45) Then
        NextTok
        PUnary
        Emit OP_NEG
    ElseIf IsOp(43) Then
        NextTok
        PUnary
    Else
        PPrimary
        Do While IsOp(37) And Not failed
            NextTok
            Emit OP_PCT
        Loop
    End If
End Sub

Private Sub PPrimary()
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long, t As Long, fname As String
    If failed Then Exit Sub
    Select Case tokKind
    Case T_NUM
        EmitNum tokNum
        NextTok
    Case T_STR
        EmitStr tokText
        NextTok
    Case T_ERR
        Emit OP_ERR
        Emit tokOp
        NextTok
    Case T_REF
        r1 = tokRow: c1 = tokCol
        NextTok
        If IsOp(58) Then
            NextTok
            If tokKind <> T_REF Then Fail "a cell name must follow ':'": Exit Sub
            r2 = tokRow: c2 = tokCol
            NextTok
            If r2 < r1 Then t = r1: r1 = r2: r2 = t
            If c2 < c1 Then t = c1: c1 = c2: c2 = t
            Emit OP_RANGE: Emit r1: Emit c1: Emit r2: Emit c2
        Else
            Emit OP_REF: Emit r1: Emit c1
        End If
    Case T_NAME
        fname = tokText
        NextTok
        If IsOp(40) Then
            NextTok
            PCall fname
        ElseIf fname = "TRUE" Then
            Emit OP_BOOL: Emit 1
        ElseIf fname = "FALSE" Then
            Emit OP_BOOL: Emit 0
        Else
            Fail "unknown name " & fname
        End If
    Case T_OP
        If tokOp = 40 Then
            NextTok
            PCompare
            If Not IsOp(41) Then Fail "missing ')'": Exit Sub
            NextTok
        Else
            Fail "unexpected '" & Mid$(lxS, tokStart, 1) & "'"
        End If
    Case T_END
        Fail "the formula ends too early"
    Case Else
        Fail "bad character '" & Mid$(lxS, tokStart, 1) & "'"
    End Select
End Sub

Public Function FuncId(ByVal fname As String) As Long
    Select Case fname
    Case "SUM": FuncId = F_SUM
    Case "AVERAGE", "AVG": FuncId = F_AVERAGE
    Case "MIN": FuncId = F_MIN
    Case "MAX": FuncId = F_MAX
    Case "COUNT": FuncId = F_COUNT
    Case "COUNTA": FuncId = F_COUNTA
    Case "IF": FuncId = F_IF
    Case "ROUND": FuncId = F_ROUND
    Case "ABS": FuncId = F_ABS
    Case "SQRT": FuncId = F_SQRT
    Case "INT": FuncId = F_INT
    Case "MOD": FuncId = F_MOD
    Case "POWER": FuncId = F_POWER
    Case "PI": FuncId = F_PI
    Case "LEN": FuncId = F_LEN
    Case "LEFT": FuncId = F_LEFT
    Case "RIGHT": FuncId = F_RIGHT
    Case "MID": FuncId = F_MID
    Case "UPPER": FuncId = F_UPPER
    Case "LOWER": FuncId = F_LOWER
    Case "TRIM": FuncId = F_TRIM
    Case "CONCAT", "CONCATENATE": FuncId = F_CONCAT
    Case "TEXT": FuncId = F_TEXT
    Case "VALUE": FuncId = F_VALUE
    Case "AND": FuncId = F_AND
    Case "OR": FuncId = F_OR
    Case "NOT": FuncId = F_NOT
    Case "PRODUCT": FuncId = F_PRODUCT
    Case "ROUNDUP": FuncId = F_ROUNDUP
    Case "ROUNDDOWN": FuncId = F_ROUNDDOWN
    Case "SUMIF": FuncId = F_SUMIF
    Case "COUNTIF": FuncId = F_COUNTIF
    Case "IFERROR": FuncId = F_IFERROR
    Case "ISNUMBER": FuncId = F_ISNUMBER
    Case "ISTEXT": FuncId = F_ISTEXT
    Case "ISBLANK": FuncId = F_ISBLANK
    Case "MEDIAN": FuncId = F_MEDIAN
    Case "EXP": FuncId = F_EXP
    Case "LN": FuncId = F_LN
    Case "LOG10", "LOG": FuncId = F_LOG10
    Case "SIN": FuncId = F_SIN
    Case "COS": FuncId = F_COS
    Case "TAN": FuncId = F_TAN
    Case "SIGN": FuncId = F_SIGN
    Case "TODAY": FuncId = F_TODAY
    Case "NOW": FuncId = F_NOW
    Case "FIND": FuncId = F_FIND
    Case "SUBSTITUTE": FuncId = F_SUBSTITUTE
    Case "REPT": FuncId = F_REPT
    Case "EXACT": FuncId = F_EXACT
    Case "AVERAGEIF": FuncId = F_AVERAGEIF
    Case "STDEV": FuncId = F_STDEV
    Case "NA": FuncId = F_NA
    Case "ROWS": FuncId = F_ROWS
    Case "COLUMNS": FuncId = F_COLUMNS
    Case "CHOOSE": FuncId = F_CHOOSE
    Case "VLOOKUP": FuncId = F_VLOOKUP
    Case "TRUNC": FuncId = F_TRUNC
    Case "COUNTBLANK": FuncId = F_COUNTBLANK
    Case "YEAR": FuncId = F_YEAR
    Case "MONTH": FuncId = F_MONTH
    Case "DAY": FuncId = F_DAY
    Case "DATE": FuncId = F_DATE
    Case Else: FuncId = 0
    End Select
End Function

' argument count limits of each function (max -1 = any)
Private Sub FuncArity(ByVal f As Long, mn As Long, mx As Long)
    mn = 1: mx = -1
    Select Case f
    Case F_IF: mn = 2: mx = 3
    Case F_ROUND, F_ROUNDUP, F_ROUNDDOWN: mn = 1: mx = 2
    Case F_TRUNC: mn = 1: mx = 2
    Case F_ABS, F_SQRT, F_INT, F_LEN, F_UPPER, F_LOWER, F_TRIM, F_VALUE, F_NOT, F_ISNUMBER, _
         F_ISTEXT, F_ISBLANK, F_EXP, F_LN, F_LOG10, F_SIN, F_COS, F_TAN, F_SIGN, F_ROWS, _
         F_COLUMNS, F_COUNTBLANK, F_YEAR, F_MONTH, F_DAY: mn = 1: mx = 1
    Case F_MOD, F_POWER, F_TEXT, F_EXACT, F_REPT, F_IFERROR: mn = 2: mx = 2
    Case F_PI, F_TODAY, F_NOW, F_NA: mn = 0: mx = 0
    Case F_LEFT, F_RIGHT: mn = 1: mx = 2
    Case F_MID: mn = 3: mx = 3
    Case F_FIND: mn = 2: mx = 3
    Case F_SUBSTITUTE: mn = 3: mx = 3
    Case F_SUMIF, F_AVERAGEIF: mn = 2: mx = 3
    Case F_COUNTIF: mn = 2: mx = 2
    Case F_CHOOSE: mn = 2: mx = -1
    Case F_VLOOKUP: mn = 3: mx = 4
    Case F_DATE: mn = 3: mx = 3
    End Select
End Sub

Private Sub PCall(ByVal fname As String)
    Dim f As Long, argc As Long, mn As Long, mx As Long, jf As Long, jm As Long
    f = FuncId(fname)
    If f = 0 Then Fail "unknown function " & fname: Exit Sub
    If f = F_IF Then
        ' IF(c, a, b): only the chosen branch is evaluated
        PCompare
        If failed Then Exit Sub
        If Not (IsOp(44) Or IsOp(59)) Then Fail "IF needs at least 2 arguments": Exit Sub
        NextTok
        Emit OP_JF: jf = outLen: Emit 0
        PCompare
        Emit OP_JMP: jm = outLen: Emit 0
        outCode(jf) = outLen
        If IsOp(44) Or IsOp(59) Then
            NextTok
            PCompare
        Else
            Emit OP_BOOL: Emit 0
        End If
        outCode(jm) = outLen
        If failed Then Exit Sub
        If Not IsOp(41) Then Fail "missing ')' after IF": Exit Sub
        NextTok
        Exit Sub
    End If
    If Not IsOp(41) Then
        Do
            PCompare
            If failed Then Exit Sub
            argc = argc + 1
            If IsOp(44) Or IsOp(59) Then
                NextTok
            Else
                Exit Do
            End If
        Loop
    End If
    If Not IsOp(41) Then Fail "missing ')' after " & fname: Exit Sub
    NextTok
    FuncArity f, mn, mx
    If argc < mn Or (mx >= 0 And argc > mx) Then Fail fname & ": wrong number of arguments": Exit Sub
    Emit OP_FUNC: Emit f: Emit argc
End Sub

' ---- moving references -------------------------------------------------------------------------

' Rewrite the references of a formula (the whole text, with its "=") for a copy that
' moves by (dr, dc): relative parts move, $ parts stay. A reference that falls off the
' sheet becomes #REF!. Strings are left alone.
Public Function AdjustFormula(ByVal s As String, ByVal dr As Long, ByVal dc As Long) As String
    AdjustFormula = RewriteRefs(s, 0, dr, dc, 0, 0)
End Function

' Rewrite for inserting (n > 0) or deleting (n < 0) rows (isCol = False) or columns at
' index at: every reference at or after `at` moves, absolute or not. References to
' deleted cells become #REF!.
Public Function ShiftFormula(ByVal s As String, ByVal isCol As Boolean, ByVal at As Long, ByVal n As Long) As String
    If isCol Then
        ShiftFormula = RewriteRefs(s, 2, 0, n, at, 0)
    Else
        ShiftFormula = RewriteRefs(s, 1, n, 0, at, 0)
    End If
End Function

' mode 0: copy by (dr, dc); 1: insert/delete rows at `at`; 2: columns
Private Function RewriteRefs(ByVal s As String, ByVal mode As Long, ByVal dr As Long, ByVal dc As Long, _
                             ByVal at As Long, ByVal unused As Long) As String
    Dim res As String, last As Long, r As Long, c As Long, bad As Boolean
    If Left$(s, 1) <> "=" Then RewriteRefs = s: Exit Function
    LexStart s, 2
    last = 1
    Do While tokKind <> T_END
        If tokKind = T_REF Then
            r = tokRow: c = tokCol: bad = False
            Select Case mode
            Case 0
                If Not tokAbsR Then r = r + dr
                If Not tokAbsC Then c = c + dc
            Case 1
                If r >= at Then
                    If dr < 0 And r < at - dr Then bad = True
                    r = r + dr
                End If
            Case 2
                If c >= at Then
                    If dc < 0 And c < at - dc Then bad = True
                    c = c + dc
                End If
            End Select
            res = res & Mid$(s, last, tokStart - last)
            If bad Or r < 0 Or c < 0 Or c > 675 Or r > 99998 Then
                res = res & "#REF!"
            Else
                res = res & IIf(tokAbsC, "$", "") & ColName(c) & IIf(tokAbsR, "$", "") & CStr(r + 1)
            End If
            last = lxPos
        End If
        If tokKind = T_BAD Then Exit Do
        NextTok
    Loop
    RewriteRefs = res & Mid$(s, last)
End Function
