Dim i As Integer
For i = 1 To 5
    If i = 3 Then GoTo skip
    Print i;
skip:
Next
Print
i = 0
again:
i = i + 1
If i < 3 Then GoTo again
Print "i ="; i
