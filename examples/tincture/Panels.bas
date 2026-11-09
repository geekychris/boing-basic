' Tincture - the tool box and the colour panel: drawn into canvases of their own, with their
' own look (slate buttons, amber highlight), and the hit tests for their mouse clicks.
' The icons are drawn with Canvas calls once, at start-up, into images.
Option Explicit

Public Const UI_BG As Long = &H3A3430         ' RGB(48, 52, 58)
Public Const UI_BUTTON As Long = &H4A443E     ' RGB(62, 68, 74)
Public Const UI_HILITE As Long = &H6A5E52
Public Const UI_ACCENT As Long = &HB0FF&      ' RGB(255, 176, 0)
Public Const UI_INK As Long = &HE8E2DC        ' RGB(220, 226, 232)
Public Const UI_DARK As Long = &H201C18

Public Const TB_CELL As Long = 28
Public Const TB_COLS As Long = 2
Public Const TB_UNDO As Long = 100
Public Const TB_REDO As Long = 101

Private icons(0 To 14) As Long          ' 0..12 tools, 13 undo, 14 redo
Private tbCanvas As Object, cpCanvas As Object

' colour panel geometry
Public Const CP_W As Long = 168
Private Const CP_PAL_Y As Long = 52
Private Const CP_CELL As Long = 10
Public pickHue As Long, pickSat As Long, pickVal As Long
Public palSel As Long                    ' the palette entry being edited (-1 none)

' ---------------------------------------------------------------- icons

Public Sub MakeIcons(tb As Object)
    Dim t As Long
    Set tbCanvas = tb
    For t = 0 To T_COUNT + 1
        icons(t) = tb.CreateImage(24, 24)
        tb.SetTarget icons(t)
        DrawIcon tb, t
    Next
    tb.SetTarget 0
End Sub

Private Sub DrawIcon(c As Object, ByVal t As Long)
    Dim xs(0 To 5) As Long, ys(0 To 5) As Long, i As Long
    Select Case t
        Case T_FREEHAND
            c.BrushLine 3, 17, 7, 9, 2, UI_INK
            c.BrushLine 7, 9, 11, 15, 2, UI_INK
            c.BrushLine 11, 15, 15, 6, 2, UI_INK
            c.BrushLine 15, 6, 20, 14, 2, UI_INK
        Case T_LINE
            c.BrushLine 4, 19, 19, 4, 2, UI_INK
        Case T_RECT
            c.Rect 4, 5, 16, 14, UI_INK
            c.Rect 5, 6, 14, 12, UI_INK
        Case T_RECTF
            c.Box 4, 5, 16, 14, UI_INK
        Case T_ELLIPSE
            c.Ellipse 12, 12, 8, 6, UI_INK
            c.Ellipse 12, 12, 7, 5, UI_INK
        Case T_ELLIPSEF
            c.Ellipse 12, 12, 8, 6, UI_INK, True
        Case T_FILL
            ' a tipped bucket pouring a drop
            xs(0) = 4: ys(0) = 10: xs(1) = 11: ys(1) = 3: xs(2) = 18: ys(2) = 10: xs(3) = 11: ys(3) = 17
            c.Polygon xs, ys, 4, UI_INK, True
            c.Polygon xs, ys, 4, UI_DARK
            c.Line 7, 10, 15, 10, UI_DARK
            c.Ellipse 19, 17, 2, 3, UI_ACCENT, True
        Case T_AIRBRUSH
            c.Spray 12, 12, 8, 70, UI_INK, 99
            c.Box 2, 10, 4, 4, UI_INK
        Case T_TEXT
            c.DrawTextScaled 6, 3, "A", UI_INK, 2
        Case T_SELECT
            c.DashRect 3, 4, 18, 16, UI_INK, UI_BUTTON, 0
            c.DashRect 4, 5, 16, 14, UI_INK, UI_BUTTON, 2
        Case T_PICK
            c.BrushLine 6, 18, 15, 9, 3, UI_INK
            c.Ellipse 17, 7, 3, 3, UI_INK, True
            c.PSet 5, 19, UI_ACCENT
        Case T_ERASER
            xs(0) = 3: ys(0) = 15: xs(1) = 12: ys(1) = 6: xs(2) = 20: ys(2) = 14: xs(3) = 11: ys(3) = 21
            c.Polygon xs, ys, 4, UI_INK, True
            xs(0) = 3: ys(0) = 15: xs(1) = 7: ys(1) = 11: xs(2) = 15: ys(2) = 19: xs(3) = 11: ys(3) = 21
            c.Polygon xs, ys, 4, UI_ACCENT, True
        Case T_GRADIENT
            c.LinearGradient 4, 4, 16, 16, 4, 4, 19, 19, UI_INK, UI_BUTTON, False
            c.Rect 3, 3, 18, 18, UI_INK
        Case T_COUNT, T_COUNT + 1
            ' curved arrow (undo points left, redo right)
            For i = 0 To 5
                xs(i) = 12 + CLng(7 * Cos(3.14159 * (0.15 + i * 0.16)))
                ys(i) = 14 - CLng(7 * Sin(3.14159 * (0.15 + i * 0.16)))
            Next
            For i = 0 To 4
                c.BrushLine xs(i), ys(i), xs(i + 1), ys(i + 1), 2, UI_INK
            Next
            xs(0) = xs(5) - 4: ys(0) = ys(5): xs(1) = xs(5) + 4: ys(1) = ys(5): xs(2) = xs(5): ys(2) = ys(5) + 6
            c.Polygon xs, ys, 3, UI_INK, True
            If t = T_COUNT Then c.FlipImage icons(t)
    End Select
