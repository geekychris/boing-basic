' Tincture - the tools: what a press, drag and release of the mouse do to the picture
'
' Coordinates are picture pixels. Button 1 paints with the foreground colour, button 2 with the
' background colour (as on every Amiga paint program). Shift constrains shapes (squares,
' circles, 45 degree lines). The ARexx commands and the tests drive the same entry points
' (ToolDown / ToolMove / ToolUp), so a scripted stroke is exactly a mouse stroke.
Option Explicit

Public Const T_FREEHAND As Long = 0
Public Const T_LINE As Long = 1
Public Const T_RECT As Long = 2
Public Const T_RECTF As Long = 3
Public Const T_ELLIPSE As Long = 4
Public Const T_ELLIPSEF As Long = 5
Public Const T_FILL As Long = 6
Public Const T_AIRBRUSH As Long = 7
Public Const T_TEXT As Long = 8
Public Const T_SELECT As Long = 9
Public Const T_PICK As Long = 10
Public Const T_ERASER As Long = 11
Public Const T_COUNT As Long = 12

Public curTool As Long
Public brushSize As Long         ' 1..64
Public brushSquare As Boolean
Public brushImg As Long          ' custom brush (0 = the round/square brush)
Public brushOwnColours As Boolean ' custom brush: its own colours, or painted in one colour
Public airRadius As Long, airDensity As Long
Public fillTolerance As Long
Public textScale As Long
Public pendingText As String     ' the Text tool's text (set by the UI or ARexx before the click)

' selection (a rectangle of the picture), and the internal clipboard
Public selActive As Boolean
Public selX As Long, selY As Long, selW As Long, selH As Long
Public clipImg As Long

' the stroke in progress
Private downX As Long, downY As Long, lastX As Long, lastY As Long, strokeCol As Long
Private stroking As Boolean, strokeBtn As Long
Private dragMode As Long         ' select tool: 0 none, 1 new rectangle, 2 moving the float
Private grabDX As Long, grabDY As Long

Public Sub ToolsInit()
    If brushSize = 0 Then brushSize = 1
    If airRadius = 0 Then airRadius = 12
    If airDensity = 0 Then airDensity = 24
    If textScale = 0 Then textScale = 2
    brushOwnColours = True
End Sub

Public Function ToolName(ByVal t As Long) As String
    ToolName = Choose(t + 1, "Freehand", "Line", "Rectangle", "Filled Rectangle", "Ellipse", "Filled Ellipse", _
                      "Flood Fill", "Airbrush", "Text", "Select", "Pick Colour", "Eraser")
End Function

Public Function IsStroking() As Boolean
    IsStroking = stroking
End Function

Private Function ButtonColour(ByVal btn As Long) As Long
    If btn And 2 Then ButtonColour = bgColor Else ButtonColour = fgColor
End Function

' the colour the eraser leaves: transparent on upper layers, the background colour at the bottom
Private Function EraseColour() As Long
    If curLayer = 1 Then EraseColour = bgColor Else EraseColour = -1
End Function

' ---------------------------------------------------------------- entry points

Public Sub ToolDown(ByVal x As Long, ByVal y As Long, ByVal btn As Long, ByVal shift As Long)
    If docW = 0 Then Exit Sub
    If stroking Then ToolUp lastX, lastY, strokeBtn, shift
    downX = x: downY = y: lastX = x: lastY = y
    strokeBtn = btn
    strokeCol = ButtonColour(btn)
    Select Case curTool
        Case T_SELECT
            SelectDown x, y, shift
            stroking = True
            Exit Sub
        Case T_PICK
            PickAt x, y, btn
            Exit Sub
    End Select
    If floatImg Then DropFloat
    stroking = True
    Select Case curTool
        Case T_FREEHAND, T_ERASER
            If curTool = T_ERASER Then strokeCol = EraseColour()
            BeginEdit IIf(curTool = T_ERASER, "Erase", "Freehand")
            Paint x, y, x, y
        Case T_AIRBRUSH
            BeginEdit "Airbrush"
            SprayAt x, y
        Case T_FILL
            FillAt x, y
            stroking = False
        Case T_TEXT
            PlaceText x, y
            stroking = False
        Case Else
            ShapePreview x, y, shift
    End Select
End Sub

