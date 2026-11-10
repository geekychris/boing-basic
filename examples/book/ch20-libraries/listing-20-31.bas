Option Explicit
Dim d As Date
d = #2026-11-10 08:45:00#
Print FormatIso8601(d)
Print FormatIso8601(d, 0)
Print FormatIso8601(d, 60)
Print FormatIso8601(d, -330)
