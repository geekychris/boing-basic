' Run from a volume root (RAM:): App.Path is "RAM:", and App.Path & "/name" ("RAM:/name") must
' reach the file beside the program, in Open, FileLen, Dir, Kill, FileCopy, Name, MkDir/RmDir
Sub Main()
    Dim f As Integer, s As String, p As String
    p = App.Path & "/"
    Print "app path "; App.Path
    f = FreeFile
    Open p & "rp_test.txt" For Output As #f
    Print #f, "beside the program"
    Close #f
    Open p & "rp_test.txt" For Input As #f
    Line Input #f, s
    Close #f
    Print "read "; s
    Print "len"; FileLen(p & "rp_test.txt")
    Print "dir "; Dir$(p & "rp_test.txt")
    FileCopy p & "rp_test.txt", p & "rp_copy.txt"
    Name p & "rp_copy.txt" As p & "rp_moved.txt"
    Print "moved "; Dir$(p & "rp_moved.txt")
    Kill p & "rp_moved.txt"
    Kill p & "rp_test.txt"
    MkDir p & "rp_dir"
    Print "mkdir "; Dir$(p & "rp_dir", vbDirectory)
    RmDir p & "rp_dir"
    Print "gone "; Dir$(p & "rp_test.txt") = ""
End Sub
