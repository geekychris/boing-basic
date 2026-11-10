Option Explicit
Dim table As Csv, s As String
Set table = CreateObject("Csv")
On Error Resume Next
table.Delimiter = ",,"
Print "delimiter:"; Err.Number: Err.Clear
table.Open "no such file.csv"
Print "open:"; Err.Number: Err.Clear
table.HasHeader = True
table.LoadText "a,b" & vbLf & "1,2"
table.ReadRecord
s = table.Field("c")
Print "column:"; Err.Number; " "; Err.Description: Err.Clear
Print "missing field: ["; table.Field(5); "]"; Err.Number
