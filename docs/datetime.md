# Dates and times: UTC, Unix time, ISO 8601

Boing BASIC's `Date` values (`Now`, `DateSerial`, ...) are local time. Web APIs, files from other
computers and log formats use UTC and ISO 8601 text; these functions convert between them.

| Function | |
|---|---|
| `NowUtc()` | the current date and time in UTC |
| `UtcOffset()` | minutes local time is ahead of UTC: +60 in Central Europe in winter, -300 in New York |
| `LocalToUtc(d)`, `UtcToLocal(d)` | convert with the current offset |
| `UnixTime(d)` | seconds since 1970-01-01 00:00 UTC of a UTC Date (a Double; milliseconds kept) |
| `FromUnixTime(seconds)` | the UTC Date of a Unix time |
| `FormatIso8601(d [, offset])` | `"2026-11-10T08:45:00"`; milliseconds are added when there are any; `offset` 0 adds `Z`, other values (minutes ahead of UTC) add `+01:00` / `-05:30`; without it no zone is written |
| `ParseIso8601(s)` | reads `2026-11-10`, `2026-11-10T08:45`, `2026-11-10T08:45:00.250Z`, `20261110T084500Z`, `2026-11-10 08:45:00+01:00`...; with a zone (`Z` or an offset) the result is UTC, without it the Date is as written. Dates that don't exist (`2026-02-31`, 29 February outside leap years) and times past `24:00:00` raise error 31401; `24:00:00` is midnight at the end of the day |

```basic
' a timestamp for a JSON API
body = "{""at"": """ & FormatIso8601(NowUtc(), 0) & """}"

' a time from an API, shown in local time
t = UtcToLocal(ParseIso8601(item("created_at")))     ' "2026-11-10T08:45:00Z"
Print Format(t, "dd.mm.yyyy hh:nn")

' Unix time stamps
Print FormatIso8601(FromUnixTime(1700000000), 0)    ' 2023-11-14T22:13:20Z
Print UnixTime(NowUtc())
```

Bad ISO 8601 text raises error **31401** saying what was wrong.

## Where the offset comes from

- **AmigaOS:** the Amiga's clock runs on local time; the offset is the time zone set in Locale
  preferences (locale.library). If the clock or the time zone setting is off, so is UTC.
- **Host:** the C library's time zone.
- **Override:** the environment variable `BOING_UTC_OFFSET` (minutes ahead of UTC) wins on any
  system, e.g. `setenv BOING_UTC_OFFSET 60`. Useful on emulators whose clock runs on UTC while
  the time zone setting says otherwise (`setenv BOING_UTC_OFFSET 0` there).

## Tests

`tests/lib/datetest.bas` (in `make test`, VM and native): Unix time (1970, 2000, the 2038 limit,
negative values, fractions), formatting with and without zones and milliseconds, parsing of all
the forms above with conversions across midnight, consistency of `Now`, `NowUtc` and
`UtcOffset`, and the errors. On the AmigaOS 4 guest: identical output in the VM and native.
