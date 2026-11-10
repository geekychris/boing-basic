' sketch.bas
Option Explicit

Private recentCount As Integer

Private Sub Form_Load()
    view.Cls
    mnuRulers.Enabled = False           ' not written yet
End Sub

' --- Project ---------------------------------------------------------------------------

Private Sub mnuNew_Click()
    view.Cls
    view.Refresh
    status.Caption = "New picture"
End Sub

Private Sub mnuOpen_Click()
    Dim name As String
    name = InputBox("Picture to open", "Open", "RAM:picture.iff")
    If name = "" Then Exit Sub
    AddRecent name
    status.Caption = "Opened " & name
End Sub

' a menu item added at run time for every file opened (up to three)
Private Sub AddRecent(ByVal file As String)
    If recentCount = 3 Then Exit Sub
    recentCount = recentCount + 1
    mnuNoRecent.Visible = False
    Me.AddMenu "mnuRecent" & recentCount, file, "mnuRecent", CStr(recentCount)
End Sub

' the Click subs of the run-time items exist from the start, with the ids AddRecent uses
Private Sub mnuRecent1_Click(): OpenRecent 1: End Sub
Private Sub mnuRecent2_Click(): OpenRecent 2: End Sub
Private Sub mnuRecent3_Click(): OpenRecent 3: End Sub

Private Sub OpenRecent(ByVal i As Integer)
    status.Caption = "Opened " & Me.Controls("mnuRecent" & i).Caption & " again"
End Sub

Private Sub mnuAbout_Click()
    MsgBox "Sketch 1.0" & vbLf & "A Boing BASIC menu example", vbInformation, "About Sketch"
End Sub

Private Sub mnuQuit_Click()
    Unload Me
End Sub

' --- View: a checkable item and a group of radio items ----------------------------------

Private Sub mnuGrid_Click()
    ' Checked is already the new state
    If mnuGrid.Checked Then status.Caption = "Grid on" Else status.Caption = "Grid off"
End Sub

Private Sub mnuSmall_Click(): SetSize "small": End Sub
Private Sub mnuNormal_Click(): SetSize "normal": End Sub
Private Sub mnuLarge_Click(): SetSize "large": End Sub

Private Sub SetSize(ByVal s As String)
    status.Caption = "Size " & s
    mnuView.Caption = "View (" & s & ")"      ' a menu title can change too
End Sub

' --- the context menus ------------------------------------------------------------------

Private Sub mnuClear_Click()
    view.Cls
    view.Refresh
    status.Caption = "Cleared (" & Me.ContextControl & ")"
End Sub

Private Sub mnuFillRed_Click()
    view.Box 0, 0, view.Width, view.Height, RGB(220, 0, 0)
    view.Refresh
End Sub

Private Sub mnuHome_Click()
    Me.Move 40, 40                        ' Left, Top (Width and Height can follow)
End Sub

' a pop-up menu opened from code: double-click the canvas
Private Sub view_DblClick()
    Me.PopupMenu mnuCanvas
End Sub
