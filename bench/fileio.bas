' Sequential write and read of a text file
Dim i As Long, n As Long, s As String, t As Long
n = Val(Command$): If n = 0 Then n = 1
Open "bench_io.tmp" For Output As #1
For i = 1 To 200000 * n
    Print #1, "line"; i; "of the benchmark file"
Next
Close #1
Open "bench_io.tmp" For Input As #1
Do While Not EOF(1)
    Line Input #1, s
    t = t + Len(s)
Loop
Close #1
Kill "bench_io.tmp"
Print t
