Declare Function Foo Lib "exec.library" (ByRef x As Long) As Long
Sub Main()
    Dim i As Integer, l As Long
    l = Foo(l)
    l = Foo(5)
    l = Foo(i)
End Sub