Public Sub ToolMove(ByVal x As Long, ByVal y As Long, ByVal shift As Long)
    If Not stroking Then Exit Sub
    If x = lastX And y = lastY Then Exit Sub
    Select Case curTool
        Case T_FREEHAND, T_ERASER
            Paint lastX, lastY, x, y
        Case T_AIRBRUSH
            SprayAt x, y
        Case T_SELECT
            SelectMove x, y, shift
        Case T_LINE, T_RECT, T_RECTF, T_ELLIPSE, T_ELLIPSEF
            ShapePreview x, y, shift
    End Select
    lastX = x: lastY = y
End Sub

Public Sub ToolUp(ByVal x As Long, ByVal y As Long, ByVal btn As Long, ByVal shift As Long)
    If Not stroking Then Exit Sub
    If x <> lastX Or y <> lastY Then ToolMove x, y, shift
    stroking = False
    Select Case curTool
        Case T_FREEHAND, T_ERASER, T_AIRBRUSH
            EndEdit
        Case T_SELECT
            SelectUp x, y
        Case T_LINE, T_RECT, T_RECTF, T_ELLIPSE, T_ELLIPSEF
            ClearPreview
            BeginEdit ToolName(curTool)
            DrawShape x, y, shift, False
            EndEdit
    End Select
End Sub

' the airbrush keeps spraying while the button is held (the form's timer calls this)
Public Sub ToolTick()
    If stroking And curTool = T_AIRBRUSH Then SprayAt lastX, lastY
End Sub

' Esc: give up the stroke or the floating selection
Public Sub ToolCancel()
    If stroking Then
        stroking = False
        ClearPreview
        CancelEdit
    End If
    If floatImg Then CancelFloat
End Sub

' ---------------------------------------------------------------- painting

Private Sub Paint(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long)
    Dim r As Long
    cv.SetTarget layers(curLayer).img
    If brushImg And curTool = T_FREEHAND Then
        If brushOwnColours Then
            cv.StampLine brushImg, x1, y1, x2, y2, -2, 1
        Else
            cv.StampLine brushImg, x1, y1, x2, y2, strokeCol, 1
        End If
        r = (IIf(cv.ImageWidth(brushImg) > cv.ImageHeight(brushImg), cv.ImageWidth(brushImg), cv.ImageHeight(brushImg))) \ 2 + 1
    Else
        cv.BrushLine x1, y1, x2, y2, brushSize, strokeCol, IIf(brushSquare, 1, 0)
        r = brushSize \ 2 + 1
    End If
    cv.SetTarget 0
    EditTouched IIf(x1 < x2, x1, x2) - r, IIf(y1 < y2, y1, y2) - r, IIf(x1 > x2, x1, x2) + r, IIf(y1 > y2, y1, y2) + r
End Sub

Private Sub SprayAt(ByVal x As Long, ByVal y As Long)
    cv.SetTarget layers(curLayer).img
    cv.Spray x, y, airRadius, airDensity, strokeCol
    cv.SetTarget 0
    EditTouched x - airRadius, y - airRadius, x + airRadius, y + airRadius
End Sub

Private Sub FillAt(ByVal x As Long, ByVal y As Long)
    Dim n As Long, b As Variant
    If x < 0 Or y < 0 Or x >= docW Or y >= docH Then Exit Sub
    BeginEdit "Flood Fill"
    cv.SetTarget layers(curLayer).img
    n = cv.FloodFill(x, y, strokeCol, fillTolerance)
    cv.SetTarget 0
    If n > 0 Then
        b = cv.FillBounds()
        EditTouched b(0), b(1), b(0) + b(2) - 1, b(1) + b(3) - 1
    End If
    EndEdit
End Sub

Private Sub PickAt(ByVal x As Long, ByVal y As Long, ByVal btn As Long)
    Dim c As Long
    Recomposite
    c = cv.ImagePoint(comp, x, y)
    If c < 0 Then Exit Sub
    If btn And 2 Then bgColor = c Else fgColor = c
End Sub

' shapes: corner / centre at the press, the other corner / radius at (x, y)
Private Sub ShapeGeom(ByVal x As Long, ByVal y As Long, ByVal shift As Long, x1 As Long, y1 As Long, x2 As Long, y2 As Long)
    Dim dx As Long, dy As Long, m As Long
    x1 = downX: y1 = downY: x2 = x: y2 = y
    If (shift And 1) = 0 Then Exit Sub
    dx = x - downX: dy = y - downY
    If curTool = T_LINE Then
        ' snap to 0, 45 or 90 degrees
        If Abs(dx) > 2 * Abs(dy) Then
            y2 = downY
        ElseIf Abs(dy) > 2 * Abs(dx) Then
            x2 = downX
        Else
            m = IIf(Abs(dx) > Abs(dy), Abs(dx), Abs(dy))
            x2 = downX + Sgn(dx) * m: y2 = downY + Sgn(dy) * m
        End If
    Else
        m = IIf(Abs(dx) > Abs(dy), Abs(dx), Abs(dy))
        x2 = downX + IIf(dx < 0, -m, m): y2 = downY + IIf(dy < 0, -m, m)
    End If
