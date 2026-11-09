' Riffwright - the song model: patterns, samples, order list, and .mod load/save
'
' The song lives here, in BASIC. Cells are kept as the four fields of a ProTracker cell
' (period, sample, effect, parameter) with the period stored raw, so a loaded file saves
' back byte for byte. Every edit goes through Edit.bas, which also mirrors it into the
' player (Player.bas) so the music changes while it plays.
Option Explicit

Public Const ROWS As Long = 64
Public Const MAXCH As Long = 8
Public Const NSMP As Long = 31
Public Const MAXPAT As Long = 100
Public Const NNOTES As Long = 60          ' note 1..60 = C-0..B-4; ProTracker uses 13..48

' ---- song
Public songTitle As String                ' 20 raw bytes (padded with Chr$(0))
Public songTag As String                  ' "M.K.", "M!K!", "FLT4", "6CHN", "8CHN" ...
Public nch As Long                        ' channels (4, 6 or 8)
Public songLen As Long                    ' 1..128 orders in use
Public songRestart As Long                ' byte 951, kept raw (127 or a restart position)
Public orders(0 To 127) As Long
Public nPat As Long                       ' patterns stored in the file
Public initSpeed As Long                  ' ticks per row at the start (6)
Public initTempo As Long                  ' BPM at the start (125)
Public songDirty As Boolean
Public songPath As String

' ---- pattern cells, index (pat * ROWS + row) * MAXCH + ch
Public cPer() As Long                     ' raw period (0 = no note)
Public cSmp() As Long                     ' sample 0..31
Public cFx() As Long                      ' effect 0..15
Public cPrm() As Long                     ' parameter 0..255

' ---- samples 1..31
Public smpName(1 To 31) As String         ' 22 raw bytes
Public smpLen(1 To 31) As Long            ' bytes (even)
Public smpFine(1 To 31) As Long           ' finetune nibble 0..15 (8..15 = -8..-1)
Public smpVol(1 To 31) As Long            ' 0..64
Public smpLoopS(1 To 31) As Long          ' loop start, bytes
Public smpLoopL(1 To 31) As Long          ' loop length, bytes (2 = no loop)
Public smpData(1 To 31) As Variant        ' Byte array 0..smpLen-1 (signed 8-bit as stored), or Empty
Public smpRawHi(1 To 31) As Long          ' high nibble of the finetune byte, kept raw
Public songTail As Variant                ' bytes after the last sample (kept for exact saves)

' ---- note tables
Public perOfNote(0 To 60) As Long         ' finetune 0 period of note n (1..60)
Public noteOfPer(0 To 4095) As Long       ' nearest note of a period
Public noteName(0 To 60) As String        ' "C-3", "---" for 0
Private tablesReady As Boolean

Public lastError As String

Public Function CellIdx(ByVal pat As Long, ByVal row As Long, ByVal ch As Long) As Long
    CellIdx = (pat * ROWS + row) * MAXCH + ch
End Function

Public Sub InitTables()
    Dim base As Variant, n As Long, o As Long, i As Long, p As Long, best As Long, d As Long
    Dim names As Variant
    If tablesReady Then Exit Sub
    ' ProTracker's finetune 0 periods, octave 1 (C-1 = 856); the other octaves are halved/doubled
    base = Array(1712, 1616, 1525, 1440, 1357, 1281, 1209, 1141, 1077, 1017, 961, 907)
    names = Array("C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-")
    noteName(0) = "---"
    For o = 0 To 4
        For i = 0 To 11
            n = o * 12 + i + 1
            Select Case o
                Case 0: p = base(i)
                Case 1: p = Choose(i + 1, 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453)
                Case 2: p = Choose(i + 1, 428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226)
                Case 3: p = Choose(i + 1, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113)
                Case 4: p = Choose(i + 1, 107, 101, 95, 90, 85, 80, 76, 71, 67, 63, 60, 57)
            End Select
            perOfNote(n) = p
            noteName(n) = names(i) & CStr(o)
        Next i
    Next o
    ' nearest note for every period (periods between two notes go to the closer one)
    noteOfPer(0) = 0
    best = 1
    For p = 1 To 4095
        best = 1
        For n = 2 To 60
            d = Abs(perOfNote(n) - p)
            If d < Abs(perOfNote(best) - p) Then best = n
        Next n
        noteOfPer(p) = best
    Next p
    tablesReady = True
End Sub

