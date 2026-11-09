' Tincture - the document: picture size, layers, palette, colours, the composite
'
' All pictures live as images of one Canvas object (the form's view on AmigaOS, an off-screen
' Boing.Canvas in the host tests), so every pixel operation is one Canvas call in C.
' Layer 1 is the bottom one and is always opaque; upper layers are transparent where nothing
' was painted. The composite (comp) is the flattened picture, kept up to date for the area
' that changed (the dirty rectangle) by Recomposite.
Option Explicit

Public Const APP_VERSION As String = "1.0"
Public Const MAX_LAYERS As Long = 16
Public Const MODE_TRUE As Long = 0
Public Const MODE_INDEXED As Long = 1

Public Type LayerRec
    img As Long
    name As String
    visible As Boolean
    opacity As Long            ' 0..255
End Type

Public cv As Object            ' the canvas that holds every image
Public docW As Long, docH As Long
Public layers(1 To 16) As LayerRec
Public nLayers As Long, curLayer As Long
Public comp As Long            ' the flattened picture
Public preview As Long         ' shape preview, shown above the current layer (transparent)
Public scratch As Long         ' the current layer as it was when an edit began
Public docMode As Long         ' MODE_TRUE / MODE_INDEXED
Public pal(0 To 255) As Long, palCount As Long
Public fgColor As Long, bgColor As Long
Public docDirty As Boolean     ' changed since last save
Public docPath As String       ' "" = untitled
Public docGen As Long          ' bumped on every change (autosave watches it)

' floating selection (paste / move): an image shown above the current layer until dropped
Public floatImg As Long, floatX As Long, floatY As Long

' the area of comp that must be rebuilt, and of the view that must be redrawn
Public dirtyX1 As Long, dirtyY1 As Long, dirtyX2 As Long, dirtyY2 As Long
Public previewX1 As Long, previewY1 As Long, previewX2 As Long, previewY2 As Long

Public Sub DocAttach(canvasObj As Object)
    Set cv = canvasObj
End Sub

' a new picture: w x h, one opaque layer filled with the background colour
Public Sub DocNew(ByVal w As Long, ByVal h As Long, Optional ByVal fill As Long = -2)
    Dim i As Long
    If w < 1 Or h < 1 Or w > 4096 Or h > 4096 Then Err.Raise 380, "Tincture", "Picture size must be 1 to 4096"
    UndoClear              ' first: it keeps the images the document still uses
    FreeDocImages
    docMode = MODE_TRUE
    If palCount = 0 Then DefaultPalette
    If fgColor = 0 And bgColor = 0 Then fgColor = vbBlack: bgColor = vbWhite
    If fill = -2 Then fill = bgColor
    docW = w: docH = h
    nLayers = 1: curLayer = 1
    layers(1).img = cv.CreateImage(w, h)
    layers(1).name = "Background"
    layers(1).visible = True
    layers(1).opacity = 255
    cv.SetTarget layers(1).img
    cv.Box 0, 0, w, h, fill
    cv.SetTarget 0
    comp = cv.CreateImage(w, h)
    preview = cv.CreateImage(w, h)
    scratch = cv.CreateImage(w, h)
    floatImg = 0
    docPath = ""
    docDirty = False
    docGen = docGen + 1
    ClearPreviewRect
    DirtyAll
    Recomposite
End Sub

' take over a loaded picture as a new single-layer document
Public Sub DocFromImage(ByVal img As Long)
    Dim w As Long, h As Long
    w = cv.ImageWidth(img): h = cv.ImageHeight(img)
    DocNew w, h, bgColor
    cv.SetTarget layers(1).img
    cv.DrawImageBlend img, 0, 0, 255       ' transparent parts show the background colour
    cv.SetTarget 0
    cv.FreeImage img
    DirtyAll
    Recomposite
End Sub

Private Sub FreeDocImages()
    Dim i As Long
    If docW = 0 Then Exit Sub
    For i = 1 To nLayers
        If layers(i).img Then cv.FreeImage layers(i).img
        layers(i).img = 0
    Next
    If comp Then cv.FreeImage comp
    If preview Then cv.FreeImage preview
    If scratch Then cv.FreeImage scratch
    If floatImg Then cv.FreeImage floatImg
    comp = 0: preview = 0: scratch = 0: floatImg = 0
    nLayers = 0
End Sub

