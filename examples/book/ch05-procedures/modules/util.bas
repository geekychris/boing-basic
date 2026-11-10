Option Explicit
Public Counter As Long
Private mSecret As String
Public Const VERSION_TEXT = "1.2"

Public Enum Color
    Red = 1
    Green
    Blue = 10
End Enum

Public Function Twice(ByVal x As Long) As Long
    Counter = Counter + 1
    Twice = x * 2
End Function

Public Property Get Secret() As String
    Secret = "[" & mSecret & "]"
End Property

Public Property Let Secret(ByVal v As String)
    mSecret = UCase$(v)
End Property

Private Function Hidden() As Long
    Hidden = 42
End Function

Public Function CallsHidden() As Long
    CallsHidden = Hidden()
End Function
