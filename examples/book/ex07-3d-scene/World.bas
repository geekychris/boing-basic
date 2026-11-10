' World.bas - the 3D world of exercise 7: the engine, the models, the floor and the camera.
' The form (scene.bas) calls WorldInit once and WorldFrame for every frame. Nothing here
' needs a window, so the same code can draw into an off-screen canvas too.
Option Explicit

Public e As Engine3D                  ' the 3D engine
Public camX As Long, camZ As Long     ' the camera's position on the floor, in world units
Public camYaw As Long                 ' the way it faces: 0..65535 is a full turn

Const CAMY = 90                       ' the camera's height above the floor
Const FLOORN = 17                     ' the floor: 17 x 17 points = 16 x 16 tiles ...
Const TILE = 64                       ' ... of 64 x 64 units

' pens (the engine's colours, by number)
Const PEN_SKY = 1, PEN_TILE1 = 2, PEN_TILE2 = 3
Const PEN_RED = 4, PEN_REDDARK = 5, PEN_BLUE = 6, PEN_BLUEDARK = 7
Const PEN_GOLD = 8, PEN_GOLDDARK = 9, PEN_WHITE = 10

Private cube As Long, pyramid As Long, tower As Long
Private floorGrid As Long

Public Sub WorldInit(cv As Canvas)
    Dim i As Long, j As Long

    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv                                       ' draw into this canvas
    ' the 3D area: the whole canvas, centred, with a field of view of 200
    e.View cv.Width, cv.Height, cv.Width \ 2, cv.Height \ 2, 200

    ' the palette: pen number -> colour (pen 0 stays black)
    e.Pen(PEN_TILE1) = RGB(70, 90, 70): e.Pen(PEN_TILE2) = RGB(200, 210, 190)
    e.Pen(PEN_RED) = RGB(230, 60, 50): e.Pen(PEN_REDDARK) = RGB(130, 30, 25)
    e.Pen(PEN_BLUE) = RGB(70, 120, 240): e.Pen(PEN_BLUEDARK) = RGB(35, 60, 130)
    e.Pen(PEN_GOLD) = RGB(250, 200, 60): e.Pen(PEN_GOLDDARK) = RGB(150, 110, 20)
    e.Pen(PEN_WHITE) = RGB(255, 255, 255)
    e.SkyGradient PEN_SKY, RGB(30, 50, 120), RGB(170, 190, 230), cv.Height \ 2
    e.Light -1, 3, -2, 80                             ' light from the upper left, behind us
    e.Fog RGB(170, 190, 230), 900, 1600              ' far things fade into the sky colour

    ' the models: built once from boxes, pyramids and prisms
    cube = e.ModelNew()
    e.MdlBox cube, PEN_RED, PEN_REDDARK, -30, 30, 0, 60, -30, 30
    pyramid = e.ModelNew()
    e.MdlPyramid pyramid, PEN_GOLD, PEN_GOLDDARK, -35, 35, 0, -35, 35, 70
    tower = e.ModelNew()
    e.MdlPrism tower, PEN_BLUE, PEN_BLUEDARK, 6, 25, 0, 100
    e.MdlPyramid tower, PEN_RED, PEN_REDDARK, -25, 25, 100, -25, 25, 140

    ' the floor: a flat height grid, its corner at (-512, -512), tiles in two colours
    floorGrid = e.GridNew(FLOORN, FLOORN, TILE, -(FLOORN \ 2) * TILE, -(FLOORN \ 2) * TILE)
    For j = 0 To FLOORN - 2
        For i = 0 To FLOORN - 2
            If (i + j) Mod 2 = 0 Then e.GridPenSet floorGrid, i, j, PEN_TILE1 Else e.GridPenSet floorGrid, i, j, PEN_TILE2
        Next i
    Next j
    e.GridShade floorGrid, False                      ' plain colours, no slope shading

    ' the camera starts south of the middle, looking north (+z)
    camX = 0: camZ = -400: camYaw = 0
End Sub

' Move the camera: turn by dYaw, and walk forward (or back, when negative) by dist units.
Public Sub WorldMove(ByVal dYaw As Long, ByVal dist As Long)
    camYaw = (camYaw + dYaw) And 65535
    ' the direction the camera faces is (Sin, Cos) of its angle; e.Sin gives 16.16 values
    camX = camX + dist * e.Sin(camYaw) \ 65536
    camZ = camZ + dist * e.Cos(camYaw) \ 65536
    ' stay on the floor
    If camX < -480 Then camX = -480
    If camX > 480 Then camX = 480
    If camZ < -480 Then camZ = -480
    If camZ > 480 Then camZ = 480
End Sub

' Draw frame t (the models' angles come from t) into the canvas. The caller shows it.
Public Sub WorldFrame(ByVal t As Long)
    e.CamPos camX, CAMY, camZ
    e.CamAngles camYaw, 1200                          ' yaw, and a slight look down (pitch)
    e.Clear PEN_SKY                                   ' the sky
    e.Begin 3000                                      ' start the list of things to draw
    e.Shading = 0
    e.DrawGrid floorGrid                              ' the floor
    e.Shading = 1                                     ' the models: lit by the light
    e.DrawModel cube, -150, 0, 0, t * 300             ' spinning about the up axis (yaw)
    e.DrawModel pyramid, 150, 0, 0, -t * 200
    e.DrawModel tower, 0, 0, 250, t * 100
    e.DrawModel cube, 0, 180 + e.Sin(t * 500) \ 2048, 250, t * 700, t * 400   ' floating, tumbling
    e.Flush                                           ' draw the list, far to near
    e.TextShadow 4, 4, "CURSOR KEYS: MOVE   ESC: QUIT", PEN_WHITE
    e.TextShadow 4, 244, e.NPolys & " POLYGONS", PEN_WHITE
End Sub
