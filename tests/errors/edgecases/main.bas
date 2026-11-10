Declare Function Foo Lib "dos.library" Alias "#9" (n As Long) As Long
Declare Function Bar Lib "dos.library" Alias "#10" (s As String) As Long
Declare Function Baz Lib "dos.library" Alias "#11" (i As Integer) As Long
Sub Main()
    Dim l As Long, s As String, i As Integer
    l = Foo(l): l = Bar(s): l = Baz(i)
    l = Foo((l))
    l = Bar("lit")
    l = Baz(3)
    Dim h As Object
    Set h = New Http
End Sub
