' StDraw - Stack Tower's picture (amiga_mcp's examples/stack_tower/render.c): the tower in
' 3D (the core, every block as a brick sticking out of it, the falling piece and its ghost,
' the drop guide, the grid and the red line), the panel with the score, the next pieces,
' the held one and the unrolled map of the whole tower, and the title, help, high-score,
' pause and game-over screens. 320 x 256, the tower in x 0..199.
'
' Unlike render.c, which works out every corner with sin/cos each frame, the tower here is
' one static mesh of ~7400 world-space points (16 columns x the edges, radii and heights
' the bricks, grid, core and ring use), built once, that only turns about the y axis. Each
' frame draws face lists (4 point numbers and a pen a quad); the lists are rebuilt only
' when what they show changes (the board, the column facing you, the piece). So the
' per-frame BASIC is small, and the 3D work is in TowerDraw (StMesh.bas).
Option Explicit

' pens: 0 black, 1 white, 2 panel, 3 grey, 4 sky, 5-6 the core, 7 the red line, 8..23 the
' pieces (lit, shaded), 24-25 garbage, 26 ghost, 27 yellow, 28 cyan, 29 green, 30 orange, 31 dark
Public Const PEN_SKY As Long = 4
Public Const PEN_CORE As Long = 5
Public Const PEN_GUIDE As Long = 6
Public Const PEN_LINE As Long = 7
Public Const PEN_PIECE As Long = 8
Public Const PEN_GARBAGE As Long = 24
Public Const PEN_YELLOW As Long = 27
Public Const PEN_CYAN As Long = 28
Public Const PEN_GREEN As Long = 29
Public Const PEN_ORANGE As Long = 30
Public Const PEN_CORE_LINE As Long = 2

Public Const TOWER_R As Long = 140
Public Const ROW_H As Long = 26

' the screens (the form's state)
Public Const SS_TITLE As Long = 0
Public Const SS_PLAY As Long = 1
Public Const SS_OVER As Long = 2
Public Const SS_ENTRY As Long = 3
Public Const SS_SCORES As Long = 4

