Public Id As Long
Private Sub Class_Initialize()
    Static n As Long
    n = n + 1
    Id = n
    Print "init"; Id
End Sub
Private Sub Class_Terminate()
    Print "term"; Id
End Sub
