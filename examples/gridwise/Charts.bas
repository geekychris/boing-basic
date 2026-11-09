' Gridwise - charts: bar, line and pie charts of a range, drawn on a Canvas.
'
' A chart is a range ("B2:D8"), a type and a title. The range's first row and first
' column are labels when they hold text: columns are the series (one bar colour or line
' each) and rows the categories, or the other way round when the range is wider than
' tall. A pie shows the first series. The drawing goes through any object with the
' Canvas methods (the form's canvas, or a Boing.Canvas off-screen for the tests).
Option Explicit

Public Const CH_BAR As Long = 0
Public Const CH_LINE As Long = 1
Public Const CH_PIE As Long = 2

Public NCharts As Long
Public chType() As Long
Public chRange() As String
Public chTitle() As String
Public chRow() As Long                ' where the chart floats over the sheet: top-left cell,
Public chCol() As Long                ' and size in pixels
Public chW() As Long
Public chH() As Long

' the data of a chart, filled by ChartData
Private dN As Long                    ' categories
Private dS As Long                    ' series
Private dVal() As Double              ' dVal(series * dN + cat)
Private dCat() As String
Private dSer() As String

Private chInit As Boolean

Public Sub ClearCharts()
    NCharts = 0
    ReDim chType(0 To 7): ReDim chRange(0 To 7): ReDim chTitle(0 To 7)
    ReDim chRow(0 To 7): ReDim chCol(0 To 7): ReDim chW(0 To 7): ReDim chH(0 To 7)
    chInit = True
End Sub

Public Function AddChart(ByVal kind As Long, ByVal rng As String, ByVal title As String) As Long
    If Not chInit Then ClearCharts
    If NCharts > UBound(chType) Then
        ReDim Preserve chType(0 To NCharts * 2): ReDim Preserve chRange(0 To NCharts * 2): ReDim Preserve chTitle(0 To NCharts * 2)
        ReDim Preserve chRow(0 To NCharts * 2): ReDim Preserve chCol(0 To NCharts * 2)
        ReDim Preserve chW(0 To NCharts * 2): ReDim Preserve chH(0 To NCharts * 2)
    End If
    chType(NCharts) = kind: chRange(NCharts) = UCase$(rng): chTitle(NCharts) = title
    chRow(NCharts) = 1: chCol(NCharts) = 4: chW(NCharts) = 300: chH(NCharts) = 190
    NCharts = NCharts + 1
    AddChart = NCharts - 1
    Modified = True
End Function

Public Sub RemoveChart(ByVal i As Long)
    Dim j As Long
    If i < 0 Or i >= NCharts Then Exit Sub
    For j = i To NCharts - 2
        chType(j) = chType(j + 1): chRange(j) = chRange(j + 1): chTitle(j) = chTitle(j + 1)
        chRow(j) = chRow(j + 1): chCol(j) = chCol(j + 1): chW(j) = chW(j + 1): chH(j) = chH(j + 1)
    Next j
    NCharts = NCharts - 1
    Modified = True
End Sub

Public Function ChartTypeName(ByVal k As Long) As String
    Select Case k
    Case CH_BAR: ChartTypeName = "bar"
    Case CH_LINE: ChartTypeName = "line"
    Case CH_PIE: ChartTypeName = "pie"
    End Select
End Function

Public Function ChartsAsText() As String
    Dim i As Long, s As String
    For i = 0 To NCharts - 1
        s = s & "CHART" & vbTab & ChartTypeName(chType(i)) & vbTab & chRange(i) & vbTab & EscapeField(chTitle(i)) & _
            vbTab & CellName(chRow(i), chCol(i)) & vbTab & chW(i) & vbTab & chH(i) & vbLf
    Next i
    ChartsAsText = s
End Function

