' A3Scene - the amiga3d engine's 3D in BASIC (a3d_math.c's camera and clipping,
' a3d_draw.c's draw list and models), drawing on a Canvas in the games' 320 x 256
' coordinates. Game-side code for the BASIC ports, until the Boing BASIC 3D library
' takes over: the calls keep the C names (cam_xform -> CamXform ...).
'
' Camera space: x right, y up, z ahead. A camera placed with CamPlace (16.16 world
' position) works in sixteenths of a unit (CamU = 16), as the C's cam_place.
' The draw list buckets polygons by depth and draws them far to near.
Option Explicit

Public Const NEAR_Z As Long = 12
Public Const A3_MAXPV As Long = 10
Public Const COL_BODY As Long = 200
Public Const COL_FLASH As Long = 210
Public Const MDL_MAXV As Long = 64
Public Const MDL_MAXF As Long = 48

Public Type A3Cam
    x As Long
    y As Long
    z As Long
    yaw As Long
    pitch As Long
    cy4 As Long          ' cos(yaw) >> 4 ... (cam_setup)
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
End Type

Public Type A3Model
    nv As Long
    nf As Long
    vx(0 To 63) As Long
    vy(0 To 63) As Long
    vz(0 To 63) As Long
    fn(0 To 47) As Long
    fcol(0 To 47) As Long
    fi(0 To 191) As Long        ' 4 indices a face
End Type

' the result of CamXform
Public ox As Long, oy As Long, oz As Long
' a polygon being built in camera space (A3Poly's input)
Public pvx(0 To 9) As Long, pvy(0 To 9) As Long, pvz(0 To 9) As Long
Public a3NPolys As Long, a3Dropped As Long
' A3ModelDraw skips a model whose middle is this far behind the camera or outside
' the view (the C engine's 800 units; a game with small models can narrow it)
Public a3ModelMargin As Long
' added to A3QuadW's depth in mode -1 (the middle of corners 0 and 2)
Public a3QuadBias As Long

Private Const MAX_DPOLY As Long = 1500
Private Const NBUCKET As Long = 512
Private dpN(0 To 1499) As Long
Private dpCol(0 To 1499) As Long
Private dpNext(0 To 1499) As Long
Private dpX(0 To 14999) As Long
Private dpY(0 To 14999) As Long
Private bHead(0 To 511) As Long
Private bTail(0 To 511) As Long
Private farZ As Long
Private clx(0 To 9) As Long, cly(0 To 9) As Long, clz(0 To 9) As Long
Private sx(0 To 9) As Long, sy(0 To 9) As Long, tx(0 To 9) As Long, ty(0 To 9) As Long
Private fx(0 To 9) As Long, fy(0 To 9) As Long
Private mvx(0 To 63) As Long, mvy(0 To 63) As Long, mvz(0 To 63) As Long
Private visFace(0 To 47) As Long, visDepth(0 To 47) As Double

' ---------- the camera ----------
Public Function CamU(c As A3Cam) As Long
    If c.precise Then CamU = 16 Else CamU = 1
End Function

Public Function CamNear(c As A3Cam) As Long
    If c.precise Then CamNear = NEAR_Z * 16 Else CamNear = NEAR_Z
End Function

Public Sub CamSetup(c As A3Cam)
    c.cy4 = ShrA(A3Cos(c.yaw), 4)
    c.sy4 = ShrA(A3Sin(c.yaw), 4)
    c.cp4 = ShrA(A3Cos(c.pitch), 4)
    c.sp4 = ShrA(A3Sin(c.pitch), 4)
End Sub

' a camera at a 16.16 world position (sixteenths kept)
Public Sub CamPlace(c As A3Cam, ByVal x As Long, ByVal y As Long, ByVal z As Long)
    c.x = ShrA(x, 16): c.y = ShrA(y, 16): c.z = ShrA(z, 16)
    c.qx = ShrA(x, 12) And 15: c.qy = ShrA(y, 12) And 15: c.qz = ShrA(z, 12) And 15
    c.precise = 1
End Sub

