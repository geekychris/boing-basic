' Lander 3D guest check: each picture loaded into an off-screen canvas and drawn, then
' the Audio object, the module and an effect, a line after each step.
Option Explicit

Sub Main()
    Dim cv As Object, au As Object, nm As Variant, id As Long, t As Double, p As String, song As Long, s As Long
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 512
    Print "canvas ok"
    For Each nm In Array("sky_moon", "sky_mars", "sky_asteroid", "lander_title")
        t = TimerMs()
        id = cv.LoadImage(p & "art/" & nm & ".png")
        Print nm & ": image " & id & " " & cv.ImageWidth(id) & "x" & cv.ImageHeight(id) & " in " & Format$(TimerMs() - t, "0") & " ms"
        cv.DrawImagePart id, 100, 0, 540, 200, 0, 0, True
        cv.DrawImage id, 0, 0, True
        Print "  drawn, hash " & cv.Hash
    Next nm
    If Command$ <> "noaudio" Then
        Set au = CreateObject("Boing.Audio")
        Print "audio " & au.Device
        song = au.LoadMusic(p & "lander_3d.mod")
        Print "music " & song
        au.PlayMusic song
        Sleep 1500
        s = au.SynthTone(200, 500, 900)
        au.PlaySound s, 40
        Sleep 500
        Print "playing " & au.Playing & " position " & au.Position
        au.StopMusic
        au.Close
        Print "audio closed"
    End If
    Print "picture hash done"
End Sub
