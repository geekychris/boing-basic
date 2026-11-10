' datetest.bas - UTC, Unix time and ISO 8601 (deterministic: BOING_UTC_OFFSET isn't relied on
' for the printed values except where set by the test runner)
Option Explicit
Dim d As Date, s As String, off As Long, diff As Double

' Unix time
Print UnixTime(DateSerial(1970, 1, 1)), UnixTime(DateSerial(2000, 1, 1)), UnixTime(DateSerial(2038, 1, 19) + TimeSerial(3, 14, 7))
Print FormatIso8601(FromUnixTime(0)), FormatIso8601(FromUnixTime(1700000000), 0), FormatIso8601(FromUnixTime(-86400))
Print UnixTime(FromUnixTime(1234567890.5))

' formatting
d = DateSerial(1985, 7, 23) + TimeSerial(10, 30, 5)
Print FormatIso8601(d); " "; FormatIso8601(d, 0); " "; FormatIso8601(d, 60); " "; FormatIso8601(d, -330)
Print FormatIso8601(DateSerial(1899, 12, 30)), FormatIso8601(DateSerial(2024, 2, 29) + 0.5)
Print FormatIso8601(FromUnixTime(1.25), 0)

' parsing
Print FormatIso8601(ParseIso8601("2026-11-10"))
Print FormatIso8601(ParseIso8601("2026-11-10T08:45:00"))
Print FormatIso8601(ParseIso8601("2026-11-10T08:45:00Z"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T09:45:00+01:00"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T03:15:00-05:30"), 0)
Print FormatIso8601(ParseIso8601("20261110T084500Z"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10 08:45"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T08:45:00.250Z"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T23:30:00-02:00"), 0)
Print ParseIso8601("1985-07-23T10:30:05") = d
Print Year(ParseIso8601("2026-11-10")), Month(ParseIso8601("2026-11-10")), Day(ParseIso8601("2026-11-10"))

' UTC and the local offset (consistent with each other, whatever the time zone)
off = UtcOffset()
diff = (Now - NowUtc()) * 1440 - off
Print Abs(diff) < 1
Print Abs(UtcToLocal(LocalToUtc(d)) - d) < 0.000001, Abs((d - LocalToUtc(d)) * 1440 - off) < 0.01

' errors: 31401
On Error Resume Next
d = ParseIso8601("2026-13-01")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("yesterday")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10T25:00")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10T08:45:00 extra")
Print Err.Number; Err.Description
