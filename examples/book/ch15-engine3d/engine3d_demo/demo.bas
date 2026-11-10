' Engine3D demo: the form. Esc or closing the window ends it (or --frames N).
Option Explicit

Private t As Long, maxFrames As Long

Private Sub Form_Load()
    SceneInit view
    ' "--frames N": end after N frames (demos, screenshots)
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
End Sub

Private Sub tick_Timer()
    SceneFrame view, t
    view.Refresh
    t = t + 1
    If view.KeyDown(vbKeyEscape) Or (maxFrames > 0 And t >= maxFrames) Then Unload Me
End Sub
