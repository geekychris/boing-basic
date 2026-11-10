Dim i As Integer, b As Byte
i = 2.5: Print i;
i = 3.5: Print i;
i = -2.5: Print i
On Error Resume Next
i = 32767
i = i + 1
Print "Error"; Err.Number; Err.Description
