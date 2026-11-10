' board.bas - the code-behind of board.afg, a sound board (exercise 8 of the Boing BASIC manual).
' The music is glimmer.mod, a ProTracker module beside the program. The four effects are made
' by the program when it starts, so they need no sample files.
Option Explicit

Private au As Audio                  ' the mixer (every Audio object is the same one)
Private song As Long                 ' the module, 0 if it could not be loaded
Private sLaser As Long, sCoin As Long, sBoom As Long, sJump As Long

Private Sub Form_Load()
    Set au = CreateObject("Boing.Audio")
    au.Open                           ' the default device: AHI on AmigaOS 4
    If au.Device = "none" Then status.Caption = "No AHI device: set one up in Prefs/AHI"

    ' sound effects, synthesised: SynthTone(ms, from Hz, to Hz, volume, wave)
    sLaser = au.SynthTone(180, 1800, 250, 40, 1)       ' a falling square wave
    sJump = au.SynthTone(220, 250, 900, 40, 2)         ' a rising sine
    sBoom = au.SynthNoise(600, 60, 8, 2)               ' noise, softened, dying away
    sCoin = MakeCoin()                                 ' built sample by sample

    ' the music
    On Error Resume Next
    song = au.LoadMusic(App.Path & "/glimmer.mod")
    If Err.Number <> 0 Then
        song = 0
        songInfo.Caption = "glimmer.mod could not be loaded (error " & Err.Number & ")"
    End If
    On Error GoTo 0
    If song > 0 Then
        songInfo.Caption = "Song: " & au.SongName(song) & " (" & au.Channels(song) & " channels)"
        progress.Max = au.SongLength(song)
    End If
    au.MusicVolume = musicVol.Value
    au.SoundVolume = fxVol.Value
    UpdateButtons
End Sub

Private Sub Form_Unload(Cancel As Integer)
    au.Close                          ' stop all sound and free the device
End Sub

' A "coin" sound made by hand: 60 ms of one note, then a higher one, fading out.
' A sound is just a list of numbers (samples): -32768..32767 for a 16-bit sound.
Private Function MakeCoin() As Long
    Dim s As Long, i As Long, n As Long, rate As Long, f As Double, amp As Double
    rate = 22050
    n = rate * 3 \ 10                         ' 0.3 seconds
    s = au.CreateSound(n, rate, 16)
    For i = 0 To n - 1
        If i < rate * 6 \ 100 Then f = 988 Else f = 1319     ' B-5, then E-6
        amp = 12000 * (1 - i / n)                           ' fade out
        ' a square wave: +amp for the first half of each cycle, -amp for the second
        If (i * f / rate) - Int(i * f / rate) < 0.5 Then
            au.SoundData(s, i) = amp
        Else
            au.SoundData(s, i) = -amp
        End If
    Next i
    MakeCoin = s
End Function

' --- music -------------------------------------------------------------------------------

Private Sub play_Click()
    If song = 0 Then Exit Sub
    If au.Paused Then au.Resume Else au.PlayMusic song
    UpdateButtons
End Sub

Private Sub pause_Click()
    If au.Playing And Not au.Paused Then au.Pause
    UpdateButtons
End Sub

Private Sub stopIt_Click()
    au.StopMusic
    progress.Value = 0
    UpdateButtons
End Sub

' The slider: Scroll while it is dragged, Change when it is let go.
Private Sub musicVol_Scroll()
    au.MusicVolume = musicVol.Value
End Sub

Private Sub musicVol_Change()
    au.MusicVolume = musicVol.Value
End Sub

Private Sub UpdateButtons()
    play.Enabled = song > 0 And (Not au.Playing Or au.Paused)
    pause.Enabled = au.Playing And Not au.Paused
    stopIt.Enabled = au.Playing
End Sub

' Five times a second: show where the music is.
Private Sub tick_Timer()
    If au.Playing Then
        status.Caption = "Position " & au.Position & " of " & au.SongLength(song) & ", row " & au.Row & IIf(au.Paused, " (paused)", "")
        progress.Value = au.Position
    ElseIf song > 0 Then
        status.Caption = "Stopped"
    End If
End Sub

' --- sound effects -----------------------------------------------------------------------

Private Sub Effect(ByVal snd As Long)
    ' PlaySound(sound, volume 0..64, pan -64..64): returns the voice it plays on
    au.PlaySound snd, 64, fxPan.Value
End Sub

Private Sub fxLaser_Click(): Effect sLaser: End Sub
Private Sub fxCoin_Click(): Effect sCoin: End Sub
Private Sub fxBoom_Click(): Effect sBoom: End Sub
Private Sub fxJump_Click(): Effect sJump: End Sub

Private Sub fxVol_Change()
    au.SoundVolume = fxVol.Value       ' the master volume of all effects
End Sub

Private Sub fxVol_Scroll()
    au.SoundVolume = fxVol.Value
End Sub

' Keys 1 to 4 play the effects too, and Space starts or pauses the music.
Private Sub Form_KeyPress(KeyAscii As Integer)
    Select Case Chr(KeyAscii)
    Case "1": Effect sLaser
    Case "2": Effect sCoin
    Case "3": Effect sBoom
    Case "4": Effect sJump
    Case " ": If au.Playing And Not au.Paused Then pause_Click Else play_Click
    End Select
End Sub
