' Boing Pinball console bench: the bot plays a game on a table, 50 frames a
' second of game time (20 ms each, whatever the real time), every frame drawn on
' an off-screen 640 x 512 Canvas; prints the state and picture hashes and the time
' per frame. Runs on the Mac too.
'   boing run Bench.bbp [--frames N] [--table T] [--shots DIR] [--build]
' --shots writes PPM pictures (every 250 frames, the title, help, scores);
' --build times building each table's picture.
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, tb As Long, tTot As Double, buildT As Boolean
    n = 500
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--table": If i < UBound(args) Then tb = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--build": buildT = True
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize SCR_W, SCR_H
    t = TimerMs()
    ShellInit cv, 1
    Print "init (fonts, ball, Comet Tour's picture): " & Format$(TimerMs() - t, "0") & " ms"
    If buildT Then
        For i = 0 To TB_COUNT - 1
            t = TimerMs()
            ChooseTable i
            Print "build " & tName & ": " & Format$(TimerMs() - t, "0") & " ms (load the painting " & Format$(buildLoadMs, "0") & _
                  ", paint " & Format$(buildPaintMs, "0") & ", ramps " & Format$(buildRampMs, "0") & ", patches and sprites " & Format$(buildPatchMs, "0") & ")"
        Next i
    End If
    If Len(shots) > 0 Then
        ShellDraw
        cv.SaveImage shots & "/pb_title_art.ppm"
        titleFrames = 300
        ShellFrame 20
        ShellDraw
        cv.SaveImage shots & "/pb_title_demo.ppm"
        pHelp = 1: ShellDraw: cv.SaveImage shots & "/pb_help1.ppm"
        pHelp = 2: ShellDraw: cv.SaveImage shots & "/pb_help2.ppm"
        pHelp = 0
    End If
    StartGame tb
    botPlay = True
    BotReset 99
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        ShellFrame 20
        tl = tl + TimerMs() - t
        t = TimerMs()
        ShellDraw
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 250 = 0 Then cv.SaveImage shots & "/pb_" & TableKey(dTable) & "_" & Format$(i, "0000") & ".ppm"
        If pState = PS_OVER Then StartGame tb: botPlay = True
    Next i
    tTot = TimerMs() - t0
    Print "Boing Pinball bench: " & n & " frames on " & tName & ", the bot from seed 99"
    Print "state: score " & gScore & " ball " & gBallNo & " steps " & stepsRun & " hash " & Hex8(StateHash())
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / tTot, "0.0") & " fps"
    Print "picture hash " & cv.Hash
    If Len(shots) > 0 Then
        ToScores2
        ShellDraw
        cv.SaveImage shots & "/pb_scores.ppm"
    End If
End Sub

Private Sub ToScores2()
    pState = PS_SCORES
    entryRank = 2
End Sub
