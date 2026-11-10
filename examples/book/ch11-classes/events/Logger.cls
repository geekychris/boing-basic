' Logger.cls - listens to a Tank through a WithEvents variable
Option Explicit

Private WithEvents mTank As Tank
Public Lines As Long

Public Sub Watch(t As Tank)
    Set mTank = t               ' connected: mTank_ subs now receive the events
End Sub

Public Sub StopWatching()
    Set mTank = Nothing         ' disconnected
End Sub

Private Sub mTank_Changed(ByVal level As Long)
    Lines = Lines + 1
    Print "  log: level"; level
End Sub

Private Sub mTank_Full(Cancel As Boolean)
    Print "  log: the tank is full, refusing"
    Cancel = True
End Sub
