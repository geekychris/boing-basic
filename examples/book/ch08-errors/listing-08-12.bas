Sub Main()
    Dim counter As Long
    On Error GoTo cleanup
    Print "running: press Ctrl-C to stop"
    Do
        counter = counter + 1
    Loop
cleanup:
    If Err.Number = 18 Then Print "stopped by the user after"; counter; "turns"
    ' close windows, free memory, delete temporary files here
End Sub
