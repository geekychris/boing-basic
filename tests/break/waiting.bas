Sub Main()
    On Error GoTo cleanup
    Print "running"
    Do
        Sleep 50
    Loop
cleanup:
    Print "cleanup"; Err.Number; Err.Description
End Sub
