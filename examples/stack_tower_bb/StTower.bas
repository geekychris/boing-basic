' StTower - the tower in 3D on the Boing.Engine3D library (the amiga3d engine in C).
'
' render.c works out every corner of every block with sin/cos each frame and turns the
' tower under a fixed camera. Here the tower stands still and the camera goes round it
' (the same picture): so every block, grid line and ring piece keeps its place in the
' world, and the lists of what to draw only change when the board or the piece does.
' Everything is a small model, the same for every column, placed and turned by
' DrawModels (one call for a whole list): a block (by colour, its neighbours, and whether
' it is on the board, the piece or the ghost), a grid line, a ring piece, a core panel,
' a cell of the drop guide. The engine culls the faces that face away, sorts each model's
' faces, and sorts the models by depth, in C. The passes are render.c's: the core, then
' the drop guide and the grid on it, then the blocks and the red line.
Option Explicit

Public e3 As Object                     ' the engine
Public towerPolys As Long               ' polygons drawn this frame

Private Const MAXI As Long = 400        ' instances in a list
' model numbers
Private mCore As Long, mGridV As Long, mGridH As Long, mGuide As Long, mRing As Long
Private mBrick(0 To 399) As Long        ' (kind * 16 + neighbours); kind: 0-8 board pens, 9-16 piece, 17-24 ghost
' lists of instances (model, x, y, z, yaw): 0 the board's blocks, 1 the piece and its
' ghost, 2 the grid's row lines, 3 the drop guide (plain arrays: they go to DrawModels)
Private Const LB As Long = 0, LP As Long = 1, LG As Long = 2, LD As Long = 3
Private lN(0 To 3) As Long
Private bId(0 To 399) As Long, bX(0 To 399) As Long, bY(0 To 399) As Long, bZ(0 To 399) As Long, bYaw(0 To 399) As Long
Private pId(0 To 399) As Long, pX(0 To 399) As Long, pY(0 To 399) As Long, pZ(0 To 399) As Long, pYaw(0 To 399) As Long
Private gX(0 To 399) As Long, gY(0 To 399) As Long, gZ(0 To 399) As Long, gYaw(0 To 399) As Long
Private dX(0 To 399) As Long, dY(0 To 399) As Long, dZ(0 To 399) As Long, dYaw(0 To 399) As Long
Private coreYaw(0 To 15) As Long, coreX(0 To 15) As Long, coreZ(0 To 15) As Long, coreY(0 To 15) As Long
Private ringYaw(0 To 15) As Long, ringX(0 To 15) As Long, ringZ(0 To 15) As Long, ringY(0 To 15) As Long
Private gvYaw(0 To 15) As Long, gvX(0 To 15) As Long, gvZ(0 To 15) As Long, gvY(0 To 15) As Long
' centre positions of the column's middle (or edge) at the radii used: (k * 16 + c)
Private posX(0 To 127) As Long, posZ(0 To 127) As Long
Private Const RK_BOARD As Long = 0      ' blocks: (140 + 162) / 2
Private Const RK_PIECE As Long = 1      ' (140 + 168) / 2
Private Const RK_GHOST As Long = 2      ' (140 + 146) / 2
Private Const RK_GRID As Long = 3       ' 139
Private Const RK_GUIDE As Long = 4      ' 138
Private Const YAW_SIGN As Long = -1     ' a model turned by yaw = YAW_SIGN * angle stands at that angle

Private keyBoard As Long, keyCol As Long, keyPiece As String, keyGrid As Long, keyGuide As String

Public Sub TowerInit(cv As Object, pens As Variant)
    Dim c As Long, k As Long, rads As Variant, a As Long
    Set e3 = CreateObject("Boing.Engine3D")
    e3.Attach cv
    e3.View 200, 256, 100, 120, 200
    e3.Palette12 pens
    rads = Array(151, 154, 143, 139, 138)
    For k = 0 To 4
        For c = 0 To 15
            a = (c * 4096) And 65535
            posX(k * 16 + c) = ShrA(A3Sin(a) * rads(k), 16)
            posZ(k * 16 + c) = -ShrA(A3Cos(a) * rads(k), 16)
        Next c
    Next k
    mCore = PanelModel(-128, 128, 137, -20, ST_ROWS * ROW_H + 30, PEN_CORE)
    mGridV = PanelModel(-6, 6, TOWER_R - 1, 0, ST_ROWS * ROW_H, PEN_CORE_LINE)
    mGridH = PanelModel(-128, 128, TOWER_R - 1, -1, 1, PEN_CORE_LINE)
    mGuide = PanelModel(-128, 128, TOWER_R - 2, 0, ROW_H, PEN_GUIDE)
    mRing = PanelModel(-128, 128, TOWER_R + 2, ST_ROWS * ROW_H - 2, ST_ROWS * ROW_H + 2, PEN_LINE)
    ' the core and the red line: every column (the culling keeps the front)
    For c = 0 To 15
        Place c * 256, 137, (ST_ROWS * ROW_H + 30 - 20) \ 2, coreX(c), coreY(c), coreZ(c), coreYaw(c)
        Place c * 256 + 128, TOWER_R + 2, ST_ROWS * ROW_H, ringX(c), ringY(c), ringZ(c), ringYaw(c)
        Place c * 256 - 128, TOWER_R - 1, ST_ROWS * ROW_H \ 2, gvX(c), gvY(c), gvZ(c), gvYaw(c)
    Next c
    keyBoard = -1: keyGrid = -1
