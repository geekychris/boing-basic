' Tincture - a paint program for AmigaOS 4.1, written in Boing BASIC
'
'   Tincture [picture] [--script file] [--size WxH] [--smoke] [--bench N]
'
' The main window: the tool box (left), the picture view (middle), the colour panel, brush and
' layer controls (right), the status line. The picture logic is in the modules (Doc, History,
' Tools, View, FileIO, Script); this file connects them to the mouse, the keys and the menus.
Option Explicit

Private Const APP_NAME As String = "Tincture"

Private panning As Boolean, panX As Long, panY As Long
Private lastMX As Long, lastMY As Long
Private colourDrag As Long
Private layerListGen As Long
Private smokeMode As Boolean, benchStrokes As Long
Private autosaveOn As Boolean
Private shownStatus As String
Private quitAt As Double            ' --smoke / --hold: quit at this Timer value
Private holdSecs As Long
Private logActive As Boolean        ' --log: print active/inactive and events for the guest tests

' ---------------------------------------------------------------- start and end

Private Sub Form_Load()
    Dim args() As String, i As Long, openPath As String, scriptPath As String, a As String, p As Long

    DocAttach view
    ToolsInit
    LoadPrefs
    ViewInit view.Width, view.Height
    MakeIcons tools
    palSel = -1
    autosavePath = AutosaveFile()

    args = Split(Trim$(Command$), " ")
    i = 0
    Do While i <= UBound(args)
        a = args(i)
        Select Case LCase$(a)
            Case "":
            Case "--script": i = i + 1: If i <= UBound(args) Then scriptPath = args(i)
            Case "--smoke": smokeMode = True
            Case "--bench": i = i + 1: If i <= UBound(args) Then benchStrokes = CLng(args(i))
            Case "--hold": i = i + 1: If i <= UBound(args) Then holdSecs = CLng(args(i))
            Case "--log": logActive = True
            Case "--size"
                i = i + 1
                If i <= UBound(args) Then
                    p = InStr(LCase$(args(i)), "x")
                    If p > 0 Then DocNew CLng(Mid$(args(i), 1, p - 1)), CLng(Mid$(args(i), p + 1))
                End If
            Case Else: If openPath = "" Then openPath = a Else openPath = openPath & " " & a
        End Select
        i = i + 1
    Loop
    If docW = 0 Then DocNew 640, 512
    ZoomFit

    SetupWorkbench
    If openPath <> "" Then
        ActOpenFile openPath, False, 0, 0
    ElseIf HasAutosave() And Not smokeMode And scriptPath = "" Then
        If MsgBox("Tincture was not closed properly last time." & vbLf & _
                  "Bring back the picture it saved?", vbYesNo + vbQuestion, APP_NAME) = vbYes Then
            If RecoverAutosave() Then statusMsg = "Picture recovered" Else statusMsg = lastError
            needFit = True
        Else
            ClearAutosave
        End If
    End If
    If scriptPath <> "" Then
        statusMsg = Replace(RunScriptFile(scriptPath), vbLf, " ")
        If scriptQuit Then statusMsg = statusMsg
    End If
    NeedAll
    needFit = True
End Sub

Private Sub Form_Activate()
    Static started As Boolean
    If logActive Then
        Debug.Print "geom " & Me.Left & " " & Me.Top & " " & view.Left & " " & view.Top & " " & view.Width & " " & view.Height
        Debug.Print "active"
    End If
    If started Then Exit Sub
    started = True
    UpdateAll
    If smokeMode Then RunSmoke
    If benchStrokes > 0 Then RunBench benchStrokes
    If scriptQuit Then QuitNow
    If holdSecs > 0 And quitAt = 0 Then quitAt = Timer + holdSecs
End Sub

Private Sub Form_Deactivate()
    If logActive Then Debug.Print "inactive"
End Sub

Private Sub Form_Resize()
    needView = True
    UpdateAll
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not ConfirmDiscard("quitting") Then Cancel = True
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ClearAutosave
    WbCleanup
End Sub

Private Sub QuitNow()
    docDirty = False
    ClearAutosave
    Unload Me
End Sub

