' Tincture host test (make test): runs the paint program's core off-screen through the same
' command language the ARexx port uses, and checks pixels, hashes, undo and file round trips
Option Explicit

Private fails As Long

Private Sub Check(ByVal what As String, ByVal got As String, ByVal want As String)
    If got = want Then
        Print "ok   "; what
    Else
        Print "FAIL "; what; ": got '"; got; "' want '"; want; "'"
        fails = fails + 1
    End If
End Sub

Private Function C(ByVal cmd As String) As String
    C = RunCommand(cmd)
    If Left$(C, 6) = "ERROR " Then Print "  ("; cmd; " -> "; C; ")"
End Function

Sub Main()
    Dim h0 As String, h1 As String, h2 As String, t As Double, i As Long
    DocAttach CreateObject("Boing.Canvas")
    ToolsInit
    ViewInit 320, 200

    Check "version", C("VERSION"), "Tincture " & APP_VERSION
    C "NEW 64 48"
    Check "info", C("INFO"), "64 48 1 1 0 32 0"
    Check "white", C("GETPIXEL 5 5"), "#FFFFFF"
    h0 = C("HASH")

    ' freehand, line, shapes
    C "COLOR 255 0 0"
    C "DRAW 2 2 20 2 20 10"
    Check "draw", C("GETPIXEL 10 2"), "#FF0000"
    Check "draw corner", C("GETPIXEL 20 6"), "#FF0000"
    Check "dirty", Right$(C("INFO"), 1), "1"
    C "COLOR #0000FF"
    C "BRUSH 5"
    C "LINE 5 30 40 30"
    Check "thick line", C("GETPIXEL 20 32") & C("GETPIXEL 20 33"), "#0000FF#FFFFFF"
    C "BRUSH 1"
    C "RECT 40 5 10 8"
    Check "rect", C("GETPIXEL 40 8") & C("GETPIXEL 44 8"), "#0000FF#FFFFFF"
    C "BOX 52 5 8 8"
    Check "box", C("GETPIXEL 55 8"), "#0000FF"
    C "COLOR 0 160 0"
    C "CIRCLE 50 38 6 FILL"
    Check "disc", C("GETPIXEL 50 38") & C("GETPIXEL 50 31"), "#00A000#FFFFFF"
    h1 = C("HASH")
    Check "undo count", C("UNDOCOUNT"), "5"

    ' undo / redo
    C "UNDO"
    Check "undo disc", C("GETPIXEL 50 38"), "#FFFFFF"
    C "REDO"
    Check "redo disc", C("GETPIXEL 50 38"), "#00A000"
    C "UNDO 5"
    Check "undo all", C("HASH"), h0
    C "REDO 5"
    Check "redo all", C("HASH"), h1
    C "UNDO 2"
    C "PLOT 1 1"
    Check "redo gone", C("REDO") & C("UNDOCOUNT"), "4"

    ' symmetry
    C "NEW 40 30"
    C "COLOR 0 0 0"
    C "SYMMETRY 4"
    C "PLOT 2 3"
    C "SYMMETRY OFF"
    Check "symmetry", C("GETPIXEL 2 3") & C("GETPIXEL 37 3") & C("GETPIXEL 2 26") & C("GETPIXEL 37 26") & C("UNDOCOUNT"), "#000000#000000#000000#0000001"

    ' flood fill
    C "NEW 40 30"
    C "COLOR 0 0 0"
    C "RECT 5 5 20 15"
    C "COLOR 255 255 0"
    C "FILL 10 10"
    Check "fill in", C("GETPIXEL 10 10") & C("GETPIXEL 2 2"), "#FFFF00#FFFFFF"
    C "UNDO"
    Check "fill undo", C("GETPIXEL 10 10"), "#FFFFFF"

    ' selection, copy / paste / move / cut
    C "NEW 40 30"
    C "COLOR 255 0 0"
    C "BOX 2 2 4 4"
    C "SELECT 2 2 4 4"
    C "COPY"
    C "PASTE 20 20"
    Check "paste", C("GETPIXEL 21 21") & C("GETPIXEL 3 3"), "#FF0000#FF0000"
    C "SELECT 2 2 4 4"
    C "MOVE 10 0"
    Check "move", C("GETPIXEL 3 3") & C("GETPIXEL 13 3"), "#FFFFFF#FF0000"
    C "UNDO"
    Check "move undo", C("GETPIXEL 3 3") & C("GETPIXEL 13 3"), "#FF0000#FFFFFF"
    C "SELECT 20 20 4 4"
    C "CUT"
    Check "cut", C("GETPIXEL 21 21"), "#FFFFFF"

    ' custom brush from the selection
    C "NEW 40 30"
    C "COLOR 0 0 255"
    C "BOX 0 0 3 3"
    C "SELECT 0 0 3 3"
    C "MAKEBRUSH"
    C "SELECT NONE"
    C "DRAW 20 20 30 20"
    Check "brush stamp", C("GETPIXEL 19 19") & C("GETPIXEL 31 21") & C("GETPIXEL 25 22"), "#0000FF#0000FF#FFFFFF"
    C "RESETBRUSH"

    ' layers
    C "NEW 40 30"
    C "LAYER ADD Ink"
    Check "layer add", C("LAYER"), "2 2 Ink"
    C "COLOR 255 0 0"
    C "BOX 0 0 10 10"
    C "LAYER HIDE"
    Check "hidden", C("GETPIXEL 5 5"), "#FFFFFF"
    C "LAYER SHOW"
    C "LAYER OPACITY 128"
    Check "opacity", C("GETPIXEL 5 5"), "#FF7F7F"
    C "LAYER OPACITY 255"
    C "ERASE 2 2 4 4"
    Check "erase to transparent", C("GETPIXEL 3 3") & C("GETPIXEL 8 8"), "#FFFFFF#FF0000"
    C "LAYER SELECT 1"
    C "COLOR 0 0 0"
    C "BOX 0 0 40 30"
    Check "under", C("GETPIXEL 3 3") & C("GETPIXEL 8 8"), "#000000#FF0000"
    C "LAYER SELECT 2"
    C "LAYER MERGE"
    Check "merge", C("INFO"), "40 30 1 1 0 32 1"
    Check "merged", C("GETPIXEL 3 3") & C("GETPIXEL 8 8"), "#000000#FF0000"
    C "UNDO"
    Check "merge undo", Left$(C("INFO"), 9), "40 30 2 2"
    C "LAYER DELETE"
    Check "delete", Left$(C("INFO"), 9), "40 30 1 1"
    C "UNDO"
    Check "delete undo", C("GETPIXEL 8 8"), "#FF0000"

    ' whole-picture operations
    C "NEW 40 30"
    C "COLOR 255 0 0"
    C "PLOT 0 0"
    C "ROTATE 90"
    Check "rotate", Left$(C("INFO"), 5) & C("GETPIXEL 29 0"), "30 40#FF0000"
    C "FLIP H"
    Check "flip", C("GETPIXEL 0 0"), "#FF0000"
    C "SCALE 60 80"
    Check "scale", Left$(C("INFO"), 5) & C("GETPIXEL 0 0"), "60 80#FF0000"
    C "UNDO 3"
    Check "undo size", Left$(C("INFO"), 5) & C("GETPIXEL 0 0"), "40 30#FF0000"
    C "CANVASSIZE 50 50"
    Check "canvas size", Left$(C("INFO"), 5) & C("GETPIXEL 45 45"), "50 50#FFFFFF"
    C "CROP 0 0 10 10"
    Check "crop", Left$(C("INFO"), 5), "10 10"

    ' text
    C "NEW 60 30"
    C "COLOR 0 0 0"
    C "TEXT 2 2 ""Hi"" 2"
    Check "text", C("GETPIXEL 2 2") <> "#FFFFFF" Or C("GETPIXEL 3 3") <> "#FFFFFF" Or C("GETPIXEL 4 4") <> "#FFFFFF", "True"

    ' indexed colour and palette edits
    C "NEW 32 32"
    C "COLOR 200 10 10"
    C "BOX 0 0 16 32"
    C "COLOR 10 10 200"
    C "BOX 16 0 16 32"
    C "INDEXED 4"
    Check "indexed", Mid$(C("INFO"), 11, 1), "1"
    C "PALETTE 0 0 255 0"
    Check "palette edit", C("PALETTE 0"), "#00FF00"

    ' file round trips
    C "NEW 50 40"
    C "COLOR 255 128 0"
    C "CIRCLE 25 20 15 FILL"
    C "SPRAY 10 10 6 50"
    h2 = C("HASH")
    C "SAVE rt.png"
    Check "saved clean", Right$(C("INFO"), 1), "0"
    C "NEW 10 10"
    C "OPEN rt.png"
    Check "png round trip", C("HASH"), h2
    C "SAVE rt.iff"
    C "NEW 10 10"
    C "OPEN rt.iff"
    Check "ilbm round trip", C("HASH") & " " & Left$(C("INFO"), 5), h2 & " 50 40"
    C "INDEXED 8"
    h2 = C("HASH")
    C "SAVE rt8.iff"
    C "OPEN rt8.iff"
    Check "ilbm8 round trip", C("HASH") & " " & Mid$(C("INFO"), 11), h2 & " 1 2 0"
    C "LAYER ADD Top"
    C "COLOR 0 0 0"
    C "BOX 1 1 5 5"
    C "LAYER OPACITY 100"
    h2 = C("HASH")
    C "SAVE rt.tinc"
    C "NEW 10 10"
    C "OPEN rt.tinc"
    Check "tinc round trip", C("HASH") & " " & C("LAYER") & " " & Left$(C("INFO"), 7), h2 & " 2 2 Top 50 40 2"
    Check "open error", Left$(RunCommand("OPEN nosuchfile.png"), 8), "ERROR 53"
    Check "bad command", RunCommand("FROB"), "ERROR 5 Unknown command FROB"

    ' autosave and recovery
    autosavePath = "auto.tinc"
    C "NEW 30 20"
    C "BOX 0 0 5 5"
    Check "autosave", CStr(Autosave()), "True"
    h2 = C("HASH")
    C "NEW 10 10"
    Check "recover", CStr(RecoverAutosave()) & " " & C("HASH") & " " & Right$(C("INFO"), 1), "True " & h2 & " 1"
    ClearAutosave
    Check "autosave gone", CStr(HasAutosave()), "False"

    ' the view: zoom, mapping and drawing
    C "NEW 64 48"
    SetViewZoom 400
    Dim dx As Long, dy As Long
    scrollX = 0: scrollY = 0
    ViewToDoc 9, 13, dx, dy
    Check "view map", dx & " " & dy, "2 3"
    ZoomFit
    Check "fit", CStr(zoomPct), "400"
    SetMagnifier True
    RenderView
    Check "render", CStr(cv.Point(0, 0) <> -1), "True"
    SetMagnifier False

    Kill "rt.png": Kill "rt.iff": Kill "rt8.iff": Kill "rt.tinc"
    If fails = 0 Then Print "PASS" Else Print "FAIL"; fails
End Sub
