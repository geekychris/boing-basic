Sub LoadAll()
    On Error GoTo skip
    Print "step 1"
    Err.Raise 53
    Print "step 3"
    Exit Sub
skip:
    Print "step 2 failed:"; Err.Number
    Resume Next
End Sub

LoadAll
