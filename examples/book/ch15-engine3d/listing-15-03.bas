Option Explicit

Sub Main()
    Dim e As Engine3D, sx As Long, sy As Long, cx As Long, cy As Long, cz As Long
    Set e = CreateObject("Boing.Engine3D")
    e.View 320, 256, 160, 128, 256
    e.CamPos 0, 100, 0
    e.CamAngles 0, 0                       ' looking along +z, level
    Print "horizon row:"; e.Horizon
    e.Xform 50, 100, 400, cx, cy, cz
    Print "camera space:"; cx; cy; cz
    If e.Project(50, 100, 400, sx, sy) Then Print "on screen at"; sx; sy
    If Not e.Project(0, 100, -50, sx, sy) Then Print "a point behind the camera is not drawn"
    Print "visible ahead:"; e.Visible(0, 100, 400, 10); "  behind:"; e.Visible(0, 100, -400, 10)
    e.CamLookAt 400, 100, 400              ' turn to look at a point
    Print "yaw after CamLookAt:"; e.CamYaw; " pitch:"; e.CamPitch
    e.CamSave 0
    e.CamPos 1000, 0, 0
    e.CamLoad 0
    Print "camera restored to x ="; e.CamX
End Sub
