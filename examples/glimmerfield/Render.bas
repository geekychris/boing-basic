' Glimmerfield - drawing the game onto the playfield Canvas
'
' All drawing goes through the canvas object passed in, so this module is
' the only place that knows the Canvas control's method names.
Option Explicit

Public pal(0 To 31) As Long        ' colour per palette index (see InitRender)
Public showPerf As Boolean

Private starX(0 To 63) As Long
Private starY(0 To 63) As Long
Private starC(0 To 63) As Long
Private shapeR(0 To 3, 0 To 7) As Long    ' per hue, per vertex radius scale /256
Private renderReady As Boolean
Private partX(0 To 511) As Long
Private partY(0 To 511) As Long
Private partC(0 To 511) As Long
Private polyX(0 To 7) As Long
Private polyY(0 To 7) As Long


Public Sub InitRender()
    Dim i As Long, k As Long, s As Long
    If renderReady Then Exit Sub
    pal(0) = RGB(4, 6, 20)            ' background
    pal(COL_SPARK) = RGB(255, 255, 210)
    pal(COL_FLAME) = RGB(255, 150, 40)
    pal(COL_WISP) = RGB(120, 255, 170)
    pal(COL_SHIP) = RGB(230, 240, 255)
    pal(5) = RGB(70, 80, 120)          ' dim stars
    pal(6) = RGB(150, 160, 200)        ' bright stars
    pal(7) = RGB(255, 220, 90)         ' HUD
    pal(COL_HUE0 + 0) = RGB(110, 200, 255)   ' ice blue
    pal(COL_HUE0 + 1) = RGB(255, 110, 210)   ' rose
    pal(COL_HUE0 + 2) = RGB(190, 140, 255)   ' violet
    pal(COL_HUE0 + 3) = RGB(255, 210, 100)   ' amber
    ' 16..23: the same hues, darker, for fading particles
    pal(16) = RGB(40, 40, 50)
    pal(17) = RGB(110, 100, 70)
    pal(18) = RGB(110, 60, 20)
    pal(19) = RGB(40, 110, 70)
    pal(20) = RGB(90, 90, 110)
    pal(24) = RGB(40, 80, 110)
    pal(25) = RGB(110, 40, 90)
    pal(26) = RGB(80, 60, 110)
    pal(27) = RGB(110, 90, 40)
    pal(28) = RGB(255, 80, 80)          ' warnings
    ' a fixed starfield, from its own seed so the game's sequence is untouched
    s = rngSeed
    SeedRng 4242
    For i = 0 To 63
        starX(i) = RandL(ARENA_W)
        starY(i) = RandL(ARENA_H)
        starC(i) = 5 + RandL(2)
    Next i
    For i = 0 To 3
        For k = 0 To 7
            shapeR(i, k) = 190 + RandL(66)
        Next k
    Next i
    rngSeed = s
    renderReady = True
End Sub

' faded colour for a particle of colour c with life left
Private Function PartColour(ByVal c As Long, ByVal life As Long) As Long
    If life > 10 Then
        PartColour = pal(c)
    Else
        PartColour = pal(16 + c)
    End If
End Function

' a crystal: a filled polygon in a dark tone of its hue, bright edges, and a facet line
Private Sub DrawShardAt(cv As Object, ByVal i As Long, ByVal sx As Long, ByVal sy As Long)
    Dim n As Long, k As Long, r As Long, a As Long, h As Long, rr As Long
    n = 3 + 2 * shards(i).size - (shards(i).size \ 3)     ' 5, 7, 8 sides
    r = ShardRadius(shards(i).size)
    h = shards(i).hue
    For k = 0 To n - 1
        a = shards(i).ang + (k * 256) \ n
        rr = r * shapeR(h, k) \ 256
        polyX(k) = sx + CosA(a) * rr \ 256
        polyY(k) = sy + SinA(a) * rr \ 256
    Next k
    cv.Polygon polyX, polyY, n, pal(24 + h), True
    cv.Polygon polyX, polyY, n, pal(COL_HUE0 + h)
    cv.Line sx, sy, polyX(0), polyY(0), pal(COL_HUE0 + h)
End Sub

Private Sub DrawShards(cv As Object)
    Dim i As Long, sx As Long, sy As Long, r As Long
    For i = 0 To MAX_SHARDS - 1
        If shards(i).active Then
            sx = shards(i).x \ FP
            sy = shards(i).y \ FP
            r = ShardRadius(shards(i).size)
            DrawShardAt cv, i, sx, sy
            ' draw again on the far side when it straddles an edge
            If sx < r Then DrawShardAt cv, i, sx + ARENA_W, sy
            If sx > ARENA_W - r Then DrawShardAt cv, i, sx - ARENA_W, sy
            If sy < r Then DrawShardAt cv, i, sx, sy + ARENA_H
            If sy > ARENA_H - r Then DrawShardAt cv, i, sx, sy - ARENA_H
        End If
    Next i
