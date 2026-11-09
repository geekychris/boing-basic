' ScDraw - ScAIry Fun's picture (amiga_mcp's examples/scairy_fun/render.c and models.c): the road
' as 8 m segments drawn far to near, each a cross-section of 8 points (the scenery each side,
' the shoulders, the road), its lines, rails, the autopilot's planned path, cones, scenery and
' whatever is on it; the painted dusk all the way round (or the route's skyline), the low sun;
' the autopilot's boxes, the cockpit, the messages, the HUD with the autopilot's view from
' above; the title, the help pages and the software update. 320 x 256, the 3D in 320 x 212.
'
' render.c fills its own polygons in painter's order by segment. Here each segment is one
' Engine3D pass (Begin, its quads in one QuadsW call, its models, Flush), so the order is the
' same: a segment's strips first, then what stands on it, then the next nearer segment.
Option Explicit

' pens (models.h)
Public Const PEN_BLACK As Long = 0
Public Const PEN_WHITE As Long = 1
Public Const PEN_PANEL As Long = 2
Public Const PEN_GREY As Long = 3
Public Const PEN_SKY As Long = 4
Public Const PEN_HAZE As Long = 5
Public Const PEN_WATER As Long = 6
Public Const PEN_ROAD As Long = 8
Public Const PEN_PAVE As Long = 10
Public Const PEN_GRASS As Long = 11
Public Const PEN_DIRT As Long = 13
Public Const PEN_ROCK As Long = 15
Public Const PEN_RED As Long = 16
Public Const PEN_YELLOW As Long = 18
Public Const PEN_ORANGE As Long = 19
Public Const PEN_AI As Long = 20
Public Const PEN_AI2 As Long = 21
Public Const PEN_BLUE As Long = 22
Public Const PEN_CARW As Long = 24
Public Const PEN_KHAKI As Long = 26
Public Const PEN_TREE As Long = 27
Public Const PEN_GLASS As Long = 28
Public Const PEN_BROWN As Long = 29
Public Const PEN_SHADOW As Long = 31

Public Const VIEW_W As Long = 320
Public Const VIEW_H As Long = 212
Public Const VIEW_CX As Long = 160
Public Const VIEW_CY As Long = 100
Public Const FOV As Long = 180
Public Const FAR_Z As Long = 4200
Public Const HELP_PAGES As Long = 3

Private Const CAM_BACK As Long = 230
Private Const CAM_UP As Long = 92
Private Const CHASE_PITCH As Long = 1150
Private Const COCKPIT_PITCH As Long = 260
Private Const LINE_SEGS As Long = 24
Private Const SCENE_SEGS As Long = 30
Private Const NVIS_MAX As Long = 48

' models
Private Const MDL_CAR As Long = 0, MDL_TRUCK As Long = 1, MDL_TRACTOR As Long = 2, MDL_CYCLIST As Long = 3, MDL_DEER As Long = 4
Private Const MDL_CONE As Long = 5, MDL_TYRE As Long = 6, MDL_ROCK As Long = 7, MDL_AMBULANCE As Long = 8, MDL_GOAT As Long = 9
Private Const MDL_PED As Long = 10, MDL_TREE As Long = 11, MDL_PINE As Long = 12, MDL_POLE As Long = 13, MDL_HOUSE As Long = 14
Private Const MDL_BLOCK As Long = 15, MDL_OVERPASS As Long = 16, MDL_GANTRY As Long = 17, MDL_BOULDER As Long = 18, MDL_LAMP As Long = 19
Private Const MAT_BODY As Long = 0, MAT_GLASS As Long = 1, MAT_DARK As Long = 2, MAT_WHITE As Long = 3, MAT_BROWN As Long = 4
Private Const MAT_TREE As Long = 5, MAT_ORANGE As Long = 6, MAT_CONCRETE As Long = 7, MAT_RED As Long = 8, MAT_FLASH As Long = 9
Private Const MAT_YELLOW As Long = 10, MAT_ROCK As Long = 11, MAT_SKIN As Long = 12

Public e3 As Object
Public showPerf As Boolean
Public polyTotal As Double
Public renderDrawDist As Long

Private mdl(0 To 19) As Long, curM As Long, partX As Long, partY As Long, partZ As Long
Private matLit(0 To 12) As Long, matShade(0 To 12) As Long
Private mvx(0 To 47) As Long, mvy(0 To 47) As Long, mvz(0 To 47) As Long, mnv As Long
Private bodyLit(0 To 5) As Long, bodyShade(0 To 5) As Long
Private objHeight(0 To 10) As Long, mdlOf(0 To 10) As Long
Private sideProf(0 To 31) As Long          ' side * 4: out, dy of the middle and far points
Private routePal(0 To 3) As Variant, routeSky(0 To 7) As Long
Private palRoute As Long, palGlare As Long

' this frame's camera
Private camX As Long, camY As Long, camZ As Long, camYaw As Long, camPitch As Long
Private camD As Long, camYawS As Long, chaseView As Long
Private horizonY As Long, vanishX As Long, groundL As Long, groundR As Long
Private sunYaw As Long, sunRoute As Long
Private skyline(0 To 3, 0 To 63) As Long, skylinesMade As Boolean
Private panorama As Long, titleImg As Long, artTried As Boolean
Public dataDir As String

' the segments' strips for QuadsW, cached: slot (segment And 63) holds up to 40 quads, built
' when the segment first shows (again every 8 frames where water moves): the strips and road
' (n1), the lines (n2), the rails (n3)
Private Const CAPQ As Long = 40
Private co(0 To 30719) As Long, cp(0 To 2559) As Long, nq As Long, qBase As Long
Private slotSeg(0 To 63) As Long, slotKey(0 To 63) As Long, slotN1(0 To 63) As Long, slotN2(0 To 63) As Long, slotN3(0 To 63) As Long
Private slotRoute As Long
Private cy4 As Long, sy4 As Long, cp4 As Long, sp4 As Long
Private curD As Long
' each slot's scenery (side 0, 1): model (-1 none), position, yaw
Private scM(0 To 127) As Long, scX(0 To 127) As Long, scY(0 To 127) As Long, scZ(0 To 127) As Long, scYaw(0 To 127) As Long
' the AI view's dotted lines, made again when the route or the palette changes
Private aiXs(0 To 799) As Long, aiYs(0 To 799) As Long, aiCs(0 To 799) As Long, aiN As Long, aiKey As Long
Private off(0 To 7) As Long, dyv(0 To 7) As Long
Private ax(0 To 7) As Long, ay(0 To 7) As Long, az(0 To 7) As Long, bx(0 To 7) As Long, by(0 To 7) As Long, bz(0 To 7) As Long
' objects drawn with each segment: per-segment lists, far to near
Private segFirst(0 To 49) As Long, objNext(0 To 40) As Long
Private px(0 To 7) As Long, py(0 To 7) As Long
Private helpTitle(1 To 3) As String, helpText(1 To 3, 0 To 11) As String, patchNotes(0 To 3, 0 To 3) As String