End Sub

' where a model made at angle 0 goes for column position colf (8.8), radius r, height y
Private Sub Place(ByVal colf As Long, ByVal r As Long, ByVal y As Long, px As Long, py As Long, pz As Long, pyaw As Long)
    Dim a As Long
    a = (colf * 16) And 65535
    px = ShrA(A3Sin(a) * r, 16)
    pz = -ShrA(A3Cos(a) * r, 16)
    py = y
    pyaw = (YAW_SIGN * colf * 16) And 65535
End Sub

' a point at column offset off (8.8), radius r, height y, relative to the model's centre
' (angle 0, radius rc, height yc)
Private Function Vtx(ByVal m As Long, ByVal off As Long, ByVal r As Long, ByVal y As Long, ByVal rc As Long, ByVal yc As Long) As Long
    Dim a As Long
    a = (off * 16) And 65535
    Vtx = e3.MdlVtx(m, ShrA(A3Sin(a) * r, 16), y - yc, -ShrA(A3Cos(a) * r, 16) + rc)
End Function

' a curved-wall quad from column offset o0 to o1 at radius r, heights y0 to y1 (one pen)
Private Function PanelModel(ByVal o0 As Long, ByVal o1 As Long, ByVal r As Long, ByVal y0 As Long, ByVal y1 As Long, _
                            ByVal p As Long) As Long
    Dim m As Long, yc As Long, a As Long, b As Long, c As Long, d As Long
    m = e3.ModelNew()
    yc = (y0 + y1) \ 2
    a = Vtx(m, o0, r, y0, r, yc): b = Vtx(m, o1, r, y0, r, yc)
    c = Vtx(m, o1, r, y1, r, yc): d = Vtx(m, o0, r, y1, r, yc)
    e3.MdlFace m, p, p, 4, a, d, c, b, 0, 0, r       ' facing away from the tower's axis
    PanelModel = m
End Function

