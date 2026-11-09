' Tincture - the command language of the ARexx port (and of the tests and --script files)
'
' One command per call: RunCommand("LINE 10 10 100 50") returns the result string; errors
' return "ERROR <n> <message>" (the ARexx port turns that into RC 10 and the message).
' Commands are case-insensitive; numbers are pixels of the picture; colours are R G B, or
' #RRGGBB. See Tincture.guide, node "ARexx", for the full list.
Option Explicit

Public scriptQuit As Boolean          ' QUIT was given

Private Function Arg(w() As String, ByVal i As Long, Optional ByVal def As String = "") As String
    If i <= UBound(w) Then Arg = w(i) Else Arg = def
End Function

Private Function NArg(w() As String, ByVal i As Long, Optional ByVal def As Long = 0) As Long
    If i <= UBound(w) Then
        If IsNumeric(w(i)) Then NArg = CLng(w(i)) Else Err.Raise 13, "Tincture", "Number expected: " & w(i)
    Else
        NArg = def
    End If
End Function

' a colour from the words at i: "R G B" or "#RRGGBB"; n gets the number of words used
Private Function ColourArg(w() As String, ByVal i As Long, n As Long) As Long
    Dim s As String
    s = Arg(w, i)
    If Left$(s, 1) = "#" And Len(s) = 7 Then
        ColourArg = RGB(CLng("&H" & Mid$(s, 2, 2)), CLng("&H" & Mid$(s, 4, 2)), CLng("&H" & Mid$(s, 6, 2)))
        n = 1
    Else
        ColourArg = RGB(NArg(w, i) And 255, NArg(w, i + 1) And 255, NArg(w, i + 2) And 255)
        n = 3
    End If
End Function

' split a command line into words; "quoted text" is one word
Public Function Words(ByVal s As String) As String()
    Dim out() As String, n As Long, i As Long, ch As String, cur As String, inQ As Boolean, have As Boolean
    ReDim out(0 To 0)
    n = -1
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If inQ Then
            If ch = """" Then inQ = False Else cur = cur & ch
        ElseIf ch = """" Then
            inQ = True: have = True
        ElseIf ch = " " Or ch = vbTab Then
            If have Then n = n + 1: ReDim Preserve out(0 To n): out(n) = cur: cur = "": have = False
        Else
            cur = cur & ch: have = True
        End If
    Next
    If have Then n = n + 1: ReDim Preserve out(0 To n): out(n) = cur
    If n < 0 Then ReDim out(0 To 0): out(0) = ""
    Words = out
End Function

Private Function ToolByName(ByVal s As String) As Long
    Select Case UCase$(s)
        Case "FREEHAND", "DRAW", "PENCIL", "BRUSH": ToolByName = T_FREEHAND
        Case "LINE": ToolByName = T_LINE
        Case "RECT", "RECTANGLE": ToolByName = T_RECT
        Case "RECTF", "BOX", "FILLEDRECT": ToolByName = T_RECTF
        Case "ELLIPSE", "OVAL": ToolByName = T_ELLIPSE
        Case "ELLIPSEF", "FILLEDELLIPSE", "DISC": ToolByName = T_ELLIPSEF
        Case "FILL", "FLOOD": ToolByName = T_FILL
        Case "AIRBRUSH", "SPRAY": ToolByName = T_AIRBRUSH
        Case "TEXT": ToolByName = T_TEXT
        Case "SELECT": ToolByName = T_SELECT
        Case "PICK", "EYEDROPPER": ToolByName = T_PICK
        Case "ERASER", "ERASE": ToolByName = T_ERASER
        Case "GRADIENT": ToolByName = T_GRADIENT
        Case Else: Err.Raise 5, "Tincture", "Unknown tool " & s
    End Select
End Function

' one stroke of a tool through the normal mouse path (x/y pairs)
Private Sub Stroke(ByVal tool As Long, pts() As Long, ByVal n As Long, ByVal btn As Long, ByVal shift As Long)
    Dim saved As Long, i As Long
    saved = curTool
    curTool = tool
    ToolDown pts(0), pts(1), btn, shift
    For i = 1 To n - 1
        ToolMove pts(2 * i), pts(2 * i + 1), shift
    Next
    ToolUp pts(2 * (n - 1)), pts(2 * (n - 1) + 1), btn, shift
    If curTool = tool Then curTool = saved
    Recomposite
