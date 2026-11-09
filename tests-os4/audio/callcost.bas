' the cost of Audio calls on the guest while AHI plays (VM): lock-free reads vs locked calls
Dim au As Object, s As Long, i As Long, x As Long, t As Double, p As String, sc() As Long
Set au = CreateObject("Boing.Audio")
au.Open
au.Volume = 30
' a 4-channel song made here (RAM: may not have fx.mod): a looped square on every channel
s = au.NewSong(4)
au.SampleLength(s, 1) = 32
For i = 0 To 31
    If i < 16 Then au.SampleData(s, 1, i) = 60 Else au.SampleData(s, 1, i) = -60
Next
au.SampleLoopLength(s, 1) = 32
au.SampleVolume(s, 1) = 30
For i = 0 To 63 Step 4
    au.SetCell s, 0, i, i Mod 4, 13 + (i \ 4) Mod 12, 1, 0, 0
Next
au.PlayMusic s
t = TimerMs()
For i = 1 To 20000: x = au.Row: Next
Print "Row (no lock): "; Format((TimerMs() - t) * 1000# / 20000, "0.00"); " us"
t = TimerMs()
For i = 1 To 20000: x = au.MusicVolume: Next
Print "MusicVolume (lock): "; Format((TimerMs() - t) * 1000# / 20000, "0.00"); " us"
t = TimerMs()
For i = 1 To 500: sc = au.Scope(0, 96): Next
Print "Scope 96: "; Format((TimerMs() - t) * 1000# / 500, "0.00"); " us"
Dim st() As Long
t = TimerMs()
For i = 1 To 2000: st = au.State(): Next
Print "State(): "; Format((TimerMs() - t) * 1000# / 2000, "0.00"); " us"
t = TimerMs()
For i = 1 To 500: sc = au.Scopes(96): Next
Print "Scopes(96) x4 ch: "; Format((TimerMs() - t) * 1000# / 500, "0.00"); " us"
t = TimerMs()
For i = 1 To 2000: x = Len(CStr(i)): Next
Print "baseline loop+CStr: "; Format((TimerMs() - t) * 1000# / 2000, "0.00"); " us"
Print "mixer cpu "; Format(au.CpuLoad / 10, "0.0"); " %"
au.Close
Print "PASS"
