' Tincture - actions shared by the menus, keys, dialogs and the ARexx port, and the flags that
' tell the main form what to redraw (the form redraws on its next event or timer tick)
Option Explicit

Public dlgPurpose As Long, dlgFresh As Boolean
Public needView As Boolean, needTools As Boolean, needColours As Boolean, needLayers As Boolean
Public needTitle As Boolean, needFit As Boolean
Public ditherOnReduce As Boolean
Public createIcons As Boolean
Public statusMsg As String

Public Sub NeedAll()
    needView = True: needTools = True: needColours = True: needLayers = True: needTitle = True
End Sub

Public Sub ActNewPicture(ByVal w As Long, ByVal h As Long, ByVal fill As Long, ByVal colourMode As Long)
    If colourMode > 0 Then
        StandardPalette IIf(colourMode = 2, 256, 32)
        fill = NearestPal(fill)
        fgColor = NearestPal(fgColor): bgColor = NearestPal(bgColor)
    End If
    DocNew w, h, fill
    If colourMode > 0 Then docMode = MODE_INDEXED
    SelectNone
    needFit = True
    statusMsg = "New picture " & w & " x " & h & IIf(colourMode > 0, ", " & palCount & " colours", "")
    NeedAll
End Sub

' the default 32 colours; for 256 also a 6 x 6 x 6 colour cube and 8 greys
Public Sub StandardPalette(ByVal n As Long)
    Dim i As Long
    DefaultPalette
    If n >= 256 Then
        For i = 0 To 215
            pal(32 + i) = RGB((i Mod 6) * 51, ((i \ 6) Mod 6) * 51, (i \ 36) * 51)
        Next
        For i = 0 To 7
            pal(248 + i) = RGB(i * 32 + 16, i * 32 + 16, i * 32 + 16)
        Next
        palCount = 256
    End If
End Sub

Public Sub ActResize(ByVal w As Long, ByVal h As Long, ByVal scaleIt As Boolean)
    ResizeDoc w, h, scaleIt
    needFit = True
    NeedAll
End Sub

Public Sub OpenDialog(ByVal purpose As Long)
    dlgPurpose = purpose
    dlgFresh = True
End Sub

Public Sub ActUndo()
    If Undo() Then statusMsg = "Undone" Else statusMsg = "Nothing to undo"
    NeedAll
End Sub

Public Sub ActRedo()
    If Redo() Then statusMsg = "Redone" Else statusMsg = "Nothing to redo"
    NeedAll
End Sub

Public Sub ActSetTool(ByVal t As Long)
    If t = curTool Then Exit Sub
    If IsStroking() Then Exit Sub
    If t <> T_SELECT And floatImg Then DropFloat
    curTool = t
    statusMsg = ToolName(t)
    needTools = True: needView = True
End Sub

Public Sub ActBrushSize(ByVal s As Long)
    If s < 1 Then s = 1
    If s > 64 Then s = 64
    brushSize = s
    needView = True
End Sub

' a picture or a project was dropped / chosen: open it, or (keepDoc) float it into this one
Public Function ActOpenFile(ByVal path As String, ByVal asFloat As Boolean, ByVal x As Long, ByVal y As Long) As Boolean
    Dim img As Long
    If asFloat And docW > 0 Then
        img = LoadAsImage(path)
        If img = 0 Then statusMsg = lastError: Exit Function
        PasteImage img, x, y
        statusMsg = FilePart(path) & " pasted: drag it, click outside to drop"
        ActOpenFile = True
    ElseIf OpenPicture(path) Then
        statusMsg = "Opened " & FilePart(path) & " (" & docW & " x " & docH & IIf(docMode = MODE_INDEXED, ", " & palCount & " colours", "") & ")"
        needFit = True
        ActOpenFile = True
    Else
        statusMsg = lastError
    End If
    NeedAll
End Function

' the ARexx port: one command line; Result for the caller, rc 0 / 10
Public Function ActScript(ByVal cmdline As String, rc As Long) As String
    Dim r As String
    r = RunCommand(cmdline)
    If Left$(r, 6) = "ERROR " Then
        rc = 10
        r = Mid$(r, InStr(7, r, " ") + 1)
    Else
        rc = 0
    End If
    NeedAll
    ActScript = r
End Function
