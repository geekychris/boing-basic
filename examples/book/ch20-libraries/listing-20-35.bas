Option Explicit
Dim d As Date
On Error Resume Next
d = ParseIso8601("10.11.2026")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-13-01")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10T25:00")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10 08:45 CET")
Print Err.Number; Err.Description