' a copy of c for drawing an object at a 16.16 position (pass its whole units)
Public Sub CamFor(c As A3Cam, ByVal x As Long, ByVal y As Long, ByVal z As Long, o As A3Cam)
    o = c
    If c.precise = 0 Then Exit Sub
    o.qx = o.qx - (ShrA(x, 12) And 15)
    o.qy = o.qy - (ShrA(y, 12) And 15)
    o.qz = o.qz - (ShrA(z, 12) And 15)
End Sub

Public Sub CamView(c As A3Cam, ByVal vw As Long, ByVal vh As Long, ByVal cx As Long, ByVal cy As Long, ByVal fov As Long)
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
    Dim i As Long
    If a3ModelMargin = 0 Then a3ModelMargin = 800
    a3NPolys = 0
    If fz > 0 Then farZ = fz Else farZ = 1
    For i = 0 To NBUCKET - 1
        bHead(i) = -1
        bTail(i) = -1
    Next i
End Sub

' the polygon in pvx/pvy/pvz (n points, camera space) into the list at depth
Public Sub A3Poly(c As A3Cam, ByVal depth As Long, ByVal col As Long, ByVal n As Long)
    Dim i As Long, j As Long, m As Long, nz As Long, ain As Boolean, bin As Boolean
    Dim p As Long, q As Long, t As Double, d As Double, b As Long, base As Long, k As Long
    Dim x1 As Long, y1 As Long, allIn As Boolean
    ' near plane (most polygons are wholly in front: copied straight)
    nz = CamNear(c)
    m = 0
    allIn = True
    For i = 0 To n - 1
        If pvz(i) < nz Then
            allIn = False
            Exit For
        End If
    Next i
    If allIn Then
        For i = 0 To n - 1
            clx(i) = pvx(i): cly(i) = pvy(i): clz(i) = pvz(i)
        Next i
        m = n
    Else
    For i = 0 To n - 1
        If i = n - 1 Then j = 0 Else j = i + 1
        ain = pvz(i) >= nz
        bin = pvz(j) >= nz
        If ain And m < A3_MAXPV Then
            clx(m) = pvx(i): cly(m) = pvy(i): clz(m) = pvz(i)
            m = m + 1
        End If
        If ain <> bin And m < A3_MAXPV Then
            If ain Then
                p = i: q = j
            Else
                p = j: q = i
            End If
            d = pvz(q) - pvz(p)
            t = nz - pvz(p)
            clx(m) = pvx(p) + Fix((pvx(q) - pvx(p)) * t / d)
            cly(m) = pvy(p) + Fix((pvy(q) - pvy(p)) * t / d)
            clz(m) = nz
            m = m + 1
        End If
    Next i
    End If
    If m < 3 Then Exit Sub
    ' project
    allIn = True
    x1 = c.vw - 1
    y1 = c.vh - 1
    For i = 0 To m - 1
        sx(i) = c.cx + (clx(i) * c.fov) \ clz(i)
        sy(i) = c.cyc - (cly(i) * c.fov) \ clz(i)
        If sx(i) < 0 Or sx(i) > x1 Or sy(i) < 0 Or sy(i) > y1 Then allIn = False
    Next i
    If Not allIn Then
        m = ClipEdge(m, 0, 0, True, True)
        If m < 3 Then Exit Sub
        m = ClipEdge(m, 0, x1, False, False)
        If m < 3 Then Exit Sub
        m = ClipEdge(m, 1, 0, True, True)
        If m < 3 Then Exit Sub
        m = ClipEdge(m, 1, y1, False, False)
        If m < 3 Then Exit Sub
    End If
    If a3NPolys >= MAX_DPOLY Then
        a3Dropped = a3Dropped + 1
        Exit Sub
    End If
    k = a3NPolys
    dpN(k) = m
    dpCol(k) = col
    dpNext(k) = -1
    base = k * 10
    For i = 0 To m - 1
        dpX(base + i) = sx(i)
        dpY(base + i) = sy(i)
    Next i
    If c.precise Then depth = depth \ 16
    If depth < 0 Then
        b = 0
    ElseIf depth >= farZ Then
        b = NBUCKET - 1
    Else
        b = (depth * NBUCKET) \ farZ
    End If
    If bTail(b) >= 0 Then dpNext(bTail(b)) = k Else bHead(b) = k
    bTail(b) = k
    a3NPolys = k + 1
