' Tincture - multi-level undo and redo
'
' One history array: entries 0 .. histPos-1 can be undone, histPos .. histTop-1 redone. An
' entry holds the state on the other side of its step, so undo and redo are the same swap:
'   region entries (a stroke, a fill, a shape): the pixels of one layer's rectangle;
'   document entries (layers added or deleted, resize, crop, palette ...): every layer's image,
'   name, visibility and opacity, the size, the palette and the mode.
' Document operations never change an image in place: they make new ones, so a snapshot can
' share images with the document (an image is freed when nothing refers to it any more).
' The history is limited to UNDO_MAX steps and undoBudget pixels.
Option Explicit

Public Const UNDO_MAX As Long = 64
Private Const K_REGION As Long = 1
Private Const K_DOC As Long = 2

Private Type UndoRec
    kind As Long
    label As String
    layer As Long
    x As Long
    y As Long
    w As Long
    h As Long
    img As Long
    pixels As Long
    ' K_DOC
    dw As Long
    dh As Long
    dn As Long
    dcur As Long
    dmode As Long
    dpalCount As Long
End Type

Private hist(0 To 63) As UndoRec
Private histLayers(1 To 16, 0 To 63) As LayerRec
Private histPal(0 To 255, 0 To 63) As Long
Private histPos As Long, histTop As Long
Public undoBudget As Long          ' pixels kept in the history (default 12 M = 48 MB)
Public undoPixels As Long

' the edit in progress (BeginEdit .. EndEdit)
Private editOpen As Boolean, editLabel As String, editLayer As Long
Private ex1 As Long, ey1 As Long, ex2 As Long, ey2 As Long

Public Sub UndoClear()
    Do While histTop > 0
        histTop = histTop - 1
        FreeEntry histTop
    Loop
    histPos = 0
    undoPixels = 0
    editOpen = False
    If undoBudget = 0 Then undoBudget = 12000000
End Sub

Public Function CanUndo() As Boolean
    CanUndo = histPos > 0
End Function

Public Function CanRedo() As Boolean
    CanRedo = histPos < histTop
End Function

Public Function UndoLabel() As String
    If histPos > 0 Then UndoLabel = hist(histPos - 1).label
End Function

Public Function RedoLabel() As String
    If histPos < histTop Then RedoLabel = hist(histPos).label
End Function

Public Function UndoCount() As Long
    UndoCount = histPos
End Function

' ---------------------------------------------------------------- region edits

' an edit of the current layer begins: remember the layer as it is now
Public Sub BeginEdit(ByVal label As String)
    If editOpen Then EndEdit
    editOpen = True
    editLabel = label
    editLayer = curLayer
    cv.SetTarget scratch
    cv.DrawImage layers(curLayer).img, 0, 0, True
    cv.SetTarget 0
    ex1 = docW: ey1 = docH: ex2 = -1: ey2 = -1
End Sub

' the edit touched this rectangle (it is also marked dirty for the composite)
Public Sub EditTouched(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long)
    Dim t As Long
    If x1 > x2 Then t = x1: x1 = x2: x2 = t
    If y1 > y2 Then t = y1: y1 = y2: y2 = t
    If x1 < 0 Then x1 = 0
    If y1 < 0 Then y1 = 0
    If x2 > docW - 1 Then x2 = docW - 1
    If y2 > docH - 1 Then y2 = docH - 1
    If x1 > x2 Or y1 > y2 Then Exit Sub
    If x1 < ex1 Then ex1 = x1
    If y1 < ey1 Then ey1 = y1
    If x2 > ex2 Then ex2 = x2
    If y2 > ey2 Then ey2 = y2
    DirtyRect x1, y1, x2, y2
End Sub

Public Function EditIsOpen() As Boolean
    EditIsOpen = editOpen
End Function

' the edit is done: keep the old pixels of the touched rectangle
Public Sub EndEdit()
    Dim k As Long
    If Not editOpen Then Exit Sub
    editOpen = False
    If ex2 < ex1 Then Exit Sub
    k = NewEntry()
    With hist(k)
        .kind = K_REGION
        .label = editLabel
        .layer = editLayer
        .x = ex1: .y = ey1: .w = ex2 - ex1 + 1: .h = ey2 - ey1 + 1
        .img = cv.CopyImage(scratch, .x, .y, .w, .h)
        .pixels = .w * .h
    End With
    undoPixels = undoPixels + hist(k).pixels
    MarkChanged
    Trim
End Sub

' give up the edit: put the old pixels back
Public Sub CancelEdit()
    If Not editOpen Then Exit Sub
    editOpen = False
    If ex2 < ex1 Then Exit Sub
    cv.SetTarget layers(editLayer).img
    cv.DrawImagePart scratch, ex1, ey1, ex2 - ex1 + 1, ey2 - ey1 + 1, ex1, ey1, True
    cv.SetTarget 0
    DirtyRect ex1, ey1, ex2, ey2
End Sub

' ---------------------------------------------------------------- document snapshots

' before a document operation: remember the whole document
Public Sub UndoPushDoc(ByVal label As String)
    Dim k As Long
    If editOpen Then EndEdit
    k = NewEntry()
    hist(k).kind = K_DOC
    hist(k).label = label
    SaveDocInto k
    undoPixels = undoPixels + hist(k).pixels
    Trim
End Sub