Public Sub ChartsFromText(ByVal rest As String)
    Dim lines() As String, f() As String, i As Long, k As Long, n As Long, r As Long, c As Long
    ClearCharts
    If rest = "" Then Exit Sub
    lines = Split(rest, vbLf)
    For i = 0 To UBound(lines)
        If Left$(lines(i), 6) = "CHART" & vbTab Then
            f = Split(lines(i), vbTab)
            If UBound(f) >= 3 Then
                Select Case f(1)
                Case "line": k = CH_LINE
                Case "pie": k = CH_PIE
                Case Else: k = CH_BAR
                End Select
                n = AddChart(k, f(2), UnescapeField(f(3)))
                If UBound(f) >= 6 Then
                    If ParseCellName(f(4), r, c) Then chRow(n) = r: chCol(n) = c
                    If Val(f(5)) >= 60 Then chW(n) = Val(f(5))
                    If Val(f(6)) >= 40 Then chH(n) = Val(f(6))
                End If
            End If
        End If
    Next i
    Modified = False
End Sub

' "B2:D8" -> corners; False if it is not a range
Public Function ParseRange(ByVal s As String, r1 As Long, c1 As Long, r2 As Long, c2 As Long) As Boolean
    Dim p As Long, t As Long
    p = InStr(s, ":")
    If p = 0 Then
        If Not ParseCellName(s, r1, c1) Then Exit Function
        r2 = r1: c2 = c1
    Else
        If Not ParseCellName(Left$(s, p - 1), r1, c1) Then Exit Function
        If Not ParseCellName(Mid$(s, p + 1), r2, c2) Then Exit Function
    End If
    If r2 < r1 Then t = r1: r1 = r2: r2 = t
    If c2 < c1 Then t = c1: c1 = c2: c2 = t
    If r2 >= NR Then r2 = NR - 1
    If c2 >= NC Then c2 = NC - 1
    ParseRange = r1 <= r2 And c1 <= c2
End Function

Public Function RangeName(ByVal r1 As Long, ByVal c1 As Long, ByVal r2 As Long, ByVal c2 As Long) As String
    RangeName = CellName(r1, c1) & ":" & CellName(r2, c2)
End Function

' Read the chart's numbers into dVal/dCat/dSer. Returns False if there are none.
Public Function ChartData(ByVal rng As String) As Boolean
    Dim r1 As Long, c1 As Long, r2 As Long, c2 As Long, hasRowLbl As Boolean, hasColLbl As Boolean
    Dim byCols As Boolean, i As Long, j As Long, r As Long, c As Long, k As Long, any As Boolean
    If Not ParseRange(rng, r1, c1, r2, c2) Then Exit Function
    ' a header row: text in the first row (beyond the corner)
    ' labels: text in the first row (after the corner) / the first column (below it)
    For c = c1 + 1 To c2
        If CellKind(r1, c) = KTEXT Then hasColLbl = True
    Next c
    For r = r1 + 1 To r2
        If CellKind(r, c1) = KTEXT Then hasRowLbl = True
    Next r
    If c1 = c2 And CellKind(r1, c1) = KTEXT Then hasColLbl = True
    If r1 = r2 And CellKind(r1, c1) = KTEXT Then hasRowLbl = True
    If hasColLbl And r1 = r2 Then hasColLbl = False
    If hasRowLbl And c1 = c2 Then hasRowLbl = False
    Dim dr1 As Long, dc1 As Long
    dr1 = r1: dc1 = c1
    If hasColLbl Then dr1 = r1 + 1
    If hasRowLbl Then dc1 = c1 + 1
    If dr1 > r2 Or dc1 > c2 Then Exit Function
    ' series run down the columns unless the data is wider than tall
    byCols = (r2 - dr1) >= (c2 - dc1)
    If byCols Then
        dN = r2 - dr1 + 1: dS = c2 - dc1 + 1
    Else
        dN = c2 - dc1 + 1: dS = r2 - dr1 + 1
    End If
    If dS > 8 Then dS = 8
    ReDim dVal(0 To dS * dN - 1)
    ReDim dCat(0 To dN - 1)
    ReDim dSer(0 To dS - 1)
    For i = 0 To dN - 1
        If byCols Then
            If hasRowLbl Then dCat(i) = CellText(dr1 + i, c1) Else dCat(i) = CStr(i + 1)
        Else
            If hasColLbl Then dCat(i) = CellText(r1, dc1 + i) Else dCat(i) = CStr(i + 1)
        End If
    Next i
    For j = 0 To dS - 1
        If byCols Then
            If hasColLbl Then dSer(j) = CellText(r1, dc1 + j) Else dSer(j) = ColName(dc1 + j)
        Else
            If hasRowLbl Then dSer(j) = CellText(dr1 + j, c1) Else dSer(j) = CStr(dr1 + j + 1)
        End If
        For i = 0 To dN - 1
            If byCols Then r = dr1 + i: c = dc1 + j Else r = dr1 + j: c = dc1 + i
            If CellKind(r, c) = KNUM Then
                dVal(j * dN + i) = CellNum(r, c)
                any = True
            End If
        Next i
    Next j
    ChartData = any
