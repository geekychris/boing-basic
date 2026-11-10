Option Explicit
Const N = 20000
Dim s As String, sb As StringBuilder, i As Long, t As Single
t = Timer
For i = 1 To N
    s = s & "Boing"
Next
Print "s = s & x:     "; Format(Timer - t, "0.000"); " s"
Set sb = CreateObject("StringBuilder")
t = Timer
For i = 1 To N
    sb.Append "Boing"
Next
Print "StringBuilder: "; Format(Timer - t, "0.000"); " s"
