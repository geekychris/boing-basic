' Tank.cls - a water tank that tells its listeners what happens
Option Explicit

Public Event Changed(ByVal level As Long)
Public Event Full(Cancel As Boolean)        ' ByRef: a handler can set Cancel
Public Event Emptied()

Private mLevel As Long
Public Capacity As Long

Private Sub Class_Initialize()
    Capacity = 100
End Sub

Public Sub Fill(ByVal amount As Long)
    Dim stopIt As Boolean
    If mLevel + amount > Capacity Then
        RaiseEvent Full(stopIt)
        If stopIt Then Exit Sub         ' a handler said no
        amount = Capacity - mLevel
    End If
    mLevel = mLevel + amount
    RaiseEvent Changed(mLevel)
End Sub

Public Sub Drain()
    mLevel = 0
    RaiseEvent Changed(mLevel)
    RaiseEvent Emptied
End Sub

Public Property Get Level() As Long
    Level = mLevel
End Property
