Sub Main()
    Print App.Title
    Print App.Major; App.Minor; App.Revision
    App.Title = "Renamed"
    Print App.Title
    Print App.ArgCount
    Print App.FromWorkbench
    Print TypeName(App.FromWorkbench)
    App.Title = "Settings Test"
    SaveSetting App.Title, "S", "K", "v"
    Print GetSetting("Settings Test", "S", "K", "none")
    DeleteSetting App.Title
End Sub