End Sub

Private Sub DrawShape(ByVal x As Long, ByVal y As Long, ByVal shift As Long, ByVal toPreview As Boolean)
    Dim x1 As Long, y1 As Long, x2 As Long, y2 As Long, r As Long, rx As Long, ry As Long, t As Long
    ShapeGeom x, y, shift, x1, y1, x2, y2
    If toPreview Then cv.SetTarget preview Else cv.SetTarget layers(curLayer).img
    r = brushSize \ 2 + 1
    Select Case curTool
        Case T_LINE
            cv.BrushLine x1, y1, x2, y2, brushSize, strokeCol, IIf(brushSquare, 1, 0)
        Case T_RECT, T_RECTF
            If x1 > x2 Then t = x1: x1 = x2: x2 = t
            If y1 > y2 Then t = y1: y1 = y2: y2 = t
            If curTool = T_RECTF Then
                cv.Line x1, y1, x2, y2, strokeCol, "BF"
            ElseIf brushSize <= 1 Then
                cv.Line x1, y1, x2, y2, strokeCol, "B"
            Else
                cv.BrushLine x1, y1, x2, y1, brushSize, strokeCol, 1
                cv.BrushLine x2, y1, x2, y2, brushSize, strokeCol, 1
                cv.BrushLine x2, y2, x1, y2, brushSize, strokeCol, 1
                cv.BrushLine x1, y2, x1, y1, brushSize, strokeCol, 1
            End If
        Case T_ELLIPSE, T_ELLIPSEF
            ' the ellipse inside the dragged box
            If x1 > x2 Then t = x1: x1 = x2: x2 = t
            If y1 > y2 Then t = y1: y1 = y2: y2 = t
            rx = (x2 - x1) \ 2: ry = (y2 - y1) \ 2
            If curTool = T_ELLIPSEF Or brushSize <= 1 Then
                cv.Ellipse x1 + rx, y1 + ry, rx, ry, strokeCol, curTool = T_ELLIPSEF
            Else
                OutlineEllipse x1 + rx, y1 + ry, rx, ry
            End If
    End Select
    cv.SetTarget 0
    If toPreview Then
        PreviewTouched IIf(x1 < x2, x1, x2) - r, IIf(y1 < y2, y1, y2) - r, IIf(x1 > x2, x1, x2) + r, IIf(y1 > y2, y1, y2) + r
    Else
        EditTouched IIf(x1 < x2, x1, x2) - r, IIf(y1 < y2, y1, y2) - r, IIf(x1 > x2, x1, x2) + r, IIf(y1 > y2, y1, y2) + r
    End If
End Sub

' a thick ellipse outline: brush segments around it
Private Sub OutlineEllipse(ByVal cx As Long, ByVal cy As Long, ByVal rx As Long, ByVal ry As Long)
    Dim i As Long, n As Long, a As Double, px As Long, py As Long, nx As Long, ny As Long
    n = (rx + ry) \ 2
    If n < 12 Then n = 12
    If n > 180 Then n = 180
    px = cx + rx: py = cy
    For i = 1 To n
        a = i * 6.28318530718 / n
        nx = cx + CLng(rx * Cos(a)): ny = cy + CLng(ry * Sin(a))
        cv.BrushLine px, py, nx, ny, brushSize, strokeCol, 0
        px = nx: py = ny
    Next
End Sub

Private Sub ShapePreview(ByVal x As Long, ByVal y As Long, ByVal shift As Long)
    ClearPreview
    DrawShape x, y, shift, True
End Sub

' ---------------------------------------------------------------- text

Private Sub PlaceText(ByVal x As Long, ByVal y As Long)
    Dim w As Long, h As Long, img As Long
    If pendingText = "" Then Exit Sub
    w = cv.TextWidth(pendingText) * textScale
    h = 9 * textScale
    img = cv.CreateImage(w, h)
    cv.SetTarget img
    cv.DrawTextScaled 0, 0, pendingText, strokeCol, textScale
    cv.SetTarget 0
    MakeFloat img, x, y, "Text"
