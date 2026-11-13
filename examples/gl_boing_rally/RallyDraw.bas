' Boing Rally - drawing with OpenGL (the OpenGL extension: Extension=opengl, docs/opengl.md).
'
' Speed on the AmigaOS 4 guest (software Mesa on an emulated FPU) decides most of this:
' - the sky is a Canvas gradient drawn before GL, and GL clears only the depth buffer;
' - the road is flat shaded, unlit, with no GL fog: OSMesa's fast flat triangle needs GL_LESS,
'   16-bit depth and no fog, texture or blending. Each row's colours are faded towards the
'   horizon colour here instead (one fog factor a row), which looks the same at this size;
' - only the faces that can be seen are sent: tile tops, a front face where the row before is
'   a gap, a side face where the next lane is empty and faces the camera;
' - the ball and the gems are lit (one directional light), from display lists made once.
Option Explicit

Public Const VW As Long = 320
Public Const VH As Long = 256

Private ballList As Long, gemList As Long
Private camX As Double, camZ As Double
Private fogR As Double, fogG As Double, fogB As Double
Private horizonY As Long
Private pr(2) As Double

Private Const FOG_NEAR As Double = 22
Private Const FOG_FAR As Double = 74
Public Const SKY_TOP As Long = &H6E2A1C       ' RGB(28, 42, 110)
Public Const SKY_HORIZON As Long = &HA0C8FA   ' RGB(250, 200, 160)
Public Const SKY_LOW As Long = &H9A70B4       ' RGB(180, 112, 154)

Public Sub DrawInit(cv As Object)
    GLAttach cv
    glViewport 0, 0, VW, VH
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    gluPerspective 58, VW / VH, 0.6, 90
    glMatrixMode GL_MODELVIEW
    glLoadIdentity

    glEnable GL_DEPTH_TEST
    glDepthFunc GL_LESS                      ' the fast path (GL_LEQUAL is many times slower)
    glEnable GL_CULL_FACE
    glShadeModel GL_FLAT

    ' one directional light from the upper left behind the camera, a cool ambient
    glLight4f GL_LIGHT0, GL_POSITION, -0.45, 1, 0.55, 0
    glLight4f GL_LIGHT0, GL_DIFFUSE, 0.85, 0.85, 0.8, 1
    glLightModel4f GL_LIGHT_MODEL_AMBIENT, 0.38, 0.38, 0.45, 1
    glEnable GL_LIGHT0
    glEnable GL_NORMALIZE
    glColorMaterial GL_FRONT, GL_AMBIENT_AND_DIFFUSE
    glEnable GL_COLOR_MATERIAL

    fogR = SKY_HORIZON And &HFF
    fogG = (SKY_HORIZON \ &H100) And &HFF
    fogB = (SKY_HORIZON \ &H10000) And &HFF

    ' the ball: red and white checks, smooth shaded
    ballList = glGenLists(2)
    glNewList ballList, GL_COMPILE
    glutSolidCheckerSphere BALLR, 14, 10, RGB(225, 30, 35), RGB(245, 245, 245)
    glEndList

    ' a gem: an octahedron, flat shaded
    gemList = ballList + 1
    glNewList gemList, GL_COMPILE
    GemShape
    glEndList
End Sub

Private Sub Tri(ByVal nx As Double, ByVal ny As Double, ByVal nz As Double, _
                ByVal x0 As Double, ByVal y0 As Double, ByVal z0 As Double, _
                ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
                ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double)
    glNormal3f nx, ny, nz
    glVertex3f x0, y0, z0
    glVertex3f x1, y1, z1
    glVertex3f x2, y2, z2
End Sub

