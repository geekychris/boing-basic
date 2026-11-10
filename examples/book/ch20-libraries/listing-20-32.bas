Option Explicit
Print FormatIso8601(ParseIso8601("2026-11-10"))
Print FormatIso8601(ParseIso8601("2026-11-10T08:45"))
Print FormatIso8601(ParseIso8601("20261110T084500Z"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10 08:45:00+01:00"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T00:30:00+01:00"), 0)   ' the day before in UTC
Print FormatIso8601(ParseIso8601("2026-11-10T08:45:00,5"))
