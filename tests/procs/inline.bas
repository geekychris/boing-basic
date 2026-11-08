' Small procedures the VM inlines: results, locals, loops, Exit, Static, side effects, errors
Dim calls As Long
Function WrapL(ByVal v As Long, ByVal lim As Long) As Long
    If v < 0 Then
        v = v + lim
    ElseIf v >= lim Then
        v = v - lim
    End If
    WrapL = v
End Function
Function FirstDiv(ByVal n As Long) As Long
    Dim d As Long
    For d = 2 To n
        If n Mod d = 0 Then FirstDiv = d: Exit Function
    Next
    FirstDiv = -1
End Function
Function Noisy(ByVal x As Long) As Long
    calls = calls + 1
    Print "<"; x; ">";
    Noisy = x * 10
End Function
Function Counter() As Long
    Static c As Long
    c = c + 1
    Counter = c
End Function
Function Flag(ByVal x As Long) As Boolean
    Dim b As Boolean
    If x > 2 Then b = True
    Flag = b
End Function
Function NoAssign(ByVal x As Double) As Double
    If x > 100 Then NoAssign = x
End Function
Function Halve(ByVal s As Single) As Single
    Halve = s / 2
End Function
Sub Show(ByVal a As Long, ByVal b As Double)
    If a < 0 Then Exit Sub
    Print "show"; a; b
End Sub
Function Ovf(ByVal i As Integer) As Integer
    Ovf = i * 1000
End Function
Function Outer(ByVal x As Long) As Long
    Outer = WrapL(x, 7) + FirstDiv(x)
End Function
Dim i As Long, t As Long
For i = -10 To 10 Step 3
    t = t + WrapL(i, 7) * 100 + FirstDiv(i + 20)
Next
Print t
Print Noisy(1) + Noisy(2); calls
For i = 1 To 3: t = Counter(): Next
Print t; Counter()
For i = 1 To 4
    If Flag(i) And Not Flag(i - 2) Then Print "flag"; i
Next
Print NoAssign(5); NoAssign(500); Halve(3)
Show -1, 2: Show 3, 0.5
Print Outer(15); Outer(-3)
On Error Resume Next
t = Ovf(30)
Print "err"; Err.Number; t
Err.Clear
On Error GoTo 0
Print Ovf(40)