' ---- a new, empty song
Public Sub NewSong(Optional ByVal channels As Long = 4)
    Dim i As Long
    InitTables
    nch = channels
    Select Case nch
        Case 6: songTag = "6CHN"
        Case 8: songTag = "8CHN"
        Case Else: nch = 4: songTag = "M.K."
    End Select
    songTitle = String$(20, Chr$(0))
    songLen = 1
    songRestart = 127
    For i = 0 To 127: orders(i) = 0: Next i
    nPat = 1
    initSpeed = 6
    initTempo = 125
    ReDim cPer(0 To MAXPAT * ROWS * MAXCH - 1)
    ReDim cSmp(0 To MAXPAT * ROWS * MAXCH - 1)
    ReDim cFx(0 To MAXPAT * ROWS * MAXCH - 1)
    ReDim cPrm(0 To MAXPAT * ROWS * MAXCH - 1)
    For i = 1 To NSMP
        ClearSample i
    Next i
    songTail = Empty
    songDirty = False
    songPath = ""
End Sub

Public Sub ClearSample(ByVal i As Long)
    smpName(i) = String$(22, Chr$(0))
    smpLen(i) = 0
    smpFine(i) = 0
    smpRawHi(i) = 0
    smpVol(i) = 0
    smpLoopS(i) = 0
    smpLoopL(i) = 2
    smpData(i) = Empty
End Sub

' text of a raw, NUL-padded name
Public Function CleanName(ByVal raw As String) As String
    Dim k As Long
    k = InStr(raw, Chr$(0))
    If k > 0 Then raw = Left$(raw, k - 1)
    CleanName = raw
End Function

' a name padded to n raw bytes
Public Function PadName(ByVal s As String, ByVal n As Long) As String
    If Len(s) >= n Then PadName = Left$(s, n) Else PadName = s & String$(n - Len(s), Chr$(0))
End Function

Public Function TitleText() As String
    TitleText = CleanName(songTitle)
End Function

Public Function SampleText(ByVal i As Long) As String
    SampleText = CleanName(smpName(i))
End Function

' signed finetune -8..7 of the nibble
Public Function FineSigned(ByVal i As Long) As Long
    If smpFine(i) >= 8 Then FineSigned = smpFine(i) - 16 Else FineSigned = smpFine(i)
End Function

' ---- byte helpers
Private Function W16(b() As Byte, ByVal o As Long) As Long
    W16 = CLng(b(o)) * 256 + b(o + 1)
End Function

Private Sub PutW16(b() As Byte, ByVal o As Long, ByVal v As Long)
    b(o) = (v \ 256) And 255
    b(o + 1) = v And 255
End Sub

Private Function BytesStr(b() As Byte, ByVal o As Long, ByVal n As Long) As String
    Dim s As String, i As Long
    s = String$(n, Chr$(0))
    For i = 0 To n - 1
        Mid$(s, i + 1, 1) = Chr$(b(o + i))
    Next i
    BytesStr = s
End Function

Private Sub PutStr(b() As Byte, ByVal o As Long, ByVal s As String, ByVal n As Long)
    Dim i As Long
    For i = 0 To n - 1
        If i < Len(s) Then b(o + i) = Asc(Mid$(s, i + 1, 1)) Else b(o + i) = 0
    Next i
End Sub

' channels for a format tag, 0 if it isn't one
Public Function ChannelsOfTag(ByVal t As String) As Long
    Select Case t
        Case "M.K.", "M!K!", "FLT4", "4CHN", "M&K!", "N.T.": ChannelsOfTag = 4
        Case "6CHN": ChannelsOfTag = 6
        Case "8CHN", "FLT8", "OCTA", "CD81": ChannelsOfTag = 8
        Case Else: ChannelsOfTag = 0
    End Select
End Function

