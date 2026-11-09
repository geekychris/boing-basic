' Lander 3D console bench: the autopilot flies the tour from seed 2026 and every frame
' is drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--shots DIR] [--title] [--win N]
' prints the state and picture hashes and the time per frame; --shots writes a PPM
' picture every 100 frames (and the title, help and score screens).
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, titleOnly As Boolean
    n = 300
    args = Split(Trim$(Command$), " ")
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 512
    DrawInit cv
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--title": titleOnly = True
            Case "--win": If i < UBound(args) Then groundWin = CLng(args(i + 1))
        End Select
    Next i
    GameInit
    SoundInit False
    HsSetup Array("ALDRIN", "ARMSTRNG", "CONRAD", "BEAN", "SHEPARD", "MITCHELL", "SCOTT", "IRWIN"), 400
    HsDefaults
    entryRank = -1
    If Not titleOnly Then
        StartGame MODE_TOUR, 1
        gDemo = True
    End If
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If gState = LS_OVER And gStateTimer = 0 Then
            StartGame MODE_TOUR, 1
            gDemo = True
        End If
        GameFrame
        If gWorldChanged Then
            DrawPalette ld.world
            gWorldChanged = False
        End If
        tl = tl + TimerMs() - t
        t = TimerMs()
        If gState = LS_TITLE Then DrawTitle Else DrawGame
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then cv.SaveImage shots & "/ld_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Lander 3D bench: " & n & " frames, the tour, seed 2026"
    Print "state: " & wName(ld.world) & " level " & ld.lvl & " score " & gScore & " ships " & gShips & _
          " t " & ld.t & " hash " & Hex8(LdStateHash()) & " picture " & cv.Hash
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    If Len(shots) > 0 Then
        DrawHelp 1
        cv.SaveImage shots & "/ld_help1.ppm"
        DrawHelp 2
        cv.SaveImage shots & "/ld_help2.ppm"
        DrawScores
        cv.SaveImage shots & "/ld_scores.ppm"
        ToTitle
        DrawPalette ld.world
        DrawTitle
        cv.SaveImage shots & "/ld_title.ppm"
    End If
End Sub
