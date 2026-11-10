Dim s As String
s = "1234567890"
Mid(s, 3, 2) = "AB"
Print s
Mid(s, 9) = "XYZ"           ' only 2 characters fit before the end
Print s
Mid(s, 1) = "--"
Print s
