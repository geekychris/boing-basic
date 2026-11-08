' scalar fields of Me in register ops; Me released by the fast return
Private n As Long
Private d As Double
Private s As Single
Private k As Integer
Public Name As String
Public Sub Add(ByVal x As Long)
    n = n + x
    d = d + x / 4
    s = s * 0.5! + 1
End Sub
Public Property Get Total() As Long
    Total = n
End Property
Public Property Let Total(ByVal v As Long)
    n = v
End Property
Public Function Avg() As Double
    Avg = d / 2
End Function
Public Function Sng() As Single
    Sng = s
End Function
Public Sub IncK()
    k = k + 10000
End Sub
Public Function GetK() As Integer
    GetK = k
End Function
Public Sub DropGlobal()
    Set keep = Nothing
    n = n + 1
End Sub
Private Sub Class_Terminate()
    Print "terminate "; Name; n
End Sub