' the classic 32-colour palette: greys, then hues in two brightnesses
Public Sub DefaultPalette()
    Dim i As Long, h As Long
    palCount = 32
    For i = 0 To 7
        pal(i) = RGB(i * 255 \ 7, i * 255 \ 7, i * 255 \ 7)
    Next
    For i = 0 To 11
        pal(8 + i) = HueColor(i * 30, 255, 230)
        pal(20 + i) = HueColor(i * 30, 150, 150)
    Next
End Sub

' hue 0..359, saturation and value 0..255 -> VB colour
Public Function HueColor(ByVal hue As Long, ByVal sat As Long, ByVal value As Long) As Long
    Dim r As Long, g As Long, b As Long
    HsvToRgb hue, sat, value, r, g, b
    HueColor = RGB(r, g, b)
End Function

Public Sub HsvToRgb(ByVal h As Long, ByVal s As Long, ByVal v As Long, r As Long, g As Long, b As Long)
    Dim region As Long, rem6 As Long, p As Long, q As Long, t As Long
    h = ((h Mod 360) + 360) Mod 360
    If s = 0 Then r = v: g = v: b = v: Exit Sub
    region = h \ 60
    rem6 = (h - region * 60) * 255 \ 60
    p = (v * (255 - s)) \ 255
    q = (v * (255 - (s * rem6) \ 255)) \ 255
    t = (v * (255 - (s * (255 - rem6)) \ 255)) \ 255
    Select Case region
        Case 0: r = v: g = t: b = p
        Case 1: r = q: g = v: b = p
        Case 2: r = p: g = v: b = t
        Case 3: r = p: g = q: b = v
        Case 4: r = t: g = p: b = v
        Case Else: r = v: g = p: b = q
    End Select
End Sub

Public Sub RgbToHsv(ByVal r As Long, ByVal g As Long, ByVal b As Long, h As Long, s As Long, v As Long)
    Dim mx As Long, mn As Long, d As Long
    mx = r: If g > mx Then mx = g
    If b > mx Then mx = b
    mn = r: If g < mn Then mn = g
    If b < mn Then mn = b
    v = mx
    d = mx - mn
    If mx = 0 Then s = 0 Else s = d * 255 \ mx
    If d = 0 Then
        h = 0
    ElseIf mx = r Then
        h = (60 * (g - b) \ d + 360) Mod 360
    ElseIf mx = g Then
        h = 60 * (b - r) \ d + 120
    Else
        h = 60 * (r - g) \ d + 240
    End If
End Sub

Public Function ColR(ByVal c As Long) As Long
    ColR = c And &HFF&
End Function
Public Function ColG(ByVal c As Long) As Long
    ColG = (c \ &H100&) And &HFF&
End Function
Public Function ColB(ByVal c As Long) As Long
    ColB = (c \ &H10000) And &HFF&
End Function

Public Function ColorHex(ByVal c As Long) As String
    ColorHex = "#" & Right$("0" & Hex$(ColR(c)), 2) & Right$("0" & Hex$(ColG(c)), 2) & Right$("0" & Hex$(ColB(c)), 2)
End Function

' ---------------------------------------------------------------- dirty tracking

Public Sub DirtyAll()
    dirtyX1 = 0: dirtyY1 = 0: dirtyX2 = docW - 1: dirtyY2 = docH - 1
End Sub

Public Sub DirtyRect(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long)
    Dim t As Long
    If x1 > x2 Then t = x1: x1 = x2: x2 = t
    If y1 > y2 Then t = y1: y1 = y2: y2 = t
    If x1 < 0 Then x1 = 0
    If y1 < 0 Then y1 = 0
    If x2 > docW - 1 Then x2 = docW - 1
    If y2 > docH - 1 Then y2 = docH - 1
    If x1 > x2 Or y1 > y2 Then Exit Sub
    If dirtyX2 < dirtyX1 Then
        dirtyX1 = x1: dirtyY1 = y1: dirtyX2 = x2: dirtyY2 = y2
    Else
        If x1 < dirtyX1 Then dirtyX1 = x1
        If y1 < dirtyY1 Then dirtyY1 = y1
        If x2 > dirtyX2 Then dirtyX2 = x2
        If y2 > dirtyY2 Then dirtyY2 = y2
    End If
End Sub

Public Function HasDirty() As Boolean
    HasDirty = dirtyX2 >= dirtyX1
