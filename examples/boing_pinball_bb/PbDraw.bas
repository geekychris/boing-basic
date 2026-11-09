' PbDraw - Boing Pinball's drawing on a 640 x 512 Canvas (a port of render.c's
' AmigaOS 4 path). The table is seen from the player's end, tilted: a millimetre
' across is 1.1 pixels, one up the table 0.88 and one of height 0.66 (heights go up
' the screen). Everything that doesn't move is drawn once, when a table is chosen,
' into a 640 x 1024 picture (an image of the Canvas): the painted playfield, the
' unlit inserts, the walls, posts, bumpers and the see-through ramps. Each frame
' copies the 448 rows in view under the dot-matrix display (one DrawImagePart) and
' draws what moves over it.
'
' The C draws what moves with spans and blends every frame; here those are made
' once too: a lit lamp, a flashing bumper or sling and a standing drop target are
' patches cut from the picture with the glow blended in, the flippers are sprites
' at 40 angles each, the Boing ball 8 sprites of its spin. So a frame is about 40
' Canvas calls, whatever the interpreter's speed.
Option Explicit

Public Const SCR_W As Long = 640
Public Const SCR_H As Long = 512
Public Const PIC_H As Long = 1024               ' the picture's rows (512 of the game's)
Public Const VIEW_Y As Long = 64                ' the screen row the table starts at
Public Const VIEW_H As Long = 448
Public Const CAM_MAX As Long = 288              ' in the game's rows (2 pixels each)

' the pens
Public Const P_BLACK As Long = 0
Public Const P_FIELD1 As Long = 1
Public Const P_FIELD2 As Long = 2
Public Const P_ART1 As Long = 3
Public Const P_ART2 As Long = 4
Public Const P_ART3 As Long = 5
Public Const P_METAL_D As Long = 6
Public Const P_METAL_L As Long = 7
Public Const P_CAB_D As Long = 8
Public Const P_CAB_L As Long = 9
Public Const P_RUBBER As Long = 10
Public Const P_RUBBER_D As Long = 11
Public Const P_RED As Long = 12
Public Const P_RED_D As Long = 13
Public Const P_FLASH As Long = 14
Public Const P_SHADOW As Long = 15
Public Const P_BLUE As Long = 16
Public Const P_BLUE_D As Long = 17
Public Const P_YEL As Long = 18
Public Const P_YEL_D As Long = 19
Public Const P_LRED As Long = 20
Public Const P_LRED_D As Long = 21
Public Const P_GREEN As Long = 22
Public Const P_MAG As Long = 23
Public Const P_ORANGE As Long = 24
Public Const P_DIM As Long = 25
Public Const P_DMD_BG As Long = 26
Public Const P_DMD_ON As Long = 27
Public Const P_DMD_MID As Long = 28
Public Const P_GLASS As Long = 29
Public Const P_WOOD As Long = 30
Public Const P_TEXT As Long = 31

Private Const KXS As Long = 72088               ' FX(0.55) * 2
Private Const KYS As Long = 57670               ' FX(0.44) * 2
Private Const KZS As Long = 43252               ' FX(0.33) * 2
Private Const BR As Long = 14                   ' the ball's radius, pixels
Private Const NFRAMES As Long = 40              ' flipper sprites per flipper

Public CV As Object                              ' the Canvas
Public penC(0 To 31) As Long                    ' the pens' colours (VB &HBBGGRR)
Public dTable As Long                           ' the table drawn, -1 none
Public cam As Long                              ' the picture row (game rows) at the top of the view
Public animFrame As Long                        ' 25 a second, as the C's frame counter
Public bumperFlash(0 To 15) As Long
Public slingFlash(0 To 1) As Long
Public bestScore As Long                        ' the chosen table's best, for the title and game over
Public buildLoadMs As Double, buildPaintMs As Double, buildRampMs As Double, buildPatchMs As Double

Public dbgLog As String                         ' a file: DbgMark writes each step to it (for finding a crash)
Private picImg As Long
Private scratch As Long                         ' a picture-sized image for blending, while a table is built
Private titleImg(0 To 2) As Long
Private fieldPainted As Boolean
Private oyR As Long                             ' picture row -> drawing row, game rows
Private orgX As Long, orgY As Long              ' the patch being drawn's top left in the picture
Private patchImg(0 To 255) As Long
Private patchX(0 To 255) As Long
Private patchY(0 To 255) As Long
Private Const PT_LAMP As Long = 0               ' + lamp
Private Const PT_BUMPER As Long = 32            ' + circle
Private Const PT_SLING As Long = 48             ' + sling id
Private Const PT_DROP As Long = 50              ' + drop
Private Const PT_FLIP As Long = 66              ' + flipper * NFRAMES + frame
Private Const PT_KNOB As Long = 190
Private Const PT_SHADOW As Long = 191
Private Const PT_BALL As Long = 192             ' + frame
Private flipLo(0 To 2) As Long, flipHi(0 To 2) As Long
Private ballPhase(0 To 7) As Long
Private ballPX(0 To 7) As Long, ballPY(0 To 7) As Long
Private glyphImg(0 To 6079) As Long              ' ((pen * 2) + sc - 1) * 95 + char - 32
Private dmdGlyph(0 To 759) As Long               ' (size * 2 + bright) * 95 + char - 32
Private dmdBits(0 To 759) As Long                ' (char - 32) * 8 + row: 8 bits, bit 7 left
Private dmdImg As Long
Private dmdKey As String
Private lineCache As Collection
Private lineCount As Long
Private xsA(0 To 63) As Long, ysA(0 To 63) As Long
Private rowBuf(0 To 639) As Long
Private drawReady As Boolean

' ================================================================ set-up

Private Function Rgb12(ByVal v As Long) As Long
    Rgb12 = RGB(((v \ 256) And 15) * 17, ((v \ 16) And 15) * 17, (v And 15) * 17)
End Function

Public Sub DrawPalette(ByVal theme As Long)
    Dim c As Variant, t As Variant, i As Long
    c = Array(&H0, &H213, &H324, &H436, &H547, &HA86, &H667, &HCCD, &H413, &H736, &HFFE, &H999, &HE22, &H811, &HFF8, &H101, _
              &H5BF, &H235, &HFD4, &H542, &HF54, &H522, &H6F9, &HF4F, &HFB2, &H443, &H210, &HFA2, &H741, &H8CF, &H631, &HFFF)
    For i = 0 To 31
        penC(i) = Rgb12(c(i))
    Next i
    ' per table: field1 field2 art1 art2 art3 cab_d cab_l shadow wood
    Select Case theme
        Case TB_DEEP: t = Array(&H24, &H35, &H47, &HA9, &HEC8, &H134, &H368, &H12, &H234)
        Case TB_FOUNDRY: t = Array(&H322, &H433, &H544, &H765, &HDA2, &H333, &H777, &H111, &H421)
        Case Else: t = Array(&H213, &H324, &H436, &H547, &HA86, &H413, &H736, &H102, &H631)
    End Select
    penC(P_FIELD1) = Rgb12(t(0)): penC(P_FIELD2) = Rgb12(t(1))
    penC(P_ART1) = Rgb12(t(2)): penC(P_ART2) = Rgb12(t(3)): penC(P_ART3) = Rgb12(t(4))
    penC(P_CAB_D) = Rgb12(t(5)): penC(P_CAB_L) = Rgb12(t(6))
    penC(P_SHADOW) = Rgb12(t(7)): penC(P_WOOD) = Rgb12(t(8))
End Sub

' the 8 x 8 dot-matrix characters: the 16 x 16 font halved (a dot where 2 or more of its 4 pixels are set)
Private Sub MakeDmdBits()
    Dim c As Long, r As Long, b As Long, v As Long, a0 As Long, a1 As Long, n As Long, w As Long
    For c = 0 To 94
        For r = 0 To 7
            a0 = fontRow(c * 16 + r * 2) And &HFFFF&
            a1 = fontRow(c * 16 + r * 2 + 1) And &HFFFF&
            v = 0
            For b = 0 To 7
                w = 2 ^ (14 - b * 2)
                n = 0
                If a0 And w Then n = n + 1
                If a0 And (w * 2) Then n = n + 1
                If a1 And w Then n = n + 1
                If a1 And (w * 2) Then n = n + 1
                If n >= 2 Then v = v Or (2 ^ (7 - b))
            Next b
            dmdBits(c * 8 + r) = v
        Next r
    Next c
End Sub

' a picture beside the program (art/NAME.png: the Canvas reads PNG itself everywhere); 0 if missing
Public Function LoadArt(ByVal nm As String) As Long
    Dim base As String
    base = App.Path
    If Len(base) > 0 And Right$(base, 1) <> "/" And Right$(base, 1) <> ":" Then base = base & "/"
    On Error Resume Next
    LoadArt = 0
    LoadArt = CV.LoadImage(base & "art/" & nm & ".png")
    If Err.Number <> 0 Then LoadArt = 0
    On Error GoTo 0
End Function

Public Sub DrawInit(cvObj As Object)
    Set CV = cvObj
    If drawReady Then Exit Sub
    FontInit
    MakeDmdBits
    Set lineCache = New Collection
    dTable = -1
    DrawPalette TB_COMET
    picImg = CV.CreateImage(SCR_W, PIC_H)
    dmdImg = CV.CreateImage(SCR_W, VIEW_Y)
    MakeBall
    drawReady = True
End Sub

Public Sub DbgMark(ByVal s As String)
    Dim f As Integer
    If Len(dbgLog) = 0 Then Exit Sub
    f = FreeFile
    Open dbgLog For Append As #f
    Print #f, s
    Close #f
End Sub

' ================================================================ coordinates

Private Function FIr(ByVal a As Long) As Long
    FIr = (a - (a And 65535)) \ 65536
End Function

Private Function FMr(ByVal a As Long, ByVal b As Long) As Long
    FMr = Int(CDbl(a) * b / 65536#)
End Function

' table mm (16.16) -> the drawing's pixels
Private Function PXf(ByVal x As Long) As Long
    PXf = 34 + FIr(FMr(x, KXS) + 32768)
End Function

Private Function PYf(ByVal y As Long, ByVal z As Long) As Long
    PYf = (478 + oyR) * 2 - FIr(FMr(y, KYS) + FMr(z, KZS) + 32768)
End Function

Private Function PXI(ByVal x As Long) As Long
    PXI = PXf(x * 65536)
End Function

Private Function PYI(ByVal y As Long, ByVal z As Long) As Long
    PYI = PYf(y * 65536, z * 65536)
End Function

Private Function RXf(ByVal r As Long) As Long
    Dim v As Long
    v = FIr(FMr(r, KXS) + 32768)
    If v < 1 Then v = 1
    RXf = v
End Function

Private Function RYf(ByVal r As Long) As Long
    Dim v As Long
    v = FIr(FMr(r, KYS) + 32768)
    If v < 1 Then v = 1
    RYf = v
End Function

Private Function ISq(ByVal v As Long) As Long
    Dim r As Long
    If v <= 0 Then Exit Function
    r = Int(Sqr(v))
    If CDbl(r) * r > v Then r = r - 1
    If CDbl(r + 1) * (r + 1) <= v Then r = r + 1
    ISq = r
End Function

' ================================================================ primitives (picture pixels, minus the patch origin)

Private Sub Span(ByVal y As Long, ByVal xl As Long, ByVal xr As Long, ByVal pen As Long)
    CV.Line xl - orgX, y - orgY, xr - orgX, y - orgY, penC(pen)
End Sub

Private Sub RectP(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal pen As Long)
    If x1 < x0 Or y1 < y0 Then Exit Sub
    CV.Box x0 - orgX, y0 - orgY, x1 - x0 + 1, y1 - y0 + 1, penC(pen)
End Sub

Private Sub Ellipse(ByVal cx As Long, ByVal cy As Long, ByVal rx As Long, ByVal ry As Long, ByVal pen As Long)
    Dim dy As Long, w As Long
    If rx < 1 Then rx = 1
    If ry < 1 Then ry = 1
    For dy = -ry To ry
        w = (rx * ISq((ry * ry - dy * dy) * 256) + ry * 8) \ (ry * 16)
        Span cy + dy, cx - w, cx + w, pen
    Next dy
End Sub

' see-through: alpha 0..256 over what is in src (the picture) at the same place
Private Sub BlendSpan(ByVal src As Long, ByVal y As Long, ByVal xl As Long, ByVal xr As Long, ByVal pen As Long, ByVal alpha As Long)
    Dim x As Long, v As Long, k As Long, cr As Long, cg As Long, cb As Long, dst As Long
    If xl < 0 Then xl = 0
    If xr > SCR_W - 1 Then xr = SCR_W - 1
    If xl > xr Or alpha <= 0 Then Exit Sub
    cr = penC(pen) And 255: cg = (penC(pen) \ 256) And 255: cb = (penC(pen) \ 65536) And 255
    k = 256 - alpha
    dst = CV.Target
    If dst <> src Then CV.SetTarget src
    For x = xl To xr
        rowBuf(x) = CV.Point(x, y)
    Next x
    If dst <> src Then CV.SetTarget dst
    For x = xl To xr
        v = rowBuf(x)
        If v >= 0 Then
            CV.PSet x - orgX, y - orgY, RGB(((v And 255) * k + cr * alpha) \ 256, (((v \ 256) And 255) * k + cg * alpha) \ 256, _
                                       (((v \ 65536) And 255) * k + cb * alpha) \ 256)
        End If
    Next x
End Sub

Private Sub BlendEllipse(ByVal src As Long, ByVal cx As Long, ByVal cy As Long, ByVal rx As Long, ByVal ry As Long, _
                         ByVal pen As Long, ByVal alpha As Long)
    Dim dst As Long, ox As Long, oy As Long
    If rx < 1 Then rx = 1
    If ry < 1 Then ry = 1
    If scratch = 0 Then                             ' (no scratch image: pixel by pixel)
        Dim dy As Long, w As Long
        For dy = -ry To ry
            w = (rx * ISq((ry * ry - dy * dy) * 256) + ry * 8) \ (ry * 16)
            If cy + dy >= 0 And cy + dy < PIC_H Then BlendSpan src, cy + dy, cx - w, cx + w, pen, alpha
        Next dy
        Exit Sub
    End If
    dst = CV.Target: ox = orgX: oy = orgY
    CV.SetTarget scratch: orgX = 0: orgY = 0
    Ellipse cx, cy, rx, ry, pen
    orgX = ox: orgY = oy
    ScratchBlend dst, cx - rx, cy - ry, cx + rx, cy + ry, alpha
End Sub

' what was drawn into the scratch image between x0..x1, y0..y1 (picture pixels), blended onto
' target dst at alpha/256, then cleared from the scratch
Private Sub ScratchBlend(ByVal dst As Long, ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal alpha As Long)
    If x0 < 0 Then x0 = 0
    If y0 < 0 Then y0 = 0
    If x1 > SCR_W - 1 Then x1 = SCR_W - 1
    If y1 > PIC_H - 1 Then y1 = PIC_H - 1
    If x0 > x1 Or y0 > y1 Then
        CV.SetTarget dst
        Exit Sub
    End If
    CV.SetTarget dst
    CV.DrawImageBlend scratch, x0 - orgX, y0 - orgY, (alpha * 255) \ 256, x0, y0, x1 - x0 + 1, y1 - y0 + 1
    CV.SetTarget scratch
    CV.ClearRect x0, y0, x1 - x0 + 1, y1 - y0 + 1
    CV.SetTarget dst
End Sub

' a line w of the game's pixels thick (squares stamped along it)
Private Sub ThickLine(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal pen As Long, ByVal w As Long)
    Dim dx As Long, dy As Long, sx As Long, sy As Long, er As Long, h As Long, e2 As Long, c As Long
    dx = Abs(x1 - x0): dy = Abs(y1 - y0)
    If x0 < x1 Then sx = 1 Else sx = -1
    If y0 < y1 Then sy = 1 Else sy = -1
    er = dx - dy
    w = w * 2
    h = w \ 2
    c = penC(pen)
    Do
        CV.Box x0 - h - orgX, y0 - h - orgY, w, w, c
        If x0 = x1 And y0 = y1 Then Exit Do
        e2 = 2 * er
        If e2 > -dy Then er = er - dy: x0 = x0 + sx
        If e2 < dx Then er = er + dx: y0 = y0 + sy
    Loop
End Sub

Private Function Cross(ByVal ox As Long, ByVal oy As Long, ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long) As Long
    Cross = (ax - ox) * (by - oy) - (ay - oy) * (bx - ox)
End Function

' the convex hull of n (<= 8) points of xsA/ysA (Andrew's monotone chain), filled
Private Sub HullFill(ByVal n As Long, ByVal pen As Long)
    Dim i As Long, j As Long, k As Long, t As Long, idx(0 To 7) As Long, hx(0 To 16) As Long, hy(0 To 16) As Long
    For i = 0 To n - 1
        idx(i) = i
    Next i
    For i = 1 To n - 1
        j = i
        Do While j > 0
            If xsA(idx(j)) < xsA(idx(j - 1)) Or (xsA(idx(j)) = xsA(idx(j - 1)) And ysA(idx(j)) < ysA(idx(j - 1))) Then
                t = idx(j): idx(j) = idx(j - 1): idx(j - 1) = t
                j = j - 1
            Else
                Exit Do
            End If
        Loop
    Next i
    For i = 0 To n - 1
        Do While k >= 2
            If Cross(hx(k - 2), hy(k - 2), hx(k - 1), hy(k - 1), xsA(idx(i)), ysA(idx(i))) > 0 Then Exit Do
            k = k - 1
        Loop
        hx(k) = xsA(idx(i)): hy(k) = ysA(idx(i)): k = k + 1
    Next i
    j = k + 1
    For i = n - 2 To 0 Step -1
        Do While k >= j
            If Cross(hx(k - 2), hy(k - 2), hx(k - 1), hy(k - 1), xsA(idx(i)), ysA(idx(i))) > 0 Then Exit Do
            k = k - 1
        Loop
        hx(k) = xsA(idx(i)): hy(k) = ysA(idx(i)): k = k + 1
    Next i
    k = k - 1
    If k < 1 Then Exit Sub
    If k < 3 Then
        If k > 1 Then ThickLine hx(0), hy(0), hx(1), hy(1), pen, 1 Else ThickLine hx(0), hy(0), hx(0), hy(0), pen, 1
        Exit Sub
    End If
    Dim px(0 To 15) As Long, py(0 To 15) As Long
    For i = 0 To k - 1
        If i < 16 Then px(i) = hx(i) - orgX: py(i) = hy(i) - orgY
    Next i
    If k > 16 Then k = 16
    CV.Polygon px, py, k, penC(pen), True
End Sub

Private Sub Quad(ByVal pen As Long)
    Dim i As Long, px(0 To 3) As Long, py(0 To 3) As Long
    For i = 0 To 3
        px(i) = xsA(i) - orgX: py(i) = ysA(i) - orgY
    Next i
    CV.Polygon px, py, 4, penC(pen), True
End Sub

' a convex polygon of xsA/ysA (picture pixels), see-through
Private Sub BlendPoly(ByVal src As Long, ByVal n As Long, ByVal pen As Long, ByVal alpha As Long)
    Dim i As Long, x0 As Long, y0 As Long, x1 As Long, y1 As Long, dst As Long, ox As Long, oy As Long
    Dim px(0 To 7) As Long, py(0 To 7) As Long
    x0 = xsA(0): x1 = xsA(0): y0 = ysA(0): y1 = ysA(0)
    For i = 0 To n - 1
        If xsA(i) < x0 Then x0 = xsA(i)
        If xsA(i) > x1 Then x1 = xsA(i)
        If ysA(i) < y0 Then y0 = ysA(i)
        If ysA(i) > y1 Then y1 = ysA(i)
        px(i) = xsA(i): py(i) = ysA(i)
    Next i
    dst = CV.Target: ox = orgX: oy = orgY
    CV.SetTarget scratch
    CV.Polygon px, py, n, penC(pen), True
    ScratchBlend dst, x0, y0, x1, y1, alpha
End Sub

' a capsule wall from a to b, radius r, h mm high: its sides, then its top
Private Sub Wall3d(ByVal ax As Long, ByVal ay As Long, ByVal bx As Long, ByVal by As Long, ByVal r As Long, ByVal h As Long, _
                   ByVal side As Long, ByVal top As Long)
    Dim ex As Long, ey As Long, ln As Long, nx As Long, ny As Long, hh As Long, i As Long, mx As Long, my As Long
    Dim cx(0 To 3) As Long, cy(0 To 3) As Long
    ex = bx - ax: ey = by - ay
    ln = FHypot(ex, ey)
    hh = h * 65536
    If ln < 16384 Then
        nx = r: ny = 0
    Else
        nx = FMr(-FDiv(ey, ln), r): ny = FMr(FDiv(ex, ln), r)
    End If
    If ln > 19660800 Then                           ' long walls in pieces
        mx = (ax + bx) \ 2: my = (ay + by) \ 2
        Wall3d ax, ay, mx, my, r, h, side, top
        Wall3d mx, my, bx, by, r, h, side, top
        Exit Sub
    End If
    cx(0) = ax + nx: cy(0) = ay + ny: cx(1) = ax - nx: cy(1) = ay - ny
    cx(2) = bx + nx: cy(2) = by + ny: cx(3) = bx - nx: cy(3) = by - ny
    For i = 0 To 3
        xsA(i) = PXf(cx(i)): ysA(i) = PYf(cy(i), 0)
        xsA(4 + i) = xsA(i): ysA(4 + i) = PYf(cy(i), hh)
    Next i
    HullFill 8, side
    Ellipse PXf(ax), PYf(ay, 0), RXf(r), RYf(r), side
    Ellipse PXf(bx), PYf(by, 0), RXf(r), RYf(r), side
    For i = 0 To 3
        xsA(i) = xsA(4 + i): ysA(i) = ysA(4 + i)
    Next i
    HullFill 4, top
    Ellipse PXf(ax), PYf(ay, hh), RXf(r), RYf(r), top
    Ellipse PXf(bx), PYf(by, hh), RXf(r), RYf(r), top
End Sub

Private Sub Cylinder(ByVal x As Long, ByVal y As Long, ByVal r As Long, ByVal h As Long, ByVal side As Long, ByVal top As Long)
    Dim cx As Long, y0 As Long, y1 As Long, rx As Long, ry As Long
    cx = PXf(x): y0 = PYf(y, 0): y1 = PYf(y, h * 65536): rx = RXf(r): ry = RYf(r)
    Ellipse cx, y0, rx, ry, side
    RectP cx - rx, y1, cx + rx, y0, side
    Ellipse cx, y1, rx, ry, top
End Sub

' ================================================================ text

' the 16 x 16 font, each of its pixels sc x sc, top left at (x, y) of the target
Private Function Glyph(ByVal c As Long, ByVal pen As Long, ByVal sc As Long) As Long
    Dim k As Long, img As Long, r As Long, b As Long, e As Long, bits As Long, w As Long, tg As Long
    If c < 33 Or c > 126 Then Exit Function
    k = (pen * 2 + sc - 1) * 95 + c - 32
    If glyphImg(k) = 0 Then
        tg = CV.Target
        img = CV.CreateImage(16 * sc, 16 * sc)
        CV.SetTarget img
        For r = 0 To 15
            bits = fontRow((c - 32) * 16 + r)
            b = 0
            Do While b < 16 And bits <> 0
                w = 2 ^ (15 - b)
                If bits And w Then
                    e = b
                    Do While e < 15
                        If (bits And (2 ^ (14 - e))) = 0 Then Exit Do
                        e = e + 1
                    Loop
                    CV.Box b * sc, r * sc, (e - b + 1) * sc, sc, penC(pen)
                    b = e + 1
                Else
                    b = b + 1
                End If
            Loop
        Next r
        CV.SetTarget tg
        glyphImg(k) = img
    End If
    Glyph = glyphImg(k)
End Function

' text of the font at (x, y) in pixels of the target: 16 * sc across a character
Private Sub TextAt(ByVal x As Long, ByVal y As Long, ByVal pen As Long, ByVal s As String, ByVal sc As Long)
    Dim i As Long, g As Long
    For i = 1 To Len(s)
        g = Glyph(Asc(Mid$(s, i, 1)), pen, sc)
        If g Then CV.DrawImage g, x - orgX, y - orgY
        x = x + 16 * sc
    Next i
End Sub

' a line of text (with its shadow) made once into an image and kept: one call to draw it again
Private Sub TextLine(ByVal x As Long, ByVal y As Long, ByVal pen As Long, ByVal s As String, ByVal sc As Long, ByVal shadow As Long)
    Dim key As String, img As Long, tg As Long, ox As Long, oy As Long, sh As Long
    If Len(s) = 0 Then Exit Sub
    key = pen & "|" & sc & "|" & shadow & "|" & s
    On Error Resume Next
    img = 0
    img = lineCache(key)
    On Error GoTo 0
    If img = 0 Then
        If lineCount >= 64 Then
            Do While lineCache.Count > 0
                CV.FreeImage lineCache(1)
                lineCache.Remove 1
            Loop
            lineCount = 0
        End If
        sh = shadow
        tg = CV.Target
        img = CV.CreateImage(Len(s) * 16 * sc + sh, 16 * sc + sh)
        CV.SetTarget img
        ox = orgX: oy = orgY: orgX = 0: orgY = 0
        If sh Then TextAt sh, sh, P_BLACK, s, sc
        TextAt 0, 0, pen, s, sc
        orgX = ox: orgY = oy
        CV.SetTarget tg
        lineCache.Add img, key
        lineCount = lineCount + 1
    End If
    CV.DrawImage img, x - orgX, y - orgY
End Sub

' the C's g_text: (x, y) in the game's coordinates, y the baseline; shadowed by 1 game pixel
Private Sub GText(ByVal x As Long, ByVal y As Long, ByVal pen As Long, ByVal s As String, ByVal shadow As Boolean)
    If shadow Then TextLine x * 2, (y - 6) * 2, pen, s, 1, 2 Else TextLine x * 2, (y - 6) * 2, pen, s, 1, 0
End Sub

Private Sub GTextCentre(ByVal y As Long, ByVal pen As Long, ByVal s As String)
    GText (320 - Len(s) * 8) \ 2, y, pen, s, True
End Sub

' the C's g_text_big: y the top
Private Sub GTextBig(ByVal x As Long, ByVal y As Long, ByVal pen As Long, ByVal s As String, ByVal sc As Long, ByVal shadow As Boolean)
    If shadow Then TextLine x * 2, y * 2, pen, s, sc, 2 Else TextLine x * 2, y * 2, pen, s, sc, 0
End Sub

Private Sub GBox(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal fill As Long, ByVal edge As Long)
    RectP x0 * 2, y0 * 2, x1 * 2 + 1, y1 * 2 + 1, fill
    RectP x0 * 2, y0 * 2, x1 * 2 + 1, y0 * 2 + 1, edge
    RectP x0 * 2, y1 * 2, x1 * 2 + 1, y1 * 2 + 1, edge
    RectP x0 * 2, y0 * 2, x0 * 2 + 1, y1 * 2 + 1, edge
    RectP x1 * 2, y0 * 2, x1 * 2 + 1, y1 * 2 + 1, edge
End Sub

' ================================================================ the Boing ball

Private Sub MakeBall()
    Dim f As Long, i As Long, j As Long, img As Long, col As Long, nx As Long, ny As Long, nz2 As Long, nz As Long
    Dim xr As Long, yr As Long, lon As Long, lat As Long, lit As Long, y2 As Long, dy As Long, w As Long
    For f = 0 To 7
        img = CV.CreateImage(2 * BR + 1, 2 * BR + 1)
        CV.SetTarget img
        For j = -BR To BR
            For i = -BR To BR
                If i * i + j * j <= BR * BR + BR \ 2 Then
                    nx = (i * 1024) \ BR: ny = (j * 1024) \ BR
                    nz2 = 1048576 - nx * nx - ny * ny
                    If nz2 < 0 Then nz2 = 0
                    nz = ISq(nz2)
                    xr = (nx * 962 - ny * 350) \ 1024: yr = (nx * 350 + ny * 962) \ 1024
                    lon = A3Atan2(xr, nz) + f * 1024
                    y2 = yr * yr
                    If y2 > 1048576 Then y2 = 1048576
                    lat = A3Atan2(yr, ISq(1048576 - y2))
                    lat = (lat + 49152) And &HFFFF&
                    lit = (-nx * 480 - ny * 560 + nz * 680) \ 1024
                    If ((((lon And &HFFFF&) \ 8192) + (lat \ 8192)) And 1) <> 0 Then col = P_RUBBER Else col = P_RED
                    If lit < 250 Or i * i + j * j > BR * BR - 4 Then
                        If col = P_RED Then col = P_RED_D Else col = P_RUBBER_D
                    End If
                    If lit > 960 Then col = P_TEXT
                    CV.PSet i + BR, j + BR, penC(col)
                End If
            Next i
        Next j
        patchImg(PT_BALL + f) = img
    Next f
    ' its shadow: black, blended at 120/256 when drawn (DrawImageBlend)
    img = CV.CreateImage(2 * BR + 1, 2 * BR - 3)
    CV.SetTarget img
    For dy = -(BR - 2) To BR - 2
        w = (BR * ISq(((BR - 2) * (BR - 2) - dy * dy) * 256) + (BR - 2) * 8) \ ((BR - 2) * 16)
        CV.Line BR - w, dy + BR - 2, BR + w, dy + BR - 2, penC(P_BLACK)
    Next dy
    patchImg(PT_SHADOW) = img
    CV.SetTarget 0
End Sub

' ================================================================ the picture

' the playfield's left and right edges at y (mm)
Private Sub FieldEdges(ByVal y As Long, xl As Long, xr As Long)
    Dim d As Long, w As Long
    If y > 780 Then
        d = y - 780
        If d < 260 Then w = ISq(260& * 260 - d * d) Else w = 0
        xl = 260 - w: xr = 260 + w
        Exit Sub
    End If
    xr = 520
    If y <= 380 Then
        xl = 20
    ElseIf y <= 470 Then
        xl = 20 - ((y - 380) * 20) \ 90
    Else
        xl = 0
    End If
End Sub

Private Function PaintField(ByVal theme As Long) As Boolean
    Dim im As Long, row As Long, x0 As Long, y0 As Long, w As Long, h As Long, py As Long, ymm As Long
    Dim xl As Long, xr As Long, s0 As Long, s1 As Long
    Dim t As Double
    t = TimerMs()
    im = LoadArt("playfield_" & Choose(theme + 1, "comet", "deep", "foundry"))
    buildLoadMs = TimerMs() - t
    If im = 0 Then Exit Function
    x0 = PXI(0): y0 = PYI(1040, 0)
    w = CV.ImageWidth(im): h = CV.ImageHeight(im)
    For row = 0 To h - 1
        py = y0 + row
        ymm = ((956 - py) * 65536) \ KYS
        If ymm >= -60 And ymm <= 1040 Then
            FieldEdges ymm, xl, xr
            s0 = PXI(xl) - x0
            s1 = PXI(xr) - x0
            If s1 > w - 1 Then s1 = w - 1
            If s0 < 0 Then s0 = 0
            If s0 <= s1 Then CV.DrawImagePart im, s0, row, s1 - s0 + 1, 1, x0 + s0, py, True
        End If
    Next row
    CV.FreeImage im
    buildPaintMs = TimerMs() - t - buildLoadMs
    PaintField = True
End Function

' the playfield without its painting: the C's flat colours
Private Sub FillField()
    Dim row As Long, ymm As Long, xl As Long, xr As Long, x2 As Long
    For row = 0 To PIC_H - 1
        ymm = ((956 - row) * 65536) \ KYS
        If ymm >= -60 And ymm <= 1040 Then
            FieldEdges ymm, xl, xr
            If xl < xr Then
                Span row, PXI(xl), PXI(xr), P_FIELD1
                If ymm > 380 And ymm < 760 And (row And 1) <> 0 Then
                    If xr < 470 Then x2 = xr - 30 Else x2 = 440
                    Span row, PXI(xl + 30), PXI(x2), P_FIELD2
                End If
            End If
        End If
    Next row
End Sub

Private Function LampPen(ByVal col As Long) As Long
    LampPen = Choose(col + 1, P_BLUE, P_YEL, P_LRED, P_GREEN, P_MAG, P_ORANGE)
End Function

Private Function SegSide(ByVal i As Long) As Long
    Select Case sg(i).kind
        Case SK_OUTER: SegSide = P_CAB_D
        Case SK_SLING: SegSide = P_RUBBER_D
        Case Else: SegSide = P_METAL_D
    End Select
End Function

Private Function SegTop(ByVal i As Long) As Long
    Select Case sg(i).kind
        Case SK_OUTER: SegTop = P_CAB_L
        Case SK_SLING: SegTop = P_RUBBER
        Case Else: SegTop = P_METAL_L
    End Select
End Function

' Catmull-Rom through a ramp's points, 4 steps a segment, into cx/cy/cz; returns the count
Private Function RampCurve(ByVal ri As Long, cx() As Long, cy() As Long, cz() As Long) As Long
    Dim i As Long, k As Long, n As Long, m As Long, t As Long, t2 As Long, t3 As Long, b As Long
    Dim p0 As Long, p1 As Long, p2 As Long, p3 As Long, c As Long, v As Long
    m = rampN(ri): b = ri * 16
    For i = 0 To m - 2
        For k = 0 To 3
            t = k * 16: t2 = t * t: t3 = t2 * t
            If i > 0 Then p0 = i - 1 Else p0 = 0
            p1 = i: p2 = i + 1
            If i + 2 < m Then p3 = i + 2 Else p3 = m - 1
            For c = 0 To 2
                Dim a0 As Long, a1 As Long, a2 As Long, a3 As Long
                Select Case c
                    Case 0: a0 = rpx(b + p0): a1 = rpx(b + p1): a2 = rpx(b + p2): a3 = rpx(b + p3)
                    Case 1: a0 = rpy(b + p0): a1 = rpy(b + p1): a2 = rpy(b + p2): a3 = rpy(b + p3)
                    Case 2: a0 = rpz(b + p0): a1 = rpz(b + p1): a2 = rpz(b + p2): a3 = rpz(b + p3)
                End Select
                v = 2 * a1 * 262144 + (-a0 + a2) * t * 4096 + (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 * 64 + _
                    (-a0 + 3 * a1 - 3 * a2 + a3) * t3
                Select Case c
                    Case 0: cx(n) = v \ 524288
                    Case 1: cy(n) = v \ 524288
                    Case 2: cz(n) = v \ 524288
                End Select
            Next c
            n = n + 1
        Next k
    Next i
    cx(n) = rpx(b + m - 1): cy(n) = rpy(b + m - 1): cz(n) = rpz(b + m - 1)
    RampCurve = n + 1
End Function

Private Sub DrawRamp(ByVal ri As Long)
    Dim cx(0 To 79) As Long, cy(0 To 79) As Long, cz(0 To 79) As Long, n As Long, i As Long, s As Long
    Dim dx As Long, dy As Long, ln As Long, nx As Long, ny As Long
    Const HALF As Long = 22
    Const RAIL As Long = 14
    n = RampCurve(ri, cx, cy, cz)
    ' the posts holding it up
    For i = 4 To n - 3 Step 6
        If cz(i) > 12 Then ThickLine PXI(cx(i)), PYI(cy(i), 0), PXI(cx(i)), PYI(cy(i), cz(i)), P_METAL_D, 2
    Next i
    For i = 0 To n - 2
        dx = cx(i + 1) - cx(i): dy = cy(i + 1) - cy(i)
        ln = A3HypotI(dx, dy)
        If ln <> 0 Then
            nx = (-dy * HALF) \ ln: ny = (dx * HALF) \ ln
            xsA(0) = PXI(cx(i) + nx): ysA(0) = PYI(cy(i) + ny, cz(i))
            xsA(1) = PXI(cx(i + 1) + nx): ysA(1) = PYI(cy(i + 1) + ny, cz(i + 1))
            xsA(2) = PXI(cx(i + 1) - nx): ysA(2) = PYI(cy(i + 1) - ny, cz(i + 1))
            xsA(3) = PXI(cx(i) - nx): ysA(3) = PYI(cy(i) - ny, cz(i))
            BlendPoly picImg, 4, P_GLASS, 96          ' clear plastic: the table shows through
            For s = -1 To 1 Step 2
                ThickLine PXI(cx(i) + s * nx), PYI(cy(i) + s * ny, cz(i) + RAIL), PXI(cx(i + 1) + s * nx), _
                          PYI(cy(i + 1) + s * ny, cz(i + 1) + RAIL), P_METAL_L, 2
            Next s
        End If
    Next i
End Sub

Private Function A3HypotI(ByVal x As Long, ByVal y As Long) As Long
    A3HypotI = FHypot(x, y)                         ' the same code as a3_hypot
End Function

Private Sub BuildPicture()
    Dim n As Long, i As Long, j As Long, t As Long, x As Long, y As Long, rx As Long, ry As Long
    Dim key(0 To 219) As Long, kind(0 To 219) As Long, idx(0 To 219) As Long, mn As Long

    CV.SetTarget picImg
    orgX = 0: orgY = 0: oyR = 0
    CV.Box 0, 0, SCR_W, PIC_H, penC(P_WOOD)
    fieldPainted = PaintField(tTheme)
    DbgMark "paint " & fieldPainted
    If Not fieldPainted Then FillField
    ' the inserts (lamps), unlit: on a painting, tinted see-through plastic
    For i = 0 To L_COUNT - 1
        If lampR(i) <> 0 Then
            x = PXI(lampX(i)): y = PYI(lampY(i), 0): rx = RXf(lampR(i) * 65536): ry = RYf(lampR(i) * 65536)
            If fieldPainted Then
                BlendEllipse picImg, x, y, rx + 2, ry + 2, P_BLACK, 150
                BlendEllipse picImg, x, y, rx, ry, LampPen(lampCol(i)), 110
            Else
                Ellipse x, y, rx + 2, ry + 2, P_BLACK
                Ellipse x, y, rx, ry, Choose(lampCol(i) + 1, P_BLUE_D, P_YEL_D, P_LRED_D, P_DIM, P_DIM, P_DIM)
            End If
        End If
    Next i
    DbgMark "lamps"
    ' the saucer
    Ellipse PXf(saucerX), PYf(saucerY, 0), RXf(saucerR + 262144), RYf(saucerR + 262144), P_METAL_L
    Ellipse PXf(saucerX), PYf(saucerY, 0), RXf(saucerR), RYf(saucerR), P_BLACK
    ' the drop targets' slots
    For i = 0 To tNdrop - 1
        j = dropSeg(i)
        ThickLine PXf(sg(j).ax), PYf(sg(j).ay, 0), PXf(sg(j).bx), PYf(sg(j).by, 0), P_BLACK, 2
    Next i
    DbgMark "slots"
    ' the walls, posts and bumpers, far to near
    For i = 0 To tNseg - 1
        If sg(i).kind <> SK_DROP And sg(i).kind <> SK_GATE Then
            If sg(i).kind = SK_OUTER Then
                key(n) = 30000
            Else
                If sg(i).ay < sg(i).by Then mn = sg(i).ay Else mn = sg(i).by
                key(n) = FIr(mn)
            End If
            kind(n) = 0: idx(n) = i: n = n + 1
        End If
    Next i
    For i = 0 To tNcirc - 1
        key(n) = FIr(cc(i).cy): kind(n) = 1: idx(n) = i: n = n + 1
    Next i
    For i = 1 To n - 1
        j = i
        Do While j > 0
            If key(j) <= key(j - 1) Then Exit Do
            t = key(j): key(j) = key(j - 1): key(j - 1) = t
            t = kind(j): kind(j) = kind(j - 1): kind(j - 1) = t
            t = idx(j): idx(j) = idx(j - 1): idx(j - 1) = t
            j = j - 1
        Loop
    Next i
    For i = 0 To n - 1
        j = idx(i)
        DbgMark "item " & i & " " & kind(i) & " " & j
        If kind(i) = 0 Then
            Wall3d sg(j).ax, sg(j).ay, sg(j).bx, sg(j).by, sg(j).r, sg(j).h, SegSide(j), SegTop(j)
        ElseIf cc(j).bumper Then
            Ellipse PXf(cc(j).cx), PYf(cc(j).cy, 0), RXf(cc(j).r + 196608), RYf(cc(j).r + 196608), P_RUBBER
            Cylinder cc(j).cx, cc(j).cy, cc(j).r - 131072, cc(j).h - 8, P_METAL_D, P_RUBBER_D
            Cylinder cc(j).cx, cc(j).cy + 65536, FMr(cc(j).r, 58982), cc(j).h, P_RED_D, P_RED
            Ellipse PXf(cc(j).cx) - 6, PYf(cc(j).cy, cc(j).h * 65536) - 2, RXf(cc(j).r) \ 3, RYf(cc(j).r) \ 3, P_LRED
        Else
            Cylinder cc(j).cx, cc(j).cy, cc(j).r, cc(j).h, P_RUBBER_D, P_RUBBER
        End If
    Next i
    DbgMark "walls"
    ' the gates: a wire on two posts
    For i = 0 To tNseg - 1
        If sg(i).kind = SK_GATE Then
            ThickLine PXf(sg(i).ax), PYf(sg(i).ay, sg(i).h * 65536), PXf(sg(i).bx), PYf(sg(i).by, sg(i).h * 65536), P_METAL_L, 1
            ThickLine PXf(sg(i).ax), PYf(sg(i).ay, 0), PXf(sg(i).ax), PYf(sg(i).ay, sg(i).h * 65536), P_METAL_D, 1
            ThickLine PXf(sg(i).bx), PYf(sg(i).by, 0), PXf(sg(i).bx), PYf(sg(i).by, sg(i).h * 65536), P_METAL_D, 1
        End If
    Next i
    ' the spinners' brackets
    For i = 0 To tNsens - 1
        If sn(i).kind = SN_SPIN Then
            ThickLine PXf(sn(i).ax) + 4, PYf(sn(i).ay, 0), PXf(sn(i).ax) + 4, PYf(sn(i).ay, 1966080), P_METAL_D, 2
            ThickLine PXf(sn(i).bx) - 4, PYf(sn(i).by, 0), PXf(sn(i).bx) - 4, PYf(sn(i).by, 1966080), P_METAL_D, 2
        End If
    Next i
    DbgMark "spinners"
    ' the apron over the drain
    xsA(0) = PXI(20): ysA(0) = PYI(22, 20): xsA(1) = PXI(474): ysA(1) = PYI(22, 20)
    xsA(2) = PXI(474): ysA(2) = PYI(-60, 0): xsA(3) = PXI(20): ysA(3) = PYI(-60, 0)
    Quad P_CAB_D
    ThickLine PXI(20), PYI(22, 20), PXI(474), PYI(22, 20), P_CAB_L, 2
    DbgMark "apron"
    GText PXI(PB_MID) \ 2 - 52, PYI(-10, 20) \ 2, P_ART3, "BOING PINBALL", True
    DbgMark "text"
    ' the ramps, over everything
    Dim tr As Double
    tr = TimerMs()
    For i = 0 To tNramp - 1
        DrawRamp i
    Next i
    buildRampMs = TimerMs() - tr
    CV.SetTarget 0
End Sub

' ================================================================ the patches and sprites of what moves

' a new patch covering picture pixels x0..x1, y0..y1; it becomes the target
Private Sub NewPatch(ByVal k As Long, ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long)
    If patchImg(k) <> 0 Then CV.FreeImage patchImg(k)
    patchImg(k) = CV.CreateImage(x1 - x0 + 1, y1 - y0 + 1)
    patchX(k) = x0: patchY(k) = y0
    orgX = x0: orgY = y0
    CV.SetTarget patchImg(k)
End Sub

' the picture under patch k, a glow (an ellipse at alpha/256) blended over it, and nothing
' (transparent) outside the ellipse: the patch can be drawn over other things that move
Private Sub GlowPatch(ByVal k As Long, ByVal cx As Long, ByVal cy As Long, ByVal rx As Long, ByVal ry As Long, _
                      ByVal pen As Long, ByVal alpha As Long)
    Dim w As Long, h As Long, dy As Long, ww As Long, yy As Long
    w = CV.ImageWidth(patchImg(k)): h = CV.ImageHeight(patchImg(k))
    CV.DrawImagePart picImg, patchX(k), patchY(k), w, h, 0, 0, True
    BlendEllipse picImg, cx, cy, rx, ry, pen, alpha
    CV.SetTarget patchImg(k)
    For yy = 0 To h - 1
        dy = yy + patchY(k) - cy
        If dy < -ry Or dy > ry Then
            CV.ClearRect 0, yy, w, 1
        Else
            ww = (rx * ISq((ry * ry - dy * dy) * 256) + ry * 8) \ (ry * 16)
            CV.ClearRect 0, yy, cx - ww - patchX(k), 1
            CV.ClearRect cx + ww + 1 - patchX(k), yy, w, 1
        End If
    Next yy
End Sub

Private Sub FreePatch(ByVal k As Long)
    If patchImg(k) <> 0 Then CV.FreeImage patchImg(k)
    patchImg(k) = 0
End Sub

Private Sub FlipperSprite(ByVal f As Long, ByVal ang As Long)
    Dim c As Long, s As Long, lvl As Long, z As Long, n1x As Long, n1y As Long, n2x As Long, n2y As Long, col As Long
    Dim saveAng As Long
    c = FCosR(ang): s = FSinR(ang)
    saveAng = fl(f).ang
    fl(f).ang = ang
    FlipperTip f
    fl(f).ang = saveAng
    For lvl = 0 To 2
        z = Choose(lvl + 1, 0, 11, 22) * 65536
        col = Choose(lvl + 1, P_RED_D, P_RED, P_RUBBER)
        n1x = FMr(-s, fl(f).r1): n1y = FMr(c, fl(f).r1): n2x = FMr(-s, fl(f).r2): n2y = FMr(c, fl(f).r2)
        xsA(0) = PXf(fl(f).px + n1x): ysA(0) = PYf(fl(f).py + n1y, z)
        xsA(1) = PXf(tipX + n2x): ysA(1) = PYf(tipY + n2y, z)
        xsA(2) = PXf(tipX - n2x): ysA(2) = PYf(tipY - n2y, z)
        xsA(3) = PXf(fl(f).px - n1x): ysA(3) = PYf(fl(f).py - n1y, z)
        Quad col
        Ellipse PXf(fl(f).px), PYf(fl(f).py, z), RXf(fl(f).r1), RYf(fl(f).r1), col
        Ellipse PXf(tipX), PYf(tipY, z), RXf(fl(f).r2), RYf(fl(f).r2), col
    Next lvl
    Ellipse PXf(fl(f).px), PYf(fl(f).py, 1441792), 2, 2, P_METAL_D   ' the pivot's screw
End Sub

Private Sub BuildPatches()
    Dim i As Long, x As Long, y As Long, rx As Long, ry As Long, j As Long, k As Long, reach As Long
    Dim x0 As Long, y0 As Long, x1 As Long, y1 As Long, ang As Long
    oyR = 0
    ' lit lamps: the glow blended over the picture, the insert, its highlight
    For i = 0 To L_COUNT - 1
        FreePatch PT_LAMP + i
        If lampR(i) <> 0 Then
            x = PXI(lampX(i)): y = PYI(lampY(i), 0): rx = RXf(lampR(i) * 65536): ry = RYf(lampR(i) * 65536)
            NewPatch PT_LAMP + i, x - 2 * rx - 1, y - 2 * ry - 1, x + 2 * rx + 1, y + 2 * ry + 1
            GlowPatch PT_LAMP + i, x, y, rx * 2, ry * 2, LampPen(lampCol(i)), 70
            Ellipse x, y, rx, ry, LampPen(lampCol(i))
            Ellipse x - 2, y - 2, rx \ 2, ry \ 2, P_TEXT
        End If
    Next i
    DbgMark "lamp patches"
    ' flashing pop bumpers
    For i = 0 To 15
        FreePatch PT_BUMPER + i
    Next i
    For i = 0 To tNcirc - 1
        If cc(i).bumper Then
            x = PXf(cc(i).cx): y = PYf(cc(i).cy, cc(i).h * 65536): rx = RXf(cc(i).r) * 2: ry = RYf(cc(i).r) * 2
            NewPatch PT_BUMPER + i, x - rx - 1, y - ry - 1, x + rx + 1, y + ry + 1
            GlowPatch PT_BUMPER + i, x, y, rx, ry, P_FLASH, 80
            Ellipse x, PYf(cc(i).cy + 65536, cc(i).h * 65536), RXf(FMr(cc(i).r, 58982)), RYf(FMr(cc(i).r, 58982)), P_FLASH
        End If
    Next i
    DbgMark "bumper patches"
    ' flashing slingshots
    For i = 0 To tNseg - 1
        If sg(i).kind = SK_SLING Then
            k = PT_SLING + (sg(i).id And 1)
            x0 = PXf(sg(i).ax): y0 = PYf(sg(i).ay, sg(i).h * 65536): x1 = PXf(sg(i).bx): y1 = PYf(sg(i).by, sg(i).h * 65536)
            If x0 < x1 Then NewPatch k, x0 - 4, 0, x1 + 4, 0 Else NewPatch k, x1 - 4, 0, x0 + 4, 0
            If y0 < y1 Then
                NewPatch k, patchX(k), y0 - 4, patchX(k) + CV.ImageWidth(patchImg(k)) - 1, y1 + 4
            Else
                NewPatch k, patchX(k), y1 - 4, patchX(k) + CV.ImageWidth(patchImg(k)) - 1, y0 + 4
            End If
            ThickLine x0, y0, x1, y1, P_FLASH, 3
        End If
    Next i
    DbgMark "sling patches"
    ' standing drop targets
    For i = 0 To 15
        FreePatch PT_DROP + i
    Next i
    For i = 0 To tNdrop - 1
        j = dropSeg(i)
        If sg(j).ax < sg(j).bx Then x0 = PXf(sg(j).ax) - 6: x1 = PXf(sg(j).bx) + 6 Else x0 = PXf(sg(j).bx) - 6: x1 = PXf(sg(j).ax) + 6
        If sg(j).ay < sg(j).by Then y0 = PYf(sg(j).by, 1703936) - 6: y1 = PYf(sg(j).ay, 0) + 6 Else y0 = PYf(sg(j).ay, 1703936) - 6: y1 = PYf(sg(j).by, 0) + 6
        NewPatch PT_DROP + i, x0, y0, x1, y1
        Wall3d sg(j).ax, sg(j).ay, sg(j).bx, sg(j).by, 196608, 26, P_YEL_D, P_ORANGE
    Next i
    DbgMark "drop patches"
    ' the flippers: NFRAMES sprites from the low angle to the high one
    For i = 0 To 2 * NFRAMES * 3 \ 2 - 1
        If PT_FLIP + i < PT_KNOB Then FreePatch PT_FLIP + i
    Next i
    For i = 0 To tNflip - 1
        If fl(i).rest < fl(i).up Then flipLo(i) = fl(i).rest: flipHi(i) = fl(i).up Else flipLo(i) = fl(i).up: flipHi(i) = fl(i).rest
        reach = fl(i).ln + fl(i).r1 + 196608
        x0 = PXf(fl(i).px - reach) - 2: x1 = PXf(fl(i).px + reach) + 2
        y0 = PYf(fl(i).py + reach, 1441792) - 2: y1 = PYf(fl(i).py - reach, 0) + 2
        For k = 0 To NFRAMES - 1
            ang = flipLo(i) + ((flipHi(i) - flipLo(i)) * CDbl(k)) / (NFRAMES - 1)
            NewPatch PT_FLIP + i * NFRAMES + k, x0, y0, x1, y1
            FlipperSprite i, ang
        Next k
    Next i
    DbgMark "flippers"
    ' the plunger's knob
    NewPatch PT_KNOB, -10, -6, 10, 6
    Ellipse 0, 0, 10, 6, P_METAL_L
    orgX = 0: orgY = 0
    CV.SetTarget 0
End Sub

' build table `which` and draw it (the picture, the patches): a second or so in the interpreter
Public Sub DrawBuild(ByVal which As Long)
    PbBuildTable which
    DrawPalette tTheme
    Set lineCache = New Collection       ' the pens changed: drop the cached text (its images stay)
    lineCount = 0
    Erase glyphImg
    Dim t As Double
    scratch = CV.CreateImage(SCR_W, PIC_H)
    BuildPicture
    t = TimerMs()
    BuildPatches
    buildPatchMs = TimerMs() - t
    CV.FreeImage scratch
    scratch = 0
    dTable = which
    dmdKey = ""
End Sub

Public Sub DrawLoadTitles()
    Dim i As Long
    For i = 0 To 2
        If titleImg(i) = 0 Then titleImg(i) = LoadArt("title_" & Choose(i + 1, "comet", "deep", "foundry"))
    Next i
End Sub

' ================================================================ the view

' move the view towards the lowest ball in play (snap: at once)
Public Sub DrawFollow(ByVal snap As Boolean)
    Dim i As Long, target As Long, best As Long, d As Long, stp As Long, r As Long
    target = CAM_MAX: best = &H7FFFFFFF
    oyR = 0
    For i = 0 To wNballs - 1
        If bl(i).st <> BS_DRAINED And bl(i).st <> BS_LANE Then
            If bl(i).y < best Then
                best = bl(i).y
                r = PYf(bl(i).y, PB_R + bl(i).z) \ 2
                target = r - 112
                If bl(i).vy > 98304000 Then target = target - 40
            End If
        End If
    Next i
    If target < 0 Then target = 0
    If target > CAM_MAX Then target = CAM_MAX
    d = target - cam
    If snap Then
        cam = target
        Exit Sub
    End If
    stp = (d * 3) \ 10                               ' (the C halves the gap at 25 fps)
    If stp = 0 Then stp = d
    cam = cam + stp
End Sub

' ================================================================ the dot-matrix display

Private Function DmdW(ByVal s As String, ByVal sx As Long) As Long
    DmdW = Len(s) * 8 * sx
End Function

Private Function DmdGlyphImg(ByVal c As Long, ByVal sz As Long, ByVal bright As Long) As Long
    Dim k As Long, img As Long, sx As Long, sy As Long, cw As Long, ch As Long, rd As Long, r As Long, b As Long
    Dim bits As Long, pen As Long, tg As Long, w As Long
    If c < 33 Or c > 126 Then Exit Function
    k = (sz * 2 + bright) * 95 + c - 32
    If dmdGlyph(k) = 0 Then
        sx = Choose(sz + 1, 4, 2, 1, 2): sy = Choose(sz + 1, 4, 4, 2, 2)
        cw = sx * 2: ch = sy * 2
        If cw < ch Then rd = cw \ 2 - 1 Else rd = ch \ 2 - 1
        If bright Then pen = P_DMD_ON Else pen = P_DMD_MID
        If cw >= 3 Then w = cw - 2 Else w = cw - 1
        tg = CV.Target
        img = CV.CreateImage(8 * cw, 8 * ch)
        CV.SetTarget img
        orgX = 0: orgY = 0
        For r = 0 To 7
            bits = dmdBits((c - 32) * 8 + r)
            For b = 0 To 7
                If (bits And (2 ^ (7 - b))) <> 0 Then
                    If rd >= 2 Then
                        Ellipse b * cw + cw \ 2, r * ch + ch \ 2, rd, rd, pen
                    Else
                        CV.Box b * cw, r * ch, w, ch - 1, penC(pen)
                    End If
                End If
            Next b
        Next r
        CV.SetTarget tg
        dmdGlyph(k) = img
    End If
    DmdGlyphImg = dmdGlyph(k)
End Function

Private Sub DmdText(ByVal s As String, ByVal y0 As Long, ByVal sz As Long, ByVal bright As Long)
    Dim sx As Long, x0 As Long, i As Long, g As Long
    sx = Choose(sz + 1, 4, 2, 1, 2)
    x0 = (320 - DmdW(s, sx)) \ 2
    For i = 1 To Len(s)
        g = DmdGlyphImg(Asc(Mid$(s, i, 1)), sz, bright)
        If g Then CV.DrawImage g, x0 * 2, y0 * 2
        x0 = x0 + 8 * sx
    Next i
End Sub

' the display: re-drawn into its image only when what it shows changes
Private Sub DrawDmd(ByVal big As String, ByVal small As String, ByVal flash As Long)
    Dim bright As Long, key As String
    If flash <> 0 And (animFrame And 4) <> 0 Then bright = 0 Else bright = 1
    key = big & "|" & small & "|" & bright
    If key <> dmdKey Then
        dmdKey = key
        CV.SetTarget dmdImg
        CV.Box 0, 0, SCR_W, VIEW_Y, penC(P_DMD_BG)
        If Len(small) = 0 Then
            If DmdW(big, 4) <= 320 Then
                DmdText big, 0, 0, bright
            ElseIf DmdW(big, 2) <= 320 Then
                DmdText big, 0, 1, bright
            Else
                DmdText big, 9, 2, bright
            End If
        Else
            If DmdW(big, 2) <= 320 Then DmdText big, 1, 3, bright Else DmdText big, 1, 2, bright
            DmdText small, 17, 2, bright
        End If
        CV.SetTarget 0
    End If
    CV.DrawImage dmdImg, 0, 0, True
End Sub

' ================================================================ what moves

Private Sub DrawPatch(ByVal k As Long, ByVal offY As Long)
    If patchImg(k) Then CV.DrawImage patchImg(k), patchX(k), patchY(k) + offY
End Sub

Private Sub DrawMoving()
    Dim i As Long, offY As Long, blink As Long, k As Long, a As Long, h As Long, yt As Long, x As Long, y As Long
    Dim topY As Long, yk As Long, ylow As Long, f As Long, n As Long, j As Long, t As Long, ka As Long, kb As Long
    Dim order(0 To 3) As Long, dx As Long, dy As Long, moved As Long, id As Long, col As Long, xa As Long, xb As Long
    offY = (VIEW_Y \ 2 - cam) * 2
    oyR = VIEW_Y \ 2 - cam
    blink = (animFrame \ 5) And 1
    ' the lit lamps
    PbLamps blink, animFrame \ 4
    For i = 0 To L_COUNT - 1
        If lampOn(i) <> 0 Then DrawPatch PT_LAMP + i, offY
    Next i
    ' standing drop targets
    For i = 0 To tNdrop - 1
        If sg(dropSeg(i)).up Then DrawPatch PT_DROP + i, offY
    Next i
    ' flashing bumpers and slings
    For i = 0 To tNcirc - 1
        If bumperFlash(i) > 0 Then DrawPatch PT_BUMPER + i, offY
    Next i
    For i = 0 To 1
        If slingFlash(i) > 0 Then DrawPatch PT_SLING + i, offY
    Next i
    ' the spinners
    For i = 0 To tNsens - 1
        If sn(i).kind = SN_SPIN Then
            yt = PYf(sn(i).ay, 1966080)
            a = A3Angle(spAng(sn(i).idx))
            h = ShrA(22 * A3Cos(a), 16)
            If h >= 0 Then col = P_METAL_L Else col = P_METAL_D
            xa = PXf(sn(i).ax) + 8: xb = PXf(sn(i).bx) - 8
            ylow = PYf(sn(i).ay, (30 - Abs(h)) * 65536)
            CV.Box xa, yt, xb - xa + 1, ylow - yt + 1, penC(col)
            CV.Box PXf(sn(i).ax) + 3, yt - 1, PXf(sn(i).bx) - PXf(sn(i).ax) - 6, 2, penC(P_METAL_L)
        End If
    Next i
    ' the plunger
    topY = 1966080 - FMr(gPull, 1441792)
    yk = PYf(topY - 393216, 524288)
    x = PXf(plungerX)
    ylow = PYf(-2621440, 524288)
    CV.Box x - 3, yk - 3, 6, ylow - yk + 6, penC(P_METAL_D)
    CV.DrawImage patchImg(PT_KNOB), x - 10, yk - 6
    ' the flippers
    For i = 0 To tNflip - 1
        If flipHi(i) > flipLo(i) Then
            f = ((fl(i).ang - flipLo(i)) * CDbl(NFRAMES - 1) + (flipHi(i) - flipLo(i)) \ 2) \ (flipHi(i) - flipLo(i))
            If f < 0 Then f = 0
            If f > NFRAMES - 1 Then f = NFRAMES - 1
            DrawPatch PT_FLIP + i * NFRAMES + f, offY
        End If
    Next i
    ' the balls: shadows, then the balls far to near (balls on a ramp last)
    For i = 0 To wNballs - 1
        If bl(i).st <> BS_DRAINED Then
            If Not (bl(i).y < 1441792 And bl(i).x < 31064064) Then order(n) = i: n = n + 1
        End If
    Next i
    For i = 1 To n - 1
        j = i
        Do While j > 0
            If bl(order(j - 1)).st = BS_RAMP Then ka = -1 Else ka = 0
            If bl(order(j)).st = BS_RAMP Then kb = -1 Else kb = 0
            If ka < kb Or (ka = kb And bl(order(j - 1)).y >= bl(order(j)).y) Then Exit Do
            t = order(j): order(j) = order(j - 1): order(j - 1) = t
            j = j - 1
        Loop
    Next i
    For i = 0 To n - 1
        k = order(i)
        CV.DrawImageBlend patchImg(PT_SHADOW), PXf(bl(k).x) + 4 - BR, PYf(bl(k).y, 0) + 2 - (BR - 2), 120
    Next i
    For i = n - 1 To 0 Step -1
        k = order(i)
        x = PXf(bl(k).x): y = PYf(bl(k).y, PB_R + bl(k).z)
        id = bl(k).id And 7
        dx = Abs(bl(k).x - ballPX(id)): dy = Abs(bl(k).y - ballPY(id))
        moved = FIr(dx + dy)
        If moved < 200 Then
            If moved Then moved = (moved * 3) \ 4 + 1
            If bl(k).vx + bl(k).vy >= 0 Then ballPhase(id) = ballPhase(id) + moved Else ballPhase(id) = ballPhase(id) - moved
        End If
        ballPX(id) = bl(k).x: ballPY(id) = bl(k).y
        CV.DrawImage patchImg(PT_BALL + (ballPhase(id) And 7)), x - BR, y - BR
    Next i
End Sub

Private Sub CentreBox(ByVal y0 As Long, ByVal y1 As Long)
    GBox 24, y0, 295, y1, P_BLACK, P_ART3
End Sub

Private Sub DrawTable()
    CV.DrawImagePart picImg, 0, cam * 2, SCR_W, VIEW_H, 0, VIEW_Y, True
    DrawMoving
End Sub

' the game: the table, the display; over (game over) and paused boxes
Public Sub DrawGame(ByVal over As Boolean, ByVal paused As Boolean, ByVal stateTimer As Long)
    orgX = 0: orgY = 0
    DrawTable
    PbDmd
    If over Then DrawDmd "GAME OVER", dmdSmall, 0 Else DrawDmd dmdBig, dmdSmall, dmdFlash
    If over Then
        CentreBox 96, 170
        GTextBig (320 - 9 * 16) \ 2, 104, P_DMD_ON, "GAME OVER", 2, False
        GTextCentre 136, P_TEXT, "SCORE " & PbFmt(gScore)
        If gScore >= bestScore And gScore > 0 Then
            GTextCentre 150, P_YEL, "BEST  " & PbFmt(bestScore)
        Else
            GTextCentre 150, P_RUBBER_D, "BEST  " & PbFmt(bestScore)
        End If
        If stateTimer = 0 Then GTextCentre 164, P_BLUE, "FIRE: THE TITLE"
    End If
    If paused Then
        CentreBox 120, 140
        GTextCentre 134, P_TEXT, "PAUSED  (P)"
    End If
End Sub

' the title: the backglass for 10 s, then the demo on the table for 15, in turn
Public Function TitleArtShowing(ByVal titleFrames As Long) As Boolean
    TitleArtShowing = titleImg(dTable) <> 0 And (titleFrames Mod 625) < 250
End Function

Public Sub DrawTitle(ByVal titleFrames As Long)
    Dim s As String
    orgX = 0: orgY = 0
    If TitleArtShowing(titleFrames) Then
        CV.DrawImage titleImg(dTable), 0, 0, True
        s = "< " & tName & " >"
        GTextBig (320 - Len(s) * 16) \ 2, 186, P_DMD_ON, s, 2, True
        GTextCentre 220, P_TEXT, tBlurb
        GTextCentre 234, P_YEL, "BEST " & PbFmt(bestScore)
        If (animFrame \ 25) And 1 Then
            GTextCentre 249, P_BLUE, "PRESS FIRE TO PLAY"
        Else
            GTextCentre 249, P_BLUE, "LEFT/RIGHT: TABLE   HELP: RULES"
        End If
        Exit Sub
    End If
    DrawTable
    If titleImg(dTable) <> 0 Then
        If (animFrame \ 50) And 1 Then DrawDmd tName, "PRESS FIRE TO PLAY", 0 Else DrawDmd tName, "LEFT/RIGHT: TABLE", 0
        Exit Sub
    End If
    If (animFrame \ 50) And 1 Then
        DrawDmd "BOING PINBALL", "PRESS FIRE TO PLAY", 0
    Else
        DrawDmd "BOING PINBALL", "THREE TABLES  HELP FOR THE RULES", 0
    End If
    CentreBox 44, 118
    s = "< " & tName & " >"
    GTextBig (320 - Len(s) * 16) \ 2, 52, P_DMD_ON, s, 2, False
    GTextCentre 82, P_RUBBER, tBlurb
    GTextCentre 96, P_YEL, "BEST " & PbFmt(bestScore)
    GTextCentre 110, P_BLUE, "FIRE: PLAY   LEFT/RIGHT: TABLE"
End Sub

Public Sub DrawHelp(ByVal page As Long)
    Dim p As Variant, i As Long, n As Long, pen As Long
    orgX = 0: orgY = 0
    If page = 2 Then
        p = Array("THE RULES", "", "SKILL SHOT: THE FLASHING TOP LANE", "  ON THE PLUNGE - 10,000", _
                  "TOP LANES: LIGHT ALL THREE FOR A", "  BONUS MULTIPLIER (FLIPPERS MOVE", "  THE LIT LANES ROUND)", _
                  "RAMP: THREE LOCK MULTIBALL; IN", "  MULTIBALL EACH RAMP IS A JACKPOT", "SAUCER (LIT RED): STARTS A MISSION", _
                  "  - BUMPERS, TARGET BANKS, SPINS,", "  RAMPS OR LANE SETS IN 40 SECONDS", "ALL FIVE MISSIONS: SUPERNOVA,", _
                  "  EVERYTHING SCORES 3X", "BALL SAVE: THE FIRST 10 SECONDS", "", "HELP: CLOSE")
    Else
        p = Array("HOW TO PLAY", "", "Z  LEFT MOUSE      LEFT FLIPPERS", "/  RIGHT MOUSE     RIGHT FLIPPERS", _
                  "SPACE  DOWN       PLUNGER: HOLD TO", "                  PULL, LET GO", "LEFT RIGHT UP     NUDGE THE TABLE", _
                  "P  PAUSE          ESC  THE TITLE", "", "S  THE HIGH SCORES (ON THE TITLE)", _
                  "M  MUSIC ON AND OFF", "", "NUDGE TOO OFTEN: TWO WARNINGS,", "THEN TILT - THE FLIPPERS GO DEAD", _
                  "AND THE BALL SCORES NO BONUS.", "", "HELP: THE RULES")
    End If
    n = UBound(p) + 1
    CV.Cls penC(P_BLACK)
    GBox 8, 8, 311, 247, P_SHADOW, P_ART3
    GTextBig (320 - Len(p(0)) * 16) \ 2, 18, P_DMD_ON, p(0), 2, False
    For i = 2 To n - 1
        If i = n - 1 Then pen = P_BLUE Else pen = P_TEXT
        GText 18, 44 + (i - 2) * 12, pen, p(i), False
    Next i
End Sub

' the high scores (HiScore.bas) of the chosen table; rank: the new entry to highlight, -1 none
Public Sub DrawScores(ByVal rank As Long, ByVal entry As String, ByVal entering As Boolean)
    Dim i As Long, pen As Long, s As String
    orgX = 0: orgY = 0
    If titleImg(dTable) <> 0 Then
        CV.DrawImage titleImg(dTable), 0, 0, True
    Else
        CV.Cls penC(P_BLACK)
    End If
    CentreBox 40, 230
    GTextBig (320 - Len(tName) * 16) \ 2, 48, P_DMD_ON, tName, 2, False
    If entering Then
        GTextCentre 90, P_YEL, "A NEW HIGH SCORE: " & PbFmt(gScore)
        GTextCentre 110, P_TEXT, "TYPE YOUR NAME, THEN RETURN"
        s = entry
        If (animFrame \ 6) And 1 Then s = s & "_" Else s = s & " "
        GTextBig (320 - 9 * 16) \ 2, 130, P_DMD_ON, s, 2, False
        Exit Sub
    End If
    GTextCentre 90, P_BLUE, "HIGH SCORES"
    For i = 0 To HS_COUNT - 1
        If i = rank And (animFrame \ 6) And 1 Then pen = P_YEL Else pen = P_TEXT
        s = Right$(" " & (i + 1), 2) & ". " & Left$(hsName(i) & "          ", 10) & Right$(Space$(11) & PbFmt(hsScore(i)), 11)
        GText 60, 110 + i * 13, pen, s, False
    Next i
    GTextCentre 222, P_BLUE, "FIRE: THE TITLE"
End Sub

' the timing overlay (F1)
Public Sub DrawPerf(ByVal s As String)
    CV.Box 0, SCR_H - 12, SCR_W, 12, RGB(0, 0, 0)
    CV.DrawText 4, SCR_H - 11, s, RGB(255, 255, 0)
End Sub

' the events of the last steps: the lights (the sound is PbSound's)
Public Sub DrawEvents()
    Dim i As Long
    For i = 0 To gNev - 1
        If gev(i).etype = EV_BUMPER Then
            If gev(i).id >= 0 And gev(i).id < 16 Then bumperFlash(gev(i).id) = 4
        ElseIf gev(i).etype = EV_SLING Then
            slingFlash(gev(i).id And 1) = 3
        End If
    Next i
End Sub

' one tick of the 25 Hz animation clock
Public Sub DrawAge()
    Dim i As Long
    animFrame = animFrame + 1
    For i = 0 To 15
        If bumperFlash(i) > 0 Then bumperFlash(i) = bumperFlash(i) - 1
    Next i
    For i = 0 To 1
        If slingFlash(i) > 0 Then slingFlash(i) = slingFlash(i) - 1
    Next i
End Sub
