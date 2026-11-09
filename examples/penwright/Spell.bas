' Penwright - the spelling checker.
'
' The dictionary (penwright.dict, ~200 000 words from web2 plus modern words; see
' tools/mkdict.py) is read into one String and binary-searched in place: no table to
' build, so it is ready as soon as the file is read. Words not in it are tried without
' common English endings (-s, -es, -ies, -ed, -ing, -er, -est, -ly, -ness, -'s), since web2
' lists base forms. The user's own words (penwright.words beside the program, or added
' with AddWord) are kept in a Collection.
Option Explicit

Private dict As String
Private dictLen As Long
Private user As Collection
Private userPath As String
Public SpellReady As Boolean
Public SpellError As String

Public Function LoadDictionary(ByVal path As String, ByVal userFile As String) As Boolean
    Dim fn As Integer, l As String
    On Error GoTo Bad
    dict = ReadFile(path)
    dict = LCase$(Replace(dict, vbCr, ""))
    If Left$(dict, 1) <> vbLf Then dict = vbLf & dict
    If Right$(dict, 1) <> vbLf Then dict = dict & vbLf
    dictLen = Len(dict)
    Set user = New Collection
    userPath = userFile
    If userFile <> "" Then
        If Dir(userFile) <> "" Then
            fn = FreeFile
            Open userFile For Input As #fn
            Do While Not EOF(fn)
                Line Input #fn, l
                l = LCase$(Trim$(l))
                If l <> "" Then AddUser l
            Loop
            Close #fn
        End If
    End If
    SpellReady = True
    LoadDictionary = True
    Exit Function
Bad:
    SpellError = Err.Description
    SpellReady = False
End Function

Private Sub AddUser(ByVal w As String)
    On Error Resume Next
    user.Add w, w
End Sub

' add a word to the user's list (and its file)
Public Sub AddWord(ByVal w As String)
    Dim fn As Integer
    w = LCase$(w)
    If user Is Nothing Then Set user = New Collection
    If InUser(w) Then Exit Sub
    AddUser w
    If userPath <> "" Then
        On Error Resume Next
        fn = FreeFile
        Open userPath For Append As #fn
        Print #fn, w
        Close #fn
    End If
End Sub

Private Function InUser(ByVal w As String) As Boolean
    Dim v As Variant
    If user Is Nothing Then Exit Function
    On Error GoTo Nope
    v = user(w)
    InUser = True
Nope:
End Function

' binary search of the word list (w lowercase)
Public Function InDict(ByVal w As String) As Boolean
    Dim lo As Long, hi As Long, mid_ As Long, a As Long, b As Long, t As String
    If dictLen = 0 Then Exit Function
    lo = 1: hi = dictLen
    Do While lo < hi
        mid_ = (lo + hi) \ 2
        a = InStrRev(dict, vbLf, mid_)          ' the newline before the word at mid_
        b = InStr(a + 1, dict, vbLf)
        If b = 0 Then Exit Function
        t = Mid$(dict, a + 1, b - a - 1)
        If t = w Then InDict = True: Exit Function
        If t < w Then
            lo = b + 1
        Else
            hi = a
        End If
        If a = 0 Then Exit Function
    Loop
End Function

Private Function Known(ByVal w As String) As Boolean
    If w = "" Then Exit Function
    If InDict(w) Then Known = True: Exit Function
    Known = InUser(w)
End Function

' is the word spelt right? (case-insensitive; numbers and single letters are fine)
Public Function CheckWord(ByVal w As String) As Boolean
    Dim l As String, n As Long, b As String
    l = LCase$(w)
    If Left$(l, 1) = "'" Then l = Mid$(l, 2)
    If Right$(l, 1) = "'" Then l = Left$(l, Len(l) - 1)
    n = Len(l)
    If n <= 1 Then CheckWord = True: Exit Function
    If l Like "*#*" Then CheckWord = True: Exit Function
    If w = UCase$(w) And n <= 6 Then CheckWord = True: Exit Function     ' acronyms: RTF, HTML
    If Known(l) Then CheckWord = True: Exit Function
    If Right$(l, 2) = "'s" Then If Known(Left$(l, n - 2)) Then CheckWord = True: Exit Function
    If Right$(l, 1) = "s" Then If Known(Left$(l, n - 1)) Then CheckWord = True: Exit Function
    If Right$(l, 2) = "es" Then If Known(Left$(l, n - 2)) Then CheckWord = True: Exit Function
    If Right$(l, 3) = "ies" Then If Known(Left$(l, n - 3) & "y") Then CheckWord = True: Exit Function
    If Right$(l, 2) = "ed" Or Right$(l, 2) = "er" Then
        b = Left$(l, n - 2)
        If Known(b) Or Known(b & "e") Then CheckWord = True: Exit Function
        If Right$(b, 1) = "i" Then If Known(Left$(b, Len(b) - 1) & "y") Then CheckWord = True: Exit Function
        If Len(b) > 2 Then If Right$(b, 1) = Mid$(b, Len(b) - 1, 1) Then If Known(Left$(b, Len(b) - 1)) Then CheckWord = True: Exit Function
    End If
    If Right$(l, 3) = "ing" Or Right$(l, 3) = "est" Then
        b = Left$(l, n - 3)
        If Known(b) Or Known(b & "e") Then CheckWord = True: Exit Function
        If Right$(b, 1) = "i" Then If Known(Left$(b, Len(b) - 1) & "y") Then CheckWord = True: Exit Function
        If Len(b) > 2 Then If Right$(b, 1) = Mid$(b, Len(b) - 1, 1) Then If Known(Left$(b, Len(b) - 1)) Then CheckWord = True: Exit Function
    End If
    If Right$(l, 2) = "ly" Then
        b = Left$(l, n - 2)
        If Known(b) Then CheckWord = True: Exit Function
        If Right$(b, 1) = "i" Then If Known(Left$(b, Len(b) - 1) & "y") Then CheckWord = True: Exit Function
    End If
    If Right$(l, 4) = "ness" Then If Known(Left$(l, n - 4)) Then CheckWord = True: Exit Function
End Function

' Up to max suggestions for a misspelt word: dictionary words one edit away (a letter
' deleted, swapped with its neighbour, changed or inserted), keeping the word's case.
Public Function Suggest(ByVal w As String, ByVal max As Long) As String
    Dim l As String, n As Long, i As Long, ch As Long, c As String, res As String, cnt As Long, cand As String
    l = LCase$(w)
    n = Len(l)
    ' swaps first: the most common typing slip
    For i = 1 To n - 1
        cand = Left$(l, i - 1) & Mid$(l, i + 1, 1) & Mid$(l, i, 1) & Mid$(l, i + 2)
        TryCand cand, w, res, cnt, max
    Next i
    For i = 1 To n
        cand = Left$(l, i - 1) & Mid$(l, i + 1)
        TryCand cand, w, res, cnt, max
    Next i
    For i = 1 To n
        For ch = 97 To 122
            c = Chr$(ch)
            If c <> Mid$(l, i, 1) Then
                cand = Left$(l, i - 1) & c & Mid$(l, i + 1)
                TryCand cand, w, res, cnt, max
            End If
        Next ch
    Next i
    For i = 0 To n
        For ch = 97 To 122
            cand = Left$(l, i) & Chr$(ch) & Mid$(l, i + 1)
            TryCand cand, w, res, cnt, max
        Next ch
    Next i
    Suggest = res
End Function

Private Sub TryCand(ByVal cand As String, ByVal orig As String, res As String, cnt As Long, ByVal max As Long)
    Dim shown As String
    If cnt >= max Or cand = "" Then Exit Sub
    If Not Known(cand) Then Exit Sub
    ' keep the case of the word: Capitalised or ALL CAPS
    If orig = UCase$(orig) And Len(orig) > 1 Then
        shown = UCase$(cand)
    ElseIf Left$(orig, 1) = UCase$(Left$(orig, 1)) And Left$(orig, 1) <> LCase$(Left$(orig, 1)) Then
        shown = UCase$(Left$(cand, 1)) & Mid$(cand, 2)
    Else
        shown = cand
    End If
    If InStr(vbLf & res, vbLf & shown & vbLf) > 0 Then Exit Sub
    res = res & shown & vbLf
    cnt = cnt + 1
End Sub

' Find the next misspelt word from (p, o); True with (p, o) = its start and wl its length
Public Function NextMisspelt(p As Long, o As Long, wl As Long) As Boolean
    Dim pp As Long, i As Long, s As String, ws As Long, k As Long, ch As String, st As Long
    For pp = p To NP - 1
        s = pText(pp)
        If pp = p Then i = o + 1 Else i = 1
        If pStyle(pp) = PS_CODE Then i = Len(s) + 1
        Do While i <= Len(s)
            ch = Mid$(s, i, 1)
            If IsLetterCh(ch) Then
                st = i
                Do While i <= Len(s)
                    ch = Mid$(s, i, 1)
                    If Not (IsLetterCh(ch) Or ch = "'" Or (ch >= "0" And ch <= "9")) Then Exit Do
                    i = i + 1
                Loop
                k = i - st
                Dim w As String
                w = Mid$(s, st, k)
                Do While Right$(w, 1) = "'"
                    w = Left$(w, Len(w) - 1): k = k - 1
                Loop
                If Not CheckWord(w) Then
                    p = pp: o = st - 1: wl = k
                    NextMisspelt = True
                    Exit Function
                End If
            Else
                i = i + 1
            End If
        Loop
    Next pp
End Function

Private Function IsLetterCh(ByVal ch As String) As Boolean
    Dim k As Long
    k = Asc(ch)
    IsLetterCh = (k >= 65 And k <= 90) Or (k >= 97 And k <= 122) Or (k >= 192 And k <> 215 And k <> 247)
End Function