End Sub

' one Sutherland-Hodgman pass of sx/sy against an axis-aligned edge; fromS: the
' input is in sx/sy (output to tx/ty), else the other way. ge: keep >= lim.
Private Function ClipEdge(ByVal n As Long, ByVal axis As Long, ByVal lim As Long, ByVal ge As Boolean, ByVal fromS As Boolean) As Long
    Dim i As Long, j As Long, m As Long, av As Long, bv As Long, ain As Boolean, bin As Boolean
    Dim p As Long, q As Long, pv As Long, qv As Long
    If fromS Then
        For i = 0 To n - 1
            fx(i) = sx(i): fy(i) = sy(i)
        Next i
    Else
        For i = 0 To n - 1
            fx(i) = tx(i): fy(i) = ty(i)
        Next i
    End If
    For i = 0 To n - 1
        If i = n - 1 Then j = 0 Else j = i + 1
        If axis Then
            av = fy(i): bv = fy(j)
        Else
            av = fx(i): bv = fx(j)
        End If
        If ge Then
            ain = av >= lim: bin = bv >= lim
        Else
            ain = av <= lim: bin = bv <= lim
        End If
        If ain And m < A3_MAXPV Then
            tx(m) = fx(i): ty(m) = fy(i)
            m = m + 1
        End If
        If ain <> bin And m < A3_MAXPV Then
            If ain Then
                p = i: q = j
            Else
                p = j: q = i
            End If
            If axis Then
                pv = fy(p): qv = fy(q)
                tx(m) = fx(p) + Fix(CDbl(fx(q) - fx(p)) * (lim - pv) / (qv - pv))
                ty(m) = lim
            Else
                pv = fx(p): qv = fx(q)
                tx(m) = lim
                ty(m) = fy(p) + Fix(CDbl(fy(q) - fy(p)) * (lim - pv) / (qv - pv))
            End If
            m = m + 1
        End If
    Next i
    ' the result always ends in sx/sy
    For i = 0 To m - 1
        sx(i) = tx(i): sy(i) = ty(i)
    Next i
    ClipEdge = m
End Function

' a quad in camera space (skipped when all of it is behind or off one side)
Public Sub A3Quad(c As A3Cam, ByVal depth As Long, ByVal col As Long, _
                  ByVal ax As Long, ByVal ay As Long, ByVal az As Long, ByVal bx As Long, ByVal by As Long, ByVal bz As Long, _
                  ByVal dx As Long, ByVal dy As Long, ByVal dz As Long, ByVal ex As Long, ByVal ey As Long, ByVal ez As Long)
    Dim nz As Long
    nz = CamNear(c)
    If az < nz And bz < nz And dz < nz And ez < nz Then Exit Sub
    If ax > az And bx > bz And dx > dz And ex > ez Then Exit Sub
    If ax < -az And bx < -bz And dx < -dz And ex < -ez Then Exit Sub
    pvx(0) = ax: pvy(0) = ay: pvz(0) = az
    pvx(1) = bx: pvy(1) = by: pvz(1) = bz
    pvx(2) = dx: pvy(2) = dy: pvz(2) = dz
    pvx(3) = ex: pvy(3) = ey: pvz(3) = ez
    A3Poly c, depth, col, 4
End Sub

