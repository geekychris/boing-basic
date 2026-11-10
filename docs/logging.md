# Logger: logging

`Logger` writes timestamped messages to a log file and/or the console, filtered by level: leave
debug messages in the program and switch them on when you need them.

```basic
Dim lg As Logger
Set lg = CreateObject("Logger")
lg.FileName = "PROGDIR:Downloader.log"
lg.Info "started"
lg.Debug "url = " & url              ' only written when Level is logDebug
lg.Error "can't save " & path & ": " & Err.Description
```

`PROGDIR:Downloader.log` then holds lines like:

```
2026-11-10 14:03:21 INFO started
2026-11-10 14:03:25 ERROR can't save RAM:x.lha: Disk full
```

## Writing messages

| Method | Level |
|---|---|
| `Debug message` | `logDebug` (10) |
| `Info message` | `logInfo` (20) |
| `Warning message` | `logWarning` (30) |
| `Error message` | `logError` (40) |
| `Fatal message` | `logFatal` (50) |
| `Log level, message` | any level 0-99 (`Log 35, ...` is shown as WARNING) |

A message is written when its level is at least `Level`.

## Settings

| Property | Default | |
|---|---|---|
| `Level` | `logInfo` | the lowest level written; `logOff` (100) writes nothing |
| `FileName` | "" | the log file; messages are appended. Empty: messages go to the console. |
| `Console` | False | also write to the console (standard error), when there is a file |
| `Pattern` | `{date} {time} {level} {message}` | the line layout; see below |
| `Source` | "" | a name for `{source}` (the module or part of the program) |
| `MaxSize` | 0 | bytes; when the file would grow past it, it is renamed to *name*.old and a new one started (0: no limit) |
| `AutoFlush` | True | write each line to disk at once (a crash or reset keeps the log) |

Pattern fields: `{date}` (2026-11-10), `{time}` (14:03:21), `{ms}` (milliseconds), `{level}`
(DEBUG, INFO, WARNING, ERROR, FATAL), `{source}`, `{message}`, `{line}` (the BASIC line that
logged it). Anything else is copied as it is.

## Other members

| Member | |
|---|---|
| `Count` | messages written so far |
| `LastMessage` | the last line written (without line end) |
| `Flush` | write buffered lines to disk (with `AutoFlush = False`) |
| `Close` | close the file (the next message opens it again) |

## Errors

75 the log file can't be opened, 61 writing failed (disk full), 380 a negative `Level` or
`MaxSize`, or a `Log` level outside 0-99.

## Tests

`tests/libs/logtest.bas` (VM, JIT and native in `make test`; on the AmigaOS 4 guest with
`tools/os4guest.py bas tests/libs/logtest.bas both`): levels, patterns, the file, rotation, the
console.
