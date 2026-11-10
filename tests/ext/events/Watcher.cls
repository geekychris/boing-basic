Private WithEvents t As Ticker
Public Count As Long

Public Sub Watch()
    Set t = New Ticker
    t.Run 2
End Sub

Private Sub t_Tick(ByVal i As Long, ByVal label As String)
    Count = Count + 1
End Sub

Private Sub t_Done()
    Print "watcher done"; Count
End Sub
