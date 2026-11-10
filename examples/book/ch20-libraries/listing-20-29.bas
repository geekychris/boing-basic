Option Explicit
Dim t As Date
t = FromUnixTime(1700000000)
Print FormatIso8601(t, 0)
Print UnixTime(#1970-01-01#); UnixTime(#2000-01-01#)
Print FormatIso8601(FromUnixTime(1700000000.25), 0)    ' milliseconds are kept
Print Format(t, "dd.mm.yyyy hh:nn:ss")
