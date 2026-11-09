Sub Main()
    Dim i As Long
    On Error GoTo cleanup
    Print "running"
    Do
        i = (i + 1) Mod 1000
    Loop
cleanup:
    Print "cleanup"; Err.Number; Err.Description
End Sub
