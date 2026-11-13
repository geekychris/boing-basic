' OpenGL Starfield: stars rush towards the camera. Every frame the program moves them in
' BASIC arrays and hands the arrays to OpenGL (glVertexPointer, glColorPointer), which draws
' them as points with glDrawArrays. Hold Space for warp speed: each star leaves a streak
' (GL_LINES). B turns additive blending on and off (the streaks glow, but blending is OpenGL's
' slowest path in software). Esc ends; "--frames N" ends after N frames (the second half at
' warp speed) and prints a checksum; "--warp" stays at warp speed.
Option Explicit

Const NSTARS = 300

Private t As Long, maxFrames As Long, t0 As Double, busy As Double
Private sx(NSTARS - 1) As Single, sy(NSTARS - 1) As Single, sz(NSTARS - 1) As Single
Private pts(NSTARS * 3 - 1) As Single, cols(NSTARS * 3 - 1) As Single
Private lines(NSTARS * 6 - 1) As Single, lcols(NSTARS * 6 - 1) As Single
Private seed As Long, speed As Double, blend As Boolean, bWas As Boolean, autoWarp As Boolean

' a repeatable random number 0..1 (the same stars every run)
Private Function Rand() As Double
    seed = (seed * 1103 + 12345) And &H7FFFF
    Rand = seed / &H80000
End Function

Private Sub NewStar(ByVal i As Long, ByVal z As Double)
    sx(i) = (Rand() - 0.5) * 40
    sy(i) = (Rand() - 0.5) * 32
    sz(i) = z
End Sub

Private Sub Form_Load()
    Dim i As Long
    GLAttach view
    glMatrixMode GL_PROJECTION
    gluPerspective 60, 320 / 256, 0.5, 100
    glMatrixMode GL_MODELVIEW
    glClearColor 0, 0, 0.04, 1
    glPointSize 2
    seed = 7
    For i = 0 To NSTARS - 1
        NewStar i, -1 - Rand() * 59
    Next
    speed = 0.25
    autoWarp = InStr(Command$(), "--warp") > 0
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

Private Sub tick_Timer()
    Dim ts As Double, i As Long, b As Double, warp As Boolean, tail As Double
    ts = Timer
    If view.KeyDown(vbKeyB) And Not bWas Then blend = Not blend
    bWas = view.KeyDown(vbKeyB)
    ' Space (or --warp, or the second half of a --frames run) is warp speed
    warp = view.KeyDown(vbKeySpace) Or autoWarp Or (maxFrames > 0 And t >= maxFrames \ 2)
    If warp Then speed = speed + (1.2 - speed) * 0.1 Else speed = speed + (0.25 - speed) * 0.1
    tail = speed * 4

    For i = 0 To NSTARS - 1
        sz(i) = sz(i) + speed
        If sz(i) > -0.5 Then NewStar i, -60      ' past the camera: a new one far away
        b = 1 + sz(i) / 60                       ' nearer is brighter
        pts(i * 3) = sx(i): pts(i * 3 + 1) = sy(i): pts(i * 3 + 2) = sz(i)
        cols(i * 3) = b: cols(i * 3 + 1) = b: cols(i * 3 + 2) = 0.6 + b * 0.4
        If warp Then
            lines(i * 6) = sx(i): lines(i * 6 + 1) = sy(i): lines(i * 6 + 2) = sz(i)
            lines(i * 6 + 3) = sx(i): lines(i * 6 + 4) = sy(i): lines(i * 6 + 5) = sz(i) - tail
            lcols(i * 6) = b * 0.6: lcols(i * 6 + 1) = b * 0.7: lcols(i * 6 + 2) = b
            lcols(i * 6 + 3) = 0: lcols(i * 6 + 4) = 0: lcols(i * 6 + 5) = b * 0.3
        End If
    Next

    glClear GL_COLOR_BUFFER_BIT
    glLoadIdentity
    glRotatef t * 0.2, 0, 0, 1                   ' a slow roll
    glEnableClientState GL_VERTEX_ARRAY
    glEnableClientState GL_COLOR_ARRAY
    If warp Then
        If blend Then
            glEnable GL_BLEND
            glBlendFunc GL_ONE, GL_ONE           ' add: overlapping streaks get brighter
        End If
        glVertexPointer 3, lines
        glColorPointer 3, lcols
        glDrawArrays GL_LINES, 0, NSTARS * 2
        glDisable GL_BLEND
    End If
    glVertexPointer 3, pts
    glColorPointer 3, cols
    glDrawArrays GL_POINTS, 0, NSTARS
    glDisableClientState GL_VERTEX_ARRAY
    glDisableClientState GL_COLOR_ARRAY
    GLPresent

    view.DrawText 4, 4, "OpenGL Starfield", vbWhite
    view.DrawText 4, 243, "Space warp  B blend " & IIf(blend, "on", "off"), RGB(140, 140, 200)
    view.Refresh
    t = t + 1
    busy = busy + Timer - ts
    If maxFrames > 0 And t >= maxFrames Then
        Print "frames"; t; "hash "; Hex$(view.Hash)
        Print "fps "; Format$(t / (Timer - t0 + 0.001), "0.0"); ", "; Format$(busy * 1000 / t, "0.0"); " ms a frame drawing"
        Unload Me
    ElseIf view.KeyDown(vbKeyEscape) Then
        Unload Me
    End If
End Sub
