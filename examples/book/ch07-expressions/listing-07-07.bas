Dim n As Integer
n = 5
Print "n is " & n; " | "; "x" & 0.5; " | "; 1 & 2
Print "5" + "5"; " | "; "5" + 5; " | "; "5" & 5
On Error Resume Next
Print "a" + 1
Print "Error"; Err.Number; Err.Description