End Sub

' ---------------------------------------------------------------- selection and the floating image

Public Sub SelectNone()
    selActive = False
    selW = 0: selH = 0
End Sub

Public Sub SelectAll()
    selActive = True
    selX = 0: selY = 0: selW = docW: selH = docH
End Sub

Public Sub SelectRect(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    If x < 0 Then w = w + x: x = 0
    If y < 0 Then h = h + y: y = 0
    If x + w > docW Then w = docW - x
    If y + h > docH Then h = docH - y
    If w < 1 Or h < 1 Then SelectNone: Exit Sub
    selActive = True
    selX = x: selY = y: selW = w: selH = h
End Sub

Private Function InFloat(ByVal x As Long, ByVal y As Long) As Boolean
    If floatImg = 0 Then Exit Function
    InFloat = x >= floatX And y >= floatY And x < floatX + cv.ImageWidth(floatImg) And y < floatY + cv.ImageHeight(floatImg)
End Function

Private Sub SelectDown(ByVal x As Long, ByVal y As Long, ByVal shift As Long)
    If InFloat(x, y) Then
        dragMode = 2
        grabDX = x - floatX: grabDY = y - floatY
        Exit Sub
    End If
    If floatImg Then DropFloat
    If selActive And x >= selX And y >= selY And x < selX + selW And y < selY + selH Then
        LiftSelection (shift And 2) <> 0       ' Ctrl+drag: move a copy
        dragMode = 2
        grabDX = x - floatX: grabDY = y - floatY
        Exit Sub
    End If
    dragMode = 1
    SelectNone
End Sub

Private Sub SelectMove(ByVal x As Long, ByVal y As Long, ByVal shift As Long)
    Dim x1 As Long, y1 As Long, x2 As Long, y2 As Long
    If dragMode = 1 Then
        x1 = IIf(downX < x, downX, x): x2 = IIf(downX < x, x, downX)
        y1 = IIf(downY < y, downY, y): y2 = IIf(downY < y, y, downY)
        SelectRect x1, y1, x2 - x1 + 1, y2 - y1 + 1
    ElseIf dragMode = 2 Then
        MoveFloat x - grabDX, y - grabDY
    End If
End Sub

Private Sub SelectUp(ByVal x As Long, ByVal y As Long)
    If dragMode = 1 And x = downX And y = downY Then SelectNone
    dragMode = 0
End Sub

' the selection becomes a floating image (its place on the layer cleared unless keepCopy)
Public Sub LiftSelection(ByVal keepCopy As Boolean)
    Dim img As Long
    If Not selActive Then Exit Sub
    BeginEdit IIf(keepCopy, "Duplicate", "Move")
    img = cv.CopyImage(layers(curLayer).img, selX, selY, selW, selH)
    If Not keepCopy Then ClearArea selX, selY, selW, selH
    floatImg = img: floatX = selX: floatY = selY
    DirtyRect selX, selY, selX + selW - 1, selY + selH - 1
End Sub

Private Sub ClearArea(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    cv.SetTarget layers(curLayer).img
    If curLayer = 1 Then cv.Box x, y, w, h, bgColor Else cv.ClearRect x, y, w, h
    cv.SetTarget 0
    EditTouched x, y, x + w - 1, y + h - 1
End Sub

Private Sub MakeFloat(ByVal img As Long, ByVal x As Long, ByVal y As Long, ByVal label As String)
    If floatImg Then DropFloat
    BeginEdit label
    floatImg = img: floatX = x: floatY = y
    selActive = True
    selX = x: selY = y: selW = cv.ImageWidth(img): selH = cv.ImageHeight(img)
    DirtyRect x, y, x + selW - 1, y + selH - 1
    curTool = T_SELECT
End Sub

Public Sub MoveFloat(ByVal x As Long, ByVal y As Long)
    Dim w As Long, h As Long
    If floatImg = 0 Then Exit Sub
    w = cv.ImageWidth(floatImg): h = cv.ImageHeight(floatImg)
    DirtyRect floatX, floatY, floatX + w - 1, floatY + h - 1
    floatX = x: floatY = y
    selActive = True
    selX = x: selY = y: selW = w: selH = h
    DirtyRect x, y, x + w - 1, y + h - 1
End Sub

' put the floating image down on the layer: one undo step with the lift/paste
Public Sub DropFloat()
    Dim w As Long, h As Long
    If floatImg = 0 Then Exit Sub
    w = cv.ImageWidth(floatImg): h = cv.ImageHeight(floatImg)
    If Not EditIsOpen() Then BeginEdit "Paste"
    cv.SetTarget layers(curLayer).img
    cv.DrawImage floatImg, floatX, floatY
    cv.SetTarget 0
    EditTouched floatX, floatY, floatX + w - 1, floatY + h - 1
    cv.FreeImage floatImg
    floatImg = 0
    EndEdit
    SelectRect floatX, floatY, w, h
End Sub

' for undo/redo: a pending float is dropped first
Public Sub DropFloatQuiet()
    If floatImg Then DropFloat
End Sub

Public Sub CancelFloat()
    Dim w As Long, h As Long
    If floatImg = 0 Then Exit Sub
    w = cv.ImageWidth(floatImg): h = cv.ImageHeight(floatImg)
    DirtyRect floatX, floatY, floatX + w - 1, floatY + h - 1
    cv.FreeImage floatImg
    floatImg = 0
    CancelEdit
End Sub

' ---------------------------------------------------------------- clipboard (internal; the OS clipboard is in the form)

Public Function CopySelection() As Boolean
    If floatImg Then
        If clipImg Then cv.FreeImage clipImg
        clipImg = cv.CopyImage(floatImg)
        CopySelection = True
        Exit Function
    End If
    If Not selActive Then Exit Function
    If clipImg Then cv.FreeImage clipImg
    clipImg = cv.CopyImage(layers(curLayer).img, selX, selY, selW, selH)
    CopySelection = True
End Function

Public Function CutSelection() As Boolean
    If floatImg Then
        CopySelection
        CancelFloat
        CutSelection = True
        Exit Function
    End If
    If Not CopySelection() Then Exit Function
    BeginEdit "Cut"
    ClearArea selX, selY, selW, selH
    EndEdit
    CutSelection = True
End Function

Public Sub ClearSelection()
    If floatImg Then CancelFloat: Exit Sub
    If Not selActive Then Exit Sub
    BeginEdit "Clear"
    ClearArea selX, selY, selW, selH
    EndEdit
End Sub

' paste the clipboard as a floating image at (x, y)
Public Sub PasteAt(ByVal x As Long, ByVal y As Long)
    If clipImg = 0 Then Exit Sub
    MakeFloat cv.CopyImage(clipImg), x, y, "Paste"
End Sub

' paste an image (from the OS clipboard or a file): it becomes the clipboard, then floats
Public Sub PasteImage(ByVal img As Long, ByVal x As Long, ByVal y As Long)
    If clipImg Then cv.FreeImage clipImg
    clipImg = img
    PasteAt x, y
End Sub

' ---------------------------------------------------------------- brushes

' the selection (or floating image) becomes the brush; the background colour is transparent
Public Function BrushFromSelection() As Boolean
    Dim img As Long
    If floatImg Then
        img = cv.CopyImage(floatImg)
    ElseIf selActive Then
        img = cv.CopyImage(layers(curLayer).img, selX, selY, selW, selH)
    Else
        Exit Function
    End If
    cv.SetTarget img
    cv.ReplaceColor bgColor, -1
    cv.SetTarget 0
    If brushImg Then cv.FreeImage brushImg
    brushImg = img
    brushOwnColours = True
    curTool = T_FREEHAND
    BrushFromSelection = True
End Function

Public Sub BrushReset()
    If brushImg Then cv.FreeImage brushImg
    brushImg = 0
End Sub

Public Sub BrushFlip(ByVal vertical As Boolean)
    If brushImg Then cv.FlipImage brushImg, vertical
End Sub

Public Sub BrushRotate()
    Dim t As Long
    If brushImg = 0 Then Exit Sub
    t = cv.RotateImage(brushImg, 1)
    cv.FreeImage brushImg
    brushImg = t
End Sub

Public Sub BrushScale(ByVal factor As Double)
    Dim t As Long, w As Long, h As Long
    If brushImg = 0 Then Exit Sub
    w = CLng(cv.ImageWidth(brushImg) * factor): h = CLng(cv.ImageHeight(brushImg) * factor)
    If w < 1 Or h < 1 Or w > 1024 Or h > 1024 Then Exit Sub
    t = cv.ScaleImage(brushImg, w, h, False)
    cv.FreeImage brushImg
    brushImg = t
End Sub
