' Ace Pilot 2 console bench: the autopilot flies the campaign from mission M (seed 1234) and
' every frame is drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--mission M] [--cockpit] [--shots DIR]
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, m As Long
    n = 300
    m = 1
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--mission": If i < UBound(args) Then m = CLng(args(i + 1))
            Case "--cockpit": acView = VIEW_COCKPIT
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize G_W, G_H
    DrawInit cv
    quietEvents = True
    nextSeed = 1234
    ShellStartGame m, False
    acAutoplay = True
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If acState = AS_RESULT And acStateTimer = 0 Then ShellNext: acState = AS_PLAY: acAutoplay = True
        If acState = AS_OVER Then ShellStartGame m, False: acAutoplay = True
        ShellTick
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawGame cv
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then cv.SaveImage shots & "/ap_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Ace Pilot 2 bench: " & n & " frames, seed 1234, from mission " & m
    Print "state: mission " & apMission & " phase " & apPhase & " score " & apScore & " kills " & apKills & _
          " hash " & Hex8(ApStateHash())
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & cv.Hash
    If Len(shots) > 0 Then
        ShellToTitle
        For i = 1 To 150: ShellTick: Next i
        DrawTitle cv
        cv.SaveImage shots & "/ap_title.ppm"
        DrawBrief cv
        cv.SaveImage shots & "/ap_brief.ppm"
        DrawHelp cv, 2
        cv.SaveImage shots & "/ap_help2.ppm"
    End If
End Sub
