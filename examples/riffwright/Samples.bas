' Riffwright - samples: load and save 8SVX, WAV and raw, and the sample editor's operations
Option Explicit

Public Const C3_RATE As Long = 16574      ' Hz at which C-3 (period 214) plays a sample at its own pitch (PAL)
Public smpError As String
Public smpInfo As String                  ' what the last load did ("WAV 44100 Hz 16 bit stereo")

Public Function FileBytes(ByVal path As String) As Variant
    Dim b() As Byte, f As Integer, n As Long
    n = FileLen(path)
    If n = 0 Then FileBytes = Empty: Exit Function
    ReDim b(0 To n - 1)
    f = FreeFile
    Open path For Binary Access Read As #f
    Get #f, , b
    Close #f
    FileBytes = b
End Function

Public Sub WriteBytes(ByVal path As String, b() As Byte)
    Dim f As Integer
    If Len(Dir$(path)) > 0 Then Kill path
    f = FreeFile
    Open path For Binary Access Write As #f
    Put #f, , b
    Close #f
End Sub

Private Function Tag4(b As Variant, ByVal o As Long) As String
    Tag4 = Chr$(b(o)) & Chr$(b(o + 1)) & Chr$(b(o + 2)) & Chr$(b(o + 3))
End Function

Private Function BE32(b As Variant, ByVal o As Long) As Long
    BE32 = ((b(o) And 127) * &H1000000) Or (CLng(b(o + 1)) * &H10000) Or (CLng(b(o + 2)) * 256) Or b(o + 3)
End Function

Private Function BE16(b As Variant, ByVal o As Long) As Long
    BE16 = CLng(b(o)) * 256 + b(o + 1)
End Function

Private Function LE32(b As Variant, ByVal o As Long) As Long
    LE32 = ((b(o + 3) And 127) * &H1000000) Or (CLng(b(o + 2)) * &H10000) Or (CLng(b(o + 1)) * 256) Or b(o)
End Function

Private Function LE16(b As Variant, ByVal o As Long) As Long
    LE16 = CLng(b(o + 1)) * 256 + b(o)
End Function

Private Function BaseName(ByVal p As String) As String
    Dim k As Long
    k = InStrRev(p, "/"): If InStrRev(p, ":") > k Then k = InStrRev(p, ":")
    p = Mid$(p, k + 1)
    k = InStrRev(p, ".")
    If k > 1 Then p = Left$(p, k - 1)
    BaseName = Left$(p, 22)
End Function

' ---- load a sample file into slot i (format from its contents); False and smpError on failure
Public Function LoadSampleFile(ByVal i As Long, ByVal path As String) As Boolean
    Dim b As Variant, d() As Byte, n As Long, ls As Long, ll As Long, vol As Long, nm As String
    On Error GoTo bad
    b = FileBytes(path)
    If IsEmpty(b) Then smpError = "the file is empty": Exit Function
    n = UBound(b) + 1
    nm = BaseName(path)
    vol = 64: ls = 0: ll = 2
    If n >= 12 Then
        If Tag4(b, 0) = "FORM" And Tag4(b, 8) = "8SVX" Then
            If Not Parse8SVX(b, d, ls, ll, vol, nm) Then Exit Function
            GoTo store
        End If
        If Tag4(b, 0) = "RIFF" And Tag4(b, 8) = "WAVE" Then
            If Not ParseWAV(b, d) Then Exit Function
            GoTo store
        End If
    End If
    ' raw: signed 8-bit
    ReDim d(0 To n - 1)
    Dim j As Long
    For j = 0 To n - 1: d(j) = b(j): Next j
    smpInfo = "raw 8 bit, " & n & " bytes"
