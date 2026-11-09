' Tincture - the view: zoom, scrolling, the magnifier, and drawing the picture with its
' overlays (selection, floating image outline, brush outline, grid) into the view canvas
'
' The view is the back buffer of the canvas that holds the images (cv). Zoom is a percentage
' from 25 to 1600. With the magnifier on, the right part of the view shows the area around
' the pointer at magZoom times, as on the classic Amiga paint programs.
Option Explicit

Public viewW As Long, viewH As Long          ' size of the view (the canvas back buffer)
Public zoomPct As Long                       ' 25, 50, 100, 200, ... 1600
Public scrollX As Long, scrollY As Long      ' picture pixel at the view's top-left
Public showGrid As Boolean
Public magOn As Boolean, magZoom As Long
Public magX As Long, magY As Long            ' picture point the magnifier centres on
Public cursorX As Long, cursorY As Long, cursorIn As Boolean   ' pointer in picture pixels
Public antsPhase As Long
Public viewBack As Long                      ' the colour around the picture

Private mainW As Long                        ' width of the main pane (all of it without magnifier)

Public Sub ViewInit(ByVal w As Long, ByVal h As Long)
    viewW = w: viewH = h
    If zoomPct = 0 Then zoomPct = 100
    If magZoom = 0 Then magZoom = 6
    If viewBack = 0 Then viewBack = RGB(72, 76, 88)
    Layout
End Sub

Private Sub Layout()
    If magOn Then mainW = viewW * 3 \ 5 Else mainW = viewW
    ClampScroll
End Sub

Public Function ViewZoom() As Long
    ViewZoom = zoomPct
End Function

