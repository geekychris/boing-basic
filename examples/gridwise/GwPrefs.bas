' Gridwise - preferences and the recent files list, in ENVARC:Gridwise.prefs (and ENV:),
' one "key=value" per line.
Option Explicit

Public Recent(0 To 7) As String
Public NRecent As Long
Public PrefAutosave As Boolean
Public PrefGridLines As Boolean
Private prefsName As String

Public Sub LoadPrefs(ByVal file As String)
    Dim fn As Integer, l As String, k As String, v As String, p As Long
    prefsName = file
    PrefAutosave = True: PrefGridLines = True
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
            Case "currency": If v <> "" And Len(v) <= 4 Then CurrencySymbol = v
            Case "autosave": PrefAutosave = (v = "1")
            Case "gridlines": PrefGridLines = (v = "1")
            Case "recent": If NRecent < 8 And v <> "" Then Recent(NRecent) = v: NRecent = NRecent + 1
            End Select
        End If
    Loop
    Close #fn
Done:
End Sub

Public Sub SavePrefs()
    Dim fn As Integer, s As String, i As Long, d As Variant
    If prefsName = "" Then Exit Sub
    s = "currency=" & CurrencySymbol & vbLf & "autosave=" & IIf(PrefAutosave, "1", "0") & vbLf & _
        "gridlines=" & IIf(PrefGridLines, "1", "0") & vbLf
    For i = 0 To NRecent - 1
        s = s & "recent=" & Recent(i) & vbLf
    Next i
    On Error Resume Next
    For Each d In Array("ENV:", "ENVARC:")
        fn = FreeFile
        Open d & prefsName For Output As #fn
        Print #fn, s;
        Close #fn
    Next d
End Sub

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