End Sub

Private Sub DrawShip(cv As Object)
    Dim x As Long, y As Long, a As Long, c As Long
    Dim nx As Long, ny As Long, lx As Long, ly As Long, rx As Long, ry As Long
    If Not ship.alive Then Exit Sub
    If ship.shield > 0 And (frame And 4) <> 0 Then Exit Sub
    x = ship.x \ FP
    y = ship.y \ FP
    a = ship.ang
    nx = x + CosA(a) * 10 \ 256
    ny = y + SinA(a) * 10 \ 256
    lx = x + CosA(a + 100) * 7 \ 256
    ly = y + SinA(a + 100) * 7 \ 256
    rx = x + CosA(a - 100) * 7 \ 256
    ry = y + SinA(a - 100) * 7 \ 256
    c = pal(COL_SHIP)
    polyX(0) = nx: polyY(0) = ny
    polyX(1) = lx: polyY(1) = ly
    polyX(2) = x: polyY(2) = y
    polyX(3) = rx: polyY(3) = ry
    cv.Polygon polyX, polyY, 4, pal(20), True
    cv.Polygon polyX, polyY, 4, c
    If ship.thrust And (frame And 2) <> 0 Then
        cv.Line x, y, x - CosA(a) * 9 \ 256, y - SinA(a) * 9 \ 256, pal(COL_FLAME)
    End If
    If ship.shield > 0 Then cv.Circle x, y, 13, pal(COL_WISP)
End Sub

Private Sub DrawWisps(cv As Object)
    Dim i As Long, x As Long, y As Long, r As Long
    For i = 0 To MAX_WISPS - 1
        If wisps(i).active Then
            x = wisps(i).x \ FP
            y = wisps(i).y \ FP
            r = 4 + (SinA(wisps(i).phase * 2) + 256) \ 128
            cv.Circle x, y, r + 2, pal(19)
            cv.Circle x, y, r, pal(COL_WISP), True
            cv.Box x - 1, y - 1, 3, 3, pal(COL_SPARK)
            If wisps(i).hp < 3 Then cv.Circle x, y, r + 3, pal(19)
        End If
    Next i
End Sub

Private Sub DrawBullets(cv As Object)
    Dim i As Long
    For i = 0 To MAX_BULLETS - 1
        If bullets(i).active Then
            cv.Box bullets(i).x \ FP - 1, bullets(i).y \ FP - 1, 2, 2, pal(COL_SPARK)
        End If
    Next i
End Sub

' particles go to the canvas in one call (PSetMany) instead of one PSet each
Private Sub DrawParts(cv As Object)
    Dim i As Long, n As Long
    For i = 0 To MAX_PARTS - 1
        If parts(i).life > 0 Then
            partX(n) = CLng(parts(i).x)
            partY(n) = CLng(parts(i).y)
            partC(n) = PartColour(parts(i).col, parts(i).life)
            n = n + 1
        End If
    Next i
    If n > 0 Then cv.PSetMany partX, partY, partC, n, 2
End Sub

Private Sub DrawPops(cv As Object)
    Dim i As Long
    For i = 0 To MAX_POPS - 1
        If pops(i).life > 0 Then
            If pops(i).life > 8 Or (pops(i).life And 1) = 0 Then
                cv.DrawText pops(i).x, pops(i).y, pops(i).msg, pal(7)
            End If
        End If
    Next i
End Sub

' the whole playfield: background, objects and the HUD line
Public Sub DrawWorld(cv As Object)
    Dim i As Long
    cv.Cls pal(0)
    For i = 0 To 63
        cv.PSet starX(i), starY(i), pal(starC(i))
    Next i
    DrawParts cv
    DrawShards cv
    DrawWisps cv
    DrawBullets cv
    DrawShip cv
    DrawPops cv
    cv.DrawText 4, 2, HudText(), pal(7)
    If showPerf Then cv.DrawText 4, ARENA_H - 12, PerfText(), pal(6)
End Sub

Public Sub DrawCentred(cv As Object, ByVal y As Long, ByVal s As String, ByVal c As Long)
    cv.DrawText (ARENA_W - cv.TextWidth(s)) \ 2, y, s, c
End Sub