End Function

' rebuild the dirty part of comp from the layers (and the preview / floating selection)
Public Sub Recomposite()
    Dim i As Long, x As Long, y As Long, w As Long, h As Long
    If dirtyX2 < dirtyX1 Then Exit Sub
    x = dirtyX1: y = dirtyY1: w = dirtyX2 - dirtyX1 + 1: h = dirtyY2 - dirtyY1 + 1
    cv.SetTarget comp
    If Not layers(1).visible Then
        cv.Checker x, y, w, h, 8, RGB(204, 204, 204), RGB(160, 160, 160)
    End If
    For i = 1 To nLayers
        If layers(i).visible Then
            If i = 1 And layers(i).opacity = 255 Then
                cv.DrawImagePart layers(i).img, x, y, w, h, x, y, True
            ElseIf i = 1 Then
                cv.Checker x, y, w, h, 8, RGB(204, 204, 204), RGB(160, 160, 160)
                cv.DrawImageBlend layers(i).img, x, y, layers(i).opacity, x, y, w, h
            Else
                cv.DrawImageBlend layers(i).img, x, y, layers(i).opacity, x, y, w, h
            End If
        End If
        If i = curLayer Then
            If previewX2 >= previewX1 Then cv.DrawImagePart preview, x, y, w, h, x, y
            If floatImg Then cv.DrawImage floatImg, floatX, floatY
        End If
    Next
    cv.SetTarget 0
    dirtyX1 = 0: dirtyY1 = 0: dirtyX2 = -1: dirtyY2 = -1
End Sub

' the flattened picture as a new image (for saving and the clipboard); caller frees it
Public Function FlattenCopy() As Long
    DirtyAll
    Recomposite
    FlattenCopy = cv.CopyImage(comp)
End Function

Public Sub MarkChanged()
    docDirty = True
    docGen = docGen + 1
End Sub

' ---------------------------------------------------------------- preview layer

Public Sub ClearPreviewRect()
    previewX1 = 0: previewY1 = 0: previewX2 = -1: previewY2 = -1
End Sub

' wipe what the preview showed (and mark it dirty)
Public Sub ClearPreview()
    If previewX2 < previewX1 Then Exit Sub
    cv.SetTarget preview
    cv.ClearRect previewX1, previewY1, previewX2 - previewX1 + 1, previewY2 - previewY1 + 1
    cv.SetTarget 0
    DirtyRect previewX1, previewY1, previewX2, previewY2
    ClearPreviewRect
End Sub

Public Sub PreviewTouched(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long)
    Dim t As Long
    If x1 > x2 Then t = x1: x1 = x2: x2 = t
    If y1 > y2 Then t = y1: y1 = y2: y2 = t
    If x1 < 0 Then x1 = 0
    If y1 < 0 Then y1 = 0
    If x2 > docW - 1 Then x2 = docW - 1
    If y2 > docH - 1 Then y2 = docH - 1
    If x1 > x2 Or y1 > y2 Then Exit Sub
    If previewX2 < previewX1 Then
        previewX1 = x1: previewY1 = y1: previewX2 = x2: previewY2 = y2
    Else
        If x1 < previewX1 Then previewX1 = x1
        If y1 < previewY1 Then previewY1 = y1
        If x2 > previewX2 Then previewX2 = x2
        If y2 > previewY2 Then previewY2 = y2
    End If
    DirtyRect x1, y1, x2, y2
End Sub

' ---------------------------------------------------------------- layers

Public Function AddLayer(Optional ByVal nm As String = "") As Long
    Dim i As Long
    If nLayers >= MAX_LAYERS Then Err.Raise 5, "Tincture", "At most " & MAX_LAYERS & " layers"
    UndoPushDoc "New Layer"
    For i = nLayers To curLayer + 1 Step -1
        layers(i + 1) = layers(i)
    Next
    nLayers = nLayers + 1
    curLayer = curLayer + 1
    If nm = "" Then nm = "Layer " & nLayers
    layers(curLayer).img = cv.CreateImage(docW, docH)
    layers(curLayer).name = nm
    layers(curLayer).visible = True
    layers(curLayer).opacity = 255
    MarkChanged
    DirtyAll
    AddLayer = curLayer
End Function