End Sub

' ---------------------------------------------------------------- the tool box

Public Function ToolBoxWidth() As Long
    ToolBoxWidth = TB_COLS * TB_CELL + 6
End Function

Public Function ToolBoxHeight() As Long
    ToolBoxHeight = ((T_COUNT + 1) \ TB_COLS + 1) * TB_CELL + 14
End Function

Public Sub DrawToolBox(c As Object)
    Dim t As Long, x As Long, y As Long
    c.SetTarget 0
    c.Cls UI_BG
    For t = 0 To T_COUNT + 1
        CellPos t, x, y
        If t < T_COUNT Then
            If t = curTool Then
                c.Box x, y, TB_CELL - 2, TB_CELL - 2, UI_HILITE
                c.Rect x, y, TB_CELL - 2, TB_CELL - 2, UI_ACCENT
            Else
                c.Box x, y, TB_CELL - 2, TB_CELL - 2, UI_BUTTON
            End If
            c.DrawImage icons(t), x + 1, y + 1
        Else
            c.Box x, y, TB_CELL - 2, TB_CELL - 2, UI_BUTTON
            If (t = T_COUNT And Not CanUndo()) Or (t = T_COUNT + 1 And Not CanRedo()) Then
                c.DrawImageBlend icons(t), x + 1, y + 1, 70         ' greyed out
            Else
                c.DrawImage icons(t), x + 1, y + 1
            End If
        End If
    Next
    c.Refresh
End Sub

Private Sub CellPos(ByVal t As Long, x As Long, y As Long)
    Dim row As Long
    If t >= T_COUNT Then row = (T_COUNT + 1) \ TB_COLS Else row = t \ TB_COLS
    x = 3 + (t Mod TB_COLS) * TB_CELL
    y = 3 + row * TB_CELL + IIf(t >= T_COUNT, 8, 0)
End Sub

' a click in the tool box: the tool number, TB_UNDO / TB_REDO, or -1
Public Function ToolBoxHit(ByVal x As Long, ByVal y As Long) As Long
    Dim t As Long, cx As Long, cy As Long
    ToolBoxHit = -1
    For t = 0 To T_COUNT + 1
        CellPos t, cx, cy
        If x >= cx And y >= cy And x < cx + TB_CELL - 2 And y < cy + TB_CELL - 2 Then
            If t = T_COUNT Then
                ToolBoxHit = TB_UNDO
            ElseIf t = T_COUNT + 1 Then
                ToolBoxHit = TB_REDO
            Else
                ToolBoxHit = t
            End If
            Exit Function
        End If
    Next
End Function

' ---------------------------------------------------------------- the colour panel

Public Function ColourPanelHeight() As Long
    ColourPanelHeight = CP_PAL_Y + 16 * CP_CELL + 8 + 100 + 6 + 14 + 22
End Function

Private Function SvY() As Long
    SvY = CP_PAL_Y + 16 * CP_CELL + 8
End Function

