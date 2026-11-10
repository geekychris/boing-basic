' FileSizes: an AppIcon on the Workbench that tells the size of the files dropped on it,
' and an item in Workbench's Tools menu that does the same for the selected icons
Option Explicit

Private quitting As Boolean

Sub Main()
    App.ShowAppIcon "FileSizes"           ' the program's own icon, or the default tool icon
    App.AddAppMenuItem "File sizes..."
    App.ARexxPort = "FILESIZES"           ' so a script can say: ADDRESS FILESIZES; QUIT
    Do Until quitting
        DoEvents                          ' handles the icon, the menu item and ARexx
        Sleep 50
    Loop
    App.HideAppIcon
End Sub

Private Sub ShowSizes(ByVal count As Integer)
    Dim i As Integer, report As String
    For i = 0 To count - 1
        report = report & App.DropFile(i) & ": " & FileLen(App.DropFile(i)) & " bytes" & vbLf
    Next
    If count > 0 Then App.Request report, "_OK", "FileSizes", vbInformation
End Sub

' files dropped on the AppIcon
Sub AppIcon_DragDrop(Count As Integer)
    ShowSizes Count
End Sub

' the AppIcon double-clicked
Sub AppIcon_DblClick()
    If App.Request("Remove FileSizes from the Workbench?", "_Quit|_Cancel", "FileSizes", vbQuestion) = 1 Then quitting = True
End Sub

' Tools > File sizes... with icons selected
Sub AppMenu_Click(Index As Integer, Count As Integer)
    ShowSizes Count
End Sub

Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    If UCase(Cmd) = "QUIT" Then quitting = True Else App.ARexxRC = 10
End Sub