End Sub

Private Sub Stroke2(ByVal tool As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long, ByVal btn As Long)
    Dim p(0 To 3) As Long
    p(0) = x1: p(1) = y1: p(2) = x2: p(3) = y2
    Stroke tool, p, 2, btn, 0
End Sub

Private Function Btn(w() As String) As Long
    Dim i As Long
    Btn = 1
    For i = 1 To UBound(w)
        If UCase$(w(i)) = "BG" Or UCase$(w(i)) = "BACKGROUND" Then Btn = 2
    Next
End Function

Private Function HasWord(w() As String, ByVal word As String) As Boolean
    Dim i As Long
    For i = 1 To UBound(w)
        If UCase$(w(i)) = word Then HasWord = True: Exit Function
    Next
End Function

Public Function RunCommand(ByVal cmdline As String) As String
    Dim w() As String, c As String, n As Long, i As Long, r As String, img As Long
    Dim pts() As Long, k As Long
    On Error GoTo failed
    w = Words(cmdline)
    c = UCase$(w(0))
    If c = "" Or Left$(c, 1) = ";" Or Left$(c, 1) = "#" Then Exit Function
    If docW = 0 And c <> "NEW" And c <> "OPEN" And c <> "VERSION" And c <> "QUIT" Then DocNew 320, 256
    Select Case c
        Case "VERSION": r = "Tincture " & APP_VERSION
        Case "NEW"
            DocNew NArg(w, 1, 320), NArg(w, 2, 256)
        Case "OPEN"
            If Not OpenPicture(Arg(w, 1)) Then Err.Raise 53, "Tincture", lastError
        Case "SAVE"
            If Arg(w, 1) = "" Then
                If docPath = "" Then Err.Raise 5, "Tincture", "No file name"
                If Not SavePicture(docPath) Then Err.Raise 75, "Tincture", lastError
            Else
                Select Case UCase$(Arg(w, 2))
                    Case "PNG": k = FMT_PNG
                    Case "ILBM", "IFF": k = FMT_ILBM
                    Case "TINC": k = FMT_TINC
                    Case Else: k = FMT_AUTO
                End Select
                If Not SavePicture(Arg(w, 1), k) Then Err.Raise 75, "Tincture", lastError
            End If
        Case "INFO"
            r = docW & " " & docH & " " & nLayers & " " & curLayer & " " & docMode & " " & palCount & " " & IIf(docDirty, 1, 0)
        Case "FILENAME": r = docPath
        Case "COLOR", "COLOUR", "FGCOLOR", "FGCOLOUR"
            If Arg(w, 1) = "" Then r = ColorHex(fgColor) Else fgColor = ColourArg(w, 1, n)
        Case "BGCOLOR", "BGCOLOUR"
            If Arg(w, 1) = "" Then r = ColorHex(bgColor) Else bgColor = ColourArg(w, 1, n)
        Case "PALETTE"
            ' PALETTE i [R G B | #RRGGBB]: read or set an entry
            i = NArg(w, 1)
            If Arg(w, 2) = "" Then r = ColorHex(pal(i)) Else SetPaletteEntry i, ColourArg(w, 2, n)
        Case "PEN"
            fgColor = pal(NArg(w, 1))
        Case "TOOL"
            If Arg(w, 1) = "" Then r = ToolName(curTool) Else curTool = ToolByName(Arg(w, 1))
        Case "BRUSH", "BRUSHSIZE"
            brushSize = NArg(w, 1, 1)
            If brushSize < 1 Then brushSize = 1
            If brushSize > 64 Then brushSize = 64
            brushSquare = HasWord(w, "SQUARE")
        Case "PLOT", "DOT"
            Stroke2 T_FREEHAND, NArg(w, 1), NArg(w, 2), NArg(w, 1), NArg(w, 2), Btn(w)
        Case "DRAW"
            ' DRAW x1 y1 x2 y2 ... : a freehand stroke through the points
            n = UBound(w) \ 2
            If n < 1 Then Err.Raise 5, "Tincture", "DRAW needs points"
            ReDim pts(0 To 2 * n - 1)
            For i = 0 To 2 * n - 1
                pts(i) = NArg(w, i + 1)
            Next
            Stroke T_FREEHAND, pts, n, 1, 0
        Case "LINE": Stroke2 T_LINE, NArg(w, 1), NArg(w, 2), NArg(w, 3), NArg(w, 4), Btn(w)
        Case "RECT", "BOX"
            k = IIf(HasWord(w, "FILL") Or c = "BOX", T_RECTF, T_RECT)
            Stroke2 k, NArg(w, 1), NArg(w, 2), NArg(w, 1) + NArg(w, 3) - 1, NArg(w, 2) + NArg(w, 4) - 1, Btn(w)
        Case "ELLIPSE", "CIRCLE"
            ' ELLIPSE cx cy rx ry [FILL]  /  CIRCLE cx cy r [FILL]
            If c = "CIRCLE" Then
                i = NArg(w, 3): k = i
            Else
                i = NArg(w, 3): k = NArg(w, 4)
            End If
            Stroke2 IIf(HasWord(w, "FILL"), T_ELLIPSEF, T_ELLIPSE), NArg(w, 1) - i, NArg(w, 2) - k, NArg(w, 1) + i, NArg(w, 2) + k, Btn(w)
        Case "FILL", "FLOOD"
            If Arg(w, 3) <> "" And IsNumeric(Arg(w, 3)) Then fillTolerance = NArg(w, 3)
            Stroke2 T_FILL, NArg(w, 1), NArg(w, 2), NArg(w, 1), NArg(w, 2), Btn(w)
        Case "SPRAY", "AIRBRUSH"
            ' SPRAY x y [radius [density]]
            If Arg(w, 3) <> "" And IsNumeric(Arg(w, 3)) Then airRadius = NArg(w, 3)
            If Arg(w, 4) <> "" And IsNumeric(Arg(w, 4)) Then airDensity = NArg(w, 4)
            Stroke2 T_AIRBRUSH, NArg(w, 1), NArg(w, 2), NArg(w, 1), NArg(w, 2), Btn(w)
        Case "GRADIENT"
            ' GRADIENT x1 y1 x2 y2: foreground to background over the selection (or the layer)
            Stroke2 T_GRADIENT, NArg(w, 1), NArg(w, 2), NArg(w, 3), NArg(w, 4), Btn(w)
        Case "ERASE"
            n = UBound(w) \ 2
            ReDim pts(0 To 2 * n - 1)
            For i = 0 To 2 * n - 1
                pts(i) = NArg(w, i + 1)
            Next
            Stroke T_ERASER, pts, n, 1, 0
        Case "TEXT"
            ' TEXT x y "text" [scale]
            pendingText = Arg(w, 3)
            If Arg(w, 4) <> "" Then textScale = NArg(w, 4)
            Stroke2 T_TEXT, NArg(w, 1), NArg(w, 2), NArg(w, 1), NArg(w, 2), Btn(w)
            DropFloat
            Recomposite
        Case "GETPIXEL", "PIXEL"
            Recomposite
            r = ColorHex(cv.ImagePoint(comp, NArg(w, 1), NArg(w, 2)))
        Case "SELECT"
            If UCase$(Arg(w, 1)) = "ALL" Then
                SelectAll
            ElseIf UCase$(Arg(w, 1)) = "NONE" Or Arg(w, 1) = "" Then
                SelectNone
            Else
                SelectRect NArg(w, 1), NArg(w, 2), NArg(w, 3), NArg(w, 4)
            End If
        Case "COPY": If Not CopySelection() Then Err.Raise 5, "Tincture", "Nothing selected"
        Case "CUT": If Not CutSelection() Then Err.Raise 5, "Tincture", "Nothing selected"
        Case "CLEAR": ClearSelection
        Case "PASTE"
            If clipImg = 0 Then Err.Raise 5, "Tincture", "The clipboard is empty"
            PasteAt NArg(w, 1), NArg(w, 2)
            If Not HasWord(w, "FLOAT") Then DropFloat
        Case "MOVE"
            ' MOVE dx dy: move the selection's contents
            If floatImg = 0 Then LiftSelection False
            MoveFloat floatX + NArg(w, 1), floatY + NArg(w, 2)
            DropFloat
        Case "DROP": DropFloat
        Case "MAKEBRUSH": If Not BrushFromSelection() Then Err.Raise 5, "Tincture", "Nothing selected"
        Case "RESETBRUSH": BrushReset
        Case "BRUSHMODE": brushOwnColours = (UCase$(Arg(w, 1)) <> "COLOUR" And UCase$(Arg(w, 1)) <> "COLOR")
        Case "UNDO"
            n = NArg(w, 1, 1)
            For i = 1 To n
                If Not Undo() Then Exit For
            Next
        Case "REDO"
            n = NArg(w, 1, 1)
            For i = 1 To n
                If Not Redo() Then Exit For
            Next
        Case "UNDOCOUNT": r = CStr(UndoCount())
        Case "LAYER"
            Select Case UCase$(Arg(w, 1))
                Case "ADD", "NEW": AddLayer Arg(w, 2)
                Case "DELETE": DeleteLayer
                Case "SELECT"
                    i = NArg(w, 2)
                    If i >= 1 And i <= nLayers Then DropFloat: curLayer = i
                Case "UP": MoveLayer 1
                Case "DOWN": MoveLayer -1
                Case "MERGE": MergeDown
                Case "FLATTEN": FlattenLayers
                Case "HIDE": SetLayerVisible NArg(w, 2, curLayer), False
                Case "SHOW": SetLayerVisible NArg(w, 2, curLayer), True
                Case "OPACITY": SetLayerOpacity curLayer, NArg(w, 2, 255)
                Case "NAME": layers(curLayer).name = Arg(w, 2): MarkChanged
                Case "", "INFO": r = curLayer & " " & nLayers & " " & layers(curLayer).name
                Case Else: Err.Raise 5, "Tincture", "LAYER ADD|DELETE|SELECT n|UP|DOWN|MERGE|FLATTEN|HIDE|SHOW|OPACITY n|NAME s"
            End Select
        Case "FLIP": FlipDoc UCase$(Arg(w, 1)) = "V" Or UCase$(Arg(w, 1)) = "VERTICAL"
        Case "ROTATE": RotateDoc NArg(w, 1, 90) \ 90
        Case "SCALE": ResizeDoc NArg(w, 1), NArg(w, 2), True
        Case "CANVASSIZE", "RESIZE": ResizeDoc NArg(w, 1), NArg(w, 2), False
        Case "CROP"
            If Arg(w, 1) <> "" Then
                CropDoc NArg(w, 1), NArg(w, 2), NArg(w, 3), NArg(w, 4)
            ElseIf selActive Then
                CropDoc selX, selY, selW, selH
            End If
        Case "INDEXED": ToIndexed NArg(w, 1, 32), HasWord(w, "DITHER")
        Case "TRUECOLOUR", "TRUECOLOR": ToTrueColour
        Case "HASH"
            Recomposite
            r = CStr(cv.ImageHash(comp))
        Case "ZOOM"
            If Arg(w, 1) = "" Then r = CStr(ViewZoom()) Else SetViewZoom NArg(w, 1)
        Case "MAGNIFIER"
            SetMagnifier UCase$(Arg(w, 1)) <> "OFF"
            If Arg(w, 2) <> "" Then magX = NArg(w, 2): magY = NArg(w, 3)
        Case "GRID": showGrid = UCase$(Arg(w, 1)) <> "OFF"
        Case "QUIT": scriptQuit = True
        Case Else
            Err.Raise 5, "Tincture", "Unknown command " & w(0)
    End Select
    Recomposite
    RunCommand = r
    Exit Function
failed:
    RunCommand = "ERROR " & Err.Number & " " & Err.Description
End Function

' run a script file of commands; returns the results, one line each (blank results skipped)
Public Function RunScriptFile(ByVal path As String) As String
    Dim f As Integer, ln As String, r As String, out As String
    f = FreeFile
    Open path For Input As #f
    Do While Not EOF(f)
        Line Input #f, ln
        r = RunCommand(ln)
        If r <> "" Then out = out & r & vbLf
        If scriptQuit Then Exit Do
    Loop
    Close #f
    RunScriptFile = out
End Function
