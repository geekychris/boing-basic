' Counter.cls - a counter that can only go up, with a lower and upper limit
Option Explicit

Private mValue As Long          ' member variables: one set per object
Private mLimit As Long
Public Caption As String        ' a Public variable is a property

Private Sub Class_Initialize()
    mLimit = 100
    Caption = "counter"
    Print "Class_Initialize"
End Sub

Private Sub Class_Terminate()
    Print "Class_Terminate "; Caption
End Sub

' a method: a Public Sub
Public Sub Increment(Optional ByVal by As Long = 1)
    Value = mValue + by         ' goes through Property Let, so the check below runs
End Sub

Public Sub Reset()
    mValue = 0
End Sub

' a read/write property: Property Get and Property Let with the same name
Public Property Get Value() As Long
    Value = mValue
End Property

Public Property Let Value(ByVal v As Long)
    If v < 0 Or v > mLimit Then Err.Raise 380, "Counter", "Value must be 0 to " & mLimit
    mValue = v
End Property

' a read-only property: Property Get only
Public Property Get Limit() As Long
    Limit = mLimit
End Property

' a method that returns a value: a Public Function
Public Function Describe() As String
    Describe = Caption & " = " & mValue
End Function
