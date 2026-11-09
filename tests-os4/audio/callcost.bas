' the cost of Audio calls on the guest while AHI plays (VM): lock-free reads vs locked calls
Dim au As Object, s As Long, i As Long, x As Long, t As Double, p As String, sc() As Long
p = App.Path
If Right(p, 1) <> "/" And Right(p, 1) <> ":" Then p = p & "/"
If Dir(p & "fx.mod") = "" Then p = p & "tests-os4/audio/"
Set au = CreateObject("Boing.Audio")
au.Open
au.Volume = 30
s = au.LoadMusic(p & "fx.mod")
au.PlayMusic s
t = Timer
For i = 1 To 2000: x = au.Row: Next
Print "Row (no lock): "; Format((Timer - t) * 1000000# / 2000, "0.0"); " us"
t = Timer
For i = 1 To 2000: x = au.MusicVolume: Next
Print "MusicVolume (lock): "; Format((Timer - t) * 1000000# / 2000, "0.0"); " us"
t = Timer
For i = 1 To 500: sc = au.Scope(0, 96): Next
Print "Scope 96: "; Format((Timer - t) * 1000000# / 500, "0.0"); " us"
t = Timer
For i = 1 To 2000: x = Len(CStr(i)): Next
Print "baseline loop+CStr: "; Format((Timer - t) * 1000000# / 2000, "0.0"); " us"
Print "mixer cpu "; Format(au.CpuLoad / 10, "0.0"); " %"
au.Close
Print "PASS"
