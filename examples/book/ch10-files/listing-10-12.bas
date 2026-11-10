Dim f As Integer, s As String
f = FreeFile
Open App.Path & "/readme.txt" For Input As #f
Line Input #f, s
Close #f
Print s
