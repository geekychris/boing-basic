Option Explicit
Sub Main()
    Dim t As Double, i As Long
    t = TimerMs()
    SoundInit App.Path & "/../../art/boing_pinball.mod"
    Print "SoundInit " & Format$(TimerMs() - t, "0") & " ms, device " & SoundDevice()
    For i = 0 To 15
        Sfx i
    Next i
    Print "played " & soundsPlayed & ", " & SoundInfo()
    SoundCleanup
End Sub
