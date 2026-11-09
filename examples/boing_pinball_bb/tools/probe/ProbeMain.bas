Option Explicit

Private Sub L(ByVal s As String)
    Dim f As Integer
    f = FreeFile
    Open "RAM:pb_probe.log" For Append As #f
    Print #f, s
    Close #f
End Sub

Sub Main()
    Dim cv As Object, i As Long
    L "start"
    PbCoreInit: L "PbCoreInit"
    PbBuildTable 0: L "PbBuildTable " & tNseg
    GameInit 1: GameStart: L "GameStart"
    For i = 1 To 600
        PbBot: GameTick: gNev = 0
    Next i
    L "600 ticks hash " & Hex8(StateHash())
    Set cv = CreateObject("Boing.Canvas"): L "canvas"
    cv.Resize 640, 512: L "resize"
    FontInit: L "FontInit"
    Set CV = cv: L "set"
    i = cv.CreateImage(640, 1024): L "image " & i
    L "App.Path [" & App.Path & "] dir ppm [" & Dir$(App.Path & "/art/playfield_comet.ppm") & "] dir png [" & Dir$(App.Path & "/art/playfield_comet.png") & "]"
    On Error Resume Next
    i = cv.LoadImage(App.Path & "/art/playfield_comet.png")
    L "LoadImage png -> " & i & " err " & Err.Number & " " & Err.Description
    Err.Clear
    On Error GoTo 0
    L "LoadArt " & LoadArt("playfield_comet")
    DrawInit cv: L "DrawInit"
    dbgLog = "RAM:pb_probe.log"
    DrawBuild 0: L "DrawBuild"
    ShellInit cv, 1: L "ShellInit"
    ShellFrame 20: L "frame"
    ShellDraw: L "draw " & cv.Hash
End Sub
