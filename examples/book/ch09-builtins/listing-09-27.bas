Dim score As Integer, day As Integer
score = 72
Print IIf(score >= 50, "pass", "fail")
For day = 1 To 4
    Print Choose(day, "Mon", "Tue", "Wed"); " ";
Next
Print
