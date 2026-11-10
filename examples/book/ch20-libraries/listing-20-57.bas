Option Explicit
Dim table As Csv
Set table = CreateObject("Csv")
table.Delimiter = ";"
table.LoadText "1; 2 ;3" & vbLf & "a;""b;c"";d"
table.ReadRecord: Print Join(table.Fields, "|")
table.ReadRecord: Print Join(table.Fields, "|")
table.TrimFields = True
table.LoadText "1; 2 ;3"
table.ReadRecord: Print Join(table.Fields, "|")
