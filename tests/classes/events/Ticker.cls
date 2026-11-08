Public Event Tick(ByVal n As Long)
Public Event Stopping(Cancel As Boolean)

Public Sub Run(ByVal times As Long)
    Dim i As Long, cancel As Boolean
    For i = 1 To times
        RaiseEvent Tick(i)
    Next
    RaiseEvent Stopping(cancel)
    If cancel Then Print "stop cancelled" Else Print "stopped"
End Sub
