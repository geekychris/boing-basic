Dim x As Integer
For x = 1 To 4
    If x = 1 Then
        Print "one"
    ElseIf x = 2 Then
        Print "two"
    Else
        Print "many"; x
    End If
Next x
If x > 3 Then Print "x>3" Else Print "x<=3"
If x Then Print "nonzero"
If 0 Then Print "never" Else Print "zero is false"
If x > 1 And x < 10 Then Print "range"
If Not (x = 5) Then Print "not five" Else Print "five"
Dim s As String
s = "abc"
If s = "abc" Then Print "equal": Print "second"
If s < "abd" Then Print "less"
If s Like "a*" Then Print "like"