' unsaved changes: save them, throw them away, or stay
Private Function ConfirmDiscard(ByVal what As String) As Boolean
    Dim r As Long
    If Not docDirty Then ConfirmDiscard = True: Exit Function
    r = MsgBox("The picture has changes that are not saved." & vbLf & "Save them before " & what & "?", _
               vbYesNoCancel + vbExclamation, APP_NAME)
    If r = vbYes Then
        ConfirmDiscard = DoSave(False)
    ElseIf r = vbNo Then
        ConfirmDiscard = True
    End If
End Function

' ---------------------------------------------------------------- drawing the window

Private Sub UpdateAll()
    If needFit Then needFit = False: ZoomFit: needView = True
    If needView Then needView = False: RenderView: view.Refresh
    If needTools Then needTools = False: DrawToolBox tools
    If needColours Then needColours = False: DrawColourPanel colours
    If needLayers Then needLayers = False: FillLayerList
    If needTitle Then needTitle = False: UpdateTitle
    UpdateStatus
End Sub

Private Sub UpdateTitle()
    Dim t As String
    If docPath = "" Then t = "Untitled" Else t = FilePart(docPath)
    If docDirty Then t = t & " *"
    Me.Caption = APP_NAME & " - " & t
    On Error Resume Next
    mnuUndo.Enabled = CanUndo()
    mnuRedo.Enabled = CanRedo()
    If CanUndo() Then mnuUndo.Caption = "Undo " & UndoLabel() Else mnuUndo.Caption = "Undo"
    If CanRedo() Then mnuRedo.Caption = "Redo " & RedoLabel() Else mnuRedo.Caption = "Redo"
    mnuMag.Checked = magOn
    mnuGrid.Checked = showGrid
End Sub

Private Sub UpdateStatus()
    Dim s As String
    If cursorIn Then s = cursorX & ", " & cursorY & "   " Else s = ""
    s = s & docW & " x " & docH & "   " & zoomPct & "%   " & ToolName(curTool)
    If selActive Then s = s & "   sel " & selW & " x " & selH
    s = s & "   layer " & curLayer & "/" & nLayers
    If docMode = MODE_INDEXED Then s = s & "   " & palCount & " colours"
    If statusMsg <> "" Then s = s & "   -   " & statusMsg
    If s <> shownStatus Then shownStatus = s: status.Caption = s
End Sub

Private Sub FillLayerList()
    Dim i As Long
    layerList.Clear
    For i = nLayers To 1 Step -1
        layerList.AddItem IIf(layers(i).visible, "", "(hidden) ") & layers(i).name
    Next
    layerList.ListIndex = nLayers - curLayer
    layerVis.Value = IIf(layers(curLayer).visible, 1, 0)
    opacity.Value = layers(curLayer).opacity
    layerDel.Enabled = nLayers > 1
    layerUp.Enabled = curLayer < nLayers
    layerDown.Enabled = curLayer > 1
End Sub

' ---------------------------------------------------------------- the picture view: mouse

Private Sub view_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim dx As Long, dy As Long
    If logActive Then Debug.Print "down " & X & " " & Y & " " & Button
    lastMX = X: lastMY = Y
    statusMsg = ""
    If (Button And 4) <> 0 Or view.KeyDown(vbKeySpace) Then
        panning = True: panX = X: panY = Y
        Exit Sub
    End If
    ViewToDoc X, Y, dx, dy
    ' Alt+click paints with the background colour (the right button opens the menus)
    If (Shift And 4) <> 0 And (Button And 1) <> 0 Then Button = 2
    ToolDown dx, dy, Button, Shift
    AfterToolEvent
End Sub

Private Sub view_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim dx As Long, dy As Long
    If logActive Then Debug.Print "move " & X & " " & Y & " " & Button
    lastMX = X: lastMY = Y
    If panning Then
        ScrollBy (panX - X) * 100 \ zoomPct, (panY - Y) * 100 \ zoomPct
        If (panX - X) * 100 \ zoomPct <> 0 Then panX = X
        If (panY - Y) * 100 \ zoomPct <> 0 Then panY = Y
        needView = True
        UpdateAll
        Exit Sub
    End If
    ViewToDoc X, Y, dx, dy
    cursorX = dx: cursorY = dy
    cursorIn = dx >= 0 And dy >= 0 And dx < docW And dy < docH
    If magOn And Not InMagnifier(X) Then magX = dx: magY = dy
    If IsStroking() Then
        ToolMove dx, dy, Shift
        AfterToolEvent
    Else
        needView = True
        UpdateAll
    End If
