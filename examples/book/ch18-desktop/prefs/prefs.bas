' prefs.bas - Save keeps the settings in ENVARC: too, Use only in ENV:, Cancel changes nothing
Option Explicit

Const APPNAME = "AlarmPrefs"

Private Sub Form_Load()
    message.Text = GetSetting(APPNAME, "Alarm", "Message", "Time for a break")
    minutes.Value = Val(GetSetting(APPNAME, "Alarm", "Minutes", "30"))
    flash.Value = Val(GetSetting(APPNAME, "Sound", "Flash", "1"))
    sound.ListIndex = Val(GetSetting(APPNAME, "Sound", "Sound", "1"))
End Sub

' Use: only ENV: (gone after a reboot); GetSetting reads ENV: first
Private Sub UseSetting(ByVal section As String, ByVal key As String, ByVal value As String)
    Dim f As Integer
    On Error Resume Next                 ' the drawers may exist already
    MkDir "ENV:" & APPNAME
    MkDir "ENV:" & APPNAME & "/" & section
    On Error GoTo 0
    f = FreeFile
    Open "ENV:" & APPNAME & "/" & section & "/" & key For Output As #f
    Print #f, value
    Close #f
End Sub

Private Sub save_Click()
    SaveSetting APPNAME, "Alarm", "Message", message.Text
    SaveSetting APPNAME, "Alarm", "Minutes", CStr(minutes.Value)
    SaveSetting APPNAME, "Sound", "Flash", CStr(flash.Value)
    SaveSetting APPNAME, "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub

Private Sub use_Click()
    UseSetting "Alarm", "Message", message.Text
    UseSetting "Alarm", "Minutes", CStr(minutes.Value)
    UseSetting "Sound", "Flash", CStr(flash.Value)
    UseSetting "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub

Private Sub cancel_Click()
    Unload Me
End Sub

' the keyboard: Esc is Cancel; the underlined letters work the gadgets
Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyEscape Then cancel_Click
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Select Case UCase(Chr(KeyAscii))
    Case "S": save_Click
    Case "U": use_Click
    Case "C": cancel_Click
    Case "M": message.SetFocus
    Case "E": minutes.SetFocus
    Case "F": flash.Value = 1 - flash.Value
    Case "O": sound.ListIndex = (sound.ListIndex + 1) Mod sound.ListCount
    End Select
End Sub
