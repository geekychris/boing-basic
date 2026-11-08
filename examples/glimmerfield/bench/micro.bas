' Glimmerfield - micro benchmarks of the constructs the game logic leans on

Option Explicit
Type P
    a As Long
    b As Long
    s As Single
End Type
Dim arr(0 To 99) As P
Dim la(0 To 99) As Long
Dim g As Long

Function F1(ByVal x As Long) As Long
    F1 = x + 1
End Function

Sub Main()
    Dim i As Long, j As Long, t As Double, x As Long, y As Single, s As String
    Const N As Long = 20000
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: x = x + j: Next j: Next i
    Print "local loop     "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: la(j) = la(j) + 1: Next j: Next i
    Print "Long array     "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: arr(j).a = arr(j).a + arr(j).b: Next j: Next i
    Print "UDT array field"; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: arr(j).s = arr(j).s * 0.94!: Next j: Next i
    Print "UDT Single mul "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: g = g + 1: Next j: Next i
    Print "module global  "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: x = F1(x): Next j: Next i
    Print "func call      "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: If arr(j).a > 5 And arr(j).b < 3 Then x = x + 1
    Next j: Next i
    Print "If And UDT     "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N: For j = 0 To 99: x = (x + j * 3) \ 2 Mod 1000: Next j: Next i
    Print "\ Mod          "; Format$((TimerMs() - t) * 1000000# / (N * 100#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N \ 10: For j = 0 To 99: s = "+" & CStr(j) & " x" & CStr(i): Next j: Next i
    Print "string concat  "; Format$((TimerMs() - t) * 1000000# / (N * 10#), "0.0"); " ns/iter"
    t = TimerMs()
    For i = 1 To N \ 10: For j = 0 To 99: s = Format$(i, "0000000"): Next j: Next i
    Print "Format$        "; Format$((TimerMs() - t) * 1000000# / (N * 10#), "0.0"); " ns/iter"
    Print x, g
End Sub
