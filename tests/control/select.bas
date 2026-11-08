Dim i As Integer, s As String
For i = 0 To 12 Step 3
    Select Case i
        Case 0
            Print i; "zero"
        Case 1 To 4
            Print i; "small"
        Case 5, 6, 7
            Print i; "medium"
        Case Is > 10
            Print i; "big"
        Case Else
            Print i; "other"
    End Select
Next
For Each w In Array("apple", "kiwi", "zebra", "Mango")
    s = w
    Select Case s
        Case "apple", "kiwi": Print s; " fruit"
        Case "a" To "m": Print s; " a-m"
        Case Else: Print s; " else"
    End Select
Next
Select Case True
    Case i > 100: Print "huge"
    Case i > 10: Print "over ten"
End Select
