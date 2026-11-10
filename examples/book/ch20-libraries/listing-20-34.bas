Option Explicit
Dim d As Date
Print Abs((Now - NowUtc()) * 1440 - UtcOffset()) < 0.01
d = #2026-07-01 12:00:00#
Print LocalToUtc(UtcToLocal(d)) = d
Print TypeName(UtcOffset()), TypeName(UnixTime(Now))