store:
    n = UBound(d) + 1
    If n > 131070 Then smpInfo = smpInfo & ", cut to 131070 bytes": n = 131070
    If n Mod 2 = 1 Then n = n - 1
    UndoSample "load sample", i
    smpName(i) = PadName(nm, 22)
    If n > 0 Then
        If UBound(d) + 1 > n Then ReDim Preserve d(0 To n - 1)
        smpData(i) = d
    Else
        smpData(i) = Empty
    End If
    smpLen(i) = n
    smpVol(i) = vol
    smpFine(i) = 0
    If ls + ll > n Or ll <= 2 Then ls = 0: ll = 2
    smpLoopS(i) = (ls \ 2) * 2
    smpLoopL(i) = (ll \ 2) * 2
    MirrorSample i
    LoadSampleFile = True
    Exit Function
bad:
    smpError = Err.Description
End Function

Private Function Parse8SVX(b As Variant, d() As Byte, ls As Long, ll As Long, vol As Long, nm As String) As Boolean
    Dim o As Long, n As Long, ck As String, sz As Long, oneShot As Long, rpt As Long, comp As Long
    Dim j As Long, gotBody As Boolean, rate As Long, x As Long, fib As Variant, k As Long
    n = UBound(b) + 1
    o = 12
    Do While o + 8 <= n
        ck = Tag4(b, o): sz = BE32(b, o + 4)
        If o + 8 + sz > n Then sz = n - o - 8
        Select Case ck
            Case "VHDR"
                oneShot = BE32(b, o + 8)
                rpt = BE32(b, o + 12)
                rate = BE16(b, o + 20)
                comp = b(o + 23)
                vol = (BE32(b, o + 24) * 64) \ 65536
                If vol > 64 Then vol = 64
            Case "NAME"
                nm = ""
                For j = 0 To sz - 1
                    If b(o + 8 + j) = 0 Then Exit For
                    nm = nm & Chr$(b(o + 8 + j))
                Next j
                nm = Left$(nm, 22)
            Case "BODY"
                If comp = 1 Then
                    ' Fibonacci-delta: 2 bytes header, then 2 samples per byte
                    fib = Array(-34, -21, -13, -8, -5, -3, -2, -1, 0, 1, 2, 3, 5, 8, 13, 21)
                    ReDim d(0 To (sz - 2) * 2 - 1)
                    x = b(o + 9): If x > 127 Then x = x - 256
                    k = 0
                    For j = 2 To sz - 1
                        x = x + fib(b(o + 8 + j) \ 16): x = ((x + 128) And 255) - 128
                        d(k) = x And 255: k = k + 1
                        x = x + fib(b(o + 8 + j) And 15): x = ((x + 128) And 255) - 128
                        d(k) = x And 255: k = k + 1
                    Next j
                ElseIf comp = 0 Then
                    j = sz
                    If oneShot + rpt > 0 And oneShot + rpt < j Then j = oneShot + rpt    ' first octave only
                    ReDim d(0 To j - 1)
                    For k = 0 To j - 1: d(k) = b(o + 8 + k): Next k
                Else
                    smpError = "unknown 8SVX compression " & comp
                    Exit Function
                End If
                gotBody = True
        End Select
        o = o + 8 + sz + (sz And 1)
    Loop
    If Not gotBody Then smpError = "8SVX without a BODY": Exit Function
    If rpt > 0 Then ls = oneShot: ll = rpt
    smpInfo = "8SVX " & rate & " Hz"
    If comp = 1 Then smpInfo = smpInfo & ", Fibonacci-delta"
    Parse8SVX = True
End Function

