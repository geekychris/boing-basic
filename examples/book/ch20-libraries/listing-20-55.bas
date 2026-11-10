Option Explicit
Dim out As Csv
Set out = CreateObject("Csv")
Print out.FormatRecord("plain", "with,comma", "with ""quote""", " space", 3.5, True, Null)
out.WriteRecord "id", "text"
out.WriteRecord 1, "a, b"
out.WriteRecord Array(2, "c")
Print out.Text;
out.QuoteAll = True
Print out.FormatRecord(Array("a", 1, Empty))