' the shell's state that the picture shows (stack.h's Stack)
Public svState As Long, svStateTimer As Long
Public svMode As Long, svStartLevel As Long
Public svView As Long                   ' the column facing you, 8.8, turning towards the piece
Public svGhost As Long, svPaused As Long, svHelp As Long
Public svFlash As String, svFlashTimer As Long
Public svBest(0 To 2) As Long
Public svEntryRank As Long, svEntryName As String, svTicks As Long
Public showPerf As Boolean
Public polyTotal As Double              ' polygons drawn, summed over frames (the bench)
Public profOn As Boolean                ' --prof: time the parts of a frame (ms, summed)
Public prSky As Double, prBuild As Double, prAdd As Double, prFlush As Double, prPanel As Double

' the mesh's point blocks (see MeshBuild)
Private Const VB0 As Long = 0           ' brick corners: (ri * 25 + row) * 16 + c, radii 140 162 168 146
Private Const VV0 As Long = 1600        ' bevels: (((ri * 24 + row) * 2 + yi) * 16 + c) * 2 + side, radii 163 169 147
Private Const VC0 As Long = 6208        ' the core: yi * 16 + c
Private Const VGV0 As Long = 6240       ' the grid's columns: (yi * 16 + c) * 2 + side
Private Const VGH0 As Long = 6304       ' the grid's rows: (r * 2 + yi) * 16 + c, r 0..20
Private Const VGD0 As Long = 6976       ' the drop guide: r * 16 + c, r 0..24
Private Const VR0 As Long = 7376        ' the red line: yi * 16 + c
Public Const MESH_N As Long = 7408

' face lists
Public Const L_CORE As Long = 0
Public Const L_GRID As Long = 1
Public Const L_BOARD As Long = 2
Public Const L_PIECE As Long = 3
Public Const L_RING As Long = 4
Public Const L_CAP As Long = 1700
Public fV(0 To 33999) As Long           ' 4 points a face, list * L_CAP * 4
Public fPen(0 To 8499) As Long
Public fBias(0 To 8499) As Long
Public fN(0 To 4) As Long

Private keyBoard As Long, keyBoardCol As Long
Private keyGrid As String
Private titleImg As Long, backImg As Long, artLoaded As Boolean, titleFrames As Long
Private helpText(1 To 2, 0 To 11) As String

Public Sub DrawInit(cv As Object)
    Dim v As Variant, i As Long
    StInit
    GfxPalette Array(&H0, &HFFF, &H223, &H99A, &H113, &H334, &H557, &HE22, _
                     &HE44, &H922, &HF92, &HA51, &HFE4, &HA92, &H5D4, &H283, _
                     &H4CE, &H278, &H46E, &H239, &HB5E, &H628, &HE6A, &H935, _
                     &H888, &H555, &H446, &HFE2, &H2EF, &H3F5, &HF82, &H111)
    MeshBuild
    TowerInit cv
    keyBoard = -1
    v = Array("PIECES LAND ON THE OUTSIDE OF A", "ROUND TOWER OF 16 COLUMNS. THERE ARE", _
              "NO SIDE WALLS: LEFT AND RIGHT TURN", "THE TOWER UNDER THE PIECE.", "", _
              "FILL A WHOLE RING TO CLEAR IT - THE", "BACK OF THE TOWER TOO. THE MAP SHOWS", _
              "THE WHOLE TOWER UNROLLED.", "", "MARATHON: FASTER EVERY 10 RINGS", _
              "RISING: RUBBLE PUSHES UP FROM BELOW", "DIG: CLEAR 10 RINGS OF RUBBLE")
    For i = 0 To 11: helpText(1, i) = v(i): Next i
    v = Array("LEFT / RIGHT   TURN THE TOWER", "UP / X         ROTATE CLOCKWISE", _
              "Z              ROTATE ANTICLOCKWISE", "DOWN           SOFT DROP", _
              "SPACE / FIRE   HARD DROP", "C / SHIFT      HOLD", "G              GHOST ON / OFF", _
              "P              PAUSE", "HELP / H       THESE PAGES", "ESC            TITLE / QUIT", _
              "", "SCORE: 100 300 600 1000 1500 x LEVEL")
    For i = 0 To 11: helpText(2, i) = v(i): Next i
End Sub

' ---------- the mesh ----------

' a point at column position colf (8.8 columns from column 0's middle), radius r, height y
Private Sub MeshPt(ByVal i As Long, ByVal colf As Long, ByVal r As Long, ByVal y As Long)
    Dim a As Long
    a = (colf * 16) And 65535
    MeshSet i, ShrA(A3Sin(a) * r, 16), y, -ShrA(A3Cos(a) * r, 16)
End Sub

