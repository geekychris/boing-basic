Dim i As Integer, j As Long, k As Double, n As Integer
For i = 10 To 1 Step -3
    Print i;
Next
Print
For j = 1 To 3
    For i = 1 To 3
        If i = 2 Then Exit For
        Print j * 10 + i;
    Next i
Next j
Print
For k = 0 To 1 Step 0.25
    Print k;
Next
Print
Print "after:"; i; k
n = 0
Do While n < 3
    n = n + 1
Loop
Print n
Do
    n = n - 1
Loop Until n = 0
Print n
Do Until n = 5
    n = n + 1
    If n = 4 Then Exit Do
Loop
Print n
Do
    n = n + 1
Loop While n < 10
Print n
While n > 7
    n = n - 1
Wend
Print n
For i = 1 To 0
    Print "never"
Next
For i = 1 To 3: Print i;: Next: Print
Dim v As Variant
For v = 1 To 2.5 Step 0.5
    Print v;
Next
Print
