' Orbit Docking console bench: the autopilot flies from station L (seed 1234) and every frame
' is drawn on an off-screen Canvas (the Mac too).
'   boing run Bench.bbp [--frames N] [--level L] [--shots DIR]
Option Explicit

Sub Main()
    Dim cv As Object, args() As String, i As Long, n As Long, shots As String, t0 As Double
    Dim tl As Double, td As Double, t As Double, lv As Long
    n = 300
    lv = 1
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--frames": If i < UBound(args) Then n = CLng(args(i + 1))
            Case "--shots": If i < UBound(args) Then shots = args(i + 1)
            Case "--level": If i < UBound(args) Then lv = CLng(args(i + 1))
        End Select
    Next i
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize G_W, G_H
    DrawInit cv
    quietEvents = True
    nextSeed = 1234
    ShellStartGame lv
    dkAutoplay = True
    t0 = TimerMs()
    For i = 1 To n
        t = TimerMs()
        If dkState = DS_OVER Then ShellStartGame lv: dkAutoplay = True
        ShellTick
        tl = tl + TimerMs() - t
        t = TimerMs()
        DrawGame cv
        td = td + TimerMs() - t
        If Len(shots) > 0 And i Mod 100 = 0 Then cv.SaveImage shots & "/od_" & Format$(i, "0000") & ".ppm"
    Next i
    t = TimerMs() - t0
    Print "Orbit Docking bench: " & n & " frames, seed 1234, station " & lv
    Print "state: station " & odLevel & " score " & odScore & " docks " & odDocks & " crashes " & odCrashes & _
          " hash " & Hex8(OdStateHash())
    Print "time: logic " & Format$(tl / n, "0.000") & " draw " & Format$(td / n, "0.000") & " ms/frame, " & _
          Format$(n * 1000# / t, "0.0") & " fps;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & cv.Hash
    If Len(shots) > 0 Then
        ShellToTitle
        For i = 1 To 200: ShellTick: Next i
        DrawTitle cv
        cv.SaveImage shots & "/od_title.ppm"
        DrawHelp cv, 1
        cv.SaveImage shots & "/od_help1.ppm"
    End If
End Sub
