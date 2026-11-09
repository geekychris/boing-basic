Option Explicit
Sub Main()
    Dim cv As Object, t0 As Double, i As Long, k As Long, x As Long, y As Long, n As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 480
    DocAttach cv
    ToolsInit
    ViewInit 640, 480
    DocNew 640, 512
    ZoomFit
    brushSize = 6
    curTool = T_FREEHAND
    t0 = Timer
    For i = 1 To 100
        x = 20 + (i * 37) Mod 560: y = 20 + (i * 53) Mod 440
        ToolDown x, y, 1, 0
        For k = 1 To 50
            ToolMove x + k, y + (k Mod 10) * 3, 0
            cursorX = x + k: cursorY = y: cursorIn = True
            RenderView
            n = n + 1
        Next
        ToolUp x + 50, y, 1, 0
    Next
    Print "per move (stroke + view): "; Format$((Timer - t0) * 1000# / n, "0.000"); " ms"
    t0 = Timer
    For i = 1 To 200
        RenderView
    Next
    Print "view redraw: "; Format$((Timer - t0) * 1000# / 200, "0.000"); " ms"
    t0 = Timer
    For i = 1 To 5000
        ToolMove 100 + (i Mod 2), 100, 0
    Next
    Print "ToolMove alone (no stroke): "; Format$((Timer - t0) * 1000# / 5000, "0.0000"); " ms"
End Sub
