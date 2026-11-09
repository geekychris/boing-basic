' Tincture - files: pictures (PNG, IFF ILBM, and whatever the datatypes read), the layered
' project format (.tinc) and the crash-safe autosave
'
' .tinc: "TINC" + Long header length + header text + one PNG per layer, back to back.
'   header lines: "Tincture 1", "size W H", "mode M", "palette N c0 c1 ...", "current N",
'   then per layer "layer <bytes> <visible> <opacity> <name>".
Option Explicit

Public Const FMT_AUTO As Long = 0
Public Const FMT_PNG As Long = 1
Public Const FMT_ILBM As Long = 2
Public Const FMT_TINC As Long = 3

Public lastError As String

Public Function FormatOf(ByVal path As String) As Long
    Dim e As String, p As Long
    p = InStrRev(path, ".")
    If p > 0 Then e = LCase$(Mid$(path, p + 1))
    Select Case e
        Case "png": FormatOf = FMT_PNG
        Case "tinc": FormatOf = FMT_TINC
        Case Else: FormatOf = FMT_ILBM
    End Select
End Function

Public Function FileExists(ByVal path As String) As Boolean
    On Error Resume Next
    FileExists = (FileLen(path) >= 0)
    If Err.Number Then FileExists = False
    Err.Clear
End Function

Public Function FilePart(ByVal path As String) As String
    Dim p As Long, q As Long
    p = InStrRev(path, "/"): q = InStrRev(path, ":")
    If q > p Then p = q
    FilePart = Mid$(path, p + 1)
End Function

' ---------------------------------------------------------------- open

Public Function OpenPicture(ByVal path As String) As Boolean
    Dim img As Long, p As Variant, i As Long
    On Error GoTo failed
    If Not FileExists(path) Then Err.Raise 53
    If FormatOf(path) = FMT_TINC Then
        If IsTinc(path) Then
            OpenPicture = LoadTinc(path)
            Exit Function
        End If
    End If
    img = cv.LoadImage(path)
    p = cv.LastPalette()
    DocFromImage img
    If IsArray(p) Then
        palCount = UBound(p) + 1
        For i = 0 To palCount - 1
            pal(i) = p(i)
        Next
        docMode = MODE_INDEXED
        fgColor = pal(IIf(palCount > 1, 1, 0))
        bgColor = pal(0)
    Else
        docMode = MODE_TRUE
    End If
    docPath = path
    docDirty = False
    OpenPicture = True
    Exit Function
failed:
    lastError = "Can't open " & FilePart(path) & ": " & Err.Description
End Function

' a picture file as an image (for paste / drop as a floating image); 0 if it can't be read
Public Function LoadAsImage(ByVal path As String) As Long
    On Error GoTo failed
    LoadAsImage = cv.LoadImage(path)
    Exit Function
failed:
    lastError = "Can't open " & FilePart(path) & ": " & Err.Description
End Function

' ---------------------------------------------------------------- save

Public Function SavePicture(ByVal path As String, Optional ByVal fmt As Long = FMT_AUTO) As Boolean
    Dim flat As Long
    On Error GoTo failed
    DropFloat
    If fmt = FMT_AUTO Then fmt = FormatOf(path)
    If fmt = FMT_TINC Then
        SaveTinc path
    Else
        flat = FlattenCopy()
        If fmt = FMT_PNG Then
            If docMode = MODE_INDEXED Then cv.SavePNG path, flat, pal, palCount Else cv.SavePNG path, flat
        Else
            If docMode = MODE_INDEXED Then cv.SaveILBM path, flat, pal, palCount Else cv.SaveILBM path, flat
        End If
        cv.FreeImage flat
    End If
    docPath = path
    docDirty = False
    SavePicture = True
    Exit Function
failed:
    lastError = "Can't save " & FilePart(path) & ": " & Err.Description
    If flat Then cv.FreeImage flat
End Function

' ---------------------------------------------------------------- the layered format

Private Function IsTinc(ByVal path As String) As Boolean
    Dim f As Integer, m As String
    On Error GoTo nope
    If Not FileExists(path) Then Exit Function      ' (Open For Binary would create it)
    f = FreeFile
    Open path For Binary Access Read As #f
    m = Space$(4)
    Get #f, , m
    Close #f
    IsTinc = (m = "TINC")
    Exit Function
nope:
    IsTinc = False
End Function

Public Sub SaveTinc(ByVal path As String)
    Dim hdr As String, i As Long, f As Integer, tmp As String, m As String, n As Long
    Dim blobs(1 To 16) As String
    tmp = path & ".layer"
    For i = 1 To nLayers
        cv.SavePNG tmp, layers(i).img
        blobs(i) = ReadAll(tmp)
    Next
    If FileExists(tmp) Then Kill tmp
    hdr = "Tincture 1" & vbLf & "size " & docW & " " & docH & vbLf & "mode " & docMode & vbLf
    hdr = hdr & "palette " & palCount
    For i = 0 To palCount - 1
        hdr = hdr & " " & pal(i)
    Next
    hdr = hdr & vbLf & "current " & curLayer & vbLf
    For i = 1 To nLayers
        hdr = hdr & "layer " & Len(blobs(i)) & " " & IIf(layers(i).visible, 1, 0) & " " & layers(i).opacity & " " & layers(i).name & vbLf
    Next
    ' write to a new file, then put it in place (a crash never leaves half a file)
    If FileExists(path & ".new") Then Kill path & ".new"
    f = FreeFile
    Open path & ".new" For Binary Access Write As #f
    m = "TINC"
    Put #f, , m
    n = Len(hdr)
    Put #f, , n
    Put #f, , hdr
    For i = 1 To nLayers
        Put #f, , blobs(i)
    Next
    Close #f
    If FileExists(path) Then Kill path
    Name path & ".new" As path