Private Sub GemShape()
    Const W As Double = 0.42, H As Double = 0.62
    glBegin GL_TRIANGLES
    Tri 1, 1, 1, 0, H, 0, 0, 0, W, W, 0, 0
    Tri 1, 1, -1, 0, H, 0, W, 0, 0, 0, 0, -W
    Tri -1, 1, -1, 0, H, 0, 0, 0, -W, -W, 0, 0
    Tri -1, 1, 1, 0, H, 0, -W, 0, 0, 0, 0, W
    Tri 1, -1, 1, 0, -H, 0, W, 0, 0, 0, 0, W
    Tri 1, -1, -1, 0, -H, 0, 0, 0, -W, W, 0, 0
    Tri -1, -1, -1, 0, -H, 0, -W, 0, 0, 0, 0, -W
    Tri -1, -1, 1, 0, -H, 0, 0, 0, W, -W, 0, 0
    glEnd
End Sub

' a colour (VB &HBBGGRR) times k, faded towards the horizon by f (0 = none, 1 = all)
Private Sub Col(ByVal c As Long, ByVal k As Double, ByVal f As Double)
    Dim r As Double, g As Double, b As Double
    r = (c And &HFF) * k: g = ((c \ &H100) And &HFF) * k: b = ((c \ &H10000) And &HFF) * k
    glColor3ub r + (fogR - r) * f, g + (fogG - g) * f, b + (fogB - b) * f
End Sub

Private Function FogAt(ByVal z As Double) As Double
    Dim d As Double
    d = camZ - z
    If d <= FOG_NEAR Then FogAt = 0: Exit Function
    If d >= FOG_FAR Then FogAt = 1: Exit Function
    FogAt = (d - FOG_NEAR) / (FOG_FAR - FOG_NEAR)
End Function

Private Function TileColour(ByVal t As Long, ByVal r As Long, ByVal lane As Long) As Long
    Select Case t
        Case T_BOOST
            If ((frameNo \ 3) + r) And 1 Then TileColour = RGB(40, 230, 170) Else TileColour = RGB(20, 170, 120)
        Case T_RAMP
            TileColour = RGB(250, 150, 40)
        Case Else
            If ((r + lane) And 1) = 0 Then TileColour = RGB(120, 128, 170) Else TileColour = RGB(98, 104, 146)
    End Select
End Function

' the road from row r0 to r1 (near to far: the depth test then skips hidden pixels early)
Private Sub DrawRoad(ByVal r0 As Long, ByVal r1 As Long)
    Dim r As Long, l As Long, t As Long, c As Long, f As Double
    Dim x0 As Double, x1 As Double, zn As Double, zf As Double
    Const M As Double = 0.07, YB As Double = -0.7, RH As Double = 0.7
    glBegin GL_QUADS
    For r = r0 To r1
        zn = -r * ROWLEN - M
        zf = -(r + 1) * ROWLEN + M
        f = FogAt((zn + zf) / 2)
        For l = 0 To LANES - 1
            t = TileAt(r, l)
            If t <> T_GAP Then
                c = TileColour(t, r, l)
                x0 = LaneX(l) - LANEW / 2 + M
                x1 = LaneX(l) + LANEW / 2 - M
                If t = T_RAMP Then
                    ' a wedge rising to RH at the far edge: its slope and sides
                    Col c, 1, f
                    glVertex3f x0, 0, zn: glVertex3f x1, 0, zn: glVertex3f x1, RH, zf: glVertex3f x0, RH, zf
                    Col c, 0.62, f
                    If camX < x0 Then
                        glVertex3f x0, YB, zf: glVertex3f x0, YB, zn: glVertex3f x0, 0, zn: glVertex3f x0, RH, zf
                    End If
                    If camX > x1 Then
                        glVertex3f x1, YB, zn: glVertex3f x1, YB, zf: glVertex3f x1, RH, zf: glVertex3f x1, 0, zn
                    End If
                Else
                    Col c, 1, f
                    glVertex3f x0, 0, zn: glVertex3f x1, 0, zn: glVertex3f x1, 0, zf: glVertex3f x0, 0, zf
                End If
                If TileAt(r - 1, l) = T_GAP Then          ' the front face, seen from the camera
                    Col c, 0.55, f
                    glVertex3f x0, YB, zn: glVertex3f x1, YB, zn: glVertex3f x1, 0, zn: glVertex3f x0, 0, zn
                End If
                If t <> T_RAMP Then
                    If camX < x0 And TileAt(r, l - 1) = T_GAP Then
                        Col c, 0.72, f
                        glVertex3f x0, YB, zf: glVertex3f x0, YB, zn: glVertex3f x0, 0, zn: glVertex3f x0, 0, zf
                    End If
                    If camX > x1 And TileAt(r, l + 1) = T_GAP Then
                        Col c, 0.72, f
                        glVertex3f x1, YB, zn: glVertex3f x1, YB, zf: glVertex3f x1, 0, zf: glVertex3f x1, 0, zn
                    End If
                End If
            End If
        Next l
    Next r
    glEnd
