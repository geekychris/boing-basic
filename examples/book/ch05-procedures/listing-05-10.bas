Dim level As Integer

Sub Show()
    Dim level As Integer          ' hides the module's level
    level = 99
    Print "inside"; level
End Sub

Function NextId() As Long
    Static lastId As Long
    lastId = lastId + 1
    NextId = lastId
End Function

Static Function RunningTotal(ByVal x As Long) As Long
    Dim sum As Long               ' static, because the whole Function is Static
    sum = sum + x
    RunningTotal = sum
End Function

level = 1
Show
Print "outside"; level
Print NextId(); NextId(); NextId()
Print RunningTotal(5); RunningTotal(10)
