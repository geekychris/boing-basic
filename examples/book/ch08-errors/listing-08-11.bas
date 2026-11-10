Sub Level3()
    Print "level 3 starts"
    Err.Raise 1001, "Level3", "deep trouble"
    Print "level 3 ends"                  ' never runs
End Sub

Sub Level2()
    Level3
    Print "level 2 ends"                  ' never runs
End Sub

Sub Level1()
    On Error GoTo h
    Level2
    Print "level 1 ends"
    Exit Sub
h:
    Print "level 1 caught"; Err.Number; Err.Source; ": "; Err.Description
End Sub

Level1
