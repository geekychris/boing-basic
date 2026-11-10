' an error caught by On Error Resume Next inside For Each over a temporary (Array(), a function's
' Collection, Split) must not end the loop: native freed the collection's temporaries
Function MakeColl() As Collection
    Dim c As New Collection
    c.Add "a": c.Add "b": c.Add "c"
    Set MakeColl = c
End Function
Sub Main()
    On Error Resume Next
    Dim x, n As Long
    For Each x In Array(1, 2, 3)
        Err.Raise 5
        Print x; Err.Number
        Err.Clear
    Next
    For Each x In MakeColl()
        n = 1 / 0
        Print x; Err.Number
        Err.Clear
    Next
    For Each x In Split("p q r", " ")
        Error 9
        Print x & Err.Number
        Err.Clear
    Next
    Print "end"
End Sub