End Sub

' the red blocks: a box each, top, front and the side facing the camera
Private Sub DrawBlocks(ByVal r0 As Long, ByVal r1 As Long)
    Dim r As Long, l As Long, f As Double, x0 As Double, x1 As Double, zn As Double, zf As Double
    Const S As Double = 0.68, H As Double = 1.35
    Const C As Long = &H2828DC                     ' RGB(220, 40, 40)
    glBegin GL_QUADS
    For r = r0 To r1
        For l = 0 To LANES - 1
            If ThingAt(r, l) = O_BLOCK And TileAt(r, l) <> T_GAP Then
                zn = -(r * ROWLEN + ROWLEN / 2) + S
                zf = zn - 2 * S
                x0 = LaneX(l) - S: x1 = LaneX(l) + S
                f = FogAt(zn)
                Col C, 1, f
                glVertex3f x0, H, zn: glVertex3f x1, H, zn: glVertex3f x1, H, zf: glVertex3f x0, H, zf
                Col C, 0.62, f
                glVertex3f x0, 0, zn: glVertex3f x1, 0, zn: glVertex3f x1, H, zn: glVertex3f x0, H, zn
                Col C, 0.8, f
                If camX < x0 Then
                    glVertex3f x0, 0, zf: glVertex3f x0, 0, zn: glVertex3f x0, H, zn: glVertex3f x0, H, zf
                ElseIf camX > x1 Then
                    glVertex3f x1, 0, zn: glVertex3f x1, 0, zf: glVertex3f x1, H, zf: glVertex3f x1, H, zn
                End If
            End If
        Next l
    Next r
    glEnd
End Sub

Private Sub DrawGems(ByVal r0 As Long, ByVal r1 As Long)
    Dim r As Long, l As Long, z As Double, bob As Double
    bob = Sin(frameNo * 0.15) * 0.15
    For r = r0 To r1
        For l = 0 To LANES - 1
            If ThingAt(r, l) = O_GEM And TileAt(r, l) <> T_GAP Then
                z = -(r * ROWLEN + ROWLEN / 2)
                If camZ - z < FOG_FAR Then
                    glPushMatrix
                    glTranslatef LaneX(l), 1 + bob, z
                    glRotatef (frameNo * 7 + r * 40) Mod 360, 0, 1, 0
                    If ((r + l) And 1) = 0 Then glColor3ub 255, 220, 40 Else glColor3ub 80, 230, 255
                    glCallList gemList
                    glPopMatrix
                End If
            End If
        Next l
    Next r
End Sub

' the ball's shadow: a dark disc on the tile under it, smaller the higher the ball is
Private Sub DrawShadow()
    Dim l As Long, r As Long, t As Long, rad As Double, i As Long, a As Double, y As Double, c As Long
    l = LaneOf(bx)
    r = BallRow()
    If l < 0 Or falling Then Exit Sub
    t = TileAt(r, l)
    If t = T_GAP Then Exit Sub
    y = 0.03
    If t = T_RAMP Then y = 0.7 * (-bz - r * ROWLEN) / ROWLEN + 0.06
    rad = BALLR * (1 - (by - BALLR) / 7)
    If rad < 0.25 Then rad = 0.25
    c = TileColour(t, r, l)
    Col c, 0.42, 0
    glBegin GL_TRIANGLE_FAN
    glVertex3f bx, y, bz
    For i = 0 To 12
        a = i * 6.2831853 / 12
        glVertex3f bx + rad * Cos(a), y, bz - rad * Sin(a)
    Next i
    glEnd
