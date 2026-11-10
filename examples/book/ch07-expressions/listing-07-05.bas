Dim d As Double, x As Double
x = 1E308
On Error Resume Next
d = x * 10
Print "x * 10:"; Err.Number; Err.Description
