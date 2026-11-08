Public Name As String
Public NextNode As Node
Private Sub Class_Terminate()
    Print "bye "; Name
End Sub
Public Function Fail() As Long
    Err.Raise 1234, "Node", "failed in " & Name
End Function
Public Property Get Upper() As String
    Upper = UCase$(Name)
End Property