End Sub

Private Sub view_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim dx As Long, dy As Long
    If panning Then panning = False: Exit Sub
    ViewToDoc X, Y, dx, dy
    ToolUp dx, dy, Button, Shift
    AfterToolEvent
    needTools = True: needTitle = True
    UpdateAll
    If logActive Then Debug.Print "up " & X & " " & Y & " undo=" & UndoCount() & " pixel=" & RunCommand("GETPIXEL " & dx & " " & dy)
End Sub

Private Sub view_MouseWheel(Delta As Integer)
    If view.KeyDown(vbKeyControl) Or zoomPct >= 400 Then
        If Delta > 0 Then ZoomIn lastMX, lastMY Else ZoomOut lastMX, lastMY
    Else
        ScrollBy 0, -Delta * 32 * 100 \ zoomPct
    End If
    needView = True
    UpdateAll
End Sub

Private Sub AfterToolEvent()
    If curTool = T_PICK Then needColours = True
    needView = True
    UpdateAll
End Sub

' ---------------------------------------------------------------- tool box and colour panel

Private Sub tools_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim t As Long
    t = ToolBoxHit(X, Y)
    Select Case t
        Case -1
        Case TB_UNDO: ActUndo
        Case TB_REDO: ActRedo
        Case T_TEXT
            ActSetTool t
            AskText
        Case Else: ActSetTool t
    End Select
    UpdateAll
End Sub

Private Sub AskText()
    Dim s As String
    s = InputBox("Text to place (click in the picture to put it down):", APP_NAME, pendingText)
    If s <> "" Then pendingText = s
End Sub

Private Sub colours_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim k As Long, idx As Long, t As Long
    k = ColourPanelHit(X, Y, idx)
    colourDrag = 0
    Select Case k
        Case 1
            t = fgColor: fgColor = bgColor: bgColor = t
        Case 2
            If Shift And 1 Then
                ' Shift+click: edit this palette entry with the picker
                palSel = idx
                SyncPickerFromColour pal(idx)
            Else
                palSel = -1
                If Button And 2 Then bgColor = pal(idx) Else fgColor = pal(idx)
                SyncPickerFromColour fgColor
            End If
        Case 3, 4
            colourDrag = k
            ApplyPicker
    End Select
    needColours = True
    UpdateAll
End Sub

Private Sub colours_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    Dim idx As Long, k As Long
    If colourDrag = 0 Or Button = 0 Then Exit Sub
    k = ColourPanelHit(X, Y, idx)
    If k = colourDrag Then ApplyPicker: needColours = True: UpdateAll
End Sub

Private Sub colours_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    If colourDrag And palSel >= 0 And docMode = MODE_INDEXED Then needView = True
    colourDrag = 0
    UpdateAll
End Sub

Private Sub colours_DblClick()
    ' double-click a pen: edit it
    If palSel < 0 Then
        palSel = PalIndex(fgColor)
        If palSel >= 0 Then SyncPickerFromColour pal(palSel)
        needColours = True
        UpdateAll
    End If
End Sub

' the picker changed: the foreground colour, or the palette entry being edited
Private Sub ApplyPicker()
    Dim c As Long
    c = PickerColour()
    If palSel >= 0 Then
        SetPaletteEntry palSel, c
        If docMode = MODE_INDEXED Then needView = True
        fgColor = c
    ElseIf docMode = MODE_INDEXED Then
        fgColor = NearestPal(c)
    Else
        fgColor = c
    End If
End Sub

' ---------------------------------------------------------------- brush and layer controls

Private Sub size_Change()
    ActBrushSize size.Value
    sizelabel.Caption = "Brush " & brushSize
    UpdateAll
End Sub

Private Sub size_Scroll()
    size_Change
End Sub

Private Sub square_Click()
    brushSquare = (square.Value = 1)
    needView = True
    UpdateAll
End Sub

Private Sub layerList_Click()
    Dim i As Long
    If layerList.ListIndex < 0 Then Exit Sub
    i = nLayers - layerList.ListIndex
    If i <> curLayer Then
        DropFloat
        curLayer = i
        layerVis.Value = IIf(layers(curLayer).visible, 1, 0)
        opacity.Value = layers(curLayer).opacity
        layerUp.Enabled = curLayer < nLayers
        layerDown.Enabled = curLayer > 1
        needView = True
        UpdateAll
    End If