Public Sub DrawInit(cv As Object)
    Dim v As Variant, i As Long
    ScInit
    Set e3 = CreateObject("Boing.Engine3D")
    e3.Attach cv
    e3.View VIEW_W, VIEW_H, VIEW_CX, VIEW_CY, FOV
    renderDrawDist = 32
    palRoute = -1: palGlare = -1: sunRoute = -1: chaseView = -1: aiKey = -1
    routePal(0) = Array(&H0, &HFFF, &H333, &H999, &H8BF, &H9AB, &H357, &H469, &H444, &H555, &H998, &H4A3, &H5B4, &H763, &H874, &H776, _
                        &HE22, &H811, &HFE2, &HF72, &H2EF, &H3F5, &H36D, &H128, &HEEE, &HAAB, &H774, &H263, &H124, &H642, &HB85, &H111)
    routePal(1) = Array(&H0, &HFFF, &H333, &H999, &HABC, &HAAA, &H467, &H578, &H555, &H666, &H999, &H6A4, &H7B5, &H875, &H986, &H887, _
                        &HE22, &H811, &HFE2, &HF72, &H2EF, &H3F5, &H36D, &H128, &HEEE, &HAAB, &H774, &H373, &H124, &H642, &HB85, &H111)
    routePal(2) = Array(&H0, &HFFF, &H333, &H999, &HF96, &H869, &H358, &H469, &H434, &H545, &H987, &H574, &H685, &H653, &H764, &H766, _
                        &HE22, &H811, &HFE2, &HF72, &H2EF, &H3F5, &H36D, &H128, &HEEE, &HAAB, &H774, &H243, &H124, &H642, &HB85, &H111)
    routePal(3) = Array(&H0, &HFFF, &H333, &H999, &H99A, &H778, &H456, &H567, &H333, &H444, &H888, &H585, &H696, &H665, &H776, &H666, _
                        &HE22, &H811, &HFE2, &HF72, &H2EF, &H3F5, &H36D, &H128, &HEEE, &HAAB, &H774, &H353, &H124, &H642, &HB85, &H111)
    v = Array(&H36C, &HBDF, &H79B, &HDDC, &H448, &HFA5, &H667, &HBBB)
    For i = 0 To 7: routeSky(i) = v(i): Next i
    v = Array(PEN_BLUE, PEN_CARW, PEN_YELLOW, PEN_KHAKI, PEN_RED, PEN_GREY)
    For i = 0 To 5: bodyLit(i) = v(i): Next i
    v = Array(PEN_BLUE + 1, PEN_CARW + 1, PEN_ORANGE, PEN_BROWN, PEN_RED + 1, PEN_PANEL)
    For i = 0 To 5: bodyShade(i) = v(i): Next i
    v = Array(0, 21, 58, 42, 32, 36, 13, 13, 49, 23, 31)
    For i = 0 To 10: objHeight(i) = v(i): Next i
    v = Array(0, MDL_CAR, MDL_TRUCK, MDL_TRACTOR, MDL_CYCLIST, MDL_DEER, MDL_CONE, MDL_TYRE, MDL_AMBULANCE, MDL_GOAT, MDL_PED)
    For i = 0 To 10: mdlOf(i) = v(i): Next i
    ' side profiles: (out, dy) of the middle and far points beyond the shoulder
    v = Array(200, -2, 1600, -8, 150, -LEVEE_H, 2000, -LEVEE_H, 220, -200, 1600, -210, 30, 180, 700, 260, _
              50, -500, 1800, -520, 40, 0, 1600, -4, 70, 3, 1600, 3, 42, -60, 1800, -60)
    For i = 0 To 31: sideProf(i) = v(i): Next i
    BuildModels
    v = Array("HOW TO PLAY", "CONTROLS", "READING THE AI")
    For i = 1 To 3: helpTitle(i) = v(i - 1): Next i
    v = Array("YOUR CAR DRIVES ITSELF. YOU SCORE", "FOR EVERY METRE IT DRIVES ON AUTOPILOT,", _
              "x THE MULTIPLIER: +1 EVERY 8 SECONDS", "THE AUTOPILOT STAYS ON, UP TO x8.", "", _
              "BUT IT HAS BLIND SPOTS. TAKE THE WHEEL", "JUST BEFORE IT GETS SOMETHING WRONG,", _
              "GET THROUGH, THEN HAND IT BACK.", "", "GOOD CATCH: YOU TOOK OVER IN TIME +500", _
              "NEEDLESS: IT HAD THAT. MULTIPLIER x1.", "", _
              "LEFT / RIGHT   STEER (TAKES OVER)", "DOWN           BRAKE (TAKES OVER)", "UP             ACCELERATE (MANUAL)", _
              "FIRE / SPACE   AUTOPILOT ON / OFF", "               (ONLY NEAR A LANE", "               CENTRE)", _
              "V / C          CHASE / COCKPIT VIEW", "P              PAUSE", "HELP / H       THESE PAGES", _
              "ESC            TITLE / QUIT", "M / S          MUSIC / EFFECTS", "", _
              "CYAN RIBBON    WHERE IT MEANS TO GO", "GREEN BOXES    WHAT IT HAS SEEN", "RED BOX ?      SOMETHING IT IMAGINES", _
              "BOTTOM RIGHT   ITS VIEW FROM ABOVE", "", "THERE ARE NO WARNINGS. WATCH THE ROAD:", _
              "FLOOD WATER, OLD LANE LINES, OVERPASS", "SHADOWS, CONES, THE LOW SUN, SIRENS,", _
              "DEBRIS. CRASHES COST INSURANCE COVER;", "AT ZERO YOUR POLICY IS CANCELLED.", _
              "EACH DESTINATION ADDS COVER AND A", "BONUS FOR AUTOPILOT USE.")
    For i = 0 To 35: helpText(i \ 12 + 1, i Mod 12) = v(i): Next i
    v = Array("", "", "", "", _
              "+ NOW DETECTS WATER", "+ IMPROVED LANE CONFIDENCE", "- REMOVED FEAR OF TRACTORS", "KNOWN ISSUE: SHADOWS LOOK SOLID", _
              "+ PHANTOM BRAKING FIXED (MOSTLY)", "+ MOUNTAIN MODE", "+ SUNGLASSES (BETA)", "KNOWN ISSUE: SUNSETS", _
              "+ CONFIDENCE INCREASED 400%", "+ CITY DRIVING", "- REMOVED SELF-DOUBT", "KNOWN ISSUE: EVERYTHING")
    For i = 0 To 15: patchNotes(i \ 4, i Mod 4) = v(i): Next i
End Sub

' ---------- the colours ----------

Private Function Mix12(ByVal c As Long, ByVal tgt As Long, ByVal num As Long, ByVal den As Long) As Long
    Dim r As Long, g As Long, b As Long
    r = (c \ 256) And 15: g = (c \ 16) And 15: b = c And 15
    r = r + ((((tgt \ 256) And 15) - r) * num) \ den
    g = g + ((((tgt \ 16) And 15) - g) * num) \ den
    b = b + (((tgt And 15) - b) * num) \ den
    Mix12 = r * 256 + g * 16 + b
End Function

' the route's colours; the low sun washes everything towards white
Private Sub ScPalette()
    Dim pal(0 To 31) As Long, i As Long, p As Variant
    p = routePal(wRoute)
    For i = 0 To 31
        pal(i) = p(i)
        If wGlare > 0 And i >= 2 Then pal(i) = Mix12(pal(i), &HFFE, wGlare * 10, 256)
    Next i
    GfxPalette pal
    e3.Palette12 pal
    e3.SkyGradient PEN_SKY, Rgb12(routeSky(wRoute * 2)), Rgb12(routeSky(wRoute * 2 + 1)), HorizonFor(wView)
    palRoute = wRoute: palGlare = wGlare
End Sub

' the screens drawn without the road (the title painting, help, the update) need the pens too
Private Sub PalCheck()
    If wRoute <> palRoute Or wGlare <> palGlare Then ScPalette
End Sub

' ---------- the models (models.c) ----------

