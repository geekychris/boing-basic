Option Explicit
Private mCount As Long
Public Label As String

Private Sub Class_Initialize()
    mCount = 0
    Label = "counter"
    Print "init"
End Sub

Private Sub Class_Terminate()
    Print "terminate "; Label
End Sub

Public Property Get Value() As Long
    Value = mCount
End Property

Public Property Let Value(ByVal v As Long)
    If v < 0 Then Err.Raise 380, "Counter", "negative value"
    mCount = v
End Property

Public Sub Increment(Optional ByVal by As Long = 1)
    mCount = mCount + by
End Sub

Public Function Twice() As Long
    Twice = mCount * 2
End Function

Public Function Describe() As String
    Describe = Label & "=" & Value
End Function
