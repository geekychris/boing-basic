Sub Main()
    Dim tries As Integer
    On Error GoTo h
again:
    tries = tries + 1
    Err.Raise 5
    Exit Sub
h:
    Print "try"; tries; Err.Number
    On Error GoTo -1
    If tries < 3 Then GoTo again
End Sub
