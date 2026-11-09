' A3Engine - A3Scene.bas's API on Boing.Engine3D: the same subs, types and globals, with the
' 3D work (transforms, clipping, sorting, models, filling) done in C by the engine
' (docs/engine3d.md). Use it in place of A3Scene.bas in a project: the game code stays as it
' is. The camera maths for game logic (CamXform, CamProject...) stays in BASIC, bit-exact.
' The engine's camera is re-sent only when the A3Cam's version changes (CamSetup, CamPlace,
' CamFor and CamView set it), so after changing a camera's fields directly call CamSetup.
' Needs Gfx2D.bas (gcv, pen()). Pictures are amiga3d's raster (the C games' pixels).
Option Explicit

Public Const NEAR_Z As Long = 12
Public Const A3_MAXPV As Long = 10
Public Const COL_BODY As Long = 200
Public Const COL_FLASH As Long = 210
Public Const MDL_MAXV As Long = 256
Public Const MDL_MAXF As Long = 192

Public Type A3Cam
    x As Long
    y As Long
    z As Long
    yaw As Long
    pitch As Long
    cy4 As Long
    sy4 As Long
    cp4 As Long
    sp4 As Long
    cx As Long
    cyc As Long
    fov As Long
    vw As Long
    vh As Long
    qx As Long
    qy As Long
    qz As Long
    precise As Long
    ver As Long          ' set by CamSetup/CamPlace/CamFor/CamView: the engine is re-sent only when it changes
End Type

' a model is a number in the engine
Public Type A3Model
    id As Long
    nv As Long
    nf As Long
End Type

Public ox As Long, oy As Long, oz As Long
Public pvx(0 To 9) As Long, pvy(0 To 9) As Long, pvz(0 To 9) As Long
Public a3NPolys As Long, a3Dropped As Long
Public a3ModelMargin As Long
Public a3QuadBias As Long
Public e3d As Object                ' the engine (made on first use, drawing into gcv)

Private last As A3Cam, haveLast As Boolean, lastMargin As Long, lastBias As Long
Private lastVer As Long, camVer As Long

Private Sub Bump(c As A3Cam)
    camVer = camVer + 1
    c.ver = camVer
End Sub

' the engine, with c as its camera (one call when the camera changed since the last time)
Private Sub UseCam(c As A3Cam)
    ' the common case: the same camera as last time (one compare)
    If c.ver = lastVer Then
        If c.ver <> 0 Then
            If a3ModelMargin <> lastMargin Then GoTo margins
            If a3QuadBias <> lastBias Then GoTo margins
            Exit Sub
        End If
    End If
    If e3d Is Nothing Then
        Set e3d = CreateObject("Boing.Engine3D")
        e3d.Attach gcv
        haveLast = False
        lastMargin = 800
    End If
    If haveLast Then
        If c.x = last.x And c.y = last.y And c.z = last.z And c.yaw = last.yaw And c.pitch = last.pitch And _
           c.qx = last.qx And c.qy = last.qy And c.qz = last.qz And c.precise = last.precise And _
           c.fov = last.fov And c.cx = last.cx And c.cyc = last.cyc And c.vw = last.vw And c.vh = last.vh Then GoTo margins
    End If
    If c.vw <> last.vw Or c.vh <> last.vh Or c.cx <> last.cx Or c.cyc <> last.cyc Or c.fov <> last.fov Or Not haveLast Then
        e3d.View c.vw, c.vh, c.cx, c.cyc, c.fov
    End If
    If c.precise Then
        e3d.CamSet c.x, c.y, c.z, c.yaw, c.pitch, c.qx, c.qy, c.qz
    Else
        e3d.CamSet c.x, c.y, c.z, c.yaw, c.pitch
    End If
    last = c
    haveLast = True
    lastVer = c.ver
margins:
    If a3ModelMargin <> lastMargin Then
        If a3ModelMargin > 0 Then e3d.ModelMargin = a3ModelMargin Else e3d.ModelMargin = 800
        lastMargin = a3ModelMargin
    End If
    If a3QuadBias <> lastBias Then
        e3d.QuadBias = a3QuadBias
        lastBias = a3QuadBias
    End If
End Sub

Private Sub Engine()
    If e3d Is Nothing Then
        Set e3d = CreateObject("Boing.Engine3D")
        e3d.Attach gcv
        haveLast = False
        lastMargin = 800
    End If
End Sub

' ---------- the camera (BASIC, bit-exact with the C) ----------
Public Function CamU(c As A3Cam) As Long
    If c.precise Then CamU = 16 Else CamU = 1
End Function

Public Function CamNear(c As A3Cam) As Long
    If c.precise Then CamNear = NEAR_Z * 16 Else CamNear = NEAR_Z
End Function

Public Sub CamSetup(c As A3Cam)
    Bump c
    c.cy4 = ShrA(A3Cos(c.yaw), 4)
    c.sy4 = ShrA(A3Sin(c.yaw), 4)
    c.cp4 = ShrA(A3Cos(c.pitch), 4)
    c.sp4 = ShrA(A3Sin(c.pitch), 4)
End Sub

' a camera at a 16.16 world position (sixteenths kept)
Public Sub CamPlace(c As A3Cam, ByVal x As Long, ByVal y As Long, ByVal z As Long)
    Bump c
    c.x = ShrA(x, 16): c.y = ShrA(y, 16): c.z = ShrA(z, 16)
    c.qx = ShrA(x, 12) And 15: c.qy = ShrA(y, 12) And 15: c.qz = ShrA(z, 12) And 15
    c.precise = 1
End Sub

' a copy of c for drawing an object at a 16.16 position (pass its whole units)
Public Sub CamFor(c As A3Cam, ByVal x As Long, ByVal y As Long, ByVal z As Long, o As A3Cam)
    o = c
    If c.precise = 0 Then Exit Sub
    Bump o
    o.qx = o.qx - (ShrA(x, 12) And 15)
    o.qy = o.qy - (ShrA(y, 12) And 15)
    o.qz = o.qz - (ShrA(z, 12) And 15)
End Sub

Public Sub CamView(c As A3Cam, ByVal vw As Long, ByVal vh As Long, ByVal cx As Long, ByVal cy As Long, ByVal fov As Long)
    Bump c
    c.vw = vw: c.vh = vh: c.cx = cx: c.cyc = cy: c.fov = fov
End Sub

' world point -> camera space, into ox, oy, oz
Public Sub CamXform(c As A3Cam, ByVal wx As Long, ByVal wy As Long, ByVal wz As Long)
    Dim dx As Long, dy As Long, dz As Long, rz As Long, t As Long
    dx = wx - c.x
    dy = wy - c.y
    dz = wz - c.z
    If c.precise Then
        dx = dx * 16 - c.qx
        dy = dy * 16 - c.qy
        dz = dz * 16 - c.qz
    End If
    ' (t - (t And 4095)) \ 4096 is t >> 12, rounding down, in integers
    t = dx * c.cy4 - dz * c.sy4
    ox = (t - (t And 4095)) \ 4096
    t = dx * c.sy4 + dz * c.cy4
    rz = (t - (t And 4095)) \ 4096
    t = dy * c.cp4 + rz * c.sp4
    oy = (t - (t And 4095)) \ 4096
    t = rz * c.cp4 - dy * c.sp4
    oz = (t - (t And 4095)) \ 4096
End Sub

Public Function CamHorizon(c As A3Cam) As Long
    CamHorizon = c.cyc - (c.fov * c.sp4) \ c.cp4
End Function

' screen position of camera-space point (x, y, z), z >= near
Public Sub CamProject(c As A3Cam, ByVal x As Long, ByVal y As Long, ByVal z As Long, px As Long, py As Long)
    px = c.cx + (x * c.fov) \ z
    py = c.cyc - (y * c.fov) \ z
End Sub

' ---------- the draw list ----------
Public Sub A3Begin(ByVal fz As Long)
    Engine
    e3d.Palette pen              ' the pens as the game set them (Gfx2D's GfxPalette)
    e3d.Begin fz
    a3NPolys = 0
    a3Dropped = 0