Private Sub MeshBuild()
    Dim c As Long, ri As Long, row As Long, yi As Long, side As Long, e As Long, rad As Variant, r As Long
    rad = Array(140, 162, 168, 146)
    For ri = 0 To 3
        For row = 0 To 24
            For c = 0 To 15
                MeshPt VB0 + (ri * 25 + row) * 16 + c, c * 256 - 128, rad(ri), row * ROW_H
            Next c
        Next row
    Next ri
    rad = Array(163, 169, 147)
    For ri = 0 To 2
        For row = 0 To 23
            For yi = 0 To 1
                For c = 0 To 15
                    For side = 0 To 1
                        If side = 0 Then e = c * 256 - 128 + 44 Else e = c * 256 + 128 - 44
                        MeshPt VV0 + (((ri * 24 + row) * 2 + yi) * 16 + c) * 2 + side, e, rad(ri), _
                               row * ROW_H + IIf(yi = 0, 5, ROW_H - 5)
                    Next side
                Next c
            Next yi
        Next row
    Next ri
    For c = 0 To 15
        MeshPt VC0 + c, c * 256 - 128, TOWER_R - 3, -20
        MeshPt VC0 + 16 + c, c * 256 - 128, TOWER_R - 3, ST_ROWS * ROW_H + 30
        For yi = 0 To 1
            MeshPt VGV0 + (yi * 16 + c) * 2, c * 256 - 128 - 6, TOWER_R - 1, yi * ST_ROWS * ROW_H
            MeshPt VGV0 + (yi * 16 + c) * 2 + 1, c * 256 - 128 + 6, TOWER_R - 1, yi * ST_ROWS * ROW_H
            MeshPt VR0 + yi * 16 + c, c * 256, TOWER_R + 2, ST_ROWS * ROW_H - 2 + yi * 4
        Next yi
        For r = 0 To 20
            MeshPt VGH0 + (r * 2) * 16 + c, c * 256 - 128, TOWER_R - 1, r * ROW_H - 1
            MeshPt VGH0 + (r * 2 + 1) * 16 + c, c * 256 - 128, TOWER_R - 1, r * ROW_H + 1
        Next r
        For r = 0 To 24
            MeshPt VGD0 + r * 16 + c, c * 256 - 128, TOWER_R - 2, r * ROW_H
        Next r
    Next c
    ' the lists that never change: the core and the red line
    fN(L_CORE) = 0
    fN(L_RING) = 0
    For c = 0 To 15
        e = (c + 1) And 15
        AddFace L_CORE, VC0 + c, VC0 + 16 + c, VC0 + 16 + e, VC0 + e, PEN_CORE, 0
        AddFace L_RING, VR0 + c, VR0 + 16 + c, VR0 + 16 + e, VR0 + e, PEN_LINE, 0
    Next c
End Sub

Private Sub AddFace(ByVal l As Long, ByVal a As Long, ByVal b As Long, ByVal c As Long, ByVal d As Long, _
                    ByVal p As Long, ByVal bias As Long)
    Dim k As Long, i As Long
    k = fN(l)
    If k >= L_CAP Then Exit Sub
    i = l * L_CAP + k
    fV(i * 4) = a: fV(i * 4 + 1) = b: fV(i * 4 + 2) = c: fV(i * 4 + 3) = d
    fPen(i) = p
    fBias(i) = bias
    fN(l) = k + 1
End Sub

Private Function LitPen(ByVal v As Long) As Long
    If v = ST_GARBAGE Then LitPen = PEN_GARBAGE Else LitPen = PEN_PIECE + 2 * (v - 1)
End Function

Private Function Occupied(ByVal c As Long, ByVal r As Long) As Boolean
    If r < 0 Then
        Occupied = True                 ' the floor counts as a neighbour below
    ElseIf r < ST_TOTAL Then
        Occupied = stBoard(r * 16 + (c And 15)) <> 0
    End If
End Function

' one block: its outside face bevelled (a shaded rim round a lit centre), its top, and the
' sides that show; ri 1 = a board block, 2 = the piece, 3 = the ghost; nb: 1 left, 2 right,
' 4 up, 8 down neighbours (their shared faces are left out)
Private Sub AddBrick(ByVal l As Long, ByVal c As Long, ByVal row As Long, ByVal lit As Long, ByVal shade As Long, _
                     ByVal ri As Long, ByVal nb As Long)
    Dim cr As Long, p0 As Long, p1 As Long, p2 As Long, p3 As Long, p4 As Long, p5 As Long, p6 As Long, p7 As Long
    Dim q As Long
    cr = (c + 1) And 15
    p0 = VB0 + row * 16 + c: p1 = p0 - c + cr
    p3 = p0 + 16: p2 = p1 + 16
    p4 = p0 + ri * 400: p5 = p1 + ri * 400: p6 = p2 + ri * 400: p7 = p3 + ri * 400
    AddFace l, p4, p7, p6, p5, shade, 0                        ' outside: the rim
    If lit <> shade Then                                      ' and its lit centre, just in front
        q = VV0 + (((ri - 1) * 24 + row) * 2 * 16 + c) * 2
        AddFace l, q, q + 32, q + 33, q + 1, lit, -6
    End If
    If (nb And 4) = 0 Then AddFace l, p7, p3, p2, p6, lit, 0      ' top
    If (nb And 8) = 0 Then AddFace l, p4, p5, p1, p0, shade, 0    ' bottom
    If (nb And 1) = 0 Then AddFace l, p0, p3, p7, p4, shade, 0    ' left side
    If (nb And 2) = 0 Then AddFace l, p1, p5, p6, p2, shade, 0    ' right side