Public Sub DeleteLayer()
    Dim i As Long
    If nLayers <= 1 Then Exit Sub
    UndoPushDoc "Delete Layer"
    ' the image itself stays alive in the undo snapshot
    For i = curLayer To nLayers - 1
        layers(i) = layers(i + 1)
    Next
    layers(nLayers).img = 0
    nLayers = nLayers - 1
    If curLayer > nLayers Then curLayer = nLayers
    If curLayer = 1 Then MakeOpaque 1
    MarkChanged
    DirtyAll
End Sub

' the bottom layer has no transparency: fill its holes with the background colour
Private Sub MakeOpaque(ByVal i As Long)
    Dim t As Long
    t = cv.CreateImage(docW, docH)
    cv.SetTarget t
    cv.Box 0, 0, docW, docH, bgColor
    cv.DrawImage layers(i).img, 0, 0
    cv.SetTarget 0
    layers(i).img = t           ' the old image belongs to the undo snapshot
End Sub

Public Sub MoveLayer(ByVal delta As Long)
    Dim j As Long, t As LayerRec
    j = curLayer + delta
    If j < 1 Or j > nLayers Then Exit Sub
    UndoPushDoc "Move Layer"
    t = layers(curLayer): layers(curLayer) = layers(j): layers(j) = t
    If curLayer = 1 Or j = 1 Then MakeOpaque 1
    curLayer = j
    MarkChanged
    DirtyAll
End Sub

' merge the current layer into the one below
Public Sub MergeDown()
    Dim i As Long, t As Long
    If curLayer <= 1 Then Exit Sub
    UndoPushDoc "Merge Down"
    t = cv.CopyImage(layers(curLayer - 1).img)
    cv.SetTarget t
    If layers(curLayer).visible Then cv.DrawImageBlend layers(curLayer).img, 0, 0, layers(curLayer).opacity
    cv.SetTarget 0
    layers(curLayer - 1).img = t
    For i = curLayer To nLayers - 1
        layers(i) = layers(i + 1)
    Next
    layers(nLayers).img = 0
    nLayers = nLayers - 1
    curLayer = curLayer - 1
    MarkChanged
    DirtyAll
End Sub

Public Sub FlattenLayers()
    Dim t As Long
    If nLayers <= 1 Then Exit Sub
    UndoPushDoc "Flatten"
    t = FlattenCopy()
    nLayers = 1
    curLayer = 1
    layers(1).img = t
    layers(1).name = "Background"
    layers(1).visible = True
    layers(1).opacity = 255
    MarkChanged
    DirtyAll
End Sub

Public Sub SetLayerVisible(ByVal i As Long, ByVal v As Boolean)
    If i < 1 Or i > nLayers Then Exit Sub
    layers(i).visible = v
    DirtyAll
End Sub

Public Sub SetLayerOpacity(ByVal i As Long, ByVal o As Long)
    If i < 1 Or i > nLayers Then Exit Sub
    If o < 0 Then o = 0
    If o > 255 Then o = 255
    layers(i).opacity = o
    MarkChanged
    DirtyAll
End Sub

Public Function CurImg() As Long
    CurImg = layers(curLayer).img
End Function

' ---------------------------------------------------------------- whole-picture operations

' resize the picture (scale = True) or the canvas (scale = False: anchored top-left)
Public Sub ResizeDoc(ByVal w As Long, ByVal h As Long, ByVal scaleIt As Boolean)
    Dim i As Long, t As Long
    If w < 1 Or h < 1 Or w > 4096 Or h > 4096 Then Err.Raise 380, "Tincture", "Picture size must be 1 to 4096"
    DropFloat
    UndoPushDoc IIf(scaleIt, "Scale Picture", "Canvas Size")
    For i = 1 To nLayers
        If scaleIt Then
            t = cv.ScaleImage(layers(i).img, w, h, True)
        Else
            t = cv.CreateImage(w, h)
            cv.SetTarget t
            If i = 1 Then cv.Box 0, 0, w, h, bgColor
            cv.DrawImage layers(i).img, 0, 0, True
            cv.SetTarget 0
        End If
        layers(i).img = t
    Next
    SetDocSize w, h
End Sub

Public Sub CropDoc(ByVal x As Long, ByVal y As Long, ByVal w As Long, ByVal h As Long)
    Dim i As Long
    If w < 1 Or h < 1 Then Exit Sub
    DropFloat
    UndoPushDoc "Crop"
    For i = 1 To nLayers
        layers(i).img = cv.CopyImage(layers(i).img, x, y, w, h)
    Next
    SetDocSize w, h
    If i > 0 Then MakeOpaque 1