End Sub

Private Sub layerList_DblClick()
    Dim s As String
    s = InputBox("Name of the layer:", APP_NAME, layers(curLayer).name)
    If s <> "" Then layers(curLayer).name = s: MarkChanged: needLayers = True: UpdateAll
End Sub

Private Sub layerAdd_Click()
    On Error GoTo failed
    AddLayer
    NeedAll
    UpdateAll
    Exit Sub
failed:
    statusMsg = Err.Description
    UpdateAll
End Sub

Private Sub layerDel_Click()
    DeleteLayer
    NeedAll
    UpdateAll
End Sub

Private Sub layerUp_Click()
    MoveLayer 1
    NeedAll
    UpdateAll
End Sub

Private Sub layerDown_Click()
    MoveLayer -1
    NeedAll
    UpdateAll
End Sub

Private Sub layerVis_Click()
    SetLayerVisible curLayer, layerVis.Value = 1
    needView = True: needLayers = True
    UpdateAll
End Sub

Private Sub opacity_Change()
    If opacity.Value <> layers(curLayer).opacity Then
        SetLayerOpacity curLayer, opacity.Value
        needView = True
        UpdateAll
    End If
End Sub

Private Sub opacity_Scroll()
    opacity_Change
End Sub

' ---------------------------------------------------------------- timers

Private Sub tick_Timer()
    If quitAt > 0 And Timer >= quitAt Then
        If logActive Then Debug.Print "quit"
        QuitNow
        Exit Sub
    End If
    If selActive Or floatImg <> 0 Then
        antsPhase = (antsPhase + 1) Mod 8
        needView = True
    End If
    If IsStroking() And curTool = T_AIRBRUSH Then ToolTick: needView = True
    If needView Or needTools Or needColours Or needLayers Or needTitle Or needFit Then UpdateAll
End Sub

Private Sub autotimer_Timer()
    If autosaveOn Then
        If Autosave() Then statusMsg = "Autosaved": UpdateStatus
    End If
End Sub

' ---------------------------------------------------------------- keys

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Select Case KeyCode
        Case vbKeyEscape: ToolCancel: SelectNone: palSel = -1: needColours = True
        Case vbKeyDelete: ClearSelection
        Case vbKeyLeft: ScrollBy -32 * 100 \ zoomPct, 0
        Case vbKeyRight: ScrollBy 32 * 100 \ zoomPct, 0
        Case vbKeyUp: ScrollBy 0, -32 * 100 \ zoomPct
        Case vbKeyDown: ScrollBy 0, 32 * 100 \ zoomPct
        Case 47, vbKeyF1: ShowHelp "main"
        Case Else: Exit Sub
    End Select
    NeedAll
    UpdateAll
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim k As String
    If (KeyAscii < 32) Then Exit Sub
    k = Chr$(KeyAscii)
    Select Case k
        Case "d": ActSetTool T_FREEHAND
        Case "v": ActSetTool T_LINE
        Case "r": ActSetTool T_RECT
        Case "R": ActSetTool T_RECTF
        Case "o": ActSetTool T_ELLIPSE
        Case "O": ActSetTool T_ELLIPSEF
        Case "f": ActSetTool T_FILL
        Case "a": ActSetTool T_AIRBRUSH
        Case "t": ActSetTool T_TEXT: AskText
        Case "s", "b": ActSetTool T_SELECT
        Case "i", ",": ActSetTool T_PICK
        Case "e": ActSetTool T_ERASER
        Case "G": ActSetTool T_GRADIENT
        Case "x": Dim c As Long: c = fgColor: fgColor = bgColor: bgColor = c: needColours = True
        Case "[": ActBrushSize brushSize - 1: size.Value = brushSize: sizelabel.Caption = "Brush " & brushSize
        Case "]": ActBrushSize brushSize + 1: size.Value = brushSize: sizelabel.Caption = "Brush " & brushSize
        Case "+", "=": ZoomIn lastMX, lastMY: needView = True
        Case "-": ZoomOut lastMX, lastMY: needView = True
        Case "1": SetViewZoom 100: needView = True
        Case "0": ZoomFit: needView = True
        Case "m": mnuMag_Click
        Case "g": mnuGrid_Click
        Case "u": ActUndo
        Case "U": ActRedo
        Case "h": mnuBrushFlipH_Click
        Case "z": mnuBrushRotate_Click
        Case Else: Exit Sub
    End Select
    UpdateAll
