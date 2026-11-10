Option Explicit
Dim web As Http, ticks As Long
Set web = CreateObject("Http")
web.OnProgress = "Progress"
web.GetAsync "https://example.com/files/game.lha"
Do While web.Busy
    ticks = ticks + 1          ' here the program could do something useful
    DoEvents
Loop
If web.ErrorNumber <> 0 Then
    Print "Failed: "; web.ErrorText
ElseIf web.Status = 200 Then
    Print web.BytesReceived; " bytes"
Else
    Print "The server said"; web.Status; " "; web.StatusText
End If

Sub Progress(got As Long, total As Long)
    If total > 0 Then Print (got * 100# \ total); "%" Else Print got; " bytes"
End Sub
