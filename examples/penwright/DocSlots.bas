' Penwright - several documents at once, and the recent files list.
'
' The document being edited lives in Doc.bas; the others wait here as .pwd text with
' their file name, cursor and scroll position. Switching saves the current one into its
' slot and loads the other (its undo history starts afresh).
'
' Preferences (Prefs*) and the recent files are kept in ENVARC:Penwright.prefs (and
' ENV:), one "key=value" per line.
Option Explicit

Public Const MAXDOCS As Long = 8
Public NDocs As Long
Public CurDoc As Long
Private slotText(0 To 7) As String
Private slotPath(0 To 7) As String
Private slotMod(0 To 7) As Boolean
Private slotP(0 To 7) As Long, slotO(0 To 7) As Long, slotScroll(0 To 7) As Long

Public Recent(0 To 7) As String
Public NRecent As Long
Public PrefSize As Long
Public PrefLiveSpell As Boolean
Public PrefAutosave As Boolean
Public PrefsFile As String

Public Sub SlotsInit()
    NDocs = 1
    CurDoc = 0
    slotPath(0) = ""
End Sub

Public Function DocName(ByVal i As Long) As String
    Dim p As String
    If i = CurDoc Then p = PwPath Else p = slotPath(i)
    If p = "" Then
        DocName = "Untitled"
    Else
        DocName = Mid$(p, InStrRev(Replace(p, ":", "/"), "/") + 1)
    End If
    If i = CurDoc Then
        If DocModified Then DocName = DocName & " *"
    ElseIf slotMod(i) Then
        DocName = DocName & " *"
    End If
End Function

Public Function DocIsModified(ByVal i As Long) As Boolean
    If i = CurDoc Then DocIsModified = DocModified Else DocIsModified = slotMod(i)
End Function

Private Sub StoreCurrent()
    slotText(CurDoc) = DocToPwd()
    slotPath(CurDoc) = PwPath
    slotMod(CurDoc) = DocModified
    slotP(CurDoc) = curP: slotO(CurDoc) = curO: slotScroll(CurDoc) = scrollY
End Sub

Private Sub LoadSlot(ByVal i As Long)
    If slotText(i) = "" Then
        NewDoc
    Else
        DocFromPwd slotText(i)
    End If
    PwPath = slotPath(i)
    DocModified = slotMod(i)
    SyncLayout
    SetCursor slotP(i), slotO(i), False
    scrollY = slotScroll(i)
    CurDoc = i
End Sub

' a new empty document; False if all slots are taken
Public Function NewSlot() As Boolean
    If NDocs >= MAXDOCS Then Exit Function
    StoreCurrent
    slotText(NDocs) = "": slotPath(NDocs) = "": slotMod(NDocs) = False
    slotP(NDocs) = 0: slotO(NDocs) = 0: slotScroll(NDocs) = 0
    NDocs = NDocs + 1
    LoadSlot NDocs - 1
    NewSlot = True
End Function

Public Sub SwitchTo(ByVal i As Long)
    If i < 0 Or i >= NDocs Or i = CurDoc Then Exit Sub
    StoreCurrent
    LoadSlot i
End Sub

' close the current document (the caller has asked about saving); the last one is just emptied
Public Sub CloseCurrent()
    Dim i As Long, k As Long
    If NDocs = 1 Then
        NewDoc
        PwPath = ""
        SyncLayout
        SetCursor 0, 0, False
        scrollY = 0
        Exit Sub
    End If
    k = CurDoc
    For i = k To NDocs - 2
        slotText(i) = slotText(i + 1): slotPath(i) = slotPath(i + 1): slotMod(i) = slotMod(i + 1)
        slotP(i) = slotP(i + 1): slotO(i) = slotO(i + 1): slotScroll(i) = slotScroll(i + 1)
    Next i
    NDocs = NDocs - 1
    If k >= NDocs Then k = NDocs - 1
    LoadSlot k
End Sub

' the slot holding this file, -1 if none
Public Function SlotOf(ByVal path As String) As Long
    Dim i As Long
    SlotOf = -1
    For i = 0 To NDocs - 1
        If i = CurDoc Then
            If LCase$(PwPath) = LCase$(path) Then SlotOf = i: Exit Function
        ElseIf LCase$(slotPath(i)) = LCase$(path) Then
            SlotOf = i: Exit Function
        End If
    Next i
End Function

' ---- recent files and preferences ---------------------------------------------------------

Public Sub AddRecent(ByVal path As String)
    Dim i As Long, k As Long
    If path = "" Then Exit Sub
    k = -1
    For i = 0 To NRecent - 1
        If LCase$(Recent(i)) = LCase$(path) Then k = i: Exit For
    Next i
    If k < 0 Then
        If NRecent < 8 Then NRecent = NRecent + 1
        k = NRecent - 1
    End If
    For i = k To 1 Step -1
        Recent(i) = Recent(i - 1)
    Next i
    Recent(0) = path
    SavePrefs
End Sub

Public Sub LoadPrefs(ByVal file As String)
    Dim fn As Integer, l As String, k As String, v As String, p As Long
    PrefsFile = file
    PrefSize = 12: PrefLiveSpell = True: PrefAutosave = True
    NRecent = 0
    On Error GoTo Done
    If Dir("ENV:" & file) <> "" Then
        l = "ENV:" & file
    ElseIf Dir("ENVARC:" & file) <> "" Then
        l = "ENVARC:" & file
    Else
        Exit Sub
    End If
    fn = FreeFile
    Open l For Input As #fn
    Do While Not EOF(fn)
        Line Input #fn, l
        p = InStr(l, "=")
        If p > 0 Then
            k = LCase$(Left$(l, p - 1)): v = Mid$(l, p + 1)
            Select Case k
            Case "size": If Val(v) >= 6 And Val(v) <= 72 Then PrefSize = Val(v)
            Case "livespell": PrefLiveSpell = (v = "1")
            Case "autosave": PrefAutosave = (v = "1")
            Case "recent": If NRecent < 8 And v <> "" Then Recent(NRecent) = v: NRecent = NRecent + 1
            End Select
        End If
    Loop
    Close #fn
Done:
End Sub

Public Sub SavePrefs()
    Dim fn As Integer, s As String, i As Long, d As Variant
    If PrefsFile = "" Then Exit Sub
    s = "size=" & PrefSize & vbLf & "livespell=" & IIf(PrefLiveSpell, "1", "0") & vbLf & "autosave=" & IIf(PrefAutosave, "1", "0") & vbLf
    For i = 0 To NRecent - 1
        s = s & "recent=" & Recent(i) & vbLf
    Next i
    On Error Resume Next
    For Each d In Array("ENV:", "ENVARC:")
        fn = FreeFile
        Open d & PrefsFile For Output As #fn
        Print #fn, s;
        Close #fn
    Next d
End Sub