End Sub

' ---------------------------------------------------------------- Project menu

Private Sub mnuNew_Click()
    If Not ConfirmDiscard("starting a new picture") Then Exit Sub
    OpenDialog 0
    newpic.Show
End Sub

Private Function AskFile(ByVal title As String, ByVal saving As Boolean, ByVal pattern As String) As String
    Dim dlg As Object
    On Error GoTo noDialog
    Set dlg = CreateObject("Boing.CommonDialog")
    dlg.DialogTitle = title
    dlg.Filter = pattern
    If prefLastDir <> "" Then dlg.InitDir = prefLastDir
    If saving Then
        If docPath <> "" Then dlg.FileName = docPath
        dlg.Flags = &H2
        dlg.ShowSave
    Else
        dlg.ShowOpen
    End If
    If dlg.Cancelled Then Exit Function
    AskFile = dlg.FileName
    prefLastDir = Mid$(AskFile, 1, Len(AskFile) - Len(FilePart(AskFile)))
    Exit Function
noDialog:
    ' without the asl dialog object: a plain requester for the name
    AskFile = InputBox(title & ":", APP_NAME, IIf(saving, docPath, prefLastDir))
End Function

Private Sub mnuOpen_Click()
    Dim p As String
    If Not ConfirmDiscard("opening another picture") Then Exit Sub
    p = AskFile("Open a picture", False, "#?.(iff|ilbm|lbm|png|tinc|jpg|jpeg|gif|bmp)")
    If p <> "" Then ActOpenFile p, False, 0, 0
    UpdateAll
End Sub

Private Sub mnuOpenLayer_Click()
    Dim p As String, img As Long
    p = AskFile("Open a picture as a new layer", False, "#?.(iff|ilbm|lbm|png|jpg|jpeg|gif|bmp)")
    If p = "" Then Exit Sub
    img = LoadAsImage(p)
    If img = 0 Then statusMsg = lastError: UpdateAll: Exit Sub
    AddLayer FilePart(p)
    PasteImage img, 0, 0
    DropFloat
    NeedAll
    UpdateAll
End Sub

Private Sub mnuRevert_Click()
    If docPath = "" Then Exit Sub
    If docDirty Then
        If MsgBox("Throw away the changes and load " & FilePart(docPath) & " again?", vbOKCancel + vbQuestion, APP_NAME) <> vbOK Then Exit Sub
    End If
    ActOpenFile docPath, False, 0, 0
    UpdateAll
End Sub

Private Function DoSave(ByVal askName As Boolean) As Boolean
    Dim p As String
    p = docPath
    If askName Or p = "" Or FormatOf(p) = FMT_ILBM And LCase$(Right$(p, 4)) = ".jpg" Then
        p = AskFile("Save the picture (.iff, .png, or .tinc with layers)", True, "#?.(iff|ilbm|png|tinc)")
        If p = "" Then Exit Function
        If InStr(FilePart(p), ".") = 0 Then p = p & IIf(nLayers > 1, ".tinc", ".iff")
    End If
    If nLayers > 1 And FormatOf(p) <> FMT_TINC Then
        If MsgBox("IFF and PNG keep one layer: the picture is saved flattened." & vbLf & _
                  "(Save as .tinc to keep the layers.)", vbOKCancel + vbInformation, APP_NAME) <> vbOK Then Exit Function
    End If
    Me.Enabled = False
    If SavePicture(p) Then
        DoSave = True
        statusMsg = "Saved " & FilePart(p)
        ClearAutosave
        If createIcons Then WriteIcon p
    Else
        MsgBox lastError, vbExclamation, APP_NAME
    End If
    Me.Enabled = True
    NeedAll
    UpdateAll
End Function

Private Sub mnuSave_Click()
    DoSave False
End Sub

Private Sub mnuSaveAs_Click()
    DoSave True
End Sub

Private Sub mnuHelp_Click()
    ShowHelp "main"
End Sub

Private Sub mnuAbout_Click()
    MsgBox "Tincture " & APP_VERSION & vbLf & "A paint program for AmigaOS 4.1" & vbLf & _
           "written in Boing BASIC." & vbLf & vbLf & "ARexx port: " & ARexxName(), vbInformation, "About Tincture"
