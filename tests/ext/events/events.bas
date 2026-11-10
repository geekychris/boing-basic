Dim WithEvents tk As Ticker
Dim total As Long

Sub tk_Tick(ByVal i As Long, ByVal label As String)
    total = total + i
    Print label; " ";
End Sub

Sub tk_Done()
    Print "| done, total"; total
End Sub

Sub Main()
    Dim w As New Watcher
    Set tk = New Ticker
    tk.Run 3
    w.Watch
    Set tk = Nothing
    Print "runs"; w.Count
End Sub
