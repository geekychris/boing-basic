' Audio on AmigaOS 4: the same PCM as on the Mac (manual device), then real output via AHI
' (tools/os4guest.py bas tests-os4/audio/audio.bas both, after pushing fx.mod beside it)
Dim au As Object, s As Long, n As Long, ok As Boolean, d As Long, v As Long, h1 As String, h2 As String
Dim p As String, t0 As Double, pos0 As Long, row0 As Long, moved As Long, load As Long, i As Long
p = App.Path
If Right(p, 1) <> "/" And Right(p, 1) <> ":" Then p = p & "/"
If Dir(p & "fx.mod") = "" Then p = p & "tests-os4/audio/"    ' the VM: App.Path is boing's directory
ok = True
Set au = CreateObject("Boing.Audio")
au.Open "manual", 22050
s = au.LoadMusic(p & "fx.mod")
au.Loop = False
au.PlayMusic s
Do While au.Playing And n < 400
    au.Render 2205
    n = n + 1
Loop
h1 = Hex(au.PcmHash)
Print "mod hash "; h1; " blocks "; n
If h1 <> "DE632796" Then ok = False: Print "  expected DE632796"
au.ResetHash
d = au.SynthTone(200, 880, 220, 48, 1)
v = au.PlaySound(d, 40, -20, 0, True)
d = au.SynthNoise(300, 50, 4, 5)
v = au.PlaySound(d, 64, 30, 16000)
au.PlayMusic s
au.Render 22050
h2 = Hex(au.PcmHash)
Print "sfx hash "; h2
If h2 <> "48225B05" Then ok = False: Print "  expected 48225B05"
au.Close

' real output, moderate volume, ~3 s
au.Open
Print "device "; au.Device; " rate "; au.Rate
If au.Device <> "ahi" Then ok = False
au.Volume = 40
s = au.LoadMusic(p & "fx.mod")
au.PlayMusic s
t0 = Timer
pos0 = au.Position: row0 = au.Row
For i = 1 To 30
    Sleep 100
    If au.Row <> row0 Then moved = moved + 1: row0 = au.Row
    If i Mod 10 = 0 Then v = au.PlaySound(d, 40)
Next
load = au.CpuLoad
Print "rows moved "; moved; " in "; Format(Timer - t0, "0.0"); " s, mixer cpu "; Format(load / 10, "0.0"); " %"
If moved < 10 Then ok = False
au.StopMusic
au.Close
Print "device after close "; au.Device
If ok Then Print "PASS" Else Print "FAIL"