End Sub

Public Sub RotateDoc(ByVal quarters As Long)
    Dim i As Long, w As Long, h As Long
    DropFloat
    UndoPushDoc "Rotate"
    For i = 1 To nLayers
        layers(i).img = cv.RotateImage(layers(i).img, quarters)
    Next
    w = cv.ImageWidth(layers(1).img): h = cv.ImageHeight(layers(1).img)
    SetDocSize w, h
End Sub

Public Sub FlipDoc(ByVal vertical As Boolean)
    Dim i As Long
    DropFloat
    UndoPushDoc IIf(vertical, "Flip Vertical", "Flip Horizontal")
    For i = 1 To nLayers
        layers(i).img = cv.CopyImage(layers(i).img)
        cv.FlipImage layers(i).img, vertical
    Next
    MarkChanged
    DirtyAll
End Sub

' after the layers changed size: new work images
Public Sub SetDocSize(ByVal w As Long, ByVal h As Long)
    If w <> docW Or h <> docH Then
        cv.FreeImage comp: cv.FreeImage preview: cv.FreeImage scratch
        docW = w: docH = h
        comp = cv.CreateImage(w, h)
        preview = cv.CreateImage(w, h)
        scratch = cv.CreateImage(w, h)
        ClearPreviewRect
        SelectNone
    End If
    MarkChanged
    DirtyAll
End Sub

' ---------------------------------------------------------------- indexed colour

' to indexed: the picture's colours reduced to n (median cut), every layer remapped
Public Sub ToIndexed(ByVal n As Long, ByVal dither As Boolean)
    Dim p As Variant, i As Long, flat As Long
    If n < 2 Then n = 2
    If n > 256 Then n = 256
    DropFloat
    UndoPushDoc "Indexed Colour"
    flat = FlattenCopy()
    p = cv.Quantize(flat, n)
    cv.FreeImage flat
    palCount = UBound(p) + 1
    For i = 0 To palCount - 1
        pal(i) = p(i)
    Next
    For i = 1 To nLayers
        layers(i).img = cv.CopyImage(layers(i).img)
        cv.RemapImage layers(i).img, pal, palCount, dither
    Next
    docMode = MODE_INDEXED
    fgColor = NearestPal(fgColor)
    bgColor = NearestPal(bgColor)
    MarkChanged
    DirtyAll
End Sub

Public Sub ToTrueColour()
    If docMode = MODE_TRUE Then Exit Sub
    UndoPushDoc "True Colour"
    docMode = MODE_TRUE
    MarkChanged
End Sub

Public Function NearestPal(ByVal c As Long) As Long
    Dim i As Long, best As Long, bd As Long, d As Long, dr As Long, dg As Long, db As Long
    bd = -1
    For i = 0 To palCount - 1
        dr = ColR(c) - ColR(pal(i)): dg = ColG(c) - ColG(pal(i)): db = ColB(c) - ColB(pal(i))
        d = dr * dr * 3 + dg * dg * 4 + db * db * 2
        If bd < 0 Or d < bd Then bd = d: best = i
    Next
    NearestPal = pal(best)
End Function

Public Function PalIndex(ByVal c As Long) As Long
    Dim i As Long
    PalIndex = -1
    For i = 0 To palCount - 1
        If pal(i) = c Then PalIndex = i: Exit Function
    Next
End Function

' change palette entry i; in indexed mode the pixels of that colour change with it
Public Sub SetPaletteEntry(ByVal i As Long, ByVal c As Long)
    Dim old As Long, k As Long
    If i < 0 Or i > 255 Then Exit Sub
    old = pal(i)
    If i >= palCount Then palCount = i + 1
    If old = c Then Exit Sub
    If docMode = MODE_INDEXED Then
        UndoPushDoc "Palette"
        For k = 1 To nLayers
            layers(k).img = cv.CopyImage(layers(k).img)
            cv.SetTarget layers(k).img
            cv.ReplaceColor old, c
        Next
        cv.SetTarget 0
        If fgColor = old Then fgColor = c
        If bgColor = old Then bgColor = c
        MarkChanged
        DirtyAll
    End If
    pal(i) = c
End Sub