Private Function ParseWAV(b As Variant, d() As Byte) As Boolean
    Dim o As Long, n As Long, ck As String, sz As Long, fmt As Long, chans As Long, rate As Long, bits As Long
    Dim dataO As Long, dataN As Long, frames As Long, bpf As Long, j As Long, v As Long, c As Long, s As Long
    Dim outN As Long, rstep As Double, pos As Double, f As Long
    n = UBound(b) + 1
    o = 12
    Do While o + 8 <= n
        ck = Tag4(b, o): sz = LE32(b, o + 4)
        If o + 8 + sz > n Then sz = n - o - 8
        Select Case ck
            Case "fmt "
                fmt = LE16(b, o + 8): chans = LE16(b, o + 10): rate = LE32(b, o + 12): bits = LE16(b, o + 22)
            Case "data"
                dataO = o + 8: dataN = sz
        End Select
        o = o + 8 + sz + (sz And 1)
    Loop
    If fmt <> 1 Or chans < 1 Or (bits <> 8 And bits <> 16) Then
        smpError = "only PCM WAV files with 8 or 16 bit samples": Exit Function
    End If
    If dataN = 0 Then smpError = "WAV without data": Exit Function
    bpf = chans * (bits \ 8)
    frames = dataN \ bpf
    smpInfo = "WAV " & rate & " Hz " & bits & " bit"
    If chans = 2 Then smpInfo = smpInfo & " stereo"
    ' resample anything faster than 22 kHz to C-3's rate, so a C-3 plays it at its pitch
    rstep = 1
    If rate > 22050 Then
        rstep = rate / C3_RATE
        smpInfo = smpInfo & ", resampled to " & C3_RATE & " Hz"
    End If
    outN = Int(frames / rstep)
    If outN > 131070 Then outN = 131070
    If outN < 1 Then smpError = "WAV too short": Exit Function
    ReDim d(0 To outN - 1)
    For j = 0 To outN - 1
        f = Int(j * rstep)
        s = 0
        For c = 0 To chans - 1
            If bits = 8 Then
                v = CLng(b(dataO + f * bpf + c)) - 128
            Else
                v = b(dataO + f * bpf + c * 2 + 1): If v > 127 Then v = v - 256
            End If
            s = s + v
        Next c
        s = s \ chans
        d(j) = s And 255
    Next j
    ParseWAV = True
End Function

' ---- save sample i: fmt "8svx", "wav" or "raw"
Public Function SaveSampleFile(ByVal i As Long, ByVal path As String, ByVal fmt As String) As Boolean
    Dim b() As Byte, n As Long, d As Variant, j As Long, o As Long, nm As String, ln As Long
    On Error GoTo bad
    n = smpLen(i)
    If n = 0 Then smpError = "the sample is empty": Exit Function
    d = smpData(i)
    nm = SampleText(i)
    Select Case LCase$(fmt)
        Case "raw"
            ReDim b(0 To n - 1)
            For j = 0 To n - 1: b(j) = d(j): Next j
        Case "wav"
            ReDim b(0 To 44 + n - 1 + (n And 1))
            PutTag b, 0, "RIFF": PutLE32 b, 4, 36 + n + (n And 1): PutTag b, 8, "WAVE"
            PutTag b, 12, "fmt ": PutLE32 b, 16, 16
            PutLE16 b, 20, 1: PutLE16 b, 22, 1: PutLE32 b, 24, C3_RATE: PutLE32 b, 28, C3_RATE
            PutLE16 b, 32, 1: PutLE16 b, 34, 8
            PutTag b, 36, "data": PutLE32 b, 40, n
            For j = 0 To n - 1: b(44 + j) = (d(j) + 128) And 255: Next j
        Case Else
            ln = Len(nm) + 1: If ln Mod 2 = 1 Then ln = ln + 1
            ReDim b(0 To 12 + 28 + 8 + ln + 8 + n - 1 + (n And 1))
            PutTag b, 0, "FORM": PutBE32 b, 4, UBound(b) + 1 - 8: PutTag b, 8, "8SVX"
            o = 12
            PutTag b, o, "VHDR": PutBE32 b, o + 4, 20
            If smpLoopL(i) > 2 Then
                PutBE32 b, o + 8, smpLoopS(i): PutBE32 b, o + 12, smpLoopL(i)
            Else
                PutBE32 b, o + 8, n: PutBE32 b, o + 12, 0
            End If
            PutBE32 b, o + 16, 32
            b(o + 20) = (C3_RATE \ 256) And 255: b(o + 21) = C3_RATE And 255
            b(o + 22) = 1: b(o + 23) = 0
            PutBE32 b, o + 24, smpVol(i) * 1024           ' volume as 16.16 fixed, 64 = 1.0
            o = o + 28
            PutTag b, o, "NAME": PutBE32 b, o + 4, ln
            For j = 1 To Len(nm): b(o + 7 + j) = Asc(Mid$(nm, j, 1)): Next j
            o = o + 8 + ln
            PutTag b, o, "BODY": PutBE32 b, o + 4, n
            For j = 0 To n - 1: b(o + 8 + j) = d(j): Next j
    End Select
    WriteBytes path, b
    SaveSampleFile = True
    Exit Function
