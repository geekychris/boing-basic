' Book.cls
Option Explicit

Public Title As String
Public Year As Long
Private mShelf As Shelf

' Property Set: the property holds an object
Public Property Set Home(ByVal s As Shelf)
    Set mShelf = s
End Property

Public Property Get Home() As Shelf
    Set Home = mShelf           ' Set, because the value is an object
End Property

Public Function Describe() As String
    Describe = Title & " (" & Year & ")"
    If Not mShelf Is Nothing Then Describe = Describe & " on " & mShelf.Name
End Function
