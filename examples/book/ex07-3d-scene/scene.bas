' scene.bas - the form of exercise 7: it shows the world (World.bas) and moves the camera.
' Up/Down walk, Left/Right turn, Esc quits. --frames N ends after N frames.
Option Explicit

Private t As Long, maxFrames As Long

Private Sub Form_Load()
    WorldInit view
    If InStr(Command(), "--frames") > 0 Then maxFrames = Val(Mid(Command(), InStr(Command(), "--frames") + 8))
End Sub

Private Sub tick_Timer()
    ' keys held down: read them every frame
    If view.KeyDown(vbKeyLeft) Then WorldMove -600, 0
    If view.KeyDown(vbKeyRight) Then WorldMove 600, 0
    If view.KeyDown(vbKeyUp) Then WorldMove 0, 8
    If view.KeyDown(vbKeyDown) Then WorldMove 0, -8
    If view.KeyDown(vbKeyEscape) Then Unload Me: Exit Sub

    WorldFrame t
    view.Refresh
    t = t + 1
    If maxFrames > 0 And t >= maxFrames Then Unload Me
End Sub
