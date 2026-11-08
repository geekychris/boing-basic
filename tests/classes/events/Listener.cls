Private WithEvents mTicker As Ticker
Public Total As Long

Public Sub Attach(t As Ticker)
    Set mTicker = t
End Sub

Public Sub Detach()
    Set mTicker = Nothing
End Sub

Private Sub mTicker_Tick(ByVal n As Long)
    Total = Total + n
    Print "listener got"; n
End Sub

Private Sub mTicker_Stopping(Cancel As Boolean)
    Cancel = True
End Sub
