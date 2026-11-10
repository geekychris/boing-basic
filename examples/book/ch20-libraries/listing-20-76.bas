Option Explicit
Dim z As Zip, s As String
Set z = CreateObject("Zip")
On Error Resume Next
z.Open "no-such.zip"
Print "missing:"; Err.Number: Err.Clear
s = Decompress("this was never compressed")
Print "damaged:"; Err.Number: Err.Clear
z.Create "bad.zip"
z.AddText "../outside.txt", "x"
Print "bad name:"; Err.Number; Err.Description: Err.Clear
z.Level = 10
Print "level:"; Err.Number: Err.Clear
z.Close
Kill "bad.zip"