' ---- load a .mod (31-sample ProTracker; 4, 6 or 8 channels); False and lastError on failure
Public Function LoadMod(ByVal path As String) As Boolean
    Dim f As Integer, n As Long, b() As Byte, i As Long, o As Long, ch As Long
    Dim p As Long, r As Long, c As Long, k As Long, b0 As Long, b2 As Long
    Dim lens(1 To 31) As Long, avail As Long, d() As Byte, flt8 As Boolean
    On Error GoTo bad
    InitTables
    n = FileLen(path)
    If n < 1084 Then lastError = "not a ProTracker module (too short)": Exit Function
    ReDim b(0 To n - 1)
    f = FreeFile
    Open path For Binary Access Read As #f
    Get #f, , b
    Close #f
    f = 0
    ch = ChannelsOfTag(BytesStr(b, 1080, 4))
    If ch = 0 Then lastError = "unknown module format '" & CleanName(BytesStr(b, 1080, 4)) & "'": Exit Function
    NewSong ch
    songTag = BytesStr(b, 1080, 4)
    flt8 = (songTag = "FLT8")
    songTitle = BytesStr(b, 0, 20)
    For i = 1 To NSMP
        o = 20 + (i - 1) * 30
        smpName(i) = BytesStr(b, o, 22)
        lens(i) = W16(b, o + 22) * 2
        smpFine(i) = b(o + 24) And 15
        smpRawHi(i) = b(o + 24) And &HF0
        smpVol(i) = b(o + 25)
        smpLoopS(i) = W16(b, o + 26) * 2
        smpLoopL(i) = W16(b, o + 28) * 2
    Next i
    songLen = b(950)
    songRestart = b(951)
    nPat = 0
    For i = 0 To 127
        orders(i) = b(952 + i)
        If orders(i) + 1 > nPat Then nPat = orders(i) + 1
    Next i
    If flt8 Then
        ' Startrekker 8 channels: patterns are pairs of 4-channel patterns
        If nPat Mod 2 = 1 Then nPat = nPat + 1
    End If
    If nPat > MAXPAT Then lastError = "too many patterns": Exit Function
    If songLen < 1 Or songLen > 128 Then lastError = "bad song length": Exit Function
    o = 1084
    If o + nPat * ROWS * ch * 4 > n Then lastError = "the file is cut short (patterns)": Exit Function
    If flt8 Then
        For p = 0 To nPat \ 2 - 1
            For r = 0 To ROWS - 1
                For c = 0 To 7
                    k = 1084 + (p * 2 + (c \ 4)) * 1024 + r * 16 + (c Mod 4) * 4
                    LoadCell b, k, p, r, c
                Next c
            Next r
        Next p
        For i = 0 To 127: orders(i) = orders(i) \ 2: Next i
        o = 1084 + nPat * 1024
        nPat = nPat \ 2
    Else
        For p = 0 To nPat - 1
            For r = 0 To ROWS - 1
                For c = 0 To ch - 1
                    LoadCell b, o, p, r, c
                    o = o + 4
                Next c
            Next r
        Next p
    End If
    For i = 1 To NSMP
        smpLen(i) = lens(i)
        If lens(i) > 0 Then
            avail = n - o
            If avail < 0 Then avail = 0
            If lens(i) > avail Then smpLen(i) = avail      ' cut short: keep what is there
            If smpLen(i) > 0 Then
                ReDim d(0 To smpLen(i) - 1)
                CopyBytes b, o, d, 0, smpLen(i)
                smpData(i) = d
            End If
            o = o + smpLen(i)
        End If
    Next i
    If o < n Then
        ReDim d(0 To n - o - 1)
        CopyBytes b, o, d, 0, n - o
        songTail = d
    End If
    songPath = path
    songDirty = False
    LoadMod = True
    Exit Function
bad:
    lastError = Err.Description
    If f <> 0 Then Close #f
End Function

Private Sub LoadCell(b() As Byte, ByVal o As Long, ByVal p As Long, ByVal r As Long, ByVal c As Long)
    Dim k As Long, b0 As Long, b2 As Long
    k = (p * ROWS + r) * MAXCH + c
    b0 = b(o)
    b2 = b(o + 2)
    cPer(k) = (b0 And 15) * 256 + b(o + 1)
    cSmp(k) = (b0 And &HF0) + (b2 \ 16)
    cFx(k) = b2 And 15
    cPrm(k) = b(o + 3)
End Sub

Public Sub CopyBytes(src() As Byte, ByVal so As Long, dst() As Byte, ByVal dofs As Long, ByVal n As Long)
    Dim i As Long
    For i = 0 To n - 1
        dst(dofs + i) = src(so + i)
    Next i
End Sub

' the size the song takes as a .mod
Public Function ModSize() As Long
    Dim i As Long, s As Long
    s = 1084 + nPat * ROWS * nch * 4
    For i = 1 To NSMP: s = s + smpLen(i): Next i
    If Not IsEmpty(songTail) Then s = s + UBound(songTail) + 1
    ModSize = s
End Function

