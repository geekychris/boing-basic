' Loops the JIT compiles, with every way out of compiled code
Dim i As Integer, j As Long, k As Long, d As Double, s As Long, t As Integer
Dim a(1 To 10) As Long, m(3, 3) As Double, b() As Integer
' Integer overflow inside a hot loop, caught
On Error Resume Next
t = 32000
For i = 1 To 100
    t = t + 10
Next
Print "overflow"; Err.Number; t; i
Err.Clear
' division by zero inside a loop
s = 0
For j = 5 To -5 Step -1
    s = s + 100 \ j
Next
Print "div"; Err.Number; s
Err.Clear
' subscript out of range
For j = 1 To 12
    a(j) = j * j
Next
Print "subscript"; Err.Number; a(10)
Err.Clear
On Error GoTo 0
' Exit For, negative steps, Double steps
s = 0
For j = 100 To 1 Step -3
    s = s + j
    If s > 1000 Then Exit For
Next
Print "exit"; s; j
d = 0
For k = 1 To 1000
    d = d + 0.5 * k
    If d > 1E+300 Then d = 0
Next
Print "double"; d
For d = 0 To 1 Step 0.125
    s = s + 1
Next
Print "dstep"; s; d
' 2-D arrays and Sqr
For j = 0 To 3
    For k = 0 To 3
        m(j, k) = Sqr(j * 4 + k)
    Next
Next
Print Format(m(3, 3), "0.0000"); Format(m(1, 2), "0.0000")
' dynamic array, ReDim between hot loops
ReDim b(1 To 5)
For j = 1 To 5: b(j) = j: Next
ReDim Preserve b(1 To 50)
For j = 6 To 50: b(j) = b(j - 1) + b(j - 5) Mod 100: Next
Print b(50)
' ByRef parameter in a hot loop
Sub Accumulate(total As Long, ByVal n As Long)
    Dim q As Long
    For q = 1 To n
        total = total + q Mod 7
    Next
End Sub
s = 0
Accumulate s, 1000
Print "byref"; s
' UDT fields
Type P
    X As Double
    N As Long
End Type
Dim ps(1 To 4) As P, one As P
For j = 1 To 2000
    k = (j Mod 4) + 1
    ps(k).X = ps(k).X + 0.25
    ps(k).N = ps(k).N + 1
    one.N = one.N + ps(k).N Mod 3
Next
Print ps(1).X; ps(2).N; one.N
' Do loops and Long overflow
On Error GoTo bad
j = 1
Do While j > 0
    j = j * 3
Loop
Print "unreachable"
bad:
Print "long overflow"; Err.Number; j
