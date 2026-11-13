' OpenGL Shapes: lighting and materials. Five shapes in a row (sphere, torus, cone, cube,
' cylinder), each a display list made once, lit by a warm light from the upper left and a blue
' one from the right. Keys: S smooth / flat shading, L lighting on / off, W wireframe, Esc ends.
' "--frames N" ends after N frames and prints a checksum of the last picture.
Option Explicit

Private t As Long, maxFrames As Long, t0 As Double, busy As Double
Private shapeList As Long                    ' the first of 5 display lists
Private smooth As Boolean, lit As Boolean, wire As Boolean
Private keyWas(2) As Boolean                 ' S, L, W last frame: toggle on the press only

Private Sub Form_Load()
    Dim i As Long
    GLAttach view
    glEnable GL_DEPTH_TEST
    glEnable GL_CULL_FACE                    ' skip the faces turned away (half the work)
    glMatrixMode GL_PROJECTION
    gluPerspective 40, 320 / 256, 1, 50
    glMatrixMode GL_MODELVIEW
    glClearColor 0.08, 0.08, 0.12, 1

    ' two lights: positions are given with the camera's matrix (identity here), so they stay put
    glLoadIdentity
    glLight4f GL_LIGHT0, GL_POSITION, -5, 6, 4, 0            ' w = 0: a direction (like the sun)
    glLight4f GL_LIGHT0, GL_DIFFUSE, 1, 0.9, 0.7, 1
    glLight4f GL_LIGHT1, GL_POSITION, 6, -1, 2, 0
    glLight4f GL_LIGHT1, GL_DIFFUSE, 0.2, 0.35, 0.9, 1
    glLightModel4f GL_LIGHT_MODEL_AMBIENT, 0.15, 0.15, 0.15, 1
    glEnable GL_LIGHT0
    glEnable GL_LIGHT1

    ' each shape once, into a display list: drawing a list later costs no BASIC calls
    shapeList = glGenLists(5)
    For i = 0 To 4
        glNewList shapeList + i, GL_COMPILE
        Select Case i
        Case 0: glutSolidSphere 0.8, 16, 12
        Case 1: glutSolidTorus 0.25, 0.6, 10, 16
        Case 2: glRotatef -90, 1, 0, 0: glTranslatef 0, 0, -0.7: glutSolidCone 0.7, 1.4, 14, 1
        Case 3: glutSolidCube 1.2
        Case 4: glRotatef -90, 1, 0, 0: glTranslatef 0, 0, -0.7: glutSolidCylinder 0.55, 1.4, 14, 1
        End Select
        glEndList
    Next
    smooth = True: lit = True
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

' the material of shape i: its own colour, and a white highlight on the sphere
Private Sub Material(ByVal i As Long)
    Dim r As Double, g As Double, b As Double
    Select Case i
    Case 0: r = 0.9: g = 0.2: b = 0.2
    Case 1: r = 0.95: g = 0.75: b = 0.1
    Case 2: r = 0.2: g = 0.8: b = 0.3
    Case 3: r = 0.3: g = 0.5: b = 0.95
    Case Else: r = 0.8: g = 0.3: b = 0.9
    End Select
    glMaterial4f GL_FRONT, GL_AMBIENT_AND_DIFFUSE, r, g, b, 1
    If i = 0 Then
        glMaterial4f GL_FRONT, GL_SPECULAR, 1, 1, 1, 1
        glMaterialf GL_FRONT, GL_SHININESS, 30
    Else
        glMaterial4f GL_FRONT, GL_SPECULAR, 0, 0, 0, 1
    End If
    glColor3f r, g, b                        ' the colour used when lighting is off
End Sub

' True once each time key k goes down (slot = which toggle)
Private Function Pressed(ByVal slot As Long, ByVal k As Long) As Boolean
    Dim down As Boolean
    down = view.KeyDown(k)
    Pressed = down And Not keyWas(slot)
    keyWas(slot) = down
End Function

Private Sub tick_Timer()
    Dim i As Long, ts As Double
    ts = Timer
    If Pressed(0, vbKeyS) Then smooth = Not smooth
    If Pressed(1, vbKeyL) Then lit = Not lit
    If Pressed(2, vbKeyW) Then wire = Not wire
    glShadeModel IIf(smooth, GL_SMOOTH, GL_FLAT)
    If lit Then glEnable GL_LIGHTING Else glDisable GL_LIGHTING
    glPolygonMode GL_FRONT_AND_BACK, IIf(wire, GL_LINE, GL_FILL)

    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    For i = 0 To 4
        glLoadIdentity
        glTranslatef (i - 2) * 1.75, Sin(t * 0.05 + i) * 0.4, -10
        glRotatef t * 2 + i * 40, 0.3, 1, 0.2
        Material i
        glCallList shapeList + i
    Next
    GLPresent

    ' the HUD: plain Canvas drawing over the OpenGL picture
    view.DrawText 4, 4, "OpenGL Shapes", vbWhite
    view.DrawText 4, 243, "S " & IIf(smooth, "smooth", "flat") & "  L light " & IIf(lit, "on", "off") & _
                  "  W " & IIf(wire, "wire", "solid"), RGB(180, 180, 220)
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