End Sub

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

' the blocks on the front half (rebuilt when the board or the column facing you changes)
Private Sub BuildBoard(ByVal vc As Long)
    Dim r As Long, c As Long, v As Long, d As Long, nb As Long
    fN(L_BOARD) = 0
    For r = 0 To ST_TOTAL - 1
        For c = 0 To 15
            v = stBoard(r * 16 + c)
            If v <> 0 Then
                d = ((c - vc + 24) And 15) - 8
                If d >= -5 And d <= 5 Then
                    nb = 0
                    If stBoard(r * 16 + ((c + 15) And 15)) <> 0 Then nb = 1
                    If stBoard(r * 16 + ((c + 1) And 15)) <> 0 Then nb = nb Or 2
                    If r < ST_TOTAL - 1 Then
                        If stBoard(r * 16 + 16 + c) <> 0 Then nb = nb Or 4
                    End If
                    If r = 0 Then
                        nb = nb Or 8
                    ElseIf stBoard(r * 16 - 16 + c) <> 0 Then
                        nb = nb Or 8
                    End If
                    AddBrick L_BOARD, c, r, LitPen(v), LitPen(v) + 1, 1, nb
                End If
            End If
        Next c
    Next r
End Sub

' the drop guide (the falling piece's columns down to where it lands) and the grid
Private Sub BuildGrid(ByVal vc As Long, ByVal guide As Boolean, ByVal ghostRow As Long)
    Dim topR(0 To 15) As Long, botR(0 To 15) As Long, c As Long, r As Long, k As Long, n As Long, e As Long, col As Long
    fN(L_GRID) = 0
    If guide Then
        For c = 0 To 15: topR(c) = -1: botR(c) = 9999: Next c
        n = StCellsOf(pType, pRot, pCol, pRow)
        For k = 0 To n - 1
            If cellR(k) > topR(cellC(k)) Then topR(cellC(k)) = cellR(k)
        Next k
        n = StCellsOf(pType, pRot, pCol, ghostRow)
        For k = 0 To n - 1
            If cellR(k) < botR(cellC(k)) Then botR(cellC(k)) = cellR(k)
        Next k
        For c = 0 To 15
            If topR(c) >= 0 And botR(c) <= topR(c) Then
                e = (c + 1) And 15
                For r = botR(c) To topR(c)
                    AddFace L_GRID, VGD0 + r * 16 + c, VGD0 + r * 16 + 16 + c, VGD0 + r * 16 + 16 + e, VGD0 + r * 16 + e, PEN_GUIDE, 0
                Next r
            End If
        Next c
    End If
    ' a thin line at every column's and row's edge on the front half, where no block hides it
    For k = -5 To 6
        c = (vc + k) And 15
        AddFace L_GRID, VGV0 + c * 2, VGV0 + (16 + c) * 2, VGV0 + (16 + c) * 2 + 1, VGV0 + c * 2 + 1, PEN_CORE_LINE, 0
    Next k
    For r = 0 To ST_ROWS
        For k = -5 To 5
            col = (vc + k) And 15
            If Occupied(col, r - 1) And (r = ST_ROWS Or Occupied(col, r)) Then
                ' hidden behind blocks
            Else
                e = (col + 1) And 15
                AddFace L_GRID, VGH0 + r * 32 + col, VGH0 + r * 32 + 16 + col, VGH0 + r * 32 + 16 + e, VGH0 + r * 32 + e, _
                        PEN_CORE_LINE, 0
            End If
        Next k
    Next r
