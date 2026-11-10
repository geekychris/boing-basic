Option Explicit
Dim nums(1 To 2, 1 To 3) As Integer, r As Integer, c As Integer
For r = 1 To 2
    For c = 1 To 3
        nums(r, c) = r * 10 + c
    Next
Next
Dim n As Variant
For Each n In nums                  ' every element, first index fastest
    Print n;
Next
Print

Dim words() As String, w As Variant
words = Split("red green blue", " ")
For Each w In words
    w = UCase(w)                    ' changes the loop variable, not the array
    Print w; " ";
Next
Print words(0)

Dim total As Long, x As Variant
For Each x In Array(3, 4, 5)
    total = total + x
Next
Print "total"; total
