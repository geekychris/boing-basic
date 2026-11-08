Dim WithEvents clock As Ticker

Sub clock_Tick(ByVal n As Long)
    Print "module tick"; n
End Sub

Dim t As New Ticker, l As New Listener
l.Attach t
t.Run 2
Print "total"; l.Total
Set clock = t
t.Run 1
l.Detach
Set clock = Nothing
t.Run 1
Print "done"
