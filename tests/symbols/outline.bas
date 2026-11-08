Option Explicit
Public Const MAX_ITEMS As Long = 10
Private Type Point
    X As Long
    Y As Long
End Type
Public Enum Dir
    North
    South = 5
End Enum
Dim count As Integer, names() As String
Declare Function DisplayBeep Lib "intuition.library" (ByVal scr As Long) As Long

Public Function Add(ByVal a As Long, Optional b As Long = 1) As Long
    Dim total As Long
    total = a + b
    Add = total
End Function

Private Sub Show(msg As String)
    Static n As Integer
again:
    Print msg
End Sub

Property Get Count() As Integer
    Count = count
End Property