End Function

Public Function SeriesColor(ByVal j As Long) As Long
    Select Case j Mod 8
    Case 0: SeriesColor = RGB(52, 101, 164)
    Case 1: SeriesColor = RGB(230, 120, 30)
    Case 2: SeriesColor = RGB(78, 154, 6)
    Case 3: SeriesColor = RGB(204, 0, 0)
    Case 4: SeriesColor = RGB(117, 80, 123)
    Case 5: SeriesColor = RGB(193, 125, 17)
    Case 6: SeriesColor = RGB(6, 152, 154)
    Case 7: SeriesColor = RGB(136, 138, 133)
    End Select
End Function

' a "nice" step for about n ticks over the span
Private Function NiceStep(ByVal span As Double, ByVal n As Long) As Double
    Dim raw As Double, mag As Double, f As Double
    If span <= 0 Then NiceStep = 1: Exit Function
    raw = span / n
    mag = 10 ^ Int(Log(raw) / Log(10#))
    f = raw / mag
    If f <= 1 Then
        f = 1
    ElseIf f <= 2 Then
        f = 2
    ElseIf f <= 5 Then
        f = 5
    Else
        f = 10
    End If
    NiceStep = f * mag
End Function

Private Function Fit(cv As Object, ByVal s As String, ByVal w As Long) As String
    Do While Len(s) > 1 And cv.TextWidth(s) > w
        s = Left$(s, Len(s) - 1)
    Loop
    Fit = s
End Function

' Draw chart i into the rectangle (x, y, w, h) of the canvas
Public Sub DrawChart(cv As Object, ByVal i As Long, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    DrawChartOf cv, chType(i), chRange(i), chTitle(i), x, y, w, h
End Sub

Public Sub DrawChartOf(cv As Object, ByVal kind As Long, ByVal rng As String, ByVal title As String, _
                       ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    Dim top As Long, th As Long
    cv.Box x, y, w, h, RGB(255, 255, 255)
    cv.Rect x, y, w, h, RGB(150, 150, 150)
    th = cv.TextHeight("A")
    top = y + 6
    If title <> "" Then
        cv.DrawText x + (w - cv.TextWidth(title)) \ 2, top, title, RGB(0, 0, 0)
        top = top + th + 6
    End If
    If Not ChartData(rng) Then
        cv.DrawText x + 8, top + 8, "No numbers in " & rng, RGB(160, 0, 0)
        Exit Sub
    End If
    If kind = CH_PIE Then
        DrawPie cv, x + 6, top, w - 12, y + h - top - 6
    Else
        DrawAxes cv, kind, x + 6, top, w - 12, y + h - top - 6
    End If
End Sub

Private Sub DrawLegend(cv As Object, ByVal x As Long, ByVal y As Long, ByVal n As Long, lbl() As String, ByVal pie As Boolean)
    Dim j As Long, th As Long
    th = cv.TextHeight("A") + 4
    For j = 0 To n - 1
        If pie Then cv.Box x, y + j * th, 8, 8, PieColor(j) Else cv.Box x, y + j * th, 8, 8, SeriesColor(j)
        cv.DrawText x + 12, y + j * th, lbl(j), RGB(0, 0, 0)
    Next j
End Sub

Private Sub DrawAxes(cv As Object, ByVal kind As Long, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    Dim mn As Double, mx As Double, i As Long, j As Long, v As Double, stp As Double, t As Double
    Dim lw As Long, legW As Long, px As Long, py As Long, pw As Long, ph As Long, s As String, th As Long
    Dim zeroY As Long, bw As Long, gw As Long, bx As Long, by As Long, lx As Long, ly As Long, cx As Long
    th = cv.TextHeight("A")
    mn = 0: mx = 0
    For i = 0 To dS * dN - 1
        If dVal(i) < mn Then mn = dVal(i)
        If dVal(i) > mx Then mx = dVal(i)
    Next i
    If mx = mn Then mx = mn + 1
    stp = NiceStep(mx - mn, 5)
    mn = Int(mn / stp) * stp
    mx = -Int(-mx / stp) * stp
    ' label width of the value axis
    lw = 0
    t = mn
    Do While t <= mx + stp / 2
        s = GeneralText(t)
        If cv.TextWidth(s) > lw Then lw = cv.TextWidth(s)
        t = t + stp
    Loop
    legW = 0
    If dS > 1 Then
        For j = 0 To dS - 1
            If cv.TextWidth(dSer(j)) + 16 > legW Then legW = cv.TextWidth(dSer(j)) + 16
        Next j
        If legW > w \ 3 Then legW = w \ 3
    End If
    px = x + lw + 6
    py = y + th \ 2
    pw = w - lw - 6 - legW - 8
    ph = h - th - 8 - th \ 2
    If pw < 20 Or ph < 20 Then Exit Sub
    ' grid and value labels
    t = mn
    Do While t <= mx + stp / 2
        ly = py + ph - CLng((t - mn) / (mx - mn) * ph)
        cv.Line px, ly, px + pw, ly, RGB(225, 225, 225)
        s = GeneralText(t)
        cv.DrawText px - 4 - cv.TextWidth(s), ly - th \ 2, s, RGB(60, 60, 60)
        t = t + stp
    Loop
    zeroY = py + ph - CLng((0 - mn) / (mx - mn) * ph)
    cv.Line px, py, px, py + ph, RGB(80, 80, 80)
    cv.Line px, zeroY, px + pw, zeroY, RGB(80, 80, 80)
    gw = pw \ dN
    If gw < 1 Then gw = 1
    ' category labels (as many as fit)
    Dim every As Long, maxw As Long
    maxw = 1
    For i = 0 To dN - 1
        If cv.TextWidth(dCat(i)) > maxw Then maxw = cv.TextWidth(dCat(i))
    Next i
    every = (maxw + 6) \ gw + 1
    For i = 0 To dN - 1 Step every
        s = Fit(cv, dCat(i), gw * every - 2)
        cx = px + i * gw + gw \ 2
        cv.DrawText cx - cv.TextWidth(s) \ 2, py + ph + 4, s, RGB(60, 60, 60)
    Next i
    If kind = CH_BAR Then
        bw = (gw * 3 \ 4) \ dS
        If bw < 1 Then bw = 1
        For i = 0 To dN - 1
            bx = px + i * gw + (gw - bw * dS) \ 2
            For j = 0 To dS - 1
                v = dVal(j * dN + i)
                by = py + ph - CLng((v - mn) / (mx - mn) * ph)
                If by < zeroY Then
                    cv.Box bx + j * bw, by, bw, zeroY - by, SeriesColor(j)
                ElseIf by > zeroY Then
                    cv.Box bx + j * bw, zeroY + 1, bw, by - zeroY, SeriesColor(j)
                End If
            Next j
        Next i
    Else
        For j = 0 To dS - 1
            For i = 0 To dN - 1
                v = dVal(j * dN + i)
                lx = px + i * gw + gw \ 2
                ly = py + ph - CLng((v - mn) / (mx - mn) * ph)
                If i > 0 Then
                    cv.Line bx, by, lx, ly, SeriesColor(j)
                    cv.Line bx, by + 1, lx, ly + 1, SeriesColor(j)
                End If
                cv.Box lx - 2, ly - 2, 5, 5, SeriesColor(j)
                bx = lx: by = ly
            Next i
        Next j
    End If
    If dS > 1 Then DrawLegend cv, x + w - legW, py, dS, dSer, False
End Sub

Public Function PieColor(ByVal j As Long) As Long
    PieColor = SeriesColor(j)
    If j >= 8 Then PieColor = RGB((j * 53) Mod 200 + 40, (j * 97) Mod 200 + 40, (j * 151) Mod 200 + 40)
End Function

Private Sub DrawPie(cv As Object, ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    Dim total As Double, i As Long, k As Long, n As Long, a0 As Double, a1 As Double, cx As Long, cy As Long, rad As Long
    Dim xs(0 To 63) As Long, ys(0 To 63) As Long, steps As Long, a As Double, legW As Long, s As String, lbl() As String
    Dim th As Long, pct As Double
    th = cv.TextHeight("A")
    For i = 0 To dN - 1
        If dVal(i) > 0 Then total = total + dVal(i)
    Next i
    If total <= 0 Then cv.DrawText x + 4, y + 4, "Nothing to show (no positive numbers)", RGB(160, 0, 0): Exit Sub
    ReDim lbl(0 To dN - 1)
    For i = 0 To dN - 1
        pct = 0
        If dVal(i) > 0 Then pct = dVal(i) / total * 100
        lbl(i) = dCat(i) & " " & Format$(pct, "0") & "%"
        If cv.TextWidth(lbl(i)) + 16 > legW Then legW = cv.TextWidth(lbl(i)) + 16
    Next i
    If legW > w \ 2 Then legW = w \ 2
    rad = (w - legW - 16) \ 2
    If (h - 8) \ 2 < rad Then rad = (h - 8) \ 2
    If rad < 8 Then Exit Sub
    cx = x + 4 + rad
    cy = y + h \ 2
    a0 = -1.5707963267949
    For i = 0 To dN - 1
        If dVal(i) > 0 Then
            a1 = a0 + dVal(i) / total * 6.28318530717959
            ' a fan of polygons, each at most 62 points of the arc plus the centre
            Dim seg0 As Double, seg1 As Double
            seg0 = a0
            Do While seg0 < a1 - 0.000001
                seg1 = seg0 + 3
                If seg1 > a1 Then seg1 = a1
                steps = CLng((seg1 - seg0) * rad / 4) + 1
                If steps > 61 Then steps = 61
                xs(0) = cx: ys(0) = cy
                For k = 0 To steps
                    a = seg0 + (seg1 - seg0) * k / steps
                    xs(k + 1) = cx + CLng(Cos(a) * rad)
                    ys(k + 1) = cy + CLng(Sin(a) * rad)
                Next k
                cv.Polygon xs, ys, steps + 2, PieColor(i), True
                seg0 = seg1
            Loop
            ' a white edge between slices
            cv.Line cx, cy, cx + CLng(Cos(a0) * rad), cy + CLng(Sin(a0) * rad), RGB(255, 255, 255)
            a0 = a1
        End If
    Next i
    cv.Circle cx, cy, rad, RGB(90, 90, 90), False
    n = dN
    If n * (th + 4) > h Then n = h \ (th + 4)
    DrawLegend cv, x + w - legW, y + (h - n * (th + 4)) \ 2, n, lbl, True
End Sub
