' jotter.bas - a note pad that works with Workbench and ARexx
Option Explicit

Private Sub Form_Load()
    App.HelpFile = App.Path & "/Jotter.guide"   ' the Help key opens it

    ' a tooltype of the program's icon: FONT=FIXED
    If UCase(App.ToolType("FONT", "")) = "FIXED" Then ed.FixedFont = True

    ' files given to the program: project icons, multi-selected icons, or the Shell
    If App.ArgCount > 0 Then LoadNote App.Arg(0)

    App.ARexxPort = "JOTTER"                ' other programs can now send commands
    status.Caption = App.Str(20, "ARexx port: ") & App.ARexxPortName
    If App.FromWorkbench Then status.Caption = status.Caption & " (started from Workbench)"
End Sub

Private Sub LoadNote(ByVal path As String)
    On Error GoTo failed
    ed.LoadFile path
    Me.Caption = App.Str(1, "Jotter") & " - " & path
    Exit Sub
failed:
    status.Caption = Err.Description
End Sub

' --- the clipboard ---------------------------------------------------------------------

Private Sub copyAll_Click()
    Clipboard.SetText ed.Text
    status.Caption = Len(ed.Text) & " characters copied"
End Sub

Private Sub pasteIn_Click()
    ed.InsertText Clipboard.GetText()
End Sub

' --- an icon for a saved note ----------------------------------------------------------

Private Sub saveIt_Click()
    Dim path As String
    path = "RAM:note.txt"
    ed.SaveFile path
    If Dir(path & ".info") = "" Then App.SaveIcon path   ' a project icon: opens Jotter
    status.Caption = "Saved " & path
End Sub

' --- iconify and the AppIcon -----------------------------------------------------------

Private Sub hideIt_Click()
    Me.WindowState = 1                      ' iconify, as the iconify gadget does
End Sub

Private Sub Form_Resize()
    ' also after iconifying and uniconifying
    If Me.WindowState = 0 Then status.Caption = "Window open"
End Sub

' an AppIcon: an icon of the running program on the Workbench screen
Private Sub mnuAppIcon_Click()
    If mnuAppIcon.Checked Then App.ShowAppIcon "Jotter" Else App.HideAppIcon
End Sub

Sub AppIcon_DblClick()                      ' the AppIcon was double-clicked
    Me.WindowState = 0
End Sub

Sub AppIcon_DragDrop(Count As Integer)      ' icons were dropped on the AppIcon
    LoadNote App.DropFile(0)
End Sub

' --- drag and drop ---------------------------------------------------------------------

Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    LoadNote App.DropFile(0)
    If Count > 1 Then status.Caption = (Count - 1) & " more files ignored"
End Sub

' --- ARexx: address JOTTER; 'TEXT' gives the text, 'APPEND words' adds a line -----------

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "TEXT": Result = ed.Text
    Case "APPEND": ed.Text = ed.Text & vbLf & Args
    Case "QUIT": Unload Me
    Case Else: App.ARexxRC = 10            ' an error for the caller
    End Select
End Sub

' --- menus -----------------------------------------------------------------------------

Private Sub mnuHelp_Click()
    App.ShowHelp App.Path & "/Jotter.guide", "main"
End Sub

Private Sub mnuQuit_Click()
    Unload Me
End Sub
