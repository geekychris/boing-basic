Dim f As Integer, s As String, n As Long, x As Double, name As String, i As Integer
f = FreeFile
Open "test.txt" For Output As #f
Print #f, "line one"
Print #f, "value:"; 42
Write #f, "quoted, text", 3.5, True
Close #f
Open "test.txt" For Append As #1
Print #1, "appended"
Close #1
Open "test.txt" For Input As #1
Do While Not EOF(1)
    Line Input #1, s
    Print "["; s; "]"
Loop
Close #1
Open "data.csv" For Output As #2
Write #2, "Ada", 36
Write #2, "Bob", 41
Close #2
Open "data.csv" For Input As #2
Do Until EOF(2)
    Input #2, name, n
    Print name; n
Loop
Close
Print FileLen("data.csv")
Open "data.csv" For Input As #3
Print LOF(3)
s = Input(4, #3)
Print s
Close #3
Kill "data.csv"
Print Dir("data.csv") = ""
Print Dir("test.txt")
Name "test.txt" As "renamed.txt"
Print Dir("renamed.txt")
Kill "renamed.txt"
MkDir "subdir"
Open "subdir/a.txt" For Output As #1: Print #1, "x": Close #1
Print Dir("subdir/*.txt")
Kill "subdir/a.txt"
RmDir "subdir"
On Error Resume Next
Open "missing.txt" For Input As #1
Print "err"; Err.Number
