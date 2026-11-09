' StMesh - the tower's 3D: a static mesh (MeshSet, once), turned about the y axis by the
' view's angle, seen by render.c's camera, face lists culled, sorted and drawn in passes.
' This is the BASIC stand-in (on examples/common/A3Scene.bas's draw list) for the Boing
' BASIC 3D library: the calls are the shape that library takes, so only this file changes.
Option Explicit

Public towerPolys As Long               ' polygons drawn this frame

Private mX(0 To 7407) As Long, mY(0 To 7407) As Long, mZ(0 To 7407) As Long
Private tX(0 To 7407) As Long, tY(0 To 7407) As Long, tZ(0 To 7407) As Long, tStamp(0 To 7407) As Long
Private stamp As Long
Private cosV As Long, sinV As Long
Private cam As A3Cam

Public Sub MeshSet(ByVal i As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long)
    mX(i) = x: mY(i) = y: mZ(i) = z
End Sub

Public Sub TowerInit(cv As Object)
    cam.x = 0: cam.y = 300: cam.z = -640
    cam.yaw = 0: cam.pitch = 900
    CamView cam, 200, 256, 100, 120, 200
    CamSetup cam
End Sub

' a new frame, the tower turned by yaw (16-bit angle: the point at angle a is drawn at a - yaw)
Public Sub TowerBegin(ByVal yaw As Long)
    stamp = stamp + 1
    cosV = A3Cos(yaw)
    sinV = A3Sin(yaw)
    towerPolys = 0
    A3Begin 1600
End Sub

' a point into camera space (tX/tY/tZ), once a frame
Private Sub Xf(ByVal v As Long)
    Dim x As Long, z As Long, dy As Long, t As Long, cp As Long, sp As Long
    t = mX(v) * (cosV \ 16) + mZ(v) * (sinV \ 16)
    x = (t - (t And 4095)) \ 4096
    t = mZ(v) * (cosV \ 16) - mX(v) * (sinV \ 16)
    z = (t - (t And 4095)) \ 4096 + 640
    dy = mY(v) - 300
    cp = cam.cp4: sp = cam.sp4
    tX(v) = x
    t = dy * cp + z * sp
    tY(v) = (t - (t And 4095)) \ 4096
    t = z * cp - dy * sp
    tZ(v) = (t - (t And 4095)) \ 4096
    tStamp(v) = stamp
End Sub

' the faces of list l into this pass: those facing the camera
Public Sub TowerAdd(ByVal l As Long)
    Dim k As Long, i As Long, j As Long, v As Long, b As Long
    Dim ux As Long, uy As Long, uz As Long, wx As Long, wy As Long, wz As Long
    Dim ax As Long, ay As Long, az As Long
    For k = 0 To fN(l) - 1
        i = l * L_CAP + k
        b = i * 4
        For j = 0 To 3
            v = fV(b + j)
            If tStamp(v) <> stamp Then Xf v
        Next j
        v = fV(b)
        ax = tX(v): ay = tY(v): az = tZ(v)
        v = fV(b + 1)
        ux = tX(v) - ax: uy = tY(v) - ay: uz = tZ(v) - az
        v = fV(b + 2)
        wx = tX(v) - ax: wy = tY(v) - ay: wz = tZ(v) - az
        ' facing the camera: the normal points back at it
        If CDbl(uy * wz - uz * wy) * ax + CDbl(uz * wx - ux * wz) * ay + CDbl(ux * wy - uy * wx) * az < 0# Then
            For j = 0 To 3
                v = fV(b + j)
                pvx(j) = tX(v): pvy(j) = tY(v): pvz(j) = tZ(v)
            Next j
            A3Poly cam, (pvz(0) + pvz(1) + pvz(2) + pvz(3)) \ 4 + fBias(i), fPen(i), 4
        End If
    Next k
End Sub

Public Sub TowerFlush(cv As Object)
    towerPolys = towerPolys + a3NPolys
    A3Flush cv
    A3Begin 1600
End Sub
