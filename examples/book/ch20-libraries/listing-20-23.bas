Option Explicit
Dim s As String
On Error Resume Next
s = Base64Decode("ab$d")
Print Err.Number; Err.Description
Err.Clear
s = Base64Decode("ab=c")
Print Err.Number; Err.Description
Err.Clear
s = UrlDecode("100%")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("ABC")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("AG")
Print Err.Number; Err.Description
