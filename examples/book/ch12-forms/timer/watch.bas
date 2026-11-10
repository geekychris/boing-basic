' watch.bas
Option Explicit

Private tenths As Long

Private Sub tick_Timer()                ' every 100 ms while tick.Enabled
    tenths = tenths + 1
    display.Caption = Format(tenths / 10, "0.0") & " s"
    minute.Value = tenths Mod 600
End Sub

Private Sub clock_Timer()               ' every second: the time of day in the title
    Me.Caption = "Stopwatch - " & Format(Now, "hh:nn:ss")
End Sub

Private Sub startStop_Click()
    tick.Enabled = Not tick.Enabled
    If tick.Enabled Then startStop.Caption = "_Stop" Else startStop.Caption = "_Start"
End Sub

Private Sub clear_Click()
    tenths = 0
    display.Caption = "0.0 s"
    minute.Value = 0
End Sub