bad:
    smpError = Err.Description
End Function

Private Sub PutTag(b() As Byte, ByVal o As Long, ByVal t As String)
    Dim j As Long
    For j = 0 To 3: b(o + j) = Asc(Mid$(t, j + 1, 1)): Next j
End Sub

Private Sub PutBE32(b() As Byte, ByVal o As Long, ByVal v As Long)
    b(o) = (v \ &H1000000) And 255: b(o + 1) = (v \ &H10000) And 255
    b(o + 2) = (v \ 256) And 255: b(o + 3) = v And 255
End Sub

Private Sub PutLE32(b() As Byte, ByVal o As Long, ByVal v As Long)
    b(o + 3) = (v \ &H1000000) And 255: b(o + 2) = (v \ &H10000) And 255
    b(o + 1) = (v \ 256) And 255: b(o) = v And 255
End Sub

Private Sub PutLE16(b() As Byte, ByVal o As Long, ByVal v As Long)
    b(o + 1) = (v \ 256) And 255: b(o) = v And 255
End Sub

' ---- editor operations (each one undoable)

Public Function SmpReverse(ByVal i As Long) As Boolean
    Dim d() As Byte, n As Long, j As Long, t As Byte
    n = smpLen(i)
    If n = 0 Then Exit Function
    d = smpData(i)
    For j = 0 To n \ 2 - 1
        t = d(j): d(j) = d(n - 1 - j): d(n - 1 - j) = t
    Next j
    EdSampleData i, "reverse", d, n
    SmpReverse = True
End Function

Public Function SmpNormalise(ByVal i As Long) As Boolean
    Dim d() As Byte, n As Long, j As Long, v As Long, peak As Long
    n = smpLen(i)
    If n = 0 Then Exit Function
    d = smpData(i)
    For j = 0 To n - 1
        v = d(j): If v > 127 Then v = v - 256
        If Abs(v) > peak Then peak = Abs(v)
    Next j
    If peak = 0 Or peak >= 127 Then Exit Function
    For j = 0 To n - 1
        v = d(j): If v > 127 Then v = v - 256
        v = (v * 127) \ peak
        d(j) = v And 255
    Next j
    EdSampleData i, "normalise", d, n
    SmpNormalise = True
End Function

' keep only the start and the loop (drops what follows the loop end)
Public Function SmpCropToLoop(ByVal i As Long) As Boolean
    Dim e As Long
    If smpLoopL(i) <= 2 Then Exit Function
    e = smpLoopS(i) + smpLoopL(i)
    If e >= smpLen(i) Then Exit Function
    EdSampleData i, "cut to loop", smpData(i), e
    SmpCropToLoop = True
End Function

' ---- synthesised samples for new songs and the demo (deterministic)
' kind: 0 square, 1 saw, 2 triangle, 3 noise; one looped cycle of n bytes
Public Sub SynthSample(ByVal i As Long, ByVal kind As Long, ByVal n As Long, ByVal nm As String)
    Dim d() As Byte, j As Long, v As Long, seed As Long
    ReDim d(0 To n - 1)
    seed = 12345
    For j = 0 To n - 1
        Select Case kind
            Case 0: If j < n \ 2 Then v = 80 Else v = -80
            Case 1: v = (j * 200) \ n - 100
            Case 2: If j < n \ 2 Then v = (j * 400) \ n - 100 Else v = 300 - (j * 400) \ n
            Case Else
                seed = (seed * 1103 + 12345) And &H7FFF&
                v = (seed And 255) - 128
        End Select
        d(j) = v And 255
    Next j
    EdSampleData i, "synth", d, n
    smpName(i) = PadName(nm, 22)
    smpVol(i) = 64
    If kind < 3 Then smpLoopS(i) = 0: smpLoopL(i) = n
    MirrorSample i
End Sub
