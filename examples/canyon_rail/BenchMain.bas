' Canyon Rail console bench: the autopilot rides from seed 1234 and every frame is
' drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--shots DIR] [--stage S]
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
            Case "--stage": If i < UBound(args) Then rnd = CLng(args(i + 1))
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    Set gcv = cv
    gcv.Resize G_W, G_H
    CrInit
    DrawInit
    SoundInit
    startStage = rnd
    CrNewGame 1234, rnd
    duState = 1
    duAutoplay = True
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If crOver <> 0 Or crWon <> 0 Then CrNewGame crSeed + 1, 1
        CrTick CrBot()
        HandleEvents True
        AgeEffects
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawGame False, True
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then gcv.SaveImage shots & "/cr_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Canyon Rail bench: " & n & " frames, seed 1234, stage " & rnd
    Print "state: stage " & crStage & " score " & crScore & " kills " & crKills & " hash " & Hex8(CrStateHash()) & _
          " picture " & gcv.Hash
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "sound: " & SfxTotal() & " effects started"
    If Len(shots) > 0 Then
        DrawTitle
        gcv.SaveImage shots & "/cr_title.ppm"
        DrawHelp 1
        gcv.SaveImage shots & "/cr_help.ppm"
    End If
End Sub
