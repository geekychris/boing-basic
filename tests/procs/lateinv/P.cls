Public Total As Long
Private st(1 To 4) As Long

Public Function Add(ByVal a As Long, Optional ByVal b As Long = 10) As Long
    Total = Total + a + b
    Add = Total
End Function

Public Function Twice(ByRef v As Long) As Long
    v = v * 2
    Twice = v
End Function

Public Function TwiceV(v) As Variant
    v = v & v
    TwiceV = v
End Function

Public Function Str2(ByVal s As String, ByVal d As Double) As String
    Str2 = s & ":" & CStr(d)
End Function

Public Function Fails(ByVal n As Long) As Long
    Fails = 100 \ n
End Function

Public Function Handled(ByVal n As Long) As Long
    On Error GoTo bad
    Handled = 100 \ n
    Exit Function
bad:
    Handled = -Err.Number
End Function

Public Function Fact(ByVal n As Long) As Long
    Dim me2 As Object
    Set me2 = Me
    If n <= 1 Then Fact = 1 Else Fact = n * me2.Fact(n - 1)
End Function

Public Property Get Item(ByVal i As Long) As Long
    Item = st(i)
End Property

Public Property Let Item(ByVal i As Long, ByVal v As Long)
    st(i) = v
End Property

Public Function State() As Long()
    State = st
End Function

Public Function Opt(Optional x As Variant) As String
    If IsMissing(x) Then Opt = "missing" Else Opt = "got " & CStr(x)
End Function

Public Sub Bump()
    Total = Total + 1
End Sub

Public Function Self() As P
    Set Self = Me
End Function