' zoom around a view point (the pointer), or the view centre when cx < 0
Public Sub SetViewZoom(ByVal z As Long, Optional ByVal cx As Long = -1, Optional ByVal cy As Long = -1)
    Dim px As Double, py As Double
    If z < 25 Then z = 25
    If z > 1600 Then z = 1600
    If cx < 0 Then cx = mainW \ 2: cy = viewH \ 2
    px = scrollX + cx * 100# / zoomPct
    py = scrollY + cy * 100# / zoomPct
    zoomPct = z
    scrollX = CLng(px - cx * 100# / zoomPct)
    scrollY = CLng(py - cy * 100# / zoomPct)
    ClampScroll
End Sub

Public Sub ZoomIn(Optional ByVal cx As Long = -1, Optional ByVal cy As Long = -1)
    Select Case zoomPct
        Case Is < 50: SetViewZoom 50, cx, cy
        Case Is < 100: SetViewZoom 100, cx, cy
        Case Else: SetViewZoom zoomPct * 2, cx, cy
    End Select
End Sub

Public Sub ZoomOut(Optional ByVal cx As Long = -1, Optional ByVal cy As Long = -1)
    Select Case zoomPct
        Case Is > 100: SetViewZoom zoomPct \ 2, cx, cy
        Case Is > 50: SetViewZoom 50, cx, cy
        Case Else: SetViewZoom 25, cx, cy
    End Select
End Sub

' the largest standard zoom at which the whole picture fits
Public Sub ZoomFit()
    Dim z As Long
    z = 1600
    Do While z > 25 And (docW * z \ 100 > mainW Or docH * z \ 100 > viewH)
        If z > 100 Then z = z \ 2 Else If z = 100 Then z = 50 Else z = 25
    Loop
    zoomPct = z
    scrollX = 0: scrollY = 0
    ClampScroll
End Sub

Public Sub SetMagnifier(ByVal onOff As Boolean)
    magOn = onOff
    Layout
End Sub

Public Sub ScrollBy(ByVal dx As Long, ByVal dy As Long)
    scrollX = scrollX + dx: scrollY = scrollY + dy
    ClampScroll
End Sub

' keep the picture in view; centre it when it is smaller than the view
Public Sub ClampScroll()
    Dim vw As Long, vh As Long
    vw = mainW * 100 \ zoomPct: vh = viewH * 100 \ zoomPct
    If docW <= vw Then
        scrollX = -(vw - docW) \ 2
    Else
        If scrollX > docW - vw Then scrollX = docW - vw
        If scrollX < 0 Then scrollX = 0
    End If
    If docH <= vh Then
        scrollY = -(vh - docH) \ 2
    Else
        If scrollY > docH - vh Then scrollY = docH - vh
        If scrollY < 0 Then scrollY = 0
    End If
End Sub

' view pixel -> picture pixel (floor); inMag = the point is in the magnifier pane
Public Sub ViewToDoc(ByVal sx As Long, ByVal sy As Long, dx As Long, dy As Long)
    Dim mw As Long, mz As Long
    If magOn And sx >= mainW + 4 Then
        mw = viewW - mainW - 4
        mz = zoomPct * magZoom
        dx = magX + FloorDiv((sx - mainW - 4 - mw \ 2) * 100, mz)
        dy = magY + FloorDiv((sy - viewH \ 2) * 100, mz)
        Exit Sub
    End If
    dx = scrollX + FloorDiv(sx * 100, zoomPct)
    dy = scrollY + FloorDiv(sy * 100, zoomPct)
End Sub

Public Function InMagnifier(ByVal sx As Long) As Boolean
    InMagnifier = magOn And sx >= mainW
End Function

Private Function FloorDiv(ByVal a As Long, ByVal b As Long) As Long
    If a >= 0 Then FloorDiv = a \ b Else FloorDiv = -((-a + b - 1) \ b)
End Function

' picture pixel -> view pixel of its top-left corner (main pane)
Public Function DocToViewX(ByVal x As Long) As Long
    DocToViewX = FloorDiv((x - scrollX) * zoomPct, 100)
End Function
Public Function DocToViewY(ByVal y As Long) As Long
    DocToViewY = FloorDiv((y - scrollY) * zoomPct, 100)
End Function

' ---------------------------------------------------------------- drawing

Public Sub RenderView()
    Recomposite
    cv.SetTarget 0
    cv.Box 0, 0, viewW, viewH, viewBack
    DrawPane 0, mainW, scrollX, scrollY, zoomPct, True
    If magOn Then
        Dim mw As Long, mz As Long, sx As Long, sy As Long
        mw = viewW - mainW - 4
        mz = zoomPct * magZoom
        cv.Box mainW, 0, 4, viewH, RGB(30, 30, 36)
        cv.Box mainW + 4, 0, mw, viewH, viewBack
        sx = magX - (mw \ 2) * 100 \ mz
        sy = magY - (viewH \ 2) * 100 \ mz
        DrawPane mainW + 4, mw, sx, sy, mz, False
        ' where the magnifier looks, in the main pane
        cv.Rect DocToViewX(sx), DocToViewY(sy), mw * zoomPct \ mz + 1, viewH * zoomPct \ mz + 1, RGB(255, 210, 0)
    End If
End Sub

' one pane: picture area (sx0, sy0) at zoom z into view columns x0 .. x0 + w - 1
Private Sub DrawPane(ByVal x0 As Long, ByVal w As Long, ByVal sx0 As Long, ByVal sy0 As Long, ByVal z As Long, ByVal main As Boolean)
    Dim srcX As Long, srcY As Long, srcW As Long, srcH As Long, dX As Long, dY As Long
    Dim x1 As Long, y1 As Long, x2 As Long, y2 As Long, k As Long, gx As Long, gy As Long, r As Long
    ' visible part of the picture
    srcX = sx0: srcY = sy0
    srcW = (w * 100 + z - 1) \ z + 1: srcH = (viewH * 100 + z - 1) \ z + 1
    If srcX < 0 Then srcW = srcW + srcX: srcX = 0
    If srcY < 0 Then srcH = srcH + srcY: srcY = 0
    If srcX + srcW > docW Then srcW = docW - srcX
    If srcY + srcH > docH Then srcH = docH - srcY
    If srcW <= 0 Or srcH <= 0 Then Exit Sub
    ' (the main pane may draw under the magnifier: that is drawn after it)
    dX = x0 + FloorDiv((srcX - sx0) * z, 100): dY = FloorDiv((srcY - sy0) * z, 100)
    cv.DrawImageScaled comp, srcX, srcY, srcW, srcH, dX, dY, srcW * z \ 100, srcH * z \ 100, True
    ' the symmetry axes
    If main And symmetry <> 0 Then
        If symmetry <> 2 Then k = x0 + FloorDiv((docW * 50 - sx0 * 100) * z \ 100, 100): cv.DashRect k, dY, 1, srcH * z \ 100, RGB(0, 200, 255), viewBack, 0
        If symmetry >= 2 Then k = FloorDiv((docH * 50 - sy0 * 100) * z \ 100, 100): cv.DashRect dX, k, srcW * z \ 100, 1, RGB(0, 200, 255), viewBack, 0
    End If
    ' a frame around the picture
    If main Then cv.Rect DocToViewX(0) - 1, DocToViewY(0) - 1, docW * z \ 100 + 2, docH * z \ 100 + 2, RGB(20, 20, 24)
    ' pixel grid when zoomed in far
    If (showGrid Or Not main) And z >= 600 Then
        For gx = srcX To srcX + srcW
            k = x0 + FloorDiv((gx - sx0) * z, 100)
            If k >= x0 And k < x0 + w Then cv.Line k, dY, k, dY + srcH * z \ 100 - 1, RGB(110, 110, 120)
        Next
        For gy = srcY To srcY + srcH
            k = FloorDiv((gy - sy0) * z, 100)
            cv.Line dX, k, IIf(dX + srcW * z \ 100 - 1 < x0 + w - 1, dX + srcW * z \ 100 - 1, x0 + w - 1), k, RGB(110, 110, 120)
        Next
    End If
    ' selection: marching ants
    If selActive Then
        x1 = x0 + FloorDiv((selX - sx0) * z, 100): y1 = FloorDiv((selY - sy0) * z, 100)
        x2 = x0 + FloorDiv((selX + selW - sx0) * z, 100): y2 = FloorDiv((selY + selH - sy0) * z, 100)
        cv.DashRect x1 - 1, y1 - 1, x2 - x1 + 2, y2 - y1 + 2, vbWhite, vbBlack, antsPhase
    End If
    ' the brush outline under the pointer
    If main And cursorIn And Not IsStroking() Then
        Select Case curTool
            Case T_FREEHAND, T_ERASER, T_LINE, T_RECT, T_ELLIPSE
                If brushImg And curTool = T_FREEHAND Then
                    x1 = x0 + FloorDiv((cursorX - cv.ImageWidth(brushImg) \ 2 - sx0) * z, 100)
                    y1 = FloorDiv((cursorY - cv.ImageHeight(brushImg) \ 2 - sy0) * z, 100)
                    cv.DashRect x1, y1, cv.ImageWidth(brushImg) * z \ 100, cv.ImageHeight(brushImg) * z \ 100, vbWhite, vbBlack, 0
                ElseIf brushSize * z \ 100 >= 4 Then
                    r = brushSize * z \ 200
                    x1 = x0 + FloorDiv((cursorX - sx0) * z, 100) + z \ 200
                    y1 = FloorDiv((cursorY - sy0) * z, 100) + z \ 200
                    If brushSquare Then cv.Rect x1 - r, y1 - r, 2 * r, 2 * r, vbWhite Else cv.Circle x1, y1, r, vbWhite
                End If
            Case T_AIRBRUSH
                x1 = x0 + FloorDiv((cursorX - sx0) * z, 100)
                y1 = FloorDiv((cursorY - sy0) * z, 100)
                cv.Circle x1, y1, airRadius * z \ 100, RGB(200, 200, 200)
        End Select
    End If
End Sub
