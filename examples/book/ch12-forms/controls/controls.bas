' controls.bas - every event of the basic controls updates the status line
Option Explicit

Private Sub Form_Load()
    colour.AddItem "Yellow"             ' a fourth choice
    status.Caption = "Ready: " & colour.ListCount & " colours"
End Sub

Private Sub Report(ByVal what As String)
    status.Caption = what
    reset.Enabled = True
End Sub

Private Sub sound_Click()
    If sound.Value = vbChecked Then Report "Sound on" Else Report "Sound off"
End Sub

Private Sub size_Click()
    Report "Size " & size.Text & " (" & size.ListIndex & ")"
End Sub

Private Sub colour_Click()
    Report "Colour " & colour.Text
End Sub

Private Sub volume_Scroll()             ' while the knob is dragged
    meter.Value = volume.Value
End Sub

Private Sub volume_Change()             ' the knob was let go
    meter.Value = volume.Value
    Report "Volume" & Str(volume.Value)
End Sub

Private Sub pos_Change()
    Report "Position" & Str(pos.Value)
End Sub

Private Sub copies_Change()
    Report copies.Value & " copies"
End Sub

Private Sub title_Change()               ' every key typed
    Me.Caption = "Controls - " & title.Text
End Sub

Private Sub apply_Click()
    Report "Title """ & title.Text & """, " & copies.Value & " copies, volume" & Str(volume.Value)
End Sub

Private Sub reset_Click()
    sound.Value = vbChecked             ' fires sound_Click
    size.ListIndex = 1                  ' fires size_Click
    colour.ListIndex = 0                ' fires colour_Click
    volume.Value = 32                   ' fires volume_Change
    copies.Value = 1
    title.Text = "Untitled"             ' fires title_Change
    status.Caption = "Reset"
    reset.Enabled = False
End Sub