End Sub

' the ghost, then the piece
Private Sub BuildPiece(ByVal ghostRow As Long)
    Dim n As Long, k As Long, lit As Long
    fN(L_PIECE) = 0
    If stOver <> 0 Then Exit Sub
    lit = LitPen(pType + 1)
    If svGhost <> 0 And ghostRow <> pRow Then
        n = StCellsOf(pType, pRot, pCol, ghostRow)
        For k = 0 To n - 1
            AddBrick L_PIECE, cellC(k), cellR(k), PEN_CORE, lit, 3, PieceNb(n, k)   ' an outline in the piece's colour
        Next k
    End If
    n = StCellsOf(pType, pRot, pCol, pRow)
    For k = 0 To n - 1
        AddBrick L_PIECE, cellC(k), cellR(k), lit, lit + 1, 2, PieceNb(n, k)
    Next k
End Sub

Public Sub DrawTower(cv As Object)
    Dim vc As Long, gr As Long, guide As Boolean, key As String
    vc = ((svView + 128) \ 256) And 15
    If stOver = 0 Then gr = StGhostRow() Else gr = pRow
    guide = stOver = 0 And svState = SS_PLAY
    Dim t As Double
    If profOn Then t = TimerMs()
    If stBoardVer <> keyBoard Or vc <> keyBoardCol Then
        BuildBoard vc
        keyBoard = stBoardVer
        keyBoardCol = vc
        keyGrid = ""
    End If
    key = vc & "," & pType & "," & pRot & "," & pCol & "," & pRow & "," & guide & "," & stOver & "," & svGhost
    If key <> keyGrid Then
        BuildGrid vc, guide, gr
        BuildPiece gr
        keyGrid = key
    End If
    ' the core is behind everything else: drawn first, in passes (its tall panels would
    ' otherwise sort in front of what lies low on them)
    If profOn Then prBuild = prBuild + TimerMs() - t: t = TimerMs()
    TowerBegin (svView * 16) And 65535
    TowerAdd L_CORE
    If profOn Then prAdd = prAdd + TimerMs() - t: t = TimerMs()
    TowerFlush cv
    If profOn Then prFlush = prFlush + TimerMs() - t: t = TimerMs()
    TowerAdd L_GRID
    If profOn Then prAdd = prAdd + TimerMs() - t: t = TimerMs()
    TowerFlush cv
    If profOn Then prFlush = prFlush + TimerMs() - t: t = TimerMs()
    TowerAdd L_BOARD
    TowerAdd L_PIECE
    TowerAdd L_RING
    If profOn Then prAdd = prAdd + TimerMs() - t: t = TimerMs()
    TowerFlush cv
    If profOn Then prFlush = prFlush + TimerMs() - t
    polyTotal = polyTotal + towerPolys
End Sub

' ---------- 2D ----------

' a piece as a little icon
Private Sub Icon(cv As Object, ByVal typ As Long, ByVal x As Long, ByVal y As Long, ByVal sz As Long)
    Dim i As Long, px As Long, py As Long
    If typ < 0 Then Exit Sub
    For i = 0 To stNCells(typ) - 1
        px = x + cellDx(typ * 20 + i) * sz
        py = y - cellDy(typ * 20 + i) * sz
        GRect cv, px, py, px + sz - 2, py + sz - 2, LitPen(typ + 1)
    Next i
End Sub

' the whole tower unrolled, centred on the piece
Private Sub DrawMap(cv As Object, ByVal x0 As Long, ByVal y0 As Long)
    Dim c As Long, r As Long, n As Long, k As Long, v As Long, mid As Long, c2 As Long, xs As Long, ys As Long
    mid = pCol
    GBox cv, x0 - 2, y0 - 2, x0 + ST_COLS * 3 + 1, y0 + ST_ROWS * 3 + 1, 0, 3
    For r = 0 To ST_ROWS - 1
        ys = y0 + (ST_ROWS - 1 - r) * 3
        For c = 0 To 15
            v = stBoard(r * 16 + ((mid - 8 + c) And 15))
            If v <> 0 Then cv.Box x0 + c * 3, ys, 2, 2, pen(LitPen(v))
        Next c
    Next r
    n = StCellsOf(pType, pRot, pCol, pRow)
    For k = 0 To n - 1
        c2 = (cellC(k) - mid + 8) And 15
        If cellR(k) < ST_ROWS Then cv.Box x0 + c2 * 3, y0 + (ST_ROWS - 1 - cellR(k)) * 3, 2, 2, pen(1)
    Next k
