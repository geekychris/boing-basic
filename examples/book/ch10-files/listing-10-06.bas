Dim f As Integer, s As String
f = FreeFile
Open "wrap.txt" For Output As #f
Width #f, 10
Print #f, "The quick brown fox jumps over the lazy dog"
Print #f, "ok"
Close #f

Open "wrap.txt" For Input As #f
Do While Not EOF(f)
    Line Input #f, s
    Print "["; s; "]"
Loop
Close #f
Kill "wrap.txt"
