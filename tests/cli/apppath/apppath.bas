' App.Path is the program's directory under `boing run`, wherever it is started from
Sub Main()
    Dim f As Integer, s As String, sep As String
    sep = "/"
    If Right$(App.Path, 1) = ":" Or Right$(App.Path, 1) = "/" Then sep = ""
    Print "dir "; Mid$(App.Path, InStrRev(App.Path, "/") + 1)
    f = FreeFile
    Open App.Path & sep & "data.txt" For Input As #f
    Line Input #f, s
    Close #f
    Print "data "; s
End Sub
