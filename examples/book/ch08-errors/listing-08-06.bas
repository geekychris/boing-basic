Dim n As Integer, v As Variant
On Error Resume Next

n = 40000
If Err.Number <> 0 Then Print "n:"; Err.Number; Err.Description
Err.Clear

v = Array(1, 2, 3)
Print v(7)
If Err.Number <> 0 Then Print "v:"; Err.Number; Err.Description
Err.Clear

Print "n is still"; n
