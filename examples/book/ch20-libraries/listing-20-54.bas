Option Explicit
Dim table As Csv, f As Variant
Set table = CreateObject("Csv")
f = table.ParseLine("42,""Smith, John"",""said """"hi""""""")
Print UBound(f) + 1; " fields: "; Join(f, " | ")