End Sub

Private Sub mnuQuit_Click()
    If ConfirmDiscard("quitting") Then QuitNow
End Sub

' ---------------------------------------------------------------- Edit menu

Private Sub mnuUndo_Click()
    ActUndo
    UpdateAll
End Sub

Private Sub mnuRedo_Click()
    ActRedo
    UpdateAll
End Sub

Private Sub mnuCut_Click()
    If CutSelection() Then ToOsClipboard: statusMsg = "Cut" Else statusMsg = "Select an area first"
    NeedAll
    UpdateAll
End Sub

Private Sub mnuCopy_Click()
    If CopySelection() Then ToOsClipboard: statusMsg = "Copied" Else statusMsg = "Select an area first"
    UpdateAll
End Sub

Private Sub mnuPaste_Click()
    Dim x As Long, y As Long, img As Long
    img = FromOsClipboard()
    If img Then
        If clipImg Then view.FreeImage clipImg
        clipImg = img
    End If
    If clipImg = 0 Then statusMsg = "The clipboard is empty": UpdateAll: Exit Sub
    ' at the pointer if it is over the picture, else at the top-left of the view
    If cursorIn Then
        x = cursorX: y = cursorY
    Else
        x = IIf(scrollX > 0, scrollX, 0): y = IIf(scrollY > 0, scrollY, 0)
    End If
    PasteAt x, y
    statusMsg = "Pasted: drag it into place, click outside to drop, Esc to cancel"
    NeedAll
    UpdateAll
End Sub

Private Sub mnuClear_Click()
    ClearSelection
    NeedAll
    UpdateAll
End Sub

Private Sub mnuSelAll_Click()
    DropFloat
    SelectAll
    ActSetTool T_SELECT
    NeedAll
    UpdateAll
End Sub

Private Sub mnuSelNone_Click()
    DropFloat
    SelectNone
    NeedAll
    UpdateAll
End Sub

Private Sub mnuCrop_Click()
    If Not selActive Then statusMsg = "Select an area first": UpdateAll: Exit Sub
    DropFloat
    CropDoc selX, selY, selW, selH
    needFit = True
    NeedAll
    UpdateAll
End Sub

Private Sub mnuMakeBrush_Click()
    If BrushFromSelection() Then
        statusMsg = "The selection is the brush now (Built-in Brush to go back)"
        SelectNone
    Else
        statusMsg = "Select an area first"
    End If
    NeedAll
    UpdateAll
End Sub

Private Sub mnuBrushColour_Click()
    On Error Resume Next
    brushOwnColours = Not mnuBrushColour.Checked
End Sub

Private Sub mnuBrushFlipH_Click()
    BrushFlip False
    needView = True
End Sub

Private Sub mnuBrushRotate_Click()
    BrushRotate
    needView = True
End Sub

Private Sub mnuBrushBigger_Click()
    BrushScale 2
    needView = True
End Sub

Private Sub mnuBrushSmaller_Click()
    BrushScale 0.5
    needView = True
End Sub

Private Sub mnuBrushReset_Click()
    BrushReset
    needView = True
    UpdateAll
End Sub

' ---------------------------------------------------------------- Picture menu

Private Sub mnuCanvasSize_Click()
    OpenDialog 1
    newpic.Show
End Sub

Private Sub mnuScale_Click()
    OpenDialog 2
    newpic.Show
End Sub

Private Sub mnuFlipH_Click()
    FlipDoc False
    NeedAll
    UpdateAll
End Sub

Private Sub mnuFlipV_Click()
    FlipDoc True
    NeedAll
    UpdateAll
End Sub

Private Sub mnuRotR_Click()
    RotateDoc 1
    needFit = True
    NeedAll
    UpdateAll
End Sub

Private Sub mnuRotL_Click()
    RotateDoc 3
    needFit = True
    NeedAll
    UpdateAll
End Sub

Private Sub mnuIndexed_Click()
    Dim s As String, n As Long
    s = InputBox("Number of colours (2 to 256):", APP_NAME, IIf(docMode = MODE_INDEXED, CStr(palCount), "32"))
    If s = "" Or Not IsNumeric(s) Then Exit Sub
    n = CLng(s)
    Me.Enabled = False
    ToIndexed n, ditherOnReduce
    Me.Enabled = True
    statusMsg = palCount & " colours"
    NeedAll
    UpdateAll
