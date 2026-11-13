' OpenGL Textures: two spinning cubes. The left one wears a checkerboard made pixel by pixel
' in a BASIC array (GLTexImage); the right one a picture drawn with the Canvas methods in an
' off-screen canvas (GLTexImageCanvas). F switches the filtering between nearest (blocky) and
' linear (smooth); P between correct perspective and the fast approximation (OpenGL's
' GL_FASTEST hint: with nearest filtering, opaque textures and GL_REPLACE, software OpenGL
' draws textured triangles about ten times faster, and on cubes this size it looks the same).
' It starts fast. Esc ends. "--frames N" ends after N frames and prints a checksum.
Option Explicit

Private t As Long, maxFrames As Long, t0 As Double, busy As Double
Private checkTex As Long, paintTex As Long, cubeList As Long
Private linear As Boolean, fWas As Boolean, fast As Boolean, pWas As Boolean

' a 64 x 64 checkerboard: colours &HAARRGGBB, row by row from the top
Private Sub MakeChecker()
    Dim pix(64 * 64 - 1) As Long, x As Long, y As Long
    For y = 0 To 63
        For x = 0 To 63
            If ((x \ 8) + (y \ 8)) And 1 Then
                pix(y * 64 + x) = &HFFF0F0F0
            Else
                pix(y * 64 + x) = &HFFC02828
            End If
        Next
    Next
    checkTex = glGenTexture()
    glBindTexture GL_TEXTURE_2D, checkTex
    GLTexImage 64, 64, pix
End Sub

' a 128 x 128 picture drawn with the Canvas methods, then copied into a texture
Private Sub MakePainting()
    Dim cv As Object, i As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 128, 128
    cv.Gradient 0, 0, 128, 128, RGB(20, 40, 120), RGB(120, 20, 110), RGB(10, 90, 90), RGB(200, 120, 20)
    For i = 0 To 5
        cv.Circle 64, 64, 12 + i * 9, RGB(255, 220 - i * 30, 80 + i * 25)
    Next
    cv.Rect 2, 2, 124, 124, vbWhite
    cv.DrawTextScaled 16, 8, "BOING", vbWhite, 3
    cv.DrawTextScaled 22, 92, "BASIC", RGB(255, 230, 120), 3
    paintTex = glGenTexture()
    glBindTexture GL_TEXTURE_2D, paintTex
    GLTexImageCanvas cv, 0                   ' 0 = the canvas's picture itself
End Sub

Private Sub SetFilter(ByVal tex As Long)
    glBindTexture GL_TEXTURE_2D, tex
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, IIf(linear, GL_LINEAR, GL_NEAREST)
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, IIf(linear, GL_LINEAR, GL_NEAREST)
End Sub

Private Sub SetHint()
    glHint GL_PERSPECTIVE_CORRECTION_HINT, IIf(fast, GL_FASTEST, GL_NICEST)
End Sub

Private Sub Form_Load()
    GLAttach view
    glEnable GL_DEPTH_TEST
    glEnable GL_CULL_FACE
    glMatrixMode GL_PROJECTION
    gluPerspective 45, 320 / 256, 1, 50
    glMatrixMode GL_MODELVIEW
    glClearColor 0.1, 0.1, 0.1, 1

    MakeChecker
    MakePainting
    SetFilter checkTex
    SetFilter paintTex
    glEnable GL_TEXTURE_2D
    glTexEnvi GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE   ' the texture's colours as they are

    cubeList = glGenLists(1)                 ' a cube with texture coordinates on every face
    glNewList cubeList, GL_COMPILE
    glutSolidCube 2
    glEndList
    fast = True
    SetHint
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

Private Sub tick_Timer()
    Dim ts As Double
    ts = Timer
    If view.KeyDown(vbKeyF) And Not fWas Then
        linear = Not linear
        SetFilter checkTex
        SetFilter paintTex
    End If
    fWas = view.KeyDown(vbKeyF)
    If view.KeyDown(vbKeyP) And Not pWas Then
        fast = Not fast
        SetHint
    End If
    pWas = view.KeyDown(vbKeyP)

    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    glTranslatef -1.6, 0, -7
    glRotatef t * 1.5, 1, 0, 0
    glRotatef t * 2.2, 0, 1, 0
    glBindTexture GL_TEXTURE_2D, checkTex
    glCallList cubeList

    glLoadIdentity
    glTranslatef 1.6, 0, -7
    glRotatef t * 1.8, 0, 1, 0
    glRotatef 20, 1, 0, 0
    glBindTexture GL_TEXTURE_2D, paintTex
    glCallList cubeList
    GLPresent

    view.DrawText 4, 4, "OpenGL Textures", vbWhite
    view.DrawText 4, 243, "F filter " & IIf(linear, "linear", "nearest") & "  P perspective " & IIf(fast, "fast", "correct"), RGB(200, 200, 200)
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
