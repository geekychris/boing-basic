Dim i As Integer, s As String, ok As Boolean, d As Double
i = 2.5: Print i;
i = 3.5: Print i;
i = "42": Print i
s = 3.25: Print s
ok = "TRUE": Print ok
d = " 1.5e3 ": Print d
On Error Resume Next
i = "abc"
Print "Error"; Err.Number; Err.Description
