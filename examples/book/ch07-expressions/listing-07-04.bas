Dim big As Long
On Error Resume Next
big = 200 * 200
Print "200 * 200:"; Err.Number; Err.Description
Err.Clear
big = 200& * 200
Print "200& * 200:"; big; Err.Number
big = CLng(200) * 200
Print "CLng(200) * 200:"; big
