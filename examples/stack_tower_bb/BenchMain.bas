' Stack Tower console bench: the bot plays marathon from seed 1234 and every frame is
' drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--shots DIR] [--mode 0|1|2] [--level L]
' prints the state and picture hashes and the time per frame; --shots writes a PPM
' picture every 100 frames, and the title, help and score screens.
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, md As Long, lv As Long
    n = 300
    lv = 1
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--mode": If i < UBound(args) Then md = CLng(args(i + 1))
            Case "--level": If i < UBound(args) Then lv = CLng(args(i + 1))
            Case "--prof": profOn = True
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize G_W, G_H
    DrawInit cv
    svGhost = 1
    svStartLevel = lv
    quietEvents = True
    nextSeed = 1234
    ShellStartGame md, lv
    autoplay = True
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If svState = SS_OVER Then ShellStartGame md, lv: autoplay = True
        ShellTick
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawGame cv
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then cv.SaveImage shots & "/st_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Stack Tower bench: " & n & " frames, " & stModeName(md) & " seed 1234, level " & lv
    Print "state: level " & stLevel & " score " & stScore & " rings " & stLines & " pieces " & stPieces & _
          " hash " & Hex8(StStateHash()) & " picture " & cv.Hash
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    If profOn Then Print "parts: sky " & Format$(prSky / n, "0.000") & " build " & Format$(prBuild / n, "0.000") & _
          " faces " & Format$(prAdd / n, "0.000") & " flush " & Format$(prFlush / n, "0.000") & " panel " & Format$(prPanel / n, "0.000")
    Print "picture hash " & cv.Hash
    If Len(shots) > 0 Then
        ShellToTitle
        For i = 1 To 300: ShellTick: Next i
        DrawTitle cv
        cv.SaveImage shots & "/st_title_art.ppm"
        For i = 1 To 260: DrawTitle cv: Next i
        DrawTitle cv
        cv.SaveImage shots & "/st_title_demo.ppm"
        DrawHelp cv, 1
        cv.SaveImage shots & "/st_help1.ppm"
        DrawHelp cv, 2
        cv.SaveImage shots & "/st_help2.ppm"
    End If
End Sub