End Sub

Private Function ModeTitle(ByVal m As Long) As String
    ModeTitle = Choose(m + 1, "MARATHON", "RISING", "DIG")
End Function

Private Sub Panel(cv As Object)
    Dim q(0 To 2) As Long, k As Long
    cv.Box 200, 0, 120, G_H, pen(2)
    GText cv, 206, 12, 3, "SCORE"
    GText cv, 206, 24, 1, CStr(stScore)
    GText cv, 206, 40, PEN_YELLOW, "LEVEL " & stLevel
    If stMode = MODE_DIG Then GText cv, 206, 52, PEN_CYAN, "DIG " & stGarbageLeft Else GText cv, 206, 52, PEN_CYAN, "RINGS " & stLines
    GText cv, 206, 70, 3, "NEXT"
    StPreview 3, q
    For k = 0 To 2
        Icon cv, q(k), 222 + k * 30, 92, IIf(k = 0, 7, 5)
    Next k
    GText cv, 206, 112, 3, "HOLD"
    Icon cv, stHold, 230, 132, 6
    DrawMap cv, 236, 150
    GText cv, 206, 228, PEN_GREEN, ModeTitle(stMode)
    GText cv, 206, 242, 3, (stTimeMs \ 60000) & ":" & Format$((stTimeMs \ 1000) Mod 60, "00")
End Sub

Private Sub LoadArt(cv As Object)
    Dim d As String
    If artLoaded Then Exit Sub
    artLoaded = True
    d = ArtDir()
    On Error Resume Next
    backImg = cv.LoadImage(d & "st_backdrop.ppm")
    If Err.Number <> 0 Then backImg = 0
    Err.Clear
    titleImg = cv.LoadImage(d & "st_title.ppm")
    If Err.Number <> 0 Then titleImg = 0
    On Error GoTo 0
End Sub

' where the pictures are: beside the program (App.Path) or in the current directory
Private Function ArtDir() As String
    ArtDir = HsPath("")
End Function

Private Sub Sky(cv As Object)
    LoadArt cv
    If backImg <> 0 Then
        cv.DrawImage backImg, 0, 0, True
    Else
        cv.Box 0, 0, 200, G_H, pen(PEN_SKY)
    End If
End Sub

Public Sub TitleRestart()
    titleFrames = 0
End Sub

Public Sub DrawGame(cv As Object)
    Dim t As Double
    If profOn Then t = TimerMs()
    Sky cv
    If profOn Then prSky = prSky + TimerMs() - t
    DrawTower cv
    If profOn Then t = TimerMs()
    Panel cv
    If profOn Then prPanel = prPanel + TimerMs() - t
    If svState = SS_OVER Then
        GBox cv, 16, 90, 184, 160, 2, PEN_LINE
        If stWon <> 0 Then
            GTextBig cv, 28, 98, PEN_GREEN, "DUG OUT!", 2
        Else
            GTextBig cv, 28, 98, PEN_LINE, "TOPPED", 2
        End If
        GText cv, 40, 132, 1, "SCORE " & stScore
        If svStateTimer = 0 Then GText cv, 40, 150, PEN_YELLOW, "PRESS FIRE"
    End If
    If svPaused = 1 Then GTextShadow cv, (200 - cv.TextWidth("PAUSED")) \ 2, 120, 1, "PAUSED"
    If svFlashTimer > 0 And Len(svFlash) > 0 Then GTextShadow cv, (200 - cv.TextWidth(svFlash)) \ 2, 30, PEN_YELLOW, svFlash
