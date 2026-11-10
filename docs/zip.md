# Compression and Zip archives

Boing BASIC can compress data (gzip, zlib, raw deflate) and read and write ZIP archives, the
same on AmigaOS 4 and the host.

```basic
packed = Compress(text)                 ' gzip
Print Len(text); " -> "; Len(packed)
original = Decompress(packed)

Dim z As Zip
Set z = CreateObject("Zip")
z.Open "RAM:download.zip"
z.ExtractAll "RAM:download/"
z.Close
```

## Functions

| Function | |
|---|---|
| `Compress(data [, format [, level]])` | data compressed. format: `zipGzip` (default; a `.gz` file's contents), `zipZlib`, `zipDeflate` (raw, no header). level: 0 (store) to 9 (smallest); default 6. |
| `Decompress(data [, format])` | the original data. format: `zipAuto` (default: gzip or zlib, recognised by their headers), `zipGzip`, `zipZlib`, `zipDeflate` |
| `CRC32(data)` | the CRC-32 of data (as in ZIP, gzip and PNG), a Long |

Data is any String, text or binary. `Decompress` raises error 31501 if the data isn't what the
format says or is damaged.

```basic
' write a .gz file that gzip/gunzip can read
packed = Compress(report)
Open "RAM:report.txt.gz" For Binary As #1
Put #1, 1, packed
Close #1
```

## The Zip class

### Reading

| Member | |
|---|---|
| `Open path` | opens an archive and reads its directory (error 53 if missing, 31501 if it isn't a ZIP file) |
| `Count` | the number of entries |
| `Name(i)` | the name of entry i (from 0), with `/` between folders; folders end in `/` |
| `Size(i)`, `CompressedSize(i)` | sizes in bytes |
| `IsFolder(i)` | True for a folder entry |
| `FileDate(i)` | the date and time stored with the entry (a Date) |
| `IndexOf(name)` | the index of an entry (any case), -1 if there's none |
| `Read(entry)` | the contents of an entry as a String; entry is an index or a name |
| `Extract entry, path` | writes one entry to a file (creating its folders) |
| `ExtractAll(folder)` | writes every entry below folder, with their folders; returns how many. Entries with absolute names or `..` are skipped, so an archive can't write outside the folder. |
| `Close` | |

Every entry's size and CRC-32 are checked when it is read (error 31501 "... is damaged").

### Writing

| Member | |
|---|---|
| `Create path` | starts a new archive (replacing the file) |
| `AddText name, data` | an entry from a String |
| `AddFile path [, name]` | a file; name in the archive defaults to the file's name |
| `AddFolder path [, name]` | a folder with everything in it; name is the folder's name in the archive (default: its contents go to the top) |
| `Level` | 0 (store) to 9; default 6. An entry that wouldn't get smaller is stored. |
| `Close` | writes the archive's directory: an archive is only complete after `Close` (or when the object goes away) |

```basic
Dim z As Zip
Set z = CreateObject("Zip")
z.Create "RAM:backup.zip"
z.AddFolder "PROGDIR:saves", "saves"
z.AddText "info.txt", "Backup of " & Now
z.Close
```

Archives written are standard ZIP files (stored and deflated entries) that `unzip`, Windows,
macOS and AmigaOS archivers read.

## Not supported

ZIP64 (archives or entries over 4 GB), encrypted entries, compression methods other than store
and deflate (e.g. bzip2 or LZMA entries), multi-disk archives, file comments and Amiga protection
bits.

## Errors

| `Err.Number` | |
|---|---|
| 31501 | not a ZIP file, a damaged archive or entry, corrupt compressed data |
| 31502 | no compression library (`z.library` missing on AmigaOS; no zlib on the host) |
| 53 / 75 / 61 | file not found / can't create / write failed |
| 5 | Add* on an archive opened for reading, a bad entry name (absolute or with `..`), a bad format |
| 9 | an entry index out of range |

## How it works

On AmigaOS the deflate work is done by `z.library` (zlib 1.2.11 as a shared library, part of
AmigaOS 4.1 since Update 1; opened on first use). On the host the system's zlib is loaded when
first needed (`libz`, present on macOS and practically every Linux), so programs built with
`boing build` don't link against it. The ZIP format itself (directories, headers, CRC checks) is
Boing BASIC's own code.

## Tests

`tests/libs/ziptest.bas` with `tests/libs/fixture.zip` (an archive made by Info-ZIP's zip): VM,
JIT and native in `make test`, on the AmigaOS 4 guest with
`tools/os4-libtest.py tests/libs/ziptest.bas both tests/libs/fixture.zip`. Archives written by
Boing BASIC pass `unzip -t`; `Compress` output passes `gzip -d`, and `gzip` output decompresses.