End Sub

' the polygon in pvx/pvy/pvz (n points, camera space) into the list at depth
Public Sub A3Poly(c As A3Cam, ByVal depth As Long, ByVal col As Long, ByVal n As Long)
    UseCam c
    e3d.Poly depth, col, pvx, pvy, pvz, n
End Sub

Public Sub A3Quad(c As A3Cam, ByVal depth As Long, ByVal col As Long, _
                  ByVal ax As Long, ByVal ay As Long, ByVal az As Long, ByVal bx As Long, ByVal by As Long, ByVal bz As Long, _
                  ByVal dx As Long, ByVal dy As Long, ByVal dz As Long, ByVal ex As Long, ByVal ey As Long, ByVal ez As Long)
    UseCam c
    e3d.Quad depth, col, ax, ay, az, bx, by, bz, dx, dy, dz, ex, ey, ez
End Sub

' a quad of world points; depthMode >= 0 that depth, -1 the middle of corners 0 and 2 (+ a3QuadBias), -2 of all four
Public Sub A3QuadW(c As A3Cam, ByVal depthMode As Long, ByVal col As Long, _
                   ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                   ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long)
    UseCam c
    e3d.QuadW depthMode, col, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3
End Sub

' a line between two world points, drawn straight away (cut at the near plane and the edges)
Public Sub A3LineW(c As A3Cam, ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, _
                   ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, ByVal col As Long)
    UseCam c
    e3d.DrawLine3D x0, y0, z0, x1, y1, z1, -1 - col      ' col is a VB colour here
End Sub

Public Sub A3Flush()
    Engine
    e3d.Flush
    a3NPolys = e3d.NPolys
    a3Dropped = e3d.Dropped
