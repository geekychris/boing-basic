' Counter.cls - a class that counts. Each New Counter has its own count.
Option Explicit

Public Name As String          ' a Public variable is a property anyone can set
Private mCount As Long         ' Private: only this class's code sees it

Private Sub Class_Initialize()
    mCount = 0
    Name = "counter"
End Sub

Public Sub Add(Optional ByVal n As Long = 1)
    mCount = mCount + n
End Sub

Public Property Get Count() As Long
    Count = mCount
End Property
