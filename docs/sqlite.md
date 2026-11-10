# SQLite: SQL databases

`SQLite` gives a program a full SQL database in a single file: tables, indexes, queries with
joins and sorting, transactions. Use it for anything bigger than a settings file: a record
collection, a game's high scores and save slots, a log you want to search.

SQLite is a standard extension: add one line to the project file,

```
Extension=sqlite
```

and the classes `SQLite`, `SqlRecordset` and `SqlStatement` are there. Only programs that ask for
it contain SQLite (about 900 KB on AmigaOS). To run such a program with `boing run`, the
interpreter must include it: the Boing BASIC kit's interpreter does (it is built with
`STD_EXTS=sqlite`); otherwise build one with `make STD_EXTS=sqlite` (`tools/build-os4.sh
STD_EXTS=sqlite` for AmigaOS) or `boing vm --project P.bbp -o myboing`.

```basic
Dim db As SQLite, rs As SqlRecordset
Set db = CreateObject("SQLite")
db.Open "PROGDIR:records.db"
db.Execute "CREATE TABLE IF NOT EXISTS album (id INTEGER PRIMARY KEY, artist TEXT, title TEXT, year INTEGER)"
db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Kraftwerk", "Computer World", 1981
Set rs = db.Query("SELECT artist, title FROM album WHERE year < ? ORDER BY year", 1990)
Do Until rs.AtEnd
    Print rs("artist"); " - "; rs("title")
    rs.MoveNext
Loop
db.Close
```

Always pass values as `?` parameters instead of pasting them into the SQL text: quotes in the
values can't break the statement (or be used to change it), and dates and numbers keep their type.

## SQLite (the database)

| Member | |
|---|---|
| `Open path [, readOnly]` | opens a database file, creating it if needed (unless readOnly). `":memory:"` is a database in memory that goes away when closed. |
| `Close` | |
| `Execute(sql, values...)` | runs a statement and returns the number of rows it changed. Several statements separated by `;` can be run at once when there are no parameters. |
| `Query(sql, values...)` | runs a SELECT and returns an `SqlRecordset` on its first row |
| `QueryValue(sql, values...)` | the first column of the first row (Empty if there is no row): `n = db.QueryValue("SELECT COUNT(*) FROM album")` |
| `QueryAll(sql, values...)` | every row as a 2-D Variant array `a(row, column)`, both from 0; Empty if there are no rows |
| `Prepare(sql)` | an `SqlStatement` to run many times with different values (faster in loops) |
| `BeginTransaction`, `Commit`, `Rollback` | group changes: all or nothing, and much faster for many inserts |
| `LastInsertId` | the id (`INTEGER PRIMARY KEY`) of the last row inserted |
| `Changes` | rows changed by the last statement |
| `InTransaction`, `IsOpen` | |
| `ErrorCode` | SQLite's (extended) code for the last error, e.g. 2067 for a UNIQUE violation |
| `Timeout` | milliseconds to wait for a database that another program has locked; default 5000 |
| `Version` | SQLite's version (3.34.0 on AmigaOS; the system's on the host) |
| `Available` | True if SQLite can be used in this program |
| `Path` | the file name. On AmigaOS `App.Path & "/x.db"` works for a program at a volume root too (`DH1:/x.db` is taken as `DH1:x.db`, as by the other file functions). |

The values after the SQL fill its `?` parameters in order; they may also be given as one array
(`db.Execute sql, Array(a, b, c)`). The number of values must match the number of `?`s.

## SqlRecordset (the rows of a query)

| Member | |
|---|---|
| `AtEnd` (or `EOF`) | True when there are no (more) rows |
| `MoveNext` | to the next row |
| `Field(column)` | a value of the current row; column is a name (any case) or a position from 0. The default member: `rs("title")`, `rs(0)`. |
| `Fields` | the current row as a Variant array |
| `FieldCount`, `FieldName(i)` | the columns |
| `RowNumber` | 1 for the first row, 0 after the end |
| `Close` | (also when the object goes away) |

`For Each row In db.Query(...)` gives each row as an array: `row(0)`, `row(1)`, ...

## SqlStatement (prepared)

| Member | |
|---|---|
| `Execute(values...)` | runs it with these values; returns the rows changed |
| `Query(values...)` | runs a SELECT; returns an SqlRecordset (close it before using the statement again) |
| `ParameterCount` | how many `?`s it has |
| `Close` | |

```basic
' 10,000 rows in a second instead of a minute: one transaction, one prepared statement
Set ins = db.Prepare("INSERT INTO reading (time, value) VALUES (?, ?)")
db.BeginTransaction
For i = 1 To 10000
    ins.Execute Now, values(i)
Next
db.Commit
```

## Types

| SQLite | Boing BASIC (reading) | written from |
|---|---|---|
| INTEGER | Long (Double beyond ±2147483647) | Byte, Integer, Long, Boolean (True = 1, False = 0), Currency without fraction |
| REAL | Double | Single, Double, Currency |
| TEXT | String | String; Date as `yyyy-mm-dd hh:nn:ss` text (SQLite's date functions read it) |
| BLOB | String (the bytes) | (a String is stored as TEXT; its bytes are kept, NULs included) |
| NULL | Null | Null, Empty |

## Errors

| `Err.Number` | |
|---|---|
| 31601 | SQLite reported an error; `Err.Description` has its message ("UNIQUE constraint failed: player.name", "near "SELEKT": syntax error", "no such table: x"); `ErrorCode` the code |
| 450 | the number of values doesn't match the `?`s |
| 5 / 9 | an unknown column name / a column index out of range |
| 13 | a value that can't be stored (an object, an array inside the values) |

## How it works

The extension is `ext/sqlite` (`sqlite.c` and `sqlite.bbx`, which says `link sqlite3`). On
AmigaOS 4 it links the SDK's SQLite 3.34 (`libsqlite3.a`, the one the Python port uses), so
nothing needs installing on the Amiga; on the host the system's libsqlite3 (macOS has it; on
Linux install libsqlite3-dev to build). Database files are the same on every platform: copy one
between the Amiga and a PC and open it there (the `sqlite3` tool, DB Browser for SQLite,
Python...).

## Tests

`tests/ext/sqlite/sqltest.bbp` (in `make test` through `tests/ext/run.sh`: native, and in an
interpreter built with `STD_EXTS=sqlite`; on the AmigaOS 4 guest the same, natively and with
`build/os4/boing` built with `STD_EXTS=sqlite`).
