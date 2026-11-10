' reminder.bas - Reminder TEXT/A,MINUTES/N,REPEAT/S
' Shows a notification after MINUTES minutes (10 by default), again and again with REPEAT.
' Ctrl-Alt-R shows the time left; Exchange's Remove (or Ctrl-C) ends it.
Option Explicit

Private message As String
Private minutes As Long
Private dueAt As Double            ' seconds since the program started
Private quitting As Boolean
Private lastTime As Single, elapsed As Double

Public Sub Main()
    If Not App.ReadArgs("TEXT/A,MINUTES/N,REPEAT/S") Then
        If App.FromWorkbench Then                       ' no Shell to print to
            App.Request "Reminder's icon needs the tooltype TEXT=..." & vbLf & _
                        "(and MINUTES=, if given, a whole number).", "_OK", "Reminder", vbExclamation
        Else
            Print "Usage: Reminder TEXT/A,MINUTES/N,REPEAT/S"
        End If
        Exit Sub
    End If
    message = App.ArgValue("TEXT")
    minutes = Val(App.ArgValue("MINUTES"))
    If minutes <= 0 Then minutes = 10

    On Error Resume Next
    App.HotKey "left", "ctrl alt r"        ' also gives Reminder an entry in Exchange
    If Err.Number <> 0 Then Print "No hotkey: is Reminder running already?"
    On Error GoTo 0

    lastTime = Timer
    dueAt = minutes * 60
    Tell "Reminder in " & minutes & " minutes: " & message
    Do Until quitting
        DoEvents                           ' hotkeys, Exchange and application.library
        Sleep 100
        Tick
        If elapsed >= dueAt Then
            Tell message
            If App.ArgValue("REPEAT") = "1" Then dueAt = dueAt + minutes * 60 Else quitting = True
        End If
    Loop
End Sub

' the seconds since the start (Timer goes back to 0 at midnight)
Private Sub Tick()
    Dim t As Single
    t = Timer
    If t < lastTime Then elapsed = elapsed + t + 86400 - lastTime Else elapsed = elapsed + t - lastTime
    lastTime = t
End Sub

' a notification; a requester if notifications don't work (no Ringhio server running)
Private Sub Tell(ByVal text As String)
    On Error GoTo noRinghio
    App.Notify "Reminder", text
    Exit Sub
noRinghio:
    App.Request text, "_OK", "Reminder", vbInformation
End Sub

' Ctrl-Alt-R, from any program
Sub HotKey_Pressed(Name As String)
    If Name = "left" Then Tell CLng((dueAt - elapsed) / 60) & " minutes left: " & message
End Sub

' Exchange's Remove, or a Quit sent through application.library
Sub App_Quit()
    quitting = True
End Sub

' Exchange's Show: tell what is set
Sub App_Show()
    HotKey_Pressed "left"
End Sub