Private Function MV(ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    mvx(mnv) = x: mvy(mnv) = y: mvz(mnv) = z
    MV = e3.MdlVtx(curM, x, y, z)
    mnv = mnv + 1
End Function

' a face, flipped if it faces the part's interior, its shade from a fixed sun (-1, 2, 1)
Private Sub MFace(ByVal mat As Long, ByVal n As Long, ByVal a As Long, ByVal b As Long, ByVal c As Long, ByVal d As Long)
    Dim ux As Long, uy As Long, uz As Long, wx As Long, wy As Long, wz As Long, nx As Long, ny As Long, nz As Long
    Dim outv As Double, light As Long, mag As Long, p As Long
    ux = mvx(b) - mvx(a): uy = mvy(b) - mvy(a): uz = mvz(b) - mvz(a)
    wx = mvx(c) - mvx(a): wy = mvy(c) - mvy(a): wz = mvz(c) - mvz(a)
    nx = uy * wz - uz * wy: ny = uz * wx - ux * wz: nz = ux * wy - uy * wx
    outv = CDbl(nx) * (mvx(a) - partX) + CDbl(ny) * (mvy(a) - partY) + CDbl(nz) * (mvz(a) - partZ)
    If outv < 0 Then
        nx = -nx: ny = -ny: nz = -nz
    End If
    light = -nx + 2 * ny + nz
    mag = Abs(nx) + Abs(ny) + Abs(nz)
    If mag <> 0 And light * 4 > mag * 3 Then p = matLit(mat) Else p = matShade(mat)
    ' (the engine flips it away from the interior point the same way)
    e3.MdlFace curM, p, p, n, a, b, c, d, partX, partY, partZ
End Sub

Private Sub MBox(ByVal mat As Long, ByVal x0 As Long, ByVal x1 As Long, ByVal y0 As Long, ByVal y1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    Dim b As Long
    partX = (x0 + x1) \ 2: partY = (y0 + y1) \ 2: partZ = (z0 + z1) \ 2
    b = MV(x0, y0, z0): MV x1, y0, z0: MV x1, y1, z0: MV x0, y1, z0
    MV x0, y0, z1: MV x1, y0, z1: MV x1, y1, z1: MV x0, y1, z1
    MFace mat, 4, b + 0, b + 3, b + 2, b + 1         ' back (-z)
    MFace mat, 4, b + 5, b + 6, b + 7, b + 4         ' front (+z)
    MFace mat, 4, b + 4, b + 7, b + 3, b + 0         ' left
    MFace mat, 4, b + 1, b + 2, b + 6, b + 5         ' right
    MFace mat, 4, b + 3, b + 7, b + 6, b + 2         ' top
End Sub

' a square pyramid on the rectangle (x0..x1, z0..z1) at height y0
Private Sub MPyramid(ByVal mat As Long, ByVal x0 As Long, ByVal x1 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal z1 As Long, ByVal apex As Long)
    Dim b As Long, t As Long
    partX = (x0 + x1) \ 2: partY = y0 + (apex - y0) \ 4: partZ = (z0 + z1) \ 2
    b = MV(x0, y0, z0): MV x1, y0, z0: MV x1, y0, z1: MV x0, y0, z1
    t = MV((x0 + x1) \ 2, apex, (z0 + z1) \ 2)
    MFace mat, 3, b + 0, b + 1, t, 0
    MFace mat, 3, b + 1, b + 2, t, 0
    MFace mat, 3, b + 2, b + 3, t, 0
    MFace mat, 3, b + 3, b + 0, t, 0
End Sub

' a flat dark rectangle on the ground under a vehicle (y 1: drawn first)
Private Sub MShadow(ByVal x0 As Long, ByVal x1 As Long, ByVal z0 As Long, ByVal z1 As Long)
    Dim b As Long
    partX = 0: partY = -10: partZ = 0
    b = MV(x0, 1, z0): MV x1, 1, z0: MV x1, 1, z1: MV x0, 1, z1
    MFace MAT_DARK, 4, b + 0, b + 1, b + 2, b + 3
End Sub

Private Sub MBegin(ByVal id As Long)
    curM = e3.ModelNew()
    mdl(id) = curM
    mnv = 0
End Sub

Private Sub BuildModels()
    Dim v As Variant, i As Long
    v = Array(200, PEN_GLASS, PEN_SHADOW, PEN_CARW, PEN_BROWN + 1, PEN_TREE, PEN_ORANGE, PEN_GREY, PEN_RED, 210, PEN_YELLOW, PEN_ROCK, PEN_BROWN + 1)
    For i = 0 To 12: matLit(i) = v(i): Next i
    v = Array(201, PEN_GLASS, PEN_SHADOW, PEN_CARW + 1, PEN_BROWN, PEN_TREE, PEN_ORANGE, PEN_PANEL, PEN_RED + 1, 210, PEN_ORANGE, PEN_DIRT, PEN_BROWN + 1)
    For i = 0 To 12: matShade(i) = v(i): Next i
    MBegin MDL_CAR
    MShadow -16, 16, -38, 38
    MBox MAT_BODY, -14, 14, 3, 11, -36, 36
    MBox MAT_GLASS, -12, 12, 11, 19, -15, 12
    MBox MAT_BODY, -12, 12, 19, 21, -13, 10
    MBegin MDL_TRUCK
    MShadow -21, 21, -92, 92
    MBox MAT_WHITE, -20, 20, 5, 58, -90, 50
    MBox MAT_BODY, -19, 19, 3, 44, 54, 90
    MBox MAT_GLASS, -17, 17, 30, 42, 88, 91
    MBegin MDL_TRACTOR
    MBox MAT_RED, -9, 9, 8, 22, -4, 30
    MBox MAT_GLASS, -10, 10, 22, 42, -26, -4
    MBox MAT_DARK, -17, -10, 0, 26, -28, -6
    MBox MAT_DARK, 10, 17, 0, 26, -28, -6
    MBegin MDL_CYCLIST
    MBox MAT_DARK, -1, 1, 1, 13, -14, 14
    MBox MAT_YELLOW, -4, 4, 13, 26, -5, 4
    MBox MAT_SKIN, -3, 3, 26, 32, -3, 3
    MBegin MDL_DEER
    MBox MAT_BROWN, -3, 3, 0, 14, -11, 11
    MBox MAT_BROWN, -5, 5, 14, 24, -14, 14
    MBox MAT_BROWN, -3, 3, 22, 36, 10, 18
    MBegin MDL_GOAT
    MBox MAT_WHITE, -2, 2, 0, 9, -7, 7
    MBox MAT_WHITE, -4, 4, 9, 17, -9, 9
    MBox MAT_WHITE, -2, 2, 15, 23, 7, 12
    MBegin MDL_PED
    MBox MAT_DARK, -3, 3, 0, 14, -2, 2
    MBox MAT_BODY, -4, 4, 14, 26, -3, 3
    MBox MAT_SKIN, -2, 2, 26, 31, -2, 2
    MBegin MDL_CONE
    MPyramid MAT_ORANGE, -5, 5, 0, -5, 5, 13
    MBegin MDL_TYRE
    MBox MAT_DARK, -10, 10, 0, 7, -9, 9
    MBegin MDL_ROCK
    MPyramid MAT_ROCK, -11, 11, 0, -9, 9, 13
    MBegin MDL_AMBULANCE
    MShadow -18, 18, -52, 52
    MBox MAT_WHITE, -17, 17, 3, 44, -50, 28
    MBox MAT_WHITE, -16, 16, 3, 28, 28, 50
    MBox MAT_GLASS, -14, 14, 18, 27, 49, 51
    MBox MAT_RED, -18, 18, 20, 26, -51, 28
    MBox MAT_FLASH, -10, 10, 44, 49, 20, 27
    MBegin MDL_TREE
    MBox MAT_BROWN, -3, 3, 0, 30, -3, 3
    MPyramid MAT_TREE, -28, 28, 28, -28, 28, 110
    MBegin MDL_PINE
    MBox MAT_BROWN, -3, 3, 0, 16, -3, 3
    MPyramid MAT_TREE, -20, 20, 14, -20, 20, 140
    MBegin MDL_POLE
    MBox MAT_BROWN, -2, 2, 0, 150, -2, 2
    MBox MAT_BROWN, -22, 22, 136, 140, -2, 2
    MBegin MDL_HOUSE
    MBox MAT_WHITE, -50, 50, 0, 80, -50, 50
    MPyramid MAT_RED, -56, 56, 80, -56, 56, 136
    MBegin MDL_BLOCK
    MBox MAT_CONCRETE, -56, 56, 0, 180, -56, 56
    MBox MAT_GLASS, -50, 50, 180, 230, -50, 50       ' a glass top storey
    MBegin MDL_OVERPASS
    MBox MAT_CONCRETE, -150, -128, 0, 104, -10, 10
    MBox MAT_CONCRETE, 128, 150, 0, 104, -10, 10
    MBox MAT_CONCRETE, -170, 170, 104, 128, -26, 26
    MBegin MDL_GANTRY
    MBox MAT_YELLOW, -150, -140, 0, 130, -4, 4
    MBox MAT_YELLOW, 140, 150, 0, 130, -4, 4
    MBox MAT_RED, -150, 150, 104, 134, -3, 3
    MBegin MDL_BOULDER
    MPyramid MAT_ROCK, -44, 44, 0, -40, 40, 66
    MBegin MDL_LAMP
    MBox MAT_CONCRETE, -2, 2, 0, 150, -2, 2
    MBox MAT_CONCRETE, -34, 2, 146, 150, -2, 2
End Sub

' ---------- the camera ----------

Private Function CarYawOff() As Long
    Dim v As Long
    If carV > 8 Then v = carV Else v = 8
    CarYawOff = A3AtanRatio(carLat, v)
End Function

Public Function HorizonFor(ByVal view As Long) As Long
    Dim p As Long
    If view = CAM_COCKPIT Then p = COCKPIT_PITCH Else p = CHASE_PITCH
    HorizonFor = VIEW_CY - (FOV * (A3Sin(p) \ 16)) \ (A3Cos(p) \ 16)
End Function

Private Sub CameraFollow()
    Dim z As Long, y0 As Long, y1 As Long, target As Long, d As Long
    If wView = CAM_COCKPIT Then
        z = carZ + 4 * 16
        camX = RoadCx(z) + ShrA(carD, FBITS)
        camZ = ShrA(z, FBITS)
        camY = RoadY(z) + 17
        camYaw = (RoadDir(carZ) + CarYawOff()) And &HFFFF&
        camPitch = COCKPIT_PITCH
        chaseView = CAM_COCKPIT
    Else
        z = carZ - CAM_BACK * 16
        If z < 0 Then z = 0
        If chaseView <> CAM_CHASE Then
            camD = carD: camYawS = RoadDir(carZ)
        End If
        camD = camD + (carD - camD) \ 4
        target = RoadDir(carZ) + CarYawOff() \ 3
        d = ((target - camYawS + 32768) And &HFFFF&) - 32768
        camYawS = camYawS + d \ 3
        camX = RoadCx(z) + ShrA(camD, FBITS)
        camZ = ShrA(z, FBITS)
        y0 = RoadY(z): y1 = RoadY(carZ)
        If y0 > y1 Then camY = y0 + CAM_UP Else camY = y1 + CAM_UP
        camYaw = camYawS And &HFFFF&
        camPitch = CHASE_PITCH
        chaseView = CAM_CHASE
    End If
    e3.CamPos camX, camY, camZ
    e3.CamAngles camYaw, camPitch
End Sub

' ---------- the road ----------

Private Sub Profile(ByVal i As Long)
    Dim L As Long, R As Long
    L = sgSideL(i) * 4: R = sgSideR(i) * 4
    off(3) = RoadLeft(): dyv(3) = 0
    off(4) = RoadRight(): dyv(4) = 0
    off(2) = off(3) - SHOULDER: dyv(2) = 0
    off(5) = off(4) + SHOULDER: dyv(5) = 0
    off(1) = off(2) - sideProf(L): dyv(1) = sideProf(L + 1)
    off(0) = off(2) - sideProf(L + 2): dyv(0) = sideProf(L + 3)
    off(6) = off(5) + sideProf(R): dyv(6) = sideProf(R + 1)
    off(7) = off(5) + sideProf(R + 2): dyv(7) = sideProf(R + 3)
End Sub

Private Sub AddQuad(ByVal x0 As Long, ByVal y0 As Long, ByVal z0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal z1 As Long, _
                    ByVal x2 As Long, ByVal y2 As Long, ByVal z2 As Long, ByVal x3 As Long, ByVal y3 As Long, ByVal z3 As Long, ByVal p As Long)
    Dim i As Long
    If nq >= CAPQ Then Exit Sub
    i = (qBase + nq) * 12
    co(i) = x0: co(i + 1) = y0: co(i + 2) = z0: co(i + 3) = x1: co(i + 4) = y1: co(i + 5) = z1
    co(i + 6) = x2: co(i + 7) = y2: co(i + 8) = z2: co(i + 9) = x3: co(i + 10) = y3: co(i + 11) = z3
    cp(qBase + nq) = p
    nq = nq + 1
End Sub

Private Sub Strip(ByVal k0 As Long, ByVal k1 As Long, ByVal p As Long)
    AddQuad ax(k0), ay(k0), az(k0), ax(k1), ay(k1), az(k1), bx(k1), by(k1), bz(k1), bx(k0), by(k0), bz(k0), p
End Sub

' a flat band on the road from x0 to x1 (units from the centre line)
Private Sub Band(ByVal i As Long, ByVal x0a As Long, ByVal x1a As Long, ByVal x0b As Long, ByVal x1b As Long, ByVal lift As Long, ByVal p As Long)
    Dim za As Long, zb As Long
    za = i * SEG_LEN: zb = za + SEG_LEN
    AddQuad sgCx(i) + x0a, sgY(i) + lift, za, sgCx(i) + x1a, sgY(i) + lift, za, _
            sgCx(i + 1) + x1b, sgY(i + 1) + lift, zb, sgCx(i + 1) + x0b, sgY(i + 1) + lift, zb, p
End Sub

Private Sub LineAt(ByVal i As Long, ByVal x As Long, ByVal p As Long)
    Band i, x - 2, x + 2, x - 2, x + 2, 0, p
End Sub

' a vertical band along the segment (guardrail, barrier)
Private Sub Wall(ByVal i As Long, ByVal x As Long, ByVal y0 As Long, ByVal y1 As Long, ByVal p As Long)
    Dim za As Long, zb As Long
    za = i * SEG_LEN: zb = za + SEG_LEN
    AddQuad sgCx(i) + x, sgY(i) + y0, za, sgCx(i) + x, sgY(i) + y1, za, sgCx(i + 1) + x, sgY(i + 1) + y1, zb, sgCx(i + 1) + x, sgY(i + 1) + y0, zb, p
End Sub

Private Function FarPen(ByVal side As Long) As Long
    Select Case side
        Case SIDE_LEVEE, SIDE_CANAL: FarPen = PEN_WATER
        Case SIDE_CLIFF: FarPen = PEN_HAZE
        Case SIDE_TOWN: FarPen = PEN_PAVE
        Case SIDE_DROP: FarPen = PEN_GRASS + 1
        Case Else: FarPen = PEN_GRASS
    End Select
End Function

Private Sub SideStrips(ByVal i As Long, ByVal side As Long)
    Dim t As Long, alt As Long, alt2 As Long, inner As Long, outer As Long, ko As Long, ki As Long
    If side <> 0 Then t = sgSideR(i) Else t = sgSideL(i)
    alt = i And 1
    alt2 = ((i \ 2) + (wFrame \ 16)) And 1
    If side <> 0 Then
        ko = 6: ki = 5
    Else
        ko = 0: ki = 1
    End If
    Select Case t
        Case SIDE_LEVEE: inner = PEN_GRASS + alt: outer = PEN_WATER + alt2
        Case SIDE_DROP: inner = PEN_DIRT + alt: outer = PEN_GRASS + 1
        Case SIDE_WALL: inner = IIf(alt <> 0, PEN_ROCK, PEN_DIRT): outer = PEN_GRASS
        Case SIDE_CLIFF: inner = IIf(alt <> 0, PEN_ROCK, PEN_DIRT): outer = PEN_HAZE
        Case SIDE_TOWN: inner = PEN_PAVE: outer = PEN_PAVE
        Case SIDE_CANAL: inner = PEN_ROCK: outer = PEN_WATER + alt2
        Case Else: inner = PEN_GRASS + alt: outer = PEN_GRASS
    End Select
    Strip ko, ko + 1, outer
    Strip ki, ki + 1, inner
End Sub

' every model on a segment sorts just in front of the segment's strips (curD) and behind the
' nearer segments: render.c's painter order (objects go with the segment their near end is in)
Private Sub AddModel(ByVal m As Long, ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal yaw As Long, ByVal body As Long, _
                     ByVal flash As Boolean, Optional ByVal unused As Long = 0)
    Dim fl As Long, bias As Long
    If flash Then fl = PEN_RED Else fl = PEN_BLUE
    bias = CamDepth(x, y, z) - (curD - 3)
    If body >= 0 Then
        e3.DrawModel mdl(m), x, y, z, yaw And &HFFFF&, 0, 0, bodyLit(body), bodyShade(body), fl, bias
    Else
        e3.DrawModel mdl(m), x, y, z, yaw And &HFFFF&, 0, 0, PEN_GREY, PEN_GREY, fl, bias
    End If
End Sub

' a point's camera space z (as the engine's transform, to 1 unit)
Private Function CamDepth(ByVal x As Long, ByVal y As Long, ByVal z As Long) As Long
    Dim t As Long, rz As Long
    t = (x - camX) * sy4 + (z - camZ) * cy4
    rz = (t - (t And 4095)) \ 4096
    t = rz * cp4 - (y - camY) * sp4
    CamDepth = (t - (t And 4095)) \ 4096
End Function

' scenery beside segment i, the same every time (hashed from i)
Private Sub Scenery(ByVal i As Long)
    Dim j As Long
    For j = (i And 63) * 2 To (i And 63) * 2 + 1
        If scM(j) >= 0 Then AddModel scM(j), scX(j), scY(j), scZ(j), scYaw(j), -1, False
    Next j
End Sub

' segment i's trees, poles, houses (render.c's add_scenery) into its slot
Private Sub BuildScenery(ByVal i As Long)
    Dim side As Long, j As Long, h As Long, t As Long, sgn As Long, m As Long, edgeX As Long, outv As Long, y As Long, z As Long, yaw As Long, zf As Long
    For side = 0 To 1
        h = A3Hash(i * 2 + side + wRoute * 977)
        If side <> 0 Then
            t = sgSideR(i): sgn = 1: edgeX = RoadRight() + SHOULDER
        Else
            t = sgSideL(i): sgn = -1: edgeX = RoadLeft() - SHOULDER
        End If
        m = -1: outv = 0: y = 0
        z = i * SEG_LEN + (ShrU(h, 8) And 63)
        yaw = h And &HFFFF&
        Select Case t
            Case SIDE_GRASS
                If UModL(h, 3) = 0 Then
                    m = MDL_TREE: outv = 90 + (ShrU(h, 12) And 511): y = -4
                End If
            Case SIDE_LEVEE
                If side = 1 And i Mod 6 = 0 Then
                    m = MDL_POLE: outv = 10: yaw = 0
                End If
            Case SIDE_DROP
                If UModL(h, 3) = 0 Then
                    m = MDL_TREE: outv = 240 + (ShrU(h, 12) And 511): y = -206
                ElseIf i Mod 6 = 3 Then
                    m = MDL_POLE: outv = 10: yaw = 0
                End If
            Case SIDE_WALL
                If UModL(h, 3) = 0 Then
                    m = MDL_PINE: outv = 60 + (ShrU(h, 12) And 255): y = 200
                ElseIf UModL(h, 7) = 1 Then
                    m = MDL_BOULDER: outv = 6: y = 0
                End If
            Case SIDE_CLIFF
                If UModL(h, 2) = 0 Then
                    m = MDL_PINE: outv = 200 + (ShrU(h, 12) And 1023): y = -515
                End If
            Case SIDE_MEDIAN
                If i Mod 4 = 0 Then
                    m = MDL_LAMP: outv = 14: yaw = 16384 * IIf(side <> 0, 1, 3) - 16384
                End If
            Case SIDE_TOWN
                If i Mod 2 = 0 Then
                    If (h And 4) <> 0 Then m = MDL_BLOCK Else m = MDL_HOUSE
                    outv = 120: y = 3: yaw = 0: z = i * SEG_LEN
                End If
        End Select
        j = (i And 63) * 2 + side
        scM(j) = m
        If m >= 0 Then
            zf = z * 16
            scX(j) = RoadCx(zf) + edgeX + sgn * outv: scY(j) = RoadY(zf) + y: scZ(j) = z: scYaw(j) = RoadDir(zf) + yaw
        End If
    Next side
End Sub

Private Function ObjZ(ByVal idx As Long) As Long
    If idx = MAX_OBJS Then ObjZ = carZ Else ObjZ = obZ(idx)
End Function

Private Sub SortObjects(ByVal s0 As Long, ByVal s1 As Long)
    Dim i As Long, s As Long, prv As Long, cur As Long, z As Long, ln As Long
    For i = 0 To s1 - s0 + 1: segFirst(i) = -1: Next i
    For i = 0 To MAX_OBJS
        If i < MAX_OBJS Then
            If obType(i) = OBJ_NONE Then GoTo nxt
        ElseIf wView = CAM_COCKPIT Then
            GoTo nxt
        End If
        z = ObjZ(i)
        ' draw it with the segment its near end (towards the camera) is in
        If i = MAX_OBJS Then ln = objLen(OBJ_CAR) Else ln = objLen(obType(i))
        s = SegOf(z - ln * 16) - s0
        If s >= 0 And s <= s1 - s0 Then
            ' insert, keeping the farthest first
            prv = -1
            cur = segFirst(s)
            Do While cur >= 0
                If ObjZ(cur) <= z Then Exit Do
                prv = cur: cur = objNext(cur)
            Loop
            objNext(i) = cur
            If prv < 0 Then segFirst(s) = i Else objNext(prv) = i
        End If
nxt:
    Next i
End Sub

Private Sub DrawObject(ByVal idx As Long)
    Dim z As Long, x As Long, y As Long, yaw As Long, m As Long
    If idx = MAX_OBJS Then
        z = carZ
        x = RoadCx(z) + ShrA(carD, FBITS)
        y = RoadY(z)
        If carState = CS_SPLASH Then
            y = y - (50 - carTimer) * 3
        ElseIf carState = CS_ROLL Then
            y = y - (50 - carTimer) * 6
        End If
        yaw = RoadDir(z) + CarYawOff()
        AddModel MDL_CAR, x, y, ShrA(z, FBITS), yaw, 4, False, objLen(OBJ_CAR)
        Exit Sub
    End If
    z = obZ(idx)
    x = RoadCx(z) + ShrA(obD(idx), FBITS)
    y = RoadY(z)
    yaw = RoadDir(z)
    If obV(idx) < 0 Then
        yaw = yaw + 32768
    ElseIf obVd(idx) < 0 And obV(idx) = 0 Then
        yaw = yaw - 16384                ' crossing to the left
    ElseIf obVd(idx) > 0 And obV(idx) = 0 Then
        yaw = yaw + 16384
    End If
    m = mdlOf(obType(idx))
    If obType(idx) = OBJ_DEBRIS And wRoute = 2 Then m = MDL_ROCK
    If (obFlags(idx) And OF_KNOCKED) <> 0 Then y = y - 4
    AddModel m, x, y, ShrA(z, FBITS), yaw, obColour(idx) And 3, ((wFrame \ 4) And 1) <> 0, objLen(obType(idx))
End Sub

' segment i's strips into its slot
Private Sub BuildSlot(ByVal i As Long, ByVal key As Long)
    Dim rl As Long, rr As Long, flood As Boolean, n As Long, roadPen As Long, shPen As Long, slot As Long
    Dim j As Long, za As Long, zb As Long, x As Long, ghost As Boolean, realPen As Long, g0 As Long, g1 As Long
    slot = i And 63
    qBase = slot * CAPQ
    nq = 0
    rl = RoadLeft(): rr = RoadRight()
    flood = (sgFlags(i) And SF_FLOOD) <> 0
    Profile i
    za = i * SEG_LEN: zb = za + SEG_LEN
    For j = 0 To 7
        ax(j) = sgCx(i) + off(j): ay(j) = sgY(i) + dyv(j): az(j) = za
        bx(j) = sgCx(i + 1) + off(j): by(j) = sgY(i + 1) + dyv(j): bz(j) = zb
    Next j
    SideStrips i, 0
    SideStrips i, 1
    If flood Then
        roadPen = PEN_WATER + (((i \ 2) + (wFrame \ 8)) And 1)
        shPen = roadPen
    ElseIf (sgFlags(i) And SF_OVERPASS) <> 0 Then
        roadPen = PEN_SHADOW: shPen = PEN_SHADOW          ' the shadow that fools it
    Else
        roadPen = PEN_ROAD + ((i \ 2) And 1)
        shPen = PEN_ROAD + 1
    End If
    Strip 2, 3, shPen
    Strip 4, 5, shPen
    Strip 3, 4, roadPen
    ' the finish line: a chequered band
    If (sgFlags(i) And SF_FINISH) <> 0 Then
        For x = rl To rr - 1 Step 16
            Band i, x, x + 8, x, x + 8, 0, IIf((((x \ 16) + i) And 1) <> 0, PEN_WHITE, PEN_BLACK)
        Next x
    End If
    slotN1(slot) = nq
    If Not flood Then
        ghost = (sgFlags(i) And SF_GHOST) <> 0
        If ghost Then realPen = PEN_ROAD + 1 Else realPen = PEN_WHITE      ' worn away where the old ones are
        If riNo(wRoute) <> 0 Then
            LineAt i, 0, IIf(ghost, PEN_ROAD + 1, PEN_YELLOW)
        Else
            LineAt i, rl + 4, PEN_YELLOW
        End If
        For n = 1 To riNl(wRoute) - 1
            If (i And 1) = 0 Then LineAt i, n * LANE_W, PEN_WHITE
        Next n
        For n = 1 To riNo(wRoute) - 1
            If (i And 1) = 0 Then LineAt i, -n * LANE_W, PEN_WHITE
        Next n
        LineAt i, rr - 3, realPen
        If riNo(wRoute) <> 0 Then LineAt i, rl + 3, PEN_WHITE
        If ghost Then
            ' the old lines: where the road used to go
            g0 = sgGhost(i)
            If (sgFlags(i + 1) And SF_GHOST) <> 0 Then g1 = sgGhost(i + 1) Else g1 = g0
            If (i And 1) = 0 Then
                Band i, g0 - 2, g0 + 2, g1 - 2, g1 + 2, 0, PEN_YELLOW
                Band i, rr - 5 + g0, rr - 1 + g0, rr - 5 + g1, rr - 1 + g1, 0, PEN_WHITE
            End If
        End If
    End If
    slotN2(slot) = nq - slotN1(slot)
    If (sgFlags(i) And SF_RAIL_L) <> 0 Then
        Wall i, off(2), 6, 12, PEN_GREY
        Wall i, off(2), 0, 6, PEN_PANEL
    End If
    If (sgFlags(i) And SF_RAIL_R) <> 0 Then
        Wall i, off(5), 6, 12, PEN_GREY
        Wall i, off(5), 0, 6, PEN_PANEL
    End If
    If sgSideL(i) = SIDE_MEDIAN Then Wall i, off(2) - 8, 0, 14, PEN_GREY
    slotN3(slot) = nq - slotN1(slot) - slotN2(slot)
    BuildScenery i
    slotSeg(slot) = i
    slotKey(slot) = key
End Sub

' where segment i's far edge lies from the camera (camera space z): its strips sort there
Private Function SegDepth(ByVal i As Long) As Long
    Dim t As Long
    t = CamDepth(sgCx(i + 1) + (RoadLeft() + RoadRight()) \ 2, sgY(i + 1), (i + 1) * SEG_LEN)
    If t < 4 Then t = 4
    If t > FAR_Z + 300 Then t = FAR_Z + 300
    SegDepth = t
End Function

Private Sub DrawSegment(ByVal i As Long, ByVal k As Long)
    Dim rl As Long, rr As Long, cur As Long, lane As Long, cd As Long, slot As Long, key As Long, d As Long, f As Long
    Dim p As Long, a As Long, b As Long, z As Long, hit As Boolean, za As Long, zb As Long
    rl = RoadLeft(): rr = RoadRight()
    slot = i And 63
    If sgSideL(i) = SIDE_LEVEE Or sgSideL(i) = SIDE_CANAL Or sgSideR(i) = SIDE_LEVEE Or sgSideR(i) = SIDE_CANAL Or _
       (sgFlags(i) And SF_FLOOD) <> 0 Then key = wFrame \ 8 Else key = -1
    If slotSeg(slot) <> i Or slotKey(slot) <> key Then BuildSlot i, key
    d = SegDepth(i)
    curD = d
    f = slot * CAPQ
    If k < LINE_SEGS Then
        e3.QuadsW slotN1(slot) + slotN2(slot) + slotN3(slot), d, cp, co, f
    Else
        e3.QuadsW slotN1(slot), d, cp, co, f
        If slotN3(slot) > 0 Then e3.QuadsW slotN3(slot), d, cp, co, f + slotN1(slot) + slotN2(slot)
    End If
    ' the autopilot's planned path
    If aiOn <> 0 And wState <> GS_GAMEOVER Then
        p = i - aiPlanFrom
        If p >= 0 And p < 12 And (aiBlinded = 0 Or (wFrame And 2) <> 0) Then
            a = ShrA(aiPlan(p), FBITS): b = ShrA(aiPlan(p + 1), FBITS)
            za = i * SEG_LEN: zb = za + SEG_LEN
            e3.QuadW d, IIf(aiBlinded <> 0, PEN_WHITE, PEN_AI), sgCx(i) + a - 3, sgY(i) + 1, za, sgCx(i) + a + 3, sgY(i) + 1, za, _
                     sgCx(i + 1) + b + 3, sgY(i + 1) + 1, zb, sgCx(i + 1) + b - 3, sgY(i + 1) + 1, zb
        End If
    End If
    ' cones: in the closed lane, and along its line
    If (sgFlags(i) And SF_CONES) <> 0 Then
        z = i * SEG_LEN
        lane = 0
        Do While lane < 8
            If (sgClosed(i) And (2 ^ lane)) <> 0 Then Exit Do
            lane = lane + 1
        Loop
        AddModel MDL_CONE, RoadCx((z + 64) * 16) + lane * LANE_W + 4, RoadY((z + 64) * 16), z + 64, 0, -1, False
        If ConeAt(i, cd) Then
            hit = sgKnocked(i) <> 0
            AddModel MDL_CONE, sgCx(i) + cd + IIf(hit, 26, 0), sgY(i), z + IIf(hit, 30, 0), 0, -1, False
        End If
    End If
    If k < SCENE_SEGS Then Scenery i
    If i > 0 Then
        If (sgFlags(i) And SF_OVERPASS) <> 0 And (sgFlags(i - 1) And SF_OVERPASS) = 0 Then
            z = (i + 1) * SEG_LEN
            AddModel MDL_OVERPASS, RoadCx(z * 16) + (rl + rr) \ 2, RoadY(z * 16), z, RoadDir(z * 16), -1, False, 4
        End If
    End If
    If i = wFinish Then
        z = i * SEG_LEN
        AddModel MDL_GANTRY, sgCx(i) + (rl + rr) \ 2, sgY(i), z, RoadDir(z * 16), -1, False, -8
    End If
    cur = segFirst(k)
    Do While cur >= 0
        DrawObject cur
        cur = objNext(cur)
    Loop
End Sub

' ---------- the sky ----------

Private Sub MakeSkylines()
    Dim r As Long, j As Long, h As Long, v As Long
    For r = 0 To 3
        For j = 0 To 63
            h = A3Hash(r * 64 + j)
            Select Case r
                Case 0: v = 4 + UModL(h, 5)                          ' trees across the river
                Case 1: If (j And 3) <> 0 Then v = 3 + UModL(h, 4) Else v = 8 + UModL(h, 14)   ' distant towers
                Case 2: v = 10 + UModL(h, 30)                        ' mountains
                Case Else: v = 6 + UModL(h, 12)                      ' rooftops
            End Select
            skyline(r, j) = v
        Next j
    Next r
    skylinesMade = True
End Sub

Private Function S16(ByVal a As Long) As Long
    S16 = ((a + 32768) And &HFFFF&) - 32768
End Function

Private Sub DrawSkyline(cv As Object)
    Dim j As Long, r As Long, blocky As Boolean, a As Long, b As Long, x0 As Long, x1 As Long, h0 As Long, h1 As Long
    r = wRoute
    blocky = r = 1 Or r = 3
    For j = -1 To 64
        a = S16(j * 1024 - camYaw): b = S16((j + 1) * 1024 - camYaw)
        x0 = VIEW_CX + (a * FOV) \ 10430
        x1 = VIEW_CX + (b * FOV) \ 10430
        h0 = skyline(r, j And 63): h1 = skyline(r, (j + 1) And 63)
        If x1 >= 0 And x0 <= VIEW_W - 1 And x1 > x0 Then
            If blocky Then h1 = h0
            px(0) = x0: py(0) = horizonY - h0
            px(1) = x1: py(1) = horizonY - h1
            px(2) = x1: py(2) = horizonY
            px(3) = x0: py(3) = horizonY
            cv.Polygon px, py, 4, pen(PEN_HAZE), True
        End If
    Next j
End Sub

Private Sub Octagon(cv As Object, ByVal cx As Long, ByVal cy As Long, ByVal r As Long, ByVal p As Long)
    Dim h As Long
    h = (r * 5) \ 12
    px(0) = cx - h: py(0) = cy - r
    px(1) = cx + h: py(1) = cy - r
    px(2) = cx + r: py(2) = cy - h
    px(3) = cx + r: py(3) = cy + h
    px(4) = cx + h: py(4) = cy + r
    px(5) = cx - h: py(5) = cy + r
    px(6) = cx - r: py(6) = cy + h
    px(7) = cx - r: py(7) = cy - h
    cv.Polygon px, py, 8, pen(p), True
End Sub

Private Sub DrawSun(cv As Object)
    Dim d As Long, x As Long, r As Long
    If sunYaw < 0 Then Exit Sub
    d = S16(sunYaw - camYaw)
    If d > 9000 Or d < -9000 Then Exit Sub
    x = VIEW_CX + (d * FOV) \ 10430
    r = 9 + wGlare \ 2
    Octagon cv, x, horizonY - 14, r + 4, PEN_ORANGE
    Octagon cv, x, horizonY - 14, r, PEN_YELLOW
    Octagon cv, x, horizonY - 14, r \ 2, PEN_WHITE
End Sub

Public Function DataFile(ByVal name As String) As String
    If Len(dataDir) > 0 Then
        If Right$(dataDir, 1) = ":" Or Right$(dataDir, 1) = "/" Then DataFile = dataDir & name Else DataFile = dataDir & "/" & name
    Else
        DataFile = HsPath(name)
    End If
End Function

Private Sub LoadArt(cv As Object)
    If artTried Then Exit Sub
    artTried = True
    On Error Resume Next
    panorama = cv.LoadImage(DataFile("sc_horizon.ppm"))
    If Err.Number <> 0 Then panorama = 0
    Err.Clear
    titleImg = cv.LoadImage(DataFile("sc_title.ppm"))
    If Err.Number <> 0 Then titleImg = 0
    On Error GoTo 0
End Sub

Public Function HasTitleArt(cv As Object) As Boolean
    LoadArt cv
    HasTitleArt = titleImg <> 0
End Function

' the painted dusk, wrapped round: its column at the view's left edge
Private Sub DrawPanorama(cv As Object, ByVal hz As Long)
    Dim w As Long, h As Long, a As Long, sx As Long, top As Long, w1 As Long, sy As Long, hh As Long
    w = cv.ImageWidth(panorama): h = cv.ImageHeight(panorama)
    a = camYaw - (VIEW_CX * 10430) \ FOV
    sx = (((a * w) \ 65536) Mod w + w) Mod w
    top = hz - h
    sy = 0: hh = h
    If top < 0 Then
        sy = -top: hh = h + top: top = 0
    End If
    If hh <= 0 Then Exit Sub
    w1 = w - sx
    If w1 > VIEW_W Then w1 = VIEW_W
    cv.DrawImagePart panorama, sx, sy, w1, hh, 0, top, True
    If w1 < VIEW_W Then cv.DrawImagePart panorama, 0, sy, VIEW_W - w1, hh, w1, top, True
End Sub

' ---------- one frame of the road ----------
Public Sub DrawScene(cv As Object)
    Dim s0 As Long, s1 As Long, i As Long, hz As Long, vx As Long, vy As Long, vz As Long
    PalCheck
    If Not skylinesMade Then MakeSkylines
    LoadArt cv
    CameraFollow
    If wRoute <> sunRoute Then
        ' the sun sits where the road heads into it
        sunRoute = wRoute
        sunYaw = -1
        For i = 0 To wNHaz - 1
            If hzType(i) = HZ_GLARE Then
                sunYaw = RoadDir((hzSeg(i) + hzLen(i) \ 2) * SEGF)
                Exit For
            End If
        Next i
    End If
    s0 = SegOf(camZ * 16)
    If s0 < 0 Then s0 = 0
    If renderDrawDist > NVIS_MAX Then s1 = s0 + NVIS_MAX Else s1 = s0 + renderDrawDist
    If s1 > wNSeg - 2 Then s1 = wNSeg - 2
    ' where the sky meets the ground
    horizonY = VIEW_CY - (FOV * (A3Sin(camPitch) \ 16)) \ (A3Cos(camPitch) \ 16)
    e3.Xform sgCx(s1) + (RoadLeft() + RoadRight()) \ 2, camY, s1 * SEG_LEN, vx, vy, vz
    If vz > 12 Then vanishX = VIEW_CX + (vx * FOV) \ vz Else vanishX = VIEW_CX
    If vanishX < 0 Then vanishX = 0
    If vanishX > VIEW_W - 1 Then vanishX = VIEW_W - 1
    groundL = FarPen(sgSideL(s1)): groundR = FarPen(sgSideR(s1))
    hz = horizonY
    If hz < 0 Then hz = 0
    If hz > VIEW_H Then hz = VIEW_H
    e3.Clear PEN_SKY
    If panorama <> 0 Then
        If hz > 0 Then DrawPanorama cv, hz
    End If
    cv.Box 0, hz, vanishX + 1, VIEW_H - hz, pen(groundL)
    cv.Box vanishX + 1, hz, VIEW_W - vanishX - 1, VIEW_H - hz, pen(groundR)
    If panorama = 0 Then DrawSkyline cv
    DrawSun cv
    If wRoute <> slotRoute Then
        For i = 0 To 63: slotSeg(i) = -1: Next i
        slotRoute = wRoute
    End If
    cy4 = A3Cos(camYaw) \ 16: sy4 = A3Sin(camYaw) \ 16: cp4 = A3Cos(camPitch) \ 16: sp4 = A3Sin(camPitch) \ 16
    SortObjects s0, s1
    e3.Begin FAR_Z + 400
    For i = s1 To s0 Step -1
        DrawSegment i, i - s0
    Next i
    e3.Flush
    polyTotal = polyTotal + e3.NPolys
End Sub

' ---------- overlays ----------
Private Sub HLine(cv As Object, ByVal x0 As Long, ByVal x1 As Long, ByVal y As Long, ByVal p As Long)
    If y < 0 Or y >= VIEW_H Then Exit Sub
    GRect cv, x0, y, x1, y, p
End Sub

Private Sub VLine(cv As Object, ByVal x As Long, ByVal y0 As Long, ByVal y1 As Long, ByVal p As Long)
    If y1 > VIEW_H - 1 Then y1 = VIEW_H - 1
    If y0 <= y1 Then GRect cv, x, y0, x, y1, p
End Sub

Private Sub Bracket(cv As Object, ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal p As Long)
    Dim l As Long
    l = (x1 - x0) \ 4
    If l < 2 Then l = 2
    If l > 8 Then l = 8
    HLine cv, x0, x0 + l, y0, p: HLine cv, x1 - l, x1, y0, p
    HLine cv, x0, x0 + l, y1, p: HLine cv, x1 - l, x1, y1, p
    VLine cv, x0, y0, y0 + l, p: VLine cv, x1, y0, y0 + l, p
    VLine cv, x0, y1 - l, y1, p: VLine cv, x1, y1 - l, y1, p
End Sub

Private Sub AiBrackets(cv As Object)
    Dim i As Long, ln As Long, wd As Long, h As Long, z As Long, x As Long, y As Long, x0 As Long, y0 As Long, x1 As Long, y1 As Long
    Dim cx As Long, cy As Long, cz As Long, dx As Long, dy As Long, dz As Long, t As Long, p As Long
    For i = 0 To aiNSeen - 1
        If snPhantom(i) <> 0 Then
            ln = 30: wd = 40: h = 64
        Else
            ln = objLen(snType(i)): wd = objWid(snType(i)): h = objHeight(snType(i))
        End If
        z = ShrA(snZ(i), FBITS) - ln: x = RoadCx(snZ(i)) + ShrA(snD(i), FBITS): y = RoadY(snZ(i))
        If z - camZ <= 2200 Then
            e3.Xform x - wd, y, z, cx, cy, cz
            e3.Xform x + wd, y + h, z, dx, dy, dz
            If cz >= 12 + 8 And dz >= 12 + 8 Then
                x0 = VIEW_CX + (cx * FOV) \ cz: y0 = VIEW_CY - (cy * FOV) \ cz
                x1 = VIEW_CX + (dx * FOV) \ dz: y1 = VIEW_CY - (dy * FOV) \ dz
                If x0 > x1 Then
                    t = x0: x0 = x1: x1 = t
                End If
                If y0 < y1 Then
                    t = y0: y0 = y1: y1 = t
                End If
                If Not (x1 < 0 Or x0 >= VIEW_W Or y0 < 0 Or y1 >= VIEW_H) Then
                    x0 = x0 - 2: x1 = x1 + 2: y1 = y1 - 2: y0 = y0 + 1
                    If snPhantom(i) <> 0 Then
                        If (wFrame And 4) <> 0 Then p = PEN_RED Else p = PEN_YELLOW
                        Bracket cv, x0, y1, x1, y0, p
                        If y1 > 12 Then GTextShadow cv, (x0 + x1) \ 2 - 3, y1 - 3, p, "?"
                    Else
                        Bracket cv, x0, y1, x1, y0, PEN_AI2
                    End If
                End If
            End If
        End If
    Next i
End Sub

Private Sub Cockpit(cv As Object)
    Dim k As Long, ang As Long, a0 As Long, a1 As Long
    px(0) = 0: py(0) = 0: px(1) = 20: py(1) = 0: px(2) = 6: py(2) = 178: px(3) = 0: py(3) = 178
    cv.Polygon px, py, 4, pen(PEN_PANEL), True
    px(0) = 300: py(0) = 0: px(1) = 319: py(1) = 0: px(2) = 319: py(2) = 178: px(3) = 313: py(3) = 178
    cv.Polygon px, py, 4, pen(PEN_PANEL), True
    GRect cv, 132, 2, 188, 12, PEN_PANEL                  ' the mirror
    GRect cv, 135, 4, 185, 10, PEN_SKY
    GRect cv, 0, 178, VIEW_W - 1, VIEW_H - 1, PEN_PANEL   ' the dashboard
    GRect cv, 0, 178, VIEW_W - 1, 179, PEN_GREY
    ang = (carS * 16384) \ 256
    For k = 0 To 7                                         ' the steering wheel, turned by the steering
        a0 = ang + k * 8192: a1 = a0 + 8192
        px(0) = 110 + ShrA(A3Sin(a0) * 40, 16): py(0) = 206 - ShrA(A3Cos(a0) * 30, 16)
        px(1) = 110 + ShrA(A3Sin(a1) * 40, 16): py(1) = 206 - ShrA(A3Cos(a1) * 30, 16)
        px(2) = 110 + ShrA(A3Sin(a1) * 33, 16): py(2) = 206 - ShrA(A3Cos(a1) * 24, 16)
        px(3) = 110 + ShrA(A3Sin(a0) * 33, 16): py(3) = 206 - ShrA(A3Cos(a0) * 24, 16)
        cv.Polygon px, py, 4, pen(PEN_BLACK), True
    Next k
    For k = 0 To 1                                         ' the spokes
        a0 = ang + 16384 + k * 32768
        px(0) = 110 + ShrA(A3Sin(a0 - 1500) * 34, 16): py(0) = 206 - ShrA(A3Cos(a0 - 1500) * 25, 16)
        px(1) = 110 + ShrA(A3Sin(a0 + 1500) * 34, 16): py(1) = 206 - ShrA(A3Cos(a0 + 1500) * 25, 16)
        px(2) = 110 + ShrA(A3Sin(a0 + 6000) * 7, 16): py(2) = 206 - ShrA(A3Cos(a0 + 6000) * 6, 16)
        px(3) = 110 + ShrA(A3Sin(a0 - 6000) * 7, 16): py(3) = 206 - ShrA(A3Cos(a0 - 6000) * 6, 16)
        cv.Polygon px, py, 4, pen(PEN_BLACK), True
    Next k
    GRect cv, 196, 184, 300, 207, PEN_BLACK                ' the car's own screen
    If aiOn <> 0 Then
        GText cv, 204, 194, IIf(aiBlinded <> 0 And (wFrame And 4) <> 0, PEN_WHITE, PEN_AI), "AUTO x" & wMult
    Else
        GText cv, 204, 194, PEN_ORANGE, "MANUAL"
    End If
    GText cv, 204, 204, PEN_GREY, Right$("  " & Kmh(carV), 3) & " KM/H"
End Sub

Private Sub PanelBox(cv As Object, ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long)
    GRect cv, x0, y0, x1, y1, PEN_PANEL
    cv.Rect x0, y0, x1 - x0 + 1, y1 - y0 + 1, pen(PEN_AI)
End Sub

Private Sub BigCentre(cv As Object, ByVal y As Long, ByVal p As Long, ByVal s As String, ByVal sc As Long)
    GTextBig cv, (G_W - GTextBigWidth(cv, s, sc)) \ 2, y, p, s, sc
End Sub

Private Sub StateBox(cv As Object)
    Dim blink As Long
    If (wFrame And 16) <> 0 Then blink = PEN_YELLOW Else blink = PEN_WHITE
    Select Case wState
        Case GS_INTRO
            PanelBox cv, 40, 54, 279, 150
            GTextCentre cv, 68, PEN_GREY, "ROUTE " & (wRoute + 1) & " OF " & NUM_ROUTES
            BigCentre cv, 76, PEN_YELLOW, riName(wRoute), 2
            GTextCentre cv, 106, PEN_WHITE, "TO " & riDest(wRoute)
            GTextCentre cv, 120, PEN_AI, "AUTOPILOT v" & riAi(wRoute)
            GTextCentre cv, 140, blink, "PRESS FIRE"
        Case GS_ARRIVED
            PanelBox cv, 32, 34, 287, 166
            GTextCentre cv, 50, PEN_YELLOW, "ARRIVED: " & riDest(wRoute)
            GTextCentre cv, 70, PEN_AI, "AUTOPILOT USED   " & Right$("  " & WorldApPct(), 3) & "%"
            GTextCentre cv, 84, PEN_AI2, "GOOD CATCHES     " & Right$("  " & wSaves, 3)
            GTextCentre cv, 98, PEN_ORANGE, "NEEDLESS GRABS   " & Right$("  " & wNeedless, 3)
            GTextCentre cv, 112, PEN_WHITE, "INSURANCE COVER  " & Right$("  " & wCover, 3)
            GTextCentre cv, 132, PEN_YELLOW, "BONUS " & wRouteBonus
            If wStateTimer < 210 Then GTextCentre cv, 154, blink, "PRESS FIRE"
        Case GS_GAMEOVER
            PanelBox cv, 40, 60, 279, 140
            BigCentre cv, 72, PEN_RED, "CANCELLED", 2
            GTextCentre cv, 100, PEN_WHITE, "YOUR INSURER HAS HAD ENOUGH"
            GTextCentre cv, 116, PEN_YELLOW, "SCORE " & wScore
            If wStateTimer = 0 Then GTextCentre cv, 132, PEN_WHITE, "PRESS FIRE"
        Case GS_WIN
            PanelBox cv, 24, 40, 295, 160
            BigCentre cv, 50, PEN_YELLOW, "YOU'RE HOME", 2
            GTextCentre cv, 84, PEN_WHITE, "FINAL SCORE " & wScore
            GTextCentre cv, 100, PEN_AI2, "GOOD CATCHES " & wTotalSaves & "  NEEDLESS " & wTotalNeedless
            GTextCentre cv, 120, PEN_AI, "THE AI THANKS YOU"
            GTextCentre cv, 132, PEN_AI, "FOR YOUR TRAINING DATA"
            If wStateTimer = 0 Then GTextCentre cv, 152, PEN_WHITE, "PRESS FIRE"
    End Select
End Sub

Public Sub DrawOverlay(cv As Object)
    Dim p As Long
    If aiOn <> 0 And wState <> GS_TITLE Then AiBrackets cv
    If wView = CAM_COCKPIT Then Cockpit cv
    If wMsg <> MSG_NONE And wState <> GS_TITLE Then
        If wMsg = MSG_TICKET Or wMsg = MSG_TOW Or wMsg = MSG_CANCELLED Then
            p = PEN_YELLOW
        ElseIf wMsg = MSG_GOOD_CATCH Then
            p = PEN_AI2
        Else
            p = PEN_AI
        End If
        GTextCentre cv, 24, p, msgText(wMsg)
    End If
    If wState = GS_PLAY And carState = CS_AQUAPLANE And (wFrame And 8) <> 0 Then GTextCentre cv, 40, PEN_WHITE, "AQUAPLANING"
    ' stopped with the autopilot off (after the tow truck): what to do
    If wState = GS_PLAY And aiOn = 0 And carState = CS_DRIVING And carV < FromKmh(5) And (wFrame And 16) <> 0 Then
        GTextCentre cv, 150, PEN_YELLOW, "FIRE: AUTOPILOT   UP: DRIVE"
    End If
    StateBox cv
End Sub

' ---------- the software update between routes ----------
Public Sub DrawUpdate(cv As Object)
    PalCheck
    Dim nxt As Long, done As Long, k As Long, fill As Long
    If wRoute + 1 < NUM_ROUTES Then nxt = wRoute + 1 Else nxt = NUM_ROUTES - 1
    done = 200 - wStateTimer
    cv.Cls pen(PEN_BLACK)
    BigCentre cv, 24, PEN_AI, "SOFTWARE UPDATE", 2
    GTextCentre cv, 64, PEN_WHITE, "AUTOPILOT v" & riAi(nxt)
    For k = 0 To 3
        If done > 20 + k * 12 Then GText cv, 40, 92 + k * 14, IIf(k = 3, PEN_ORANGE, PEN_AI2), patchNotes(nxt, k)
    Next k
    fill = done * 2
    If fill > 240 Then fill = 240
    GRect cv, 40, 160, 280, 170, PEN_PANEL
    If fill > 0 Then GRect cv, 40, 160, 40 + fill, 170, PEN_AI
    If fill >= 240 Then
        GTextCentre cv, 190, PEN_WHITE, "INSTALLED. I AM BETTER NOW."
        If done > 40 Then GTextCentre cv, 220, IIf((wFrame And 16) <> 0, PEN_YELLOW, PEN_WHITE), "PRESS FIRE"
    Else
        GTextCentre cv, 190, PEN_GREY, "INSTALLING... " & ((fill * 100) \ 240) & "%"
    End If
End Sub

' ---------- the rules ----------
Public Sub DrawHelp(cv As Object, ByVal page As Long)
    PalCheck
    Dim k As Long, p As Long
    If page < 1 Or page > HELP_PAGES Then Exit Sub
    cv.Cls pen(PEN_BLACK)
    BigCentre cv, 14, PEN_AI, helpTitle(page), 2
    For k = 0 To 11
        If page = 1 And k = 9 Then
            p = PEN_AI2
        ElseIf page = 1 And k > 9 Then
            p = PEN_ORANGE
        Else
            p = PEN_WHITE
        End If
        GText cv, 4, 54 + k * 14, p, helpText(page, k)
    Next k
    GText cv, 4, 236, PEN_GREY, "PAGE " & page & " OF " & HELP_PAGES
    GText cv, 140, 236, PEN_YELLOW, "HELP: NEXT  FIRE: PLAY"
End Sub

' ---------- the title, over the autopilot driving itself ----------
Public Sub DrawTitleText(cv As Object)
    Dim x As Long, w As Long
    w = GTextBigWidth(cv, "SCAIRY FUN", 3)
    x = (G_W - w) \ 2
    GTextBig cv, x + 3, 33, PEN_BLACK, "SC", 3
    GTextBig cv, x, 30, PEN_WHITE, "SC", 3
    GTextBig cv, x + GTextBigWidth(cv, "SC", 3) + 3, 33, PEN_BLACK, "AI", 3
    GTextBig cv, x + GTextBigWidth(cv, "SC", 3), 30, PEN_AI, "AI", 3
    GTextBig cv, x + GTextBigWidth(cv, "SCAI", 3) + 3, 33, PEN_BLACK, "RY FUN", 3
    GTextBig cv, x + GTextBigWidth(cv, "SCAI", 3), 30, PEN_WHITE, "RY FUN", 3
    GTextCentre cv, 70, PEN_YELLOW, "A SELF-DRIVING ADVENTURE"
    GTextCentre cv, 150, PEN_WHITE, "LEFT/RIGHT/BRAKE TAKES OVER"
    GTextCentre cv, 162, PEN_WHITE, "FIRE: AUTOPILOT   V: VIEW"
    GTextCentre cv, 186, IIf((wFrame And 16) <> 0, PEN_YELLOW, PEN_WHITE), "PRESS FIRE TO START"
    GTextCentre cv, 200, PEN_GREY, "HELP OR H: HOW TO PLAY"
End Sub

Public Sub DrawTitleArt(cv As Object)
    PalCheck
    cv.DrawImage titleImg, 0, 0, True
    GTextCentre cv, G_H - 26, PEN_WHITE, "PRESS FIRE TO START"
    GTextCentre cv, G_H - 12, PEN_GREY, "HELP OR H: HOW TO PLAY"
End Sub

' ---------- the HUD ----------
Private Sub HudBar(cv As Object, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal v As Long, ByVal mx As Long, ByVal p As Long)
    Dim fill As Long
    fill = (v * w) \ mx
    If fill < 0 Then fill = 0
    If fill > w Then fill = w
    GRect cv, x, y, x + w, y + 4, PEN_BLACK
    If fill > 0 Then GRect cv, x, y, x + fill, y + 4, p
End Sub

Private Function AXp(ByVal u As Long, ByVal l As Long, ByVal span As Long) As Long
    AXp = 246 + 2 + ((u - l) * (316 - 246 - 4)) \ span
End Function

Private Function AYp(ByVal dz As Long) As Long
    AYp = 253 - 6 - (dz * (253 - (VIEW_H + 3) - 10)) \ (12 * SEG_LEN)
End Function

Private Sub AiDot(ByVal x As Long, ByVal y As Long, ByVal p As Long)
    If aiN > 799 Then Exit Sub
    aiXs(aiN) = x: aiYs(aiN) = y: aiCs(aiN) = pen(p)
    aiN = aiN + 1
End Sub

' what the autopilot thinks is around it, from above
Private Sub AiDisplay(cv As Object)
    Dim x0 As Long, y0 As Long, x1 As Long, y1 As Long, l As Long, r As Long, span As Long, cz As Long, i As Long, n As Long
    Dim h As Long, ppx As Long, ppy As Long, dz As Long
    x0 = 246: y0 = VIEW_H + 3: x1 = 316: y1 = 253
    l = RoadLeft() - SHOULDER: r = RoadRight() + SHOULDER: span = r - l: cz = ShrA(carZ, FBITS)
    GRect cv, x0, y0, x1, y1, PEN_BLACK
    If aiBlinded <> 0 Then
        h = MulW(wFrame, &H9E3779B1)
        For i = 0 To 89
            h = AddW(MulW(h, 1103515245), 12345)
            ppx = x0 + 1 + UModL(ShrU(h, 8), x1 - x0 - 2)
            ppy = y0 + 1 + UModL(ShrU(h, 20), y1 - y0 - 2)
            GRect cv, ppx, ppy, ppx, ppy, IIf((h And 1) <> 0, PEN_WHITE, PEN_GREY)
        Next i
        GText cv, x0 + 15, y0 + 22, PEN_RED, "BLIND"
        Exit Sub
    End If
    If aiKey <> wRoute * 4096 + palGlare Then
        aiKey = wRoute * 4096 + palGlare
        aiN = 0
        For i = y0 + 1 To y1 - 1 Step 3
            AiDot AXp(RoadLeft(), l, span), i, PEN_GREY
            AiDot AXp(RoadRight(), l, span), i, PEN_GREY
            If riNo(wRoute) <> 0 Then AiDot AXp(0, l, span), i, PEN_YELLOW
            If i Mod 6 = 0 Then
                For n = 1 To riNl(wRoute) - 1
                    AiDot AXp(n * LANE_W, l, span), i, PEN_PANEL
                Next n
            End If
        Next i
    End If
    If aiN > 0 Then cv.PSetMany aiXs, aiYs, aiCs, aiN
    If aiOn <> 0 Then
        For i = 0 To 11
            dz = (aiPlanFrom + i) * SEG_LEN - cz
            ppx = AXp(ShrA(aiPlan(i), FBITS), l, span): ppy = AYp(dz)
            If Not (dz < 0 Or ppy <= y0 Or ppx <= x0 Or ppx >= x1) Then GRect cv, ppx, ppy, ppx, ppy, PEN_AI
        Next i
    End If
    For i = 0 To aiNSeen - 1
        dz = ShrA(snZ(i), FBITS) - cz
        ppx = AXp(ShrA(snD(i), FBITS), l, span): ppy = AYp(dz)
        If Not (ppy - 2 <= y0 Or ppy + 2 >= y1 Or ppx - 1 <= x0 Or ppx + 1 >= x1) Then
            If snPhantom(i) <> 0 Then
                GRect cv, ppx - 4, ppy - 3, ppx + 4, ppy + 2, IIf((wFrame And 4) <> 0, PEN_RED, PEN_YELLOW)
            Else
                GRect cv, ppx - 1, ppy - 2, ppx + 1, ppy + 1, PEN_AI2
            End If
        End If
    Next i
    ppx = AXp(ShrA(carD, FBITS), l, span)
    If ppx > x0 + 1 And ppx < x1 - 1 Then GRect cv, ppx - 1, y1 - 7, ppx + 1, y1 - 3, PEN_RED
    GText cv, x0 + 2, y0 + 8, IIf(aiOn <> 0, PEN_AI, PEN_PANEL), IIf(aiOn <> 0, "AI", "OFF")
End Sub

Public Sub DrawHud(cv As Object, ByVal paused As Boolean)
    Dim togo As Long, p As Long
    GRect cv, 0, VIEW_H, 319, 255, PEN_PANEL
    GRect cv, 0, VIEW_H, 319, VIEW_H, PEN_GREY
    GRect cv, 245, VIEW_H + 2, 317, 254, PEN_GREY
    If wState = GS_TITLE Then
        GText cv, 6, VIEW_H + 12, PEN_WHITE, "AN AMIGA DEVBENCH GAME"
        GText cv, 6, VIEW_H + 26, PEN_AI, "AUTOPILOT DEMONSTRATION"
        GText cv, 6, VIEW_H + 40, PEN_GREY, "TAKE OVER ONLY WHEN IT MATTERS"
        AiDisplay cv
        Exit Sub
    End If
    GText cv, 108, VIEW_H + 22, PEN_GREY, "COVER"
    GText cv, 6, VIEW_H + 12, PEN_WHITE, "SCORE " & Format$(wScore, "000000")
    If aiOn <> 0 Then GText cv, 6, VIEW_H + 26, PEN_AI, "AUTO x" & wMult Else GText cv, 6, VIEW_H + 26, PEN_ORANGE, "MANUAL"
    GText cv, 6, VIEW_H + 40, PEN_GREY, "AP " & Right$("  " & WorldApPct(), 3) & "% R" & (wRoute + 1)
    GText cv, 108, VIEW_H + 12, PEN_WHITE, Right$("  " & Kmh(carV), 3) & " KM/H"
    togo = (wFinish - SegOf(carZ)) * 8
    If togo < 0 Then togo = 0
    GText cv, 108, VIEW_H + 40, PEN_GREY, (togo \ 1000) & "." & ((togo Mod 1000) \ 100) & " KM"
    HudBar cv, 152, VIEW_H + 17, 84, wCover, 100, IIf(wCover < 30, PEN_RED, PEN_AI2)
    ' progress along the route
    If wFinish <> 0 Then p = (SegOf(carZ) * 84) \ wFinish Else p = 0
    If p > 84 Then p = 84
    GRect cv, 196, VIEW_H + 34, 240, VIEW_H + 39, PEN_PANEL
    GRect cv, 196, VIEW_H + 36, 240, VIEW_H + 37, PEN_GREY
    GRect cv, 196 + p \ 2, VIEW_H + 34, 197 + p \ 2, VIEW_H + 39, PEN_RED
    AiDisplay cv
    If paused Then GTextCentre cv, 100, PEN_WHITE, "PAUSED"
End Sub

Public Sub DrawPerf(cv As Object)
    cv.Box 0, 0, G_W, 11, pen(0)
    GText cv, 2, 9, PEN_AI2, PerfText()
End Sub
