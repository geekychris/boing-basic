' Riffwright - preferences: a key=value text file in ENV: (and ENVARC:, so they survive a reboot)
Option Explicit

Public prefDir As String          ' last drawer used in the file requester
Public prefScale As Long          ' reserved

Private Function PrefPaths() As Variant
    PrefPaths = Array("ENV:Riffwright.prefs", "ENVARC:Riffwright.prefs")
End Function

Public Sub LoadPrefs(Optional ByVal path As String = "")
    Dim f As Integer, ln As String, k As Long, key As String, v As String
    On Error GoTo done
    If path = "" Then
        path = "ENV:Riffwright.prefs"
        If Len(Dir$(path)) = 0 Then path = "ENVARC:Riffwright.prefs"
    End If
    If Len(Dir$(path)) = 0 Then Exit Sub
    f = FreeFile
    Open path For Input As #f
    Do While Not EOF(f)
        Line Input #f, ln
        k = InStr(ln, "=")
        If k > 1 Then
            key = LCase$(Trim$(Left$(ln, k - 1)))
            v = Trim$(Mid$(ln, k + 1))
            Select Case key
                Case "octave": octave = CLng(Val(v)): If octave < 1 Or octave > 3 Then octave = 2
                Case "follow": followOn = (v = "1")
                Case "editstep": editStep = CLng(Val(v)): If editStep < 0 Or editStep > 8 Then editStep = 1
                Case "drawer": prefDir = v
            End Select
        End If
    Loop
    Close #f
    Exit Sub
done:
    If f <> 0 Then Close #f
End Sub

Public Sub SavePrefs(Optional ByVal path As String = "")
    Dim p As Variant, f As Integer
    On Error Resume Next
    For Each p In PrefPaths()
        If path <> "" Then p = path
        f = FreeFile
        Open p For Output As #f
        If Err.Number = 0 Then
            Print #f, "octave=" & octave
            Print #f, "follow=" & IIf(followOn, "1", "0")
            Print #f, "editstep=" & editStep
            Print #f, "drawer=" & prefDir
            Close #f
        End If
        Err.Clear
        If path <> "" Then Exit For
    Next
End Sub
