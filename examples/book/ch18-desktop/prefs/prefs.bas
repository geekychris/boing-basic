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

Private Sub save_Click()
    SaveSetting APPNAME, "Alarm", "Message", message.Text
    SaveSetting APPNAME, "Alarm", "Minutes", CStr(minutes.Value)
    SaveSetting APPNAME, "Sound", "Flash", CStr(flash.Value)
    SaveSetting APPNAME, "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub

' Use: only ENV: (gone after a reboot); GetSetting reads ENV: first
Private Sub use_Click()
    UseSetting APPNAME, "Alarm", "Message", message.Text
    UseSetting APPNAME, "Alarm", "Minutes", CStr(minutes.Value)
    UseSetting APPNAME, "Sound", "Flash", CStr(flash.Value)
    UseSetting APPNAME, "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub

Private Sub cancel_Click()
    Unload Me
End Sub