' ---- save as .mod; False and lastError on failure
Public Function SaveMod(ByVal path As String) As Boolean
    Dim b() As Byte, i As Long, o As Long, p As Long, r As Long, c As Long, k As Long
    Dim f As Integer, d() As Byte, tag As String
    On Error GoTo bad
    FitPatternCount
    ReDim b(0 To ModSize() - 1)
    PutStr b, 0, songTitle, 20
    For i = 1 To NSMP
        o = 20 + (i - 1) * 30
        PutStr b, o, smpName(i), 22
        PutW16 b, o + 22, smpLen(i) \ 2
        b(o + 24) = smpRawHi(i) Or (smpFine(i) And 15)
        b(o + 25) = smpVol(i)
        PutW16 b, o + 26, smpLoopS(i) \ 2
        PutW16 b, o + 28, smpLoopL(i) \ 2
    Next i
    b(950) = songLen
    b(951) = songRestart
    For i = 0 To 127: b(952 + i) = orders(i): Next i
    tag = songTag
    If tag = "FLT8" Then tag = "8CHN"           ' saved in the plain layout
    If ChannelsOfTag(tag) <> nch Then
        Select Case nch
            Case 6: tag = "6CHN"
            Case 8: tag = "8CHN"
            Case Else: If nPat > 64 Then tag = "M!K!" Else tag = "M.K."
        End Select
    End If
    PutStr b, 1080, tag, 4
    o = 1084
    For p = 0 To nPat - 1
        For r = 0 To ROWS - 1
            For c = 0 To nch - 1
                k = (p * ROWS + r) * MAXCH + c
                b(o) = (cSmp(k) And &HF0) Or ((cPer(k) \ 256) And 15)
                b(o + 1) = cPer(k) And 255
                b(o + 2) = ((cSmp(k) And 15) * 16) Or (cFx(k) And 15)
                b(o + 3) = cPrm(k)
                o = o + 4
            Next c
        Next r
    Next p
    For i = 1 To NSMP
        If smpLen(i) > 0 Then
            d = smpData(i)
            CopyBytes d, 0, b, o, smpLen(i)
            o = o + smpLen(i)
        End If
    Next i
    If Not IsEmpty(songTail) Then
        d = songTail
        CopyBytes d, 0, b, o, UBound(d) + 1
    End If
    If Len(Dir$(path)) > 0 Then Kill path
    f = FreeFile
    Open path For Binary Access Write As #f
    Put #f, , b
    Close #f
    f = 0
    songPath = path
    songDirty = False
    SaveMod = True
    Exit Function
bad:
    lastError = Err.Description
    If f <> 0 Then Close #f
End Function

' ---- cell text for the editor: "C-3 1F C40"
Public Function NoteText(ByVal per As Long) As String
    If per = 0 Then NoteText = "---" Else NoteText = noteName(noteOfPer(per And 4095))
End Function

Public Function Hex2(ByVal v As Long) As String
    Hex2 = Right$("0" & Hex$(v), 2)
End Function

Public Function CellText(ByVal k As Long) As String
    Dim s As String
    s = NoteText(cPer(k)) & " "
    If cSmp(k) = 0 Then s = s & ".. " Else s = s & Hex2(cSmp(k)) & " "
    If cFx(k) = 0 And cPrm(k) = 0 Then s = s & "..." Else s = s & Hex$(cFx(k)) & Hex2(cPrm(k))
    CellText = s
End Function

' highest pattern used by the order list + 1 (what a save stores)
Public Sub RecountPatterns()
    Dim i As Long, m As Long
    m = 0
    For i = 0 To 127
        If orders(i) + 1 > m Then m = orders(i) + 1
    Next i
    If m > nPat Then nPat = m
End Sub

' a pattern holds anything?
Public Function PatternUsed(ByVal p As Long) As Boolean
    Dim k As Long, k1 As Long
    k1 = (p + 1) * ROWS * MAXCH - 1
    For k = p * ROWS * MAXCH To k1
        If cPer(k) Or cSmp(k) Or cFx(k) Or cPrm(k) Then PatternUsed = True: Exit Function
    Next k
End Function

' A .mod stores the patterns 0 .. the highest number in all 128 order entries. Before a
' save, make that cover every pattern with notes in it: the highest one goes into the first
' order entry past the song's end (never played), as players read all 128 entries.
Public Sub FitPatternCount()
    Dim i As Long, m As Long, hp As Long
    m = 0
    For i = 0 To 127
        If orders(i) + 1 > m Then m = orders(i) + 1
    Next i
    hp = -1
    For i = MAXPAT - 1 To m Step -1
        If PatternUsed(i) Then hp = i: Exit For
    Next i
    If hp >= m And songLen < 128 Then orders(songLen) = hp: m = hp + 1
    nPat = m
End Sub