End Sub

Public Function LoadTinc(ByVal path As String) As Boolean
    Dim f As Integer, m As String, n As Long, hdr As String, lines() As String, w() As String
    Dim i As Long, k As Long, nl As Long, blob As String, tmp As String, img As Long
    Dim names(1 To 16) As String, vis(1 To 16) As Boolean, op(1 To 16) As Long, sizes(1 To 16) As Long
    Dim dw As Long, dh As Long, md As Long, cur As Long, pc As Long, pv(0 To 255) As Long
    On Error GoTo failed
    f = FreeFile
    Open path For Binary Access Read As #f
    m = Space$(4)
    Get #f, , m
    If m <> "TINC" Then Close #f: Err.Raise 481, "Tincture", "Not a Tincture picture"
    Get #f, , n
    hdr = Space$(n)
    Get #f, , hdr
    lines = Split(hdr, vbLf)
    If lines(0) <> "Tincture 1" Then Close #f: Err.Raise 481, "Tincture", "Unknown Tincture version"
    For i = 1 To UBound(lines)
        w = Split(lines(i), " ")
        If UBound(w) >= 0 Then
            Select Case w(0)
                Case "size": dw = CLng(w(1)): dh = CLng(w(2))
                Case "mode": md = CLng(w(1))
                Case "current": cur = CLng(w(1))
                Case "palette"
                    pc = CLng(w(1))
                    For k = 0 To pc - 1
                        pv(k) = CLng(w(2 + k))
                    Next
                Case "layer"
                    If nl < MAX_LAYERS Then
                        nl = nl + 1
                        sizes(nl) = CLng(w(1)): vis(nl) = (w(2) = "1"): op(nl) = CLng(w(3))
                        names(nl) = Mid$(lines(i), Len(w(0)) + Len(w(1)) + Len(w(2)) + Len(w(3)) + 5)
                    End If
            End Select
        End If
    Next
    If dw < 1 Or dh < 1 Or nl < 1 Then Close #f: Err.Raise 481, "Tincture", "Damaged Tincture picture"
    DocNew dw, dh
    tmp = path & ".layer"
    For i = 1 To nl
        blob = Space$(sizes(i))
        Get #f, , blob
        WriteAll tmp, blob
        img = cv.LoadImage(tmp)
        If i = 1 Then
            cv.FreeImage layers(1).img
        End If
        layers(i).img = img
        layers(i).name = names(i)
        layers(i).visible = vis(i)
        layers(i).opacity = op(i)
    Next
    Close #f
    Kill tmp
    nLayers = nl
    curLayer = cur: If curLayer < 1 Or curLayer > nl Then curLayer = nl
    docMode = md
    palCount = pc
    For k = 0 To pc - 1
        pal(k) = pv(k)
    Next
    docPath = path
    docDirty = False
    DirtyAll
    Recomposite
    LoadTinc = True
    Exit Function
failed:
    lastError = "Can't open " & FilePart(path) & ": " & Err.Description
    Close
End Function

Public Function ReadAll(ByVal path As String) As String
    Dim f As Integer, s As String
    f = FreeFile
    Open path For Binary Access Read As #f
    s = Space$(LOF(f))
    Get #f, , s
    Close #f
    ReadAll = s
End Function

Public Sub WriteAll(ByVal path As String, ByVal s As String)
    Dim f As Integer
    If FileExists(path) Then Kill path
    f = FreeFile
    Open path For Binary Access Write As #f
    Put #f, , s
    Close #f
End Sub

' ---------------------------------------------------------------- autosave

Public autosavePath As String
Private autosavedGen As Long

' write the document to the autosave file if it changed since the last time
Public Function Autosave() As Boolean
    If autosavePath = "" Or docW = 0 Then Exit Function
    If docGen = autosavedGen Or Not docDirty Then Exit Function
    If IsStroking() Then Exit Function
    On Error GoTo failed
    SaveTinc autosavePath
    WriteAll autosavePath & ".info.txt", docPath
    autosavedGen = docGen
    Autosave = True
    Exit Function
failed:
    lastError = "Autosave failed: " & Err.Description
End Function

Public Function HasAutosave() As Boolean
    HasAutosave = autosavePath <> "" And FileExists(autosavePath)
End Function

' bring back the autosaved picture (still marked as changed)
Public Function RecoverAutosave() As Boolean
    Dim orig As String
    If Not HasAutosave() Then Exit Function
    If Not LoadTinc(autosavePath) Then Exit Function
    If FileExists(autosavePath & ".info.txt") Then orig = ReadAll(autosavePath & ".info.txt")
    docPath = orig
    docDirty = True
    RecoverAutosave = True
End Function

' the program ends normally, or the user saved / threw the picture away
Public Sub ClearAutosave()
    On Error Resume Next
    If autosavePath = "" Then Exit Sub
    If FileExists(autosavePath) Then Kill autosavePath
    If FileExists(autosavePath & ".info.txt") Then Kill autosavePath & ".info.txt"
    autosavedGen = docGen
End Sub