Private Sub SaveDocInto(ByVal k As Long)
    Dim i As Long
    With hist(k)
        .dw = docW: .dh = docH: .dn = nLayers: .dcur = curLayer: .dmode = docMode: .dpalCount = palCount
        .pixels = docW * docH * nLayers \ 2        ' shared images count half
    End With
    For i = 1 To nLayers
        histLayers(i, k) = layers(i)
    Next
    For i = 0 To 255
        histPal(i, k) = pal(i)
    Next
End Sub

Private Sub LoadDocFrom(ByVal k As Long)
    Dim i As Long, w As Long, h As Long
    With hist(k)
        w = .dw: h = .dh
        nLayers = .dn: curLayer = .dcur: docMode = .dmode: palCount = .dpalCount
    End With
    For i = 1 To nLayers
        layers(i) = histLayers(i, k)
    Next
    For i = nLayers + 1 To MAX_LAYERS
        layers(i).img = 0
    Next
    For i = 0 To 255
        pal(i) = histPal(i, k)
    Next
    SetDocSize w, h
End Sub

' ---------------------------------------------------------------- undo / redo

Public Function Undo() As Boolean
    If editOpen Then EndEdit
    DropFloatQuiet
    If histPos = 0 Then Exit Function
    histPos = histPos - 1
    SwapEntry histPos
    Undo = True
End Function

Public Function Redo() As Boolean
    If editOpen Then EndEdit
    DropFloatQuiet
    If histPos >= histTop Then Exit Function
    SwapEntry histPos
    histPos = histPos + 1
    Redo = True
End Function

Private Sub SwapEntry(ByVal k As Long)
    Dim t As Long, tmpL(1 To 16) As LayerRec, tmpPal(0 To 255) As Long, i As Long
    Dim tw As Long, th As Long, tn As Long, tc As Long, tm As Long, tp As Long
    With hist(k)
        If .kind = K_REGION Then
            If .layer > nLayers Then Exit Sub
            t = cv.CopyImage(layers(.layer).img, .x, .y, .w, .h)
            cv.SetTarget layers(.layer).img
            cv.DrawImage .img, .x, .y, True
            cv.SetTarget 0
            cv.FreeImage .img
            .img = t
            DirtyRect .x, .y, .x + .w - 1, .y + .h - 1
            If .layer <> curLayer And .layer <= nLayers Then curLayer = .layer
        Else
            ' swap the document with the snapshot
            tw = docW: th = docH: tn = nLayers: tc = curLayer: tm = docMode: tp = palCount
            For i = 1 To nLayers
                tmpL(i) = layers(i)
            Next
            For i = 0 To 255
                tmpPal(i) = pal(i)
            Next
            LoadDocFrom k
            .dw = tw: .dh = th: .dn = tn: .dcur = tc: .dmode = tm: .dpalCount = tp
            For i = 1 To tn
                histLayers(i, k) = tmpL(i)
            Next
            For i = 0 To 255
                histPal(i, k) = tmpPal(i)
            Next
            DirtyAll
        End If
    End With
    MarkChanged
End Sub

' ---------------------------------------------------------------- bookkeeping

' a new entry at histPos: the redo steps are gone, the oldest step goes if the history is full
Private Function NewEntry() As Long
    Do While histTop > histPos
        histTop = histTop - 1
        FreeEntry histTop
    Loop
    If histTop = UNDO_MAX Then DropOldest
    NewEntry = histTop
    hist(histTop).img = 0
    histTop = histTop + 1
    histPos = histTop
End Function

Private Sub DropOldest()
    Dim i As Long, j As Long
    FreeEntry 0
    For i = 1 To histTop - 1
        hist(i - 1) = hist(i)
        For j = 1 To MAX_LAYERS
            histLayers(j, i - 1) = histLayers(j, i)
        Next
        For j = 0 To 255
            histPal(j, i - 1) = histPal(j, i)
        Next
    Next
    histTop = histTop - 1
    If histPos > 0 Then histPos = histPos - 1
End Sub

' keep within the pixel budget (always keep the newest step)
Private Sub Trim()
    Do While undoPixels > undoBudget And histTop > 1 And histPos > 1
        DropOldest
    Loop
End Sub

Private Sub FreeEntry(ByVal k As Long)
    Dim i As Long
    undoPixels = undoPixels - hist(k).pixels
    If hist(k).kind = K_REGION Then
        If hist(k).img Then cv.FreeImage hist(k).img
        hist(k).img = 0
    ElseIf hist(k).kind = K_DOC Then
        For i = 1 To hist(k).dn
            If Not ImageInUse(histLayers(i, k).img, k) Then cv.FreeImage histLayers(i, k).img
            histLayers(i, k).img = 0
        Next
    End If
    hist(k).kind = 0
    hist(k).pixels = 0
End Sub

' is image id used by the document or by a snapshot other than entry `except`?
Private Function ImageInUse(ByVal id As Long, ByVal except As Long) As Boolean
    Dim i As Long, k As Long
    If id = 0 Then ImageInUse = True: Exit Function
    For i = 1 To nLayers
        If layers(i).img = id Then ImageInUse = True: Exit Function
    Next
    For k = 0 To histTop - 1
        If k <> except And hist(k).kind = K_DOC Then
            For i = 1 To hist(k).dn
                If histLayers(i, k).img = id Then ImageInUse = True: Exit Function
            Next
        End If
    Next
End Function