End Sub

Private Sub mnuDither_Click()
    On Error Resume Next
    ditherOnReduce = mnuDither.Checked
End Sub

Private Sub mnuTrue_Click()
    ToTrueColour
    NeedAll
    UpdateAll
End Sub

Private Sub mnuPalReset_Click()
    If docMode = MODE_INDEXED Then
        statusMsg = "In indexed mode the palette belongs to the picture"
    Else
        DefaultPalette
    End If
    NeedAll
    UpdateAll
End Sub

' ---------------------------------------------------------------- Layer menu

Private Sub mnuLayerNew_Click()
    layerAdd_Click
End Sub

Private Sub mnuLayerDel_Click()
    layerDel_Click
End Sub

Private Sub mnuLayerUp_Click()
    layerUp_Click
End Sub

Private Sub mnuLayerDown_Click()
    layerDown_Click
End Sub

Private Sub mnuLayerMerge_Click()
    MergeDown
    NeedAll
    UpdateAll
End Sub

Private Sub mnuLayerFlatten_Click()
    FlattenLayers
    NeedAll
    UpdateAll
End Sub

' ---------------------------------------------------------------- View menu

Private Sub mnuZoomIn_Click()
    ZoomIn
    needView = True
    UpdateAll
End Sub

Private Sub mnuZoomOut_Click()
    ZoomOut
    needView = True
    UpdateAll
End Sub

Private Sub mnuZoom1_Click()
    SetViewZoom 100
    needView = True
    UpdateAll
End Sub

Private Sub mnuZoomFit_Click()
    ZoomFit
    needView = True
    UpdateAll
End Sub

Private Sub mnuMag_Click()
    SetMagnifier Not magOn
    If magOn Then magX = docW \ 2: magY = docH \ 2
    needView = True: needTitle = True
    UpdateAll
End Sub

Private Sub mnuGrid_Click()
    showGrid = Not showGrid
    needView = True: needTitle = True
    UpdateAll
End Sub

' ---------------------------------------------------------------- Settings menu

Private Sub mnuAutosave_Click()
    On Error Resume Next
    autosaveOn = mnuAutosave.Checked
End Sub

Private Sub mnuIcons_Click()
    On Error Resume Next
    createIcons = mnuIcons.Checked
End Sub

Private Sub mnuSavePrefs_Click()
    SavePrefs
    statusMsg = "Settings saved"
    UpdateAll
End Sub

' ---------------------------------------------------------------- Workbench: drops, AppIcon, ARexx, clipboard, help, icons

Private Sub SetupWorkbench()
    WbInit "TINCTURE"
End Sub

Private Function ARexxName() As String
    ARexxName = WbARexxName()
End Function

' files dropped on the window: the first opens (or, over a picture with changes, floats in)
Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    Dim p As String, dx As Long, dy As Long
    p = WbDropFile(0)
    If p = "" Then Exit Sub
    If docDirty Or nLayers > 1 Then
        dx = scrollX: dy = scrollY
        If cursorIn Then dx = cursorX: dy = cursorY
        ActOpenFile p, True, IIf(dx < 0, 0, dx), IIf(dy < 0, 0, dy)
    Else
        ActOpenFile p, False, 0, 0
    End If
    UpdateAll
End Sub

Private Sub view_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    Form_OLEDragDrop Count, X, Y
End Sub

Private Sub AppIcon_DragDrop(Count As Integer)
    Form_OLEDragDrop Count, 0, 0
    On Error Resume Next
    Me.WindowState = 0
End Sub

Private Sub AppIcon_DblClick()
    On Error Resume Next
    Me.WindowState = 0
End Sub

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Dim rc As Long
    Result = ActScript(Cmd & " " & Args, rc)
    WbSetRC rc
    UpdateAll
    If scriptQuit Then QuitNow
End Sub

Private Sub ToOsClipboard()
    If clipImg Then WbClipboardPut view, clipImg
End Sub

Private Function FromOsClipboard() As Long
    FromOsClipboard = WbClipboardGet(view)
End Function

Private Sub ShowHelp(ByVal node As String)
    If Not WbHelp("Tincture.guide", node) Then statusMsg = "Help: see Tincture.guide": UpdateAll
End Sub

Private Sub WriteIcon(ByVal path As String)
    WbSaveIcon path
