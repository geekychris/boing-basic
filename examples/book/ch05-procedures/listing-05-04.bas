Sub AddOneRef(n As Long)          ' ByRef is the default
    n = n + 1
End Sub

Sub AddOneVal(ByVal n As Long)
    n = n + 1
End Sub

Sub Swap(a As Long, b As Long)
    Dim t As Long
    t = a: a = b: b = t
End Sub

Dim k As Long, x As Long, y As Long
k = 1
AddOneVal k: Print k
AddOneRef k: Print k
AddOneRef (k): Print k            ' (k) is an expression: a copy is passed
x = 1: y = 2
Swap x, y
Print x; y
