' Sphere Siege console bench: the autopilot plays from seed 1234 and every frame is
' drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--shots DIR] [--wave W]
' prints the state and picture hashes and the time per frame; --shots writes a
' PPM picture every 100 frames.
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, rnd As Long
    n = 300
    rnd = 1
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--wave": If i < UBound(args) Then rnd = CLng(args(i + 1))
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    Set gcv = cv
    gcv.Resize G_W, G_H
    SsInit
    DrawInit
    SoundInit
    If InStr(Command$, "--grid1") > 0 Then gridDetail = 1
    startWave = rnd
    SsNewGame 1234, rnd
    duState = 1
    duAutoplay = True
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If ssOver <> 0 Then SsNewGame ssSeed + 1, 1
        SsTick SsBot()
        HandleEvents True
        AgeEffects
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawGame False, True
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then gcv.SaveImage shots & "/ss_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Sphere Siege bench: " & n & " frames, seed 1234, wave " & rnd
    Print "state: wave " & ssWave & " score " & ssScore & " kills " & ssKills & " hash " & Hex8(SsStateHash()) & _
          " picture " & gcv.Hash
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "sound: " & SfxTotal() & " effects started"
    If Len(shots) > 0 Then
        DrawTitle
        gcv.SaveImage shots & "/ss_title.ppm"
        DrawHelp 1
        gcv.SaveImage shots & "/ss_help.ppm"
    End If
End Sub