Public Sub SyncPickerFromColour(ByVal c As Long)
    RgbToHsv ColR(c), ColG(c), ColB(c), pickHue, pickSat, pickVal
End Sub

Public Sub DrawColourPanel(c As Object)
    Dim i As Long, x As Long, y As Long, sy As Long, hx As Long, k As Long
    c.SetTarget 0
    c.Cls UI_BG
    ' foreground over background swatches; click swaps
    c.Box 26, 20, 30, 26, UI_DARK
    c.Box 27, 21, 28, 24, bgColor
    c.Box 8, 6, 30, 26, UI_DARK
    c.Box 9, 7, 28, 24, fgColor
    c.DrawText 64, 8, ColorHex(fgColor), UI_INK
    c.DrawText 64, 20, ColorHex(bgColor), RGB(160, 166, 172)
    If docMode = MODE_INDEXED Then
        c.DrawText 64, 34, palCount & " colours", UI_ACCENT
    Else
        c.DrawText 64, 34, "true colour", RGB(160, 166, 172)
    End If
    ' palette
    For i = 0 To 255
        x = 4 + (i Mod 16) * CP_CELL: y = CP_PAL_Y + (i \ 16) * CP_CELL
        If i < palCount Then
            c.Box x, y, CP_CELL - 1, CP_CELL - 1, pal(i)
            If pal(i) = fgColor Then c.Rect x - 1, y - 1, CP_CELL + 1, CP_CELL + 1, vbWhite
            If i = palSel Then c.Rect x - 1, y - 1, CP_CELL + 1, CP_CELL + 1, UI_ACCENT
        Else
            c.Box x, y, CP_CELL - 1, CP_CELL - 1, UI_BUTTON
        End If
    Next
    ' saturation / value square for the current hue, then the hue bar
    sy = SvY()
    c.Gradient 4, sy, 160, 100, vbWhite, HueColor(pickHue, 255, 255), vbBlack, vbBlack
    x = 4 + pickSat * 159 \ 255: y = sy + (255 - pickVal) * 99 \ 255
    c.Circle x, y, 4, IIf(pickVal > 140, vbBlack, vbWhite)
    For k = 0 To 5
        c.Gradient 4 + k * 160 \ 6, sy + 106, 160 \ 6 + 1, 14, HueColor(k * 60, 255, 255), HueColor(k * 60 + 60, 255, 255)
    Next
    hx = 4 + pickHue * 159 \ 359
    c.Rect hx - 1, sy + 105, 3, 16, vbWhite
    If palSel >= 0 Then c.DrawText 4, sy + 126, "Editing pen " & palSel, UI_ACCENT Else c.DrawText 4, sy + 126, "Pick a colour", RGB(160, 166, 172)
    c.Refresh
End Sub

' a click in the colour panel. Returns: 0 nothing, 1 swatch swap, 2 palette (index in hitIndex),
' 3 saturation/value, 4 hue
Public Function ColourPanelHit(ByVal x As Long, ByVal y As Long, hitIndex As Long) As Long
    Dim sy As Long, i As Long
    sy = SvY()
    If y < CP_PAL_Y - 4 And x < 60 Then ColourPanelHit = 1: Exit Function
    If y >= CP_PAL_Y And y < CP_PAL_Y + 16 * CP_CELL And x >= 4 And x < 4 + 16 * CP_CELL Then
        i = ((y - CP_PAL_Y) \ CP_CELL) * 16 + (x - 4) \ CP_CELL
        If i < palCount Then hitIndex = i: ColourPanelHit = 2
        Exit Function
    End If
    If y >= sy And y < sy + 100 Then
        pickSat = Clamp((x - 4) * 255 \ 159, 0, 255)
        pickVal = Clamp(255 - (y - sy) * 255 \ 99, 0, 255)
        ColourPanelHit = 3
        Exit Function
    End If
    If y >= sy + 104 And y < sy + 122 Then
        pickHue = Clamp((x - 4) * 359 \ 159, 0, 359)
        ColourPanelHit = 4
    End If
End Function

' the picker's colour (after a hit 3 / 4)
Public Function PickerColour() As Long
    PickerColour = HueColor(pickHue, pickSat, pickVal)
End Function

Public Function Clamp(ByVal v As Long, ByVal lo As Long, ByVal hi As Long) As Long
    If v < lo Then v = lo
    If v > hi Then v = hi
    Clamp = v
End Function