End Sub

Public Sub DrawTitle(cv As Object)
    Dim p As Long
    LoadArt cv
    If (svTicks \ 12) And 1 Then p = PEN_YELLOW Else p = 1
    If titleImg <> 0 And titleFrames Mod 625 < 250 Then
        titleFrames = titleFrames + 1
        cv.DrawImage titleImg, 0, 0, True
        GTextCentre cv, 214, PEN_GREEN, "< " & ModeTitle(svMode) & " >   LEVEL " & svStartLevel & " (UP/DOWN)"
        GTextCentre cv, 230, p, "PRESS FIRE TO START"
        GTextCentre cv, 246, 3, "BEST " & svBest(svMode) & "    HELP: RULES"
        Exit Sub
    End If
    titleFrames = titleFrames + 1
    Sky cv
    DrawTower cv                        ' the demo game behind
    cv.Box 200, 0, 120, G_H, pen(2)
    GTextBig cv, 14, 14, 0, "STACK", 3
    GTextBig cv, 12, 12, PEN_YELLOW, "STACK", 3
    GTextBig cv, 14, 44, 0, "TOWER", 3
    GTextBig cv, 12, 42, PEN_CYAN, "TOWER", 3
    GText cv, 206, 30, 3, "MODE"
    GText cv, 206, 44, PEN_GREEN, "< " & ModeTitle(svMode) & " >"
    GText cv, 206, 66, 3, "LEVEL"
    GText cv, 206, 80, 1, "  " & svStartLevel & "  (UP/DOWN)"
    GText cv, 206, 110, 3, "BEST"
    GText cv, 206, 124, PEN_YELLOW, CStr(svBest(svMode))
    GText cv, 206, 200, p, "FIRE: START"
    GText cv, 206, 214, 3, "HELP: RULES"
    GText cv, 206, 242, 3, "AN AMIGA GAME"
End Sub

Public Sub DrawHelp(cv As Object, ByVal page As Long)
    Dim k As Long
    cv.Cls pen(0)
    If page = 1 Then GTextBig cv, 72, 14, PEN_CYAN, "HOW TO PLAY", 2 Else GTextBig cv, 96, 14, PEN_CYAN, "CONTROLS", 2
    For k = 0 To 11
        GText cv, 8, 58 + k * 14, 1, helpText(page, k)
    Next k
    GText cv, 8, 242, 3, "PAGE " & page & " OF 2"
    GText cv, 156, 242, PEN_YELLOW, "HELP: NEXT  FIRE: PLAY"
End Sub

Public Sub DrawEntry(cv As Object)
    Dim cur As String
    DrawGame cv
    GBox cv, 20, 70, 300, 180, 2, PEN_YELLOW
    GTextCentre cv, 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre cv, 110, 1, ModeTitle(stMode) & "   PLACE " & (HsRank(stScore) + 1) & "   " & stScore
    If (svTicks And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre cv, 140, PEN_GREEN, "YOUR NAME: " & svEntryName & cur
    GTextCentre cv, 166, 3, "RETURN TO CONFIRM"
End Sub

Public Sub DrawScores(cv As Object)
    Dim i As Long, p As Long
    DrawGame cv
    GBox cv, 40, 30, 280, 206, 2, 3
    GTextBig cv, (G_W - GTextBigWidth(cv, "HIGH SCORES", 2)) \ 2, 38, PEN_YELLOW, "HIGH SCORES", 2
    GTextCentre cv, 72, PEN_GREEN, ModeTitle(stMode)
    For i = 0 To HS_COUNT - 1
        If i = svEntryRank Then p = PEN_GREEN Else p = 1
        GTextCentre cv, 90 + i * 14, p, HsLine(i)
    Next i
End Sub

Public Sub DrawPerf(cv As Object)
    cv.Box 0, 0, 200, 11, pen(0)
    GText cv, 2, 9, PEN_GREEN, PerfText()
End Sub