End Sub

Private Sub DrawBall()
    Dim y As Double, sq As Double
    If ghostT > 0 And ((frameNo \ 3) And 1) = 1 Then Exit Sub   ' flashing after a respawn
    y = by
    glPushMatrix
    If crashT > 0 Then
        If crashKind = "fall" Then
            y = eventY - (36 - crashT) * 0.35
        Else
            y = eventY
        End If
    End If
    glTranslatef bx, y, bz
    If crashT > 0 And crashKind = "crash" Then
        sq = 1 - (36 - crashT) / 60                                  ' squashed against the block
        glScalef 1 + (1 - sq) * 0.8, sq, 1 + (1 - sq) * 0.8
    End If
    glRotatef -spin, 1, 0, 0
    glRotatef 90, 0, 1, 0
    glCallList ballList
    glPopMatrix
End Sub

' one frame: sky, road, blocks, gems, shadow, ball, then the +100 labels (the form draws the HUD)
Public Sub DrawScene(cv As Object)
    Dim r0 As Long, r1 As Long, i As Long
    camX = bx * 0.55
    camZ = bz + 8
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    gluLookAt camX, 4.4, camZ, bx * 0.8, 1.1, bz - 8, 0, 1, 0
    ' where the horizon is: the sky's two gradients meet there, in the road's fade colour
    If GLProject(camX, 0, camZ - 5000, pr) Then horizonY = pr(1) Else horizonY = VH / 2
    If horizonY < 1 Then horizonY = 1
    If horizonY > VH - 1 Then horizonY = VH - 1
    cv.Gradient 0, 0, VW, horizonY, SKY_TOP, SKY_TOP, SKY_HORIZON, SKY_HORIZON
    cv.Gradient 0, horizonY, VW, VH - horizonY, SKY_HORIZON, SKY_HORIZON, SKY_LOW, SKY_LOW
    glClear GL_DEPTH_BUFFER_BIT

    r0 = BallRow() - 2
    r1 = BallRow() + 18
    glDisable GL_LIGHTING
    glShadeModel GL_FLAT
    DrawRoad r0, r1
    DrawBlocks r0, r1
    DrawShadow
    glEnable GL_LIGHTING
    DrawGems r0, r1
    glShadeModel GL_SMOOTH
    DrawBall
    glShadeModel GL_FLAT
    glDisable GL_LIGHTING
    GLPresent

    ' labels where the gems were (GLProject: world -> canvas pixels)
    For i = 0 To NLABELS - 1
        If labT(i) > 0 Then
            If GLProject(labX(i), labY(i), labZ(i), pr) Then
                cv.DrawText pr(0) - cv.TextWidth(labText(i)) / 2, pr(1) - 5, labText(i), IIf(labT(i) > 8, vbYellow, RGB(160, 140, 60))
            End If
        End If
    Next i
End Sub

' text with a dark outline (readable on the sky and the road)
Public Sub ShadowText(cv As Object, ByVal x As Long, ByVal y As Long, ByVal t As String, ByVal c As Long)
    cv.DrawText x + 1, y + 1, t, RGB(20, 20, 40)
    cv.DrawText x, y, t, c
End Sub

Public Sub CentreText(cv As Object, ByVal y As Long, ByVal t As String, ByVal c As Long, ByVal sc As Long)
    Dim w As Long
    w = cv.TextWidth(t) * sc
    If sc > 1 Then
        cv.DrawTextScaled (VW - w) \ 2 + sc, y + sc, t, RGB(20, 20, 40), sc
        cv.DrawTextScaled (VW - w) \ 2, y, t, c, sc
    Else
        ShadowText cv, (VW - w) \ 2, y, t, c
    End If
End Sub
