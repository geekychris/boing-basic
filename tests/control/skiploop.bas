' For i: If arr(i).flag Then ... : Next (one fused op skips the entries with flag 0)
Type E
    act As Boolean
    w As Integer
    n As Long
End Type
Dim a(1 To 20) As E, i As Long, cnt As Long, s As Long
For i = 1 To 20 Step 3: a(i).act = True: a(i).n = i * 10: Next
a(20).w = 5
For i = 1 To 20
    If a(i).act Then cnt = cnt + 1: s = s + a(i).n
Next
Print cnt; s; i
cnt = 0
For i = 20 To 1 Step -2
    If a(i).act Then cnt = cnt + 1
Next
Print cnt; i
For i = 1 To 20
    If a(i).w Then Print "w at"; i
Next
For i = 1 To 20
    If a(i).n > 100 Then Print "big"; i;
Next
Print
For i = 5 To 4
    If a(i).act Then Print "never"
Next
Print "empty"; i
On Error Resume Next
cnt = 0
For i = 18 To 25
    If a(i).act Then cnt = cnt + 1
Next
Print "err"; Err.Number; i; cnt
