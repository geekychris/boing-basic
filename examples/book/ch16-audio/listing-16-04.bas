Option Explicit

Dim au As Audio
Dim song As Long, answer As String

Sub Main()
    Set au = CreateObject("Boing.Audio")
    au.Open
    If au.Device = "none" Then Print "No AHI device: set one up in Prefs/AHI"
    On Error Resume Next
    song = au.LoadMusic("PROGDIR:tune.mod")
    If Err.Number <> 0 Then
        Print "Can't load the music: error"; Err.Number
        Exit Sub
    End If
    On Error GoTo 0
    au.MusicVolume = 40
    au.PlayMusic song
    Print "Playing "; au.SongName(song); ". Press Return to stop."
    Line Input answer
    au.StopMusic
End Sub
