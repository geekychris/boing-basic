' Tincture - the New Picture dialog (also used for Canvas Size and Scale)
Option Explicit

' dlgPurpose (Actions.bas) says what for: 0 new picture, 1 canvas size, 2 scale

Private Sub Form_Load()
    preset_Click
End Sub

' (dlgFresh: set by OpenDialog when the dialog is opened for a new purpose)
Private Sub Form_Activate()
    If Not dlgFresh Then Exit Sub
    dlgFresh = False
    Select Case dlgPurpose
        Case 0
            Me.Caption = "New Picture"
            ok.Caption = "_Create"
            colours.Enabled = True
            fill.Enabled = True
        Case 1
            Me.Caption = "Canvas Size"
            ok.Caption = "_Resize"
            w.Value = docW: h.Value = docH
            preset.ListIndex = 5
            colours.Enabled = False
            fill.Enabled = False
        Case 2
            Me.Caption = "Scale Picture"
            ok.Caption = "_Scale"
            w.Value = docW: h.Value = docH
            preset.ListIndex = 5
            colours.Enabled = False
            fill.Enabled = False
    End Select
End Sub

Private Sub preset_Click()
    Select Case preset.ListIndex
        Case 0: w.Value = 320: h.Value = 256
        Case 1: w.Value = 640: h.Value = 512
        Case 2: w.Value = 800: h.Value = 600
        Case 3: w.Value = 1024: h.Value = 768
        Case 4: w.Value = 1280: h.Value = 1024
    End Select
End Sub

Private Sub ok_Click()
    Dim fc As Long
    Me.Hide
    Select Case dlgPurpose
        Case 0
            Select Case fill.ListIndex
                Case 1: fc = vbWhite
                Case 2: fc = vbBlack
                Case 3: fc = fgColor
                Case Else: fc = bgColor
            End Select
            ActNewPicture w.Value, h.Value, fc, colours.ListIndex
        Case 1: ActResize w.Value, h.Value, False
        Case 2: ActResize w.Value, h.Value, True
    End Select
End Sub

Private Sub cancel_Click()
    Me.Hide
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    ' the close gadget only hides the dialog
    If UnloadMode = 0 Then Cancel = True: Me.Hide
End Sub