End Sub

' ---------------------------------------------------------------- tests and benchmarks (--smoke, --bench N)

Private Sub RunSmoke()
    Dim r As String, h As String
    ' every tool once through the real handlers, then undo all of it
    DocNew 320, 200
    ZoomFit
    h = RunCommand("HASH")
    SmokeStroke T_FREEHAND, 10, 10, 100, 60
    SmokeStroke T_LINE, 10, 100, 200, 120
    SmokeStroke T_RECT, 120, 10, 180, 60
    SmokeStroke T_RECTF, 190, 10, 240, 60
    SmokeStroke T_ELLIPSE, 10, 130, 90, 190
    SmokeStroke T_ELLIPSEF, 100, 130, 180, 190
    SmokeStroke T_AIRBRUSH, 250, 150, 260, 160
    fgColor = vbRed
    SmokeStroke T_FILL, 150, 30, 150, 30
    SmokeStroke T_SELECT, 10, 10, 60, 40
    mnuCopy_Click
    mnuPaste_Click
    DropFloat
    UpdateAll
    Debug.Print "SMOKE drawn hash=" & RunCommand("HASH") & " undo=" & UndoCount()
    Do While Undo(): Loop
    UpdateAll
    Debug.Print "SMOKE undo-all " & IIf(RunCommand("HASH") = h, "PASS", "FAIL")
    Do While Redo(): Loop
    NeedAll
    UpdateAll
    Debug.Print "SMOKE redo-all hash=" & RunCommand("HASH")
    view.SaveImage "RAM:tincture-smoke.ppm"
    docDirty = False
    If holdSecs = 0 Then QuitNow
End Sub

Private Sub SmokeStroke(ByVal t As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long)
    Dim i As Long, sx1 As Long, sy1 As Long, sx2 As Long, sy2 As Long
    ActSetTool t
    sx1 = DocToViewX(x1): sy1 = DocToViewY(y1): sx2 = DocToViewX(x2): sy2 = DocToViewY(y2)
    view_MouseDown 1, 0, sx1, sy1
    For i = 1 To 8
        view_MouseMove 1, 0, sx1 + (sx2 - sx1) * i \ 8, sy1 + (sy2 - sy1) * i \ 8
    Next
    view_MouseUp 1, 0, sx2, sy2
End Sub

' N freehand strokes of 50 segments through the real handlers, timed
Private Sub RunBench(ByVal n As Long)
    Dim t0 As Double, t1 As Double, i As Long, k As Long, x As Long, y As Long, segs As Long
    DocNew 640, 512
    ZoomFit
    UpdateAll
    ActSetTool T_FREEHAND
    brushSize = 6
    t0 = Timer
    For i = 1 To n
        x = 20 + (i * 37) Mod 560: y = 20 + (i * 53) Mod 440
        view_MouseDown 1, 0, DocToViewX(x), DocToViewY(y)
        For k = 1 To 50
            view_MouseMove 1, 0, DocToViewX(x + k * 1), DocToViewY(y + (k Mod 10) * 3)
            segs = segs + 1
        Next
        view_MouseUp 1, 0, DocToViewX(x + 50), DocToViewY(y)
    Next
    t1 = Timer
    Debug.Print "BENCH " & n & " strokes, " & segs & " moves: " & Format$((t1 - t0) * 1000# / segs, "0.00") & " ms per mouse move (incl. view redraw)"
    t0 = Timer
    For i = 1 To 20
        RenderView
        view.Refresh
    Next
    Debug.Print "BENCH full view redraw: " & Format$((Timer - t0) * 1000# / 20, "0.00") & " ms"
    t0 = Timer
    For i = 1 To 10
        RunCommand "BOX 100 100 300 200"
        Undo
    Next
    Debug.Print "BENCH undo of a 300x200 box: " & Format$((Timer - t0) * 1000# / 10, "0.00") & " ms (draw + undo)"
    t0 = Timer
    For i = 1 To 5
        curTool = T_FILL
        ToolDown 5, 5, 1 + (i Mod 2), 0
        ToolUp 5, 5, 1 + (i Mod 2), 0
    Next
    Debug.Print "BENCH flood fill of 640x512: " & Format$((Timer - t0) * 1000# / 5, "0.00") & " ms (fill + undo record)"
    docDirty = False
    QuitNow
End Sub
