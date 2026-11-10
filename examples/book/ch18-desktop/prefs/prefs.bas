' prefs.bas - Save keeps the settings in ENVARC: too, Use only in ENV:, Cancel changes nothing
' (the keyboard needs no code: the .afg's _ letters, default=1 and cancel=1 do it)
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
