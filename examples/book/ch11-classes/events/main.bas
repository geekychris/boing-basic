' main.bas - a standard module can hold WithEvents variables too
Option Explicit

Dim WithEvents water As Tank
Dim book As New Logger

Sub water_Changed(ByVal level As Long)
    Print "main: level is now"; level
End Sub

Sub water_Emptied()
    Print "main: empty"
End Sub

Sub Main()
    Set water = New Tank
    book.Watch water
    water.Fill 60
    water.Fill 60               ' too much: Full is raised, the logger cancels
    Print "level"; water.Level
    book.StopWatching
    water.Fill 60               ' nobody cancels now: filled to the top
    water.Drain
    Print "the logger wrote"; book.Lines; "lines"
End Sub
