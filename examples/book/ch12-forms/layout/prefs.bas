' prefs.bas
Option Explicit

Private Sub Form_Load()
    userName.Text = GetSetting("LayoutDemo", "User", "Name", "")
    email.Text = GetSetting("LayoutDemo", "User", "Email", "")
    autosave.Value = Val(GetSetting("LayoutDemo", "Files", "AutoSave", "1"))
    minutes.Value = Val(GetSetting("LayoutDemo", "Files", "Minutes", "5"))
    minutes.Enabled = autosave.Value = vbChecked
End Sub

Private Sub autosave_Click()
    minutes.Enabled = autosave.Value = vbChecked
End Sub

Private Sub pages_Click()
    Me.Caption = "Preferences - " & pages.TabCaption(pages.Tab)
End Sub

Private Sub folders_Click()
    folderInfo.Caption = "Folder " & folders.Text
End Sub

Private Sub ok_Click()
    SaveSetting "LayoutDemo", "User", "Name", userName.Text
    SaveSetting "LayoutDemo", "User", "Email", email.Text
    SaveSetting "LayoutDemo", "Files", "AutoSave", CStr(autosave.Value)
    SaveSetting "LayoutDemo", "Files", "Minutes", CStr(minutes.Value)
    Unload Me
End Sub

Private Sub cancel_Click()
    Unload Me
End Sub