' a quad from four world points (CamXform written out four times: calls cost in the VM)
Public Sub A3QuadW(c As A3Cam, ByVal depthMode As Long, ByVal col As Long, _
                   ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                   ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long)
    Dim cu As Long, cy4 As Long, sy4 As Long, cp4 As Long, sp4 As Long, t As Long, rz As Long, k As Long
    Dim dx As Long, dy As Long, dz As Long, nz As Long
    If c.precise Then cu = 16 Else cu = 1
    cy4 = c.cy4: sy4 = c.sy4: cp4 = c.cp4: sp4 = c.sp4
    For k = 0 To 3
        Select Case k
            Case 0: dx = x0: dy = y0: dz = z0
            Case 1: dx = x1: dy = y1: dz = z1
            Case 2: dx = x2: dy = y2: dz = z2
            Case Else: dx = x3: dy = y3: dz = z3
        End Select
        dx = (dx - c.x) * cu - c.qx
        dy = (dy - c.y) * cu - c.qy
        dz = (dz - c.z) * cu - c.qz
        t = dx * cy4 - dz * sy4
        pvx(k) = (t - (t And 4095)) \ 4096
        t = dx * sy4 + dz * cy4
        rz = (t - (t And 4095)) \ 4096
        t = dy * cp4 + rz * sp4
        pvy(k) = (t - (t And 4095)) \ 4096
        t = rz * cp4 - dy * sp4
        pvz(k) = (t - (t And 4095)) \ 4096
    Next k
    ' (A3Quad's early outs)
    nz = CamNear(c)
    If pvz(0) < nz And pvz(1) < nz And pvz(2) < nz And pvz(3) < nz Then Exit Sub
    If pvx(0) > pvz(0) And pvx(1) > pvz(1) And pvx(2) > pvz(2) And pvx(3) > pvz(3) Then Exit Sub
    If pvx(0) < -pvz(0) And pvx(1) < -pvz(1) And pvx(2) < -pvz(2) And pvx(3) < -pvz(3) Then Exit Sub
    ' depthMode >= 0: that depth; -1: the middle of the first and third corners; -2: of all four
    If depthMode = -1 Then
        depthMode = (pvz(0) + pvz(2)) \ 2 + a3QuadBias
    ElseIf depthMode = -2 Then
        depthMode = (pvz(0) + pvz(1) + pvz(2) + pvz(3)) \ 4
    End If
    A3Poly c, depthMode, col, 4
End Sub

' a line between two world points, drawn straight away: cut at the near plane
' and at the picture's edges (the Canvas would step through the whole line)
Public Sub A3LineW(cv As Object, c As A3Cam, ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, _
                   ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, ByVal col As Long)
    Dim ax As Long, ay As Long, az As Long, nz As Long, t As Double
    Dim sx0 As Double, sy0 As Double, sx1 As Double, sy1 As Double, dx As Double, dy As Double
    Dim t0 As Double, t1 As Double, p As Double, q As Double, r As Double, k As Long
    CamXform c, x0, y0, z0: ax = ox: ay = oy: az = oz
    CamXform c, x1, y1, z1
    nz = CamNear(c)
    If az < nz And oz < nz Then Exit Sub
    If az < nz Then
        t = CDbl(nz - oz) / (az - oz)
        ax = ox + Fix((ax - ox) * t): ay = oy + Fix((ay - oy) * t): az = nz
    ElseIf oz < nz Then
        t = CDbl(nz - az) / (oz - az)
        ox = ax + Fix((ox - ax) * t): oy = ay + Fix((oy - ay) * t): oz = nz
    End If
    sx0 = c.cx + (ax * c.fov) \ az: sy0 = c.cyc - (ay * c.fov) \ az
    sx1 = c.cx + (ox * c.fov) \ oz: sy1 = c.cyc - (oy * c.fov) \ oz
    ' Liang-Barsky against 0..vw-1, 0..vh-1
    dx = sx1 - sx0: dy = sy1 - sy0
    t0 = 0#: t1 = 1#
    For k = 0 To 3
        Select Case k
            Case 0: p = -dx: q = sx0
            Case 1: p = dx: q = c.vw - 1 - sx0
            Case 2: p = -dy: q = sy0
            Case Else: p = dy: q = c.vh - 1 - sy0
        End Select
        If p = 0# Then
            If q < 0# Then Exit Sub
        Else
            r = q / p
            If p < 0# Then
                If r > t1 Then Exit Sub
                If r > t0 Then t0 = r
            Else
                If r < t0 Then Exit Sub
                If r < t1 Then t1 = r
            End If
        End If
    Next k
    cv.Line CLng(sx0 + t0 * dx), CLng(sy0 + t0 * dy), CLng(sx0 + t1 * dx), CLng(sy0 + t1 * dy), col
End Sub