' a block (render.c's brick): the outside face bevelled (a rim round a centre just in
' front), its top and the sides without a neighbour; out: how far it sticks out
Private Function BrickModel(ByVal lit As Long, ByVal shade As Long, ByVal out As Long, ByVal nb As Long) As Long
    Dim m As Long, rc As Long, r1 As Long, p(0 To 7) As Long, q(0 To 3) As Long, h As Long
    m = e3.ModelNew()
    r1 = TOWER_R + out
    rc = (TOWER_R + r1) \ 2
    h = ROW_H \ 2
    p(0) = Vtx(m, -128, TOWER_R, 0, rc, h): p(1) = Vtx(m, 128, TOWER_R, 0, rc, h)
    p(2) = Vtx(m, 128, TOWER_R, ROW_H, rc, h): p(3) = Vtx(m, -128, TOWER_R, ROW_H, rc, h)
    p(4) = Vtx(m, -128, r1, 0, rc, h): p(5) = Vtx(m, 128, r1, 0, rc, h)
    p(6) = Vtx(m, 128, r1, ROW_H, rc, h): p(7) = Vtx(m, -128, r1, ROW_H, rc, h)
    q(0) = Vtx(m, -84, r1 + 1, 5, rc, h): q(1) = Vtx(m, 84, r1 + 1, 5, rc, h)
    q(2) = Vtx(m, 84, r1 + 1, ROW_H - 5, rc, h): q(3) = Vtx(m, -84, r1 + 1, ROW_H - 5, rc, h)
    e3.MdlFace m, shade, shade, 4, p(4), p(7), p(6), p(5), 0, 0, 0        ' outside: the rim
    e3.MdlFace m, lit, lit, 4, q(0), q(3), q(2), q(1), 0, 0, 0            ' its lit centre
    If (nb And 4) = 0 Then e3.MdlFace m, lit, lit, 4, p(7), p(3), p(2), p(6), 0, 0, 0       ' top
    If (nb And 8) = 0 Then e3.MdlFace m, shade, shade, 4, p(4), p(5), p(1), p(0), 0, 0, 0   ' bottom
    If (nb And 1) = 0 Then e3.MdlFace m, shade, shade, 4, p(0), p(3), p(7), p(4), 0, 0, 0   ' left
    If (nb And 2) = 0 Then e3.MdlFace m, shade, shade, 4, p(1), p(5), p(6), p(2), 0, 0, 0   ' right
    BrickModel = m
End Function

' the model for a block of kind k (0-8 board pens 1-9, 9-16 piece, 17-24 ghost), made when first needed
Private Function Brick(ByVal k As Long, ByVal nb As Long) As Long
    Dim i As Long, lit As Long
    i = k * 16 + nb
    If mBrick(i) = 0 Then
        If k < 9 Then
            lit = LitPen(k + 1)
            mBrick(i) = BrickModel(lit, lit + 1, 22, nb)
        ElseIf k < 17 Then
            lit = LitPen(k - 8)
            mBrick(i) = BrickModel(lit, lit + 1, 28, nb)
        Else
            mBrick(i) = BrickModel(PEN_CORE, LitPen(k - 16), 6, nb)   ' an outline in the piece's colour
        End If
    End If
    Brick = mBrick(i)
End Function

Private Sub AddInst(ByVal l As Long, ByVal id As Long, ByVal c As Long, ByVal rk As Long, ByVal y As Long)
    Dim i As Long, x As Long, z As Long, yaw As Long
    i = lN(l)
    If i >= MAXI Then Exit Sub
    x = posX(rk * 16 + c)
    z = posZ(rk * 16 + c)
    yaw = (YAW_SIGN * c * 4096) And 65535
    Select Case l
        Case LB: bId(i) = id: bX(i) = x: bY(i) = y: bZ(i) = z: bYaw(i) = yaw
        Case LP: pId(i) = id: pX(i) = x: pY(i) = y: pZ(i) = z: pYaw(i) = yaw
        Case LG: gX(i) = x: gY(i) = y: gZ(i) = z: gYaw(i) = yaw
        Case Else: dX(i) = x: dY(i) = y: dZ(i) = z: dYaw(i) = yaw
    End Select
    lN(l) = i + 1
End Sub

Private Function LitPen(ByVal v As Long) As Long
    If v = ST_GARBAGE Then LitPen = PEN_GARBAGE Else LitPen = PEN_PIECE + 2 * (v - 1)
End Function

' a piece's own neighbours among its cells (in cellC / cellR)
Private Function PieceNb(ByVal n As Long, ByVal k As Long) As Long
    Dim j As Long, nb As Long, dc As Long, dr As Long
    For j = 0 To n - 1
        dc = ((cellC(j) - cellC(k) + 24) Mod 16) - 8
        dr = cellR(j) - cellR(k)
        If dr = 0 And dc = -1 Then nb = nb Or 1
        If dr = 0 And dc = 1 Then nb = nb Or 2
        If dc = 0 And dr = 1 Then nb = nb Or 4
        If dc = 0 And dr = -1 Then nb = nb Or 8
    Next j
    PieceNb = nb
End Function

' the blocks on the front half
Private Sub BuildBoard(ByVal vc As Long)
    Dim r As Long, c As Long, v As Long, d As Long, nb As Long, b As Long
    lN(LB) = 0
    For r = 0 To ST_TOTAL - 1
        b = r * 16
        For c = 0 To 15
            v = stBoard(b + c)
            If v <> 0 Then
                d = ((c - vc + 24) And 15) - 8
                If d >= -5 And d <= 5 Then
                    nb = 0
                    If stBoard(b + ((c + 15) And 15)) <> 0 Then nb = 1
                    If stBoard(b + ((c + 1) And 15)) <> 0 Then nb = nb Or 2
                    If r < ST_TOTAL - 1 Then
                        If stBoard(b + 16 + c) <> 0 Then nb = nb Or 4
                    End If
                    If r = 0 Then
                        nb = nb Or 8
                    ElseIf stBoard(b - 16 + c) <> 0 Then
                        nb = nb Or 8
                    End If
                    AddInst LB, Brick(v - 1, nb), c, RK_BOARD, r * ROW_H + ROW_H \ 2
                End If
            End If
        Next c
    Next r
End Sub

' the grid's row lines, where no block hides them
Private Sub BuildGrid()
    Dim r As Long, c As Long, below As Boolean, here As Boolean
    lN(LG) = 0
    For r = 0 To ST_ROWS
        For c = 0 To 15
            If r = 0 Then below = True Else below = stBoard((r - 1) * 16 + c) <> 0
            If below Then
                If r = ST_ROWS Then here = True Else here = stBoard(r * 16 + c) <> 0
            End If
            If Not (below And here) Then AddInst LG, mGridH, c, RK_GRID, r * ROW_H
        Next c
    Next r
End Sub

' the ghost, then the piece; and the drop guide (the piece's columns down to where it lands)
Private Sub BuildPiece(ByVal ghostRow As Long, ByVal guide As Boolean)
    Dim n As Long, k As Long, c As Long, r As Long, topR(0 To 15) As Long, botR(0 To 15) As Long
    lN(LP) = 0
    lN(LD) = 0
    If stOver <> 0 Then Exit Sub
    If svGhost <> 0 And ghostRow <> pRow Then
        n = StCellsOf(pType, pRot, pCol, ghostRow)
        For k = 0 To n - 1
            AddInst LP, Brick(17 + pType, PieceNb(n, k)), cellC(k), RK_GHOST, cellR(k) * ROW_H + ROW_H \ 2
        Next k
    End If
    n = StCellsOf(pType, pRot, pCol, pRow)
    For k = 0 To n - 1
        AddInst LP, Brick(9 + pType, PieceNb(n, k)), cellC(k), RK_PIECE, cellR(k) * ROW_H + ROW_H \ 2
    Next k
    If Not guide Then Exit Sub
    For c = 0 To 15: topR(c) = -1: botR(c) = 9999: Next c
    For k = 0 To n - 1
        If cellR(k) > topR(cellC(k)) Then topR(cellC(k)) = cellR(k)
    Next k
    n = StCellsOf(pType, pRot, pCol, ghostRow)
    For k = 0 To n - 1
        If cellR(k) < botR(cellC(k)) Then botR(cellC(k)) = cellR(k)
    Next k
    For c = 0 To 15
        If topR(c) >= 0 And botR(c) <= topR(c) Then
            For r = botR(c) To topR(c)
                AddInst LD, mGuide, c, RK_GUIDE, r * ROW_H + ROW_H \ 2
            Next r
        End If
    Next c
