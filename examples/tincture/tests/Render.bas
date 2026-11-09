Option Explicit
Sub Main()
    Dim a() As String, cv As Object, r As String
    a = Split(Command$, " ")
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 480
    DocAttach cv
    ToolsInit
    ViewInit 640, 480
    r = RunScriptFile(a(0))
    If r <> "" Then Print r
    If Not magOn Then ZoomFit
    RenderView
    cv.SaveImage a(1)
    Dim tb As Object, cp As Object
    Set tb = CreateObject("Boing.Canvas"): tb.Resize ToolBoxWidth(), ToolBoxHeight()
    Set cp = CreateObject("Boing.Canvas"): cp.Resize CP_W, ColourPanelHeight()
    MakeIcons tb
    DrawToolBox tb
    tb.SaveImage Replace(a(1), ".ppm", "-tools.ppm")
    palSel = -1
    SyncPickerFromColour fgColor
    DrawColourPanel cp
    cp.SaveImage Replace(a(1), ".ppm", "-colours.ppm")
End Sub
