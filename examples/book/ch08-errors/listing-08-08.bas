On Error Resume Next
Dim x As Integer
x = 32767 + 1
Print Err; Erl; Err.Description
Print Error(53); " / "; Error$(62)
Print Error(30000)
