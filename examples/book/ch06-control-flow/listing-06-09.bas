Dim n As Integer
n = 1
Do While n < 100
    n = n * 2
Loop
Print "While:"; n
n = 1
Do Until n >= 100
    n = n * 3
Loop
Print "Until:"; n
n = 500
Do
    n = n + 1
Loop While n < 10
Print "Loop While:"; n
n = 0
Do
    n = n + 1
    If n * n > 50 Then Exit Do
Loop
Print "Exit Do:"; n
