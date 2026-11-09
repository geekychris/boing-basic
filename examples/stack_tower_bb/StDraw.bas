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
Public prSky As Double, prTower As Double, prPanel As Double

Private mapImg As Long, mapKey As Long
Private titleImg As Long, backImg As Long, artLoaded As Boolean, titleFrames As Long
Private helpText(1 To 2, 0 To 11) As String

Public Sub DrawInit(cv As Object)
    Dim v As Variant, i As Long
    StInit
    v = Array(&H0, &HFFF, &H223, &H99A, &H113, &H334, &H557, &HE22, _
              &HE44, &H922, &HF92, &HA51, &HFE4, &HA92, &H5D4, &H283, _
              &H4CE, &H278, &H46E, &H239, &HB5E, &H628, &HE6A, &H935, _
              &H888, &H555, &H446, &HFE2, &H2EF, &H3F5, &HF82, &H111)
    GfxPalette v
    TowerInit cv, v
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

Private Function LitPen(ByVal v As Long) As Long
    If v = ST_GARBAGE Then LitPen = PEN_GARBAGE Else LitPen = PEN_PIECE + 2 * (v - 1)
End Function

Public Sub DrawTower(cv As Object)
    Dim t As Double
    If profOn Then t = TimerMs()
    TowerDraw svView, stOver = 0 And svState = SS_PLAY
    If profOn Then prTower = prTower + TimerMs() - t
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

' the whole tower unrolled, centred on the piece (drawn into an image when it changes)
Private Sub DrawMap(cv As Object, ByVal x0 As Long, ByVal y0 As Long)
    Dim c As Long, r As Long, n As Long, k As Long, v As Long, mid As Long, c2 As Long, ys As Long, key As Long
    key = (((stBoardVer And &HFFFFF) * 16 + pCol) * 32 + (pRow And 31)) * 32 + pType * 4 + pRot
    If mapImg = 0 Or key <> mapKey Then
        If mapImg = 0 Then mapImg = cv.CreateImage(ST_COLS * 3 + 4, ST_ROWS * 3 + 4)
        cv.SetTarget mapImg
        cv.Box 0, 0, ST_COLS * 3 + 4, ST_ROWS * 3 + 4, pen(0)
        cv.Rect 0, 0, ST_COLS * 3 + 4, ST_ROWS * 3 + 4, pen(3)
        mid = pCol
        For r = 0 To ST_ROWS - 1
            ys = 2 + (ST_ROWS - 1 - r) * 3
            For c = 0 To 15
                v = stBoard(r * 16 + ((mid - 8 + c) And 15))
                If v <> 0 Then cv.Box 2 + c * 3, ys, 2, 2, pen(LitPen(v))
            Next c
        Next r
        n = StCellsOf(pType, pRot, pCol, pRow)
        For k = 0 To n - 1
            c2 = (cellC(k) - mid + 8) And 15
            If cellR(k) < ST_ROWS Then cv.Box 2 + c2 * 3, 2 + (ST_ROWS - 1 - cellR(k)) * 3, 2, 2, pen(1)
        Next k
        cv.SetTarget 0
        mapKey = key
    End If
    cv.DrawImage mapImg, x0 - 2, y0 - 2, True
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
