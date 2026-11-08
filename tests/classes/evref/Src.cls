Public Event Ask(ByRef answer As Long, ByRef text As Variant)
Public Sub Go()
    Dim a As Long, t As Variant
    a = 1: t = "start"
    RaiseEvent Ask(a, t)
    Print "after event:"; a; " "; t
End Sub
