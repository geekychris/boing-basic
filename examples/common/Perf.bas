' Perf - frame timing (logic / draw / blit) and fps (from Glimmerfield's)
Option Explicit

Public Const PH_LOGIC As Long = 0
Public Const PH_DRAW As Long = 1
Public Const PH_BLIT As Long = 2
Public Const PH_COUNT As Long = 3

Public phaseSum(0 To 2) As Double     ' ms in the current 1 s window
Public phaseAvg(0 To 2) As Double     ' ms per frame over the last window
Public perfFps As Double
Public perfWorst As Double            ' slowest frame of the last window, ms
Public perfLog As Boolean             ' Debug.Print one line per window

Private winStart As Double
Private winFrames As Long
Private winWorst As Double
Private markT As Double
Private frameStart As Double

' Milliseconds from an arbitrary start (monotonic, high resolution).
Public Function NowMs() As Double
    NowMs = TimerMs()
End Function

Public Sub PerfReset()
    Dim i As Long
    For i = 0 To PH_COUNT - 1
        phaseSum(i) = 0
        phaseAvg(i) = 0
    Next i
    winStart = NowMs()
    winFrames = 0
    winWorst = 0
    perfFps = 0
    perfWorst = 0
End Sub

' call at the start of a frame
Public Sub PerfBegin()
    markT = NowMs()
    frameStart = markT
End Sub

' charge the time since the last mark to phase ph
Public Sub PerfAdd(ByVal ph As Long)
    Dim t As Double
    t = NowMs()
    phaseSum(ph) = phaseSum(ph) + (t - markT)
    markT = t
End Sub

' call at the end of a frame
Public Sub PerfEnd()
    Dim t As Double, i As Long, ft As Double
    t = NowMs()
    ft = t - frameStart
    If ft > winWorst Then winWorst = ft
    winFrames = winFrames + 1
    If t < winStart Then winStart = t        ' midnight
    If t - winStart >= 1000# Then
        perfFps = winFrames * 1000# / (t - winStart)
        For i = 0 To PH_COUNT - 1
            phaseAvg(i) = phaseSum(i) / winFrames
            phaseSum(i) = 0
        Next i
        perfWorst = winWorst
        If perfLog Then Debug.Print PerfText()
        winStart = t
        winFrames = 0
        winWorst = 0
    End If
End Sub

Public Function PerfText() As String
    PerfText = "FPS " & Format$(perfFps, "0.0") & _
               "  logic " & Format$(phaseAvg(PH_LOGIC), "0.00") & _
               "  draw " & Format$(phaseAvg(PH_DRAW), "0.00") & _
               "  blit " & Format$(phaseAvg(PH_BLIT), "0.00") & _
               "  worst " & Format$(perfWorst, "0.0") & " ms"
End Function
