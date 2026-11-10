' dialogs.bas
Option Explicit

Private Sub Note(ByVal s As String)
    log.AddItem s
    log.ListIndex = log.ListCount - 1
End Sub

Private Sub openOne_Click()
    dlg.DialogTitle = "Open a text"
    dlg.Flags = cdlOFNFileMustExist
    dlg.ShowOpen
    If dlg.Cancelled Then Note "Open: cancelled": Exit Sub
    Note "Open " & dlg.FileName & " (file " & dlg.FileTitle & ")"
End Sub

Private Sub openMany_Click()
    Dim i As Long
    dlg.DialogTitle = "Open texts"
    dlg.Flags = cdlOFNAllowMultiselect
    dlg.ShowOpen
    If dlg.Cancelled Then Exit Sub
    For i = 0 To dlg.FileCount - 1
        Note "File " & (i + 1) & ": " & dlg.Files(i)
    Next
End Sub

Private Sub saveAs_Click()
    ' with CancelError, cancelling raises error 32755 (cdlCancel) instead
    dlg.CancelError = True
    dlg.DialogTitle = "Save the text"
    dlg.FileName = "RAM:untitled.txt"
    dlg.Flags = cdlOFNOverwritePrompt
    On Error GoTo cancelled
    dlg.ShowSave
    Note "Save as " & dlg.FileName
    dlg.CancelError = False
    Exit Sub
cancelled:
    dlg.CancelError = False
    If Err.Number = cdlCancel Then Note "Save: cancelled" Else Note "Error " & Err.Description
End Sub

Private Sub font_Click()
    dlg.FontName = "DejaVu Sans"
    dlg.FontSize = 14
    dlg.ShowFont
    If dlg.Cancelled Then Exit Sub
    Note "Font " & dlg.FontName & " " & dlg.FontSize & IIf(dlg.FontBold, " bold", "") & IIf(dlg.FontItalic, " italic", "")
End Sub

Private Sub colour_Click()
    dlg.Color = RGB(255, 128, 0)
    dlg.ShowColor
    If dlg.Cancelled Then Exit Sub
    Note "Colour &H" & Hex(dlg.Color)
End Sub

Private Sub screen_Click()
    dlg.ShowScreenMode
    If dlg.Cancelled Then Exit Sub
    Note "Screen mode &H" & Hex(dlg.ScreenModeID) & ": " & dlg.ScreenWidth & " x " & dlg.ScreenHeight & " x " & dlg.ScreenDepth
End Sub

Private Sub ask_Click()
    Select Case MsgBox("Save the changes first?", vbYesNoCancel + vbQuestion, "Requesters")
    Case vbYes: Note "MsgBox: Yes"
    Case vbNo: Note "MsgBox: No"
    Case vbCancel: Note "MsgBox: Cancel"
    End Select
End Sub

Private Sub askName_Click()
    Dim s As String
    s = InputBox("What is your name?", "Requesters", "Amiga")
    If s = "" Then Note "InputBox: cancelled" Else Note "Hello " & s
End Sub

Private Sub choose_Click()
    Dim n As Long
    ' buttons from the left: 1, 2, 3; Esc or the close gadget gives the last
    n = dlg.ShowMessage("The picture has changed.", "_Save|_Discard|_Cancel", "Requesters", vbExclamation)
    Note "Button" & Str(n)
    ' the same without a CommonDialog control
    n = App.Request("Really quit?", "_Quit|_Stay")
    If n = 1 Then Unload Me
End Sub