End Sub

' ---------- models ----------
Public Sub MdlBegin(m As A3Model)
    Engine
    If m.id = 0 Then m.id = e3d.ModelNew() Else e3d.ModelClear m.id
    m.nv = 0
    m.nf = 0
End Sub

Public Function MdlVtx(m As A3Model, ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    MdlVtx = e3d.MdlVtx(m.id, x, y, z)
    m.nv = e3d.ModelVerts(m.id)
End Function

Public Sub MdlFace(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal n As Long, ByVal a As Long, ByVal b As Long, _
                   ByVal c As Long, ByVal d As Long, ByVal ix As Long, ByVal iy As Long, ByVal iz As Long)
    e3d.MdlFace m.id, lit, shade, n, a, b, c, d, ix, iy, iz
    m.nf = e3d.ModelFaces(m.id)
End Sub

Public Sub MdlBox(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal x0 As Long, ByVal x1 As Long, _
                  ByVal y0 As Long, ByVal y1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    e3d.MdlBox m.id, lit, shade, x0, x1, y0, y1, z0, z1
    m.nv = e3d.ModelVerts(m.id): m.nf = e3d.ModelFaces(m.id)
End Sub

Public Sub MdlPyramid(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal x0 As Long, ByVal x1 As Long, _
                      ByVal y0 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal apex As Long)
    e3d.MdlPyramid m.id, lit, shade, x0, x1, y0, z0, z1, apex
    m.nv = e3d.ModelVerts(m.id): m.nf = e3d.ModelFaces(m.id)
End Sub

Public Sub MdlPrism(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal sides As Long, ByVal r As Long, _
                    ByVal y0 As Long, ByVal y1 As Long)
    e3d.MdlPrism m.id, lit, shade, sides, r, y0, y1
    m.nv = e3d.ModelVerts(m.id): m.nf = e3d.ModelFaces(m.id)
End Sub

Public Sub MdlShadow(m As A3Model, ByVal col As Long, ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    e3d.MdlShadow m.id, col, x0, x1, z0, z1
    m.nv = e3d.ModelVerts(m.id): m.nf = e3d.ModelFaces(m.id)
End Sub

Public Sub RotYaw(rm() As Long, ByVal yaw As Long)
    Dim c As Long, s As Long
    c = A3Cos(yaw)
    s = A3Sin(yaw)
    rm(0) = c: rm(1) = 0: rm(2) = s
    rm(3) = 0: rm(4) = 65536: rm(5) = 0
    rm(6) = -s: rm(7) = 0: rm(8) = c
End Sub

' roll about z, then pitch about x, then yaw about y
Public Sub RotYPR(rm() As Long, ByVal yaw As Long, ByVal pitch As Long, ByVal roll As Long)
    Dim cy As Long, sy As Long, cp As Long, sp As Long, cr As Long, sr As Long
    Dim a00 As Long, a01 As Long, a10 As Long, a11 As Long, a12 As Long, a20 As Long, a21 As Long, a22 As Long
    cy = ShrA(A3Cos(yaw), 4): sy = ShrA(A3Sin(yaw), 4)
    cp = ShrA(A3Cos(pitch), 4): sp = ShrA(A3Sin(pitch), 4)
    cr = ShrA(A3Cos(roll), 4): sr = ShrA(A3Sin(roll), 4)
    a00 = cr: a01 = -sr: a10 = ShrA(cp * sr, 12): a11 = ShrA(cp * cr, 12): a12 = -sp
    a20 = ShrA(sp * sr, 12): a21 = ShrA(sp * cr, 12): a22 = cp
    rm(0) = ShrA(cy * a00 + sy * a20, 8): rm(1) = ShrA(cy * a01 + sy * a21, 8): rm(2) = ShrA(sy * a22, 8)
    rm(3) = a10 * 16: rm(4) = a11 * 16: rm(5) = a12 * 16
    rm(6) = ShrA(-sy * a00 + cy * a20, 8): rm(7) = ShrA(-sy * a01 + cy * a21, 8): rm(8) = ShrA(cy * a22, 8)
End Sub

' draw a model at world (wx, wy, wz); rotated by rm unless useRot is False;
' bodyLit/bodyShade: COL_BODY's pens; flash: COL_FLASH's pen; depthBias moves it in the list
Public Sub A3ModelDraw(c As A3Cam, m As A3Model, ByVal wx As Long, ByVal wy As Long, ByVal wz As Long, _
                       ByVal useRot As Boolean, rm() As Long, ByVal bodyLit As Long, ByVal bodyShade As Long, _
                       ByVal flash As Long, ByVal depthBias As Long)
    UseCam c
    If useRot Then
        e3d.DrawModelM m.id, wx, wy, wz, rm, bodyLit, bodyShade, flash, depthBias
    Else
        e3d.DrawModel m.id, wx, wy, wz, 0, 0, 0, bodyLit, bodyShade, flash, depthBias
    End If
End Sub