' draw the list, far to near
Public Sub A3Flush(cv As Object)
    Dim b As Long, k As Long, i As Long, base As Long, n As Long
    For b = NBUCKET - 1 To 0 Step -1
        k = bHead(b)
        Do While k >= 0
            n = dpN(k)
            base = k * 10
            For i = 0 To n - 1
                fx(i) = dpX(base + i)
                fy(i) = dpY(base + i)
            Next i
            cv.Polygon fx, fy, n, pen(dpCol(k)), True
            k = dpNext(k)
        Loop
    Next b
End Sub

' ---------- models ----------
Public Sub MdlBegin(m As A3Model)
    m.nv = 0
    m.nf = 0
End Sub

Public Function MdlVtx(m As A3Model, ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    Dim i As Long
    i = m.nv
    If i >= MDL_MAXV Then
        MdlVtx = MDL_MAXV - 1
        Exit Function
    End If
    m.nv = i + 1
    m.vx(i) = x: m.vy(i) = y: m.vz(i) = z
    MdlVtx = i
End Function

' a face; flipped if it faces the interior point (ix, iy, iz); shaded by a fixed
' sun high in the north-west (-1, 2, 1)
Public Sub MdlFace(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal n As Long, ByVal a As Long, ByVal b As Long, _
                   ByVal c As Long, ByVal d As Long, ByVal ix As Long, ByVal iy As Long, ByVal iz As Long)
    Dim ux As Long, uy As Long, uz As Long, vx As Long, vy As Long, vz As Long
    Dim nx As Long, ny As Long, nzz As Long, light As Long, mag As Long, f As Long
    If m.nf >= MDL_MAXF Then Exit Sub
    ux = m.vx(b) - m.vx(a): uy = m.vy(b) - m.vy(a): uz = m.vz(b) - m.vz(a)
    vx = m.vx(c) - m.vx(a): vy = m.vy(c) - m.vy(a): vz = m.vz(c) - m.vz(a)
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nzz = ux * vy - uy * vx
    f = m.nf
    m.nf = f + 1
    m.fn(f) = n
    If CDbl(nx) * (m.vx(a) - ix) + CDbl(ny) * (m.vy(a) - iy) + CDbl(nzz) * (m.vz(a) - iz) >= 0 Then
        m.fi(f * 4) = a: m.fi(f * 4 + 1) = b: m.fi(f * 4 + 2) = c: m.fi(f * 4 + 3) = d
    Else
        If n = 4 Then
            m.fi(f * 4) = d: m.fi(f * 4 + 1) = c: m.fi(f * 4 + 2) = b: m.fi(f * 4 + 3) = a
        Else
            m.fi(f * 4) = c: m.fi(f * 4 + 1) = b: m.fi(f * 4 + 2) = a: m.fi(f * 4 + 3) = 0
        End If
        nx = -nx: ny = -ny: nzz = -nzz
    End If
    light = -nx + 2 * ny + nzz
    mag = Abs(nx) + Abs(ny) + Abs(nzz)
    If mag <> 0 And CDbl(light) * 4 > CDbl(mag) * 3 Then m.fcol(f) = lit Else m.fcol(f) = shade
End Sub

Public Sub MdlBox(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal x0 As Long, ByVal x1 As Long, _
                  ByVal y0 As Long, ByVal y1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    Dim b As Long, cx As Long, cy As Long, cz As Long, k As Long
    b = m.nv
    cx = (x0 + x1) \ 2: cy = (y0 + y1) \ 2: cz = (z0 + z1) \ 2
    k = MdlVtx(m, x0, y0, z0): k = MdlVtx(m, x1, y0, z0): k = MdlVtx(m, x1, y1, z0): k = MdlVtx(m, x0, y1, z0)
    k = MdlVtx(m, x0, y0, z1): k = MdlVtx(m, x1, y0, z1): k = MdlVtx(m, x1, y1, z1): k = MdlVtx(m, x0, y1, z1)
    MdlFace m, lit, shade, 4, b + 0, b + 3, b + 2, b + 1, cx, cy, cz
    MdlFace m, lit, shade, 4, b + 5, b + 6, b + 7, b + 4, cx, cy, cz
    MdlFace m, lit, shade, 4, b + 4, b + 7, b + 3, b + 0, cx, cy, cz
    MdlFace m, lit, shade, 4, b + 1, b + 2, b + 6, b + 5, cx, cy, cz
    MdlFace m, lit, shade, 4, b + 3, b + 7, b + 6, b + 2, cx, cy, cz
    MdlFace m, lit, shade, 4, b + 0, b + 1, b + 5, b + 4, cx, cy, cz
End Sub

Public Sub MdlPyramid(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal x0 As Long, ByVal x1 As Long, _
                      ByVal y0 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal apex As Long)
    Dim b As Long, t As Long, cx As Long, cz As Long, cy As Long, k As Long
    b = m.nv
    cx = (x0 + x1) \ 2: cz = (z0 + z1) \ 2: cy = y0 + (apex - y0) \ 4
    k = MdlVtx(m, x0, y0, z0): k = MdlVtx(m, x1, y0, z0): k = MdlVtx(m, x1, y0, z1): k = MdlVtx(m, x0, y0, z1)
    t = MdlVtx(m, cx, apex, cz)
    MdlFace m, lit, shade, 3, b + 0, b + 1, t, 0, cx, cy, cz
    MdlFace m, lit, shade, 3, b + 1, b + 2, t, 0, cx, cy, cz
    MdlFace m, lit, shade, 3, b + 2, b + 3, t, 0, cx, cy, cz
    MdlFace m, lit, shade, 3, b + 3, b + 0, t, 0, cx, cy, cz
End Sub

' a prism about the y axis
Public Sub MdlPrism(m As A3Model, ByVal lit As Long, ByVal shade As Long, ByVal sides As Long, ByVal r As Long, _
                    ByVal y0 As Long, ByVal y1 As Long)
    Dim b As Long, k As Long, j As Long, cy As Long, a As Long, x As Long, z As Long, c As Long, q As Long
    b = m.nv
    cy = (y0 + y1) \ 2
    For k = 0 To sides - 1
        a = (k * 65536) \ sides
        x = ShrA(A3Sin(a) * r, 16)
        z = ShrA(A3Cos(a) * r, 16)
        q = MdlVtx(m, x, y0, z)
        q = MdlVtx(m, x, y1, z)
    Next k
    For k = 0 To sides - 1
        j = (k + 1) Mod sides
        MdlFace m, lit, shade, 4, b + 2 * k, b + 2 * k + 1, b + 2 * j + 1, b + 2 * j, 0, cy, 0
    Next k
    c = MdlVtx(m, 0, y1, 0)
    For k = 0 To sides - 1
        j = (k + 1) Mod sides
        MdlFace m, lit, lit, 3, b + 2 * k + 1, b + 2 * j + 1, c, 0, 0, y0, 0
    Next k
End Sub

' a shadow flat on the ground (y = 1): always drawn first
Public Sub MdlShadow(m As A3Model, ByVal col As Long, ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    Dim b As Long, k As Long
    b = m.nv
    k = MdlVtx(m, x0, 1, z0): k = MdlVtx(m, x1, 1, z0): k = MdlVtx(m, x1, 1, z1): k = MdlVtx(m, x0, 1, z1)
    MdlFace m, col, col, 4, b + 0, b + 1, b + 2, b + 3, 0, -10, 0
End Sub

' rotation matrices, 16.16, row-major: world = M * model
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
    Dim i As Long, k As Long, nvis As Long, x As Long, y As Long, z As Long, mg As Long
    Dim cxz As Long, a As Long, b As Long, d As Long, col As Long, n As Long, rx As Long, ry As Long, rzz As Long
    Dim bx As Long, by As Long, bz As Long, cu As Long, qx0 As Long, qy0 As Long, qz0 As Long
    Dim cy4 As Long, sy4 As Long, cp4 As Long, sp4 As Long
    Dim ux As Long, uy As Long, uz As Long, vx As Long, vy As Long, vz As Long
    Dim nx As Double, ny As Double, nzz As Double, depth As Double, dep As Long
    CamXform c, wx, wy, wz
    cxz = oz
    mg = a3ModelMargin * CamU(c)
    If oz < -mg Or ox > oz + mg Or ox < -oz - mg Then Exit Sub
    ' the vertices to camera space (CamXform written out: calls cost in the VM)
    bx = wx - c.x: by = wy - c.y: bz = wz - c.z
    If c.precise Then
        cu = 16
        qx0 = c.qx: qy0 = c.qy: qz0 = c.qz
    Else
        cu = 1
    End If
    cy4 = c.cy4: sy4 = c.sy4: cp4 = c.cp4: sp4 = c.sp4
    For i = 0 To m.nv - 1
        x = m.vx(i): y = m.vy(i): z = m.vz(i)
        If useRot Then
            rx = x * rm(0) + y * rm(1) + z * rm(2)
            ry = x * rm(3) + y * rm(4) + z * rm(5)
            rzz = x * rm(6) + y * rm(7) + z * rm(8)
            x = (rx - (rx And 65535)) \ 65536
            y = (ry - (ry And 65535)) \ 65536
            z = (rzz - (rzz And 65535)) \ 65536
        End If
        x = (bx + x) * cu - qx0
        y = (by + y) * cu - qy0
        z = (bz + z) * cu - qz0
        rx = x * cy4 - z * sy4
        mvx(i) = (rx - (rx And 4095)) \ 4096
        rx = x * sy4 + z * cy4
        rzz = (rx - (rx And 4095)) \ 4096
        rx = y * cp4 + rzz * sp4
        mvy(i) = (rx - (rx And 4095)) \ 4096
        rx = rzz * cp4 - y * sp4
        mvz(i) = (rx - (rx And 4095)) \ 4096
    Next i
    ' the faces that face the camera, farthest first
    For k = 0 To m.nf - 1
        a = m.fi(k * 4): b = m.fi(k * 4 + 1): d = m.fi(k * 4 + 2)
        ux = mvx(b) - mvx(a): uy = mvy(b) - mvy(a): uz = mvz(b) - mvz(a)
        vx = mvx(d) - mvx(a): vy = mvy(d) - mvy(a): vz = mvz(d) - mvz(a)
        nx = CDbl(uy) * vz - CDbl(uz) * vy
        ny = CDbl(uz) * vx - CDbl(ux) * vz
        nzz = CDbl(ux) * vy - CDbl(uy) * vx
        If nx * mvx(a) + ny * mvy(a) + nzz * mvz(a) < 0 Then
            If m.fn(k) = 4 Then
                depth = CDbl(mvz(a)) + mvz(b) + mvz(d) + mvz(m.fi(k * 4 + 3))
            Else
                depth = CDbl(mvz(a)) + mvz(b) + mvz(d) + mvz(d)
            End If
            If m.vy(a) = 1 And m.vy(b) = 1 And m.vy(d) = 1 Then depth = 2147483647#   ' a shadow goes first
            i = nvis
            Do While i > 0
                If visDepth(i - 1) >= depth Then Exit Do
                visFace(i) = visFace(i - 1)
                visDepth(i) = visDepth(i - 1)
                i = i - 1
            Loop
            visFace(i) = k
            visDepth(i) = depth
            nvis = nvis + 1
        End If
    Next k
    dep = cxz - depthBias * CamU(c)
    For i = 0 To nvis - 1
        k = visFace(i)
        n = m.fn(k)
        a = m.fi(k * 4)
        pvx(0) = mvx(a): pvy(0) = mvy(a): pvz(0) = mvz(a)
        a = m.fi(k * 4 + 1)
        pvx(1) = mvx(a): pvy(1) = mvy(a): pvz(1) = mvz(a)
        a = m.fi(k * 4 + 2)
        pvx(2) = mvx(a): pvy(2) = mvy(a): pvz(2) = mvz(a)
        If n = 4 Then
            a = m.fi(k * 4 + 3)
            pvx(3) = mvx(a): pvy(3) = mvy(a): pvz(3) = mvz(a)
        End If
        col = m.fcol(k)
        If col >= COL_FLASH Then
            col = flash
        ElseIf col = COL_BODY Then
            col = bodyLit
        ElseIf col > COL_BODY Then
            col = bodyShade
        End If
        A3Poly c, dep, col, n
    Next i
End Sub
