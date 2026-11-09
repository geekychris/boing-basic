' ScAIry Fun console bench: the perfect autopilot drives from route R and every frame is drawn
' on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--route R] [--cockpit] [--shots DIR]
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, r As Long
    n = 300
    r = 1
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--route": If i < UBound(args) Then r = CLng(args(i + 1))
            Case "--cockpit": wView = CAM_COCKPIT
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize G_W, G_H
    DrawInit cv
    quietEvents = True
    tuSpeedPct = 0
    WorldInit
    If args(0) = "--cockpit" Or InStr(Command$, "--cockpit") > 0 Then wView = CAM_COCKPIT
    tuAiPerfect = 1
    WorldStartGame
    If r > 1 Then WorldStartRoute r - 1
    wState = GS_PLAY
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If wState <> GS_PLAY Then
            WorldStartRoute (wRoute + 1) Mod NUM_ROUTES
            wState = GS_PLAY
        End If
        ShellTick 0
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawFrame cv
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then cv.SaveImage shots & "/sc_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "ScAIry Fun bench: " & n & " frames, the perfect autopilot from route " & r
    Print "state: route " & (wRoute + 1) & " seg " & SegOf(carZ) & " score " & wScore & " hash " & Hex8(ScStateHash())
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & cv.Hash
End Sub
