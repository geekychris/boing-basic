' labels inside Select Case branches (and nested in If / For inside them), GoTo and duplicates
Sub Main()
    Dim i As Long, k As Long
    For k = 1 To 3
        Select Case k
            Case 1
                GoTo one
                Print "no"
one:
                Print "case one"
            Case 2, 3
                For i = 1 To 3
                    If i = 2 Then GoTo skip
                    Print "i"; i;
skip:
                Next i
                Print
            Case Else
                Print "else"
        End Select
    Next k
    If k > 0 Then
        GoTo inif
        Print "no"
inif:
        Print "in if"
    End If
End Sub
