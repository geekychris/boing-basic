' Tincture - the Workbench side, through this one module: ARexx port, AppWindow drops,
' AppIcon, the clipboard, help, icons and settings.
'
' This version uses only what the runtime has today: settings in a file next to the program
' (ENV:-style files once GetSetting/SaveSetting exist), help as a plain message, no ARexx port
' (--script files run the same commands), no OS clipboard (the internal one works). When the
' runtime's Workbench API (docs/ui.md sections 6 and 7) lands, the bodies below switch to it;
' the rest of the program doesn't change.
Option Explicit

Private settingKeys() As String, settingVals() As String, nSettings As Long, settingsRead As Boolean

Public Sub WbInit(ByVal portName As String)
End Sub

Public Sub WbCleanup()
End Sub

Public Function WbARexxName() As String
    WbARexxName = "(not available in this build)"
End Function

Public Sub WbSetRC(ByVal rc As Long)
End Sub

Public Function WbDropFile(ByVal i As Long) As String
End Function

Public Sub WbClipboardPut(cv As Object, ByVal img As Long)
End Sub

Public Function WbClipboardGet(cv As Object) As Long
End Function

Public Function WbHelp(ByVal guide As String, ByVal node As String) As Boolean
    MsgBox "Tincture help is in " & guide & " (open it with MultiView)." & vbLf & "Topic: " & node, vbInformation, "Tincture"
    WbHelp = True
End Function

Public Sub WbSaveIcon(ByVal path As String)
End Sub

' ---------------------------------------------------------------- settings: Tincture.prefs next to the program

Private Function PrefsFile() As String
    Dim p As String
    p = App.Path
    If p <> "" And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    PrefsFile = p & "Tincture.prefs"
End Function

Private Sub ReadSettings()
    Dim f As Integer, ln As String, q As Long
    settingsRead = True
    nSettings = 0
    ReDim settingKeys(0 To 63): ReDim settingVals(0 To 63)
    If Not FileExists(PrefsFile()) Then Exit Sub
    On Error GoTo done
    f = FreeFile
    Open PrefsFile() For Input As #f
    Do While Not EOF(f)
        Line Input #f, ln
        q = InStr(ln, "=")
        If q > 1 And nSettings < 64 Then
            settingKeys(nSettings) = Mid$(ln, 1, q - 1)
            settingVals(nSettings) = Mid$(ln, q + 1)
            nSettings = nSettings + 1
        End If
    Loop
    Close #f
done:
End Sub

Public Function WbGetSetting(ByVal key As String, ByVal def As String) As String
    Dim i As Long
    If Not settingsRead Then ReadSettings
    WbGetSetting = def
    For i = 0 To nSettings - 1
        If LCase$(settingKeys(i)) = LCase$(key) Then WbGetSetting = settingVals(i): Exit Function
    Next
End Function

Public Sub WbSaveSetting(ByVal key As String, ByVal v As String)
    Dim i As Long, f As Integer
    If Not settingsRead Then ReadSettings
    For i = 0 To nSettings - 1
        If LCase$(settingKeys(i)) = LCase$(key) Then Exit For
    Next
    If i = nSettings Then
        If nSettings >= 64 Then Exit Sub
        nSettings = nSettings + 1
        settingKeys(i) = key
    End If
    settingVals(i) = v
    On Error Resume Next
    f = FreeFile
    Open PrefsFile() For Output As #f
    For i = 0 To nSettings - 1
        Print #f, settingKeys(i) & "=" & settingVals(i)
    Next
    Close #f
End Sub
