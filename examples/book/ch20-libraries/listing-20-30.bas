Option Explicit
Print FormatIso8601(FromUnixTime(-86400), 0)
Print FormatIso8601(FromUnixTime(2147483647), 0)          ' the largest Long
Print UnixTime(ParseIso8601("2038-01-19T03:14:08Z"))      ' one second later
Print FormatIso8601(FromUnixTime(1731228300123# / 1000), 0)  ' milliseconds from a service
