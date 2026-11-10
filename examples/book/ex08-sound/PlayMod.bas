' PlayMod.bas - play a ProTracker module from the Shell (step 2 of exercise 8).
'   boing run PlayMod.bas                    plays glimmer.mod (beside this file)
'   boing run PlayMod.bas DH0:Mods/song.mod  plays another module
' It stops when the song has played through once, or when you press Ctrl-C.
Option Explicit

Dim au As Audio, song As Long, path As String, lastPos As Long

path = Trim(Command())
If path = "" Then path = App.Path & "/glimmer.mod"

Set au = CreateObject("Boing.Audio")
song = au.LoadMusic(path)             ' error 53 if the file isn't there
Print "Playing " & au.SongName(song) & " (" & au.Channels(song) & " channels, " & au.SongLength(song) & " positions)"
au.Loop = False                       ' stop at the end instead of starting again
au.PlayMusic song
lastPos = -1
Do While au.Playing
    If au.Position <> lastPos Then
        lastPos = au.Position
        Print "Position"; lastPos; "pattern"; au.Pattern
    End If
    Sleep 100                         ' wait a tenth of a second; the music plays on meanwhile
Loop
Print "The end."
