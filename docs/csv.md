# Csv: comma-separated values

`Csv` reads and writes CSV files, the format spreadsheets, databases and many web services use
to exchange tables. It handles the awkward cases: fields in quotes that contain commas, quotes
or line breaks, other delimiters (`;`, tab), header rows, and Windows, Unix or old Mac line ends.

```basic
Dim table As Csv
Set table = CreateObject("Csv")
table.HasHeader = True
table.Open "RAM:members.csv"
Do While table.ReadRecord()
    Print table.Field("Name"); " ("; table.Field("City"); ")"
Loop
table.Close
```

(Give the variable a name other than `csv`: names aren't case-sensitive, so `Dim csv As Csv`
would hide the type.)

## Reading

| Member | |
|---|---|
| `Open path` | reads a file (into memory) for `ReadRecord`. Error 53 if it isn't there. |
| `LoadText text` | the same, from a String |
| `ReadRecord()` | moves to the next record; False at the end. Empty lines are skipped. |
| `Field(index)` / `Field(name)` | a field of the current record: by position from **0**, or by column name (needs `HasHeader`; any case). The default member, so `table("Name")` works too. A field the record doesn't have is "". |
| `Fields` | the current record as an array of Strings (from 0) |
| `FieldCount` | how many fields the current record has |
| `Headers` | the column names (first row) as an array, with `HasHeader` |
| `ColumnIndex(name)` | the position of a column, -1 if there is none |
| `ReadAll()` | all remaining records as a 2-D array: `a(record, field)`, both from 0; short records are padded with "" |
| `RecordNumber` | the current record's number (1 = the first after the header) |
| `LineNumber` | the line of the file where the current record starts (a quoted field can span lines) |
| `AtEnd` | True when no records are left |
| `ParseLine(text)` | the fields of one record given as text, as an array (no file needed) |

All fields are Strings; convert numbers with `Val`, `CLng`, `CDbl` or `CDate` as needed.

## Writing

| Member | |
|---|---|
| `Create path [, append]` | opens a file for writing (append = True adds to its end) |
| `WriteRecord value, value, ...` | writes one record: each argument a field, or one array whose elements are the fields. Without an open file the record is added to `Text`. |
| `FormatRecord(value, ...)` | the record as a String (no line end), without writing it |
| `Close` | closes the file (and the input of `Open`) |
| `Text` | what `WriteRecord` wrote while no file was open; `Text = ""` empties it |

Numbers, dates and Booleans are written as `CStr` writes them (`3.5`, `True`); Empty and Null as
empty fields. A field is put in quotes only when it has to be (it contains the delimiter, a
quote, a line break, or starts or ends with a space); quotes inside become `""`.

## Settings

| Property | Default | |
|---|---|---|
| `Delimiter` | `,` | the field separator, one character (`";"`, `vbTab`) |
| `Quote` | `"` | the quote character; `""` for none (quotes are then ordinary characters) |
| `HasHeader` | False | the first record holds the column names (`Headers`, `Field(name)`) |
| `TrimFields` | False | remove spaces and tabs around fields when reading |
| `QuoteAll` | False | quote every field when writing |
| `LineEnding` | `vbLf` | the line end written after each record (`vbCrLf` for Windows programs) |

When reading, LF, CR LF and CR line ends are all understood, and a UTF-8 byte order mark at the
start of the file is skipped. Text isn't converted: a UTF-8 file gives UTF-8 Strings.

## Example: export a list

```basic
Dim out As Csv, i As Long
Set out = CreateObject("Csv")
out.Create "RAM:scores.csv"
out.WriteRecord "Player", "Score", "Date"
For i = 1 To n
    out.WriteRecord names(i), scores(i), Format(dates(i), "yyyy-mm-dd")
Next
out.Close
```

## Errors

53 the file isn't there, 57 it can't be read, 75 it can't be created, 61 writing failed (disk
full), 380 a bad `Delimiter`/`Quote` (more than one character, or both the same), 5 `Field` with
a column name that doesn't exist (`Err.Description` names it), 9 a negative field index.

## Tests

`tests/libs/csvtest.bas` (VM, JIT and native in `make test`; on the AmigaOS 4 guest with
`tools/os4guest.py bas tests/libs/csvtest.bas both`).
