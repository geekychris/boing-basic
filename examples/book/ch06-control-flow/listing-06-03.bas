Sub Describe(ByVal n As Integer)
    Select Case n
        Case 0
            Print n; "zero"
        Case 1, 2, 3
            Print n; "small"
        Case 4 To 9, 11
            Print n; "medium"
        Case Is >= 100
            Print n; "huge"
        Case Is < 0
            Print n; "negative"
        Case Else
            Print n; "large"
    End Select
End Sub

Describe 0: Describe 2: Describe 7: Describe 11: Describe 10: Describe 500: Describe -3
