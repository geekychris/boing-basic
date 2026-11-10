Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "(\d{4})-(\d\d)-(\d\d)"
re.Global = True
Print re.Replace("from 2026-11-10 to 2026-12-24", "$3.$2.$1")
Print re.Test("no dates here"); re.Test("due 2027-01-31")
