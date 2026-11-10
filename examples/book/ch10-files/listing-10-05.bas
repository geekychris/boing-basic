Dim f As Integer, s As String, i As Integer

f = FreeFile
Open "log.txt" For Output As #f
Print #f, "first line"
Print #f, "value:"; 42
Close #f

Open "log.txt" For Append As #f
Print #f, "added later"
Close #f

Open "log.txt" For Input As #f
Do While Not EOF(f)
    Line Input #f, s
    i = i + 1
    Print i; "["; s; "]"
Loop
Close #f

Kill "log.txt"
