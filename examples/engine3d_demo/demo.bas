' Engine3D demo: the form. Esc or closing the window ends it.
Option Explicit

Private t As Long

Private Sub Form_Load()
    SceneInit view
End Sub

Private Sub tick_Timer()
    SceneFrame view, t
    view.Refresh
    t = t + 1
    If view.KeyDown(vbKeyEscape) Then Unload Me
End Sub