End Sub

' one frame of the tower; view: the column facing you (8.8)
Public Sub TowerDraw(ByVal view As Long, ByVal guide As Boolean)
    Dim vc As Long, gr As Long, key As String, a As Long
    vc = ((view + 128) \ 256) And 15
    If stOver = 0 Then gr = StGhostRow() Else gr = pRow
    If stBoardVer <> keyBoard Or vc <> keyCol Then
        BuildBoard vc
        keyCol = vc
    End If
    If stBoardVer <> keyBoard Then
        BuildGrid
        keyBoard = stBoardVer
        keyPiece = ""
    End If
    key = pType & "," & pRot & "," & pCol & "," & pRow & "," & gr & "," & guide & "," & stOver & "," & svGhost
    If key <> keyPiece Then
        BuildPiece gr, guide
        keyPiece = key
    End If
    ' the camera goes round the tower at 640, 300 up, looking down a little at the column
    ' facing you
    a = (view * 16) And 65535
    e3.CamPlace 640 * A3Sin(a), 300 * 65536, -640 * A3Cos(a)
    e3.CamAngles (-a) And 65535, 900
    towerPolys = 0
    ' the core is behind everything else: drawn first, in passes (its tall panels would
    ' otherwise sort in front of what lies low on them)
    e3.Begin 16000
    e3.DrawModels 16, mCore, coreX, coreY, coreZ, coreYaw
    e3.Flush
    towerPolys = towerPolys + e3.NPolys
    If lN(LD) > 0 Then
        e3.Begin 16000
        e3.DrawModels lN(LD), mGuide, dX, dY, dZ, dYaw
        e3.Flush
        towerPolys = towerPolys + e3.NPolys
    End If
    e3.Begin 16000
    e3.DrawModels 16, mGridV, gvX, gvY, gvZ, gvYaw
    e3.DrawModels lN(LG), mGridH, gX, gY, gZ, gYaw
    e3.Flush
    towerPolys = towerPolys + e3.NPolys
    e3.Begin 16000
    e3.DrawModels lN(LB), bId, bX, bY, bZ, bYaw
    e3.DrawModels lN(LP), pId, pX, pY, pZ, pYaw
    e3.DrawModels 16, mRing, ringX, ringY, ringZ, ringYaw
    e3.Flush
    towerPolys = towerPolys + e3.NPolys
End Sub
